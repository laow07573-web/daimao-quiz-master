import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flashcard_app/models/answer_record.dart';
import 'package:flashcard_app/models/question.dart';
import 'package:flashcard_app/models/question_bank.dart';
import 'package:flashcard_app/models/quiz_session.dart';
import 'package:flashcard_app/services/app_state.dart';
import 'package:flashcard_app/services/bank_file_service.dart';
import 'package:flashcard_app/services/database_service.dart';
import 'package:flashcard_app/services/debug_log_service.dart';
import 'package:flashcard_app/services/theme_service.dart';
import 'package:flashcard_app/widgets/answer_sheet_widget.dart';

/// 七项改进回归测试（v1.0.2）：
/// 断点续刷（session_questions/session_banks + resume）、同名题库自动改名、
/// 深色模式、日志导出脱敏、复盘答题卡、v8 备份校验
void main() {
  setUp(() async {
    await DatabaseService.instance.close();
    final dir = Directory(
        Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path);
    final dbPath = '${dir.path}/flashcard_app/test_seven.db';
    DatabaseService.overrideDbPath = dbPath;
    final f = File(dbPath);
    if (await f.exists()) await f.delete();
  });

  tearDown(() async {
    await DatabaseService.instance.close();
    DatabaseService.overrideDbPath = null;
  });

  Future<int> seedBank(String name, int count) async {
    final db = DatabaseService.instance;
    final now = DateTime.now().toIso8601String();
    final bankId =
        await db.insertBank(QuestionBank(name: name, createdAt: now));
    await db.insertQuestions([
      for (var i = 1; i <= count; i++)
        Question(
            bankId: bankId,
            title: '$name-题$i',
            correctAnswer: 'A',
            options: const ['A', 'B', 'C'],
            createdAt: now),
    ]);
    return bankId;
  }

  test('会话题目顺序/题库关联写入 + 断点续刷恢复', () async {
    final db = DatabaseService.instance;
    final bankId = await seedBank('R', 3);
    final qs = await db.getQuestionsByBank(bankId);
    final now = DateTime.now().toIso8601String();
    final sessionWithId = QuizSession(
      id: await db.insertSession(QuizSession(
          bankIds: '$bankId', mode: 'single', totalQuestions: 3,
          startTime: now)),
      bankIds: '$bankId',
      mode: 'single',
      totalQuestions: 3,
      startTime: now,
    );
    await db.insertSessionBanks(sessionWithId.id!, [bankId]);
    await db.insertSessionQuestions(sessionWithId.id!, qs);
    // 第 1 题已答对
    await db.insertAnswerRecord(AnswerRecord(
        questionId: qs[0].id!, sessionId: sessionWithId.id!, userAnswer: 'A',
        isCorrect: true, answeredAt: now));

    // 会话关联查询
    expect(await db.getSessionBankIds(sessionWithId.id!), [bankId]);
    expect(await db.getSessionBankNames(sessionWithId.id!), ['R']);
    final questions = await db.getSessionQuestions(sessionWithId.id!);
    expect(questions.map((q) => q.id).toList(),
        qs.map((q) => q.id).toList()); // 顺序一致

    // 断点续刷：恢复题目、历史、跳到第一个未答题
    final appState = AppState();
    final ok = await appState.resumeUnfinishedSession();
    expect(ok, isTrue);
    expect(appState.quizQuestions.length, 3);
    expect(appState.quizQuestions.first.id, qs[0].id);
    expect(appState.currentQuestionIndex, 1); // 第 1 题已答，跳到第 2 题
    expect(appState.lastAnswerRecord, isNull);
    appState.previousQuestion();
    expect(appState.lastAnswerRecord?.isCorrect, isTrue); // 历史恢复
    // 完成会话后不再有可续刷的会话
    await appState.endSession();
    final appState2 = AppState();
    expect(await appState2.resumeUnfinishedSession(), isFalse);
  });

  test('deleteSessionWithRecords 级联清理会话题目/题库关联表', () async {
    final db = DatabaseService.instance;
    final bankId = await seedBank('D', 2);
    final qs = await db.getQuestionsByBank(bankId);
    final sessionWithId = QuizSession(
      id: await db.insertSession(QuizSession(
          bankIds: '$bankId', mode: 'single', totalQuestions: 2,
          startTime: DateTime.now().toIso8601String())),
      bankIds: '$bankId',
      mode: 'single',
      totalQuestions: 2,
      startTime: DateTime.now().toIso8601String(),
    );
    await db.insertSessionBanks(sessionWithId.id!, [bankId]);
    await db.insertSessionQuestions(sessionWithId.id!, qs);
    await db.deleteSessionWithRecords(sessionWithId.id!);
    expect(await db.getSessionQuestions(sessionWithId.id!), isEmpty);
    expect(await db.getSessionBankIds(sessionWithId.id!), isEmpty);
    expect(await db.getSessionById(sessionWithId.id!), isNull);
  });

  test('同名题库自动改名：existingNames 冲突加后缀 + ensureUniqueBankName', () async {
    final db = DatabaseService.instance;
    final dir = Directory.systemTemp.createTempSync('seven_dup');
    final path = '${dir.path}/dup_${DateTime.now().millisecondsSinceEpoch}.json';
    await File(path).writeAsString(
        '{"format":"maojuan-quiz-questions","name":"临床检验","count":1,'
        '"questions":[{"title":"q1","correct_answer":"A"}]}');
    final (banks1, _, err1, renamed1) =
        await BankFileService.importJsonFile(path);
    expect(err1, isNull);
    expect(renamed1, 0);
    expect(banks1, 1);
    // 再次导入同名：传入已存在集合 → 自动改名
    final (banks2, _, err2, renamed2) =
        await BankFileService.importJsonFile(path, existingNames: {'临床检验'});
    expect(err2, isNull);
    expect(renamed2, 1);
    final names = (await db.getAllBanks()).map((b) => b.name).toSet();
    expect(names, containsAll({'临床检验', '临床检验(2)'}));

    // ensureUniqueBankName 连续冲突加后缀
    final appState = AppState();
    final (name1, isRenamed1) = await appState.ensureUniqueBankName('临床检验');
    expect(isRenamed1, isTrue);
    expect(name1, '临床检验(3)');
    final (name2, isRenamed2) = await appState.ensureUniqueBankName('全新题库');
    expect(isRenamed2, isFalse);
    expect(name2, '全新题库');
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('深色模式：切换持久化 + 3 套深色变体可生成', () async {
    SharedPreferences.setMockInitialValues({});
    final ts = ThemeService();
    await ts.init();
    expect(ts.themeMode, ThemeMode.system);   // v1.28 新设计语言：默认跟随系统
    await ts.switchThemeMode(ThemeMode.dark);
    final ts2 = ThemeService();
    await ts2.init();
    expect(ts2.themeMode, ThemeMode.dark);
    expect(ts2.themeData.brightness, Brightness.light);
    expect(ts2.darkThemeData.brightness, Brightness.dark);
    // 3 套主题深色变体：深背景 + 挂载配色扩展
    for (final t in AppTheme.values) {
      await ts2.switchTo(t);
      final darkTheme = ts2.darkThemeData;
      expect(darkTheme.brightness, Brightness.dark);
      final ac = darkTheme.extension<AppThemeColors>()!;
      expect(ac.background.computeLuminance(), lessThan(0.1));
      expect(ac.surface.computeLuminance(), lessThan(0.15));
    }
  });

  test('日志导出脱敏：作答内容与 AI 预览原文隐藏', () {
    final logger = DebugLogService.instance;
    logger.enable();
    logger.logAnswerSubmit(
        userAnswer: 'A',
        correctAnswer: 'B',
        isCorrect: false,
        questionType: 'single_choice',
        questionTitle: '某题目');
    logger.logUtf8Decode(10, 10, 'AI解析内容预览');
    final exported = logger.exportToString();
    expect(exported, contains('已脱敏'));
    expect(exported, contains('userAnswer="***"'));
    expect(exported, contains('correctAnswer="***"'));
    expect(exported, isNot(contains('userAnswer="A"')));
    expect(exported, isNot(contains('correctAnswer="B"')));
    expect(exported, isNot(contains('AI解析内容预览')));
    logger.clear();
    logger.disable();
  });

  testWidgets('复盘答题卡：答对/答错/未答图例齐全', (tester) async {
    final states = [
      PracticeAnswerState()..answered = true..correct = true,
      PracticeAnswerState()..answered = true..correct = false,
      PracticeAnswerState(),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AnswerSheetWidget(
          answers: states,
          currentIndex: -1,
          showResult: true,
          onJumpTo: (_) {},
        ),
      ),
    ));
    expect(find.text('答对'), findsOneWidget);
    expect(find.text('答错'), findsOneWidget);
    expect(find.text('未答'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  test('备份校验：user_version=8 但缺新表 → 拒绝导入', () async {
    final dir = Directory.systemTemp.createTempSync('seven_backup');
    final fake = '${dir.path}/fake8.db';
    final tmp = await databaseFactory.openDatabase(fake);
    await tmp.execute('PRAGMA page_size = 8192');
    await tmp.execute('CREATE TABLE question_banks (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, file_source TEXT, question_count INTEGER DEFAULT 0, created_at TEXT NOT NULL)');
    await tmp.execute('CREATE TABLE questions (id INTEGER PRIMARY KEY AUTOINCREMENT, bank_id INTEGER NOT NULL, title TEXT NOT NULL, options TEXT NOT NULL DEFAULT "[]", correct_answer TEXT NOT NULL, analysis TEXT, question_type TEXT DEFAULT "single_choice", source TEXT, knowledge_point TEXT, created_at TEXT NOT NULL)');
    await tmp.execute('CREATE TABLE answer_records (id INTEGER PRIMARY KEY AUTOINCREMENT, question_id INTEGER NOT NULL, session_id INTEGER, user_answer TEXT, is_correct INTEGER NOT NULL, ai_analysis TEXT, answered_at TEXT NOT NULL, hidden INTEGER NOT NULL DEFAULT 0, source TEXT NOT NULL DEFAULT "real")');
    await tmp.execute('CREATE TABLE quiz_sessions (id INTEGER PRIMARY KEY AUTOINCREMENT, bank_ids TEXT NOT NULL, mode TEXT NOT NULL, total_questions INTEGER NOT NULL, correct_count INTEGER DEFAULT 0, wrong_count INTEGER DEFAULT 0, start_time TEXT NOT NULL, end_time TEXT, duration_seconds INTEGER DEFAULT 0, source TEXT NOT NULL DEFAULT "real")');
    await tmp.execute('CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
    await tmp.execute('PRAGMA user_version = 8');
    await tmp.close();
    final err = await DatabaseService.instance.validateBackupFile(fake);
    expect(err, isNotNull);
    expect(err, contains('session_banks'));
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });
}
