import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/question.dart';
import '../models/question_bank.dart';
import '../models/quiz_session.dart';
import '../models/answer_record.dart';
import '../models/app_settings.dart';
import 'database_service.dart';
import 'doc_parser_service.dart';
import 'ai_service.dart';
import 'quiz_service.dart';
import 'stats_service.dart';
import 'fsrs_service.dart';

class AppState extends ChangeNotifier {
  final DatabaseService _db = DatabaseService.instance;
  final QuizService _quizService = QuizService();
  final StatsService _statsService = StatsService();
  AIService? _aiService;

  // 设置
  AppSettings _settings = AppSettings();
  AppSettings get settings => _settings;

  // 题库
  List<QuestionBank> _banks = [];
  List<QuestionBank> get banks => _banks;

  // 选中用于刷题的题库
  Set<int> _selectedBankIds = {};
  Set<int> get selectedBankIds => _selectedBankIds;

  // 刷题状态
  QuizSession? _currentSession;
  QuizSession? get currentSession => _currentSession;
  List<Question> _quizQuestions = [];
  List<Question> get quizQuestions => _quizQuestions;
  int _currentQuestionIndex = 0;
  int get currentQuestionIndex => _currentQuestionIndex;
  Question? get currentQuestion => _currentQuestionIndex < _quizQuestions.length
      ? _quizQuestions[_currentQuestionIndex]
      : null;
  bool get isLastQuestion =>
      _currentQuestionIndex >= _quizQuestions.length - 1;

  // 当前题目的AI解析
  String? _currentAnalysis;
  String? get currentAnalysis => _currentAnalysis;
  bool _analysisLoading = false;
  bool get analysisLoading => _analysisLoading;

  // 上次答题结果
  AnswerRecord? _lastAnswerRecord;
  AnswerRecord? get lastAnswerRecord => _lastAnswerRecord;

  // 答题历史（按题目索引存储，支持前后翻题）
  final List<AnswerRecord?> _answerHistory = [];
  bool _skipFSRS = false;
  void set skipFSRS(bool v) => _skipFSRS = v;
  bool _noShuffle = false;
  void set noShuffle(bool v) => _noShuffle = v;
  bool get hasPrevious => _currentQuestionIndex > 0;

  // 单题统计
  Map<String, int> _currentQuestionStats = {};
  Map<String, int> get currentQuestionStats => _currentQuestionStats;

  // 首页统计
  HomeStats? _homeStats;
  HomeStats? get homeStats => _homeStats;
  String? _weaknessAnalysis;
  String? get weaknessAnalysis => _weaknessAnalysis;

  // 导入进度
  double _importProgress = 0;
  double get importProgress => _importProgress;
  String _importStatus = '';
  String get importStatus => _importStatus;
  bool _useAiImport = false;
  bool get useAiImport => _useAiImport;

  void setUseAiImport(bool value) {
    _useAiImport = value;
    notifyListeners();
  }

  // 预览导入：解析后先预览再确认
  List<Question> _previewQuestions = [];
  List<Question> get previewQuestions => _previewQuestions;
  String _previewBankName = '';
  String get previewBankName => _previewBankName;

