import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/models/question.dart';
import 'package:flashcard_app/models/question_bank.dart';
import 'package:flashcard_app/services/database_service.dart';

/// 模拟长期使用（v1.0.2 对齐里程碑）：
/// 基于当前题库生成过去 N 天的刷题记录、错题与复习卡；
/// 重复执行会先清理上次模拟的数据（数据量不变）。
///
/// v1.0.2 设计审查修复：模拟数据带 source='simulation'，不再进入真实
/// 统计口径（getTotalQuestionsAnswered/getAllSessions 等），
/// 本测试改用原始表直查验证生成与清理。
void main() {
  setUp(() async {
    // 每个用例独立数据库（多测试文件并行隔离）
    await DatabaseService.instance.close();
    final dir = Directory(
        Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path);
    final dbPath = '${dir.path}/flashcard_app/test_simulate.db';
    DatabaseService.overrideDbPath = dbPath;
    final dbFile = File(dbPath);
    if (await dbFile.exists()) await dbFile.delete();
  });

  tearDown(() async {
    await DatabaseService.instance.close();
    DatabaseService.overrideDbPath = null;
  });

  Future<int> seedBank() async {
    final db = DatabaseService.instance;
    final now = DateTime.now().toIso8601String();
    final bankId =
        await db.insertBank(QuestionBank(name: '真实题库', createdAt: now));
    await db.insertQuestions([
      for (var i = 1; i <= 20; i++)
        Question(
            bankId: bankId,
            title: '题$i',
            correctAnswer: 'A',
            options: const ['A', 'B', 'C'],
            createdAt: now),
    ]);
    return bankId;
  }

  /// 原始表直查（不区分 source，验证模拟数据的物理存在/清理）
  Future<int> rawAnswerCount() async {
    final raw = await DatabaseService.instance.database;
    final r = await raw.rawQuery('SELECT COUNT(*) as c FROM answer_records');
    return r.first['c'] as int;
  }

  Future<int> rawSessionCount() async {
    final raw = await DatabaseService.instance.database;
    final r = await raw.rawQuery('SELECT COUNT(*) as c FROM quiz_sessions');
    return r.first['c'] as int;
  }

  test('simulateLongTermUse 重复执行数据量不变', () async {
    final db = DatabaseService.instance;
    await seedBank();

    final r1 = await db.simulateLongTermUse();
    final records1 = await rawAnswerCount();
    final sessions1 = await rawSessionCount();
    // 模拟数据不进入真实统计口径（source 隔离）
    expect(await db.getTotalQuestionsAnswered(), 0);

    final r2 = await db.simulateLongTermUse();
    final records2 = await rawAnswerCount();
    final sessions2 = await rawSessionCount();

    expect(r1.error, isNull);
    expect(r2.error, isNull);
    expect(records2, records1);
    expect(sessions2, sessions1);
    expect(records1, greaterThan(0));
  });

  test('deleteBank 显式清理 answer_records（模拟记录随题库级联清理）', () async {
    final db = DatabaseService.instance;
    final bankId = await seedBank();
    final r1 = await db.simulateLongTermUse();
    expect(r1.records, greaterThan(0));
    final before = await rawAnswerCount();
    expect(before, greaterThan(0));
    await db.deleteBank(bankId);
    final after = await rawAnswerCount();
    expect(after, 0); // 外键级联清理
    expect((await db.getAllBanks()).any((b) => b.name == '真实题库'), isFalse);
  });
}
