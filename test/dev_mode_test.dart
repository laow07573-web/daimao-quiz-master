import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/services/database_service.dart';

/// 开发者选项相关逻辑测试（v1.0.2）：
/// - 模拟长期使用幂等（跨调用不新增数据）
/// - DB 备份导出/导入校验（SQLite 魔数 + 核心表）
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

  test('模拟长期使用：首次生成数据，重复调用不新增', () async {
    final db = DatabaseService.instance;
    await db.simulateLongTermUse();
    final r1 = await db.getTotalQuestionsAnswered();
    expect(r1, greaterThan(0));
    await db.simulateLongTermUse();
    final r2 = await db.getTotalQuestionsAnswered();
    expect(r2, r1);
  });

  test('DB 备份：导出 → 导入（校验通过并替换）', () async {
    final db = DatabaseService.instance;
    await db.simulateLongTermUse();
    final dir = Directory(
        Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path);
    final backupPath = '${dir.path}/backup_${DateTime.now().millisecondsSinceEpoch}.db';
    final err = await db.exportBackup(backupPath);
    expect(err, isNull);

    // 校验合法备份
    expect(await db.validateBackupFile(backupPath), isNull);

    // 篡改文件 → 魔数校验失败
    final badPath = '${dir.path}/bad_${DateTime.now().millisecondsSinceEpoch}.db';
    await File(badPath).writeAsString('not a sqlite file at all');
    expect(await db.validateBackupFile(badPath), isNotNull);

    // 导入合法备份
    final importErr = await db.importBackup(backupPath);
    expect(importErr, isNull);
    // 导入后数据仍在
    final r = await db.getTotalQuestionsAnswered();
    expect(r, greaterThan(0));
  });
}