  /// 解析文件并在预览中展示（不保存到数据库）
  Future<void> parseForPreview(List<String> filePaths) async {
    _previewQuestions = [];
    _importProgress = 0;
    _importStatus = '正在解析...';
    notifyListeners();

    final files = filePaths
        .where((p) => p.toLowerCase().endsWith('.docx') || p.toLowerCase().endsWith('.doc'))
        .map((p) => File(p))
        .toList();

    if (files.isEmpty) {
      _importStatus = '未找到有效的 DOC/DOCX 文件';
      notifyListeners();
      return;
    }

    if (!_settings.isConfigured || _aiService == null) {
      _importStatus = '请先在设置中配置 API Key';
      notifyListeners();
      return;
    }

    final file = files.first;
    final fileName = file.path.split('/').last.split('\\').last;

    // 检测格式：不允许旧版二进制 .doc
    final format = DocParserService.detectFormat(file.path);
    if (format == 'doc') {
      _importStatus = '「$fileName」是旧版 .doc 格式，不兼容。\n请用 Word 打开 → 文件 → 另存为 → .docx';
      notifyListeners();
      return;
    }
    if (format != 'docx') {
      _importStatus = '「$fileName」不是有效的 DOCX 文件';
      notifyListeners();
      return;
    }

    _previewBankName = fileName.replaceAll(
        RegExp(r'\.(docx|doc)$', caseSensitive: false), '');

    if (_aiService != null) {
      _importStatus = 'AI 解析中...';
      notifyListeners();
      final rawText = await DocParserService.extractRawText(file.path);
      _previewQuestions = await _aiService!.parseQuestionsFromRawText(
          rawText, 0, (d, t) {
        _importStatus = 'AI 解析中 ($d/$t 块)';
        notifyListeners();
      });
    }

    _importStatus = '解析完成，共 ${_previewQuestions.length} 道题目，请预览确认';
    notifyListeners();
  }

  /// 确认导入：将预览题目保存到数据库
  Future<void> confirmImport() async {
    if (_previewQuestions.isEmpty) return;

    final now = DateTime.now().toIso8601String();
    final bankId = await _db.insertBank(QuestionBank(
      name: _previewBankName,
      createdAt: now,
    ));

    final questions = _previewQuestions.map((q) => Question(
          bankId: bankId,
          title: q.title,
          options: q.options,
          correctAnswer: q.correctAnswer,
          analysis: q.analysis,
          questionType: q.questionType,
          createdAt: now,
        )).toList();

    await _db.insertQuestions(questions);
    await _db.updateBankQuestionCount(bankId, questions.length);

    _importStatus = '导入完成！共 ${questions.length} 道题目';
    _previewQuestions = [];
    await _loadBanks();
    notifyListeners();
  }

  /// 从预览中删除单题
  void removePreviewQuestion(int index) {
    if (index >= 0 && index < _previewQuestions.length) {
      _previewQuestions.removeAt(index);
      notifyListeners();
    }
  }

  /// 编辑预览中的单题
  void updatePreviewQuestion(int index, Question updated) {
    if (index >= 0 && index < _previewQuestions.length) {
      _previewQuestions[index] = updated;
      notifyListeners();
    }
  }

  /// 清空预览
  void clearPreview() {
    _previewQuestions = [];
    _previewBankName = '';
    _importStatus = "";
    _importProgress = 0;
    notifyListeners();
  }

  // 刷题模式
  int _selectedQuestionCount = 50;
  int get selectedQuestionCount => _selectedQuestionCount;
  void setQuestionCount(int count) { _selectedQuestionCount = count; notifyListeners(); }

  // 初始化
  Future<void> init() async {
    await _loadSettings();
    await _loadBanks();
    await _loadHomeStats();
    _initAIService();
  }

  void _initAIService() {
    _aiService = AIService(_settings);
  }

  AIService? get aiService => _aiService;

  Future<double?> fetchAIBalance() async {
    return await _aiService?.fetchBalance();
  }

  int getEstimatedRemainingQuestions() {
    return _aiService?.getEstimatedRemainingQuestions() ?? -1;
  }

  // ======================== 设置 ========================

  Future<void> _loadSettings() async {
    final apiKey = await _db.getSetting('api_key') ?? '';
    final apiEndpoint =
        await _db.getSetting('api_endpoint') ?? AppSettings.defaultApiEndpoint;
    final model = await _db.getSetting('model') ?? AppSettings.defaultModel;
    _settings = AppSettings(
      apiKey: apiKey,
      apiEndpoint: apiEndpoint,
      model: model,
    );
    _initAIService();
    notifyListeners();
  }

  Future<void> updateSettings(AppSettings newSettings) async {
    _settings = newSettings;
    await _db.setSetting('api_key', newSettings.apiKey);
    await _db.setSetting('api_endpoint', newSettings.apiEndpoint);
    await _db.setSetting('model', newSettings.model);
    _initAIService();
    notifyListeners();
  }

