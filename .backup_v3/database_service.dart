import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/question.dart';
import '../models/question_bank.dart';
import '../models/quiz_session.dart';
import '../models/answer_record.dart';
import 'fsrs_service.dart';

class DatabaseService {
  static DatabaseService? _instance;
  static Database? _database;

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
    if (Platform.isAndroid) {
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
      version: 4,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
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
        WHERE next_review_at <= datetime('now')
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

  /// 按题库获取错题统计（到期题数 + 收藏题数）
  Future<List<Map<String, dynamic>>> getErrorStatsByBank() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT
        qb.id as bank_id,
        qb.name as bank_name,
        COUNT(DISTINCT CASE
          WHEN fc.next_review_at IS NOT NULL AND fc.next_review_at <= datetime('now')
          THEN q.id END
        ) as due_count,
        COUNT(DISTINCT CASE WHEN eb.question_id IS NOT NULL THEN q.id END) as bookmark_count
      FROM question_banks qb
      LEFT JOIN questions q ON q.bank_id = qb.id
      LEFT JOIN fsrs_cards fc ON fc.question_id = q.id
      LEFT JOIN error_book eb ON eb.question_id = q.id
      GROUP BY qb.id
      HAVING due_count > 0 OR bookmark_count > 0
      ORDER BY qb.name
    ''');
  }
}
