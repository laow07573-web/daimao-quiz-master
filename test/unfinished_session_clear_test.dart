import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/models/question.dart';
import 'package:flashcard_app/models/question_bank.dart';
import 'package:flashcard_app/services/database_service.dart';
import 'package:flashcard_app/services/quiz_service.dart';

/// 断档记录清理回归测试：
/// 上一次答题未完成（暂停/中断）后开始下一次答题时，
/// 旧会话的断档记录（会话行/题目顺序/题库关联）被清空，
/// 续刷卡片只可能指向新会话；已落库的作答记录保留（统计/错题本不受影响）
void main() {
  setUp(() async {
    await DatabaseService.instance.close();
    final dir = Directory(
        Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path);
    final dbPath = '${dir.path}/flashcard_app/test_unfinished_clear.db';
    DatabaseService.overrideDbPath = dbPath;
    final f = File(dbPath);
    if (await f.exists()) await f.delete();
  });

  tearDown(() async {
    await DatabaseService.instance.close();
    DatabaseService.overrideDbPath = null;
  });

  Future<int> seedBank(String name, int count) async {
    final db = DatabaseService.instance;
    final now = DateTime.now().toIso8601String();
    final bankId =
        await db.insertBank(QuestionBank(name: name, createdAt: now));
    await db.insertQuestions([
      for (var i = 1; i <= count; i++)
        Question(
            bankId: bankId,
            title: '$name-题$i',
            correctAnswer: 'A',
            options: const ['甲', '乙', '丙'],
            createdAt: now),
    ]);
    return bankId;
  }

  test('开始新会话时清空上一次未完成会话的断档记录', () async {
    final db = DatabaseService.instance;
    final bankId = await seedBank('T', 3);

    // 第一轮：答一题后中断（暂停不写 end_time）
    final first = QuizService();
    await first.startQuiz(
        bankIds: [bankId], mode: 'single', questionCount: 3);
    final oldSessionId = first.currentSession!.id!;
    await first.submitAnswer('A');
    first.pauseSession();

    final before = await db.getLatestUnfinishedSession();
    expect(before, isNotNull);
    expect(before!.$1.id, oldSessionId);
    expect((await db.getSessionQuestions(oldSessionId)).length, 3);

    // 第二轮：开始新会话 → 旧断档记录被清空
    final second = QuizService();
    await second.startQuiz(
        bankIds: [bankId], mode: 'single', questionCount: 2);
    final newSessionId = second.currentSession!.id!;
    expect(newSessionId, isNot(oldSessionId));

    // 续刷入口只可能指向新会话
    final after = await db.getLatestUnfinishedSession();
    expect(after, isNotNull);
    expect(after!.$1.id, newSessionId);

    // 旧会话行与题目顺序/题库关联均已删除
    final sessions = await db.getAllSessions();
    expect(sessions.any((s) => s.id == oldSessionId), isFalse);
    expect(await db.getSessionQuestions(oldSessionId), isEmpty);
    expect(await db.getSessionBankIds(oldSessionId), isEmpty);

    // 已落库的作答记录保留，统计/错题本口径不受影响
    final records = await db.getAnswerRecordsBySession(oldSessionId);
    expect(records.length, 1);
  });

  test('不落会话的练习（persistSession: false）不清空断档记录', () async {
    final db = DatabaseService.instance;
    final bankId = await seedBank('P', 2);

    final first = QuizService();
    await first.startQuiz(
        bankIds: [bankId], mode: 'single', questionCount: 2);
    final oldSessionId = first.currentSession!.id!;
    await first.submitAnswer('A');
    first.pauseSession();

    // 练习模式不创建会话行，不应取代旧的中断会话
    final practice = QuizService();
    await practice.startQuiz(
        bankIds: [bankId],
        mode: 'practice',
        questionCount: 2,
        persistSession: false);

    final unfinished = await db.getLatestUnfinishedSession();
    expect(unfinished, isNotNull);
    expect(unfinished!.$1.id, oldSessionId);
  });

  test('空题库不建会话时，旧的未完成会话仍可续刷', () async {
    final db = DatabaseService.instance;
    final bankId = await seedBank('E', 2);

    final first = QuizService();
    await first.startQuiz(
        bankIds: [bankId], mode: 'single', questionCount: 2);
    final oldSessionId = first.currentSession!.id!;
    first.pauseSession();

    // 用空题库开新会话：无题不建会话，旧断档保留
    final emptyBankId = await seedBank('EMPTY', 0);
    final second = QuizService();
    await second.startQuiz(
        bankIds: [emptyBankId], mode: 'single', questionCount: 2);
    expect(second.currentSession, isNull);

    final unfinished = await db.getLatestUnfinishedSession();
    expect(unfinished, isNotNull);
    expect(unfinished!.$1.id, oldSessionId);
  });
}