  // ======================== 题库管理 ========================

  Future<void> _loadBanks() async {
    _banks = await _db.getAllBanks();
    notifyListeners();
  }

  Future<void> importFiles(List<String> filePaths) async {
    _importProgress = 0;
    _importStatus = _useAiImport ? 'AI 解析准备中...' : '准备导入...';
    notifyListeners();

    final files = filePaths
        .where((p) => p.toLowerCase().endsWith('.docx') || p.toLowerCase().endsWith('.doc'))
        .map((p) => File(p))
        .toList();

    if (files.isEmpty) {
      _importStatus = '未找到有效的DOC/DOCX文件';
      notifyListeners();
      return;
    }

    // 检查 AI 模式是否需要设置
    if (_useAiImport && !_settings.isConfigured) {
      _importStatus = '请先在设置中配置 API Key 再使用 AI 整理';
      notifyListeners();
      return;
    }

    int totalQuestions = 0;
    int processedFiles = 0;

    for (final file in files) {
      final fileName = file.path.split('/').last.split('\\').last;
      final bankName = fileName.replaceAll(
          RegExp(r'\.(docx|doc)$', caseSensitive: false), '');
      final now = DateTime.now().toIso8601String();
      final bankId = await _db.insertBank(QuestionBank(
        name: bankName,
        fileSource: file.path,
        createdAt: now,
      ));

      List<Question> questions;

      if (_useAiImport && _aiService != null) {
        // ===== AI 整理模式 =====
        _importStatus = '正在提取文本: $fileName';
        notifyListeners();

        final rawText = await DocParserService.extractRawText(file.path);
        if (rawText.isEmpty) {
          processedFiles++;
          continue;
        }

        _importStatus = 'AI 正在解析题目: $fileName';
        notifyListeners();

        questions = await _aiService!.parseQuestionsFromRawText(
          rawText,
          bankId,
          (done, total) {
            _importStatus = 'AI 解析中 ($done/$total 块): $fileName';
            notifyListeners();
          },
        );
      } else {
        // ===== 正则解析模式（原有逻辑）=====
        _importStatus = '正在解析: $fileName';
        notifyListeners();
        questions = await DocParserService.parseFileInIsolate(file.path, bankId);
      }

      if (questions.isNotEmpty) {
        await _db.insertQuestions(questions);
        totalQuestions += questions.length;
        await _db.updateBankQuestionCount(bankId, questions.length);
      }

      processedFiles++;
      _importProgress = processedFiles / files.length;
      notifyListeners();
    }

    final mode = _useAiImport ? '（AI 整理）' : '';
    _importStatus = '导入完成$mode！共 $totalQuestions 道题目，${files.length} 个题库';
    await _loadBanks();
    notifyListeners();
  }

  Future<void> deleteBank(int bankId) async {
    await _db.deleteBank(bankId);
    _selectedBankIds.remove(bankId);
    await _loadBanks();
  }

  void toggleBankSelection(int bankId) {
    if (_selectedBankIds.contains(bankId)) {
      _selectedBankIds.remove(bankId);
    } else {
      _selectedBankIds.add(bankId);
    }
    notifyListeners();
  }

  void setSelectedQuestionCount(int count) {
    _selectedQuestionCount = count;
    notifyListeners();
  }

  // ======================== 刷题逻辑 ========================

  Future<void> startQuiz() async {
    if (_selectedBankIds.isEmpty) return;

    await _quizService.startQuiz(
      bankIds: _selectedBankIds.toList(),
      mode: _selectedBankIds.length > 1 ? 'mixed' : 'single',
      questionCount: _selectedQuestionCount,
      noShuffle: _noShuffle,
    );

    _currentSession = _quizService.currentSession;
    _quizQuestions = _quizService.questions;
    _currentQuestionIndex = 0;
    _currentAnalysis = null;
    _lastAnswerRecord = null;
    _currentQuestionStats = {};
    _analysisLoading = false;
    _answerHistory.clear();
    _answerHistory.length = _quizQuestions.length;

    notifyListeners();
  }

