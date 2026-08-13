import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/models/question.dart';
import 'package:flashcard_app/models/question_bank.dart';
import 'package:flashcard_app/services/database_service.dart';
import 'package:flashcard_app/services/fsrs_service.dart';
import 'package:flashcard_app/utils/format_utils.dart';

/// FSRS 可见化回归测试（v1.0.2）：
/// relativeDayLabel 相对天数标签、getFsrsCardsByIds 批量查询、
/// getErrorStatsByBank.next_due_at 题库最早到期时间
void main() {
  setUp(() async {
    await DatabaseService.instance.close();
    final dir = Directory(
        Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path);
    final dbPath = '${dir.path}/flashcard_app/test_fsrs_vis.db';
    DatabaseService.overrideDbPath = dbPath;
    final f = File(dbPath);
    if (await f.exists()) await f.delete();
  });

  tearDown(() async {
    await DatabaseService.instance.close();
    DatabaseService.overrideDbPath = null;
  });

  group('relativeDayLabel', () {
    final now = DateTime(2026, 8, 14, 15, 30);

    test('全分支：已到期/今天/明天/N天后', () {
      expect(relativeDayLabel(DateTime(2026, 8, 13), now: now), '已到期1天');
      expect(relativeDayLabel(DateTime(2026, 8, 10), now: now), '已到期4天');
      expect(relativeDayLabel(DateTime(2026, 8, 14, 8), now: now), '今天');
      expect(relativeDayLabel(DateTime(2026, 8, 14, 23, 59), now: now), '今天');
      expect(relativeDayLabel(DateTime(2026, 8, 15, 9), now: now), '明天');
      expect(relativeDayLabel(DateTime(2026, 8, 17), now: now), '3天后');
      expect(relativeDayLabel(DateTime(2026, 9, 14), now: now), '31天后');
    });
  });

  test('getFsrsCardsByIds：批量取卡，无卡题目不出现', () async {
    final db = DatabaseService.instance;
    final now = DateTime.now().toIso8601String();
    final bankId = await db.insertBank(QuestionBank(name: '卡', createdAt: now));
    await db.insertQuestions([
      for (var i = 1; i <= 4; i++)
        Question(
            bankId: bankId,
            title: '题$i',
            correctAnswer: 'A',
            createdAt: now),
    ]);
    final qs = await db.getQuestionsByBank(bankId);
    await db.upsertFSRSCard(FSRSService.initCard(qs[0].id!, DateTime.now()));
    await db.upsertFSRSCard(FSRSService.initCard(qs[2].id!, DateTime.now()));
    final cards = await db.getFsrsCardsByIds(qs.map((q) => q.id!).toList());
    expect(cards.length, 2);
    expect(cards.containsKey(qs[0].id), isTrue);
    expect(cards.containsKey(qs[2].id), isTrue);
    expect(cards.containsKey(qs[1].id), isFalse);
    // 空列表防御
    expect(await db.getFsrsCardsByIds([]), isEmpty);
  });

  test('getErrorStatsByBank.next_due_at：取该题库到期卡中最早时间', () async {
    final db = DatabaseService.instance;
    final now = DateTime.now().toIso8601String();
    final bankId =
        await db.insertBank(QuestionBank(name: '到期库', createdAt: now));
    await db.insertQuestions([
      for (var i = 1; i <= 3; i++)
        Question(
            bankId: bankId,
            title: '题$i',
            correctAnswer: 'A',
            createdAt: now),
    ]);
    final qs = await db.getQuestionsByBank(bankId);
    final nowD = DateTime.now();
    // 三张卡：昨天到期 / 5 天后到期 / 无卡
    await db.upsertFSRSCard(FSRSCardState(
        questionId: qs[0].id!,
        stability: 1,
        difficulty: 5,
        reviewCount: 1,
        lastReviewAt: nowD.subtract(const Duration(days: 2)),
        nextReviewAt: nowD.subtract(const Duration(days: 1))));
    await db.upsertFSRSCard(FSRSCardState(
        questionId: qs[1].id!,
        stability: 1,
        difficulty: 5,
        reviewCount: 1,
        lastReviewAt: nowD,
        nextReviewAt: nowD.add(const Duration(days: 5))));

    final stats = await db.getErrorStatsByBank();
    expect(stats.length, 1);
    final row = stats.first;
    expect(row['due_count'], 1);
    expect(row['bookmark_count'], 0);
    // 最早到期 = 昨天（未到期卡不参与 MIN）
    final nextDue = DateTime.parse(row['next_due_at'] as String);
    expect(nextDue.isBefore(nowD), isTrue);
    expect(nextDue.difference(nowD).inDays, -1);
    // 无到期卡的题库：next_due_at 为 null
    final bankId2 = await db.insertBank(
        QuestionBank(name: '纯收藏库', createdAt: now));
    await db.insertQuestions([
      Question(
          bankId: bankId2, title: '收藏题', correctAnswer: 'A', createdAt: now),
    ]);
    final qs2 = await db.getQuestionsByBank(bankId2);
    await db.addToErrorBook(qs2.first.id!);
    final stats2 = await db.getErrorStatsByBank();
    final row2 = stats2.firstWhere((r) => r['bank_name'] == '纯收藏库');
    expect(row2['next_due_at'], isNull);
    expect(row2['due_count'], 0);
    expect(row2['bookmark_count'], 1);
  });
}
