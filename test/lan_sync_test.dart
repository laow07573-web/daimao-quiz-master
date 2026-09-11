import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flashcard_app/models/ink_annotation.dart';
import 'package:flashcard_app/models/question.dart';
import 'package:flashcard_app/models/question_bank.dart';
import 'package:flashcard_app/models/quiz_session.dart';
import 'package:flashcard_app/models/answer_record.dart';
import 'package:flashcard_app/services/annotation_service.dart';
import 'package:flashcard_app/services/database_service.dart';
import 'package:flashcard_app/services/device_service.dart';
import 'package:flashcard_app/services/sync/sync_discovery.dart';
import 'package:flashcard_app/services/sync/sync_models.dart';
import 'package:flashcard_app/services/sync/sync_repository.dart';
import 'package:flashcard_app/services/sync/sync_server.dart';

/// 局域网同步测试（v11）：
/// DB v10→v11 迁移、uid upsert 合并、批注/错题按设备隔离、
/// 信标编解码与设备去重、同步服务端交换接口
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DatabaseService.instance.close();
    final dir = Directory(
        Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path);
    final dbPath = '${dir.path}/flashcard_app/test_lan_sync.db';
    DatabaseService.overrideDbPath = dbPath;
    final f = File(dbPath);
    if (await f.exists()) await f.delete();
  });

  tearDown(() async {
    await DatabaseService.instance.close();
    DatabaseService.overrideDbPath = null;
  });

  group('DB v10→v11 迁移', () {
    /// 构造一个 v10 旧库（无 uid / 单列批注主键 / 错题单列唯一）
    Future<String> buildV10Db(String path) async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final old = await databaseFactory.openDatabase(path);
      await old.execute('''
        CREATE TABLE question_banks (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          file_source TEXT,
          question_count INTEGER DEFAULT 0,
          created_at TEXT NOT NULL
        )
      ''');
      await old.execute('''
        CREATE TABLE questions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          bank_id INTEGER NOT NULL,
          title TEXT NOT NULL,
          options TEXT NOT NULL DEFAULT '[]',
          correct_answer TEXT NOT NULL,
          analysis TEXT,
          question_type TEXT DEFAULT 'single_choice',
          source TEXT,
          knowledge_point TEXT,
          created_at TEXT NOT NULL
        )
      ''');
      await old.execute('''
        CREATE TABLE quiz_sessions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          bank_ids TEXT NOT NULL,
          mode TEXT NOT NULL,
          total_questions INTEGER NOT NULL,
          correct_count INTEGER DEFAULT 0,
          wrong_count INTEGER DEFAULT 0,
          start_time TEXT NOT NULL,
          end_time TEXT,
          duration_seconds INTEGER DEFAULT 0,
          source TEXT NOT NULL DEFAULT 'real'
        )
      ''');
      await old.execute('''
        CREATE TABLE session_questions (
          session_id INTEGER NOT NULL,
          position INTEGER NOT NULL,
          question_id INTEGER NOT NULL,
          PRIMARY KEY (session_id, position)
        )
      ''');
      await old.execute('''
        CREATE TABLE answer_records (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          question_id INTEGER NOT NULL,
          session_id INTEGER,
          user_answer TEXT,
          is_correct INTEGER NOT NULL,
          ai_analysis TEXT,
          answered_at TEXT NOT NULL,
          hidden INTEGER NOT NULL DEFAULT 0,
          source TEXT NOT NULL DEFAULT 'real'
        )
      ''');
      await old.execute('''
        CREATE TABLE error_book (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          question_id INTEGER NOT NULL UNIQUE,
          added_at TEXT NOT NULL
        )
      ''');
      await old.execute('''
        CREATE TABLE question_annotations (
          question_id INTEGER PRIMARY KEY,
          data TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
      // 旧数据：1 题库 + 1 题 + 1 会话 + 1 作答 + 1 错题 + 1 批注
      final bankId = await old.insert('question_banks',
          {'name': '旧库', 'question_count': 1, 'created_at': '2025-01-01T00:00:00'});
      final qid = await old.insert('questions', {
        'bank_id': bankId,
        'title': '旧题',
        'correct_answer': 'A',
        'created_at': '2025-01-01T00:00:00',
      });
      final sid = await old.insert('quiz_sessions', {
        'bank_ids': '$bankId',
        'mode': 'single',
        'total_questions': 1,
        'start_time': '2025-01-02T00:00:00',
        'end_time': '2025-01-02T00:10:00',
      });
      await old.insert('session_questions',
          {'session_id': sid, 'position': 0, 'question_id': qid});
      await old.insert('answer_records', {
        'question_id': qid,
        'session_id': sid,
        'user_answer': 'A',
        'is_correct': 1,
        'answered_at': '2025-01-02T00:05:00',
      });
      await old.insert('error_book',
          {'question_id': qid, 'added_at': '2025-01-02T00:06:00'});
      await old.insert('question_annotations',
          {'question_id': qid, 'data': '[[]]', 'updated_at': '2025-01-02T00:07:00'});
      await old.execute('PRAGMA user_version = 10');
      await old.close();
      return path;
    }

    test('迁移：回填 uid / 归属设备，批注复合主键，错题 (题,设备) 唯一', () async {
      // setUp 已删除库文件：直接在此路径上构造 v10 旧库，再交给
      // DatabaseService 以 version 11 打开，触发 onUpgrade(10→11)
      final dir = Directory(
          Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path);
      final path = '${dir.path}/flashcard_app/test_lan_sync.db';
      await buildV10Db(path);

      // 迁移时归属设备取本机标识（注入确定值）
      DeviceService.instance.overrideDeviceId('local-device');
      final migrated = await DatabaseService.instance.database;

      // 版本升到 11
      final version = await migrated.rawQuery('PRAGMA user_version');
      expect(version.first.values.first, 11);

      // uid 全部回填且非空
      final banks = await migrated.rawQuery('SELECT uid, updated_at FROM question_banks');
      expect(banks.first['uid'], isNotNull);
      expect(banks.first['updated_at'], '2025-01-01T00:00:00'); // 回填 created_at
      final questions = await migrated.rawQuery('SELECT uid FROM questions');
      expect(questions.first['uid'], isNotNull);
      final sessions = await migrated.rawQuery('SELECT uid FROM quiz_sessions');
      expect(sessions.first['uid'], isNotNull);
      final records = await migrated.rawQuery(
          'SELECT uid, origin_device FROM answer_records');
      expect(records.first['uid'], isNotNull);
      expect(records.first['origin_device'], 'local-device');

      // session_questions.question_uid 按题目关联回填
      final sq = await migrated.rawQuery('SELECT question_uid FROM session_questions');
      expect(sq.first['question_uid'], questions.first['uid']);

      // 错题：回填 uid + 归属本机
      final errors = await migrated.rawQuery(
          'SELECT uid, origin_device FROM error_book');
      expect(errors.first['uid'], isNotNull);
      expect(errors.first['origin_device'], 'local-device');

      // 新唯一约束：同一题另一设备的错题可共存（旧表 UNIQUE 会冲突）
      final qid = (await migrated.rawQuery('SELECT id FROM questions')).first['id'];
      await migrated.insert('error_book', {
        'question_id': qid,
        'uid': 'remote-uid',
        'origin_device': 'other-device',
        'added_at': '2025-01-03T00:00:00',
      });
      final both = await migrated.rawQuery('SELECT * FROM error_book');
      expect(both.length, 2);

      // 批注：复合主键迁移，既有批注归属本机
      final annos = await migrated.rawQuery(
          'SELECT device_id, data FROM question_annotations');
      expect(annos.first['device_id'], 'local-device');
      // 他端同一题批注可共存
      await migrated.insert('question_annotations', {
        'question_id': qid,
        'device_id': 'other-device',
        'data': '[[]]',
        'updated_at': '2025-01-03T00:00:00',
      });
      final annoBoth = await migrated.rawQuery('SELECT * FROM question_annotations');
      expect(annoBoth.length, 2);
    });
  });

  group('同步快照合并（SyncRepository）', () {
    const remoteDevice = 'device-b';

    test('uid upsert：新则插、已有按 updated_at 取新，重复导入幂等', () async {
      DeviceService.instance.overrideDeviceId('device-a');
      final db = DatabaseService.instance;
      final repo = SyncRepository();
      final bankId = await db.insertBank(
          QuestionBank(name: '共享库', createdAt: '2025-02-01T00:00:00'));
      await db.insertQuestions([
        Question(bankId: bankId, title: '原题', correctAnswer: 'A',
            createdAt: '2025-02-01T00:00:00'),
      ]);
      final bankUid = (await (await db.database).rawQuery(
          'SELECT uid FROM question_banks WHERE id = ?', [bankId])).first['uid'] as String;
      final questionUid = (await (await db.database).rawQuery(
          'SELECT uid FROM questions')).first['uid'] as String;

      // 对端推送同一题库：名字更新（updated_at 更新）→ 采纳
      final snapshot = {
        'protocol': 1,
        'device_id': remoteDevice,
        'banks': [
          {
            'uid': bankUid,
            'name': '共享库(改名)',
            'file_source': null,
            'question_count': 1,
            'created_at': '2025-02-01T00:00:00',
            'updated_at': '2025-02-02T00:00:00',
          }
        ],
        'questions': [
          {
            'uid': questionUid,
            'bank_uid': bankUid,
            'title': '新题面',
            'options': '[]',
            'correct_answer': 'B',
            'analysis': null,
            'question_type': 'single_choice',
            'source': null,
            'knowledge_point': null,
            'created_at': '2025-02-01T00:00:00',
            'updated_at': '2025-02-02T00:00:00',
          }
        ],
        'sessions': <Map<String, dynamic>>[],
        'answer_records': <Map<String, dynamic>>[],
        'error_book': <Map<String, dynamic>>[],
        'annotations': <Map<String, dynamic>>[],
      };
      await repo.importSnapshot(snapshot);
      var rows = await db.getAllBanks();
      expect(rows.length, 1); // 按 uid 合并不产生重复题库
      expect(rows.first.name, '共享库(改名)');
      var qs = await db.getQuestionsByBank(bankId);
      expect(qs.length, 1);
      expect(qs.first.title, '新题面');

      // 对端推送更旧数据（updated_at 更早）→ 不覆盖本机新内容
      snapshot['banks'] = [
        {
          'uid': bankUid,
          'name': '旧名',
          'question_count': 1,
          'created_at': '2025-02-01T00:00:00',
          'updated_at': '2025-02-01T00:00:00',
        }
      ];
      snapshot['questions'] = [
        {
          'uid': questionUid,
          'bank_uid': bankUid,
          'title': '旧题面',
          'options': '[]',
          'correct_answer': 'A',
          'created_at': '2025-02-01T00:00:00',
          'updated_at': '2025-02-01T00:00:00',
        }
      ];
      await repo.importSnapshot(snapshot);
      rows = await db.getAllBanks();
      expect(rows.first.name, '共享库(改名)'); // 保持较新版本
      qs = await db.getQuestionsByBank(bankId);
      expect(qs.first.title, '新题面');

      // 重复导入幂等：实体数不变
      await repo.importSnapshot(snapshot);
      expect((await db.getAllBanks()).length, 1);
      expect((await db.getQuestionsByBank(bankId)).length, 1);

      // 自己的快照不合入（防自合并）
      final mySnap = await repo.exportSnapshot();
      expect(await repo.importSnapshot(mySnap), 0);
    });

    test('批注按设备隔离：两端同题批注互不覆盖，刷题页只见本机', () async {
      DeviceService.instance.overrideDeviceId('device-a');
      final db = DatabaseService.instance;
      final repo = SyncRepository();
      final bankId = await db.insertBank(
          QuestionBank(name: '批注库', createdAt: '2025-02-01T00:00:00'));
      await db.insertQuestions([
        Question(bankId: bankId, title: 'q', correctAnswer: 'A',
            createdAt: '2025-02-01T00:00:00'),
      ]);
      final qid = (await db.getQuestionsByBank(bankId)).first.id!;
      final questionUid = (await (await db.database).rawQuery(
          'SELECT uid FROM questions WHERE id = ?', [qid])).first['uid'] as String;

      // 本机批注
      await AnnotationService.instance.save(qid, [
        InkStroke(pts: [0.1, 0.1, 0.2, 0.2], color: 0xFF212121, width: 2.0),
      ]);

      // 对端同一题推送自己的批注
      await repo.importSnapshot({
        'device_id': remoteDevice,
        'banks': <Map<String, dynamic>>[],
        'questions': <Map<String, dynamic>>[],
        'sessions': <Map<String, dynamic>>[],
        'answer_records': <Map<String, dynamic>>[],
        'error_book': <Map<String, dynamic>>[],
        'annotations': [
          {
            'question_uid': questionUid,
            'device_id': remoteDevice,
            'data': InkStroke.encodeList([
              InkStroke(pts: [0.9, 0.9], color: 0xFF0000FF, width: 5.0),
            ]),
            'updated_at': '2025-02-03T00:00:00',
          }
        ],
      });

      // 两设备批注共存
      final all = await (await db.database)
          .rawQuery('SELECT device_id FROM question_annotations');
      expect(all.length, 2);

      // 刷题页只显示本机批注（他端保留但不显示）
      final local = await AnnotationService.instance.load(qid);
      expect(local.length, 1);
      expect(local.first.color, 0xFF212121);

      // 本机保存不覆盖他端，他端重复推送也不覆盖本机
      await AnnotationService.instance.save(qid, [
        InkStroke(pts: [0.3, 0.3, 0.4, 0.4], color: 0xFF212121, width: 2.0),
      ]);
      await repo.importSnapshot({
        'device_id': remoteDevice,
        'banks': <Map<String, dynamic>>[],
        'questions': <Map<String, dynamic>>[],
        'sessions': <Map<String, dynamic>>[],
        'answer_records': <Map<String, dynamic>>[],
        'error_book': <Map<String, dynamic>>[],
        'annotations': [
          {
            'question_uid': questionUid,
            'device_id': remoteDevice,
            'data': InkStroke.encodeList([
              InkStroke(pts: [0.8, 0.8], color: 0xFF00FF00, width: 5.0),
            ]),
            'updated_at': '2025-02-04T00:00:00',
          }
        ],
      });
      final after = await (await db.database).rawQuery(
          'SELECT device_id, data FROM question_annotations ORDER BY device_id');
      expect(after.length, 2); // 仍各一行，互不覆盖
      final localAfter = await AnnotationService.instance.load(qid);
      expect(localAfter.first.pts.first, closeTo(0.3, 1e-9)); // 本机最新笔迹
    });

    test('错题按 (题,设备) 共存；作答记录按 uid 合并并映射本地外键', () async {
      DeviceService.instance.overrideDeviceId('device-a');
      final db = DatabaseService.instance;
      final repo = SyncRepository();
      final bankId = await db.insertBank(
          QuestionBank(name: '错题库', createdAt: '2025-02-01T00:00:00'));
      await db.insertQuestions([
        Question(bankId: bankId, title: 'q', correctAnswer: 'A',
            createdAt: '2025-02-01T00:00:00'),
      ]);
      final qid = (await db.getQuestionsByBank(bankId)).first.id!;
      final questionUid = (await (await db.database).rawQuery(
          'SELECT uid FROM questions WHERE id = ?', [qid])).first['uid'] as String;

      await db.addToErrorBook(qid); // 本机收藏

      // 对端会话 + 作答 + 同一题错题
      final remoteSessionUid = 'sess-uid-1';
      await repo.importSnapshot({
        'device_id': remoteDevice,
        'banks': <Map<String, dynamic>>[],
        'questions': <Map<String, dynamic>>[],
        'sessions': [
          {
            'uid': remoteSessionUid,
            'bank_ids': '',
            'mode': 'single',
            'total_questions': 1,
            'correct_count': 0,
            'wrong_count': 1,
            'start_time': '2025-02-02T10:00:00',
            'end_time': '2025-02-02T10:05:00',
            'duration_seconds': 300,
            'source': 'real',
          }
        ],
        'answer_records': [
          {
            'uid': 'rec-uid-1',
            'question_uid': questionUid,
            'session_uid': remoteSessionUid,
            'user_answer': 'B',
            'is_correct': 0,
            'ai_analysis': null,
            'answered_at': '2025-02-02T10:03:00',
            'hidden': 0,
            'source': 'real',
            'origin_device': remoteDevice,
          }
        ],
        'error_book': [
          {
            'uid': 'err-uid-1',
            'question_uid': questionUid,
            'origin_device': remoteDevice,
            'added_at': '2025-02-02T10:04:00',
          }
        ],
        'annotations': <Map<String, dynamic>>[],
      });

      // 错题共存：本机 + 对端同一题各一行
      final errors = await (await db.database).rawQuery(
          'SELECT origin_device FROM error_book ORDER BY origin_device');
      expect(errors.length, 2);
      expect(errors.map((e) => e['origin_device']).toList(),
          ['device-a', remoteDevice]);

      // 本机移出错题本不误删他端记录
      await db.removeFromErrorBook(qid);
      final afterRemove = await (await db.database).rawQuery(
          'SELECT origin_device FROM error_book');
      expect(afterRemove.length, 1);
      expect(afterRemove.first['origin_device'], remoteDevice);
      expect(await db.isInErrorBook(qid), isFalse); // 本机状态已取消

      // 作答记录：uid 映射本地题目/会话，统计口径计入
      final raw = await (await db.database).rawQuery(
          'SELECT question_id, session_id, origin_device FROM answer_records');
      expect(raw.length, 1);
      expect(raw.first['question_id'], qid);
      expect(raw.first['session_id'], isNotNull); // 会话已按 uid 落地
      expect(raw.first['origin_device'], remoteDevice);
      final stats = await db.getQuestionStats(qid);
      expect(stats['total'], 1);

      // 重复导入幂等（错题不再新增、作答不新增）
      await repo.importSnapshot({
        'device_id': remoteDevice,
        'banks': <Map<String, dynamic>>[],
        'questions': <Map<String, dynamic>>[],
        'sessions': [
          {
            'uid': remoteSessionUid,
            'bank_ids': '',
            'mode': 'single',
            'total_questions': 1,
            'correct_count': 0,
            'wrong_count': 1,
            'start_time': '2025-02-02T10:00:00',
            'end_time': '2025-02-02T10:05:00',
            'duration_seconds': 300,
            'source': 'real',
          }
        ],
        'answer_records': [
          {
            'uid': 'rec-uid-1',
            'question_uid': questionUid,
            'session_uid': remoteSessionUid,
            'user_answer': 'B',
            'is_correct': 0,
            'answered_at': '2025-02-02T10:03:00',
            'hidden': 0,
            'source': 'real',
            'origin_device': remoteDevice,
          }
        ],
        'error_book': [
          {
            'uid': 'err-uid-1',
            'question_uid': questionUid,
            'origin_device': remoteDevice,
            'added_at': '2025-02-02T10:04:00',
          }
        ],
        'annotations': <Map<String, dynamic>>[],
      });
      expect((await (await db.database).rawQuery(
          'SELECT COUNT(*) AS c FROM answer_records')).first['c'], 1);
      expect((await (await db.database).rawQuery(
          'SELECT COUNT(*) AS c FROM error_book')).first['c'], 1);
      expect((await (await db.database).rawQuery(
          'SELECT COUNT(*) AS c FROM quiz_sessions')).first['c'], 1);
    });

    test('导出快照：uid/bank_uid 关联、bank_ids 按 uid 对应、模拟数据不同步',
        () async {
      DeviceService.instance.overrideDeviceId('device-a');
      final db = DatabaseService.instance;
      final repo = SyncRepository();
      final bankId = await db.insertBank(
          QuestionBank(name: '导出库', createdAt: '2025-02-01T00:00:00'));
      await db.insertQuestions([
        Question(bankId: bankId, title: 'q', correctAnswer: 'A',
            createdAt: '2025-02-01T00:00:00'),
      ]);
      final q = (await db.getQuestionsByBank(bankId)).first;
      final bankUid = (await (await db.database).rawQuery(
          'SELECT uid FROM question_banks WHERE id = ?', [bankId])).first['uid'] as String;

      // 完成的真实会话（bank_ids 本地 id）+ 模拟会话（不应导出）
      await db.insertSession(QuizSession(
        bankIds: '$bankId',
        mode: 'single',
        totalQuestions: 1,
        startTime: '2025-02-02T10:00:00',
        endTime: '2025-02-02T10:05:00',
      ));
      final simId = await db.insertSession(QuizSession(
        bankIds: 'simulation',
        mode: 'single',
        totalQuestions: 1,
        startTime: '2025-02-03T10:00:00',
        endTime: '2025-02-03T10:05:00',
      ));
      await (await db.database)
          .update('quiz_sessions', {'source': 'simulation'},
              where: 'id = ?', whereArgs: [simId]);
      await db.insertAnswerRecord(AnswerRecord(
        questionId: q.id!,
        isCorrect: true,
        userAnswer: 'A',
        answeredAt: '2025-02-02T10:03:00',
      ));

      final snap = await repo.exportSnapshot();
      expect(snap['device_id'], 'device-a');
      final banks = snap['banks'] as List;
      expect(banks.length, 1);
      expect(banks.first['uid'], bankUid);
      final questions = snap['questions'] as List;
      expect(questions.first['bank_uid'], bankUid);
      // bank_ids 按 uid 对应（本地数字 id 已替换）
      final sessions = snap['sessions'] as List;
      expect(sessions.length, 1); // 模拟会话不导出
      expect(sessions.first['bank_ids'], bankUid);
      // 作答记录带 question_uid + origin_device
      final records = snap['answer_records'] as List;
      expect(records.first['question_uid'],
          (await (await db.database).rawQuery(
              'SELECT uid FROM questions WHERE id = ?', [q.id])).first['uid']);
      expect(records.first['origin_device'], 'device-a');
    });
  });

  group('设备发现（信标）', () {
    test('信标编解码往返 + 他应用/垃圾数据拒绝', () {
      final beacon = SyncBeacon(
          deviceId: 'dev-1', deviceName: '猫卷-Android', port: 51630);
      final decoded = SyncBeacon.decode(beacon.encode());
      expect(decoded, isNotNull);
      expect(decoded!.deviceId, 'dev-1');
      expect(decoded.deviceName, '猫卷-Android');
      expect(decoded.port, 51630);

      expect(SyncBeacon.decode('{"app":"other_app"}'), isNull);
      expect(SyncBeacon.decode('garbage'), isNull);
      expect(SyncBeacon.decode(''), isNull);
      // 缺 device_id / 非法端口拒绝
      expect(SyncBeacon.decode('{"app":"flashcard_sync","port":1}'), isNull);
      expect(
          SyncBeacon.decode(
              '{"app":"flashcard_sync","device_id":"x","port":0}'),
          isNull);
    });

    test('设备去重：同设备重复信标不新增；自己信标忽略', () {
      final discovery = SyncDiscovery();
      discovery.selfDeviceIdForTest = 'self-device';
      var discovered = 0;
      var changed = 0;
      discovery.onPeerDiscovered = (_) => discovered++;
      discovery.onPeersChanged = () => changed++;

      final peerBeacon = const SyncBeacon(
          deviceId: 'peer-1', deviceName: '平板', port: 51630);
      discovery.handleDatagram(
          Uint8List.fromList(utf8.encode(peerBeacon.encode())),
          InternetAddress('192.168.1.2'));
      expect(discovery.peers.length, 1);
      expect(discovered, 1);
      expect(changed, 1);

      // 重复信标：去重（仅刷新 lastSeen），不重复触发发现
      discovery.handleDatagram(
          Uint8List.fromList(utf8.encode(peerBeacon.encode())),
          InternetAddress('192.168.1.2'));
      expect(discovery.peers.length, 1);
      expect(discovered, 1);

      // 自己的信标回环忽略
      final selfBeacon = const SyncBeacon(
          deviceId: 'self-device', deviceName: '本机', port: 51630);
      discovery.handleDatagram(
          Uint8List.fromList(utf8.encode(selfBeacon.encode())),
          InternetAddress('192.168.1.1'));
      expect(discovery.peers.length, 1);

      // 改名触发变更通知
      final renamed = const SyncBeacon(
          deviceId: 'peer-1', deviceName: '平板-新名', port: 51630);
      discovery.handleDatagram(
          Uint8List.fromList(utf8.encode(renamed.encode())),
          InternetAddress('192.168.1.2'));
      expect(discovery.peers.length, 1);
      expect(discovery.peers.first.deviceName, '平板-新名');
      expect(changed, 2);
    });
  });

  group('同步服务端（SyncServer）', () {
    test('exchange 接口：收对端快照合并、响应返回本机快照', () async {
      final server = SyncServer();
      Map<String, dynamic>? received;
      await server.start(
        onReceived: (snap) async => received = snap,
        snapshot: () async => {'device_id': 'self', 'banks': <dynamic>[]},
      );
      expect(server.port, greaterThan(0));

      final client = http.Client();
      try {
        final peerSnap = {
          'device_id': 'peer-x',
          'banks': [
            {'uid': 'b1', 'name': '对端库', 'question_count': 3}
          ],
        };
        final resp = await client.post(
          Uri.parse('http://127.0.0.1:${server.port}/sync/exchange'),
          headers: {'Content-Type': 'application/json'},
          body: utf8.encode(jsonEncode(peerSnap)),
        );
        expect(resp.statusCode, 200);
        // 对端数据已交给合并回调
        expect(received, isNotNull);
        expect(received!['device_id'], 'peer-x');
        // 响应体是本机快照（对端据此合并，一次请求双向同步）
        final body = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
        expect(body['device_id'], 'self');

        // info 接口返回设备信息
        final info = await client
            .get(Uri.parse('http://127.0.0.1:${server.port}/sync/info'));
        expect(info.statusCode, 200);
        expect(
            (jsonDecode(utf8.decode(info.bodyBytes)) as Map)['device_name'],
            isNotNull);

        // 非法 body 拒绝
        final bad = await client.post(
          Uri.parse('http://127.0.0.1:${server.port}/sync/exchange'),
          body: 'not json',
        );
        expect(bad.statusCode, 400);
      } finally {
        client.close();
        await server.stop();
      }
    });
  });
}