  Future<void> submitAnswer(String userAnswer) async {
    if (_quizService.currentQuestion == null) return;

    _lastAnswerRecord = await _quizService.submitAnswer(userAnswer);
    _currentSession = _quizService.currentSession;

    // 存储答题历史
    if (_currentQuestionIndex < _answerHistory.length) {
      _answerHistory[_currentQuestionIndex] = _lastAnswerRecord;
    }

    // 加载单题统计
    final qId = _quizService.currentQuestion!.id!;
    _currentQuestionStats = await _quizService.getQuestionStats(qId);

    // 不再自动加载解析，由用户手动触发
    _currentAnalysis = null;
    _analysisLoading = false;

    // 更新 FSRS 状态（如果这道题已有 FSRS 卡，则更新；如果答错且没有卡，则创建）
    if (!_skipFSRS) _updateFSRSIfNeeded(qId);

    notifyListeners();
  }

  /// 更新 FSRS 间隔重复状态
  Future<void> _updateFSRSIfNeeded(int questionId) async {
    final record = _lastAnswerRecord;
    if (record == null) return;

    final reactionMs = _quizService.answerReactionMs;
    final rating = FSRSService.inferRating(record.isCorrect, reactionMs);

    final existingCard = await _db.getFSRSCard(questionId);
    final now = DateTime.now();

    if (existingCard != null) {
      // 已有卡：根据评分更新间隔
      final updated = FSRSService.schedule(existingCard, rating, now,
          reactionMs: reactionMs);
      await _db.upsertFSRSCard(updated);
    } else if (!record.isCorrect) {
      // 第一次答错：创建新卡
      final card = FSRSService.initCard(questionId, now);
      await _db.upsertFSRSCard(card);
    }
  }

  Future<void> _loadAnalysis() async {
    if (_aiService == null || currentQuestion == null) return;

    _analysisLoading = true;
    notifyListeners();

    _currentAnalysis = await _aiService!.getAnalysis(currentQuestion!);

    _analysisLoading = false;
    notifyListeners();
  }

  /// 手动查看解析
  Future<void> showAnalysis() async {
    await _loadAnalysis();
  }

  /// 重新生成解析（清除缓存）
  Future<void> regenerateAnalysis() async {
    if (_aiService == null || currentQuestion == null) return;
    // 清除缓存，强制 AI 重新生成
    if (currentQuestion!.id != null) {
      await _db.cacheAnalysis(currentQuestion!.id!, '');
    }
    _currentAnalysis = null;
    await _loadAnalysis();
  }

  /// 追问题目
  Future<String> askFollowUp(String question) async {
    if (_aiService == null || currentQuestion == null) return '';
    if (_currentAnalysis == null) return '';

    return await _aiService!.askFollowUp(
      currentQuestion!,
      _currentAnalysis!,
      question,
    );
  }

  void nextQuestion() {
    if (_quizService.hasNext) {
      _quizService.nextQuestion();
      _currentQuestionIndex = _quizService.currentIndex;
      _restoreAnswerState();
      notifyListeners();
    }
  }

  /// 返回上一题（只查看已答状态，不可修改答案）
  void previousQuestion() {
    if (_quizService.hasPrevious) {
      _quizService.previousQuestion();
      _currentQuestionIndex = _quizService.currentIndex;
      _restoreAnswerState();
      notifyListeners();
    }
  }

  void _restoreAnswerState() {
    _currentAnalysis = null;
    if (_currentQuestionIndex < _answerHistory.length) {
      _lastAnswerRecord = _answerHistory[_currentQuestionIndex];
    } else {
      _lastAnswerRecord = null;
    }
    _currentQuestionStats = {};
  }

  Future<void> updateCurrentQuestion(String title, String answer, String? type) async {
    final q = currentQuestion;
    if (q == null) return;
    await _db.updateQuestion(q.id!, title, answer, type ?? q.questionType);
    _quizQuestions[_currentQuestionIndex] = q.copyWith(
      title: title,
      correctAnswer: answer,
      questionType: type ?? q.questionType,
    );
    notifyListeners();
  }

