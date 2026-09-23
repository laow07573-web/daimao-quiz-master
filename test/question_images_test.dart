import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flashcard_app/models/question.dart';
import 'package:flashcard_app/models/question_bank.dart';
import 'package:flashcard_app/models/question_image.dart';
import 'package:flashcard_app/services/bank_file_service.dart';
import 'package:flashcard_app/services/database_service.dart';

/// 题目配图（schema v12）的持久化回归测试 + 备份版本闸门。
///
/// 图片必须「随题走」：入库随题、删题级联、备份/JSON 往返都不少图。
/// 备份闸门那条是硬回归——版本上界不随 schema 抬头的话，
/// 新版备份会被自己拒收（导得进不出、出得去进不来）。
void main() {
  late Directory tmp;
  const now = '2026-09-23T00:00:00.000';

  setUp(() async {
    await DatabaseService.instance.close();
    tmp = Directory.systemTemp.createTempSync('mj_qimg_');
    DatabaseService.overrideDbPath = '${tmp.path}/flashcard.db';
  });

  tearDown(() async {
    await DatabaseService.instance.close();
    DatabaseService.overrideDbPath = null;
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  QuestionImage img(int pos, List<int> bytes) => QuestionImage(
        position: pos,
        width: 20,
        height: 10,
        content: Uint8List.fromList(bytes),
      );

  Future<int> seedBank() => DatabaseService.instance.insertBank(
      QuestionBank(name: 'T', createdAt: now));

  group('配图随题入库', () {
    test('插题返回 id；配图按槽位落库、按槽位取回', () async {
      final db = DatabaseService.instance;
      final bankId = await seedBank();
      final ids = await db.insertQuestions([
        Question(
          bankId: bankId,
          title: '一题{{img:0}}',
          correctAnswer: 'A',
          createdAt: now,
          images: [img(0, [1, 1]), img(1, [2, 2])],
        ),
        Question(bankId: bankId, title: '二题', correctAnswer: 'B', createdAt: now),
      ]);
      expect(ids, hasLength(2));

      final map = await db.getImagesForQuestions(ids);
      expect(map[ids[0]]!.map((i) => i.position), [0, 1]);
      expect(map[ids[0]]![1].content, [2, 2]);
      expect(map[ids[1]], isNull);

      final counts = await db.getImageCountsByQuestions(ids);
      expect(counts[ids[0]], 2);
      expect(counts.containsKey(ids[1]), isFalse);
    });

    test('删题级联删图（图片是题目的一部分，随题删除）', () async {
      final db = DatabaseService.instance;
      final bankId = await seedBank();
      final ids = await db.insertQuestions([
        Question(
          bankId: bankId,
          title: '带图{{img:0}}',
          correctAnswer: 'A',
          createdAt: now,
          images: [img(0, [3])],
        ),
      ]);
      final raw = await db.database;
      await raw.delete('questions', where: 'id = ?', whereArgs: [ids.first]);
      expect(await db.getImagesForQuestions(ids), isEmpty);
    });

    test('replaceQuestionImages 整题换图；mergeQuestionImages 首写槽位生效', () async {
      final db = DatabaseService.instance;
      final bankId = await seedBank();
      final ids = await db.insertQuestions([
        Question(
          bankId: bankId,
          title: '{{img:0}}',
          correctAnswer: 'A',
          createdAt: now,
          images: [img(0, [1])],
        ),
      ]);
      final id = ids.first;

      await db.replaceQuestionImages(id, [img(0, [9])]);
      var map = await db.getImagesForQuestions([id]);
      expect(map[id]!.single.content, [9]);

      // 同步合并语义：已有槽位不覆盖，缺的补插（幂等）
      await db.mergeQuestionImages(id, [img(0, [7]), img(1, [8])]);
      await db.mergeQuestionImages(id, [img(0, [6]), img(1, [4])]);
      map = await db.getImagesForQuestions([id]);
      expect(map[id]!.map((i) => i.content), [
        [9],
        [8],
      ]);
    });
  });

  group('备份版本闸门（硬回归）', () {
    test('当前 schema 备份可导可验；未来版本备份拒绝', () async {
      final db = DatabaseService.instance;
      final bankId = await seedBank();
      await db.insertQuestions([
        Question(
          bankId: bankId,
          title: '带图{{img:0}}',
          correctAnswer: 'A',
          createdAt: now,
          images: [img(0, [1, 2, 3])],
        ),
      ]);

      final dest = '${tmp.path}/backup.db';
      expect(await db.exportBackup(dest), isNull);
      expect(await db.validateBackupFile(dest), isNull);

      // 伪造「未来 schema」备份（user_version = 13）：必须拒绝而不是导入后踩坑
      final futurePath = '${tmp.path}/future.db';
      File(dest).copySync(futurePath);
      final raw = await databaseFactory.openDatabase(futurePath);
      await raw.execute('PRAGMA user_version = 13');
      await raw.close();
      expect(await db.validateBackupFile(futurePath), isNotNull);
    });

    test('v11 库升到 v12 自动补出配图表与索引', () async {
      final db = DatabaseService.instance;
      final raw = await db.database; // 先建出 v12 全量结构
      await raw.execute('DROP TABLE question_images');
      await raw.execute('PRAGMA user_version = 11');
      await DatabaseService.instance.close();

      final upgraded = await DatabaseService.instance.database;
      final tables = await upgraded.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='question_images'");
      expect(tables, hasLength(1));
      final idx = await upgraded.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_question_images_slot'");
      expect(idx, isNotEmpty);
    });
  });

  group('JSON 题库带图往返', () {
    test('导出带 images 键，解析回来图不丢', () async {
      final db = DatabaseService.instance;
      final bankId = await seedBank();
      await db.insertQuestions([
        Question(
          bankId: bankId,
          title: '带图{{img:0}}',
          correctAnswer: 'A',
          createdAt: now,
          images: [img(0, [5, 6])],
        ),
      ]);

      final dest = '${tmp.path}/bank.json';
      expect(await BankFileService.exportBank(bankId, 'T', dest), isNotNull);
      final (groups, err) = await BankFileService.parseJsonFile(dest);
      expect(err, isNull);
      final got = groups.values.first.single;
      expect(got.title, '带图{{img:0}}');
      expect(got.images, hasLength(1));
      expect(got.images.single.content, [5, 6]);
    });
  });
}
