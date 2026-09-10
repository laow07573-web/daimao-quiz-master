import '../models/question.dart';
import '../models/question_bank.dart';
import '../models/quiz_session.dart';
import '../models/answer_record.dart';
import 'database_service.dart';
import 'debug_log_service.dart';

class QuizService {
  final DatabaseService _db = DatabaseService.instance;

  /// v1.0.2 设计审查修复：会话计数夹取上限提为命名常量
  static const int maxSessionCount = 1 << 30;

  // 当前会话状态
  QuizSession? _currentSession;
  List<Question> _questions = [];
  int _currentIndex = 0;
  DateTime? _answerStartTime;  // 当前题目开始计时

  QuizSession? get currentSession => _currentSession;
  List<Question> get questions => _questions;
  int get currentIndex => _currentIndex;
  int get totalQuestions => _questions.length;
  Question? get currentQuestion =>
      _currentIndex < _questions.length && _currentIndex >= 0
          ? _questions[_currentIndex]
          : null;
  bool get isLastQuestion => _currentIndex >= _questions.length - 1;
  bool get hasNext => _currentIndex < _questions.length - 1;
  bool get hasPrevious => _currentIndex > 0;
  DateTime? get answerStartTime => _answerStartTime;
  int get answerReactionMs =>
      _answerStartTime != null
          ? DateTime.now().difference(_answerStartTime!).inMilliseconds
          : 0;
  void markAnswerStart() => _answerStartTime = DateTime.now();

  /// 开始新的刷题会话
  /// [persistSession] 为 false 时不落库（练习/背题模式不产生会话行，
  /// 避免「退出后本次练习记录将不保存」的幽灵会话）
  Future<void> startQuiz({
    required List<int> bankIds,
    required String mode,
    required int questionCount,
    List<QuestionBank>? allBanks,
    bool noShuffle = false,
    bool persistSession = true,
  }) async {
    // 从指定题库抽取题目（noShuffle 时保持题库原始顺序）。
    // v1.0.2 设计审查修复：LIMIT 下推数据库，不再全量加载后内存截断，
    // 也不再二次 shuffle（SQL RANDOM() 已随机）
    _questions = await _db.getQuestionsByBanks(bankIds,
        random: !noShuffle, limit: questionCount);

    // v1.0.2 设计审查修复：空题库不创建会话（避免 0 题幽灵会话
    // 污染最近会话/历史列表与统计）
    if (_questions.isEmpty) {
      _currentSession = null;
      _currentIndex = 0;
      _answerStartTime = DateTime.now();
      DebugLogService.instance.log('SESSION', '所选题库无题目，未创建会话');
      return;
    }

    // 创建会话
    _currentSession = QuizSession(
      bankIds: bankIds.join(','),
      mode: mode,
      totalQuestions: _questions.length,
      startTime: DateTime.now().toIso8601String(),
    );

    if (persistSession) {
      // 开始新会话前，清空上一次未完成会话的断档记录（会话行/题目顺序/题库关联）：
      // 用户已开始新一轮答题，旧的中断会话不再可续刷。
      // 空题库不建会话时不会走到这里，旧会话仍可续刷
      await _db.deleteUnfinishedSessions();
      _currentSession = QuizSession(
        id: await _db.insertSession(_currentSession!),
        bankIds: _currentSession!.bankIds,
        mode: _currentSession!.mode,
        totalQuestions: _currentSession!.totalQuestions,
        startTime: _currentSession!.startTime,
      );
      // v1.0.2 七项改进：会话题目顺序 + 题库关联（断点续刷/历史副标题用）
      await _db.insertSessionBanks(_currentSession!.id!, bankIds);
      await _db.insertSessionQuestions(_currentSession!.id!, _questions);
    }

    DebugLogService.instance.log('SESSION', '新会话 id=${_currentSession!.id} start=${_currentSession!.startTime} questions=${_currentSession!.totalQuestions}');
    _currentIndex = 0;
    _answerStartTime = DateTime.now();
  }

