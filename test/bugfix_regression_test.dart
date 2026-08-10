import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flashcard_app/models/answer_record.dart';
import 'package:flashcard_app/models/question.dart';
import 'package:flashcard_app/models/question_bank.dart';
import 'package:flashcard_app/models/quiz_session.dart';
import 'package:flashcard_app/services/ai_service.dart';
import 'package:flashcard_app/services/bank_file_service.dart';
import 'package:flashcard_app/services/database_service.dart';
import 'package:flashcard_app/services/fsrs_service.dart';
import 'package:flashcard_app/services/key_crypto.dart';
import 'package:flashcard_app/services/quiz_service.dart';
import 'package:flashcard_app/services/theme_service.dart';

/// 全面 Bug 修复回归测试（v1.0.2 修复批次）：
/// hidden 口径、kp+bankIds 参数绑定、AC 归一、AI 失败串判定、3字答案豁免、
/// 模拟幂等清理、备份 user_version 校验、KeyCrypto 明文回退、主题持久化
void main() {
  setUp(() async {
    await DatabaseService.instance.close();
    final dir = Directory(
        Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path);
    final dbPath = '${dir.path}/flashcard_app/test_bugfix.db';
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

  /// 把某题加入错题本并建一张已到期的复习卡
  Future<void> dueQuestion(int questionId) async {
    final db = DatabaseService.instance;
    await db.addToErrorBook(questionId);
    final card = FSRSService.initCard(questionId, DateTime.now());
    await db.upsertFSRSCard(FSRSCardState(
      questionId: card.questionId,
      stability: card.stability,
      difficulty: card.difficulty,
      reviewCount: card.reviewCount,
      lastReviewAt: card.lastReviewAt,
      nextReviewAt:
          DateTime.now().subtract(const Duration(days: 1)),
    ));
  }

  test('hidden 口径：累计刷题量/整体正确率排除隐藏记录', () async {
    final db = DatabaseService.instance;
    final bankId = await seedBank('H', 2);
    final qs = await db.getQuestionsByBank(bankId);
    final now = DateTime.now().toIso8601String();
    final sessionId = await db.insertSession(QuizSession(
      bankIds: '$bankId',
      mode: 'single',
      totalQuestions: 2,
      startTime: now,
    ));
    await db.insertAnswerRecord(AnswerRecord(
        questionId: qs[0].id!,
        sessionId: sessionId,
        userAnswer: 'A',
        isCorrect: true,
        answeredAt: now));
    await db.insertAnswerRecord(AnswerRecord(
        questionId: qs[1].id!,
        sessionId: sessionId,
        userAnswer: 'B',
        isCorrect: false,
        answeredAt: now));

    expect(await db.getTotalQuestionsAnswered(), 2);
    expect(await db.getOverallAccuracy(), 50);

    await db.hideTodayRecords();
    expect(await db.getTotalQuestionsAnswered(), 0);
    expect(await db.getOverallAccuracy(), 0);
  });

  test('getFullQuestionsByKnowledgePoint：kp + bankIds 参数绑定组合', () async {
    final db = DatabaseService.instance;
    final bankA = await seedBank('A', 4);
    final bankB = await seedBank('B', 4);
    final qsA = await db.getQuestionsByBank(bankA);
    final qsB = await db.getQuestionsByBank(bankB);
    // A 库前两题打「细菌的形态结构」，B 库前两题打「免疫应答」
    await db.updateQuestionKnowledgePoint(qsA[0].id!, '细菌的形态结构');
    await db.updateQuestionKnowledgePoint(qsA[1].id!, '细菌的形态结构');
    await db.updateQuestionKnowledgePoint(qsB[0].id!, '免疫应答');
    await db.updateQuestionKnowledgePoint(qsB[1].id!, '免疫应答');
    // 全部进错题本 + 到期（all 口径）
    for (final q in [...qsA, ...qsB]) {
      await dueQuestion(q.id!);
    }
    // 只选 A 库 + 「细菌的形态结构」：应精确返回 A 库 2 题（此前参数错位返回空/错位）
    final result = await db.getFullQuestionsByKnowledgePoint(
        '细菌的形态结构', 'all',
        bankIds: {bankA});
    expect(result.length, 2);
    for (final q in result) {
      expect(q.bankId, bankA);
      expect(q.knowledgePoint, '细菌的形态结构');
    }
    // 只选 B 库 + 「细菌的形态结构」：应为 0
    final none = await db.getFullQuestionsByKnowledgePoint(
        '细菌的形态结构', 'all',
        bankIds: {bankB});
    expect(none, isEmpty);
  });

  test('JSON 多选答案 "AC" 归一为 A,C（含类型判定与去前缀）', () async {
    final dir = Directory.systemTemp.createTempSync('bank_import');
    final file = File('${dir.path}/multi.json');
    await file.writeAsString('''{
  "format": "daimao-flashcard-questions",
  "name": "多选",
  "questions": [
    {"title": "q1", "options": ["A. 甲", "B. 乙", "C. 丙"],
     "correct_answer": "AC", "question_type": "multi_choice"},
    {"title": "q2", "options": "A. 甲 B. 乙 C. 丙",
     "correct_answer": "A, C"}
  ]
}''');
    final groups = await BankFileService.parseJsonFile(file.path);
    expect(BankFileService.lastError, isNull);
    final qs = groups.values.first;
    expect(qs.length, 2);
    // "AC" → A,C
    expect(qs[0].correctAnswer, 'A,C');
    expect(qs[0].questionType, 'multi_choice');
    // "A. 甲 B. 乙 C. 丙" 同行拆分 + 逐项去前缀
    expect(qs[1].options, ['甲', '乙', '丙']);
    // 导入后判定正确
    expect(QuizService.judgeAnswer(qs[0], 'A,C'), isTrue);
    expect(QuizService.judgeAnswer(qs[0], 'C,A'), isTrue);
    expect(QuizService.judgeAnswer(qs[0], 'A,B'), isFalse);
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('AI 失败串判定：不写入解析缓存', () async {
    expect(AIService.isAiError('AI请求失败: SocketException'), isTrue);
    expect(AIService.isAiError('AI服务返回错误 (401)，请检查API配置。'), isTrue);
    expect(AIService.isAiError('AI解析生成失败'), isTrue);
    expect(AIService.isAiError('解析生成失败，请检查网络或 API 配置后重试。'), isTrue);
    expect(AIService.isAiError('这是一段正常解析内容'), isFalse);
  });

  test('名解/简答 3 字正确答案精确相等判对（细胞壁）', () async {
    final q = Question(
        bankId: 1,
        title: '植物细胞壁的主要成分？',
        correctAnswer: '细胞壁',
        questionType: 'ming_jie',
        createdAt: 'now');
    expect(QuizService.judgeAnswer(q, '细胞壁'), isTrue);
    expect(QuizService.judgeAnswer(q, ' 细胞壁 '), isTrue);
    expect(QuizService.judgeAnswer(q, '细胞膜'), isFalse);
    // 长答案包含匹配仍生效
    final q2 = Question(
        bankId: 1,
        title: 't',
        correctAnswer: '细菌的形态结构',
        questionType: 'jian_da',
        createdAt: 'now');
    expect(QuizService.judgeAnswer(q2, '细菌的形态结构包括球菌、杆菌'), isTrue);
  });

  test('模拟幂等：重复执行 fsrs_cards/error_book 数量不变，手动收藏与卡片保留', () async {
    final db = DatabaseService.instance;
    final bankId = await seedBank('S', 10);
    final qs = await db.getQuestionsByBank(bankId);
    // 用户真实数据：手动收藏 + 一张复习卡（题库内题目）
    await db.addToErrorBook(qs[9].id!);
    await db.upsertFSRSCard(FSRSService.initCard(qs[9].id!, DateTime.now()));

    final r1 = await db.simulateLongTermUse(days: 30);
    expect(r1.error, isNull);
    final cards1 = await db.countAllFsrsCards();
    final errors1 = await db.getErrorBookCount();

    final r2 = await db.simulateLongTermUse(days: 30);
    expect(r2.error, isNull);
    expect(await db.countAllFsrsCards(), cards1); // 卡片数不随重复执行漂移
    expect(await db.getErrorBookCount(), errors1); // 错题数不漂移
    expect(cards1, greaterThan(0));
    // 用户真实数据未被模拟清理（卡片可能被 replace，但必须仍在）
    expect(await db.getFSRSCard(qs[9].id!), isNotNull);
    expect(await db.isInErrorBook(qs[9].id!), isTrue);
  });

  test('备份导入：拒绝 user_version 非法（0）的库', () async {
    final db = DatabaseService.instance;
    await seedBank('B', 3);
    final dir = Directory.systemTemp.createTempSync('backup_check');
    final backup = '${dir.path}/backup.db';
    final exported = await db.exportBackup(backup);
    expect(exported, isNull);
    // 打开副本把 user_version 重置为 0（模拟外部工具重置版本）
    final tmp = await databaseFactory.openDatabase(backup);
    await tmp.execute('PRAGMA user_version = 0');
    await tmp.close();
    final err = await db.validateBackupFile(backup);
    expect(err, isNotNull); // 拒绝导入，避免 onUpgrade(0→6) 破坏性重建清空题目
    // 恢复版本号后仍可正常导入
    final tmp2 = await databaseFactory.openDatabase(backup);
    await tmp2.execute('PRAGMA user_version = 6');
    await tmp2.close();
    final ok = await db.importBackup(backup);
    expect(ok, isNull);
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('KeyCrypto：符合 base64 字符集的明文不被误当 v1 密文', () async {
    const plain16 = '1234567890123456'; // 16 位数字：严格 base64 字符集 + 长度%4==0
    expect(KeyCrypto.decrypt(plain16), plain16);
    const sk = 'sk-abc1234567890xyz';
    expect(KeyCrypto.decrypt(sk), sk);
    // v1 密文（XOR）仍能解
    final v1Cipher = _xorEncrypt('sk-legacy-key-123');
    expect(KeyCrypto.decrypt(v1Cipher), 'sk-legacy-key-123');
  });

  test('重新作答：更新原记录不新增，会话统计差量修正', () async {
    final db = DatabaseService.instance;
    final bankId = await seedBank('R', 3);
    final qs = await db.getQuestionsByBank(bankId);
    // 手动构造会话并加载题目
    final session = QuizSession(
        bankIds: '$bankId', mode: 'single', totalQuestions: 3,
        startTime: DateTime.now().toIso8601String());
    final sessionWithId = QuizSession(
        id: await db.insertSession(session),
        bankIds: session.bankIds,
        mode: session.mode,
        totalQuestions: session.totalQuestions,
        startTime: session.startTime);
    final quizService = QuizService();
    quizService.loadQuiz(questions: qs, session: sessionWithId);

    // 首次答错（正确 A，选 B）
    final r1 = await quizService.submitAnswer('B');
    expect(r1.isCorrect, isFalse);
    expect(await db.getTotalQuestionsAnswered(), 1);

    // 重新作答答对 → 更新原记录（同一 id），不新增记录
    final r2 = await quizService.resubmitAnswer('A');
    expect(r2.isCorrect, isTrue);
    expect(r2.id, r1.id);
    expect(await db.getTotalQuestionsAnswered(), 1);
    // 会话统计差量修正：0对1错 → 1对0错
    final s1 = await db.getSessionById(sessionWithId.id!);
    expect(s1!.correctCount, 1);
    expect(s1.wrongCount, 0);

    // 再改回答错 → 0对1错
    final r3 = await quizService.resubmitAnswer('C');
    expect(r3.isCorrect, isFalse);
    expect(r3.id, r1.id);
    expect(await db.getTotalQuestionsAnswered(), 1);
    final s2 = await db.getSessionById(sessionWithId.id!);
    expect(s2!.correctCount, 0);
    expect(s2.wrongCount, 1);

    // 首次未答的题走正常提交（新增记录）
    final r4 = await quizService.nextQuestion();
    expect(r4, isTrue);
    final r5 = await quizService.submitAnswer('A');
    expect(r5.isCorrect, isTrue);
    expect(await db.getTotalQuestionsAnswered(), 2);
  });

  test('清除模拟数据：模拟数据归零且幂等，无模拟时不动真实数据', () async {
    final db = DatabaseService.instance;
    final bankId = await seedBank('C', 10);
    final qs = await db.getQuestionsByBank(bankId);

    // 场景1：模拟 → 清除
    final r = await db.simulateLongTermUse(days: 30);
    expect(r.error, isNull);
    expect(await db.getTotalQuestionsAnswered(), greaterThan(0));
    final removed = await db.clearSimulatedData();
    expect(removed, greaterThan(0));
    expect(await db.getTotalQuestionsAnswered(), 0);
    expect(await db.countAllFsrsCards(), 0);
    expect((await db.getAllSessions()).length, 0);
    expect(await db.getErrorBookCount(), 0);
    // 幂等：再次清除无操作
    expect(await db.clearSimulatedData(), 0);

    // 场景2：无模拟锚点时，用户真实收藏与复习卡不受影响
    await db.addToErrorBook(qs[0].id!);
    await db.upsertFSRSCard(FSRSService.initCard(qs[0].id!, DateTime.now()));
    await db.clearSimulatedData();
    expect(await db.isInErrorBook(qs[0].id!), isTrue);
    expect(await db.getFSRSCard(qs[0].id!), isNotNull);
  });

  test('主题切换持久化：重启（新实例）后保留', () async {
    SharedPreferences.setMockInitialValues({});
    final ts = ThemeService();
    await ts.init();
    expect(ts.current, AppTheme.brand);
    await ts.switchTo(AppTheme.minimal);
    final ts2 = ThemeService();
    await ts2.init();
    expect(ts2.current, AppTheme.minimal);
  });
}

/// 复刻 v1 XOR 加密（测试解密回退链用）
String _xorEncrypt(String plain) {
  final random = Random(0x5EEDC0DE);
  final bytes = plain.codeUnits;
  final key = List.generate(bytes.length, (_) => random.nextInt(256));
  return base64Encode([
    for (var i = 0; i < bytes.length; i++) bytes[i] ^ key[i],
  ]);
}
