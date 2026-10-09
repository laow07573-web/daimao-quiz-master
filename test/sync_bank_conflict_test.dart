import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flashcard_app/services/database_service.dart';
import 'package:flashcard_app/services/sync/sync_models.dart';
import 'package:flashcard_app/services/sync/sync_repository.dart';

/// 2026-10-09 用户要求：「同名题库的话，先进行校验比较两份题库和题库附属的内容
/// 的文件是否不一样，若一样则不更新，若不一样则提示是否覆盖或者增添（把题库和
/// 附属文件中相当于本机题库和附属文件中多出来的部分添加到本机的题库和其附属
/// 文件中）。」
///
/// 这些测试覆盖四种情形：不同名照常合并、同名同内容跳过、同名不同内容挂起冲突、
/// 冲突决策后的覆盖与增添两种落地结果。
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late String dbPath;

  setUp(() async {
    await DatabaseService.instance.close();
    final dir = Directory.systemTemp;
    dbPath =
        '${dir.path}/flashcard_sync_conflict_${DateTime.now().microsecondsSinceEpoch}.db';
    DatabaseService.overrideDbPath = dbPath;
    final f = File(dbPath);
    if (await f.exists()) await f.delete();
  });

  tearDown(() async {
    await DatabaseService.instance.close();
    DatabaseService.overrideDbPath = null;
    final f = File(dbPath);
    if (await f.exists()) await f.delete();
  });

  /// 造一个对端快照：一个题库 + 若干题
  Map<String, dynamic> peerSnapshot({
    required String bankUid,
    required String bankName,
    required List<String> titles,
  }) =>
      {
        'protocol': 1,
        'device_id': 'peer-device',
        'device_name': '平板',
        'banks': [
          {
            'uid': bankUid,
            'name': bankName,
            'file_source': 'peer.docx',
            'question_count': titles.length,
            'created_at': '2026-10-01T00:00:00.000',
            'updated_at': '2026-10-01T00:00:00.000',
          }
        ],
        'questions': [
          for (var i = 0; i < titles.length; i++)
            {
              'uid': '$bankUid-q$i',
              'bank_uid': bankUid,
              'title': titles[i],
              'options': jsonEncode(['A', 'B']),
              'correct_answer': 'A',
              'analysis': null,
              'question_type': 'single_choice',
              'source': 'real',
              'knowledge_point': null,
              'created_at': '2026-10-01T00:00:00.000',
              'updated_at': '2026-10-01T00:00:00.000',
            }
        ],
        'question_images': const [],
        'sessions': const [],
        'answer_records': const [],
        'error_book': const [],
        'annotations': const [],
      };

  /// 在本机建一个同名题库（uid 不同）与给定题目
  Future<int> seedLocalBank(String name, List<String> titles) async {
    final db = await DatabaseService.instance.database;
    final bankId = await db.insert('question_banks', {
      'uid': 'local-$name',
      'name': name,
      'file_source': 'local.docx',
      'question_count': titles.length,
      'created_at': '2026-09-01T00:00:00.000',
      'updated_at': '2026-09-01T00:00:00.000',
    });
    for (var i = 0; i < titles.length; i++) {
      await db.insert('questions', {
        'uid': 'local-$name-q$i',
        'bank_id': bankId,
        'title': titles[i],
        'options': jsonEncode(['A', 'B']),
        'correct_answer': 'A',
        'question_type': 'single_choice',
        'source': 'real',
        'created_at': '2026-09-01T00:00:00.000',
        'updated_at': '2026-09-01T00:00:00.000',
      });
    }
    return bankId;
  }

  Future<int> countQuestions(int bankId) async {
    final db = await DatabaseService.instance.database;
    final rows = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM questions WHERE bank_id = ?', [bankId]);
    return (rows.first['c'] as int?) ?? 0;
  }

  final repo = SyncRepository();

  test('不同名题库：照常合并，不产生冲突', () async {
    final conflicts = <SyncBankConflict>[];
    final merged = await repo.importSnapshot(
      peerSnapshot(bankUid: 'p1', bankName: '解剖学', titles: ['题一']),
      conflictSink: conflicts,
    );
    expect(conflicts, isEmpty);
    expect(merged, greaterThan(0));
  });

  test('同名且内容一致：不更新，也不产生冲突', () async {
    await seedLocalBank('解剖学', ['题一', '题二']);
    final conflicts = <SyncBankConflict>[];
    await repo.importSnapshot(
      peerSnapshot(bankUid: 'p1', bankName: '解剖学', titles: ['题一', '题二']),
      conflictSink: conflicts,
    );
    expect(conflicts, isEmpty, reason: '内容一样就该直接跳过');
    // 对端题库不应被插入（只有本机那一份）
    final db = await DatabaseService.instance.database;
    final rows = await db.rawQuery(
        "SELECT COUNT(*) AS c FROM question_banks WHERE name = '解剖学'");
    expect(rows.first['c'], 1);
    // 本机题目数不变
    expect(await countQuestions(1), 2);
  });

  test('同名但内容不同：挂起冲突，本批不动本机数据', () async {
    final bankId = await seedLocalBank('生理学', ['本机题一', '本机题二']);
    final conflicts = <SyncBankConflict>[];
    await repo.importSnapshot(
      peerSnapshot(bankUid: 'p2', bankName: '生理学', titles: ['对端题一']),
      conflictSink: conflicts,
    );
    expect(conflicts, hasLength(1));
    final c = conflicts.first;
    expect(c.name, '生理学');
    expect(c.localBankId, bankId);
    expect(c.localCount, 2);
    expect(c.peerCount, 1);
    expect(c.peerDeviceName, '平板');
    // 未决策前，本机题目不动
    expect(await countQuestions(bankId), 2);
  });

  test('决策「增添」：只并进对端多出来的题，本机已有的不动', () async {
    final bankId = await seedLocalBank('药理学', ['共同题']);
    final conflicts = <SyncBankConflict>[];
    await repo.importSnapshot(
      peerSnapshot(bankUid: 'p3', bankName: '药理学', titles: ['共同题', '对端独有题']),
      conflictSink: conflicts,
    );
    expect(conflicts, hasLength(1));
    expect(conflicts.first.additionCount, 1, reason: '对端只多出一道题');

    final affected =
        await repo.resolveBankConflict(conflicts.first, overwrite: false);
    expect(affected, 1);
    // 本机原有 1 题 + 增添 1 题
    expect(await countQuestions(bankId), 2);
  });

  test('决策「覆盖」：用对端整套替换本机题目', () async {
    final bankId = await seedLocalBank('病理学', ['本机旧题一', '本机旧题二']);
    final conflicts = <SyncBankConflict>[];
    await repo.importSnapshot(
      peerSnapshot(bankUid: 'p4', bankName: '病理学', titles: ['对端新题']),
      conflictSink: conflicts,
    );
    expect(conflicts, hasLength(1));

    final affected =
        await repo.resolveBankConflict(conflicts.first, overwrite: true);
    expect(affected, 1);
    expect(await countQuestions(bankId), 1, reason: '覆盖后只剩对端那一题');

    final db = await DatabaseService.instance.database;
    final rows = await db
        .rawQuery('SELECT title FROM questions WHERE bank_id = ?', [bankId]);
    expect(rows.first['title'], '对端新题');
  });

  test('没有 conflictSink 时保持旧行为（不抛异常、题库照常处理）', () async {
    await seedLocalBank('内科学', ['本机题']);
    await repo.importSnapshot(
      peerSnapshot(bankUid: 'p5', bankName: '内科学', titles: ['对端题']),
    );
  });
}