  /// 共享答案判定（刷题与练习共用）
  /// - 单选/判断：忽略大小写与首尾空白；判断题归一（√/×/T/F/正确/错误 → 对/错）
  /// - 多选：集合比较（忽略顺序与分隔符）
  /// - 填空：逐空去标点比对，空数不一致判错
  /// - 名解/简答/问答：去标点后包含匹配，答案过短判错
  /// - 空答案一律判错
  static bool judgeAnswer(Question question, String userAnswer) {
    final correctAnswer = question.correctAnswer.trim();
    final normalizedUser = userAnswer.trim();
    if (normalizedUser.isEmpty) return false;
    if (correctAnswer.isEmpty) return false;

    if (question.questionType == 'true_false') {
      // 判断题输入归一：对/√/正确/T/TRUE ↔ 错/×/错误/F/FALSE
      final u = _normalizeTrueFalse(normalizedUser);
      final c = _normalizeTrueFalse(correctAnswer);
      if (u == null || c == null) return false;
      return u == c;
    }

    if (question.questionType == 'multi_choice') {
      // 多选集合比较：忽略顺序与分隔符（A,C / C、A / c a）
      final correctSet = _parseChoiceSet(correctAnswer);
      final userSet = _parseChoiceSet(normalizedUser);
      if (correctSet.isEmpty || userSet.isEmpty) return false;
      return setEquals(correctSet, userSet);
    }

    if (question.questionType == 'fill_blank') {
      // 填空：按分号拆分，逐空比对（去除标点符号）
      final correctParts = correctAnswer
          .split(RegExp(r'[；;]'))
          .map((s) => stripPunct(s))
          .where((s) => s.isNotEmpty)
          .toList();
      final userParts = normalizedUser
          .split(RegExp(r'[；;]'))
          .map((s) => stripPunct(s))
          .where((s) => s.isNotEmpty)
          .toList();
      return correctParts.isNotEmpty &&
          correctParts.length == userParts.length &&
          List.generate(correctParts.length,
                  (i) => correctParts[i] == (i < userParts.length ? userParts[i] : ''))
              .every((v) => v);
    }

    if (question.questionType == 'ming_jie' ||
        question.questionType == 'jian_da' ||
        question.questionType == 'jie_da') {
      // 名解/简答/问答：去除标点后做包含匹配；
      // 恰好 3 字（如"细胞壁"）精确相等时豁免"过短判错"限制
      final userClean = stripPunct(normalizedUser);
      final correctClean = stripPunct(correctAnswer);
      if (userClean.isNotEmpty && userClean == correctClean) return true;
      return userClean.length > 3 &&
          (correctClean.contains(userClean) || userClean.contains(correctClean));
    }

    return normalizedUser.toUpperCase() == correctAnswer.toUpperCase();
  }

  /// 解析选择题答案字符串为字母集合（忽略顺序/分隔符/大小写）
  static Set<String> _parseChoiceSet(String s) {
    return s
        .split(RegExp(r'[,，、;；\s/]+'))
        .map((e) => e.trim().toUpperCase())
        .where((e) => e.isNotEmpty && RegExp(r'^[A-Z]$').hasMatch(e))
        .toSet();
  }

  /// 判断题输入归一：返回 '对'/'错'，无法识别返回 null
  static String? _normalizeTrueFalse(String s) {
    final t = s.trim().toUpperCase();
    // 否定类先行（"不正确"/"不对" 含 "正确"/"对" 子串）
    if (t == '不正确' || t == '不对' || t == '错误' || t == '错' ||
        t == '×' || t == 'X' || t == 'F' || t == 'FALSE') {
      return '错';
    }
    if (t == '正确' || t == '对' || t == '√' ||
        t == 'T' || t == 'TRUE') {
      return '对';
    }
    return null;
  }

  static bool setEquals(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }

