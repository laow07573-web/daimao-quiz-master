import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/models/answer_record.dart';
import 'package:flashcard_app/models/question.dart';
import 'package:flashcard_app/models/question_bank.dart';
import 'package:flashcard_app/services/app_state.dart';
import 'package:flashcard_app/services/bank_file_service.dart';
import 'package:flashcard_app/services/database_service.dart';

/// 错题导出增强 + 逐题统计的回归测试。
///
/// 覆盖产品要求：按「错得最多」排序导出、按时间窗（近 7 天 / 近 30 天）筛选、
/// 自定义选题导出，以及卡片要显示的「做过几次 / 正确率 / FSRS」数据来源。
/// 另外锁住一条兼容性：**带统计字段的导出文件仍可被当前版本导入**。
void main() {
  late Directory tmp;

  setUp(() async {
    await DatabaseService.instance.close();
    tmp = Directory.systemTemp.createTempSync('mj_error_export_');
    DatabaseService.overrideDbPath = '${tmp.path}/flashcard.db';
  });

  tearDown(() async {
    await DatabaseService.instance.close();
    DatabaseService.overrideDbPath = null;
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// 造一道错题：入库 + 加入错题本 + 若干次作答（wrong 次错、其余对）
  Future<int> seedErrorQuestion(
    String title, {
    required int wrong,
    required int correct,
    required int daysAgo,
    String kp = '测试知识点',
  }) async {
    final db = DatabaseService.instance;
    final now = DateTime.now();
    final answeredAt = now.subtract(Duration(days: daysAgo));
    final stamp = answeredAt.toIso8601String();

    final bankId = await db.insertBank(
        QuestionBank(name: '题库_$title', createdAt: stamp));
    await db.insertQuestions([
      Question(
        bankId: bankId,
        title: title,
        options: const ['A', 'B'],
        correctAnswer: 'A',
        knowledgePoint: kp,
        createdAt: stamp,
      ),
    ]);
    final qid = (await db.getQuestionsByBank(bankId)).first.id!;
    await db.addToErrorBook(qid);

    for (var i = 0; i < wrong; i++) {
      await db.insertAnswerRecord(AnswerRecord(
          questionId: qid,
          userAnswer: 'B',
          isCorrect: false,
          answeredAt: stamp));
    }
    for (var i = 0; i < correct; i++) {
      await db.insertAnswerRecord(AnswerRecord(
          questionId: qid,
          userAnswer: 'A',
          isCorrect: true,
          answeredAt: stamp));
    }
    return qid;
  }

  group('批量作答统计', () {
    test('多题一次聚合，且口径一致（排除 hidden / 模拟数据）', () async {
      final db = DatabaseService.instance;
      final a = await seedErrorQuestion('A', wrong: 2, correct: 1, daysAgo: 1);
      final b = await seedErrorQuestion('B', wrong: 3, correct: 0, daysAgo: 10);

      final stats = await db.getQuestionStatsByIds([a, b]);
      expect(stats[a], (3, 1));
      expect(stats[b], (3, 0));

      // 隐藏的记录不计入
      final rows = await (await db.database)
          .query('answer_records', where: 'question_id = ?', whereArgs: [a]);
      await (await db.database).update('answer_records', {'hidden': 1},
          where: 'id = ?', whereArgs: [rows.first['id']]);
      final after = await db.getQuestionStatsByIds([a]);
      expect(after[a], (2, 1), reason: 'hidden=1 的记录不应计入');
    });

    test('空列表返回空（不抛错、不查库）', () async {
      expect(await DatabaseService.instance.getQuestionStatsByIds([]), isEmpty);
    });

    test('没有任何作答记录的题不出现在结果里', () async {
      final stats = await DatabaseService.instance.getQuestionStatsByIds([999999]);
      expect(stats, isEmpty);
    });
  });

  group('导出：排序 / 时间窗 / 自定义选题', () {
    test('默认按「错得最多」排序', () async {
      final appState = AppState();
      await appState.init();
      await seedErrorQuestion('错2次', wrong: 2, correct: 0, daysAgo: 1);
      await seedErrorQuestion('错5次', wrong: 5, correct: 1, daysAgo: 1);
      await seedErrorQuestion('错3次', wrong: 3, correct: 0, daysAgo: 1);

      final (path, count) =
          await appState.exportErrorQuestionsJson('all', includeStats: true);
      expect(count, 3);
      expect(path, isNotNull);

      final data = jsonDecode(await File(path!).readAsString());
      final titles = (data['questions'] as List)
          .map((q) => q['title'] as String)
          .toList();
      expect(titles.first, '错5次', reason: '错得最多的应排在最前');
      expect(titles.last, '错2次');
    });

    test('近 7 天时间窗：只导出最近做过的，第 8 天的排除在外', () async {
      final appState = AppState();
      await appState.init();
      await seedErrorQuestion('今天做过', wrong: 1, correct: 0, daysAgo: 0);
      await seedErrorQuestion('6天前做过', wrong: 9, correct: 0, daysAgo: 6);
      await seedErrorQuestion('8天前做过', wrong: 9, correct: 0, daysAgo: 8);

      final (path, count) =
          await appState.exportErrorQuestionsJson('all', window: '7d');
      expect(count, 2);
      final data = jsonDecode(await File(path!).readAsString());
      final titles =
          (data['questions'] as List).map((q) => q['title'] as String).toSet();
      expect(titles, containsAll(['今天做过', '6天前做过']));
      expect(titles, isNot(contains('8天前做过')));
    });

    test('近 30 天时间窗：第 31 天排除', () async {
      final appState = AppState();
      await appState.init();
      await seedErrorQuestion('10天前', wrong: 1, correct: 0, daysAgo: 10);
      await seedErrorQuestion('40天前', wrong: 1, correct: 0, daysAgo: 40);

      final (_, count) =
          await appState.exportErrorQuestionsJson('all', window: '30d');
      expect(count, 1);
    });

    test('自定义选题：只导出指定 id', () async {
      final appState = AppState();
      await appState.init();
      final keep = await seedErrorQuestion('要导出', wrong: 1, correct: 0, daysAgo: 1);
      await seedErrorQuestion('不要导出', wrong: 1, correct: 0, daysAgo: 1);

      final (path, count) = await appState.exportErrorQuestionsJson('all',
          questionIds: {keep});
      expect(count, 1);
      final data = jsonDecode(await File(path!).readAsString());
      expect((data['questions'] as List).single['title'], '要导出');
    });

    test('按知识点导出（最薄弱点）', () async {
      final appState = AppState();
      await appState.init();
      await seedErrorQuestion('血液题', wrong: 1, correct: 0, daysAgo: 1, kp: '血液');
      await seedErrorQuestion('免疫题', wrong: 1, correct: 0, daysAgo: 1, kp: '免疫');

      final (_, count) = await appState.exportErrorQuestionsJson('all',
          knowledgePoint: '血液');
      expect(count, 1);
    });

    test('无题可导出时返回 (null, 0)', () async {
      final appState = AppState();
      await appState.init();
      final (path, count) = await appState.exportErrorQuestionsJson('all');
      expect(path, isNull);
      expect(count, 0);
    });
  });

  group('导出格式兼容性', () {
    test('带 stats/fsrs 的导出文件仍可被导入（附加键向后兼容）', () async {
      final appState = AppState();
      await appState.init();
      await seedErrorQuestion('带统计的题', wrong: 2, correct: 1, daysAgo: 1);

      final (path, _) =
          await appState.exportErrorQuestionsJson('all', includeStats: true);
      final data = jsonDecode(await File(path!).readAsString());
      final q = (data['questions'] as List).first;

      // 附加字段确实写进去了
      expect(q['stats'], isNotNull);
      expect(q['stats']['answered'], 3);
      expect(q['stats']['correct'], 1);
      expect(q['stats']['wrong'], 2);

      // 关键：导入侧只读已知键，忽略未知键——文件仍可被识别为猫卷题库
      final (groups, err) = await BankFileService.parseJsonFile(path!);
      expect(err, isNull, reason: '附加 stats/fsrs/filter 不应导致导入失败');
      expect(groups.length, 1);
      expect(groups.values.first.single.title, '带统计的题');
    });
  });
}
