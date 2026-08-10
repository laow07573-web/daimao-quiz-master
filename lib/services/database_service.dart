import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/question.dart';
import '../models/question_bank.dart';
import '../models/quiz_session.dart';
import '../models/answer_record.dart';
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
      version: 6,
      onConfigure: _onConfigure,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// 外键级联删除生效（v1.0.2：PRAGMA foreign_keys = ON）
  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
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
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE question_banks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        file_source TEXT,
        question_count INTEGER DEFAULT 0,
        created_at TEXT NOT NULL
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
        duration_seconds INTEGER DEFAULT 0
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

    // 创建索引加速查询
    await db.execute(
        'CREATE INDEX idx_questions_bank_id ON questions(bank_id)');
    await db.execute(
        'CREATE INDEX idx_answer_records_question_id ON answer_records(question_id)');
    await db.execute(
        'CREATE INDEX idx_answer_records_session_id ON answer_records(session_id)');
    await db.execute(
        'CREATE INDEX idx_ai_cache_question_id ON ai_cache(question_id)');

    await db.execute('''
      CREATE TABLE error_book (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        question_id INTEGER NOT NULL UNIQUE,
        added_at TEXT NOT NULL,
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
  }

  // ======================== QuestionBank CRUD ========================

  Future<int> insertBank(QuestionBank bank) async {
    final db = await database;
    return await db.insert('question_banks', bank.toMap());
  }

  Future<List<QuestionBank>> getAllBanks() async {
    final db = await database;
    final maps = await db.query('question_banks', orderBy: 'created_at DESC');
    return maps.map((m) => QuestionBank.fromMap(m)).toList();
  }

  Future<void> updateBankQuestionCount(int bankId, int count) async {
    final db = await database;
    await db.update('question_banks', {'question_count': count},
        where: 'id = ?', whereArgs: [bankId]);
  }

  Future<void> deleteBank(int bankId) async {
    final db = await database;
    // 显式清理 answer_records（外键级联兜底）
    final qs = await db.query('questions',
        columns: ['id'], where: 'bank_id = ?', whereArgs: [bankId]);
    for (final q in qs) {
      await db.delete('answer_records',
          where: 'question_id = ?', whereArgs: [q['id']]);
    }
    await db.delete('questions', where: 'bank_id = ?', whereArgs: [bankId]);
    await db.delete('question_banks', where: 'id = ?', whereArgs: [bankId]);
  }

  // ======================== Question CRUD ========================

  Future<void> insertQuestions(List<Question> questions) async {
    final db = await database;
    final batch = db.batch();
    for (final q in questions) {
      batch.insert('questions', q.toMap());
    }
    await batch.commit(noResult: true);
  }

  Future<void> updateQuestion(int id, String title, String correctAnswer, String questionType) async {
    final db = await database;
    await db.update('questions', {
      'title': title,
      'correct_answer': correctAnswer,
      'question_type': questionType,
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Question>> getQuestionsByBank(int bankId) async {
    final db = await database;
    final maps = await db.query('questions',
        where: 'bank_id = ?', whereArgs: [bankId]);
    return maps.map((m) => Question.fromMap(m)).toList();
  }

  Future<List<Question>> getQuestionsByBanks(List<int> bankIds,
      {bool random = true}) async {
    final db = await database;
    if (bankIds.isEmpty) return <Question>[]; // 防御：空集合不生成 IN () 语法错误
    final placeholders = bankIds.map((_) => '?').join(',');
    final maps = await db.query('questions',
        where: 'bank_id IN ($placeholders)',
        whereArgs: bankIds,
        orderBy: random ? 'RANDOM()' : null);
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
    return await db.insert('quiz_sessions', session.toMap());
  }

  Future<void> updateSession(QuizSession session) async {
    final db = await database;
    await db.update('quiz_sessions', session.toMap(),
        where: 'id = ?', whereArgs: [session.id]);
  }

  /// 删除会话及其作答记录（放弃会话用：练习模式退出/未作答退出）
  Future<void> deleteSessionWithRecords(int sessionId) async {
    final db = await database;
    await db.delete('answer_records',
        where: 'session_id = ?', whereArgs: [sessionId]);
    await db.delete('quiz_sessions', where: 'id = ?', whereArgs: [sessionId]);
  }

  Future<List<QuizSession>> getAllSessions() async {
    final db = await database;
    final maps = await db.query('quiz_sessions', orderBy: 'start_time DESC');
    return maps.map((m) => QuizSession.fromMap(m)).toList();
  }

  Future<QuizSession?> getLastSession() async {
    final db = await database;
    final maps = await db.query('quiz_sessions',
        orderBy: 'start_time DESC', limit: 1);
    if (maps.isEmpty) return null;
    return QuizSession.fromMap(maps.first);
  }

  /// 按 id 查单个会话（改判后局部刷新用，不受 getRecentSessions 条数限制）
  Future<QuizSession?> getSessionById(int id) async {
    final db = await database;
    final maps = await db.query('quiz_sessions',
        where: 'id = ?', whereArgs: [id], limit: 1);
    if (maps.isEmpty) return null;
    return QuizSession.fromMap(maps.first);
  }

  // ======================== AnswerRecord CRUD ========================

  Future<int> insertAnswerRecord(AnswerRecord record) async {
    final db = await database;
    return await db.insert('answer_records', record.toMap());
  }

  /// 获取单题统计：作答次数、正确次数（排除隐藏记录）
  Future<Map<String, int>> getQuestionStats(int questionId) async {
    final db = await database;
    final total = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM answer_records WHERE question_id = ? AND hidden = 0',
        [questionId]);
    final correct = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM answer_records WHERE question_id = ? AND is_correct = 1 AND hidden = 0',
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

  /// 累计刷题总时长（秒）
  Future<int> getTotalPracticeDuration() async {
    final db = await database;
    final result = await db.rawQuery(
        'SELECT COALESCE(SUM(duration_seconds), 0) as total FROM quiz_sessions');
    return result.first['total'] as int;
  }

  /// 累计总刷题量（排除隐藏记录）
  Future<int> getTotalQuestionsAnswered() async {
    final db = await database;
    final result = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM answer_records WHERE hidden = 0');
    return result.first['cnt'] as int;
  }

  /// 整体平均正确率（排除隐藏记录）
  Future<double> getOverallAccuracy() async {
    final db = await database;
    final total = await db
        .rawQuery('SELECT COUNT(*) as cnt FROM answer_records WHERE hidden = 0');
    final correct = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM answer_records WHERE is_correct = 1 AND hidden = 0');
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
      WHERE ar.hidden = 0
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

  Future<void> addToErrorBook(int questionId) async {
    final db = await database;
    await db.insert('error_book', {
      'question_id': questionId,
      'added_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> removeFromErrorBook(int questionId) async {
    final db = await database;
    await db.delete('error_book', where: 'question_id = ?', whereArgs: [questionId]);
  }

  Future<bool> isInErrorBook(int questionId) async {
    final db = await database;
    final result = await db.query('error_book',
        where: 'question_id = ?', whereArgs: [questionId]);
    return result.isNotEmpty;
  }

  /// 获取错题重刷题目：错3次以上 + 手动加入错题本（错误阈值排除隐藏记录）
  Future<List<Question>> getErrorReviewQuestions() async {
    final db = await database;
    final results = await db.rawQuery('''
      SELECT DISTINCT q.* FROM questions q
      WHERE q.id IN (
        SELECT question_id FROM error_book
        UNION
        SELECT question_id FROM (
          SELECT question_id, COUNT(*) as cnt
          FROM answer_records
          WHERE is_correct = 0 AND hidden = 0
          GROUP BY question_id
          HAVING cnt >= 3
        )
      )
      ORDER BY RANDOM()
    ''');
    return results.map((m) => Question.fromMap(m)).toList();
  }

  /// 获取错题本数量（错误阈值排除隐藏记录）
  Future<int> getErrorBookCount() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT COUNT(DISTINCT q.id) as cnt FROM questions q
      WHERE q.id IN (
        SELECT question_id FROM error_book
        UNION
        SELECT question_id FROM (
          SELECT question_id, COUNT(*) as cnt
          FROM answer_records WHERE is_correct = 0 AND hidden = 0
          GROUP BY question_id HAVING cnt >= 3
        )
      )
    ''');
    return result.first['cnt'] as int;
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

  /// 按题库获取错题统计（到期题数 + 收藏题数 + 全部去重数）
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
        ) as all_count
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
  /// 与里程碑一致：空知识点并入「未打标签」分组；AI 失败标记按前缀分组。
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

  /// 更新题目知识点标签
  Future<void> updateQuestionKnowledgePoint(int questionId, String kp) async {
    final db = await database;
    await db.update('questions', {'knowledge_point': kp},
        where: 'id = ?', whereArgs: [questionId]);
  }

  // ======================== v1.0.2 对齐里程碑：改判 / 隐藏今日记录 ========================

  /// 改判一条作答记录（会话统计同步修正；FSRS 卡片按新结果补一次复习）
  Future<void> rejudgeAnswerRecord(int recordId, bool isCorrect) async {
    final db = await database;
    final rows = await db.query('answer_records',
        where: 'id = ?', whereArgs: [recordId]);
    if (rows.isEmpty) return;
    final record = rows.first;
    final oldCorrect = (record['is_correct'] as int) == 1;
    if (oldCorrect == isCorrect) return;

    await db.update('answer_records', {'is_correct': isCorrect ? 1 : 0},
        where: 'id = ?', whereArgs: [recordId]);

    // 会话统计修正
    final sessionId = record['session_id'];
    if (sessionId != null) {
      final sessions = await db.query('quiz_sessions',
          where: 'id = ?', whereArgs: [sessionId]);
      if (sessions.isNotEmpty) {
        final s = sessions.first;
        final correct = (s['correct_count'] as int? ?? 0) + (isCorrect ? 1 : -1);
        final wrong = (s['wrong_count'] as int? ?? 0) + (isCorrect ? -1 : 1);
        await db.update('quiz_sessions',
            {'correct_count': correct < 0 ? 0 : correct,
             'wrong_count': wrong < 0 ? 0 : wrong},
            where: 'id = ?', whereArgs: [sessionId]);
      }
    }

    // FSRS：以改判后的结果补记一次
    final questionId = record['question_id'] as int;
    final now = DateTime.now();
    final existing = await getFSRSCard(questionId);
    if (existing != null) {
      await upsertFSRSCard(
          FSRSService.schedule(existing, isCorrect ? 3 : 1, now));
    } else {
      await upsertFSRSCard(FSRSService.initCard(questionId, now));
    }
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
      WHERE hidden = 0 AND date(answered_at) >= date(?)
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
  static int countConsecutiveDays(
    Map<String, int> dailyTotals, {
    required DateTime now,
    List<DateTime>? vacationDays,
    int threshold = 50,
    DateTime? upTo,
  }) {
    assert(threshold > 0, 'threshold 必须为正数，否则缺失日期会触发无限循环');
    if (threshold <= 0) return 0;
    final vacationSet = <String>{
      ...?vacationDays?.map((d) => _dateKey(d)),
    };
    final end = upTo ?? DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 1));
    var streak = 0;
    var cursor = DateTime(end.year, end.month, end.day);
    while (true) {
      final key = _dateKey(cursor);
      if (vacationSet.contains(key)) {
        cursor = cursor.subtract(const Duration(days: 1));
        continue;
      }
      if ((dailyTotals[key] ?? 0) >= threshold) {
        streak++;
        cursor = cursor.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }
    return streak;
  }

  /// 最近 N 天每日正确率（total/correct，与 getDailyStats 同日口径）
  Future<List<Map<String, dynamic>>> getDailyAccuracy(int days) async {
    final db = await database;
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: days - 1));
    final rows = await db.rawQuery('''
      SELECT date(answered_at) as day, COUNT(*) as total,
             SUM(CASE WHEN is_correct = 1 THEN 1 ELSE 0 END) as correct
      FROM answer_records
      WHERE hidden = 0 AND date(answered_at) >= date(?)
      GROUP BY date(answered_at)
    ''', [start.toIso8601String()]);
    return rows;
  }

  /// 按知识点的正确率排行（排除隐藏记录；AI 失败标记不入排行）
  Future<List<Map<String, dynamic>>> getAccuracyByKnowledgePoint() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT q.knowledge_point as kp, COUNT(ar.id) as total,
             SUM(CASE WHEN ar.is_correct = 1 THEN 1 ELSE 0 END) as correct
      FROM answer_records ar
      JOIN questions q ON ar.question_id = q.id
      WHERE ar.hidden = 0 AND q.knowledge_point IS NOT NULL
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
          ${start != null ? 'WHERE s.start_time >= ? AND' : 'WHERE'}
          EXISTS (SELECT 1 FROM answer_records ar2
                  WHERE ar2.session_id = s.id AND ar2.hidden = 0)), 0) as duration
      FROM answer_records
      WHERE hidden = 0 ${start != null ? 'AND answered_at >= ?' : ''}
    ''', start != null ? [start.toIso8601String(), start.toIso8601String()] : []);
    final r = rows.first;
    return {
      'questions': (r['questions'] as int?) ?? 0,
      'correct': (r['correct'] as int?) ?? 0,
      'duration': (r['duration'] as int?) ?? 0,
    };
  }

  /// 会话详情：answer_records JOIN questions 逐题展示
  Future<List<Map<String, dynamic>>> getSessionDetail(int sessionId) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT ar.id, ar.question_id, ar.user_answer, ar.is_correct,
             ar.ai_analysis, ar.answered_at,
             q.title as question_title, q.correct_answer, q.question_type
      FROM answer_records ar
      JOIN questions q ON ar.question_id = q.id
      WHERE ar.session_id = ?
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

    final anchor = DateTime.now().subtract(Duration(days: days - 1));
    final rng = Random(20260808); // 固定种子 → 同一题库下重复执行数据量一致

    // 随机 1~2 个知识点作为薄弱点（若启用）：给部分题打标签
    const kpPool = ['细菌的形态结构', '消毒灭菌', '免疫应答', '临床检验基础', '血液学检验'];
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
        ).toMap());
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
          });
          recordCount++;
          if (!isCorrect) {
            // 答错的题自动进错题本并建复习卡
            simCardIds.add(q.id!);
            await txn.insert('fsrs_cards', {
              ...FSRSService.initCard(q.id!, DateTime(d.year, d.month, d.day))
                  .toMap(),
            }, conflictAlgorithm: ConflictAlgorithm.replace);
            cardCount++;
            simBookmarkIds.add(q.id!);
            await txn.insert('error_book', {
              'question_id': q.id!,
              'added_at': DateTime.now().toIso8601String(),
            }, conflictAlgorithm: ConflictAlgorithm.ignore);
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
      if (version < 1 || version > 6) {
        // user_version 0/非法：非本 App 生成或版本被外部重置，导入后会触发
        // onUpgrade(0→6) 破坏性重建清空题目，拒绝导入
        return '文件不是有效的数据库备份（版本信息缺失或非法）';
      }
      final tables = await tmpDb.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name IN "
          "('question_banks','questions','answer_records','settings')");
      final names = tables.map((r) => r['name']).toSet();
      for (final t in ['question_banks', 'questions', 'answer_records', 'settings']) {
        if (!names.contains(t)) return '备份缺少核心表: $t';
      }
    } catch (e) {
      return '文件不是有效的数据库备份（无法打开: ${e.toString().split('\n').first}）';
    } finally {
      await tmpDb?.close();
    }
    return null;
  }

  /// 导入备份：校验后关闭当前库，用备份文件原子替换，下次访问自动重开
  Future<String?> importBackup(String filePath) async {
    final err = await validateBackupFile(filePath);
    if (err != null) return err;
    final db = await database;
    await db.close();
    _database = null;
    final target = db.path;
    // 先复制到临时文件，成功后再原子替换，避免复制中断产生半写入库
    final tmpPath = '$target.importing';
    await File(filePath).copy(tmpPath);
    final tmpErr = await validateBackupFile(tmpPath);
    if (tmpErr != null) {
      try { await File(tmpPath).delete(); } catch (_) {}
      return '导入失败：临时文件校验未通过（$tmpErr）';
    }
    if (File(target).existsSync()) {
      await File(target).delete();
    }
    await File(tmpPath).rename(target);
    return null;
  }

  /// 导出当前数据库备份到指定路径
  Future<String?> exportBackup(String destPath) async {
    final db = await database;
    await File(db.path).copy(destPath);
    return null;
  }
}
