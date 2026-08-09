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
      version: 5,
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

  Future<List<Question>> getQuestionsByBanks(List<int> bankIds) async {
    final db = await database;
    final placeholders = bankIds.map((_) => '?').join(',');
    final maps = await db.query('questions',
        where: 'bank_id IN ($placeholders)',
        whereArgs: bankIds,
        orderBy: 'RANDOM()');
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

  // ======================== AnswerRecord CRUD ========================

  Future<int> insertAnswerRecord(AnswerRecord record) async {
    final db = await database;
    return await db.insert('answer_records', record.toMap());
  }

  /// 获取单题统计：作答次数、正确次数
  Future<Map<String, int>> getQuestionStats(int questionId) async {
    final db = await database;
    final total = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM answer_records WHERE question_id = ?',
        [questionId]);
    final correct = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM answer_records WHERE question_id = ? AND is_correct = 1',
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

  /// 累计总刷题量
  Future<int> getTotalQuestionsAnswered() async {
    final db = await database;
    final result = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM answer_records');
    return result.first['cnt'] as int;
  }

  /// 整体平均正确率
  Future<double> getOverallAccuracy() async {
    final db = await database;
    final total = await db
        .rawQuery('SELECT COUNT(*) as cnt FROM answer_records');
    final correct = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM answer_records WHERE is_correct = 1');
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
      GROUP BY qb.id
    ''');
  }

  /// 关闭数据库
  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
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

  /// 获取错题重刷题目：错3次以上 + 手动加入错题本
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
          WHERE is_correct = 0
          GROUP BY question_id
          HAVING cnt >= 3
        )
      )
      ORDER BY RANDOM()
    ''');
    return results.map((m) => Question.fromMap(m)).toList();
  }

  /// 获取错题本数量
  Future<int> getErrorBookCount() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT COUNT(DISTINCT q.id) as cnt FROM questions q
      WHERE q.id IN (
        SELECT question_id FROM error_book
        UNION
        SELECT question_id FROM (
          SELECT question_id, COUNT(*) as cnt
          FROM answer_records WHERE is_correct = 0
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

  /// 知识点分组统计（与 getFullErrorQuestions 同口径）
  Future<List<Map<String, dynamic>>> getKnowledgePointStats(String mode,
      {Set<int>? bankIds}) async {
    final db = await database;
    final bankWhere = (bankIds != null && bankIds.isNotEmpty)
        ? 'AND q.bank_id IN (${List.filled(bankIds.length, '?').join(',')})'
        : '';
    final args = bankIds != null && bankIds.isNotEmpty ? bankIds.toList() : <Object>[];
    return await db.rawQuery('''
      SELECT q.knowledge_point as kp, COUNT(DISTINCT q.id) as cnt
      FROM questions q
      WHERE q.id IN (${_errorIdSubquery(mode)}) $bankWhere
        AND q.knowledge_point IS NOT NULL AND q.knowledge_point != ''
      GROUP BY q.knowledge_point
      ORDER BY cnt DESC
    ''', args);
  }

  /// 按知识点取题（复习范围与主列表同口径）
  Future<List<Question>> getFullQuestionsByKnowledgePoint(
      String kp, String mode,
      {Set<int>? bankIds}) async {
    final db = await database;
    final bankWhere = (bankIds != null && bankIds.isNotEmpty)
        ? 'AND q.bank_id IN (${List.filled(bankIds.length, '?').join(',')})'
        : '';
    final args = bankIds != null && bankIds.isNotEmpty
        ? [kp, ...bankIds]
        : [kp];
    final rows = await db.rawQuery('''
      SELECT DISTINCT q.* FROM questions q
      WHERE q.id IN (${_errorIdSubquery(mode)}) $bankWhere
        AND q.knowledge_point = ?
      ORDER BY RANDOM()
    ''', args);
    return rows.map((m) => Question.fromMap(m)).toList();
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
      WHERE date(answered_at) >= date(?)
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
      WHERE date(answered_at) >= date(?)
      GROUP BY date(answered_at)
    ''', [start.toIso8601String()]);
    return rows;
  }

  /// 按知识点的正确率排行
  Future<List<Map<String, dynamic>>> getAccuracyByKnowledgePoint() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT q.knowledge_point as kp, COUNT(ar.id) as total,
             SUM(CASE WHEN ar.is_correct = 1 THEN 1 ELSE 0 END) as correct
      FROM answer_records ar
      JOIN questions q ON ar.question_id = q.id
      WHERE q.knowledge_point IS NOT NULL AND q.knowledge_point != ''
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
        COALESCE((SELECT SUM(duration_seconds) FROM quiz_sessions
          ${start != null ? 'WHERE start_time >= ?' : ''}), 0) as duration
      FROM answer_records
      ${start != null ? 'WHERE answered_at >= ?' : ''}
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

  /// 模拟长期使用（开发者选项）：以首次执行时间为锚点，
  /// 幂等 —— 已生成过则直接返回，重复调用不会跨午夜生成新数据。
  Future<void> simulateLongTermUse() async {
    final db = await database;
    // 幂等：模拟数据已存在则直接返回。
    // 若标记残留但题库已被删除（如 deleteBank），重置标记重新生成。
    final simBank = await db.query('question_banks',
        where: 'name = ?', whereArgs: ['模拟题库']);
    if (simBank.isNotEmpty && await getSetting('sim_done') == '1') return;
    if (simBank.isEmpty) {
      await db.delete('settings', where: "key IN ('sim_done','sim_anchor')");
    }
    final anchorStr = await getSetting('sim_anchor');
    final anchor = anchorStr != null
        ? DateTime.parse(anchorStr)
        : DateTime.now();
    if (anchorStr == null) {
      await setSetting('sim_anchor', anchor.toIso8601String());
    }

    // 模拟题库
    final existing = await db.query('question_banks',
        where: 'name = ?', whereArgs: ['模拟题库']);
    int bankId;
    if (existing.isNotEmpty) {
      bankId = existing.first['id'] as int;
    } else {
      bankId = await insertBank(QuestionBank(
        name: '模拟题库',
        fileSource: 'simulation',
        questionCount: 40,
        createdAt: anchor.subtract(const Duration(days: 89)).toIso8601String(),
      ));
      final questions = <Question>[];
      for (var i = 1; i <= 40; i++) {
        questions.add(Question(
          bankId: bankId,
          title: '模拟单选题 $i',
          options: const ['选项A', '选项B', '选项C', '选项D'],
          correctAnswer: 'A',
          analysis: '模拟解析',
          questionType: 'single_choice',
          source: 'simulation',
          createdAt: anchor.toIso8601String(),
        ));
      }
      await insertQuestions(questions);
    }

    // 90 天随机刷题记录（以锚点做随机种子 → 确定性 → 幂等）
    final rng = Random(anchor.millisecondsSinceEpoch);
    final allQuestions = await getQuestionsByBank(bankId);
    if (allQuestions.isEmpty) return;
    final dayZero = DateTime(anchor.year, anchor.month, anchor.day)
        .subtract(const Duration(days: 89));
    for (var day = 0; day < 90; day++) {
      final d = dayZero.add(Duration(days: day));
      final count = day == 89 ? 0 : rng.nextInt(80) + 10; // 10~89 题/天
      if (count == 0) continue;
      final sessionId = await insertSession(QuizSession(
        bankIds: '$bankId',
        mode: 'single',
        totalQuestions: count,
        correctCount: (count * 0.75).round(),
        wrongCount: count - (count * 0.75).round(),
        startTime: DateTime(d.year, d.month, d.day, 9).toIso8601String(),
        endTime: DateTime(d.year, d.month, d.day, 9, 40).toIso8601String(),
        durationSeconds: 2400,
      ));
      for (var i = 0; i < count; i++) {
        final q = allQuestions[rng.nextInt(allQuestions.length)];
        final isCorrect = rng.nextDouble() < 0.75;
        await insertAnswerRecord(AnswerRecord(
          questionId: q.id!,
          sessionId: sessionId,
          userAnswer: isCorrect ? q.correctAnswer : 'B',
          isCorrect: isCorrect,
          answeredAt: DateTime(d.year, d.month, d.day, 9, rng.nextInt(30))
              .toIso8601String(),
        ));
      }
    }
    await setSetting('sim_done', '1');
  }

  /// 校验备份文件：SQLite 魔数 + 核心表存在性。返回 null 表示合法，否则返回错误信息
  Future<String?> validateBackupFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return '文件不存在';
    final raf = await file.open();
    try {
      final header = await raf.read(16);
      // SQLite 魔数: "SQLite format 3\0"
      if (header.length < 16 ||
          String.fromCharCodes(header.sublist(0, 15)) != 'SQLite format 3') {
        return '不是有效的 SQLite 数据库文件';
      }
    } finally {
      await raf.close();
    }
    // 核心表校验：临时打开备份库检查 sqlite_master
    final tmpDb = await databaseFactory.openDatabase(filePath);
    try {
      final tables = await tmpDb.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name IN "
          "('question_banks','questions','answer_records','settings')");
      final names = tables.map((r) => r['name']).toSet();
      for (final t in ['question_banks', 'questions', 'answer_records', 'settings']) {
        if (!names.contains(t)) return '备份缺少核心表: $t';
      }
    } finally {
      await tmpDb.close();
    }
    return null;
  }

  /// 导入备份：校验后关闭当前库，用备份文件替换，下次访问自动重开
  Future<String?> importBackup(String filePath) async {
    final err = await validateBackupFile(filePath);
    if (err != null) return err;
    final db = await database;
    await db.close();
    _database = null;
    await File(filePath).copy(db.path);
    return null;
  }

  /// 导出当前数据库备份到指定路径
  Future<String?> exportBackup(String destPath) async {
    final db = await database;
    await File(db.path).copy(destPath);
    return null;
  }
}