  /// 提交答案
  Future<AnswerRecord> submitAnswer(String userAnswer) async {
    final question = currentQuestion;
    if (question == null || _currentSession == null) {
      throw StateError('没有活跃的刷题会话');
    }

    final isCorrect = judgeAnswer(question, userAnswer);

    DebugLogService.instance.logAnswerSubmit(
      userAnswer: userAnswer,
      correctAnswer: question.correctAnswer,
      isCorrect: isCorrect,
      questionType: question.questionType,
      questionTitle: question.title,
    );

    final record = AnswerRecord(
      questionId: question.id!,
      sessionId: _currentSession!.id,
      userAnswer: userAnswer,
      isCorrect: isCorrect,
      answeredAt: DateTime.now().toIso8601String(),
    );

    final recordId = await _db.insertAnswerRecord(record);

    // 更新会话统计
    if (isCorrect) {
      _currentSession = QuizSession(
        id: _currentSession!.id,
        bankIds: _currentSession!.bankIds,
        mode: _currentSession!.mode,
        totalQuestions: _currentSession!.totalQuestions,
        correctCount: _currentSession!.correctCount + 1,
        wrongCount: _currentSession!.wrongCount,
        startTime: _currentSession!.startTime,
        endTime: _currentSession!.endTime,
        durationSeconds: _currentSession!.durationSeconds,
      );
    } else {
      _currentSession = QuizSession(
        id: _currentSession!.id,
        bankIds: _currentSession!.bankIds,
        mode: _currentSession!.mode,
        totalQuestions: _currentSession!.totalQuestions,
        correctCount: _currentSession!.correctCount,
        wrongCount: _currentSession!.wrongCount + 1,
        startTime: _currentSession!.startTime,
        endTime: _currentSession!.endTime,
        durationSeconds: _currentSession!.durationSeconds,
      );
    }

    return AnswerRecord(
      id: recordId,
      questionId: record.questionId,
      sessionId: record.sessionId,
      userAnswer: record.userAnswer,
      isCorrect: record.isCorrect,
      aiAnalysis: record.aiAnalysis,
      answeredAt: record.answeredAt,
    );
  }

  /// 重新作答当前题（v1.0.2 完善：返回上一题后允许修改答案）。
  /// 已有记录则更新原记录（不新增，避免污染刷题量统计），
  /// 会话统计与 FSRS 由改判逻辑按新旧结果差量修正。
  Future<AnswerRecord> resubmitAnswer(String userAnswer) async {
    final question = currentQuestion;
    if (question == null || _currentSession == null) {
      throw StateError('没有活跃的刷题会话');
    }
    final isCorrect = judgeAnswer(question, userAnswer);

    // 首次作答走正常提交路径
    final existing = await _db.getAnswerRecordBySessionQuestion(
        _currentSession!.id!, question.id!);
    if (existing == null) {
      return await submitAnswer(userAnswer);
    }

    final now = DateTime.now();
    final oldCorrect = existing.isCorrect;

    // 先按新旧结果差量修正会话统计 + FSRS（rejudge 读取的是旧记录值；
    // 若先更新记录再修正，oldCorrect 会读到新值导致差量修正被跳过）
    if (oldCorrect != isCorrect) {
      await _db.rejudgeAnswerRecord(existing.id!, isCorrect);
    }
    // 再更新答案内容。v1.0.2 设计审查修复：同判定时保留原 answered_at，
    // 避免 23:59 作答、次日重答同一答案导致记录跨天漂移
    if (oldCorrect == isCorrect) {
      await _db.updateAnswerRecordAnswer(existing.id!, userAnswer, isCorrect,
          DateTime.tryParse(existing.answeredAt) ?? now);
    } else {
      await _db.updateAnswerRecordAnswer(
          existing.id!, userAnswer, isCorrect, now);
    }

    // 同步内存会话统计（按新旧结果差量调整）
    if (oldCorrect != isCorrect) {
      adjustSessionCounts(toCorrect: isCorrect);
    }

    return AnswerRecord(
      id: existing.id,
      questionId: question.id!,
      sessionId: _currentSession!.id,
      userAnswer: userAnswer,
      isCorrect: isCorrect,
      answeredAt: now.toIso8601String(),
    );
  }

  /// 移动到下一题
  bool nextQuestion() {
    if (hasNext) {
      _currentIndex++;
      _answerStartTime = DateTime.now();
      return true;
    }
    return false;
  }

  /// 返回上一题
  bool previousQuestion() {
    if (hasPrevious) {
      _currentIndex--;
      _answerStartTime = DateTime.now();
      return true;
    }
    return false;
  }

  /// 直接跳转到指定题号（答题卡/底部圆点跳题用）。
  /// v1.0.2 设计审查修复：单次变更替代 UI 层 while 逐题循环
  /// （O(n) 次 notify + O(n) 次单题统计查询）
  bool jumpToIndex(int index) {
    if (index < 0 || index >= _questions.length || index == _currentIndex) {
      return false;
    }
    _currentIndex = index;
    _answerStartTime = DateTime.now();
    return true;
  }

