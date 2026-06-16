import 'dart:math';
import '../models/question.dart';
import '../models/question_bank.dart';
import '../models/quiz_session.dart';
import '../models/answer_record.dart';
import 'database_service.dart';
import 'debug_log_service.dart';

class QuizService {
  final DatabaseService _db = DatabaseService.instance;

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
  Future<void> startQuiz({
    required List<int> bankIds,
    required String mode,
    required int questionCount,
    List<QuestionBank>? allBanks,
  }) async {
    // 从指定题库中随机抽取题目
    final allQuestions = await _db.getQuestionsByBanks(bankIds);

    if (allQuestions.isEmpty) {
      _questions = [];
    } else if (allQuestions.length <= questionCount) {
      _questions = allQuestions;
      _questions.shuffle();
    } else {
      _questions = allQuestions;
      _questions.shuffle(Random());
      _questions = _questions.take(questionCount).toList();
    }

    // 创建会话
    _currentSession = QuizSession(
      bankIds: bankIds.join(','),
      mode: mode,
      totalQuestions: _questions.length,
      startTime: DateTime.now().toIso8601String(),
    );

    _currentSession = QuizSession(
      id: await _db.insertSession(_currentSession!),
      bankIds: _currentSession!.bankIds,
      mode: _currentSession!.mode,
      totalQuestions: _currentSession!.totalQuestions,
      startTime: _currentSession!.startTime,
    );

    _currentIndex = 0;
    _answerStartTime = DateTime.now();
  }

  /// 提交答案
  Future<AnswerRecord> submitAnswer(String userAnswer) async {
    final question = currentQuestion;
    if (question == null || _currentSession == null) {
      throw StateError('没有活跃的刷题会话');
    }

    final correctAnswer = question.correctAnswer.trim();
    final normalizedUser = userAnswer.trim();
    final bool isCorrect;

    if (question.questionType == 'fill_blank') {
      // 填空：按分号拆分，逐空比对
      final correctParts = correctAnswer
          .split(RegExp(r'[；;]'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      final userParts = normalizedUser
          .split(RegExp(r'[；;]'))
          .map((s) => s.trim())
          .toList();
      isCorrect = correctParts.isNotEmpty &&
          correctParts.length == userParts.length &&
          List.generate(correctParts.length,
                  (i) => correctParts[i] == (i < userParts.length ? userParts[i] : ''))
              .every((v) => v);
    } else if (question.questionType == 'ming_jie' ||
        question.questionType == 'jian_da' ||
        question.questionType == 'jie_da') {
      // 名解/简答/问答：用户答案在参考答案中能找到关键匹配即可
      final userLower = normalizedUser.replaceAll(RegExp(r'\s+'), '');
      final correctLower = correctAnswer.replaceAll(RegExp(r'\s+'), '');
      isCorrect = userLower.length > 3 &&
          (correctLower.contains(userLower) || userLower.contains(correctLower));
    } else {
      isCorrect = normalizedUser.toUpperCase() == correctAnswer.toUpperCase();
    }

    DebugLogService.instance.logAnswerSubmit(
      userAnswer: userAnswer,
      correctAnswer: correctAnswer,
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

  /// 结束当前会话
  Future<QuizSession> endSession() async {
    if (_currentSession == null) {
      throw StateError('没有活跃的刷题会话');
    }

    final endTime = DateTime.now();
    final startTime = DateTime.parse(_currentSession!.startTime);
    final durationSeconds = endTime.difference(startTime).inSeconds;

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
    return _currentSession!;
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
    _currentIndex = 0;
    _answerStartTime = DateTime.now();
  }

  /// 重置会话
  void reset() {
    _currentSession = null;
    _questions = [];
    _currentIndex = 0;
  }
}
