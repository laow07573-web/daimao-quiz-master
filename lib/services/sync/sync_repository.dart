import '../database_service.dart';
import '../device_service.dart';

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

  /// 导出本机全量同步快照（局域网数据量小，全量合并；
  /// 模拟数据与未完成会话不参与同步）
  Future<Map<String, dynamic>> exportSnapshot() async {
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

    // 本地题库 id → uid（会话的 bank_ids 文本导出时按 uid 对应）
    final bankRows =
        await db.rawQuery('SELECT id, uid FROM question_banks');
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
      m['bank_ids'] = _mapBankIdsToUids(m['bank_ids'] as String? ?? '', bankUidById);
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

  /// 合并对端快照入库（单事务）。返回处理的实体数；
  /// 快照来自本机（device_id 相同）时直接跳过
  Future<int> importSnapshot(Map<String, dynamic> snapshot) async {
    final deviceId = await DeviceService.instance.deviceId;
    if (snapshot['device_id'] == deviceId) return 0; // 不合并自己的快照
    final db = await _db.database;
    final now = DateTime.now().toIso8601String();
    var merged = 0;

    await db.transaction((txn) async {
      // 1. 题库
      final bankLocalByUid = <String, int>{};
      for (final raw in (snapshot['banks'] as List? ?? const [])) {
        final m = Map<String, dynamic>.from(raw as Map);
        final uid = m['uid'] as String?;
        if (uid == null || uid.isEmpty) continue;
        bankLocalByUid[uid] = await _db.upsertBankByUid(txn, {
          'uid': uid,
          'name': m['name'] ?? '',
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

      // 3. 会话（bank_ids 的 uid 还原为本地 id）
      final sessionLocalByUid = <String, int>{};
      for (final raw in (snapshot['sessions'] as List? ?? const [])) {
        final m = Map<String, dynamic>.from(raw as Map);
        final uid = m['uid'] as String?;
        if (uid == null || uid.isEmpty) continue;
        sessionLocalByUid[uid] = await _db.upsertSessionByUid(txn, {
          'uid': uid,
          'bank_ids': _mapUidsToBankIds(
              m['bank_ids'] as String? ?? '', bankLocalByUid),
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
          'origin_device':
              (m['origin_device'] as String?)?.isNotEmpty == true
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
