import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import 'package:flashcard_app/models/question.dart';
import 'package:flashcard_app/models/question_bank.dart';
import 'package:flashcard_app/services/ai_service.dart';
import 'package:flashcard_app/services/database_service.dart';
import 'package:flashcard_app/services/pdf_import_service.dart';
import 'package:flashcard_app/utils/question_image_tokens.dart';
import 'package:flashcard_app/widgets/quiz/quiz_question_card.dart';

/// 真机端到端：PDF 抽图 → 图文归属 → 随题渲染 → 入库/备份往返。
///
/// 硬性约束「题目带图必须显示出来、作为题目的一部分」在这里走真实链路：
/// pdfrx 光栅化、图区裁切、`{{img:N}}` 归属、Image.memory 内联渲染都是真代码。
/// AI 结构化一步用「按题号切块」模拟（真实链路里 AI 只做结构化，占位符随文本走，
/// 契约由 test/question_image_tokens_test.dart 钉住）。
///
/// 样张：tool/make_sample_pdf.py 生成后临时放入 assets/（验证后删除，不入库）。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// 样张落盘到应用临时目录（pdfrx 走文件路径）
  Future<File> stageSample() async {
    final data = await rootBundle.load('assets/e2e_sample.pdf');
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/e2e_sample.pdf');
    f.writeAsBytesSync(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    return f;
  }

  /// 模拟 AI 的题号切块（与 AIService.splitTextIntoQuestionChunks 同口径：
  /// 首题之前的文档头并入第一块；AI 只做结构化，占位符随文本走）
  List<Question> fakeAiParse(String rawText) {
    final blocks = <String>[];
    final cur = StringBuffer();
    var seenFirst = false;
    for (final line in rawText.split('\n')) {
      if (AIService.isQuestionStart(line)) {
        if (cur.isNotEmpty && seenFirst) {
          blocks.add(cur.toString().trim());
          cur.clear();
        }
        seenFirst = true;
      }
      cur.writeln(line);
    }
    if (cur.isNotEmpty) blocks.add(cur.toString().trim());

    final now = DateTime.now().toIso8601String();
    return [
      for (final c in blocks)
        Question(bankId: 0, title: c, correctAnswer: 'A', createdAt: now),
    ];
  }

  test('抽取：文本带占位符 + 图片池齐（含扫描页整页图）', () async {
    final r = await PdfImportService.extract((await stageSample()).path);
    // 诊断输出：rawText 与题号行（供宿主日志核对图文交织与切块口径）
    print('=== RAWTEXT START ===');
    for (final line in r.rawText.split('\n')) {
      final mark = AIService.isQuestionStart(line) ? 'MATCH>> ' : '        ';
      print('$mark[$line]');
    }
    print('=== RAWTEXT END (pool=${r.imagePool.length}) ===');
    // 诊断：把每张图落盘 + 打印 anchor（页码:y:期望题序），供 run-as 取回肉眼核对
    r.imagePool.forEach((k, v) {
      File('/data/data/com.flashcard.app/files/fig_${k}_$k.jpg')
          .writeAsBytesSync(v.content);
      print('POOL $k anchor=${v.anchor} ${v.width}x${v.height}');
    });
    expect(r.charCount, greaterThan(100), reason: '有文字层，不是扫描件');
    expect(r.imagePool.length, 6,
        reason: 'Q1 心电 + Q2 病理(前置) + Q3 矢量/病理 + Q5 解析图 + 扫描页');
    expect(r.rawText, contains('{{img:'));
  });

  test('物化：图按题归属（「下图所示」/「上图所示」两版式）', () async {
    final r = await PdfImportService.extract((await stageSample()).path);
    final m = materializeQuestionImages(
        questions: fakeAiParse(r.rawText), pool: r.imagePool);
    expect(m.questions.length, 5);
    expect(m.orphans, isEmpty, reason: '占位符都在文本里，不该有孤儿图');
    expect(m.questions[0].images.length, 1,
        reason: 'Q1 下图所示：题干与选项之间的图');
    expect(m.questions[1].images.length, 1,
        reason: 'Q2 上图所示：前置图挂到题前');
    expect(m.questions[2].images.length, 2,
        reason: 'Q3 一题两图（矢量线图+位图）');
    expect(m.questions[3].images, isEmpty,
        reason: 'Q4 跨页题无图（大留白不该误判成图）');
    expect(m.questions[4].images.length, 2,
        reason: 'Q5 解析图 + 扫描页整页图');
  });

  testWidgets('渲染：图片作为题目的一部分内联显示', (tester) async {
    final r = await PdfImportService.extract((await stageSample()).path);
    final m = materializeQuestionImages(
        questions: fakeAiParse(r.rawText), pool: r.imagePool);
    final q = m.questions[0];
    expect(q.images, hasLength(1));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child:
                QuizQuestionCard(question: q, attempts: 1, accuracyPercent: 100),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // 硬性约束：图渲染在题目内容里（Image.memory），不是外挂占位/文字
    expect(find.byType(Image), findsOneWidget);
    final img = tester.widget<Image>(find.byType(Image));
    expect(img.image, isA<MemoryImage>());

    // 保持画面 25 秒，供宿主机 adb screencap 取证
    await Future<void>.delayed(const Duration(seconds: 25));
  });

  test('入库/备份往返：图随题持久化', () async {
    final db = DatabaseService.instance;
    final r = await PdfImportService.extract((await stageSample()).path);
    final m = materializeQuestionImages(
        questions: fakeAiParse(r.rawText), pool: r.imagePool);

    final bankId = await db.insertBank(QuestionBank(
        name: 'E2E样张-${DateTime.now().millisecondsSinceEpoch}',
        createdAt: DateTime.now().toIso8601String()));
    final ids = await db.insertQuestions([
      for (final q in m.questions) q.copyWith(bankId: bankId),
    ]);
    final byId = await db.getImagesForQuestions(ids);
    final total = byId.values.fold<int>(0, (n, l) => n + l.length);
    expect(total, 6, reason: '六张图全部随题入库');

    // 备份 → 校验（v12 闸门放行）→ 整库拷贝图随行走
    final dir = await getTemporaryDirectory();
    final dest = '${dir.path}/e2e_backup.db';
    expect(await db.exportBackup(dest), isNull);
    expect(await db.validateBackupFile(dest), isNull);

    await db.deleteBank(bankId);
    File(dest).deleteSync();
  });
}
