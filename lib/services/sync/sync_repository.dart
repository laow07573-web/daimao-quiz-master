import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../database_service.dart';
import '../debug_log_service.dart';
import '../device_service.dart';
import '../../models/question_image.dart';
import 'sync_models.dart';

/// 局域网同步：快照导出与合并入库
///
/// 合并规则：
/// - 题库/题目/会话/作答记录：按全局 `uid` upsert（新则插、已有按时间取新）
/// - 批注：按 `(题目, 设备)` 隔离，他端批注存其 `device_id` 下，绝不覆盖本机批注
/// - 错题：按 `(题目, 来源设备)` 共存，两端同一题错题互不覆盖
/// - 本地外键（bank_id/question_id/session_id）导入时按 uid 映射为本地自增 id；
///   孤儿引用（对应实体未同步到）跳过，不产生悬空记录
class SyncRepository {
  static const int protocolVersion = 1;

  final DatabaseService _db = DatabaseService.instance;

  /// 导出本机同步快照。
  ///
  /// [banksOnly] = true 时**只导出题库与题目（含配图）**，不带刷题会话、
  /// 作答记录、错题本与批注——这是 2026-10-08 用户要的「只同步题库」模式，
  /// 设计目标是用户之间互相分享题库，不该把自己的学习记录一并交出去。
  ///
  /// [banksOnly] = false 时是整库快照（局域网数据量小，全量合并；
  /// 模拟数据与未完成会话不参与同步）。
  Future<Map<String, dynamic>> exportSnapshot({bool banksOnly = false}) async {
    final db = await _db.database;
    final deviceId = await DeviceService.instance.deviceId;
    final deviceName = await DeviceService.instance.deviceName;

    final banks = await db.rawQuery('''
      SELECT uid, name, file_source, question_count, created_at,
             COALESCE(updated_at, created_at) AS updated_at
      FROM question_banks
    ''');

    final questions = await db.rawQuery('''
      SELECT q.uid AS uid, qb.uid AS bank_uid, q.title, q.options,
             q.correct_answer, q.analysis, q.question_type, q.source,
             q.knowledge_point, q.created_at,
             COALESCE(q.updated_at, q.created_at) AS updated_at
      FROM questions q
      JOIN question_banks qb ON qb.id = q.bank_id
    ''');

    // v12 配图随题同步（图片是题目的一部分）：BLOB 转 base64 走 JSON
    final images = (await db.rawQuery('''
      SELECT q.uid AS question_uid, qi.position, qi.mime, qi.width, qi.height,
             qi.anchor, qi.content
      FROM question_images qi
      JOIN questions q ON q.id = qi.question_id
      ORDER BY q.uid, qi.position
    ''')).map((r) {
      final m = Map<String, dynamic>.from(r);
      final content = m['content'];
      m['content'] = content is List<int> ? base64Encode(content) : '';
      return m;
    }).toList();

    // 仅题库：到这里就结束，记录类数据一律不出门
    if (banksOnly) {
      return {
        'protocol': protocolVersion,
        'device_id': deviceId,
        'device_name': deviceName,
        'scope': 'banks',
        'banks': banks,
        'questions': questions,
        'question_images': images,
        'sessions': const [],
        'answer_records': const [],
        'error_book': const [],
        'annotations': const [],
      };
    }

    // 本地题库 id → uid（会话的 bank_ids 文本导出时按 uid 对应）
    final bankRows = await db.rawQuery('SELECT id, uid FROM question_banks');
    final bankUidById = <int, String>{
      for (final r in bankRows)
        if (r['uid'] != null) r['id'] as int: r['uid'] as String,
    };

    // 只同步已完成（有 end_time）的真实会话；模拟数据不跨设备
    final sessionRows = await db.rawQuery('''
      SELECT uid, bank_ids, mode, total_questions, correct_count, wrong_count,
             start_time, end_time, duration_seconds, source
      FROM quiz_sessions
      WHERE source = 'real' AND end_time IS NOT NULL AND end_time != ''
    ''');
    final sessions = sessionRows.map((r) {
      final m = Map<String, dynamic>.from(r);
      m['bank_ids'] =
          _mapBankIdsToUids(m['bank_ids'] as String? ?? '', bankUidById);
      return m;
    }).toList();

    final records = await db.rawQuery('''
      SELECT ar.uid AS uid, q.uid AS question_uid, qs.uid AS session_uid,
             ar.user_answer, ar.is_correct, ar.ai_analysis, ar.answered_at,
             ar.hidden, ar.source, ar.origin_device
      FROM answer_records ar
      JOIN questions q ON q.id = ar.question_id
      LEFT JOIN quiz_sessions qs ON qs.id = ar.session_id
      WHERE ar.source = 'real'
    ''');

    final errors = await db.rawQuery('''
      SELECT eb.uid AS uid, q.uid AS question_uid, eb.origin_device, eb.added_at
      FROM error_book eb
      JOIN questions q ON q.id = eb.question_id
    ''');

    final annotations = await db.rawQuery('''
      SELECT qa.device_id, q.uid AS question_uid, qa.data, qa.updated_at
      FROM question_annotations qa
      JOIN questions q ON q.id = qa.question_id
    ''');

    return {
      'protocol': protocolVersion,
      'device_id': deviceId,
      'device_name': deviceName,
      'banks': banks,
      'questions': questions,
      'question_images': images,
      'sessions': sessions,
      'answer_records': records,
      'error_book': errors,
      'annotations': annotations,
    };
  }

