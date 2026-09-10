import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/models/question.dart';
import 'package:flashcard_app/models/question_bank.dart';
import 'package:flashcard_app/services/database_service.dart';

/// 聊天气泡式追问（v1.0.2 用户反馈）：
/// 每道题追问历史持久化（follow_up_messages 表）、
/// 随题库删除级联清理、备份版本提升至 9。
void main() {
  setUp(() async {
    // 每个用例独立数据库（多测试文件并行隔离）
    await DatabaseService.instance.close();
    final dir = Directory(
        Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path);
    final dbPath = '${dir.path}/flashcard_app/test_follow_up.db';
    DatabaseService.overrideDbPath = dbPath;
    final dbFile = File(dbPath);
    if (await dbFile.exists()) await dbFile.delete();
  });

  tearDown(() async {
    await DatabaseService.instance.close();
    DatabaseService.overrideDbPath = null;
  });

  Future<(int, int)> seedBankAndQuestion() async {
    final db = DatabaseService.instance;
    final now = DateTime.now().toIso8601String();
    final bankId =
        await db.insertBank(QuestionBank(name: '追问测试库', createdAt: now));
    await db.insertQuestions([
      Question(
        bankId: bankId,
        title: '测试题',
        options: const ['A', 'B', 'C', 'D'],
        correctAnswer: 'A',
        questionType: 'single_choice',
        createdAt: now,
      ),
    ]);
    final raw = await db.database;
    final r =
        await raw.rawQuery('SELECT id FROM questions ORDER BY id DESC LIMIT 1');
    final qid = r.first['id'] as int;
    return (bankId, qid);
  }

  test('追问消息保存与读取（用户/AI 按时间正序）', () async {
    final (_, qid) = await seedBankAndQuestion();
    final db = DatabaseService.instance;

    await db.saveFollowUpMessage(qid, 'user', '为什么选 A？');
    await db.saveFollowUpMessage(qid, 'assistant', '因为 A 符合定义。');
    await db.saveFollowUpMessage(qid, 'user', '再讲细一点。');
    await db.saveFollowUpMessage(qid, 'assistant', '好的，A 的定义是……');

    final rows = await db.getFollowUpMessages(qid);
    expect(rows.length, 4);
    expect(rows[0]['role'], 'user');
    expect(rows[0]['content'], '为什么选 A？');
    expect(rows[1]['role'], 'assistant');
    expect(rows[3]['content'], '好的，A 的定义是……');
  });

  test('追问消息按题隔离', () async {
    final (_, qid1) = await seedBankAndQuestion();
    final (_, qid2) = await seedBankAndQuestion();
    final db = DatabaseService.instance;

    await db.saveFollowUpMessage(qid1, 'user', '问题一的追问');
    await db.saveFollowUpMessage(qid2, 'user', '问题二的追问');

    final rows1 = await db.getFollowUpMessages(qid1);
    final rows2 = await db.getFollowUpMessages(qid2);
    expect(rows1.length, 1);
    expect(rows1[0]['content'], '问题一的追问');
    expect(rows2.length, 1);
    expect(rows2[0]['content'], '问题二的追问');
  });

  test('删除题库级联清理追问消息', () async {
    final (bankId, qid) = await seedBankAndQuestion();
    final db = DatabaseService.instance;

    await db.saveFollowUpMessage(qid, 'user', '测试消息');
    await db.saveFollowUpMessage(qid, 'assistant', '测试回复');

    await db.deleteBank(bankId);

    final rows = await db.getFollowUpMessages(qid);
    expect(rows, isEmpty, reason: '级联删除后追问历史应为空');
  });

  test('schema 版本为 10（备份导入校验范围含 10）', () async {
    final (_, qid) = await seedBankAndQuestion();
    final db = DatabaseService.instance;
    await db.saveFollowUpMessage(qid, 'user', '消息');
    expect(await db.getFollowUpMessages(qid), isNotEmpty);

    // 导出备份后校验：v10 应通过（版本范围 1..10，
    // v1.0.3 手写批注升级同款 bug 不重现）
    final bakPath =
        '${Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path}'
        '/flashcard_app/test_follow_up_bak.db';
    final bakFile = File(bakPath);
    if (await bakFile.exists()) await bakFile.delete();
    final ok = await db.exportBackup(bakPath);
    expect(ok, isNull, reason: '导出不应报错');
    final error = await db.validateBackupFile(bakPath);
    expect(error, isNull, reason: 'v10 备份应通过校验');
    if (await bakFile.exists()) await bakFile.delete();
  });
}
