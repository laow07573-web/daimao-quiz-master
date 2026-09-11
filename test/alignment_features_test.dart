import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/models/answer_record.dart';
import 'package:flashcard_app/models/question.dart';
import 'package:flashcard_app/models/question_bank.dart';
import 'package:flashcard_app/models/quiz_session.dart';
import 'package:flashcard_app/services/bank_file_service.dart';
import 'package:flashcard_app/services/database_service.dart';
import 'package:flashcard_app/services/fsrs_service.dart';

/// v1.0.2 对齐里程碑的新功能测试：
/// - 未打标签分组（空知识点 → 未打标签；AI 失败标记独立分组）
/// - 打标签更新
/// - 改判（记录 + 会话统计同步修正）
/// - 隐藏/恢复今日记录（统计排除 hidden）
/// - 模拟：薄弱知识点 / 复习卡到期
/// - 错题导出 JSON（format 标记）→ 可被导入识别
void main() {
  setUp(() async {
    await DatabaseService.instance.close();
    final dir =
        Directory(Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path);
    final dbPath = '${dir.path}/flashcard_app/test_alignment.db';
    DatabaseService.overrideDbPath = dbPath;
    final dbFile = File(dbPath);
    if (await dbFile.exists()) await dbFile.delete();
  });

  tearDown(() async {
    await DatabaseService.instance.close();
    DatabaseService.overrideDbPath = null;
  });

  Future<int> seedBank({String? kp}) async {
    final db = DatabaseService.instance;
    final now = DateTime.now().toIso8601String();
    final bankId =
        await db.insertBank(QuestionBank(name: '测试题库', createdAt: now));
    await db.insertQuestions([
      Question(
          bankId: bankId,
          title: 'q1',
          correctAnswer: 'A',
          knowledgePoint: kp,
          createdAt: now),
    ]);
    final ids = await db.getQuestionsByBank(bankId);
    return ids.first.id!;
  }

  test('空知识点并入「未打标签」分组，且可按该标签取题', () async {
    final db = DatabaseService.instance;
    final untaggedId = await seedBank(); // kp = null
    final taggedId = await seedBank(kp: '血液');
    await db.addToErrorBook(untaggedId);
    await db.addToErrorBook(taggedId);
    await db.upsertFSRSCard(FSRSCardState(
      questionId: untaggedId,
      stability: 1,
      difficulty: 5,
      reviewCount: 1,
      lastReviewAt: DateTime.now(),
      nextReviewAt: DateTime.now().subtract(const Duration(days: 1)),
    ));
    await db.upsertFSRSCard(FSRSCardState(
      questionId: taggedId,
      stability: 1,
      difficulty: 5,
      reviewCount: 1,
      lastReviewAt: DateTime.now(),
      nextReviewAt: DateTime.now().subtract(const Duration(days: 1)),
    ));

    final kps = await db.getKnowledgePointStats('all');
    final byKp = {for (final k in kps) k['kp'] as String: k['cnt'] as int};
    expect(byKp['未打标签'], 1);
    expect(byKp['血液'], 1);

    final untaggedQuestions =
        await db.getFullQuestionsByKnowledgePoint('未打标签', 'all');
    expect(untaggedQuestions.map((q) => q.id).toSet(), {untaggedId});

    expect(await db.getUntaggedErrorCount(), 1);
  });

  test('AI 失败标记不进入知识点分组（与正确率排行同口径）', () async {
    final db = DatabaseService.instance;
    final id = await seedBank();
    await db.addToErrorBook(id);
    // 模拟打标签失败：写入失败标记
    await db.updateQuestionKnowledgePoint(id, 'AI请求失败');
    final kps = await db.getKnowledgePointStats('all');
    final byKp = {for (final k in kps) k['kp'] as String: k['cnt'] as int};
    // v1.0.2 设计审查修复：AI 失败标记不再产生伪分组
    expect(byKp.containsKey('AI请求失败'), isFalse);
    expect(await db.getUntaggedErrorCount(), 0);
    // 打标签成功
    await db.updateQuestionKnowledgePoint(id, '免疫应答');
    final kps2 = await db.getKnowledgePointStats('all');
    expect(
        {for (final k in kps2) k['kp'] as String: k['cnt'] as int}['免疫应答'],
        1);
  });

  test('改判：记录与会话统计同步修正', () async {
    final db = DatabaseService.instance;
    final now = DateTime.now().toIso8601String();
    final bankId =
        await db.insertBank(QuestionBank(name: '测试题库', createdAt: now));
    await db.insertQuestions([
      Question(bankId: bankId, title: 'q1', correctAnswer: 'A', createdAt: now),
    ]);
    final qid = (await db.getQuestionsByBank(bankId)).first.id!;
    final sessionId = await db.insertSession(QuizSession(
      bankIds: '$bankId',
      mode: 'single',
      totalQuestions: 1,
      correctCount: 0,
      wrongCount: 1,
      startTime: now,
      endTime: now,
      durationSeconds: 10,
    ));
    final recordId = await db.insertAnswerRecord(AnswerRecord(
      questionId: qid,
      sessionId: sessionId,
      userAnswer: 'A',
      isCorrect: false,
      answeredAt: now,
    ));

    await db.rejudgeAnswerRecord(recordId, true);
    final records = await db.getSessionDetail(sessionId);
    expect(records.first['is_correct'], 1);
    final sessions = await db.getAllSessions();
    expect(sessions.first.correctCount, 1);
    expect(sessions.first.wrongCount, 0);

    // 反向改判
    await db.rejudgeAnswerRecord(recordId, false);
    final records2 = await db.getSessionDetail(sessionId);
    expect(records2.first['is_correct'], 0);
    final sessions2 = await db.getAllSessions();
    expect(sessions2.first.correctCount, 0);
    expect(sessions2.first.wrongCount, 1);
  });

  test('隐藏/恢复今日记录：统计口径排除 hidden', () async {
    final db = DatabaseService.instance;
    final now = DateTime.now().toIso8601String();
    final bankId =
        await db.insertBank(QuestionBank(name: '测试题库', createdAt: now));
    await db.insertQuestions([
      Question(bankId: bankId, title: 'q1', correctAnswer: 'A', createdAt: now),
    ]);
    final qid = (await db.getQuestionsByBank(bankId)).first.id!;
    for (var i = 0; i < 5; i++) {
      await db.insertAnswerRecord(AnswerRecord(
        questionId: qid,
        userAnswer: 'A',
        isCorrect: true,
        answeredAt: now,
      ));
    }

    final before = await db.getDailyStats(1);
    expect(before.last['total'], 5);

    final hidden = await db.hideTodayRecords();
    expect(hidden, 5);
    expect(await db.getHiddenTodayRecordCount(), 5);
    final after = await db.getDailyStats(1);
    expect(after.last['total'], 0);
    final period = await db.getPeriodStats('week');
    expect(period['questions'], 0);

    await db.restoreTodayRecords();
    final restored = await db.getDailyStats(1);
    expect(restored.last['total'], 5);
    expect(await db.getHiddenTodayRecordCount(), 0);
  });

  test('模拟：基于当前题库 + 薄弱知识点打标签 + 复习卡今天到期', () async {
    final db = DatabaseService.instance;
    // 基于"当前题库"生成（对齐里程碑：不再自建模拟题库）
    final now = DateTime.now().toIso8601String();
    final bankId =
        await db.insertBank(QuestionBank(name: '真实题库', createdAt: now));
    await db.insertQuestions([
      for (var i = 1; i <= 20; i++)
        Question(
            bankId: bankId,
            title: '题$i',
            correctAnswer: 'A',
            options: const ['A', 'B', 'C'],
            createdAt: now),
    ]);

    final result = await db.simulateLongTermUse(
        days: 30, randomWeakKp: true, dueToday: true);
    expect(result.error, isNull);
    expect(result.records, greaterThan(0));
    expect(result.cards, greaterThan(0));

    // 薄弱知识点标签已打到当前题库的题上
    final questions = await db.getQuestionsByBank(bankId);
    final tagged = questions
        .where((q) => q.knowledgePoint != null && q.knowledgePoint!.isNotEmpty)
        .length;
    expect(tagged, greaterThan(0));

    // 复习卡全部今天到期（dueToday 影响全部卡）
    final allCards = await db.countAllFsrsCards();
    expect(result.cards, allCards);
    final dueRows = await db.countDueFsrsCards();
    expect(dueRows, allCards);

    // 错题本里有模拟错题
    final errorStats = await db.getErrorStatsByBank();
    final sim = errorStats.firstWhere((s) => s['bank_id'] == bankId);
    expect(sim['all_count'], greaterThan(0));

    // 重复执行先清理再重生成（固定种子 → 记录数不变）
    final result2 = await db.simulateLongTermUse(
        days: 30, randomWeakKp: true, dueToday: true);
    expect(result2.records, result.records);
    expect(result2.cards, result.cards);
  });

  test('模拟：题库为空时拦截', () async {
    final db = DatabaseService.instance;
    final result = await db.simulateLongTermUse(days: 30);
    expect(result.error, isNotNull);
    expect(result.records, 0);
  });

  test('错题导出 JSON 带 format 标记，可被导入识别', () async {
    final db = DatabaseService.instance;
    final now = DateTime.now().toIso8601String();
    final bankId =
        await db.insertBank(QuestionBank(name: '测试题库', createdAt: now));
    await db.insertQuestions([
      Question(
          bankId: bankId,
          title: 'q1',
          correctAnswer: 'A',
          knowledgePoint: '血液',
          createdAt: now),
    ]);
    final qid = (await db.getQuestionsByBank(bankId)).first.id!;
    await db.addToErrorBook(qid);
    await db.upsertFSRSCard(FSRSCardState(
      questionId: qid,
      stability: 1,
      difficulty: 5,
      reviewCount: 1,
      lastReviewAt: DateTime.now(),
      nextReviewAt: DateTime.now().subtract(const Duration(days: 1)),
    ));

    final questions = await db.getFullErrorQuestions('all');
    expect(questions.length, 1);

    // 手工构造与 AppState.exportErrorQuestionsJson 一致的格式
    final file = File(
        '${Directory.systemTemp.path}/test_export_${DateTime.now().millisecondsSinceEpoch}.json');
    await file.writeAsString(
        '{"format":"maojuan-quiz-questions","name":"错题导出_1","count":1,"questions":[{"title":"q1","options":[],"correct_answer":"A","analysis":null,"question_type":"single_choice","knowledge_point":"血液"}]}');

    final (groups, err) = await BankFileService.parseJsonFile(file.path);
    expect(err, isNull);
    expect(groups.length, 1);
    expect(groups.keys.first, '错题导出_1');
    expect(groups.values.first.length, 1);
    expect(groups.values.first.first.title, 'q1');
    expect(groups.values.first.first.knowledgePoint, '血液');
    await file.delete();
  });

  test('题库导出（整理后字段）→ 回读 → 导入入库闭环', () async {
    final db = DatabaseService.instance;
    final now = DateTime.now().toIso8601String();
    final bankId =
        await db.insertBank(QuestionBank(name: '导出测试题库', createdAt: now));
    await db.insertQuestions([
      Question(
          bankId: bankId,
          title: '单选题A',
          options: const ['选项1', '选项2', '选项3', '选项4'],
          correctAnswer: 'B',
          analysis: '解析内容',
          questionType: 'single_choice',
          knowledgePoint: '细菌的形态结构',
          createdAt: now),
      Question(
          bankId: bankId,
          title: '填空题B',
          correctAnswer: '白细胞',
          questionType: 'fill_blank',
          knowledgePoint: '血液学检验',
          createdAt: now),
    ]);
    final bank = (await db.getAllBanks()).first;

    // 导出：带 format 标记 + 题库名 + 整理后字段
    final dest = '${Directory.systemTemp.path}/bank_export_${DateTime.now().millisecondsSinceEpoch}.json';
    final exported = await BankFileService.exportBank(bankId, bank.name, dest);
    expect(exported, isNotNull);
    final raw = await File(exported!).readAsString();
    expect(raw, contains('"format": "maojuan-quiz-questions"'));
    expect(raw, contains('"name": "导出测试题库"'));
    expect(raw, contains('"knowledge_point": "细菌的形态结构"'));
    expect(raw, contains('"analysis": "解析内容"'));

    // 回读解析：题目数量与字段一致
    final (groups, err2) = await BankFileService.parseJsonFile(exported);
    expect(err2, isNull);
    expect(groups.length, 1);
    expect(groups.keys.first, '导出测试题库');
    final questions = groups.values.first;
    expect(questions.length, 2);
    final byTitle = {for (final q in questions) q.title: q};
    expect(byTitle['单选题A']!.knowledgePoint, '细菌的形态结构');
    expect(byTitle['单选题A']!.analysis, '解析内容');
    expect(byTitle['填空题B']!.questionType, 'fill_blank');
    expect(byTitle['填空题B']!.knowledgePoint, '血液学检验');

    // 导入入库闭环：导出文件直接导入为可用题库
    final (bankCount, questionCount, importErr, renamed) =
        await BankFileService.importJsonFile(exported);
    expect(importErr, isNull);
    expect(renamed, 0);
    expect(bankCount, 1);
    expect(questionCount, 2);
    final importedBanks = await db.getAllBanks();
    final imported = importedBanks.firstWhere((b) => b.name == '导出测试题库');
    final importedQs = await db.getQuestionsByBank(imported.id!);
    expect(importedQs.length, 2);
    expect(
        importedQs.any((q) =>
            q.title == '单选题A' &&
            q.knowledgePoint == '细菌的形态结构' &&
            q.analysis == '解析内容'),
        isTrue);
    await File(exported).delete();
  });
}