  /// bank_ids 文本中的本地数字 id 替换为题库 uid；非数字标记
  /// （'simulation'/'all' 等）原样保留
  String _mapBankIdsToUids(String bankIds, Map<int, String> bankUidById) {
    if (bankIds.isEmpty) return bankIds;
    return bankIds.split(',').map((token) {
      final id = int.tryParse(token);
      if (id == null) return token;
      return bankUidById[id] ?? token;
    }).join(',');
  }

  /// 反向：bank_ids 文本中的题库 uid 还原为本地数字 id
  String _mapUidsToBankIds(String bankIds, Map<String, int> bankLocalByUid) {
    if (bankIds.isEmpty) return bankIds;
    return bankIds.split(',').map((token) {
      final id = bankLocalByUid[token];
      return id != null ? '$id' : token;
    }).join(',');
  }

  /// 本机某题库的**题目内容指纹**集合（用于同名题库比对）。
  ///
  /// 指纹只取「题目本身的内容」——题干、选项、答案、题型、知识点，
  /// 外加配图的槽位与内容摘要；不含 uid、时间戳这类每端都会不同的字段，
  /// 否则同名题库永远判为「不一样」。
  Future<Set<String>> _questionFingerprints(
      DatabaseExecutor txn, int bankId) async {
    final rows = await txn.rawQuery('''
      SELECT q.uid AS uid, q.title, q.options, q.correct_answer, q.analysis,
             q.question_type, q.knowledge_point
      FROM questions q WHERE q.bank_id = ?
    ''', [bankId]);
    final imagesByQuestion = <String, List<String>>{};
    final imgRows = await txn.rawQuery('''
      SELECT q.uid AS q_uid, qi.position, qi.mime, qi.anchor, qi.content
      FROM question_images qi
      JOIN questions q ON q.id = qi.question_id
      WHERE q.bank_id = ?
    ''', [bankId]);
    for (final r in imgRows) {
      final qUid = r['q_uid'] as String? ?? '';
      imagesByQuestion.putIfAbsent(qUid, () => []).add(
          _imageSignature(r['position'], r['mime'], r['anchor'], r['content']));
    }
    return {
      for (final r in rows)
        _questionSignature(r, imagesByQuestion[r['uid'] as String? ?? '']),
    };
  }

  /// 对端快照里某题库的题目内容指纹集合
  Set<String> _fingerprintsOf(
    List<Map<String, dynamic>> questions,
    Map<String, List<Map<String, dynamic>>> imagesByQuestion,
  ) {
    return {
      for (final q in questions)
        _questionSignature(
          q,
          (imagesByQuestion[q['uid']] ?? const [])
              .map((i) => _imageSignature(
                  i['position'], i['mime'], i['anchor'], i['content']))
              .toList(),
        ),
    };
  }

