import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/models/question.dart';
import 'package:flashcard_app/models/question_bank.dart';
import 'package:flashcard_app/services/database_service.dart';

/// 开发者选项相关逻辑测试（v1.0.2 对齐里程碑）：
/// - 模拟长期使用基于当前题库（先建题库）；重复执行不新增数据
/// - DB 备份导出/导入校验（SQLite 魔数 + 核心表 + 文件过小）
void main() {
  setUp(() async {
    await DatabaseService.instance.close();
    final dir = Directory(
        Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path);
    final dbPath = '${dir.path}/flashcard_app/test_dev_mode.db';
    DatabaseService.overrideDbPath = dbPath;
    final dbFile = File(dbPath);
    if (await dbFile.exists()) await dbFile.delete();
  });

  tearDown(() async {
    await DatabaseService.instance.close();
    DatabaseService.overrideDbPath = null;
  });

  Future<void> seedBank() async {
    final db = DatabaseService.instance;
    final now = DateTime.now().toIso8601String();
    final bankId =
        await db.insertBank(QuestionBank(name: '真实题库', createdAt: now));
    await db.insertQuestions([
      for (var i = 1; i <= 10; i++)
        Question(
            bankId: bankId,
            title: '题$i',
            correctAnswer: 'A',
            options: const ['A', 'B', 'C'],
            createdAt: now),
    ]);
  }

  test('模拟长期使用：基于当前题库生成数据，重复调用不新增', () async {
    final db = DatabaseService.instance;
    await seedBank();
    final r1 = await db.simulateLongTermUse();
    expect(r1.error, isNull);
    // v1.0.2 设计审查修复：模拟数据带 source='simulation'，不进真实统计口径，
    // 本测试用原始表直查验证数据量
    final raw = await db.database;
    Future<int> rawCount(String table) async =>
        (await raw.rawQuery('SELECT COUNT(*) as c FROM $table')).first['c']
            as int;
    final total1 = await rawCount('answer_records');
    expect(total1, greaterThan(0));
    final r2 = await db.simulateLongTermUse();
    expect(r2.error, isNull);
    final total2 = await rawCount('answer_records');
    expect(total2, total1);
  });

  test('DB 备份：导出 → 导入（校验通过并替换）', () async {
    final db = DatabaseService.instance;
    await seedBank();
    await db.simulateLongTermUse();
    final dir = Directory(
        Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path);
    final backupPath = '${dir.path}/backup_${DateTime.now().millisecondsSinceEpoch}.db';
    final err = await db.exportBackup(backupPath);
    expect(err, isNull);

    // 校验合法备份
    expect(await db.validateBackupFile(backupPath), isNull);

    // 篡改文件 → 魔数校验失败（文件不是有效的 SQLite 数据库备份）
    final badPath = '${dir.path}/bad_${DateTime.now().millisecondsSinceEpoch}.db';
    await File(badPath).writeAsString('not a sqlite file at all');
    expect(await db.validateBackupFile(badPath), isNotNull);

    // 过小文件 → 文件不是有效的数据库备份（文件过小）
    final tinyPath = '${dir.path}/tiny_${DateTime.now().millisecondsSinceEpoch}.db';
    await File(tinyPath).writeAsString('tiny');
    expect(await db.validateBackupFile(tinyPath), isNotNull);

    // 导入合法备份
    final importErr = await db.importBackup(backupPath);
    expect(importErr, isNull);
    // 导入后数据仍在（模拟数据带 source='simulation'，用原始表直查验证）
    final rawDb = await db.database;
    final rawAfterImport =
        await rawDb.rawQuery('SELECT COUNT(*) as c FROM answer_records');
    expect(rawAfterImport.first['c'], greaterThan(0));
  });
}
