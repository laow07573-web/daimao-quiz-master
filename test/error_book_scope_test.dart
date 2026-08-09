import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/models/question.dart';
import 'package:flashcard_app/models/question_bank.dart';
import 'package:flashcard_app/services/database_service.dart';
import 'package:flashcard_app/services/fsrs_service.dart';

/// 错题口径测试（v1.0.2）：
/// - 全部 = 到期 ∪ 收藏（去重）
/// - 待复习 = 纯到期
/// - 知识点分组与主列表同口径
void main() {
  setUp(() async {
    await DatabaseService.instance.close();
    // 每次测试使用独立数据库文件（多测试文件并行隔离）
    final dir =
        Directory(Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path);
    final dbPath = '${dir.path}/flashcard_app/test_error_book.db';
    DatabaseService.overrideDbPath = dbPath;
    final dbFile = File(dbPath);
    if (await dbFile.exists()) await dbFile.delete();
  });

  tearDown(() async {
    await DatabaseService.instance.close();
    DatabaseService.overrideDbPath = null;
  });

  Future<(int, List<int>)> seed() async {
    final db = DatabaseService.instance;
    final now = DateTime.now().toIso8601String();
    final bankId = await db.insertBank(
        QuestionBank(name: '测试题库', createdAt: now));
    // 4 道题：q1 到期+收藏 / q2 到期 / q3 收藏 / q4 无
    await db.insertQuestions([
      Question(
          bankId: bankId,
          title: 'q1',
          correctAnswer: 'A',
          knowledgePoint: '血液',
          createdAt: now),
    ]);
    await db.insertQuestions([
      Question(
          bankId: bankId,
          title: 'q2',
          correctAnswer: 'B',
          knowledgePoint: '血液',
          createdAt: now),
    ]);
    await db.insertQuestions([
      Question(
          bankId: bankId,
          title: 'q3',
          correctAnswer: 'C',
          knowledgePoint: '生化',
          createdAt: now),
    ]);
    await db.insertQuestions([
      Question(
          bankId: bankId,
          title: 'q4',
          correctAnswer: 'D',
          knowledgePoint: '生化',
          createdAt: now),
    ]);
    final ids = await db.getQuestionsByBank(bankId);
    final q1id = ids[0].id!, q2id = ids[1].id!, q3id = ids[2].id!, q4id = ids[3].id!;

    // 收藏 q1、q3
    await db.addToErrorBook(q1id);
    await db.addToErrorBook(q3id);
    // FSRS 到期 q1、q2（next_review_at 过去），q4 未到期
    await db.upsertFSRSCard(FSRSCardState(
      questionId: q1id,
      stability: 1,
      difficulty: 5,
      reviewCount: 1,
      lastReviewAt: DateTime.now(),
      nextReviewAt: DateTime.now().subtract(const Duration(days: 1)),
    ));
    await db.upsertFSRSCard(FSRSCardState(
      questionId: q2id,
      stability: 1,
      difficulty: 5,
      reviewCount: 1,
      lastReviewAt: DateTime.now(),
      nextReviewAt: DateTime.now().subtract(const Duration(days: 1)),
    ));
    await db.upsertFSRSCard(FSRSCardState(
      questionId: q4id,
      stability: 1,
      difficulty: 5,
      reviewCount: 1,
      lastReviewAt: DateTime.now(),
      nextReviewAt: DateTime.now().add(const Duration(days: 30)),
    ));
    return (bankId, [q1id, q2id, q3id, q4id]);
  }

  test('getErrorStatsByBank 三计数：due/bookmark/all 去重', () async {
    await seed();
    final stats = await DatabaseService.instance.getErrorStatsByBank();
    expect(stats.length, 1);
    final s = stats.first;
    expect(s['due_count'], 2); // q1, q2 到期
    expect(s['bookmark_count'], 2); // q1, q3 收藏
    expect(s['all_count'], 3); // 到期∪收藏去重 = q1,q2,q3
  });

  test('getFullErrorQuestions 三口径', () async {
    final (_, ids) = await seed();
    final db = DatabaseService.instance;
    final all = await db.getFullErrorQuestions('all');
    final wrong = await db.getFullErrorQuestions('wrong');
    final bookmark = await db.getFullErrorQuestions('bookmark');
    expect(all.map((q) => q.id).toSet(), {ids[0], ids[1], ids[2]});
    expect(wrong.map((q) => q.id).toSet(), {ids[0], ids[1]});
    expect(bookmark.map((q) => q.id).toSet(), {ids[0], ids[2]});
  });

  test('getFullErrorCount 与列表一致', () async {
    final (_, ids) = await seed();
    final db = DatabaseService.instance;
    expect(await db.getFullErrorCount('all'), 3);
    expect(await db.getFullErrorCount('wrong'), 2);
    expect(await db.getFullErrorCount('bookmark'), 2);
    expect(await db.getFullErrorCount('bookmark', bankIds: {999}), 0);
    expect(ids, isNotEmpty);
  });

  test('知识点分组与主列表同口径（all 模式）', () async {
    final (_, ids) = await seed();
    final db = DatabaseService.instance;
    final kps = await db.getKnowledgePointStats('all');
    final byKp = {for (final k in kps) k['kp'] as String: k['cnt'] as int};
    expect(byKp['血液'], 2); // q1, q2
    expect(byKp['生化'], 1); // q3（q4 未到期未收藏）
    // 按知识点取题范围一致
    final blood = await db.getFullQuestionsByKnowledgePoint('血液', 'all');
    expect(blood.map((q) => q.id).toSet(), {ids[0], ids[1]});
  });

  test('知识点分组与主列表同口径（wrong 模式）', () async {
    final (_, ids) = await seed();
    final db = DatabaseService.instance;
    final kps = await db.getKnowledgePointStats('wrong');
    final byKp = {for (final k in kps) k['kp'] as String: k['cnt'] as int};
    expect(byKp['血液'], 2);
    expect(byKp.containsKey('生化'), isFalse);
    final blood = await db.getFullQuestionsByKnowledgePoint('血液', 'wrong');
    expect(blood.map((q) => q.id).toSet(), {ids[0], ids[1]});
  });
}
