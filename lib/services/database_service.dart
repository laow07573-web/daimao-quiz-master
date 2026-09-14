import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';
import '../models/question.dart';
import '../models/question_bank.dart';
import '../models/quiz_session.dart';
import '../models/answer_record.dart';
import 'backup_crypto.dart';
import 'device_service.dart';
import 'fsrs_service.dart';

class DatabaseService {
  static DatabaseService? _instance;
  static Database? _database;
  /// 测试用：覆盖数据库文件路径（多测试文件并行时按文件隔离，防互相清库）
  static String? overrideDbPath;

  DatabaseService._();

  static DatabaseService get instance {
    _instance ??= DatabaseService._();
    return _instance!;
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    // 桌面分支仅保留给测试宿主（flutter test 在 Windows 上运行需要 FFI）。
    // 正式产品只做 Android，无需此分支的发布形态
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    String dbPath;
    if (overrideDbPath != null) {
      dbPath = overrideDbPath!;
    } else if (Platform.isAndroid) {
      dbPath = join(await getDatabasesPath(), 'flashcard.db');
    } else {
      dbPath = join(
        Platform.environment['LOCALAPPDATA'] ?? Platform.environment['HOME'] ?? '.',
        'flashcard_app',
        'flashcard.db',
      );
      await Directory(dirname(dbPath)).create(recursive: true);
    }

    return await openDatabase(
      dbPath,
      version: 11,
      onConfigure: _onConfigure,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// 外键级联删除生效（v1.0.2：PRAGMA foreign_keys = ON）
  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  /// 索引统一创建（onCreate / onUpgrade 共用，幂等）。
  /// v1.0.2 设计审查修复：补 answered_at / start_time 高频过滤索引，
  /// 并让升级库与全新安装库的索引集保持一致。
  Future<void> _createIndexes(Database db) async {
    const indexes = [
      'CREATE INDEX IF NOT EXISTS idx_questions_bank_id ON questions(bank_id)',
      'CREATE INDEX IF NOT EXISTS idx_answer_records_question_id ON answer_records(question_id)',
      'CREATE INDEX IF NOT EXISTS idx_answer_records_session_id ON answer_records(session_id)',
      'CREATE INDEX IF NOT EXISTS idx_answer_records_answered_at ON answer_records(answered_at)',
      'CREATE INDEX IF NOT EXISTS idx_quiz_sessions_start_time ON quiz_sessions(start_time)',
      'CREATE INDEX IF NOT EXISTS idx_ai_cache_question_id ON ai_cache(question_id)',
    ];
    for (final s in indexes) {
      await db.execute(s);
    }
  }

  /// 同步相关索引（uid 唯一 + 批注设备过滤，v11）。幂等，
  /// onCreate 与 onUpgrade(v11) 共用
  Future<void> _createSyncIndexes(Database db) async {
    const indexes = [
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_question_banks_uid ON question_banks(uid)',
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_questions_uid ON questions(uid)',
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_quiz_sessions_uid ON quiz_sessions(uid)',
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_answer_records_uid ON answer_records(uid)',
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_error_book_uid ON error_book(uid)',
      'CREATE INDEX IF NOT EXISTS idx_question_annotations_device ON question_annotations(device_id)',
    ];
    for (final s in indexes) {
      await db.execute(s);
    }
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // 纵深防御：若库文件已含完整表结构（如外部备份 user_version 被重置为 0），
      // 不做破坏性重建，直接标记版本号跳过（validateBackupFile 已拒绝此类备份导入）
      final existing = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name = 'questions'");
      if (existing.isNotEmpty) {
        await db.execute('PRAGMA user_version = $newVersion');
        return;
      }
      // 删除旧的 questions 表，重建（options 字段从固定列改为 JSON）
      await db.execute('DROP TABLE IF EXISTS questions');
      await db.execute('DROP TABLE IF EXISTS answer_records');
      await db.execute('DROP TABLE IF EXISTS ai_cache');
      await db.execute('''
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
          created_at TEXT NOT NULL,
          FOREIGN KEY (bank_id) REFERENCES question_banks(id) ON DELETE CASCADE
        )
      ''');
      await db.execute('''
        CREATE TABLE answer_records (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          question_id INTEGER NOT NULL,
          session_id INTEGER,
          user_answer TEXT,
          is_correct INTEGER NOT NULL,
          ai_analysis TEXT,
          answered_at TEXT NOT NULL,
          FOREIGN KEY (question_id) REFERENCES questions(id) ON DELETE CASCADE
        )
      ''');
      await db.execute('''
        CREATE TABLE ai_cache (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          question_id INTEGER NOT NULL UNIQUE,
          analysis TEXT NOT NULL,
          created_at TEXT NOT NULL,
          FOREIGN KEY (question_id) REFERENCES questions(id) ON DELETE CASCADE
        )
      ''');
      await db.execute(
          'CREATE INDEX idx_questions_bank_id ON questions(bank_id)');
      await db.execute(
          'CREATE INDEX idx_answer_records_question_id ON answer_records(question_id)');
      await db.execute(
          'CREATE INDEX idx_ai_cache_question_id ON ai_cache(question_id)');
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE error_book (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          question_id INTEGER NOT NULL UNIQUE,
          added_at TEXT NOT NULL,
          FOREIGN KEY (question_id) REFERENCES questions(id) ON DELETE CASCADE
        )
      ''');
    }
    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE fsrs_cards (
          question_id INTEGER PRIMARY KEY,
          stability REAL DEFAULT 0.5,
          difficulty REAL DEFAULT 5.0,
          review_count INTEGER DEFAULT 0,
          last_review_at TEXT,
          next_review_at TEXT,
          FOREIGN KEY (question_id) REFERENCES questions(id) ON DELETE CASCADE
        )
      ''');
    }
    if (oldVersion < 5) {
      await db.execute(
          'ALTER TABLE questions ADD COLUMN knowledge_point TEXT');
    }
    if (oldVersion < 6) {
      // v1.0.2 对齐里程碑：隐藏今日答题记录（统计查询统一排除 hidden=1）
      await db.execute(
          'ALTER TABLE answer_records ADD COLUMN hidden INTEGER NOT NULL DEFAULT 0');
    }
    if (oldVersion < 7) {
      // v1.0.2 设计审查修复：数据来源标记（模拟数据与真实数据隔离）+ 索引补齐。
      // 加列前先查列存在性：user_version 被外部重置（如备份文件把版本改回 6）
      // 时库文件可能已物理含 source 列，直接 ALTER 会报 duplicate column
      final arCols = (await db.rawQuery('PRAGMA table_info(answer_records)'))
          .map((r) => r['name'] as String)
          .toList();
      final qsCols = (await db.rawQuery('PRAGMA table_info(quiz_sessions)'))
          .map((r) => r['name'] as String)
          .toList();
      if (!arCols.contains('source')) {
        await db.execute(
            "ALTER TABLE answer_records ADD COLUMN source TEXT NOT NULL DEFAULT 'real'");
      }
      if (!qsCols.contains('source')) {
        await db.execute(
            "ALTER TABLE quiz_sessions ADD COLUMN source TEXT NOT NULL DEFAULT 'real'");
      }
      await _createIndexes(db);
    }
    if (oldVersion < 8) {
      // v1.0.2 七项改进：断点续刷（会话题目顺序）+ 会话-题库关联表。
      // IF NOT EXISTS：兼容 user_version 被外部重置但表已物理存在的库
      await db.execute('''
        CREATE TABLE IF NOT EXISTS session_questions (
          session_id INTEGER NOT NULL,
          position INTEGER NOT NULL,
          question_id INTEGER NOT NULL,
          PRIMARY KEY (session_id, position),
          FOREIGN KEY (question_id) REFERENCES questions(id) ON DELETE CASCADE
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS session_banks (
          session_id INTEGER NOT NULL,
          bank_id INTEGER NOT NULL,
          PRIMARY KEY (session_id, bank_id),
          FOREIGN KEY (bank_id) REFERENCES question_banks(id) ON DELETE CASCADE
        )
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_session_questions_session '
          'ON session_questions(session_id)');
    }
    if (oldVersion < 9) {
      // v1.0.2 聊天气泡式追问：每道题的追问历史（用户/AI 消息持久化）
      await db.execute('''
        CREATE TABLE IF NOT EXISTS follow_up_messages (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          question_id INTEGER NOT NULL,
          role TEXT NOT NULL,
          content TEXT NOT NULL,
          created_at TEXT NOT NULL,
          FOREIGN KEY (question_id) REFERENCES questions(id) ON DELETE CASCADE
        )
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_follow_up_question '
          'ON follow_up_messages(question_id)');
    }
    if (oldVersion < 10) {
      // v1.0.3 手写批注：答题后批注按题持久化（即时批注不落库）
      await db.execute('''
        CREATE TABLE IF NOT EXISTS question_annotations (
          question_id INTEGER PRIMARY KEY,
          data TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (question_id) REFERENCES questions(id) ON DELETE CASCADE
        )
      ''');
    }
    if (oldVersion < 11) {
      // 局域网同步：全局 UID + 设备维度隔离（批注复合主键、错题按题+设备唯一）
      await _upgradeToV11(db);
    }
  }

