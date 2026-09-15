import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';
import 'package:flashcard_app/models/answer_record.dart';
import 'package:flashcard_app/models/question.dart';
import 'package:flashcard_app/models/question_bank.dart';
import 'package:flashcard_app/services/app_state.dart';
import 'package:flashcard_app/services/database_service.dart';
import 'package:flashcard_app/services/export_storage.dart';
import 'package:flashcard_app/services/docx_export_service.dart';

/// 「导出成 Word 打印稿」的回归测试。
///
/// 这一层必须测的原因：docx 是个 zip 包，肉眼看不见内部，坏了只会在用户
/// 打开 Word 的那一刻才暴露（「文件已损坏」），而且坏法多种多样——
/// XML 没转义、`w:pPr` 位置不对、分页符放错地方，都属于「生成成功但打不开」。
/// 所以这里直接解包 + 解析，把 Word 会检查的东西逐条钉住。
void main() {
  late Directory tmp;

  setUp(() async {
    await DatabaseService.instance.close();
    tmp = Directory.systemTemp.createTempSync('mj_docx_');
    DatabaseService.overrideDbPath = '${tmp.path}/flashcard.db';
    // 导出目录注入到临时目录：既不让测试往用户的「文档/猫卷导出」里写，
    // 也让「导出落到哪个文件夹」这件事可断言（path_provider 在测试里没有实现）
    ExportStorage.overrideDirForTest = '${tmp.path}/猫卷导出';
  });

  tearDown(() async {
    await DatabaseService.instance.close();
    DatabaseService.overrideDbPath = null;
    ExportStorage.overrideDirForTest = null;
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Question q(
    String title, {
    List<String> options = const ['选项一', '选项二'],
    String answer = 'A',
    String? analysis,
    String type = 'single_choice',
  }) =>
      Question(
        bankId: 1,
        title: title,
        options: options,
        correctAnswer: answer,
        analysis: analysis,
        questionType: type,
        createdAt: '2026-09-15T00:00:00.000',
      );

  /// 解包并解析出 word/document.xml
  XmlDocument docxOf(List<int> bytes) {
    final zip = ZipDecoder().decodeBytes(bytes);
    final names = zip.files.map((f) => f.name).toList();
    final entry = zip.files.firstWhere((f) => f.name == 'word/document.xml',
        orElse: () => throw StateError('缺 word/document.xml，包内为 $names'));
    return XmlDocument.parse(utf8.decode(entry.content as List<int>));
  }

  /// 段落文本列表（w:p 里的 w:t 拼起来，空段落是空串）
  List<String> paraTexts(XmlDocument doc) => doc
      .findAllElements('w:p')
      .map((p) => p.findAllElements('w:t').map((t) => t.innerText).join())
      .toList();

  group('docx 结构：Word 会不会报「文件已损坏」', () {
    test('包内三件套齐全，document.xml 可解析', () {
      final bytes = DocxExportService.build(
        questions: [q('测试题一')],
        placement: DocxAnswerPlacement.underQuestion,
      );
      final zip = ZipDecoder().decodeBytes(bytes);
      expect(zip.files.map((f) => f.name).toSet(),
          {'[Content_Types].xml', '_rels/.rels', 'word/document.xml'});

      final doc = docxOf(bytes);
      expect(doc.rootElement.name.qualified, 'w:document');
      final body = doc.findAllElements('w:body').single;
      // 页面设置必须挂在 body 末尾
      expect(body.childElements.last.name.qualified, 'w:sectPr');
      expect(doc.findAllElements('w:pgSz').single.getAttribute('w:w'), '11906');
    });

    test('每个段落的第一个子元素都是 w:pPr（顺序错了 Word 直接报损坏）', () {
      final doc = docxOf(DocxExportService.build(
        questions: [q('甲'), q('乙', options: const [])],
        placement: DocxAnswerPlacement.lastPage,
      ));
      for (final p in doc.findAllElements('w:p')) {
        final kids = p.childElements.toList();
        if (kids.isNotEmpty) {
          expect(kids.first.name.qualified, 'w:pPr');
        }
      }
    });

    test('题干里的 & < > " 会被转义，解析回来一字不差', () {
      const tricky = '血压 & <心率> "正常" 吗？';
      final doc = docxOf(DocxExportService.build(
        questions: [q(tricky, analysis: '解析里也有 & 符号')],
        placement: DocxAnswerPlacement.underQuestion,
      ));
      final texts = paraTexts(doc);
      expect(texts.any((t) => t.contains(tricky)), isTrue,
          reason: '未转义的 & 会让 Word 报文件损坏');
      expect(texts.any((t) => t.contains('解析里也有 & 符号')), isTrue);
    });
  });

  group('两种答案排布', () {
    final questions = [q('第一题'), q('第二题'), q('第三题')];

    test('答案在题目下方：每题答案紧跟该题、且在下一次题目之前', () {
      final texts = paraTexts(docxOf(DocxExportService.build(
        questions: questions,
        placement: DocxAnswerPlacement.underQuestion,
      )));
      expect(texts.where((t) => t.startsWith('答案：')).toList(),
          ['答案：A', '答案：A', '答案：A']);

      // 逐题定位：第 i 题的答案必须落在第 i 题与第 i+1 题之间
      final qIdx = [
        for (var i = 1; i <= 3; i++) texts.indexWhere((t) => t.startsWith('$i. ')),
      ];
      expect(qIdx.every((i) => i >= 0), isTrue, reason: '三道题都应出现');
      var searchFrom = 0;
      for (var i = 0; i < 3; i++) {
        final ai = texts.indexWhere((t) => t == '答案：A', searchFrom);
        expect(ai, greaterThan(qIdx[i]), reason: '第 ${i + 1} 题的答案要排在题干之后');
        if (i + 1 < 3) {
          expect(ai, lessThan(qIdx[i + 1]),
              reason: '第 ${i + 1} 题的答案不能跑到下一题后面');
        }
        searchFrom = ai + 1;
      }
      // 题下模式没有分页符、也没有独立的答案区标题
      expect(texts.contains('答案'), isFalse);
    });

    test('答案在最后一页：题目区不含答案，答案按题号集中在分页之后', () {
      final bytes = DocxExportService.build(
        questions: questions,
        placement: DocxAnswerPlacement.lastPage,
      );
      final doc = docxOf(bytes);
      final texts = paraTexts(doc);

      // 末页模式的答案行也带题号（3. 答案：A），定位题目时要把它排除
      final lastQuestion = texts.lastIndexWhere(
          (t) => t.startsWith('3. ') && !t.contains('答案：'));
      final answersHeading = texts.indexOf('答案');
      expect(answersHeading, greaterThan(lastQuestion),
          reason: '答案区必须在全部题目之后');
      expect(
        texts.take(answersHeading).any((t) => t.startsWith('答案：')),
        isFalse,
        reason: '题目区里不该出现答案',
      );
      expect(
        texts
            .skip(answersHeading)
            .where((t) => t.contains('答案：'))
            .toList(),
        ['1. 答案：A', '2. 答案：A', '3. 答案：A'],
        reason: '末页答案要按题号顺序、每题各一条',
      );
      // 带题号，便于对答案
      expect(texts.skip(answersHeading).where((t) => t.startsWith('1. 答案：')),
          hasLength(1));

      final brs = doc.findAllElements('w:br').toList();
      expect(brs, hasLength(1));
      expect(brs.single.getAttribute('w:type'), 'page',
          reason: '没有分页符，答案就不会落在「最后一页」');
    });

    test('两种模式的知识内容完全一致，只有答案位置与留白不同', () {
      // 只比「题干 + 选项」行：卷头在末页模式本来就会多一句「答案见最后一页」
      final content = RegExp(r'^(\d+\. |[A-Z]\. )');
      List<String> questionArea(DocxAnswerPlacement p) => paraTexts(docxOf(
              DocxExportService.build(questions: questions, placement: p)))
          .where((t) => content.hasMatch(t) && !t.contains('答案：'))
          .toList();

      final under = questionArea(DocxAnswerPlacement.underQuestion);
      final last = questionArea(DocxAnswerPlacement.lastPage);
      // 先确认真的筛出了题目行：否则两边都是空列表，这条断言等于没测
      expect(under, contains('1. 第一题'));
      expect(under, contains('A. 选项一'));
      expect(under, hasLength(9)); // 3 题 ×（1 题干 + 2 选项）
      expect(last, under);
    });
  });

  group('内容细节', () {
    test('选项带 A./B. 前缀，非单选才标题型', () {
      final texts = paraTexts(docxOf(DocxExportService.build(
        questions: [
          q('单选题', options: const ['甲', '乙']),
          q('多选题', options: const ['丙', '丁'], answer: 'A,C', type: 'multi_choice'),
        ],
        placement: DocxAnswerPlacement.underQuestion,
      )));
      expect(texts, contains('A. 甲'));
      expect(texts, contains('B. 乙'));
      expect(texts.any((t) => t == '1. 单选题'), isTrue);
      expect(texts.any((t) => t == '2. 【多选】多选题'), isTrue,
          reason: '多选不标题型，学生可能只选一个');
      expect(texts, contains('答案：A,C'));
    });

    test('简答题（无选项）不产出选项行', () {
      final texts = paraTexts(docxOf(DocxExportService.build(
        questions: [
          q('简述休克的分类', options: const [], answer: '低血容量性、心源性…', type: 'jian_da')
        ],
        placement: DocxAnswerPlacement.underQuestion,
      )));
      expect(texts.any((t) => t.startsWith('A. ')), isFalse);
      expect(texts.any((t) => t.contains('简答')), isTrue);
      expect(texts.any((t) => t.startsWith('答案：低血容量性')), isTrue);
    });

    test('多行解析按行拆成多个段落', () {
      final texts = paraTexts(docxOf(DocxExportService.build(
        questions: [q('有解析的题', analysis: '第一步\n第二步\n第三步')],
        placement: DocxAnswerPlacement.underQuestion,
      )));
      expect(texts, contains('解析：'));
      for (final line in ['第一步', '第二步', '第三步']) {
        expect(texts, contains(line));
      }
    });

    test('卷头写题数、日期与范围说明', () {
      final texts = paraTexts(docxOf(DocxExportService.build(
        questions: [q('甲'), q('乙')],
        placement: DocxAnswerPlacement.lastPage,
        subtitle: '最薄弱知识点：血液',
        now: DateTime(2026, 9, 15),
      )));
      expect(texts.first, '猫卷 · 错题练习');
      expect(texts[1], '共 2 题 · 2026-09-15 · 答案见最后一页');
      expect(texts[2], '最薄弱知识点：血液');
    });
  });

  group('AppState.exportErrorQuestionsDocx（落盘 + 范围复用）', () {
    Future<int> seedErrorQuestion(String title, {String kp = '血液'}) async {
      final db = DatabaseService.instance;
      final bankId = await db.insertBank(QuestionBank(
          name: '题库_$title', createdAt: DateTime.now().toIso8601String()));
      await db.insertQuestions([
        Question(
          bankId: bankId,
          title: title,
          options: const ['A项', 'B项'],
          correctAnswer: 'B',
          analysis: '因为 B 对',
          knowledgePoint: kp,
          createdAt: DateTime.now().toIso8601String(),
        ),
      ]);
      final qid = (await db.getQuestionsByBank(bankId)).first.id!;
      await db.addToErrorBook(qid);
      await db.insertAnswerRecord(AnswerRecord(
          questionId: qid,
          userAnswer: 'A',
          isCorrect: false,
          answeredAt: DateTime.now().toIso8601String()));
      return qid;
    }

    test('生成 .docx 文件并返回题数；文件可解包', () async {
      final appState = AppState();
      await appState.init();
      await seedErrorQuestion('打印题A');
      await seedErrorQuestion('打印题B');

      final (path, count) = await appState.exportErrorQuestionsDocx(
        'all',
        placement: DocxAnswerPlacement.lastPage,
        subtitle: '当前筛选',
      );
      expect(count, 2);
      expect(path, isNotNull);
      expect(path!.endsWith('.docx'), isTrue);
      final file = File(path);
      expect(file.existsSync(), isTrue);
      expect(file.lengthSync(), greaterThan(1000));

      final doc = docxOf(file.readAsBytesSync());
      final texts = paraTexts(doc);
      expect(texts.any((t) => t.contains('打印题A')), isTrue);
      expect(texts.any((t) => t.contains('打印题B')), isTrue);
      expect(texts, contains('当前筛选'));
      expect(texts.where((t) => t.contains('答案：')).length, 2,
          reason: '两道题各一条答案（末页模式的答案行带题号）');
    });

    test('范围参数照常用：按知识点只导该知识点的题', () async {
      final appState = AppState();
      await appState.init();
      await seedErrorQuestion('血液题', kp: '血液');
      await seedErrorQuestion('免疫题', kp: '免疫');

      final (path, count) = await appState.exportErrorQuestionsDocx('all',
          knowledgePoint: '免疫',
          placement: DocxAnswerPlacement.underQuestion);
      expect(count, 1);
      final texts = paraTexts(docxOf(File(path!).readAsBytesSync()));
      expect(texts.any((t) => t.contains('免疫题')), isTrue);
      expect(texts.any((t) => t.contains('血液题')), isFalse);
    });

    test('范围内没有题时返回 (null, 0)，不产出空文件', () async {
      final appState = AppState();
      await appState.init();
      final (path, count) = await appState.exportErrorQuestionsDocx('all',
          placement: DocxAnswerPlacement.underQuestion);
      expect(path, isNull);
      expect(count, 0);
    });
  });
}
