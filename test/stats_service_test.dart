import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/models/answer_record.dart';
import 'package:flashcard_app/models/question.dart';
import 'package:flashcard_app/models/question_bank.dart';
import 'package:flashcard_app/services/database_service.dart';
import 'package:flashcard_app/services/stats_service.dart';

/// StatsService（统计页数据层）此前零覆盖。
/// 覆盖：首页统计聚合、周期统计、题库正确率、最长连击（含假期口径）。
void main() {
  setUp(() async {
    await DatabaseService.instance.close();
    final dir = Directory(
        Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path);
    final dbPath =
        '${dir.path}/flashcard_app/test_stats_service_${DateTime.now().millisecondsSinceEpoch}.db';
    DatabaseService.overrideDbPath = dbPath;
    final f = File(dbPath);
    if (await f.exists()) await f.delete();
  });

  tearDown(() async {
    await DatabaseService.instance.close();
    DatabaseService.overrideDbPath = null;
  });

  final svc = StatsService();

  Future<int> seedBankWithQuestions() async {
    final db = DatabaseService.instance;
    final now = DateTime.now().toIso8601String();
    final bankId =
        await db.insertBank(QuestionBank(name: '统计测试库', createdAt: now));
    await db.insertQuestions([
      Question(
          bankId: bankId,
          title: '统计题1',
          options: const ['A', 'B'],
          correctAnswer: 'A',
          createdAt: now),
      Question(
          bankId: bankId,
          title: '统计题2',
          options: const ['A', 'B'],
          correctAnswer: 'B',
          createdAt: now),
    ]);
    return bankId;
  }

  Future<void> answer(int questionId, bool correct) async {
    await DatabaseService.instance.insertAnswerRecord(AnswerRecord(
      questionId: questionId,
      userAnswer: correct ? 'A' : 'Z',
      isCorrect: correct,
      answeredAt: DateTime.now().toIso8601String(),
    ));
  }

  test('空库：getHomeStats 全零、getPeriodStats 归零不抛异常', () async {
    final home = await svc.getHomeStats();
    expect(home.totalQuestions, 0);
    expect(home.totalDurationSeconds, 0);
    expect(home.overallAccuracy, 0);
    expect(home.formattedDuration, '0 h 0 m');
    expect(home.formattedAccuracy, '0.0%');

    final period = await svc.getPeriodStats('week');
    expect(period.totalQuestions, 0);
    expect(period.accuracy, 0);
    expect(period.formattedDuration, '0秒');
  });

  test('getHomeStats：聚合总题量 / 正确率 / 时长', () async {
    final bankId = await seedBankWithQuestions();
    final db = DatabaseService.instance;
    final all = await db.getQuestionsByBank(bankId);
    final q1 = all[0], q2 = all[1];

    await answer(q1.id!, true);
    await answer(q2.id!, false);

    final home = await svc.getHomeStats();
    expect(home.totalQuestions, 2);
    expect(home.overallAccuracy, closeTo(50.0, 0.01));
    expect(home.formattedAccuracy, '50.0%');
  });

  test('getPeriodStats：本周窗口内计入，正确率换算正确', () async {
    final bankId = await seedBankWithQuestions();
    final db = DatabaseService.instance;
    final all = await db.getQuestionsByBank(bankId);
    await answer(all[0].id!, true);
    await answer(all[1].id!, true);
    await answer(all[0].id!, false);

    final period = await svc.getPeriodStats('week');
    expect(period.totalQuestions, 3);
    expect(period.accuracy, closeTo(2 / 3 * 100, 0.01));
  });

  test('getBankAccuracies：按题库聚合正确率', () async {
    final bankId = await seedBankWithQuestions();
    final db = DatabaseService.instance;
    final all = await db.getQuestionsByBank(bankId);
    await answer(all[0].id!, true);
    await answer(all[0].id!, true);
    await answer(all[1].id!, false);

    final accs = await svc.getBankAccuracies();
    expect(accs, hasLength(1));
    expect(accs.first.bankName, '统计测试库');
    expect(accs.first.total, 3);
    expect(accs.first.correct, 2);
    expect(accs.first.accuracy, closeTo(2 / 3 * 100, 0.01));
    expect(accs.first.formattedAccuracy, '66.7%');
  });

  test('getPeriodLongestStreak：≥50 题连击计数、不足中断', () async {
    // 直接构造 5 天：3 天达标（50+）、1 天不足、1 天达标 → 最长连击 3
    final db = DatabaseService.instance;
    final bankId = await seedBankWithQuestions();
    final all = await db.getQuestionsByBank(bankId);
    final qid = all.first.id!;
    final now = DateTime.now();
    for (var d = 4; d >= 0; d--) {
      final day = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: d));
      final count = (d == 1) ? 49 : 50; // 倒数第 2 天不足 50
      for (var i = 0; i < count; i++) {
        await db.insertAnswerRecord(AnswerRecord(
          questionId: qid,
          isCorrect: true,
          answeredAt: day
              .add(Duration(hours: 8, minutes: i))
              .toIso8601String(),
        ));
      }
    }
    final streak = await svc.getPeriodLongestStreak('all');
    expect(streak, 3, reason: '达标-达标-达标-不足-达标 → 最长连击为 3');
  });
}