  static String _questionSignature(
      Map<String, dynamic> q, List<String>? imageSigs) {
    final parts = [
      (q['title'] ?? '').toString(),
      (q['options'] ?? '').toString(),
      (q['correct_answer'] ?? '').toString(),
      (q['question_type'] ?? '').toString(),
      (q['knowledge_point'] ?? '').toString(),
    ];
    final imgs = [...?imageSigs]..sort();
    return sha1
        .convert(
            utf8.encode('${parts.join('\u0001')}\u0002${imgs.join('\u0001')}'))
        .toString();
  }

  static String _imageSignature(
      Object? position, Object? mime, Object? anchor, Object? content) {
    // 本机是 BLOB，对端快照是 base64 —— 统一成字节再取摘要
    List<int> bytes;
    if (content is List<int>) {
      bytes = content;
    } else if (content is String) {
      bytes = _tryBase64(content);
    } else {
      bytes = const [];
    }
    final digest = sha1.convert(bytes).toString();
    return '${position ?? ''}|${mime ?? ''}|${anchor ?? ''}|$digest';
  }

  static List<int> _tryBase64(String s) {
    try {
      return base64Decode(s);
    } catch (_) {
      return utf8.encode(s);
    }
  }

  /// 落地一条同名题库冲突（用户在首页做的决定）。
  ///
  /// [overwrite] = true → 用对端题库整行替换本机同名题库（题目/配图全换）；
  /// false → 「增添」：只把**对端多出来**的题目并进本机该题库
  /// （按内容指纹去重，本机已有的题不动）。
  /// 返回受影响的题目数。
  Future<int> resolveBankConflict(SyncBankConflict conflict,
      {required bool overwrite}) async {
    final db = await _db.database;
    final now = DateTime.now().toIso8601String();
    var affected = 0;

    await db.transaction((txn) async {
      final localBankId = conflict.localBankId;
      if (overwrite) {
        // 覆盖：清掉本机该题库的题目与配图，再把对端的整套写进来
        await txn.delete('question_images',
            where:
                'question_id IN (SELECT id FROM questions WHERE bank_id = ?)',
            whereArgs: [localBankId]);
        await txn.delete('questions',
            where: 'bank_id = ?', whereArgs: [localBankId]);
        // 题库行本身更新为对端的名称/来源等
        await txn.update(
          'question_banks',
          {
            'name': conflict.peerBank['name'] ?? conflict.name,
            'file_source': conflict.peerBank['file_source'],
            'question_count': conflict.peerBank['question_count'] ?? 0,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [localBankId],
        );
      }

      // 现有指纹（覆盖模式下此时为空集）
      final existing = await _questionFingerprints(txn, localBankId);
      final imagesByQuestion = <String, List<Map<String, dynamic>>>{};
      for (final img in conflict.peerImages) {
        final qUid = img['question_uid'] as String?;
        if (qUid == null || qUid.isEmpty) continue;
        imagesByQuestion.putIfAbsent(qUid, () => []).add(img);
      }

      for (final q in conflict.peerQuestions) {
        final fp = _questionSignature(
          q,
          (imagesByQuestion[q['uid']] ?? const [])
              .map((i) => _imageSignature(
                  i['position'], i['mime'], i['anchor'], i['content']))
              .toList(),
        );
        if (!overwrite && existing.contains(fp)) continue; // 增添：本机已有则跳过
        final qid = await _db.upsertQuestionByUid(txn, {
          'uid': q['uid'],
          'bank_id': localBankId,
          'title': q['title'] ?? '',
          'options': q['options'] ?? '[]',
          'correct_answer': q['correct_answer'] ?? '',
          'analysis': q['analysis'],
          'question_type': q['question_type'] ?? 'single_choice',
          'source': q['source'],
          'knowledge_point': q['knowledge_point'],
          'created_at': q['created_at'] ?? now,
          'updated_at': q['updated_at'],
        });
        affected++;
        // 配图随题：首写槽位生效，不覆盖本机已有槽位
        for (final img in imagesByQuestion[q['uid']] ?? const []) {
          final raw = img['content'];
          final bytes = raw is String ? _tryBase64(raw) : <int>[];
          if (bytes.isEmpty) continue;
          // 事务内直接写（mergeQuestionImages 用的是全局 batch，不能嵌事务）
          await txn.insert(
            'question_images',
            {
              'question_id': qid,
              'position': (img['position'] as num?)?.toInt() ?? 0,
              'mime': (img['mime'] ?? 'image/jpeg').toString(),
              'width': (img['width'] as num?)?.toInt() ?? 0,
              'height': (img['height'] as num?)?.toInt() ?? 0,
              'anchor': img['anchor'],
              'content': Uint8List.fromList(bytes),
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      }

      // 题目数变了，题库行的计数跟着更新
      final countRows = await txn.rawQuery(
          'SELECT COUNT(*) AS c FROM questions WHERE bank_id = ?',
          [localBankId]);
      final count = (countRows.first['c'] as int?) ?? 0;
      await txn.update('question_banks', {'question_count': count},
          where: 'id = ?', whereArgs: [localBankId]);
    });

    DebugLogService.instance.log('SYNC',
        '同名题库「${conflict.name}」已${overwrite ? '覆盖' : '增添'}，影响 $affected 题');
    return affected;
  }

  /// 合并对端快照入库（单事务）。返回处理的实体数；
  /// 快照来自本机（device_id 相同）时直接跳过。
  ///
  /// [conflictSink] 非空时，遇到**同名但内容不同**的题库会把冲突收集进去
  /// （2026-10-09 用户要求：一样就不更新，不一样就提示覆盖或增添）。
  /// 冲突题库及其题目在本批中**不合并**，等用户决策后走
  /// [resolveBankConflict] 落地。
  Future<int> importSnapshot(
    Map<String, dynamic> snapshot, {
    List<SyncBankConflict>? conflictSink,
  }) async {
    final deviceId = await DeviceService.instance.deviceId;
    if (snapshot['device_id'] == deviceId) return 0; // 不合并自己的快照
    final db = await _db.database;
    final now = DateTime.now().toIso8601String();
    var merged = 0;

    // 对端题库按 uid 归档，便于同名比对时取到它名下的题目与配图
    final peerQuestionsByBank = <String, List<Map<String, dynamic>>>{};
    for (final raw in (snapshot['questions'] as List? ?? const [])) {
      final m = Map<String, dynamic>.from(raw as Map);
      final bankUid = m['bank_uid'] as String?;
      if (bankUid == null || bankUid.isEmpty) continue;
      peerQuestionsByBank.putIfAbsent(bankUid, () => []).add(m);
    }
    final peerImagesByQuestion = <String, List<Map<String, dynamic>>>{};
    for (final raw in (snapshot['question_images'] as List? ?? const [])) {
      final m = Map<String, dynamic>.from(raw as Map);
      final qUid = m['question_uid'] as String?;
      if (qUid == null || qUid.isEmpty) continue;
      peerImagesByQuestion.putIfAbsent(qUid, () => []).add(m);
    }

    await db.transaction((txn) async {
      // 1. 题库
      final bankLocalByUid = <String, int>{};
      // 同名冲突 / 内容一致的题库：本批跳过它们的题库行与题目
      final deferredBankUids = <String>{};
      for (final raw in (snapshot['banks'] as List? ?? const [])) {
        final m = Map<String, dynamic>.from(raw as Map);
        final uid = m['uid'] as String?;
        if (uid == null || uid.isEmpty) continue;
        final name = (m['name'] ?? '').toString();

        // 同名检测：uid 不同但题库名相同 → 先比内容
        final sameName = await txn.query(
          'question_banks',
          columns: ['id', 'uid'],
          where: 'name = ?',
          whereArgs: [name],
          limit: 1,
        );
        if (sameName.isNotEmpty && sameName.first['uid'] != uid) {
          final localBankId = sameName.first['id'] as int;
          final peerQuestions = peerQuestionsByBank[uid] ?? const [];
          final localFp = await _questionFingerprints(txn, localBankId);
          final peerFp = _fingerprintsOf(
            peerQuestions,
            peerImagesByQuestion,
          );
          if (localFp.length == peerFp.length && localFp.containsAll(peerFp)) {
            // ① 内容完全一致 → 不更新（用户要求：若一样则不更新）
            deferredBankUids.add(uid);
            DebugLogService.instance.log('SYNC', '同名题库「$name」内容一致，跳过');
            continue;
          }
          // ② 内容不同 → 挂起冲突，等用户在首页选择覆盖或增添
          deferredBankUids.add(uid);
          final addition = peerFp.difference(localFp).length;
          conflictSink?.add(SyncBankConflict(
            name: name,
            peerBankUid: uid,
            peerBank: m,
            peerQuestions:
                peerQuestions.map((e) => Map<String, dynamic>.from(e)).toList(),
            peerImages: [
              for (final q in peerQuestions)
                ...(peerImagesByQuestion[q['uid']] ?? const []),
            ],
            localBankId: localBankId,
            localCount: localFp.length,
            peerCount: peerFp.length,
            additionCount: addition,
            peerDeviceName: (snapshot['device_name'] ?? '').toString(),
          ));
          DebugLogService.instance.log('SYNC',
              '同名题库「$name」内容不同（本机 ${localFp.length} / 对端 ${peerFp.length}），已挂起待决策');
          continue;
        }

        bankLocalByUid[uid] = await _db.upsertBankByUid(txn, {
          'uid': uid,
          'name': name,
          'file_source': m['file_source'],
          'question_count': m['question_count'] ?? 0,
          'created_at': m['created_at'] ?? now,
          'updated_at': m['updated_at'],
        });
        merged++;
      }

      // 2. 题目（bank_uid 映射为本地 bank_id；未知题库的题跳过）
      final questionLocalByUid = <String, int>{};
      for (final raw in (snapshot['questions'] as List? ?? const [])) {
        final m = Map<String, dynamic>.from(raw as Map);
        final uid = m['uid'] as String?;
        if (uid == null || uid.isEmpty) continue;
        final bankUid = m['bank_uid'] as String?;
        // 同名冲突/内容一致题库的题目本批不落库
        if (bankUid != null && deferredBankUids.contains(bankUid)) continue;
        final id = await _db.upsertQuestionByUid(txn, {
          'uid': uid,
          'bank_id': bankUid != null ? bankLocalByUid[bankUid] : null,
          'title': m['title'] ?? '',
          'options': m['options'] ?? '[]',
          'correct_answer': m['correct_answer'] ?? '',
          'analysis': m['analysis'],
          'question_type': m['question_type'] ?? 'single_choice',
          'source': m['source'],
          'knowledge_point': m['knowledge_point'],
          'created_at': m['created_at'] ?? now,
          'updated_at': m['updated_at'],
        });
        if (id > 0) questionLocalByUid[uid] = id;
        merged++;
      }

      // 兜底：对端引用了更早同步过的实体（本批未重发）时按库内 uid 查
      Future<int?> questionIdByUid(String? uid) async {
        if (uid == null || uid.isEmpty) return null;
        final cached = questionLocalByUid[uid];
        if (cached != null) return cached;
        final row = await _db.questionRowByUid(txn, uid);
        if (row == null) return null;
        questionLocalByUid[uid] = row['id'] as int;
        return questionLocalByUid[uid];
      }

      // 2b. 题目配图（图片是题目的一部分，随题合并）。
      //     首写槽位生效、不覆盖本机已有——本地题目文本的占位符与本地
      //     图片槽位是对齐的，覆盖会错位；删除型差异不跨设备传播
      for (final raw in (snapshot['question_images'] as List? ?? const [])) {
        final m = Map<String, dynamic>.from(raw as Map);
        final questionId = await questionIdByUid(m['question_uid'] as String?);
        if (questionId == null) continue;
        final data = m['content'];
        Uint8List bytes;
        try {
          bytes = data is String ? base64Decode(data) : Uint8List(0);
        } catch (_) {
          continue;
        }
        if (bytes.isEmpty) continue;
        await _db.mergeQuestionImages(questionId, [
          QuestionImage(
            position: (m['position'] as num?)?.toInt() ?? 0,
            mime: m['mime'] as String? ?? 'image/jpeg',
            width: (m['width'] as num?)?.toInt() ?? 0,
            height: (m['height'] as num?)?.toInt() ?? 0,
            anchor: m['anchor'] as String?,
            content: bytes,
          ),
        ]);
        merged++;
      }

      // 3. 会话（bank_ids 的 uid 还原为本地 id）
      final sessionLocalByUid = <String, int>{};
      for (final raw in (snapshot['sessions'] as List? ?? const [])) {
        final m = Map<String, dynamic>.from(raw as Map);
        final uid = m['uid'] as String?;
        if (uid == null || uid.isEmpty) continue;
        sessionLocalByUid[uid] = await _db.upsertSessionByUid(txn, {
          'uid': uid,
          'bank_ids':
              _mapUidsToBankIds(m['bank_ids'] as String? ?? '', bankLocalByUid),
          'mode': m['mode'] ?? 'single',
          'total_questions': m['total_questions'] ?? 0,
          'correct_count': m['correct_count'] ?? 0,
          'wrong_count': m['wrong_count'] ?? 0,
          'start_time': m['start_time'] ?? now,
          'end_time': m['end_time'],
          'duration_seconds': m['duration_seconds'] ?? 0,
          'source': m['source'] ?? 'real',
        });
        merged++;
      }

      // 4. 作答记录（题目/会话 uid 映射；孤儿记录跳过）
      for (final raw in (snapshot['answer_records'] as List? ?? const [])) {
        final m = Map<String, dynamic>.from(raw as Map);
        final uid = m['uid'] as String?;
        if (uid == null || uid.isEmpty) continue;
        final questionId = await questionIdByUid(m['question_uid'] as String?);
        if (questionId == null) continue;
        final sessionUid = m['session_uid'] as String?;
        int? sessionId =
            sessionUid != null ? sessionLocalByUid[sessionUid] : null;
        if (sessionId == null && sessionUid != null && sessionUid.isNotEmpty) {
          final row = await _db.sessionRowByUid(txn, sessionUid);
          sessionId = row?['id'] as int?;
        }
        await _db.upsertAnswerRecordByUid(txn, {
          'uid': uid,
          'question_id': questionId,
          'session_id': sessionId,
          'user_answer': m['user_answer'],
          'is_correct': m['is_correct'] ?? 0,
          'ai_analysis': m['ai_analysis'],
          'answered_at': m['answered_at'] ?? now,
          'hidden': m['hidden'] ?? 0,
          'source': m['source'] ?? 'real',
          'origin_device': m['origin_device'] ?? snapshot['device_id'],
        });
        merged++;
      }

      // 5. 错题（按 题+来源设备 共存，两端各自保留）
      for (final raw in (snapshot['error_book'] as List? ?? const [])) {
        final m = Map<String, dynamic>.from(raw as Map);
        final questionId = await questionIdByUid(m['question_uid'] as String?);
        if (questionId == null) continue;
        await _db.upsertErrorBookEntry(txn, {
          'question_id': questionId,
          'uid': m['uid'],
          'origin_device': (m['origin_device'] as String?)?.isNotEmpty == true
              ? m['origin_device']
              : snapshot['device_id'],
          'added_at': m['added_at'] ?? now,
        });
        merged++;
      }

      // 6. 批注（按 题+设备 隔离：他端批注存其 device_id 下，
      //    绝不覆盖本机批注）
      for (final raw in (snapshot['annotations'] as List? ?? const [])) {
        final m = Map<String, dynamic>.from(raw as Map);
        final questionId = await questionIdByUid(m['question_uid'] as String?);
        if (questionId == null) continue;
        final owner = m['device_id'] as String?;
        if (owner == null || owner.isEmpty) continue;
        await _db.upsertAnnotationByDevice(txn, {
          'question_id': questionId,
          'device_id': owner,
          'data': m['data'] ?? '',
          'updated_at': m['updated_at'] ?? now,
        });
        merged++;
      }
    });
    return merged;
  }
}
