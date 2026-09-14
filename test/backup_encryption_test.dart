import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/services/backup_crypto.dart';
import 'package:flashcard_app/services/database_service.dart';
import 'package:flashcard_app/services/key_crypto.dart';

/// 加密备份（口令保护）与「导出默认不含 API Key」的回归测试。
///
/// 背景：导出备份原本就是整库文件拷贝，`settings.api_key` 那条密文会随之
/// 进入备份；而它的密钥是写死在 App 里的（[KeyCrypto] 的固定盐），
/// 也就是说**拿到备份文件的人就能解出 API Key**。
/// 现在默认在副本里删掉该行；要带 Key 就必须给整个文件设口令加密。
void main() {
  late Directory tmp;

  setUp(() async {
    await DatabaseService.instance.close();
    tmp = Directory.systemTemp.createTempSync('mj_backup_test_');
    DatabaseService.overrideDbPath = '${tmp.path}/flashcard.db';
  });

  tearDown(() async {
    await DatabaseService.instance.close();
    DatabaseService.overrideDbPath = null;
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// 造一份带 API Key 的最小数据。
  Future<void> seedWithApiKey() async {
    final db = DatabaseService.instance;
    await db.setSetting('api_key', KeyCrypto.encrypt('sk-test-secret-key'));
    await db.setSetting('nickname', '测试同学');
  }

  Future<String> readSetting(DatabaseService db, String key) async {
    final rows = await (await db.database)
        .query('settings', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? '' : (rows.first['value'] as String? ?? '');
  }

  group('BackupCrypto 容器格式', () {
    test('加解密往返一致', () {
      final plain = List<int>.generate(4096, (i) => i % 256);
      final sealed = BackupCrypto.encrypt(plain, 'hunter2hunter2');
      expect(BackupCrypto.looksEncrypted(sealed), isTrue);
      expect(sealed.length, greaterThan(plain.length));
      final back = BackupCrypto.decrypt(sealed, 'hunter2hunter2');
      expect(back, isNotNull);
      expect(back, equals(plain));
    });

    test('口令错误返回 null', () {
      final sealed = BackupCrypto.encrypt(List<int>.filled(64, 7), 'correct');
      expect(BackupCrypto.decrypt(sealed, 'wrong'), isNull);
    });

    test('密文被篡改返回 null（GCM MAC 生效）', () {
      final sealed = BackupCrypto.encrypt(List<int>.filled(256, 9), 'pw123456');
      sealed[BackupCrypto.headerLength + 3] ^= 0xFF; // 改动密文一个字节
      expect(BackupCrypto.decrypt(sealed, 'pw123456'), isNull);
    });

    test('盐与 nonce 每次随机（同一明文两次密文不同）', () {
      final a = BackupCrypto.encrypt(List<int>.filled(32, 1), 'pw123456');
      final b = BackupCrypto.encrypt(List<int>.filled(32, 1), 'pw123456');
      expect(a, isNot(equals(b)));
    });

    test('非容器数据不会被误判', () {
      // SQLite 文件头
      final notMine = List<int>.from('SQLite format 3\u0000'.codeUnits);
      expect(BackupCrypto.looksEncrypted(notMine), isFalse);
      expect(BackupCrypto.decrypt(notMine, 'x'), isNull);
    });

    test('迭代档位码写在头里，未知档位拒绝解密', () {
      final sealed = BackupCrypto.encrypt(List<int>.filled(32, 5), 'pw123456');
      expect(sealed[5], BackupCrypto.formatVersion);
      expect(sealed[6], BackupCrypto.defaultIterCode);
      sealed[6] = 99; // 未来档位：本版本不认识
      expect(BackupCrypto.decrypt(sealed, 'pw123456'), isNull);
    });
  });

  group('导出：API Key 的处理', () {
    test('默认导出不含 API Key（副本里被删掉），其他设置保留', () async {
      final db = DatabaseService.instance;
      await seedWithApiKey();

      final out = '${tmp.path}/plain.db';
      final err = await db.exportBackup(out); // 默认 includeApiKey: false
      expect(err, isNull, reason: '默认导出不应失败');
      expect(File(out).existsSync(), isTrue);

      // 直接开这个备份文件检查
      DatabaseService.overrideDbPath = out;
      await db.close();
      final keyInBackup = await readSetting(db, 'api_key');
      final nicknameInBackup = await readSetting(db, 'nickname');
      expect(keyInBackup, isEmpty,
          reason: '默认导出的备份里不应残留 API Key 密文');
      expect(nicknameInBackup, '测试同学', reason: '其他设置应当正常带出');

      // 明文备份不应被误判为加密容器
      DatabaseService.overrideDbPath = '${tmp.path}/flashcard.db';
      await db.close();
      expect(await db.isEncryptedBackup(out), isFalse);
    });

    test('要带 Key 但没给口令 → 拒绝导出，且不留下文件', () async {
      final db = DatabaseService.instance;
      await seedWithApiKey();

      final out = '${tmp.path}/nopwd.db';
      final err = await db.exportBackup(out, includeApiKey: true);
      expect(err, isNotNull);
      expect(err, contains('口令'));
      expect(File(out).existsSync(), isFalse,
          reason: '被拒绝的导出不应留下半成品文件');
    });

    test('带 Key + 口令 → 产物是加密容器，解密后可得到含 Key 的库', () async {
      final db = DatabaseService.instance;
      await seedWithApiKey();

      final out = '${tmp.path}/enc.db';
      final err = await db.exportBackup(out, includeApiKey: true, password: 'pw123456');
      expect(err, isNull);

      final bytes = await File(out).readAsBytes();
      expect(BackupCrypto.looksEncrypted(bytes), isTrue,
          reason: '导出文件应为加密容器（开头是 MJBAK 魔数）');
      expect(await db.isEncryptedBackup(out), isTrue);

      // 解密后应是一份可用的库，且 Key 被保留
      final plain = BackupCrypto.decrypt(bytes, 'pw123456');
      expect(plain, isNotNull);
      final decPath = '${tmp.path}/dec.db';
      await File(decPath).writeAsBytes(plain!);
      DatabaseService.overrideDbPath = decPath;
      await db.close();
      expect(await readSetting(db, 'api_key'), isNotEmpty,
          reason: '含 Key 导出的备份，解密后应保留 API Key');
    });
  });

  group('导入：加密备份与旧版明文备份', () {
    test('正确口令可导入加密备份', () async {
      final db = DatabaseService.instance;
      await seedWithApiKey();
      final enc = '${tmp.path}/enc.db';
      await db.exportBackup(enc, includeApiKey: true, password: 'pw123456');

      // 换一个空库，再从加密备份导入
      final fresh = Directory.systemTemp.createTempSync('mj_fresh_');
      addTearDown(() {
        try {
          fresh.deleteSync(recursive: true);
        } catch (_) {}
      });
      DatabaseService.overrideDbPath = '${fresh.path}/flashcard.db';
      await db.close();

      final err = await db.importBackup(enc, password: 'pw123456');
      expect(err, isNull, reason: '正确口令应导入成功');

      // 导入后设置应恢复
      expect(await readSetting(db, 'nickname'), '测试同学');
    });

    test('口令错误 → 明确报错，且不损坏当前库', () async {
      final db = DatabaseService.instance;
      await seedWithApiKey();
      final enc = '${tmp.path}/enc.db';
      await db.exportBackup(enc, includeApiKey: true, password: 'pw123456');

      final err = await db.importBackup(enc, password: 'wrong-pw');
      expect(err, isNotNull);
      expect(err, contains('口令错误'));

      // 当前库仍然可用、数据还在
      expect(await readSetting(db, 'api_key'), isNotEmpty);
    });

    test('加密备份不给口令 → 提示需要口令（而不是报格式错误）', () async {
      final db = DatabaseService.instance;
      await seedWithApiKey();
      final enc = '${tmp.path}/enc.db';
      await db.exportBackup(enc, includeApiKey: true, password: 'pw123456');

      final err = await db.importBackup(enc);
      expect(err, isNotNull);
      expect(err, contains('口令'));
    });

    test('旧版明文备份仍可直接导入（向后兼容）', () async {
      final db = DatabaseService.instance;
      await seedWithApiKey();
      final plain = '${tmp.path}/plain.db';
      await db.exportBackup(plain); // 不含 Key、未加密

      final err = await db.importBackup(plain); // 不给口令
      expect(err, isNull, reason: '明文备份不应要求口令');
      expect(await readSetting(db, 'nickname'), '测试同学');
    });

    test('解密用的中间文件不会留在磁盘上', () async {
      final db = DatabaseService.instance;
      await seedWithApiKey();
      final enc = '${tmp.path}/enc.db';
      await db.exportBackup(enc, includeApiKey: true, password: 'pw123456');
      await db.importBackup(enc, password: 'pw123456');

      expect(File('$enc.decrypted').existsSync(), isFalse,
          reason: '解密出的明文副本用完必须删除');
    });
  });
}
