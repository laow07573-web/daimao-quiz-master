import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/models/answer_record.dart';
import 'package:flashcard_app/models/question.dart';
import 'package:flashcard_app/models/question_bank.dart';
import 'package:flashcard_app/screens/error_book_screen.dart' show questionStatLine;
import 'package:flashcard_app/services/app_state.dart';
import 'package:flashcard_app/services/bank_file_service.dart';
import 'package:flashcard_app/services/database_service.dart';
import 'package:flashcard_app/services/fsrs_service.dart';

/// 错题导出增强 + 逐题统计的回归测试。
///
/// 覆盖产品要求：按「错得最多」排序导出、按时间窗（近 7 天 / 近 30 天）筛选、
/// 自定义选题导出，以及卡片要显示的「做过几次 / 正确率 / FSRS」数据来源。
/// 另外锁住一条兼容性：**带统计字段的导出文件仍可被当前版本导入**。
void main() {
  late Directory tmp;

  setUp(() async {
    await DatabaseService.instance.close();
    tmp = Directory.systemTemp.createTempSync('mj_error_export_');
    DatabaseService.overrideDbPath = '${tmp.path}/flashcard.db';
  });

  tearDown(() async {
    await DatabaseService.instance.close();
    DatabaseService.overrideDbPath = null;
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// 造一道错题：入库 + 加入错题本 + 若干次作答（wrong 次错、其余对）
  /// [at]：显式指定作答时刻（时间窗边界用），默认按 [daysAgo] 折算
  Future<int> seedErrorQuestion(
    String title, {
    required int wrong,
    required int correct,
    required int daysAgo,
    String kp = '测试知识点',
    DateTime? at,
  }) async {
    final db = DatabaseService.instance;
    final now = DateTime.now();
    final answeredAt = at ?? now.subtract(Duration(days: daysAgo));
    final stamp = answeredAt.toIso8601String();

    final bankId = await db.insertBank(
        QuestionBank(name: '题库_$title', createdAt: stamp));
    await db.insertQuestions([
      Question(
        bankId: bankId,
        title: title,
        options: const ['A', 'B'],
        correctAnswer: 'A',
        knowledgePoint: kp,
        createdAt: stamp,
      ),
    ]);
    final qid = (await db.getQuestionsByBank(bankId)).first.id!;
    await db.addToErrorBook(qid);

    for (var i = 0; i < wrong; i++) {
      await db.insertAnswerRecord(AnswerRecord(
          questionId: qid,
          userAnswer: 'B',
          isCorrect: false,
          answeredAt: stamp));
    }
    for (var i = 0; i < correct; i++) {
      await db.insertAnswerRecord(AnswerRecord(
          questionId: qid,
          userAnswer: 'A',
          isCorrect: true,
          answeredAt: stamp));
    }
    return qid;
  }

  /// 取题目所属题库 id（按题库范围测试用）
  Future<int> bankOf(int questionId) async {
    final rows = await (await DatabaseService.instance.database).query(
      'questions',
      columns: ['bank_id'],
      where: 'id = ?',
      whereArgs: [questionId],
    );
    return rows.first['bank_id'] as int;
  }

  /// 造一道错题，创建时间与每次作答时间/对错可分别指定，
  /// 用于验证「时间窗看的是最近一次作答」「错次/作答次数两个别名」这类口径。
  Future<int> seedDetailed(
    String title, {
    String kp = '测试知识点',
    required DateTime createdAt,
    required List<(bool correct, DateTime at)> answers,
  }) async {
    final db = DatabaseService.instance;
    final bankId = await db.insertBank(
        QuestionBank(name: '题库_$title', createdAt: createdAt.toIso8601String()));
    await db.insertQuestions([
      Question(
        bankId: bankId,
        title: title,
        options: const ['A', 'B'],
        correctAnswer: 'A',
        knowledgePoint: kp,
        createdAt: createdAt.toIso8601String(),
      ),
    ]);
    final qid = (await db.getQuestionsByBank(bankId)).first.id!;
    await db.addToErrorBook(qid);
    for (final (ok, at) in answers) {
      await db.insertAnswerRecord(AnswerRecord(
          questionId: qid,
          userAnswer: ok ? 'A' : 'B',
          isCorrect: ok,
          answeredAt: at.toIso8601String()));
    }
    return qid;
  }

  /// 读出导出文件里的题目标题（按文件内顺序）
  List<String> titlesOf(String path) => (jsonDecode(File(path).readAsStringSync())
          ['questions'] as List)
      .map((q) => (q as Map)['title'] as String)
      .toList();

  group('批量作答统计', () {
    test('多题一次聚合，且口径一致（排除 hidden / 模拟数据）', () async {
      final db = DatabaseService.instance;
      final a = await seedErrorQuestion('A', wrong: 2, correct: 1, daysAgo: 1);
      final b = await seedErrorQuestion('B', wrong: 3, correct: 0, daysAgo: 10);

      final stats = await db.getQuestionStatsByIds([a, b]);
      expect(stats[a], (3, 1));
      expect(stats[b], (3, 0));

      // 隐藏的记录不计入
      final rows = await (await db.database)
          .query('answer_records', where: 'question_id = ?', whereArgs: [a]);
      await (await db.database).update('answer_records', {'hidden': 1},
          where: 'id = ?', whereArgs: [rows.first['id']]);
      final after = await db.getQuestionStatsByIds([a]);
      expect(after[a], (2, 1), reason: 'hidden=1 的记录不应计入');
    });

    test('空列表返回空（不抛错、不查库）', () async {
      expect(await DatabaseService.instance.getQuestionStatsByIds([]), isEmpty);
    });

    test('没有任何作答记录的题不出现在结果里', () async {
      final stats = await DatabaseService.instance.getQuestionStatsByIds([999999]);
      expect(stats, isEmpty);
    });
  });

  group('导出：排序 / 时间窗 / 自定义选题', () {
    test('默认按「错得最多」排序', () async {
      final appState = AppState();
      await appState.init();
      await seedErrorQuestion('错2次', wrong: 2, correct: 0, daysAgo: 1);
      await seedErrorQuestion('错5次', wrong: 5, correct: 1, daysAgo: 1);
      await seedErrorQuestion('错3次', wrong: 3, correct: 0, daysAgo: 1);

      final (path, count) =
          await appState.exportErrorQuestionsJson('all', includeStats: true);
      expect(count, 3);
      expect(path, isNotNull);

      final data = jsonDecode(await File(path!).readAsString());
      final titles = (data['questions'] as List)
          .map((q) => q['title'] as String)
          .toList();
      expect(titles.first, '错5次', reason: '错得最多的应排在最前');
      expect(titles.last, '错2次');
    });

    test('近 7 天时间窗：只导出最近做过的，第 8 天的排除在外', () async {
      final appState = AppState();
      await appState.init();
      await seedErrorQuestion('今天做过', wrong: 1, correct: 0, daysAgo: 0);
      await seedErrorQuestion('6天前做过', wrong: 9, correct: 0, daysAgo: 6);
      await seedErrorQuestion('8天前做过', wrong: 9, correct: 0, daysAgo: 8);

      final (path, count) =
          await appState.exportErrorQuestionsJson('all', window: '7d');
      expect(count, 2);
      final data = jsonDecode(await File(path!).readAsString());
      final titles =
          (data['questions'] as List).map((q) => q['title'] as String).toSet();
      expect(titles, containsAll(['今天做过', '6天前做过']));
      expect(titles, isNot(contains('8天前做过')));
    });

    test('近 30 天时间窗：第 31 天排除', () async {
      final appState = AppState();
      await appState.init();
      await seedErrorQuestion('10天前', wrong: 1, correct: 0, daysAgo: 10);
      await seedErrorQuestion('40天前', wrong: 1, correct: 0, daysAgo: 40);

      final (_, count) =
          await appState.exportErrorQuestionsJson('all', window: '30d');
      expect(count, 1);
    });

    test('自定义选题：只导出指定 id', () async {
      final appState = AppState();
      await appState.init();
      final keep = await seedErrorQuestion('要导出', wrong: 1, correct: 0, daysAgo: 1);
      await seedErrorQuestion('不要导出', wrong: 1, correct: 0, daysAgo: 1);

      final (path, count) = await appState.exportErrorQuestionsJson('all',
          questionIds: {keep});
      expect(count, 1);
      final data = jsonDecode(await File(path!).readAsString());
      expect((data['questions'] as List).single['title'], '要导出');
    });

    test('按知识点导出（最薄弱点）', () async {
      final appState = AppState();
      await appState.init();
      await seedErrorQuestion('血液题', wrong: 1, correct: 0, daysAgo: 1, kp: '血液');
      await seedErrorQuestion('免疫题', wrong: 1, correct: 0, daysAgo: 1, kp: '免疫');

      final (_, count) = await appState.exportErrorQuestionsJson('all',
          knowledgePoint: '血液');
      expect(count, 1);
    });

    test('无题可导出时返回 (null, 0)', () async {
      final appState = AppState();
      await appState.init();
      final (path, count) = await appState.exportErrorQuestionsJson('all');
      expect(path, isNull);
      expect(count, 0);
    });
  });

  group('导出格式兼容性', () {
    test('带 stats/fsrs 的导出文件仍可被导入（附加键向后兼容）', () async {
      final appState = AppState();
      await appState.init();
      await seedErrorQuestion('带统计的题', wrong: 2, correct: 1, daysAgo: 1);

      final (path, _) =
          await appState.exportErrorQuestionsJson('all', includeStats: true);
      final data = jsonDecode(await File(path!).readAsString());
      final q = (data['questions'] as List).first;

      // 附加字段确实写进去了
      expect(q['stats'], isNotNull);
      expect(q['stats']['answered'], 3);
      expect(q['stats']['correct'], 1);
      expect(q['stats']['wrong'], 2);

      // 关键：导入侧只读已知键，忽略未知键——文件仍可被识别为猫卷题库
      final (groups, err) = await BankFileService.parseJsonFile(path);
      expect(err, isNull, reason: '附加 stats/fsrs/filter 不应导致导入失败');
      expect(groups.length, 1);
      expect(groups.values.first.single.title, '带统计的题');
    });

    test('includeStats: false（默认）不写 stats / fsrs 键', () async {
      final appState = AppState();
      await appState.init();
      await seedErrorQuestion('只有题干', wrong: 1, correct: 0, daysAgo: 1);

      final (path, _) = await appState.exportErrorQuestionsJson('all');
      final data = jsonDecode(await File(path!).readAsString());
      final q = (data['questions'] as List).single as Map;
      expect(q.containsKey('stats'), isFalse);
      expect(q.containsKey('fsrs'), isFalse);
      // filter 只记录真正生效的条件，不再写出恒为空的 limit
      expect(data['filter'], {'mode': 'all'});
    });
  });

  group('最薄弱知识点：范围与导出同口径', () {
    test('「未打标签」导出的是空知识点题，不是字面量标签', () async {
      final appState = AppState();
      await appState.init();
      await seedErrorQuestion('没标签A', wrong: 1, correct: 0, daysAgo: 1, kp: '');
      await seedErrorQuestion('没标签B', wrong: 3, correct: 0, daysAgo: 1, kp: '');
      await seedErrorQuestion('有标签', wrong: 9, correct: 0, daysAgo: 1, kp: '血液');

      // 面板分组：空知识点并入「未打标签」，且它是错题最多的一组
      final kps = await appState.getKnowledgePointStats('all');
      expect(kps.first['kp'], '未打标签');
      expect(kps.first['cnt'], 2);

      // 导出必须走同一约定，否则面板点进导出恒为「暂无错题」
      final (path, count) = await appState.exportErrorQuestionsJson('all',
          knowledgePoint: '未打标签');
      expect(count, 2);
      final data = jsonDecode(await File(path!).readAsString());
      final titles =
          (data['questions'] as List).map((q) => q['title'] as String).toSet();
      expect(titles, {'没标签A', '没标签B'});
      expect((data['filter'] as Map)['knowledge_point'], '未打标签');
    });

    test('知识点分组随已选题库收窄（面板 / 下钻 / 导出同范围）', () async {
      final appState = AppState();
      await appState.init();
      final qa = await seedErrorQuestion('甲库血液', wrong: 1, correct: 0, daysAgo: 1, kp: '血液');
      await seedErrorQuestion('乙库免疫', wrong: 1, correct: 0, daysAgo: 1, kp: '免疫');
      final bankA = await bankOf(qa);

      final all = await appState.getKnowledgePointStats('all');
      expect(all.map((e) => e['kp']).toSet(), {'血液', '免疫'});

      final scoped =
          await appState.getKnowledgePointStats('all', bankIds: {bankA});
      expect(scoped.map((e) => e['kp']).toSet(), {'血液'},
          reason: '勾选题库后，面板只应列出该库的知识点');

      final (_, count) = await appState.exportErrorQuestionsJson('all',
          bankIds: {bankA}, knowledgePoint: '血液');
      expect(count, 1, reason: '导出的「最薄弱点」必须与面板同一个范围');
    });
  });

  group('排序：最近做过的在前', () {
    test('recentFirst 时最近作答的排最前（不看错次）', () async {
      final appState = AppState();
      await appState.init();
      await seedErrorQuestion('很久以前错很多次', wrong: 9, correct: 0, daysAgo: 20);
      await seedErrorQuestion('昨天才错一次', wrong: 1, correct: 0, daysAgo: 1);

      final (byWrong, _) = await appState.exportErrorQuestionsJson('all');
      final wrongFirst = jsonDecode(await File(byWrong!).readAsString());
      expect((wrongFirst['questions'] as List).first['title'], '很久以前错很多次');

      final (byRecent, _) = await appState.exportErrorQuestionsJson('all',
          recentFirst: true);
      final recentFirst = jsonDecode(await File(byRecent!).readAsString());
      expect((recentFirst['questions'] as List).first['title'], '昨天才错一次');
    });
  });

  group('时间窗边界（严格按天数）', () {
    test('7 天窗：6 天 23 小时 55 分在内，7 天零 5 分在外', () async {
      final appState = AppState();
      await appState.init();
      final now = DateTime.now();
      await seedErrorQuestion('刚过 6 天',
          wrong: 1, correct: 0, daysAgo: 0,
          at: now.subtract(const Duration(days: 6, hours: 23, minutes: 55)));
      await seedErrorQuestion('刚过 7 天',
          wrong: 1, correct: 0, daysAgo: 0,
          at: now.subtract(const Duration(days: 7, minutes: 5)));

      final (path, count) =
          await appState.exportErrorQuestionsJson('all', window: '7d');
      expect(count, 1, reason: '7 天前那一刻起算的题应被排除');
      final data = jsonDecode(await File(path!).readAsString());
      expect((data['questions'] as List).single['title'], '刚过 6 天');
    });

    test('30 天窗：29 天 23 小时在内，30 天零 5 分在外', () async {
      final appState = AppState();
      await appState.init();
      final now = DateTime.now();
      await seedErrorQuestion('刚过 29 天',
          wrong: 1, correct: 0, daysAgo: 0,
          at: now.subtract(const Duration(days: 29, hours: 23)));
      await seedErrorQuestion('刚过 30 天',
          wrong: 1, correct: 0, daysAgo: 0,
          at: now.subtract(const Duration(days: 30, minutes: 5)));

      final (_, count) =
          await appState.exportErrorQuestionsJson('all', window: '30d');
      expect(count, 1);
    });
  });

  group('自定义选题：分块与合并排序', () {
    test('>500 题（跨 3 个分块）仍全部导出且全局按错次排序', () async {
      final appState = AppState();
      await appState.init();
      final db = DatabaseService.instance;
      final bankId = await db.insertBank(
          QuestionBank(name: '大批量', createdAt: DateTime.now().toIso8601String()));

      // 1100 题：前 1000 题没有作答记录（错 0 次），后 100 题各错 1 次。
      // 分块按 id 顺序切，若合并后不重排，前 500 条会排在最前面。
      await db.insertQuestions([
        for (var i = 0; i < 1100; i++)
          Question(
            bankId: bankId,
            title: 'Q$i',
            options: const ['A', 'B'],
            correctAnswer: 'A',
            knowledgePoint: '批量',
            createdAt: DateTime.now().toIso8601String(),
          ),
      ]);
      final all = await db.getQuestionsByBank(bankId);
      expect(all.length, 1100);

      final ids = all.map((q) => q.id!).toList();
      for (var i = 1000; i < 1100; i++) {
        await db.insertAnswerRecord(AnswerRecord(
            questionId: ids[i],
            userAnswer: 'B',
            isCorrect: false,
            answeredAt: DateTime.now().toIso8601String()));
      }

      final (path, count) = await appState.exportErrorQuestionsJson('all',
          questionIds: ids.toSet(), includeStats: true);
      expect(count, 1100, reason: '分块不应漏题，也不应抛 too many SQL variables');

      final data = jsonDecode(await File(path!).readAsString());
      final questions = (data['questions'] as List).cast<Map>();
      expect(questions.length, 1100);
      // 错 1 次的 100 题必须整体排在错 0 次的题前面；同错次按 id 倒序
      expect(questions.first['title'], 'Q1099');
      expect(questions[99]['title'], 'Q1000');
      expect(
        questions.take(100).every((q) => (q['stats'] as Map)['wrong'] == 1),
        isTrue,
      );
      expect(questions[100]['title'], 'Q999');
    });

    test('连续两次导出文件名不同，两份都留；陈旧导出会被回收', () async {
      final appState = AppState();
      await appState.init();
      await seedErrorQuestion('导出两次', wrong: 1, correct: 0, daysAgo: 1);

      final (p1, c1) = await appState.exportErrorQuestionsJson('all');
      final (p2, c2) = await appState.exportErrorQuestionsJson('all');
      expect(c1, 1);
      expect(c2, 1);
      expect(p1, isNot(p2), reason: '文件名撞车会让后一次覆盖前一次');
      expect(File(p1!).existsSync(), isTrue,
          reason: '刚导出的另一份不能立刻删掉——它可能还在分享目标手里');
      expect(File(p2!).existsSync(), isTrue);

      // 造一个两小时前的旧导出文件：下一次导出应把它回收
      final stale = File('${Directory.systemTemp.path}/错题导出_1.json');
      stale.writeAsStringSync('{}');
      stale.setLastModifiedSync(
          DateTime.now().subtract(const Duration(hours: 2)));
      await appState.exportErrorQuestionsJson('all');
      expect(stale.existsSync(), isFalse,
          reason: '陈旧的导出文件要回收，否则缓存目录只增不减');
      expect(File(p2).existsSync(), isTrue);
    });
  });

  group('错题卡片数据与文案', () {
    test('getErrorQuestionCards：作答统计与 FSRS 卡一次取回', () async {
      final appState = AppState();
      await appState.init();
      final qid = await seedErrorQuestion('卡片题', wrong: 3, correct: 1, daysAgo: 1);

      final cards = await appState.getErrorQuestionCards('all');
      expect(cards.length, 1);
      final it = cards.single;
      expect(it.answered, 4);
      expect(it.correct, 1);
      // 没写过 FSRS 卡时为 null（文案要能容忍）
      expect(it.card, isNull);

      // 写一张卡后应能取到
      await DatabaseService.instance.upsertFSRSCard(FSRSCardState(
        questionId: qid,
        stability: 2.5,
        difficulty: 5.0,
        reviewCount: 3,
        lastReviewAt: DateTime.now().subtract(const Duration(days: 2)),
        nextReviewAt: DateTime.now().subtract(const Duration(days: 1)),
      ));
      final withCard = (await appState.getErrorQuestionCards('all')).single;
      expect(withCard.card, isNotNull);
      expect(withCard.card!.reviewCount, 3);
    });

    test('questionStatLine：做过几次 · 正确率 · FSRS 轮数 · 下次复习', () {
      final q = Question(
        bankId: 1,
        title: '文案题',
        options: const ['A', 'B'],
        correctAnswer: 'A',
        createdAt: DateTime.now().toIso8601String(),
      );
      final card = FSRSCardState(
        questionId: 1,
        stability: 1.0,
        difficulty: 5.0,
        reviewCount: 4,
        lastReviewAt: DateTime.now().subtract(const Duration(days: 3)),
        // 已过期一天：错题卡片上要能看出「已到期」
        nextReviewAt: DateTime.now().subtract(const Duration(days: 1)),
      );

      final line = questionStatLine(
          (question: q, answered: 3, correct: 2, card: card));
      expect(line, contains('做过 3 次'));
      expect(line, contains('正确率 67%'));
      expect(line, contains('FSRS 复习 4 轮'));
      expect(line, contains('下次复习：已到期1天'));

      // 没作答题时不要显示「正确率 NaN%」
      final noStat = questionStatLine(
          (question: q, answered: 0, correct: 0, card: null));
      expect(noStat, '做过 0 次');
      expect(noStat, isNot(contains('正确率')));

      // 全错（correct = 0）也要显示正确率 0%，不能被「有值才显示」的守卫吞掉
      final allWrong = questionStatLine(
          (question: q, answered: 3, correct: 0, card: null));
      expect(allWrong, contains('正确率 0%'));

      // 刚建卡还没复习（reviewCount = 0）不写「FSRS 复习 0 轮」，但下次复习要在
      final fresh = questionStatLine((
        question: q,
        answered: 1,
        correct: 1,
        card: FSRSCardState(
          questionId: 1,
          stability: 1.0,
          difficulty: 5.0,
          reviewCount: 0,
          lastReviewAt: DateTime.now(),
          nextReviewAt: DateTime.now().add(const Duration(days: 2)),
        ),
      ));
      expect(fresh, isNot(contains('复习 0 轮')));
      expect(fresh, contains('下次复习：2天后'));
    });
  });

  group('排序口径：两条路径必须同序', () {
    test('错次 → 作答次数 → id 三级降序，分块与非分块结果一致', () async {
      final appState = AppState();
      await appState.init();
      final now = DateTime.now();

      // A/B：错次相同（2），作答次数不同（7 / 4）——只有按 answered 兜底才排得出先后
      final a = await seedDetailed('A(错2答7)', createdAt: now, answers: [
        for (var i = 0; i < 2; i++) (false, now.subtract(Duration(minutes: i + 3))),
        for (var i = 0; i < 5; i++) (true, now.subtract(Duration(minutes: i + 10))),
      ]);
      final b = await seedDetailed('B(错2答4)', createdAt: now, answers: [
        for (var i = 0; i < 2; i++) (false, now.subtract(Duration(minutes: i + 3))),
        for (var i = 0; i < 2; i++) (true, now.subtract(Duration(minutes: i + 10))),
      ]);
      // C/D：两个键完全相同，只剩 id 兜底
      final c = await seedDetailed('C(并列)', createdAt: now,
          answers: [(false, now.subtract(const Duration(minutes: 30)))]);
      final d = await seedDetailed('D(并列)', createdAt: now,
          answers: [(false, now.subtract(const Duration(minutes: 30)))]);

      const expected = ['A(错2答7)', 'B(错2答4)', 'D(并列)', 'C(并列)'];

      // 路径一：不带 questionIds（SQL 直接排序）
      final (viaSql, count1) =
          await appState.exportErrorQuestionsJson('all', includeStats: true);
      expect(count1, 4);
      expect(titlesOf(viaSql!), expected, reason: '错次降序 → 作答次数降序 → id 降序');

      // 路径二：带 questionIds（分块后 Dart 侧重排）——顺序必须一模一样
      final (viaDart, _) = await appState.exportErrorQuestionsJson('all',
          questionIds: {a, b, c, d}, includeStats: true);
      expect(titlesOf(viaDart!), expected,
          reason: '分块合并后若忘了重排，这里会变成插入顺序');

      // 两个统计别名各自正确（防止 answered_count / wrong_count 张冠李戴）
      final rows =
          (jsonDecode(File(viaSql).readAsStringSync())['questions'] as List)
              .cast<Map>();
      final stats = {
        for (final r in rows) r['title'] as String: r['stats'] as Map
      };
      expect(stats['A(错2答7)']!['wrong'], 2);
      expect(stats['A(错2答7)']!['answered'], 7);
      expect(stats['B(错2答4)']!['wrong'], 2);
      expect(stats['B(错2答4)']!['answered'], 4);
      // 分块上限必须低于旧 SQLite 的绑定变量上限（结构断言：本机 SQLite 太新，
      // 行为层测不出「too many SQL variables」）
      expect(DatabaseService.maxBindingVars, lessThan(999));
    });

    test('recentFirst 并列时也用 id 兜底（两路径同序）', () async {
      final appState = AppState();
      await appState.init();
      final at = DateTime.now().subtract(const Duration(hours: 2));
      // 两道题最近一次作答时间完全相同
      final c = await seedDetailed('更早建的', createdAt: at, answers: [(false, at)]);
      final d = await seedDetailed('更晚建的', createdAt: at, answers: [(false, at)]);

      final (viaSql, _) = await appState.exportErrorQuestionsJson('all',
          recentFirst: true);
      final (viaDart, _) = await appState.exportErrorQuestionsJson('all',
          questionIds: {c, d}, recentFirst: true);
      expect(titlesOf(viaSql!), ['更晚建的', '更早建的'], reason: '并列时 id 降序');
      expect(titlesOf(viaDart!), titlesOf(viaSql));
    });
  });

  group('时间窗口径：看最近一次作答', () {
    test('按 MAX(answered_at) 过滤，不看创建时间也不看首次作答', () async {
      final appState = AppState();
      await appState.init();
      final now = DateTime.now();
      // 40 天前建库、昨天才答过 → 7 天内
      await seedDetailed('老题新答',
          createdAt: now.subtract(const Duration(days: 40)),
          answers: [(false, now.subtract(const Duration(days: 1)))]);
      // 今天建的、8 天前答过（导入的历史数据）→ 7 天外
      await seedDetailed('新题旧答', createdAt: now,
          answers: [(false, now.subtract(const Duration(days: 8)))]);
      // 10 天前错过、昨天答对 → 最近一次在窗内
      await seedDetailed('先错后对',
          createdAt: now.subtract(const Duration(days: 12)),
          answers: [
            (false, now.subtract(const Duration(days: 10))),
            (true, now.subtract(const Duration(days: 1))),
          ]);

      final (path, count) =
          await appState.exportErrorQuestionsJson('all', window: '7d');
      expect(count, 2);
      expect(titlesOf(path!), containsAll(['老题新答', '先错后对']));
      expect(titlesOf(path), isNot(contains('新题旧答')),
          reason: '按首次作答或创建时间过滤都会误判这两题');
    });
  });

  group('自定义选题的语义边界', () {
    test('bankIds 真正生效，且与 questionIds 是与关系', () async {
      final appState = AppState();
      await appState.init();
      final now = DateTime.now();
      final qa = await seedDetailed('甲库血液题',
          kp: '血液', createdAt: now, answers: [(false, now)]);
      final qb = await seedDetailed('乙库血液题',
          kp: '血液', createdAt: now, answers: [(false, now)]);
      final bankA = await bankOf(qa);

      // 两个库都有一道「血液」题，只给甲库 → 只能导出甲库那道
      final (p1, c1) = await appState.exportErrorQuestionsJson('all',
          bankIds: {bankA}, knowledgePoint: '血液');
      expect(c1, 1);
      expect(titlesOf(p1!), ['甲库血液题'], reason: 'bankIds 没生效时这里会是 2 题');

      // 指定乙库的题 + 只要甲库 → 空（两个条件是 AND）
      final (p2, c2) = await appState.exportErrorQuestionsJson('all',
          bankIds: {bankA}, questionIds: {qb});
      expect(c2, 0);
      expect(p2, isNull);
    });

    test('传空集合 = 一道都没选 → 导出空，不回退成「当前筛选全部」', () async {
      final appState = AppState();
      await appState.init();
      await seedErrorQuestion('有错题', wrong: 1, correct: 0, daysAgo: 1);

      final (path, count) =
          await appState.exportErrorQuestionsJson('all', questionIds: {});
      expect(path, isNull);
      expect(count, 0);
    });

    test('指定 questionIds 时不受错题本范围影响（不在错题本也能导出）', () async {
      final appState = AppState();
      await appState.init();
      final db = DatabaseService.instance;
      final bankId = await db.insertBank(QuestionBank(
          name: '没进错题本', createdAt: DateTime.now().toIso8601String()));
      await db.insertQuestions([
        Question(
          bankId: bankId,
          title: '普通题',
          options: const ['A', 'B'],
          correctAnswer: 'A',
          createdAt: DateTime.now().toIso8601String(),
        ),
      ]);
      final qid = (await db.getQuestionsByBank(bankId)).first.id!;

      final (path, count) = await appState.exportErrorQuestionsJson('all',
          questionIds: {qid}, includeStats: true);
      expect(count, 1);
      expect(titlesOf(path!), ['普通题']);
      // 没有任何作答记录时不能崩，统计为零
      final q = (jsonDecode(File(path).readAsStringSync())['questions'] as List)
          .single as Map;
      expect((q['stats'] as Map)['answered'], 0);
      expect((q['stats'] as Map)['last_answered_at'], isNull);
    });
  });

  group('卡片数据：映射与字段', () {
    test('一题有 FSRS 卡、一题没有 → 各归各的，不错配', () async {
      final appState = AppState();
      await appState.init();
      final withCard = await seedErrorQuestion('有卡', wrong: 2, correct: 1, daysAgo: 3);
      await seedErrorQuestion('无卡', wrong: 5, correct: 0, daysAgo: 1);

      await DatabaseService.instance.upsertFSRSCard(FSRSCardState(
        questionId: withCard,
        stability: 2.0,
        difficulty: 6.0,
        reviewCount: 7,
        lastReviewAt: DateTime.now().subtract(const Duration(days: 2)),
        nextReviewAt: DateTime.now().add(const Duration(days: 3)),
      ));

      final cards = await appState.getErrorQuestionCards('all');
      final byTitle = {for (final c in cards) c.question.title: c};
      expect(byTitle['有卡']!.card!.reviewCount, 7);
      expect(byTitle['有卡']!.answered, 3);
      expect(byTitle['无卡']!.card, isNull, reason: 'FSRS 卡不能错配到另一题上');
      expect(byTitle['无卡']!.answered, 5);
      // 默认按错得最多排序：无卡（错 5 次）在前
      expect(cards.first.question.title, '无卡');
    });

    test('includeStats 时导出带 fsrs 块与 last_answered_at', () async {
      final appState = AppState();
      await appState.init();
      final qid = await seedErrorQuestion('带卡的题', wrong: 1, correct: 0, daysAgo: 2);
      await DatabaseService.instance.upsertFSRSCard(FSRSCardState(
        questionId: qid,
        stability: 1.5,
        difficulty: 4.0,
        reviewCount: 2,
        lastReviewAt: DateTime.now().subtract(const Duration(days: 1)),
        nextReviewAt: DateTime.now().add(const Duration(days: 1)),
      ));

      final (path, _) = await appState.exportErrorQuestionsJson('all',
          includeStats: true);
      final q = (jsonDecode(File(path!).readAsStringSync())['questions'] as List)
          .single as Map;
      expect((q['fsrs'] as Map)['review_count'], 2);
      expect((q['stats'] as Map)['last_answered_at'], isNotNull);
      // 已知键一个都不能少：导入侧靠这些键重建题目
      expect(q['title'], '带卡的题');
      expect(q['correct_answer'], 'A');
      expect(q['knowledge_point'], '测试知识点');
    });
  });
}