  /// 改判后同步内存会话计数（DB 已由 rejudgeAnswerRecord 差量修正；
  /// 内存会话需同步调整，否则 endSession 会用陈旧值覆盖 DB）
  void adjustSessionCounts({required bool toCorrect}) {
    final s = _currentSession;
    if (s == null) return;
    _currentSession = QuizSession(
      id: s.id,
      bankIds: s.bankIds,
      mode: s.mode,
      totalQuestions: s.totalQuestions,
      correctCount: (s.correctCount + (toCorrect ? 1 : -1)).clamp(0, maxSessionCount),
      wrongCount: (s.wrongCount + (toCorrect ? -1 : 1)).clamp(0, maxSessionCount),
      startTime: s.startTime,
      endTime: s.endTime,
      durationSeconds: s.durationSeconds,
    );
  }

  /// 当前会话是否已有作答记录（退出时用于区分"正常结束"与"放弃"）
  bool get hasAnyAnswers =>
      (_currentSession?.correctCount ?? 0) + (_currentSession?.wrongCount ?? 0) >
      0;

  /// 放弃当前会话：删除会话行与作答记录（练习模式退出/未作答退出），
  /// 兑现「退出后本次练习记录将不保存」的承诺，不产生 0 题幽灵会话
  Future<void> abortSession() async {
    final s = _currentSession;
    _questions = [];
    _currentSession = null;
    _currentIndex = 0;
    if (s?.id != null) {
      await _db.deleteSessionWithRecords(s!.id!);
    }
  }

  /// 暂停会话（v1.0.2 七项改进：断点续刷）。
  /// 不写 end_time、不重置 DB 行——作答记录已逐题落库，
  /// 下次通过 getLatestUnfinishedSession + session_questions 恢复继续
  void pauseSession() {
    DebugLogService.instance.log('SESSION',
        '暂停会话 id=${_currentSession?.id}（保留进度，可断点续刷）');
  }

  /// 结束当前会话
  Future<QuizSession> endSession() async {
    if (_currentSession == null) {
      throw StateError('没有活跃的刷题会话');
    }

    final endTime = DateTime.now();
    final startTime = DateTime.parse(_currentSession!.startTime);
    // 时钟回拨保护：时长不允许为负
    final durationSeconds =
        endTime.difference(startTime).inSeconds < 0 ? 0 : endTime.difference(startTime).inSeconds;

    DebugLogService.instance.log('SESSION',
        '结束会话 id=${_currentSession!.id} start=$startTime end=$endTime duration=${durationSeconds}s');

    _currentSession = QuizSession(
      id: _currentSession!.id,
      bankIds: _currentSession!.bankIds,
      mode: _currentSession!.mode,
      totalQuestions: _currentSession!.totalQuestions,
      correctCount: _currentSession!.correctCount,
      wrongCount: _currentSession!.wrongCount,
      startTime: _currentSession!.startTime,
      endTime: endTime.toIso8601String(),
      durationSeconds: durationSeconds,
    );

    await _db.updateSession(_currentSession!);
    DebugLogService.instance.log('SESSION',
        '已写入 DB: id=${_currentSession!.id} duration=${durationSeconds}s');
    return _currentSession!;
  }

  /// 去除标点、空白符号，统一为纯文本用于比对
  static String stripPunct(String s) {
    return s
        .replaceAll(RegExp(r'^[\s]*[（(]?\d+[)）.．、\s]*'), '')
        .replaceAll(RegExp(r'^[\s]*[①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱⑲⑳][、.\s]*'), '')
        .replaceAll(
            // 字符类分三段 raw 拼接（避免非 raw 字符串吞掉 \s）
            RegExp(r'[，。！？；：、""' +
                r"「」『』【】《》（）·…—\s,.!?;:'" +
                r'\(\)\[\]\\/\-_=+*&^%$#@~`|{}<>]'),
            '')
        .trim()
        .toUpperCase();
  }

  /// 获取单题统计
  Future<Map<String, int>> getQuestionStats(int questionId) async {
    return await _db.getQuestionStats(questionId);
  }

  /// 从外部加载题目和会话（用于错题重刷等不通过 startQuiz 的场景）
  void loadQuiz({
    required List<Question> questions,
    required QuizSession session,
  }) {
    _questions = questions;
    _currentSession = session;
    DebugLogService.instance.log('SESSION', '新会话 id=${_currentSession!.id} start=${_currentSession!.startTime} questions=${_currentSession!.totalQuestions}');
    _currentIndex = 0;
    _answerStartTime = DateTime.now();
  }

  /// 重置会话
  void reset() {
    _currentSession = null;
    _questions = [];
    DebugLogService.instance.log('SESSION', '会话已重置');
    _currentIndex = 0;
  }
}