  /// v10→v11 迁移：同步实体补 uid，批注改复合主键，错题改 (题,设备) 唯一。
  /// 既有行的 uid 用 uuid v4 回填；既有批注/错题/作答记录的归属设备记为本机。
  /// SQLite 不支持改主键/唯一约束，error_book 与 question_annotations 重建表。
  Future<void> _upgradeToV11(Database db) async {
    final deviceId = await DeviceService.instance.deviceId;
    const uuid = Uuid();

    Future<void> addCol(String table, String col, String type) async {
      final cols = (await db.rawQuery('PRAGMA table_info($table)'))
          .map((r) => r['name'] as String)
          .toList();
      if (!cols.contains(col)) {
        await db.execute('ALTER TABLE $table ADD COLUMN $col $type');
      }
    }

    await addCol('question_banks', 'uid', 'TEXT');
    await addCol('question_banks', 'updated_at', 'TEXT');
    await addCol('questions', 'uid', 'TEXT');
    await addCol('questions', 'updated_at', 'TEXT');
    await addCol('quiz_sessions', 'uid', 'TEXT');
    await addCol('session_questions', 'question_uid', 'TEXT');
    await addCol('answer_records', 'uid', 'TEXT');
    await addCol('answer_records', 'origin_device', 'TEXT');

    // uid 回填（批量）
    Future<void> backfillUid(String table) async {
      final rows =
          await db.rawQuery('SELECT id FROM $table WHERE uid IS NULL');
      if (rows.isEmpty) return;
      final batch = db.batch();
      for (final r in rows) {
        batch.update(table, {'uid': uuid.v4()},
            where: 'id = ?', whereArgs: [r['id']]);
      }
      await batch.commit(noResult: true);
    }

    await backfillUid('question_banks');
    await backfillUid('questions');
    await backfillUid('quiz_sessions');
    await backfillUid('answer_records');

    await db.execute(
        'UPDATE question_banks SET updated_at = created_at WHERE updated_at IS NULL');
    await db.execute(
        'UPDATE questions SET updated_at = created_at WHERE updated_at IS NULL');
    await db.execute(
        "UPDATE answer_records SET origin_device = ? WHERE origin_device IS NULL OR origin_device = ''",
        [deviceId]);
    // session_questions.question_uid 按题目关联回填（悬空引用保持 NULL）
    await db.execute('''
      UPDATE session_questions SET question_uid = (
        SELECT q.uid FROM questions q WHERE q.id = session_questions.question_id
      ) WHERE question_uid IS NULL
    ''');

    // 重建 error_book：question_id UNIQUE → (question_id, origin_device) 唯一，
    // 两端可各有同一题的错题记录，互不覆盖。既有错题归属本机
    final ebRows =
        await db.rawQuery('SELECT id, question_id, added_at FROM error_book');
    await db.execute('DROP TABLE error_book');
    await db.execute('''
      CREATE TABLE error_book (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        question_id INTEGER NOT NULL,
        uid TEXT,
        origin_device TEXT NOT NULL DEFAULT '',
        added_at TEXT NOT NULL,
        UNIQUE (question_id, origin_device),
        FOREIGN KEY (question_id) REFERENCES questions(id) ON DELETE CASCADE
      )
    ''');
    if (ebRows.isNotEmpty) {
      final batch = db.batch();
      for (final r in ebRows) {
        batch.insert('error_book', {
          'id': r['id'],
          'question_id': r['question_id'],
          'uid': uuid.v4(),
          'origin_device': deviceId,
          'added_at': r['added_at'],
        });
      }
      await batch.commit(noResult: true);
    }

    // 重建 question_annotations：单列主键 → (question_id, device_id) 复合，
    // 批注按设备隔离。既有批注归属本机。
    final anRows = await db.rawQuery(
        'SELECT question_id, data, updated_at FROM question_annotations');
    await db.execute('DROP TABLE question_annotations');
    await db.execute('''
      CREATE TABLE question_annotations (
        question_id INTEGER NOT NULL,
        device_id TEXT NOT NULL,
        data TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (question_id, device_id),
        FOREIGN KEY (question_id) REFERENCES questions(id) ON DELETE CASCADE
      )
    ''');
    if (anRows.isNotEmpty) {
      final batch = db.batch();
      for (final r in anRows) {
        batch.insert('question_annotations', {
          'question_id': r['question_id'],
          'device_id': deviceId,
          'data': r['data'],
          'updated_at': r['updated_at'],
        });
      }
      await batch.commit(noResult: true);
    }

    await _createSyncIndexes(db);
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE question_banks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        file_source TEXT,
        question_count INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        uid TEXT,
        updated_at TEXT
      )
    ''');

    await db.execute('''
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
        created_at TEXT NOT NULL,
        uid TEXT,
        updated_at TEXT,
        FOREIGN KEY (bank_id) REFERENCES question_banks(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
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
        source TEXT NOT NULL DEFAULT 'real',
        uid TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE answer_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        question_id INTEGER NOT NULL,
        session_id INTEGER,
        user_answer TEXT,
        is_correct INTEGER NOT NULL,
        ai_analysis TEXT,
        answered_at TEXT NOT NULL,
        hidden INTEGER NOT NULL DEFAULT 0,
        source TEXT NOT NULL DEFAULT 'real',
        uid TEXT,
        origin_device TEXT,
        FOREIGN KEY (question_id) REFERENCES questions(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE ai_cache (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        question_id INTEGER NOT NULL UNIQUE,
        analysis TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (question_id) REFERENCES questions(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    // 统一创建索引（幂等，onUpgrade 复用同一份）
    await _createIndexes(db);

    // 局域网同步（v11）：错题按 (题, 来源设备) 唯一，两端同一题错题共存
    await db.execute('''
      CREATE TABLE error_book (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        question_id INTEGER NOT NULL,
        uid TEXT,
        origin_device TEXT NOT NULL DEFAULT '',
        added_at TEXT NOT NULL,
        UNIQUE (question_id, origin_device),
        FOREIGN KEY (question_id) REFERENCES questions(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE fsrs_cards (
        question_id INTEGER PRIMARY KEY,
        stability REAL DEFAULT 0.5,
        difficulty REAL DEFAULT 5.0,
        review_count INTEGER DEFAULT 0,
        last_review_at TEXT,
        next_review_at TEXT,
        FOREIGN KEY (question_id) REFERENCES questions(id) ON DELETE CASCADE
      )
    ''');

    // v1.0.2 七项改进：断点续刷（会话题目顺序）+ 会话-题库关联表。
    // v11 同步：question_uid 跨设备关联（断点续刷仍按本地 question_id）
    await db.execute('''
      CREATE TABLE session_questions (
        session_id INTEGER NOT NULL,
        position INTEGER NOT NULL,
        question_id INTEGER NOT NULL,
        question_uid TEXT,
        PRIMARY KEY (session_id, position),
        FOREIGN KEY (question_id) REFERENCES questions(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE session_banks (
        session_id INTEGER NOT NULL,
        bank_id INTEGER NOT NULL,
        PRIMARY KEY (session_id, bank_id),
        FOREIGN KEY (bank_id) REFERENCES question_banks(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('CREATE INDEX idx_session_questions_session '
        'ON session_questions(session_id)');

    // v1.0.2 聊天气泡式追问：每道题的追问历史（用户/AI 消息持久化）
    await db.execute('''
      CREATE TABLE follow_up_messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        question_id INTEGER NOT NULL,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (question_id) REFERENCES questions(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('CREATE INDEX idx_follow_up_question '
        'ON follow_up_messages(question_id)');

    // v1.0.3 手写批注：答题后批注按题持久化（即时批注不落库）。
    // v11 同步：主键改 (question_id, device_id)，批注按设备隔离互不覆盖；
    // 刷题页只显示本机批注（AnnotationService 按 device_id 过滤）
    await db.execute('''
      CREATE TABLE question_annotations (
        question_id INTEGER NOT NULL,
        device_id TEXT NOT NULL,
        data TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (question_id, device_id),
        FOREIGN KEY (question_id) REFERENCES questions(id) ON DELETE CASCADE
      )
    ''');

    // 同步索引（uid 唯一 + 批注设备过滤）
    await _createSyncIndexes(db);
  }

  // ======================== 局域网同步 DAO（v11） ========================
  //
  // 同步引擎按 uid 合并：新则插、已有按时间取新。批注按 (题,设备) 隔离，
  // 绝不覆盖他端批注。参数统一收 DatabaseExecutor，便于仓库层包进单事务。
  // 以下 [row] 均为已完成本地 id 映射后的列集（不含自增 id）。

  /// 按 uid 查本地题库行（不存在返回 null）
  Future<Map<String, dynamic>?> bankRowByUid(
      DatabaseExecutor db, String uid) async {
    final rows = await db.query('question_banks', where: 'uid = ?', whereArgs: [uid]);
    return rows.isEmpty ? null : rows.first;
  }

  /// 按 uid 查本地题目行（不存在返回 null）
  Future<Map<String, dynamic>?> questionRowByUid(
      DatabaseExecutor db, String uid) async {
    final rows = await db.query('questions', where: 'uid = ?', whereArgs: [uid]);
    return rows.isEmpty ? null : rows.first;
  }

  /// 按 uid 查本地会话行（不存在返回 null）
  Future<Map<String, dynamic>?> sessionRowByUid(
      DatabaseExecutor db, String uid) async {
    final rows = await db.query('quiz_sessions', where: 'uid = ?', whereArgs: [uid]);
    return rows.isEmpty ? null : rows.first;
  }

  /// 按 uid upsert 题库：新则插；已有且传入 updated_at 更新则更新名/题数。
  /// 返回本地 id
  Future<int> upsertBankByUid(DatabaseExecutor db, Map<String, dynamic> row) async {
    final existing = await bankRowByUid(db, row['uid'] as String);
    if (existing == null) {
      return await db.insert('question_banks', row);
    }
    final id = existing['id'] as int;
    final oldAt = (existing['updated_at'] as String?) ?? '';
    final newAt = (row['updated_at'] as String?) ?? '';
    if (newAt.compareTo(oldAt) > 0) {
      await db.update('question_banks', {
        'name': row['name'],
        'file_source': row['file_source'],
        'question_count': row['question_count'],
        'updated_at': newAt.isEmpty ? null : newAt,
      }, where: 'id = ?', whereArgs: [id]);
    }
    return id;
  }

  /// 按 uid upsert 题目：新则插；已有且传入 updated_at 更新则更新内容。
  /// [row] 的 bank_id 必须已映射为本地 id。返回本地 id；
  /// bank_id 为 null（对端题库未同步到）返回 -1 表示跳过。
  Future<int> upsertQuestionByUid(
      DatabaseExecutor db, Map<String, dynamic> row) async {
    if (row['bank_id'] == null) return -1;
    final existing = await questionRowByUid(db, row['uid'] as String);
    if (existing == null) {
      return await db.insert('questions', row);
    }
    final id = existing['id'] as int;
    final oldAt = (existing['updated_at'] as String?) ?? '';
    final newAt = (row['updated_at'] as String?) ?? '';
    if (newAt.compareTo(oldAt) > 0) {
      await db.update('questions', {
        'bank_id': row['bank_id'],
        'title': row['title'],
        'options': row['options'],
        'correct_answer': row['correct_answer'],
        'analysis': row['analysis'],
        'question_type': row['question_type'],
        'source': row['source'],
        'knowledge_point': row['knowledge_point'],
        'updated_at': newAt.isEmpty ? null : newAt,
      }, where: 'id = ?', whereArgs: [id]);
    }
    return id;
  }

  /// 按 uid upsert 会话：新则插；已有则按 (end_time ?? start_time) 取新，
  /// 会话只在创建设备上完结，取新即收敛。返回本地 id。
  Future<int> upsertSessionByUid(
      DatabaseExecutor db, Map<String, dynamic> row) async {
    final existing = await sessionRowByUid(db, row['uid'] as String);
    if (existing == null) {
      return await db.insert('quiz_sessions', row);
    }
    final id = existing['id'] as int;
    String stamp(Map<String, dynamic> r) =>
        (r['end_time'] as String?) ?? (r['start_time'] as String? ?? '');
    if (stamp(row).compareTo(stamp(existing)) > 0) {
      await db.update('quiz_sessions', {
        'bank_ids': row['bank_ids'],
        'mode': row['mode'],
        'total_questions': row['total_questions'],
        'correct_count': row['correct_count'],
        'wrong_count': row['wrong_count'],
        'start_time': row['start_time'],
        'end_time': row['end_time'],
        'duration_seconds': row['duration_seconds'],
        'source': row['source'],
      }, where: 'id = ?', whereArgs: [id]);
    }
    return id;
  }

  /// 按 uid upsert 作答记录：新则插；已有且 answered_at 更新则更新答案/判定。
  /// [row] 的 question_id 必须已映射为本地 id；session_id 可为 null
  Future<void> upsertAnswerRecordByUid(
      DatabaseExecutor db, Map<String, dynamic> row) async {
    if (row['question_id'] == null) return; // 对应题目未同步到，丢弃孤儿记录
    final uid = row['uid'] as String;
    final rows =
        await db.query('answer_records', where: 'uid = ?', whereArgs: [uid]);
    if (rows.isEmpty) {
      await db.insert('answer_records', row);
      return;
    }
    final oldAt = (rows.first['answered_at'] as String?) ?? '';
    final newAt = (row['answered_at'] as String?) ?? '';
    if (newAt.compareTo(oldAt) > 0) {
      await db.update('answer_records', {
        'user_answer': row['user_answer'],
        'is_correct': row['is_correct'],
        'ai_analysis': row['ai_analysis'],
        'answered_at': newAt,
        'hidden': row['hidden'],
        'session_id': row['session_id'],
      }, where: 'id = ?', whereArgs: [rows.first['id']]);
    }
  }

  /// 按 (question_id, origin_device) upsert 错题：新则插；已有保持最早收藏时间，
  /// 两端同一题错题共存互不覆盖。重复推送（同 uid）幂等。
  Future<void> upsertErrorBookEntry(
      DatabaseExecutor db, Map<String, dynamic> row) async {
    if (row['question_id'] == null) return;
    final rows = await db.query('error_book',
        where: 'question_id = ? AND origin_device = ?',
        whereArgs: [row['question_id'], row['origin_device']]);
    if (rows.isEmpty) {
      await db.insert('error_book', row);
      return;
    }
    // 旧库回填前 uid 可能为空：补上，保证重复推送幂等
    if (rows.first['uid'] == null && row['uid'] != null) {
      await db.update('error_book', {'uid': row['uid']},
          where: 'id = ?', whereArgs: [rows.first['id']]);
    }
  }

  /// 按 (question_id, device_id) upsert 批注：他端批注存其 device_id 下，
  /// 绝不覆盖本机批注；同设备重复推送按 updated_at 取新。
  Future<void> upsertAnnotationByDevice(
      DatabaseExecutor db, Map<String, dynamic> row) async {
    if (row['question_id'] == null) return;
    final rows = await db.query('question_annotations',
        where: 'question_id = ? AND device_id = ?',
        whereArgs: [row['question_id'], row['device_id']]);
    if (rows.isEmpty) {
      await db.insert('question_annotations', row);
      return;
    }
    final oldAt = (rows.first['updated_at'] as String?) ?? '';
    final newAt = (row['updated_at'] as String?) ?? '';
    if (newAt.compareTo(oldAt) > 0) {
      await db.update('question_annotations', {
        'data': row['data'],
        'updated_at': newAt,
      }, where: 'question_id = ? AND device_id = ?',
          whereArgs: [row['question_id'], row['device_id']]);
    }
  }

  /// 按设备取某题批注行（刷题页只显示本机；同步拉取他端用全量查询）
  Future<List<Map<String, dynamic>>> getAnnotationsByDevice(
      int questionId, String deviceId) async {
    final db = await database;
    return await db.query('question_annotations',
        where: 'question_id = ? AND device_id = ?',
        whereArgs: [questionId, deviceId]);
  }

  /// 替换会话题目顺序（同步他端断点续刷数据：先删后插）
  Future<void> replaceSessionQuestions(DatabaseExecutor db, int sessionId,
      List<Map<String, dynamic>> entries) async {
    await db.delete('session_questions',
        where: 'session_id = ?', whereArgs: [sessionId]);
    if (entries.isEmpty) return;
    final batch = db.batch();
    for (final e in entries) {
      batch.insert('session_questions', e,
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }

  // ======================== QuestionBank CRUD ========================

  Future<int> insertBank(QuestionBank bank) async {
    final db = await database;
    final map = bank.toMap();
    // v11 同步：新题库自动分配全局 uid（跨设备一致标识）
    map['uid'] ??= const Uuid().v4();
    map['updated_at'] ??= bank.createdAt;
    return await db.insert('question_banks', map);
  }

  Future<List<QuestionBank>> getAllBanks() async {
    final db = await database;
    final maps = await db.query('question_banks', orderBy: 'created_at DESC');
    return maps.map((m) => QuestionBank.fromMap(m)).toList();
  }

  Future<void> updateBankQuestionCount(int bankId, int count) async {
    final db = await database;
    await db.update('question_banks', {
      'question_count': count,
      // v11 同步：题数变化可被对端按 updated_at 取新合并
      'updated_at': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [bankId]);
  }

  Future<void> deleteBank(int bankId) async {
    final db = await database;
    // v1.0.2 设计审查修复：单条 IN 删除 + 事务，替代逐题循环（N+1 且无事务）
    await db.transaction((txn) async {
      // 显式清理 answer_records（外键级联兜底）
      await txn.delete('answer_records',
          where: 'question_id IN (SELECT id FROM questions WHERE bank_id = ?)',
          whereArgs: [bankId]);
      // v1.0.3 手写批注：随题库删除清理（外键级联兜底，与 answer_records 同模式）
      await txn.delete('question_annotations',
          where: 'question_id IN (SELECT id FROM questions WHERE bank_id = ?)',
          whereArgs: [bankId]);
      await txn.delete('questions',
          where: 'bank_id = ?', whereArgs: [bankId]);
      await txn.delete('question_banks',
          where: 'id = ?', whereArgs: [bankId]);
    });
  }

  // ======================== Question CRUD ========================

  Future<void> insertQuestions(List<Question> questions) async {
    final db = await database;
    // v1.27 导入提速：包显式事务（无事务时每条插入独立 fsync，
    // 大题库导入慢一个数量级；与 simulateLongTermUse 同策略）
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final q in questions) {
        final map = q.toMap();
        // v11 同步：新题自动分配全局 uid；updated_at 缺省同 created_at
        map['uid'] ??= const Uuid().v4();
        map['updated_at'] ??= q.createdAt;
        batch.insert('questions', map);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> updateQuestion(int id, String title, String correctAnswer, String questionType) async {
    final db = await database;
    await db.update('questions', {
      'title': title,
      'correct_answer': correctAnswer,
      'question_type': questionType,
      // v11 同步：编辑后对端可按 updated_at 取新合并，不被旧数据覆盖
      'updated_at': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Question>> getQuestionsByBank(int bankId) async {
    final db = await database;
    final maps = await db.query('questions',
        where: 'bank_id = ?', whereArgs: [bankId]);
    return maps.map((m) => Question.fromMap(m)).toList();
  }

  /// 按题库取题。[limit] 下推 SQL LIMIT（随机抽取时避免全量加载进内存），
  /// 调用方不再需要二次 shuffle/take
  Future<List<Question>> getQuestionsByBanks(List<int> bankIds,
      {bool random = true, int? limit}) async {
    final db = await database;
    if (bankIds.isEmpty) return <Question>[]; // 防御：空集合不生成 IN () 语法错误
    final placeholders = bankIds.map((_) => '?').join(',');
    final maps = await db.query('questions',
        where: 'bank_id IN ($placeholders)',
        whereArgs: bankIds,
        orderBy: random ? 'RANDOM()' : null,
        limit: limit);
    return maps.map((m) => Question.fromMap(m)).toList();
  }

  Future<int> getQuestionCountByBank(int bankId) async {
    final db = await database;
    final result = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM questions WHERE bank_id = ?', [bankId]);
    return result.first['cnt'] as int;
  }

  // ======================== QuizSession CRUD ========================

  Future<int> insertSession(QuizSession session) async {
    final db = await database;
    final map = session.toMap();
    // v11 同步：会话全局 uid（作答记录按会话 uid 跨设备关联）
    map['uid'] ??= const Uuid().v4();
    return await db.insert('quiz_sessions', map);
  }

  Future<void> updateSession(QuizSession session) async {
    final db = await database;
    await db.update('quiz_sessions', session.toMap(),
        where: 'id = ?', whereArgs: [session.id]);
  }

  /// 删除会话及其作答记录（放弃会话用：练习模式退出/未作答退出）。
  /// v1.0.2 七项改进：级联清理 session_questions / session_banks
  Future<void> deleteSessionWithRecords(int sessionId) async {
    final db = await database;
    await db.delete('answer_records',
        where: 'session_id = ?', whereArgs: [sessionId]);
    await db.delete('session_questions',
        where: 'session_id = ?', whereArgs: [sessionId]);
    await db.delete('session_banks',
        where: 'session_id = ?', whereArgs: [sessionId]);
    await db.delete('quiz_sessions', where: 'id = ?', whereArgs: [sessionId]);
  }

  // ======================== v1.0.2 七项改进：会话题目/题库关联 ========================

  /// 写入会话-题库关联（startQuiz / 错题复习建会话后调用）
  Future<void> insertSessionBanks(int sessionId, List<int> bankIds) async {
    if (bankIds.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    for (final id in bankIds) {
      batch.insert('session_banks', {
        'session_id': sessionId,
        'bank_id': id,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }

  /// 写入会话题目顺序（断点续刷恢复用）。
  /// v11 同步：同步写入 question_uid（跨设备关联）
  Future<void> insertSessionQuestions(
      int sessionId, List<Question> questions) async {
    if (questions.isEmpty) return;
    final db = await database;
    // 预取 uid 映射，避免逐题查库（uid 由 insertQuestions 生成）
    final ids = questions.where((q) => q.id != null).map((q) => q.id!).toList();
    final uidMap = <int, String>{};
    if (ids.isNotEmpty) {
      final placeholders = List.filled(ids.length, '?').join(',');
      final rows = await db.rawQuery(
          'SELECT id, uid FROM questions WHERE id IN ($placeholders)', ids);
      for (final r in rows) {
        final uid = r['uid'];
        if (uid != null) uidMap[r['id'] as int] = uid as String;
      }
    }
    final batch = db.batch();
    for (var i = 0; i < questions.length; i++) {
      final q = questions[i];
      if (q.id == null) continue;
      batch.insert('session_questions', {
        'session_id': sessionId,
        'position': i,
        'question_id': q.id!,
        'question_uid': uidMap[q.id],
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }

  /// 按记录顺序取会话题目（断点续刷恢复用）
  Future<List<Question>> getSessionQuestions(int sessionId) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT q.* FROM session_questions sq
      JOIN questions q ON q.id = sq.question_id
      WHERE sq.session_id = ?
      ORDER BY sq.position
    ''', [sessionId]);
    return rows.map((m) => Question.fromMap(m)).toList();
  }

  // ======================== 追问消息（聊天气泡式持久化） ========================

  /// 保存一条追问消息（role: 'user' | 'assistant'）
  Future<void> saveFollowUpMessage(
      int questionId, String role, String content) async {
    final db = await database;
    await db.insert('follow_up_messages', {
      'question_id': questionId,
      'role': role,
      'content': content,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// 某题的追问历史（按时间正序，最多 50 条）
  Future<List<Map<String, dynamic>>> getFollowUpMessages(
      int questionId) async {
    final db = await database;
    return await db.query(
      'follow_up_messages',
      where: 'question_id = ?',
      whereArgs: [questionId],
      orderBy: 'created_at ASC, id ASC',
      limit: 50,
    );
  }

  /// 清空某题的追问历史（用户主动"清空对话"）
  Future<void> deleteFollowUpMessages(int questionId) async {
    final db = await database;
    await db.delete('follow_up_messages',
        where: 'question_id = ?', whereArgs: [questionId]);
  }

  /// 某会话的全部作答记录（question_id → 记录，断点续刷恢复历史用）
  Future<Map<int, AnswerRecord>> getAnswerRecordsBySession(
      int sessionId) async {
    final db = await database;
    final maps = await db.query('answer_records',
        where: 'session_id = ?', whereArgs: [sessionId]);
    return {
      for (final m in maps) (m['question_id'] as int): AnswerRecord.fromMap(m),
    };
  }

  /// 最新一条未完成会话（end_time 为空且会话题目顺序仍在）。
  /// 返回 null 表示无可继续的会话
  Future<(QuizSession, int)?> getLatestUnfinishedSession() async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT s.*,
        COALESCE(SUM(CASE WHEN ar.is_correct = 1 AND ar.hidden = 0 AND ar.source = 'real'
                          THEN 1 ELSE 0 END), 0) as d_correct,
        COALESCE(SUM(CASE WHEN ar.is_correct = 0 AND ar.hidden = 0 AND ar.source = 'real'
                          THEN 1 ELSE 0 END), 0) as d_wrong,
        (SELECT COUNT(*) FROM session_questions sq WHERE sq.session_id = s.id) as q_count
      FROM quiz_sessions s
      LEFT JOIN answer_records ar ON ar.session_id = s.id
      WHERE s.source = 'real' AND (s.end_time IS NULL OR s.end_time = '')
      GROUP BY s.id
      HAVING q_count > 0
      ORDER BY s.start_time DESC
      LIMIT 1
    ''');
    if (maps.isEmpty) return null;
    final session = _sessionFromRow(maps.first);
    final answered = session.correctCount + session.wrongCount;
    return (session, answered);
  }

  /// 清空全部未完成会话的断档记录（会话行 + 题目顺序 + 题库关联）。
  /// 开始新会话时调用：上一次未完成的会话被新会话取代，
  /// 续刷卡片与历史列表不再显示。已落库的作答记录保留，
  /// 统计/错题本口径不受影响（answer_records.session_id 无外键，容忍悬空）。
  /// 返回清理的会话数
  Future<int> deleteUnfinishedSessions() async {
    final db = await database;
    final rows = await db.query('quiz_sessions',
        columns: ['id'],
        where: "source = 'real' AND (end_time IS NULL OR end_time = '')");
    if (rows.isEmpty) return 0;
    final ids = rows.map((r) => r['id'] as int).toList();
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.delete('session_questions',
        where: 'session_id IN ($placeholders)', whereArgs: ids);
    await db.delete('session_banks',
        where: 'session_id IN ($placeholders)', whereArgs: ids);
    await db.delete('quiz_sessions',
        where: 'id IN ($placeholders)', whereArgs: ids);
    return ids.length;
  }

  /// 会话关联的题库 id（按 session_banks）
  Future<List<int>> getSessionBankIds(int sessionId) async {
    final db = await database;
    final rows = await db.query('session_banks',
        columns: ['bank_id'], where: 'session_id = ?', whereArgs: [sessionId]);
    return rows.map((r) => r['bank_id'] as int).toList();
  }

  /// 会话关联的题库名（历史列表副标题用）
  Future<List<String>> getSessionBankNames(int sessionId) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT qb.name FROM session_banks sb
      JOIN question_banks qb ON qb.id = sb.bank_id
      WHERE sb.session_id = ?
      ORDER BY qb.name
    ''', [sessionId]);
    return rows.map((r) => r['name'] as String).toList();
  }

  /// 全部真实会话（按开始时间倒序）。correct/wrong 为派生值
  /// （LEFT JOIN 汇总未隐藏的真实作答），与统计口径一致：
  /// 进程被杀后的未完成会话也能显示真实正确率，隐藏今日后同步剔除。
  /// [limit] 非空时下推 LIMIT（getRecentSessions 不再全量加载）
  Future<List<QuizSession>> getAllSessions({int? limit}) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT s.*,
        COALESCE(SUM(CASE WHEN ar.is_correct = 1 AND ar.hidden = 0 AND ar.source = 'real'
                          THEN 1 ELSE 0 END), 0) as d_correct,
        COALESCE(SUM(CASE WHEN ar.is_correct = 0 AND ar.hidden = 0 AND ar.source = 'real'
                          THEN 1 ELSE 0 END), 0) as d_wrong
      FROM quiz_sessions s
      LEFT JOIN answer_records ar ON ar.session_id = s.id
      WHERE s.source = 'real'
      GROUP BY s.id
      ORDER BY s.start_time DESC
      ${limit != null ? 'LIMIT ?' : ''}
    ''', limit != null ? [limit] : []);
    return maps.map(_sessionFromRow).toList();
  }

  Future<QuizSession?> getLastSession() async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT s.*,
        COALESCE(SUM(CASE WHEN ar.is_correct = 1 AND ar.hidden = 0 AND ar.source = 'real'
                          THEN 1 ELSE 0 END), 0) as d_correct,
        COALESCE(SUM(CASE WHEN ar.is_correct = 0 AND ar.hidden = 0 AND ar.source = 'real'
                          THEN 1 ELSE 0 END), 0) as d_wrong
      FROM quiz_sessions s
      LEFT JOIN answer_records ar ON ar.session_id = s.id
      WHERE s.source = 'real'
      GROUP BY s.id
      ORDER BY s.start_time DESC
      LIMIT 1
    ''');
    if (maps.isEmpty) return null;
    return _sessionFromRow(maps.first);
  }

  /// 按 id 查单个会话（改判后局部刷新用，不受 getRecentSessions 条数限制）。
  /// correct/wrong 同样为派生值
  Future<QuizSession?> getSessionById(int id) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT s.*,
        COALESCE(SUM(CASE WHEN ar.is_correct = 1 AND ar.hidden = 0 AND ar.source = 'real'
                          THEN 1 ELSE 0 END), 0) as d_correct,
        COALESCE(SUM(CASE WHEN ar.is_correct = 0 AND ar.hidden = 0 AND ar.source = 'real'
                          THEN 1 ELSE 0 END), 0) as d_wrong
      FROM quiz_sessions s
      LEFT JOIN answer_records ar ON ar.session_id = s.id
      WHERE s.id = ?
      GROUP BY s.id
    ''', [id]);
    if (maps.isEmpty) return null;
    return _sessionFromRow(maps.first);
  }

  /// 会话行 → QuizSession：correct/wrong 优先取派生值（d_correct/d_wrong），
  /// 无派生列的查询（如 insertSession 回读）回退存储值
  static QuizSession _sessionFromRow(Map<String, dynamic> m) {
    final s = QuizSession.fromMap(m);
    return QuizSession(
      id: s.id,
      bankIds: s.bankIds,
      mode: s.mode,
      totalQuestions: s.totalQuestions,
      correctCount: (m['d_correct'] as int?) ?? s.correctCount,
      wrongCount: (m['d_wrong'] as int?) ?? s.wrongCount,
      startTime: s.startTime,
      endTime: s.endTime,
      durationSeconds: s.durationSeconds,
    );
  }

  // ======================== AnswerRecord CRUD ========================

  Future<int> insertAnswerRecord(AnswerRecord record) async {
    final db = await database;
    final map = record.toMap();
    // v11 同步：作答记录全局 uid + 来源设备（跨设备统计合并）
    map['uid'] ??= const Uuid().v4();
    map['origin_device'] ??= await DeviceService.instance.deviceId;
    return await db.insert('answer_records', map);
  }

  /// 查某会话中某题的作答记录（重新作答用；同一会话同一题只应有一条）
  Future<AnswerRecord?> getAnswerRecordBySessionQuestion(
      int sessionId, int questionId) async {
    final db = await database;
    final maps = await db.query('answer_records',
        where: 'session_id = ? AND question_id = ?',
        whereArgs: [sessionId, questionId],
        limit: 1);
    if (maps.isEmpty) return null;
    return AnswerRecord.fromMap(maps.first);
  }

  /// 更新一条作答记录的答案与判定结果（重新作答用）。
  /// v11 同步：answered_at 同步刷新，对端可按时间取新合并重答结果
  Future<void> updateAnswerRecordAnswer(
      int id, String userAnswer, bool isCorrect, DateTime answeredAt) async {
    final db = await database;
    await db.update(
      'answer_records',
      {
        'user_answer': userAnswer,
        'is_correct': isCorrect ? 1 : 0,
        'answered_at': answeredAt.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 获取单题统计：作答次数、正确次数（排除隐藏记录与模拟数据）
  Future<Map<String, int>> getQuestionStats(int questionId) async {
    final db = await database;
    final total = await db.rawQuery(
        "SELECT COUNT(*) as cnt FROM answer_records WHERE question_id = ? AND hidden = 0 AND source = 'real'",
        [questionId]);
    final correct = await db.rawQuery(
        "SELECT COUNT(*) as cnt FROM answer_records WHERE question_id = ? AND is_correct = 1 AND hidden = 0 AND source = 'real'",
        [questionId]);
    return {
      'total': total.first['cnt'] as int,
      'correct': correct.first['cnt'] as int,
    };
  }

  // ======================== AI Cache ========================

  Future<String?> getCachedAnalysis(int questionId) async {
    final db = await database;
    final maps = await db.query('ai_cache',
        where: 'question_id = ?', whereArgs: [questionId]);
    if (maps.isEmpty) return null;
    return maps.first['analysis'] as String;
  }

  Future<void> cacheAnalysis(int questionId, String analysis) async {
    final db = await database;
    await db.insert(
      'ai_cache',
      {
        'question_id': questionId,
        'analysis': analysis,
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ======================== Settings ========================

  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getSetting(String key) async {
    final db = await database;
    final maps = await db.query('settings', where: 'key = ?', whereArgs: [key]);
    if (maps.isEmpty) return null;
    return maps.first['value'] as String;
  }

  // ======================== 统计查询 ========================

  /// 累计刷题总时长（秒）。
  /// 口径与 getPeriodStats 的 duration 一致：只计真实会话，且会话至少
  /// 有一条未隐藏作答记录（隐藏今日后时长同步剔除）
  Future<int> getTotalPracticeDuration() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(s.duration_seconds), 0) as total
      FROM quiz_sessions s
      WHERE s.source = 'real'
        AND EXISTS (SELECT 1 FROM answer_records ar2
                    WHERE ar2.session_id = s.id AND ar2.hidden = 0
                      AND ar2.source = 'real')
    ''');
    return result.first['total'] as int;
  }

  /// 累计总刷题量（排除隐藏记录与模拟数据）
  Future<int> getTotalQuestionsAnswered() async {
    final db = await database;
    final result = await db.rawQuery(
        "SELECT COUNT(*) as cnt FROM answer_records WHERE hidden = 0 AND source = 'real'");
    return result.first['cnt'] as int;
  }

  /// 整体平均正确率（排除隐藏记录与模拟数据）
  Future<double> getOverallAccuracy() async {
    final db = await database;
    final total = await db
        .rawQuery("SELECT COUNT(*) as cnt FROM answer_records WHERE hidden = 0 AND source = 'real'");
    final correct = await db.rawQuery(
        "SELECT COUNT(*) as cnt FROM answer_records WHERE is_correct = 1 AND hidden = 0 AND source = 'real'");
    final t = total.first['cnt'] as int;
    final c = correct.first['cnt'] as int;
    return t > 0 ? (c / t) * 100 : 0;
  }

  /// 各题库的正确率（用于薄弱点分析）
  Future<List<Map<String, dynamic>>> getAccuracyByBank() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT 
        qb.id as bank_id,
        qb.name as bank_name,
        COUNT(ar.id) as total,
        SUM(CASE WHEN ar.is_correct = 1 THEN 1 ELSE 0 END) as correct
      FROM answer_records ar
      JOIN questions q ON ar.question_id = q.id
      JOIN question_banks qb ON q.bank_id = qb.id
      WHERE ar.hidden = 0 AND ar.source = 'real'
      GROUP BY qb.id
    ''');
  }

  /// 关闭数据库
  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }

  /// 重置数据库（启动恢复页用）：关闭并删除当前库文件（含 wal/shm），
  /// 下次访问自动重建空库
  Future<void> resetDatabase() async {
    final db = await database;
    await db.close();
    _database = null;
    final path = db.path;
    for (final p in [path, '$path-wal', '$path-shm']) {
      final f = File(p);
      if (f.existsSync()) await f.delete();
    }
  }

  // ======================== 错题本 ========================

  /// 加入错题本（本机维度）。
  /// v11 同步：记录带来源设备与全局 uid；(题,设备) 唯一，
  /// 两端同一题错题共存互不覆盖；本机重复收藏幂等。
  /// 错题复习查询保持全设备并集（题库共享，哪台都能复习）
  Future<void> addToErrorBook(int questionId) async {
    final db = await database;
    await db.insert('error_book', {
      'question_id': questionId,
      'uid': const Uuid().v4(),
      'origin_device': await DeviceService.instance.deviceId,
      'added_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// 移出错题本：只删本机收藏，不动其他设备的错题记录（各自保留）
  Future<void> removeFromErrorBook(int questionId) async {
    final db = await database;
    await db.delete('error_book',
        where: 'question_id = ? AND origin_device = ?',
        whereArgs: [questionId, await DeviceService.instance.deviceId]);
  }

  /// 本机是否已收藏（刷题页收藏状态只反映本机，不误删他端记录）
  Future<bool> isInErrorBook(int questionId) async {
    final db = await database;
    final result = await db.query('error_book',
        where: 'question_id = ? AND origin_device = ?',
        whereArgs: [questionId, await DeviceService.instance.deviceId]);
    return result.isNotEmpty;
  }

  // ======================== FSRS 间隔重复 ========================

  /// 读取一道题的 FSRS 状态，不存在返回 null
  Future<FSRSCardState?> getFSRSCard(int questionId) async {
    final db = await database;
    final maps = await db.query('fsrs_cards',
        where: 'question_id = ?', whereArgs: [questionId]);
    if (maps.isEmpty) return null;
    return FSRSCardState.fromMap(maps.first);
  }

  /// 写入或更新 FSRS 状态
  Future<void> upsertFSRSCard(FSRSCardState card) async {
    final db = await database;
    await db.insert('fsrs_cards', card.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 某题库下今天到期的复习卡数（模拟 dueToday 校验用）
  Future<int> countDueReviewCards(int bankId) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT COUNT(*) as cnt FROM fsrs_cards
      WHERE question_id IN (SELECT id FROM questions WHERE bank_id = ?)
        AND datetime(next_review_at) <= datetime('now', 'localtime')
    ''', [bankId]);
    return (rows.first['cnt'] as int?) ?? 0;
  }

  /// 全部复习卡数
  Future<int> countAllFsrsCards() async {
    final db = await database;
    final rows = await db.rawQuery('SELECT COUNT(*) as cnt FROM fsrs_cards');
    return (rows.first['cnt'] as int?) ?? 0;
  }

  /// 今天到期的复习卡总数
  Future<int> countDueFsrsCards() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT COUNT(*) as cnt FROM fsrs_cards
      WHERE datetime(next_review_at) <= datetime('now', 'localtime')
    ''');
    return (rows.first['cnt'] as int?) ?? 0;
  }

  /// 获取到期的 FSRS 错题（按题库分组）
  Future<Map<int, List<Question>>> getDueReviewQuestionsByBank() async {
    final db = await database;
    final results = await db.rawQuery('''
      SELECT DISTINCT q.* FROM questions q
      WHERE q.id IN (
        SELECT question_id FROM fsrs_cards
        WHERE datetime(next_review_at) <= datetime('now', 'localtime')
        UNION
        SELECT question_id FROM error_book
      )
      ORDER BY q.bank_id, RANDOM()
    ''');
    final questions = results.map((m) => Question.fromMap(m)).toList();
    final map = <int, List<Question>>{};
    for (final q in questions) {
      map.putIfAbsent(q.bankId, () => []).add(q);
    }
    return map;
  }

  /// 批量取题目复习卡（question_id → 卡；FSRS 可见化：错题本逐题「下次复习」显示用）
  Future<Map<int, FSRSCardState>> getFsrsCardsByIds(
      List<int> questionIds) async {
    if (questionIds.isEmpty) return const {};
    final db = await database;
    final placeholders = List.filled(questionIds.length, '?').join(',');
    final maps = await db.query('fsrs_cards',
        where: 'question_id IN ($placeholders)', whereArgs: questionIds);
    return {
      for (final m in maps)
        (m['question_id'] as int): FSRSCardState.fromMap(m),
    };
  }

  /// 按题库获取错题统计（到期题数 + 收藏题数 + 全部去重数）。
  /// v1.0.2 FSRS 可见化：加 next_due_at（该题库到期卡中最早的到期时间）
  Future<List<Map<String, dynamic>>> getErrorStatsByBank() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT
        qb.id as bank_id,
        qb.name as bank_name,
        COUNT(DISTINCT CASE
          WHEN fc.next_review_at IS NOT NULL AND datetime(fc.next_review_at) <= datetime('now', 'localtime')
          THEN q.id END
        ) as due_count,
        COUNT(DISTINCT CASE WHEN eb.question_id IS NOT NULL THEN q.id END) as bookmark_count,
        COUNT(DISTINCT CASE
          WHEN (fc.next_review_at IS NOT NULL AND datetime(fc.next_review_at) <= datetime('now', 'localtime'))
            OR eb.question_id IS NOT NULL
          THEN q.id END
        ) as all_count,
        MIN(CASE
          WHEN fc.next_review_at IS NOT NULL AND datetime(fc.next_review_at) <= datetime('now', 'localtime')
          THEN fc.next_review_at END
        ) as next_due_at
      FROM question_banks qb
      LEFT JOIN questions q ON q.bank_id = qb.id
      LEFT JOIN fsrs_cards fc ON fc.question_id = q.id
      LEFT JOIN error_book eb ON eb.question_id = q.id
      GROUP BY qb.id
      HAVING due_count > 0 OR bookmark_count > 0
      ORDER BY qb.name
    ''');
  }

  // ======================== v1.0.2 新增：统计/模拟/备份 ========================

  /// 错题筛选口径：
  /// 'all'      = 到期 ∪ 收藏（去重）
  /// 'wrong'    = 纯到期（FSRS 到期）
  /// 'bookmark' = 纯收藏
  String _errorIdSubquery(String mode) {
    switch (mode) {
      case 'wrong':
        return "SELECT question_id FROM fsrs_cards "
            "WHERE datetime(next_review_at) <= datetime('now', 'localtime')";
      case 'bookmark':
        return 'SELECT question_id FROM error_book';
      default:
        return "SELECT question_id FROM fsrs_cards "
            "WHERE datetime(next_review_at) <= datetime('now', 'localtime') "
            "UNION SELECT question_id FROM error_book";
    }
  }

  /// 按筛选模式取错题全量题列表（复习范围与统计口径一致）
  Future<List<Question>> getFullErrorQuestions(String mode,
      {Set<int>? bankIds}) async {
    final db = await database;
    final bankWhere = (bankIds != null && bankIds.isNotEmpty)
        ? 'AND q.bank_id IN (${List.filled(bankIds.length, '?').join(',')})'
        : '';
    final args = bankIds != null && bankIds.isNotEmpty ? bankIds.toList() : <Object>[];
    final rows = await db.rawQuery('''
      SELECT DISTINCT q.* FROM questions q
      WHERE q.id IN (${_errorIdSubquery(mode)}) $bankWhere
      ORDER BY RANDOM()
    ''', args);
    return rows.map((m) => Question.fromMap(m)).toList();
  }

  /// 按筛选模式的错题总数
  Future<int> getFullErrorCount(String mode, {Set<int>? bankIds}) async {
    final db = await database;
    final bankWhere = (bankIds != null && bankIds.isNotEmpty)
        ? 'AND q.bank_id IN (${List.filled(bankIds.length, '?').join(',')})'
        : '';
    final args = bankIds != null && bankIds.isNotEmpty ? bankIds.toList() : <Object>[];
    final rows = await db.rawQuery('''
      SELECT COUNT(DISTINCT q.id) as cnt FROM questions q
      WHERE q.id IN (${_errorIdSubquery(mode)}) $bankWhere
    ''', args);
    return rows.first['cnt'] as int;
  }

  /// 知识点分组统计（与 getFullErrorQuestions 同口径）。
  /// 与里程碑一致：空知识点并入「未打标签」分组。
  /// v1.0.2 设计审查修复：AI 失败标记（AI请求失败/AI服务返回错误/AI解析生成失败）
  /// 与正确率排行同口径排除，不再出现伪分组
  Future<List<Map<String, dynamic>>> getKnowledgePointStats(String mode,
      {Set<int>? bankIds}) async {
    final db = await database;
    final bankWhere = (bankIds != null && bankIds.isNotEmpty)
        ? 'AND q.bank_id IN (${List.filled(bankIds.length, '?').join(',')})'
        : '';
    final args = bankIds != null && bankIds.isNotEmpty ? bankIds.toList() : <Object>[];
    return await db.rawQuery('''
      SELECT
        CASE
          WHEN q.knowledge_point IS NULL OR q.knowledge_point = '' THEN '未打标签'
          ELSE q.knowledge_point
        END as kp,
        COUNT(DISTINCT q.id) as cnt
      FROM questions q
      WHERE q.id IN (${_errorIdSubquery(mode)}) $bankWhere
        AND (q.knowledge_point IS NULL OR q.knowledge_point = ''
             OR (q.knowledge_point NOT LIKE 'AI请求失败%'
                 AND q.knowledge_point NOT LIKE 'AI服务返回错误%'
                 AND q.knowledge_point NOT LIKE 'AI解析生成失败%'))
      GROUP BY
        CASE
          WHEN q.knowledge_point IS NULL OR q.knowledge_point = '' THEN '未打标签'
          ELSE q.knowledge_point
        END
      ORDER BY cnt DESC
    ''', args);
  }

  /// 按知识点取题（复习范围与主列表同口径；'未打标签' 匹配空知识点）
  Future<List<Question>> getFullQuestionsByKnowledgePoint(
      String kp, String mode,
      {Set<int>? bankIds}) async {
    final db = await database;
    final bankWhere = (bankIds != null && bankIds.isNotEmpty)
        ? 'AND q.bank_id IN (${List.filled(bankIds.length, '?').join(',')})'
        : '';
    final untagged = kp == '未打标签';
    // 占位符顺序：bankWhere（bankIds）在前，knowledge_point 在后
    final args = bankIds != null && bankIds.isNotEmpty
        ? <Object>[...bankIds, ...(untagged ? <Object>[] : [kp])]
        : (untagged ? <Object>[] : [kp]);
    final rows = await db.rawQuery('''
      SELECT DISTINCT q.* FROM questions q
      WHERE q.id IN (${_errorIdSubquery(mode)}) $bankWhere
        ${untagged ? "AND (q.knowledge_point IS NULL OR q.knowledge_point = '')"
                   : 'AND q.knowledge_point = ?'}
      ORDER BY RANDOM()
    ''', args);
    return rows.map((m) => Question.fromMap(m)).toList();
  }

  // ======================== v1.0.2 对齐里程碑：AI 打标签 ========================

  /// 未打知识标签的错题数（空知识点，不含 AI 失败标记）
  Future<int> getUntaggedErrorCount() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT COUNT(DISTINCT q.id) as cnt
      FROM questions q
      WHERE q.id IN (SELECT question_id FROM error_book)
        AND (q.knowledge_point IS NULL OR q.knowledge_point = '')
    ''');
    return (rows.first['cnt'] as int?) ?? 0;
  }

  /// 未打知识标签的错题（limit 批处理上限）
  Future<List<Question>> getUntaggedErrorQuestions({int limit = 200}) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT DISTINCT q.* FROM questions q
      WHERE q.id IN (SELECT question_id FROM error_book)
        AND (q.knowledge_point IS NULL OR q.knowledge_point = '')
      LIMIT ?
    ''', [limit]);
    return rows.map((m) => Question.fromMap(m)).toList();
  }

  /// 更新题目知识点标签（v11 同步：同步刷新 updated_at）
  Future<void> updateQuestionKnowledgePoint(int questionId, String kp) async {
    final db = await database;
    await db.update('questions', {
      'knowledge_point': kp,
      'updated_at': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [questionId]);
  }

  // ======================== v1.0.2 对齐里程碑：改判 / 隐藏今日记录 ========================

  /// 改判一条作答记录（会话统计同步修正；FSRS 卡片按新结果补一次复习）。
  /// v1.0.2 设计审查修复：三条写操作包进事务，中途失败整体回滚，
  /// 不再出现记录已改而会话计数未改的永久失同步
  Future<void> rejudgeAnswerRecord(int recordId, bool isCorrect) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query('answer_records',
          where: 'id = ?', whereArgs: [recordId]);
      if (rows.isEmpty) return;
      final record = rows.first;
      final oldCorrect = (record['is_correct'] as int) == 1;
      if (oldCorrect == isCorrect) return;

      await txn.update('answer_records', {'is_correct': isCorrect ? 1 : 0},
          where: 'id = ?', whereArgs: [recordId]);

      // 会话统计修正
      final sessionId = record['session_id'];
      if (sessionId != null) {
        final sessions = await txn.query('quiz_sessions',
            where: 'id = ?', whereArgs: [sessionId]);
        if (sessions.isNotEmpty) {
          final s = sessions.first;
          final correct = (s['correct_count'] as int? ?? 0) + (isCorrect ? 1 : -1);
          final wrong = (s['wrong_count'] as int? ?? 0) + (isCorrect ? -1 : 1);
          await txn.update('quiz_sessions',
              {'correct_count': correct < 0 ? 0 : correct,
               'wrong_count': wrong < 0 ? 0 : wrong},
              where: 'id = ?', whereArgs: [sessionId]);
        }
      }

      // FSRS：以改判后的结果补记一次（事务内直读直写，保证原子性）
      final questionId = record['question_id'] as int;
      final now = DateTime.now();
      final existingRows = await txn.query('fsrs_cards',
          where: 'question_id = ?', whereArgs: [questionId]);
      if (existingRows.isNotEmpty) {
        final existing = FSRSCardState.fromMap(existingRows.first);
        await txn.insert(
            'fsrs_cards',
            FSRSService.schedule(existing, isCorrect ? 3 : 1, now).toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace);
      } else {
        await txn.insert('fsrs_cards',
            FSRSService.initCard(questionId, now).toMap());
      }
    });
  }

  /// 隐藏今日全部作答记录（统计口径：今日从打卡/统计中剔除）
  Future<int> hideTodayRecords() async {
    final db = await database;
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    return await db.rawUpdate('''
      UPDATE answer_records SET hidden = 1
      WHERE hidden = 0 AND date(answered_at) = date(?)
    ''', [day.toIso8601String()]);
  }

  /// 恢复全部被隐藏的今日作答记录
  Future<int> restoreTodayRecords() async {
    final db = await database;
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    return await db.rawUpdate('''
      UPDATE answer_records SET hidden = 0
      WHERE hidden = 1 AND date(answered_at) = date(?)
    ''', [day.toIso8601String()]);
  }

  /// 今日被隐藏的作答记录条数
  Future<int> getHiddenTodayRecordCount() async {
    final db = await database;
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    final rows = await db.rawQuery('''
      SELECT COUNT(*) as cnt FROM answer_records
      WHERE hidden = 1 AND date(answered_at) = date(?)
    ''', [day.toIso8601String()]);
    return (rows.first['cnt'] as int?) ?? 0;
  }

  /// 最近 N 天每日刷题量（无记录天补占位 total=0，COUNT 保证 int）
  Future<List<Map<String, dynamic>>> getDailyStats(int days) async {
    final db = await database;
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: days - 1));
    final rows = await db.rawQuery('''
      SELECT date(answered_at) as day, COUNT(*) as total
      FROM answer_records
      WHERE hidden = 0 AND source = 'real' AND date(answered_at) >= date(?)
      GROUP BY date(answered_at)
    ''', [start.toIso8601String()]);
    final byDay = <String, int>{};
    for (final r in rows) {
      byDay[r['day'] as String] = r['total'] as int;
    }
    final result = <Map<String, dynamic>>[];
    for (var i = 0; i < days; i++) {
      final d = start.add(Duration(days: i));
      final key = _dateKey(d);
      result.add({'date': d, 'total': byDay[key] ?? 0});
    }
    return result;
  }

  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// 连续打卡天数（纯函数）：从 upTo（默认昨天）往前数，
  /// 每日刷题量 >= threshold 记 1 天；假期日期跳过（不中断也不计入）。
  /// [vacationDays] 精确日期列表；[vacationStart]/[vacationEnd] 区间判断
  /// （v1.0.2 设计审查修复：区间不再逐日展开，长假期也不会生成大列表）
  static int countConsecutiveDays(
    Map<String, int> dailyTotals, {
    required DateTime now,
    List<DateTime>? vacationDays,
    DateTime? vacationStart,
    DateTime? vacationEnd,
    int threshold = 50,
    DateTime? upTo,
  }) {
    assert(threshold > 0, 'threshold 必须为正数，否则缺失日期会触发无限循环');
    if (threshold <= 0) return 0;
    final vacationSet = <String>{
      ...?vacationDays?.map((d) => _dateKey(d)),
    };
    final hasRange = vacationStart != null && vacationEnd != null;
    final rangeStart = vacationStart != null
        ? DateTime(vacationStart.year, vacationStart.month, vacationStart.day)
        : null;
    final rangeEnd = vacationEnd != null
        ? DateTime(vacationEnd.year, vacationEnd.month, vacationEnd.day)
        : null;
    bool inVacation(DateTime d) {
      if (vacationSet.contains(_dateKey(d))) return true;
      if (hasRange) {
        final k = DateTime(d.year, d.month, d.day);
        if (!k.isBefore(rangeStart!) && !k.isAfter(rangeEnd!)) return true;
      }
      return false;
    }

    final end = upTo ?? DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 1));
    var streak = 0;
    var cursor = DateTime(end.year, end.month, end.day);
    while (true) {
      if (inVacation(cursor)) {
        cursor = cursor.subtract(const Duration(days: 1));
        continue;
      }
      if ((dailyTotals[_dateKey(cursor)] ?? 0) >= threshold) {
        streak++;
        cursor = cursor.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }
    return streak;
  }

  /// 最近 N 天每日正确率（total/correct，与 getDailyStats 同日口径）。
  /// v1.0.2 设计审查修复：无记录天补 0，与 getDailyStats 结构对齐，
  /// 避免调用方依赖外层合并才能得到完整数组
  Future<List<Map<String, dynamic>>> getDailyAccuracy(int days) async {
    final db = await database;
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: days - 1));
    final rows = await db.rawQuery('''
      SELECT date(answered_at) as day, COUNT(*) as total,
             SUM(CASE WHEN is_correct = 1 THEN 1 ELSE 0 END) as correct
      FROM answer_records
      WHERE hidden = 0 AND source = 'real' AND date(answered_at) >= date(?)
      GROUP BY date(answered_at)
    ''', [start.toIso8601String()]);
    final byDay = <String, Map<String, dynamic>>{
      for (final r in rows) r['day'] as String: r,
    };
    final result = <Map<String, dynamic>>[];
    for (var i = 0; i < days; i++) {
      final d = start.add(Duration(days: i));
      final key = _dateKey(d);
      final r = byDay[key];
      result.add({
        'day': key,
        'total': (r?['total'] as int?) ?? 0,
        'correct': (r?['correct'] as int?) ?? 0,
      });
    }
    return result;
  }

  /// 按知识点的正确率排行（排除隐藏记录；AI 失败标记不入排行）
  Future<List<Map<String, dynamic>>> getAccuracyByKnowledgePoint() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT q.knowledge_point as name, COUNT(ar.id) as total,
             SUM(CASE WHEN ar.is_correct = 1 THEN 1 ELSE 0 END) as correct
      FROM answer_records ar
      JOIN questions q ON ar.question_id = q.id
      WHERE ar.hidden = 0 AND ar.source = 'real' AND q.knowledge_point IS NOT NULL
        AND q.knowledge_point != ''
        AND q.knowledge_point NOT LIKE 'AI请求失败%'
        AND q.knowledge_point NOT LIKE 'AI服务返回错误%'
        AND q.knowledge_point NOT LIKE 'AI解析生成失败%'
      GROUP BY q.knowledge_point
      ORDER BY total DESC
    ''');
  }

  /// 某周期（week/month/all）的答题统计
  Future<Map<String, dynamic>> getPeriodStats(String period) async {
    final db = await database;
    final now = DateTime.now();
    DateTime? start;
    switch (period) {
      case 'week':
        start = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: now.weekday - 1));
        break;
      case 'month':
        start = DateTime(now.year, now.month, 1);
        break;
      default:
        start = null;
    }
    final rows = await db.rawQuery('''
      SELECT
        COUNT(*) as questions,
        SUM(CASE WHEN is_correct = 1 THEN 1 ELSE 0 END) as correct,
        COALESCE((SELECT SUM(s.duration_seconds) FROM quiz_sessions s
          WHERE s.source = 'real'
            ${start != null ? 'AND s.start_time >= ?' : ''}
            AND EXISTS (SELECT 1 FROM answer_records ar2
                    WHERE ar2.session_id = s.id AND ar2.hidden = 0
                      AND ar2.source = 'real')), 0) as duration
      FROM answer_records
      WHERE hidden = 0 AND source = 'real'
        ${start != null ? 'AND answered_at >= ?' : ''}
    ''', start != null ? [start.toIso8601String(), start.toIso8601String()] : []);
    final r = rows.first;
    return {
      'questions': (r['questions'] as int?) ?? 0,
      'correct': (r['correct'] as int?) ?? 0,
      'duration': (r['duration'] as int?) ?? 0,
    };
  }

  /// 会话详情：answer_records JOIN questions 逐题展示。
  /// 与统计口径一致：隐藏记录与模拟记录不展示
  Future<List<Map<String, dynamic>>> getSessionDetail(int sessionId) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT ar.id, ar.question_id, ar.user_answer, ar.is_correct,
             ar.ai_analysis, ar.answered_at,
             q.title as question_title, q.correct_answer, q.question_type
      FROM answer_records ar
      JOIN questions q ON ar.question_id = q.id
      WHERE ar.session_id = ? AND ar.hidden = 0 AND ar.source = 'real'
      ORDER BY ar.id
    ''', [sessionId]);
  }

  /// 模拟长期使用（v1.0.2 对齐里程碑）：
  /// 基于当前题库生成过去 N 天的刷题记录、错题与复习卡；
  /// 重复执行会先清理上次模拟的数据，可放心多试。
  /// [randomWeakKp]：随机 1~2 个知识点作为薄弱点（打标签 + 降低答对率）
  /// [dueToday]：把所有复习卡设为今天到期（错题本的「待复习」数量会全部增加）
  /// 返回 (error, 记录条数, 复习卡数)；error 非空表示失败（如题库为空）
  Future<({String? error, int records, int cards})> simulateLongTermUse({
    int days = 90,
    bool randomWeakKp = false,
    bool dueToday = false,
  }) async {
    final db = await database;

    // 基于当前题库：空题库拦截
    final allQuestions = await db.rawQuery(
        'SELECT * FROM questions ORDER BY id LIMIT 500');
    final pool = allQuestions.map((m) => Question.fromMap(m)).toList();
    if (pool.isEmpty) {
      return (error: '题库为空，请先导入题库再模拟', records: 0, cards: 0);
    }

    // 重复执行会先清理上次模拟的数据（模拟会话 id + 模拟产生的复习卡/错题条目）
    final simSessionsRaw = await getSetting('sim_sessions');
    if (simSessionsRaw != null) {
      final ids = (jsonDecode(simSessionsRaw) as List)
          .map((e) => e as int)
          .toList();
      for (final id in ids) {
        await db.delete('answer_records', where: 'session_id = ?', whereArgs: [id]);
        await db.delete('quiz_sessions', where: 'id = ?', whereArgs: [id]);
      }
    }
    // 上次模拟写入的 fsrs_cards / error_book（按 question 集合精确清理；
    // 只删模拟自己产生/打标记的条目，不动用户真实复习进度与手动收藏）
    final simQuestionsRaw = await getSetting('sim_questions');
    if (simQuestionsRaw != null) {
      final simQ = jsonDecode(simQuestionsRaw) as Map<String, dynamic>;
      final cardIds = (simQ['cards'] as List? ?? []).cast<int>();
      final bookmarkIds = (simQ['bookmarks'] as List? ?? []).cast<int>();
      if (cardIds.isNotEmpty) {
        await db.delete('fsrs_cards',
            where: 'question_id IN (${List.filled(cardIds.length, '?').join(',')})',
            whereArgs: cardIds);
      }
      if (bookmarkIds.isNotEmpty) {
        await db.delete('error_book',
            where: 'question_id IN (${List.filled(bookmarkIds.length, '?').join(',')})',
            whereArgs: bookmarkIds);
      }
    }
    await db.delete('settings', where: "key = 'sim_sessions' OR key = 'sim_questions'");
    final simIds = <int>[];
    final simCardIds = <int>{};
    final simBookmarkIds = <int>{};

    // v1.0.2 设计审查修复：预取真实复习卡/收藏的题号集合。
    // 此前模拟对已有复习卡直接 replace（覆盖真实复习进度）、对已有收藏
    // 仍记入锚点，导致「清除模拟数据」按题号删除时误删用户真实收藏/复习卡。
    // 现在：模拟遇到已有真实数据的题一律跳过，锚点只记模拟真正新建的条目
    final existingCardIds = <int>{
      for (final r in await db.rawQuery('SELECT question_id FROM fsrs_cards'))
        r['question_id'] as int,
    };
    final existingBookmarkIds = <int>{
      for (final r in await db.rawQuery('SELECT question_id FROM error_book'))
        r['question_id'] as int,
    };

    final anchor = DateTime.now().subtract(Duration(days: days - 1));
    final rng = Random(20260808); // 固定种子 → 同一题库下重复执行数据量一致

    // 随机 1~2 个知识点作为薄弱点（若启用）：给部分题打标签。
    // v1.0.2 定位调整：医学课程知识点（医学生通用，不再绑定具体专业）
    const kpPool = ['解剖学', '生理学', '病理学', '药理学', '内科学'];
    final weakKps = randomWeakKp
        ? (kpPool.toList()..shuffle(rng)).take(rng.nextInt(2) + 1).toList()
        : <String>[];
    if (weakKps.isNotEmpty) {
      for (var i = 0; i < pool.length; i++) {
        if (i % 5 < 3) {
          await db.update('questions',
              {'knowledge_point': weakKps[i % weakKps.length]},
              where: 'id = ?', whereArgs: [pool[i].id]);
        }
      }
    }

    var recordCount = 0;
    var cardCount = 0;
    final dayZero = DateTime(anchor.year, anchor.month, anchor.day);
    // v1.0.2 性能修复：全部生成包在单个事务内执行（ffi 下事务内插入
    // 快 10 倍+；此前逐天 batch 在无事务环境下每条 fsync，90 天 4000+
    // 条记录需 15s+，导致测试超时与用户等待）
    await db.transaction((txn) async {
      for (var day = 0; day < days; day++) {
        final d = dayZero.add(Duration(days: day));
        // 最后一天（今天）不生成数据，避免影响实时打卡/连击
        final count = day == days - 1 ? 0 : rng.nextInt(80) + 10;
        if (count == 0) continue;
        final sessionId = await txn.insert('quiz_sessions', QuizSession(
          bankIds: 'simulation',
          mode: 'single',
          totalQuestions: count,
          correctCount: (count * 0.75).round(),
          wrongCount: count - (count * 0.75).round(),
          startTime: DateTime(d.year, d.month, d.day, 9).toIso8601String(),
          endTime: DateTime(d.year, d.month, d.day, 9, 40).toIso8601String(),
          durationSeconds: 2400,
        ).toMap()..['source'] = 'simulation');
        simIds.add(sessionId);
        for (var i = 0; i < count; i++) {
          final q = pool[rng.nextInt(pool.length)];
          // 薄弱知识点的题答对率更低，从而成为统计中的薄弱点
          final isWeak =
              q.knowledgePoint != null && weakKps.contains(q.knowledgePoint);
          final isCorrect = rng.nextDouble() < (isWeak ? 0.4 : 0.75);
          await txn.insert('answer_records', {
            'question_id': q.id!,
            'session_id': sessionId,
            'user_answer': isCorrect ? q.correctAnswer : 'B',
            'is_correct': isCorrect ? 1 : 0,
            'answered_at': DateTime(d.year, d.month, d.day, 9, rng.nextInt(30))
                .toIso8601String(),
            // v1.0.2 设计审查修复：source 标记模拟数据，统计 SQL 统一排除，
            // 模拟不再污染真实刷题量/正确率/连击/热力图
            'source': 'simulation',
          });
          recordCount++;
          if (!isCorrect) {
            // 答错的题自动进错题本并建复习卡。
            // v1.0.2 设计审查修复：已有真实复习卡/收藏的题跳过（不覆盖、
            // 不记锚点），否则「清除模拟数据」会误删用户真实数据。
            // 插入后同步更新内存集合：同一题多次答错只建一次卡/收藏
            if (!existingCardIds.contains(q.id)) {
              existingCardIds.add(q.id!);
              simCardIds.add(q.id!);
              await txn.insert('fsrs_cards', {
                ...FSRSService.initCard(q.id!, DateTime(d.year, d.month, d.day))
                    .toMap(),
              });
              cardCount++;
            }
            if (!existingBookmarkIds.contains(q.id)) {
              existingBookmarkIds.add(q.id!);
              simBookmarkIds.add(q.id!);
              await txn.insert('error_book', {
                'question_id': q.id!,
                'added_at': DateTime.now().toIso8601String(),
              });
            }
          }
        }
      }
    });

    if (dueToday) {
      // 把所有复习卡设为今天到期，便于测试错题复习（「待复习」数量全部增加）。
      // 只更新本次模拟产生的卡，避免影响用户真实复习进度
      if (simCardIds.isNotEmpty) {
        await db.rawUpdate(
            'UPDATE fsrs_cards SET next_review_at = ? WHERE question_id IN '
            '(${List.filled(simCardIds.length, '?').join(',')})',
            [DateTime.now().toIso8601String(), ...simCardIds]);
        cardCount = simCardIds.length;
      } else {
        cardCount = 0;
      }
    }

    await setSetting('sim_sessions', jsonEncode(simIds));
    await setSetting('sim_questions', jsonEncode({
      'cards': simCardIds.toList(),
      'bookmarks': simBookmarkIds.toList(),
    }));
    return (error: null, records: recordCount, cards: cardCount);
  }

  /// 清除模拟长期使用产生的全部数据（v1.0.2）：
  /// 删除模拟会话与作答记录、模拟产生的复习卡与错题条目、设置锚点。
  /// 只清理模拟自己产生/打标记的数据，不动用户真实复习进度与手动收藏。
  /// 返回删除的会话数。
  Future<int> clearSimulatedData() async {
    final db = await database;
    var removedSessions = 0;
    final simSessionsRaw = await getSetting('sim_sessions');
    if (simSessionsRaw != null) {
      final ids = (jsonDecode(simSessionsRaw) as List)
          .map((e) => e as int)
          .toList();
      for (final id in ids) {
        await db.delete('answer_records',
            where: 'session_id = ?', whereArgs: [id]);
        await db.delete('quiz_sessions', where: 'id = ?', whereArgs: [id]);
        removedSessions++;
      }
    }
    final simQuestionsRaw = await getSetting('sim_questions');
    if (simQuestionsRaw != null) {
      final simQ = jsonDecode(simQuestionsRaw) as Map<String, dynamic>;
      final cardIds = (simQ['cards'] as List? ?? []).cast<int>();
      final bookmarkIds = (simQ['bookmarks'] as List? ?? []).cast<int>();
      if (cardIds.isNotEmpty) {
        await db.delete('fsrs_cards',
            where: 'question_id IN (${List.filled(cardIds.length, '?').join(',')})',
            whereArgs: cardIds);
      }
      if (bookmarkIds.isNotEmpty) {
        await db.delete('error_book',
            where: 'question_id IN (${List.filled(bookmarkIds.length, '?').join(',')})',
            whereArgs: bookmarkIds);
      }
    }
    await db.delete(
        'settings', where: "key = 'sim_sessions' OR key = 'sim_questions'");
    return removedSessions;
  }

  /// 校验备份文件：SQLite 魔数 + user_version + 核心表存在性。返回 null 表示合法，否则返回错误信息
  Future<String?> validateBackupFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return '文件不存在';
    if (await file.length() < 8192) {
      // v1.0.2 对齐里程碑：文件不是有效的数据库备份（文件过小）
      return '文件不是有效的数据库备份（文件过小）';
    }
    final raf = await file.open();
    try {
      final header = await raf.read(16);
      // SQLite 魔数: "SQLite format 3\0"
      if (header.length < 16 ||
          String.fromCharCodes(header.sublist(0, 15)) != 'SQLite format 3') {
        // v1.0.2 对齐里程碑：文件不是有效的 SQLite 数据库备份
        return '文件不是有效的 SQLite 数据库备份';
      }
    } finally {
      await raf.close();
    }
    // 核心表 + user_version 校验：临时打开备份库检查 sqlite_master
    Database? tmpDb;
    try {
      tmpDb = await databaseFactory.openDatabase(filePath);
      final versionRows = await tmpDb.rawQuery('PRAGMA user_version');
      final version = versionRows.isNotEmpty ? versionRows.first.values.first as int : 0;
      if (version < 1 || version > 11) {
        // user_version 0/非法：非本 App 生成或版本被外部重置，导入后会触发
        // onUpgrade(0→8) 破坏性重建清空题目，拒绝导入
        return '文件不是有效的数据库备份（版本信息缺失或非法）';
      }
      final tables = await tmpDb.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name IN "
          "('question_banks','questions','answer_records','settings')");
      final names = tables.map((r) => r['name']).toSet();
      for (final t in ['question_banks', 'questions', 'answer_records', 'settings']) {
        if (!names.contains(t)) return '备份缺少核心表: $t';
      }
      // v8 新增表存在性（旧版本备份导入后由 onUpgrade 建表，故只校验 v8 备份）
      if (version >= 8) {
        final extraTables = await tmpDb.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name IN "
            "('session_banks','session_questions')");
        final extraNames = extraTables.map((r) => r['name']).toSet();
        for (final t in ['session_banks', 'session_questions']) {
          if (!extraNames.contains(t)) return '备份缺少核心表: $t';
        }
      }
      // v1.0.2 设计审查修复：关键列存在性校验（防 user_version 伪造但缺列的库）。
      // 旧版本备份导入后由 onUpgrade 补列，故只校验该版本应当已存在的列
      final colChecks = <int, Map<String, List<String>>>{
        6: {'answer_records': ['hidden']},
        7: {'answer_records': ['hidden', 'source'], 'quiz_sessions': ['source']},
        // v11 同步字段：缺列的库导入后由 onUpgrade 补，故只作完整性提示校验
        11: {
          'question_banks': ['uid'],
          'questions': ['uid'],
          'quiz_sessions': ['uid'],
          'answer_records': ['uid', 'origin_device'],
        },
      };
      for (var v = 6; v <= version; v++) {
        final checks = colChecks[v];
        if (checks == null) continue;
        for (final entry in checks.entries) {
          final cols = await tmpDb.rawQuery('PRAGMA table_info(${entry.key})');
          final colNames = cols.map((r) => r['name']).toSet();
          for (final c in entry.value) {
            if (!colNames.contains(c)) return '备份缺少必要字段: ${entry.key}.$c';
          }
        }
      }
    } catch (e) {
      return '文件不是有效的数据库备份（无法打开: ${e.toString().split('\n').first}）';
    } finally {
      await tmpDb?.close();
    }
    return null;
  }

  /// 导入备份：校验后关闭当前库，用备份文件替换，下次访问自动重开。
  /// v1.0.2 设计审查修复：全程 try/catch、旧库先改名留底（失败可还原）、
  /// 清理 wal/shm 残留，异常不再冒泡为未捕获错误
  ///
  /// 口令加密的备份（见 [BackupCrypto]）需传入 [password]：先用口令解出明文
  /// 落成临时文件，再走与明文备份相同的替换流程。调用方可以先用
  /// [isEncryptedBackup] 判断是否需要向用户索要口令。
  Future<String?> importBackup(String filePath, {String? password}) async {
    try {
      var effectivePath = filePath;
      File? decryptedTmp;

      if (await isEncryptedBackup(filePath)) {
        if (password == null || password.isEmpty) {
          return '这是口令加密的备份，请输入导出时设置的备份口令';
        }
        final container = await File(filePath).readAsBytes();
        final plain = BackupCrypto.decrypt(container, password);
        if (plain == null) {
          return '口令错误，或备份文件已损坏';
        }
        decryptedTmp = File('$filePath.decrypted');
        await decryptedTmp.writeAsBytes(plain, flush: true);
        effectivePath = decryptedTmp.path;
      }

      try {
        final err = await validateBackupFile(effectivePath);
        if (err != null) return err;
        final db = await database;
        await db.close();
        _database = null;
        final target = db.path;
        // 先复制到临时文件，成功后再替换，避免复制中断产生半写入库
        final tmpPath = '$target.importing';
        await File(effectivePath).copy(tmpPath);
        final tmpErr = await validateBackupFile(tmpPath);
        if (tmpErr != null) {
          try {
            await File(tmpPath).delete();
          } catch (_) {}
          return '导入失败：临时文件校验未通过（$tmpErr）';
        }
        final backupOld = '$target.pre-import';
        if (File(target).existsSync()) {
          try {
            await File(backupOld).delete();
          } catch (_) {}
          await File(target).rename(backupOld);
        }
        try {
          await File(tmpPath).rename(target);
        } catch (e) {
          // 替换失败：还原旧库，数据不丢
          try {
            await File(backupOld).rename(target);
          } catch (_) {}
          try {
            await File(tmpPath).delete();
          } catch (_) {}
          return '导入失败：替换数据库失败（已还原原库）';
        }
        // 清理旧库残留的 wal/shm（防下次打开读取旧事务日志）
        for (final p in ['$target-wal', '$target-shm']) {
          final f = File(p);
          if (f.existsSync()) {
            try {
              await f.delete();
            } catch (_) {}
          }
        }
        try {
          await File(backupOld).delete();
        } catch (_) {}
        return null;
      } finally {
        // 解密出的明文副本用完即删，不留在磁盘上
        if (decryptedTmp != null) {
          try {
            if (decryptedTmp.existsSync()) await decryptedTmp.delete();
          } catch (_) {}
        }
      }
    } catch (e) {
      return '导入失败：${e.toString().split('\n').first}';
    }
  }

  /// 导出当前数据库备份到指定路径。
  ///
  /// [includeApiKey] 默认 false：备份是整库拷贝，`settings` 表里的 `api_key`
  /// 密文会随之进入备份，而那条密文的密钥是写死在 App 里的（见 [KeyCrypto]）
  /// ——**拿到备份就能解出 API Key**。所以默认在副本里清掉该行；
  /// 只有在用户明确选择「包含 API Key」时才保留，并且必须提供 [password]
  /// 对整个备份文件加密（[BackupCrypto]），否则拒绝导出。
  ///
  /// [password] 非空时，导出完成后把文件整体加密为该口令保护的容器。
  Future<String?> exportBackup(
    String destPath, {
    bool includeApiKey = false,
    String? password,
  }) async {
    try {
      if (includeApiKey && (password == null || password.isEmpty)) {
        // 不允许「带 Key 但不加密」——那等于把 Key 明文交出去
        return '导出失败：包含 API Key 时必须设置备份口令';
      }
      final db = await database;
      // v1.0.2 设计审查修复：WAL 检查点先把未落盘的页写回主文件，
      // 保证直接 copy 得到的是完整快照（不再是名不副实的一致性快照）
      await db.rawQuery('PRAGMA wal_checkpoint(FULL)');
      await File(db.path).copy(destPath);

      if (!includeApiKey) {
        final err = await _stripApiKeyFromBackup(destPath);
        if (err != null) return err;
      }

      if (password != null && password.isNotEmpty) {
        final err = await _encryptBackupFile(destPath, password);
        if (err != null) return err;
      }
      return null;
    } catch (e) {
      return '导出失败：${e.toString().split('\n').first}';
    }
  }

  /// 在备份副本里删除 API Key 行（副本是独立文件，不影响在用数据库）。
  Future<String?> _stripApiKeyFromBackup(String path) async {
    Database? copy;
    try {
      copy = await openDatabase(path);
      await copy.delete('settings', where: 'key = ?', whereArgs: ['api_key']);
      return null;
    } catch (e) {
      // 清不掉就当作导出失败：宁可让用户重试，也不能悄悄导出带 Key 的备份
      try {
        await File(path).delete();
      } catch (_) {}
      return '导出失败：无法从备份中移除 API Key（${e.toString().split('\n').first}）';
    } finally {
      try {
        await copy?.close();
      } catch (_) {}
    }
  }

  /// 把已生成的明文备份就地加密为口令保护容器。
  Future<String?> _encryptBackupFile(String path, String password) async {
    try {
      final plain = await File(path).readAsBytes();
      final sealed = BackupCrypto.encrypt(plain, password);
      await File(path).writeAsBytes(sealed, flush: true);
      return null;
    } catch (e) {
      try {
        await File(path).delete(); // 加密失败不留半成品
      } catch (_) {}
      return '导出失败：加密备份时出错（${e.toString().split('\n').first}）';
    }
  }

  /// 判断备份文件是否为口令加密容器（只读文件头，用于导入前决定是否索要口令）。
  Future<bool> isEncryptedBackup(String filePath) async {
    try {
      final f = File(filePath);
      if (!f.existsSync()) return false;
      final raf = await f.open();
      try {
        final head = await raf.read(BackupCrypto.headerLength);
        return BackupCrypto.looksEncrypted(head);
      } finally {
        await raf.close();
      }
    } catch (_) {
      return false;
    }
  }
}