  Future<QuizSession> endSession() async {
    _currentSession = await _quizService.endSession();
    _quizService.reset();
    await _loadHomeStats();
    notifyListeners();
    return _currentSession!;
  }

  // ======================== 错题本 ========================

  Future<void> toggleErrorBook(int questionId) async {
    final inBook = await _db.isInErrorBook(questionId);
    if (inBook) {
      await _db.removeFromErrorBook(questionId);
    } else {
      await _db.addToErrorBook(questionId);
    }
  }

  Future<bool> isInErrorBook(int questionId) async {
    return await _db.isInErrorBook(questionId);
  }

  /// 错题重刷模式（全题库 FSRS 到期题目 + 收藏）
  /// [bankIds] 为 null 或空时，从所有题库抽题；否则只从指定题库抽题
  Future<void> startErrorReview({Set<int>? bankIds}) async {
    // 使用 FSRS 到期题目，按题库分组获取
    final questionsByBank = await _db.getDueReviewQuestionsByBank();
    if (questionsByBank.isEmpty) return;

    // 按 bankIds 过滤（null/空 = 全题库）
    final allQuestions = <Question>[];
    for (final entry in questionsByBank.entries) {
      if (bankIds == null || bankIds.isEmpty || bankIds.contains(entry.key)) {
        allQuestions.addAll(entry.value);
      }
    }
    if (allQuestions.isEmpty) return;

    allQuestions.shuffle();
    final count = allQuestions.length > _selectedQuestionCount
        ? _selectedQuestionCount
        : allQuestions.length;

    final selectedQuestions = allQuestions.take(count).toList();

    final session = QuizSession(
      bankIds: bankIds?.join(',') ?? 'all',
      mode: 'error_review',
      totalQuestions: selectedQuestions.length,
      startTime: DateTime.now().toIso8601String(),
    );
    final sessionWithId = QuizSession(
      id: await _db.insertSession(session),
      bankIds: session.bankIds,
      mode: session.mode,
      totalQuestions: session.totalQuestions,
      startTime: session.startTime,
    );

    _quizService.loadQuiz(questions: selectedQuestions, session: sessionWithId);
    _quizQuestions = _quizService.questions;
    _currentSession = _quizService.currentSession;
    _currentQuestionIndex = 0;
    _currentAnalysis = null;
    _lastAnswerRecord = null;
    _currentQuestionStats = {};
    _answerHistory.clear();
    _answerHistory.length = _quizQuestions.length;

    notifyListeners();
  }

  /// 获取错题本统计（按题库分组）：到期题数 + 收藏题数
  Future<List<Map<String, dynamic>>> getErrorBookStats() async {
    return await _db.getErrorStatsByBank();
  }

  Future<int> getErrorBookCount() async {
    return await _db.getErrorBookCount();
  }

  // ======================== 统计 ========================

  Future<void> _loadHomeStats() async {
    _homeStats = await _statsService.getHomeStats();
    notifyListeners();
  }

  Future<void> refreshWeaknessAnalysis() async {
    if (_aiService == null) return;

    final bankAccuracies = await _statsService.getBankAccuracies();
    final overallAccuracy = await _db.getOverallAccuracy();

    if (bankAccuracies.isEmpty) {
      _weaknessAnalysis = '暂无刷题数据，开始你的第一次刷题吧！';
    } else {
      _weaknessAnalysis = await _aiService!.generateWeaknessAnalysis(
        bankAccuracies.map((b) => {
          'bank_name': b.bankName,
          'total': b.total,
          'correct': b.correct,
        }).toList(),
        overallAccuracy,
      );
    }
    notifyListeners();
  }

  /// 生成刷题小结
  Future<String> generateSessionSummary(QuizSession session) async {
    if (_aiService == null) return '';
    return await _aiService!.generateSessionSummary(
      session.totalQuestions,
      session.correctCount,
      session.wrongCount,
      session.durationSeconds,
    );
  }

  @override
  void dispose() {
    _aiService?.dispose();
    super.dispose();
  }
}
