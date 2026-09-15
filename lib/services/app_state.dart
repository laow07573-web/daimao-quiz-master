import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/question.dart';
import '../models/question_bank.dart';
import '../models/quiz_session.dart';
import '../models/answer_record.dart';
import '../models/follow_up_message.dart';
import '../models/app_settings.dart';
import 'database_service.dart';
import 'device_service.dart';
import 'doc_parser_service.dart';
import 'bank_file_service.dart';
import 'reminder_service.dart';
import 'ai_service.dart';
import 'quiz_service.dart';
import 'sample_bank.dart';
import 'stats_service.dart';
import 'debug_log_service.dart';
import 'docx_export_service.dart';
import 'fsrs_service.dart';
import 'key_crypto.dart';
import 'secure_key_storage.dart';

class AppState extends ChangeNotifier {
  /// 测试注入：给定则用它构造 [AIService]（配合 MockClient 覆盖流式竞态等
  /// 只能在 AppState 层验证的行为）。生产代码不传，行为不变。
  AppState({http.Client? aiClient}) : _aiClientOverride = aiClient;

  final http.Client? _aiClientOverride;

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

  /// 进行中的讲解流（切题 / 重建 AI 服务 / 退出时要取消）
  StreamSubscription<String>? _analysisSub;

  /// 解析流的通知节流时间戳（见 _notifyAnalysisThrottled）
  DateTime _lastAnalysisNotify = DateTime.fromMillisecondsSinceEpoch(0);

  /// 解析代次：每发起一次生成就自增。**同一题可能有多条流**（点重新生成、
  /// 切走再切回），所以守卫要用代次而不是题号——否则旧流的 chunk 会被当成新结果。
  int _analysisGen = 0;

  /// 正在流式生成的追问回复（App 内对话页据此渲染「边生成边显示」的气泡）；
  /// 生成完成后并入 followUpHistory，这里清空。
  String _streamingReply = '';
  String get streamingReply => _streamingReply;

  // 上次答题结果
  AnswerRecord? _lastAnswerRecord;
  AnswerRecord? get lastAnswerRecord => _lastAnswerRecord;

  // 答题历史（按题目索引存储，支持前后翻题）
  final List<AnswerRecord?> _answerHistory = [];
bool _skipFSRS = false;
bool get skipFSRS => _skipFSRS;
void set skipFSRS(bool v) => _skipFSRS = v;
  bool _noShuffle = false;
  void set noShuffle(bool v) => _noShuffle = v;
  bool get hasPrevious => _currentQuestionIndex > 0;

  // 单题统计
  Map<String, int> _currentQuestionStats = {};
  Map<String, int> get currentQuestionStats => _currentQuestionStats;

  // v1.0.2 FSRS 可见化：当前题的复习卡（下次复习时间展示）
  FSRSCardState? _currentFsrsCard;
  FSRSCardState? get currentFsrsCard => _currentFsrsCard;

  // v1.0.2 聊天气泡式追问：当前题追问历史（用户/AI 消息）
  List<FollowUpMessage> _followUpHistory = [];
  List<FollowUpMessage> get followUpHistory => _followUpHistory;
  bool _followUpLoading = false;
  bool get followUpLoading => _followUpLoading;

  /// 清空当前题上下文（单题统计 + 复习卡 + 追问历史）
  void _clearQuestionContext() {
    _currentQuestionStats = {};
    _currentFsrsCard = null;
    _followUpHistory = [];
    // 流式输出改造：切题时必须掐断进行中的流，否则旧题的 chunk 会写进新题
    _cancelAnalysisStream();
    _streamingReply = '';
  }

  // 首页统计
  HomeStats? _homeStats;
  HomeStats? get homeStats => _homeStats;

  /// 统计数据版本号。
  ///
  /// 任何会改变「统计口径」的写入都应调用 [bumpStatsRevision]：
  /// 答题结束、导入/删除题库、改判、打标签、生成/清除模拟数据……
  /// 首页（本周战绩卡是页面私有 state）与统计页据此自动重载本地统计，
  /// 免得每个调用点都要记得手动刷新、漏一处就出现「数据不更新」。
  int _statsRevision = 0;
  int get statsRevision => _statsRevision;

  /// 统计是否包含模拟数据（开发者选项）。默认 false：只统计真实作答。
  bool get includeSimulatedStats => DatabaseService.includeSimulatedData;

  /// 切换「统计包含模拟数据」。持久化，并立即刷新统计口径。
  Future<void> setIncludeSimulatedStats(bool v) async {
    DatabaseService.includeSimulatedData = v;
    await _db.setSetting('stats_include_simulated', v ? '1' : '0');
    await bumpStatsRevision();
  }

  /// 标记统计数据已变化：重算累计统计 + 通知所有监听者。
  Future<void> bumpStatsRevision() async {
    await _loadHomeStats();
    _statsRevision++;
    notifyListeners();
  }
  String? _weaknessAnalysis;
  String? get weaknessAnalysis => _weaknessAnalysis;

  // 导入进度
  double _importProgress = 0;
  double get importProgress => _importProgress;
  String _importStatus = '';
  String get importStatus => _importStatus;
  bool _useAiImport = false;
  bool get useAiImport => _useAiImport;

  // v1.27 后台导入：任务在应用层运行，离开导入页不中断；
  // 首页展示进度卡，完成后经 [pendingImportResult] 弹完成提示。
  bool _importTaskActive = false;
  bool get importTaskActive => _importTaskActive;
  ImportTaskResult? _pendingImportResult;
  ImportTaskResult? get pendingImportResult => _pendingImportResult;
  // 当前解析阶段在总进度中的起点/跨度（JSON 与 AI 解析两阶段共存时拼接）
  double _bgProgressBase = 0;
  double _bgProgressSpan = 1;

  /// 消费完成提示（主壳弹窗后调用，防重复弹）
  ImportTaskResult? consumeImportResult() {
    final r = _pendingImportResult;
    _pendingImportResult = null;
    return r;
  }

  void setUseAiImport(bool value) {
    _useAiImport = value;
    notifyListeners();
  }

  // 预览导入：解析后先预览再确认
  List<Question> _previewQuestions = [];
  List<Question> get previewQuestions => _previewQuestions;
  String _previewBankName = '';
  String get previewBankName => _previewBankName;
  // v1.0.2 设计审查修复：分块解析失败原因（预览页显性提示，不再伪装 0 题成功）
  List<String> _previewParseErrors = [];
  List<String> get previewParseErrors => _previewParseErrors;

  /// 解析文件并在预览中展示（不保存到数据库）
  Future<void> parseForPreview(List<String> filePaths) async {
    _previewQuestions = [];
    _previewParseErrors = [];
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
      final result = await _aiService!.parseQuestionsFromRawText(
          rawText, 0, (d, t) {
        _importStatus = 'AI 解析中 ($d/$t 块)';
        // v1.27 进度精确化：按分块推进进度条（映射到当前阶段跨度内）
        _importProgress = (_bgProgressBase +
                _bgProgressSpan * (t > 0 ? d / t : 0))
            .clamp(0.0, 1.0);
        notifyListeners();
      });
      _previewQuestions = result.questions;
      _previewParseErrors = result.errors;
    }

    // v1.0.2 设计审查修复：失败块显性提示，不再「解析完成，共 0 道题目」假成功
    if (_previewQuestions.isEmpty && _previewParseErrors.isNotEmpty) {
      _importStatus = '解析失败：${_previewParseErrors.first}';
      notifyListeners();
      return;
    }
    _importStatus = '解析完成，共 ${_previewQuestions.length} 道题目，请预览确认'
        '${_previewParseErrors.isNotEmpty ? '（${_previewParseErrors.length} 个分块失败，已跳过）' : ''}';
    notifyListeners();
  }

  /// v1.0.2 七项改进：同名题库自动改名（导入防重复）。
  /// 返回 (最终名字, 是否改名)
  Future<(String, bool)> ensureUniqueBankName(String base) async {
    final names = (await _db.getAllBanks()).map((b) => b.name).toSet();
    if (!names.contains(base)) return (base, false);
    var i = 2;
    while (names.contains('$base($i)')) {
      i++;
    }
    return ('$base($i)', true);
  }

  /// 确认导入：将预览题目保存到数据库
  Future<void> confirmImport() async {
    if (_previewQuestions.isEmpty) return;

    final now = DateTime.now().toIso8601String();
    // v1.0.2 七项改进：重名自动加后缀，杜绝同一文档重复导入产生重复题库
    final (uniqueName, renamed) = await ensureUniqueBankName(_previewBankName);
    final bankId = await _db.insertBank(QuestionBank(
      name: uniqueName,
      createdAt: now,
    ));

    final questions = _previewQuestions.map((q) => Question(
          bankId: bankId,
          title: q.title,
          options: q.options,
          correctAnswer: q.correctAnswer,
          analysis: q.analysis,
          questionType: q.questionType,
          // v1.0.2 修复：预览阶段 AI 整理出的知识点不丢失
          knowledgePoint: q.knowledgePoint,
          createdAt: now,
        )).toList();

    await _db.insertQuestions(questions);
    await _db.updateBankQuestionCount(bankId, questions.length);

    _importStatus = '导入完成！共 ${questions.length} 道题目'
        '${renamed ? '（检测到同名题库，已自动命名为「$uniqueName」）' : ''}';
    _previewQuestions = [];
    await _loadBanks();
    notifyListeners();
  }

  /// 一键导入内置示例题库（无需文件、无需 AI 解析）：
  /// 新用户/演示场景快速体验刷题。重名自动加后缀，返回导入题数。
  Future<int> importSampleBank() async {
    final now = DateTime.now().toIso8601String();
    final (uniqueName, _) = await ensureUniqueBankName(sampleBankName);
    final bankId = await _db.insertBank(QuestionBank(
      name: uniqueName,
      createdAt: now,
    ));
    final questions = sampleQuestions(bankId: bankId, createdAt: now);
    await _db.insertQuestions(questions);
    await _db.updateBankQuestionCount(bankId, questions.length);
    await _loadBanks();
    // v1.28.1 新生引导：尚无勾选题库时自动勾上刚导入的示例题库，
    // 导入完成即可直接从「定向爆破」开刷，不用再去题库管理页勾选。
    if (_selectedBankIds.isEmpty) _selectedBankIds.add(bankId);
    notifyListeners();
    await bumpStatsRevision();
    return questions.length;
  }

  /// 从预览中删除单题。v1.27：筛选态下按原始序号删除不错位。
  void removePreviewQuestion(int index) {
    if (index >= 0 && index < _previewQuestions.length) {
      _previewQuestions.removeAt(index);
      notifyListeners();
    }
  }
  
  /// 测试注入：直接填充预览题目（预览页交互测试用，跳过 AI 解析）。
  @visibleForTesting
  void setPreviewQuestionsForTest(List<Question> qs, {String bankName = '测试题库'}) {
    _previewQuestions = List.of(qs);
    _previewBankName = bankName;
    notifyListeners();
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

    // 恢复「统计包含模拟数据」开关（开发者选项；默认关闭）
    try {
      final v = await _db.getSetting('stats_include_simulated');
      DatabaseService.includeSimulatedData = v == '1';
    } catch (_) {
      DatabaseService.includeSimulatedData = false;
    }

  }

  void _initAIService() {
    // v1.0.2 设计审查修复：重建前关闭旧实例的 http.Client，
    // 避免每次保存设置/启动都泄漏一个 socket 连接。
    // 流式改造补充：先取消在途的流——旧 client 被 close 时进行中的流会抛异常，
    // 不取消的话「保存设置」会把正在显示的解析打崩。
    _cancelAnalysisStream();
    _aiService?.dispose();
    _aiService = AIService(_settings, client: _aiClientOverride);
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
    // v1.0.2 七项改进：API Key 优先读 Android 安全存储（Keystore 加密），
    // 读不到时从 DB 旧密文迁移（一次性）
    var apiKey = await SecureKeyStorage.readApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      final storedKey = await _db.getSetting('api_key') ?? '';
      apiKey = KeyCrypto.decrypt(storedKey);
      if (apiKey.isNotEmpty) {
        await SecureKeyStorage.writeApiKey(apiKey);
      }
    }
    final apiEndpoint =
        await _db.getSetting('api_endpoint') ?? AppSettings.defaultApiEndpoint;
    final model = await _db.getSetting('model') ?? AppSettings.defaultModel;
    final soundEnabled = (await _db.getSetting('sound_enabled') ?? '1') == '1';
    final nickname = await _db.getSetting('nickname') ?? '';
    // 局域网同步设置（v11）
    final autoSync = (await _db.getSetting('auto_sync') ?? '0') == '1';
    final deviceName = await _db.getSetting('device_name') ?? '';
    _settings = AppSettings(
      apiKey: apiKey,
      apiEndpoint: apiEndpoint,
      model: model,
      soundEnabled: soundEnabled,
      nickname: nickname,
      autoSync: autoSync,
      deviceName: deviceName,
    );
    // v1.0.2 新增设置
    _vacationModeEnabled = (await _db.getSetting('vacation_mode_enabled') ?? '0') == '1';
    final vStart = await _db.getSetting('vacation_start_date');
    final vEnd = await _db.getSetting('vacation_end_date');
    _vacationStartDate = vStart != null ? DateTime.tryParse(vStart) : null;
    _vacationEndDate = vEnd != null ? DateTime.tryParse(vEnd) : null;
    _reminderEnabled = (await _db.getSetting('reminder_enabled') ?? '0') == '1';
    final rTime = await _db.getSetting('reminder_time');
    _reminderTime = rTime != null ? DateTime.tryParse(rTime) : null;
    _initAIService();
    notifyListeners();
  }

  Future<void> updateSettings(AppSettings newSettings) async {
    _settings = newSettings;
    // v1.0.2 七项改进：双写——DB 加密副本（备份可移植）+ Android 安全存储
    await _db.setSetting('api_key', KeyCrypto.encrypt(newSettings.apiKey));
    await SecureKeyStorage.writeApiKey(newSettings.apiKey);
    await _db.setSetting('api_endpoint', newSettings.apiEndpoint);
    await _db.setSetting('model', newSettings.model);
    await _db.setSetting('sound_enabled', newSettings.soundEnabled ? '1' : '0');
    await _db.setSetting('nickname', newSettings.nickname);
    // 局域网同步设置（v11）；设备名同步给 DeviceService（信标广播用）
    await _db.setSetting('auto_sync', newSettings.autoSync ? '1' : '0');
    await _db.setSetting('device_name', newSettings.deviceName);
    if (newSettings.deviceName.isNotEmpty) {
      await DeviceService.instance.setDeviceName(newSettings.deviceName);
    }
    _initAIService();
    notifyListeners();
  }

  /// 局域网同步落库后刷新（题库列表 + 首页统计；同步引擎回调接入）
  Future<void> refreshAfterSync() async {
    await _loadBanks();
    await _loadHomeStats();
    notifyListeners();
  }

  // ======================== v1.0.2: 假期模式 / 每日提醒设置 ========================

  bool _vacationModeEnabled = false;
  DateTime? _vacationStartDate;
  DateTime? _vacationEndDate;
  bool _reminderEnabled = false;
  DateTime? _reminderTime;

  bool get vacationModeEnabled => _vacationModeEnabled;
  DateTime? get vacationStartDate => _vacationStartDate;
  DateTime? get vacationEndDate => _vacationEndDate;
  bool get reminderEnabled => _reminderEnabled;
  DateTime? get reminderTime => _reminderTime;

  /// 假期日期范围（用于连击冻结与日历标注）
  List<DateTime> get vacationDateRange {
    final start = _vacationStartDate;
    final end = _vacationEndDate;
    if (!_vacationModeEnabled || start == null || end == null) return const [];
    final result = <DateTime>[];
    var cursor = DateTime(start.year, start.month, start.day);
    final last = DateTime(end.year, end.month, end.day);
    while (!cursor.isAfter(last)) {
      result.add(cursor);
      cursor = cursor.add(const Duration(days: 1));
    }
    return result;
  }

  /// 保存假期模式（开关 + 起止日期）
  Future<void> setVacationMode({
    required bool enabled,
    DateTime? start,
    DateTime? end,
  }) async {
    _vacationModeEnabled = enabled;
    if (start != null) _vacationStartDate = start;
    if (end != null) _vacationEndDate = end;
    await _db.setSetting('vacation_mode_enabled', enabled ? '1' : '0');
    if (_vacationStartDate != null) {
      await _db.setSetting('vacation_start_date', _vacationStartDate!.toIso8601String());
    }
    if (_vacationEndDate != null) {
      await _db.setSetting('vacation_end_date', _vacationEndDate!.toIso8601String());
    }
    notifyListeners();
  }

  /// 保存每日提醒设置
  Future<void> setReminderSettings({
    required bool enabled,
    DateTime? time,
  }) async {
    _reminderEnabled = enabled;
    if (time != null) _reminderTime = time;
    await _db.setSetting('reminder_enabled', enabled ? '1' : '0');
    if (_reminderTime != null) {
      await _db.setSetting('reminder_time', _reminderTime!.toIso8601String());
    }
    notifyListeners();
  }

  // ======================== v1.0.2: 统计页数据 ========================

  /// 首页/统计页切换时刷新战绩数据。
  ///
  /// 走 bumpStatsRevision 而非「_loadHomeStats + notify」：首页的续刷卡片与
  /// 本周战绩是页面私有 state，只有版本号变了才会重载。切回首页时必须让它们
  /// 重新取数（不然在别的 Tab 里产生的变化切回来还是旧值）。
  Future<void> refreshWeeklyStats() async {
    await bumpStatsRevision();
  }

  /// 最近 N 天每日刷题量（date: DateTime, total: int）
  Future<List<Map<String, dynamic>>> getDailyStats(int days) =>
      _db.getDailyStats(days);

  /// 最近 N 天每日正确率（total/correct，与 getDailyStats 同日口径）
  Future<List<Map<String, dynamic>>> getDailyAccuracy(int days) =>
      _db.getDailyAccuracy(days);

  /// 年度每日刷题量映射（key: 'YYYY-MM-DD'）
  Future<Map<String, int>> getYearlyTotals() async {
    final list = await _db.getDailyStats(365);
    return {
      for (final d in list)
        '${(d['date'] as DateTime).year}-'
            '${(d['date'] as DateTime).month.toString().padLeft(2, '0')}-'
            '${(d['date'] as DateTime).day.toString().padLeft(2, '0')}':
            d['total'] as int,
    };
  }

  /// 趋势数据（含正确率，无记录天占位）。
  /// v1.0.3 历史数据可查：窗口参数化，统计页传 365 覆盖一年历史。
  Future<List<Map<String, dynamic>>> getTrendData({int days = 30}) async {
    final totals = await _db.getDailyStats(days);
    final accuracy = await _db.getDailyAccuracy(days);
    final accByDay = <String, Map<String, dynamic>>{
      for (final a in accuracy) a['day'] as String: a,
    };
    return totals.map((d) {
      final date = d['date'] as DateTime;
      final key = '${date.year}-${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}';
      final total = d['total'] as int;
      final acc = accByDay[key];
      final correct = acc != null ? (acc['correct'] as int?) ?? 0 : 0;
      return {
        'date': date,
        'total': total,
        'accuracy': total > 0 ? (correct / total) * 100 : 0.0,
      };
    }).toList();
  }

  /// 连续打卡天数（含今天，>=50 题/天，假期冻结）。
  /// 今天未刷时与截止昨天结果一致；今天已刷则计入当天，首页/统计页口径统一
  Future<int> getStreakDays() async {
    final totals = await getYearlyTotals();
    return DatabaseService.countConsecutiveDays(
      totals,
      now: DateTime.now(),
      vacationStart: _vacationModeEnabled ? _vacationStartDate : null,
      vacationEnd: _vacationModeEnabled ? _vacationEndDate : null,
      upTo: DateTime.now(),
    );
  }

  /// 周期统计（week/month/all）
  Future<PeriodStats> getPeriodStats(String period) =>
      _statsService.getPeriodStats(period);

  /// 周期内最长连击
  Future<int> getPeriodLongestStreak(String period) =>
      _statsService.getPeriodLongestStreak(period);

  /// 最近会话记录（LIMIT 下推数据库，不再全量加载后内存截断）
  Future<List<QuizSession>> getRecentSessions(int limit) async {
    return await _db.getAllSessions(limit: limit);
  }

  /// 按 id 查单个会话（改判后局部刷新用）
  Future<QuizSession?> getSessionById(int id) => _db.getSessionById(id);

  /// 会话详情（answer_records JOIN questions）
  Future<List<Map<String, dynamic>>> getSessionDetail(int sessionId) =>
      _db.getSessionDetail(sessionId);

  /// 按知识点正确率排行
  Future<List<Map<String, dynamic>>> getAccuracyByKnowledgePoint(
          {Set<int>? bankIds}) =>
      _db.getAccuracyByKnowledgePoint(bankIds: bankIds);

  /// 各题库正确率（薄弱点分析/统计页排行）
  Future<List<BankAccuracy>> getBankAccuracies() =>
      _statsService.getBankAccuracies();

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
    int failedChunksTotal = 0;

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
          // 空文本：清理刚建的空题库，避免残留 0 题题库
          await _db.deleteBank(bankId);
          processedFiles++;
          continue;
        }

        _importStatus = 'AI 正在解析题目: $fileName';
        notifyListeners();

        final result = await _aiService!.parseQuestionsFromRawText(
          rawText,
          bankId,
          (done, total) {
            _importStatus = 'AI 解析中 ($done/$total 块): $fileName';
            notifyListeners();
          },
        );
        questions = result.questions;
        failedChunksTotal += result.failedChunks;
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
      } else {
        // AI 解析失败/无可解析题目：清理空题库
        await _db.deleteBank(bankId);
      }

      processedFiles++;
      _importProgress = processedFiles / files.length;
      notifyListeners();
    }

    final mode = _useAiImport ? '（AI 整理）' : '';
    _importStatus = '导入完成$mode！共 $totalQuestions 道题目，${files.length} 个题库'
        '${failedChunksTotal > 0 ? '；其中 $failedChunksTotal 个分块解析失败（已跳过）' : ''}';
    await _loadBanks();
    notifyListeners();
  }

  /// JSON 题库导入（v1.0.2：分组建库，无需预览）
  /// 返回 (题库数, 题目数, 错误信息, 改名组数)——错误随返回值传递；
  /// v1.0.2 七项改进：同名题库自动加后缀，杜绝重复题库
  Future<(int, int, String?, int)> importJsonFiles(List<String> filePaths) async {
    var banks = 0;
    var questions = 0;
    var renamed = 0;
    String? firstError;
    final existingNames =
        (await _db.getAllBanks()).map((b) => b.name).toSet();
    for (final p in filePaths) {
      final (b, q, err, r) =
          await BankFileService.importJsonFile(p, existingNames: existingNames);
      banks += b;
      questions += q;
      renamed += r;
      firstError ??= err;
    }
    await _loadBanks();
    notifyListeners();
    return (banks, questions, firstError, renamed);
  }

  // ======================== v1.27 后台导入（离开导入页不中断） ========================

  static String _fileName(String path) => path.split('/').last.split('\\').last;

  /// 后台导入：立即返回，任务在应用层继续运行（可离开导入页）。
  /// [jsonFiles] JSON 题库直接入库（按文件推进进度）；
  /// [docxFiles] 走 AI 解析（按分块推进进度），解析完成后待预览确认。
  /// 两者混选时先 JSON 后 AI，总进度按阶段拼接。
  Future<void> startBackgroundImport({
    List<String> jsonFiles = const [],
    List<String> docxFiles = const [],
  }) async {
    if (_importTaskActive) return;
    if (jsonFiles.isEmpty && docxFiles.isEmpty) return;
    _importTaskActive = true;
    _importProgress = 0;
    _importStatus = '准备导入...';
    _bgProgressBase = 0;
    _bgProgressSpan = 1;
    notifyListeners();

    final hasDocx = docxFiles.isNotEmpty;
    final jsonSpan = hasDocx ? 0.3 : 1.0; // 混选时 JSON 占 0~0.3，AI 解析占 0.3~1
    var jsonBanks = 0;
    var jsonQuestions = 0;
    var jsonRenamed = 0;
    String? jsonError;

    try {
      // 阶段一：JSON 题库（按文件数推进，精确）
      if (jsonFiles.isNotEmpty) {
        final existingNames =
            (await _db.getAllBanks()).map((b) => b.name).toSet();
        for (var i = 0; i < jsonFiles.length; i++) {
          _importStatus =
              '正在导入题库 (${i + 1}/${jsonFiles.length})：${_fileName(jsonFiles[i])}';
          notifyListeners();
          final (b, q, err, r) = await BankFileService.importJsonFile(
              jsonFiles[i],
              existingNames: existingNames);
          jsonBanks += b;
          jsonQuestions += q;
          jsonRenamed += r;
          jsonError ??= err;
          _importProgress = jsonSpan * (i + 1) / jsonFiles.length;
          notifyListeners();
        }
        await _loadBanks();
      }

      // 阶段二：DOCX AI 解析（按分块推进；解析完待预览确认）
      if (hasDocx) {
        _bgProgressBase = jsonSpan;
        _bgProgressSpan = 1 - jsonSpan;
        if (docxFiles.length > 1) {
          _importStatus =
              '已选 ${docxFiles.length} 个文档，本次仅解析第一个：${_fileName(docxFiles.first)}';
          notifyListeners();
        }
        await parseForPreview(docxFiles);
      }
    } catch (e) {
      _importStatus = '导入异常：$e';
    }

    // 汇总结果（完成提示由主壳在主页弹出）
    final ImportTaskResult result;
    if (hasDocx) {
      if (_previewQuestions.isNotEmpty) {
        result = ImportTaskResult(
          kind: ImportTaskKind.docxParse,
          success: true,
          message: 'AI 解析完成，共 ${_previewQuestions.length} 道题目，'
              '请预览确认后入库'
              '${jsonBanks > 0 ? '\n（JSON 题库已入库：$jsonBanks 个 / $jsonQuestions 道）' : ''}',
          questionCount: _previewQuestions.length,
        );
      } else {
        result = ImportTaskResult(
          kind: ImportTaskKind.docxParse,
          success: false,
          message: (jsonBanks > 0
                  ? 'JSON 题库已入库（$jsonBanks 个 / $jsonQuestions 道），'
                      '但文档解析失败：'
                  : '解析失败：') +
              _importStatus,
          questionCount: 0,
        );
      }
    } else if (jsonBanks > 0 || jsonQuestions > 0) {
      result = ImportTaskResult(
        kind: ImportTaskKind.json,
        success: true,
        message: 'JSON 导入完成：$jsonBanks 个题库，$jsonQuestions 道题'
            '${jsonRenamed > 0 ? '（$jsonRenamed 个同名题库已自动改名）' : ''}'
            '${jsonError != null ? '\n部分文件：$jsonError' : ''}',
        questionCount: jsonQuestions,
      );
    } else {
      result = ImportTaskResult(
        kind: ImportTaskKind.json,
        success: false,
        message: jsonError ?? _importStatus,
        questionCount: 0,
      );
    }

    _importTaskActive = false;
    _importProgress = 1;
    _pendingImportResult = result;
    _bgProgressBase = 0;
    _bgProgressSpan = 1;
    if (jsonFiles.isNotEmpty) {
      await _loadHomeStats(); // JSON 已入库，首页统计同步刷新。
    }
    notifyListeners();
  }

  /// 后台导入示例题库（一键入口，完成后弹提示引导刷题）
  Future<void> startBackgroundSampleImport() async {
    if (_importTaskActive) return;
    _importTaskActive = true;
    _importProgress = 0.2;
    _importStatus = '正在导入示例题库...';
    notifyListeners();
    try {
      final count = await importSampleBank();
      _importProgress = 1;
      _pendingImportResult = ImportTaskResult(
        kind: ImportTaskKind.sample,
        success: true,
        message: '示例题库导入完成，共 $count 道题，快去刷题体验吧',
        questionCount: count,
      );
    } catch (e) {
      _pendingImportResult = ImportTaskResult(
        kind: ImportTaskKind.sample,
        success: false,
        message: '示例题库导入失败：$e',
        questionCount: 0,
      );
    }
    _importTaskActive = false;
    await _loadHomeStats();
    notifyListeners();
  }

  /// 模拟长期使用（开发者选项，幂等）
  Future<({String? error, int records, int cards})> simulateLongTermUse({
    int days = 90,
    bool randomWeakKp = false,
    bool dueToday = false,
  }) async {
    final r = await _db.simulateLongTermUse(
        days: days, randomWeakKp: randomWeakKp, dueToday: dueToday);
    // 生成成功即自动打开「统计包含模拟数据」——否则开发者生成完
    // 在首页/统计看不到任何东西，等于白生成。
    if (r.error == null && r.records > 0) {
      await setIncludeSimulatedStats(true);
    } else {
      await bumpStatsRevision();
    }
    return r;
  }

  /// 清除模拟长期使用产生的全部数据（会话/记录/复习卡/错题条目）
  Future<int> clearSimulatedData() async {
    final n = await _db.clearSimulatedData();
    await bumpStatsRevision();
    return n;
  }

  /// 删除题库（同时清理答案记录）
  Future<void> deleteBank(int bankId) async {
    await _db.deleteBank(bankId);
    _selectedBankIds.remove(bankId);
    await _loadBanks();
    await bumpStatsRevision();
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

  Future<void> startQuiz({bool persistSession = true}) async {
    if (_selectedBankIds.isEmpty) return;

    // v1.0.2 设计审查修复：skipFSRS 复位收口到会话生命周期
    // （startQuiz/abortSession/endSession），不再依赖 QuizScreen.dispose 的
    // context.read 复位（Element 存活时机脆弱）
    _skipFSRS = false;

    await _quizService.startQuiz(
      bankIds: _selectedBankIds.toList(),
      mode: _selectedBankIds.length > 1 ? 'mixed' : 'single',
      questionCount: _selectedQuestionCount,
      noShuffle: _noShuffle,
      persistSession: persistSession,
    );

    _currentSession = _quizService.currentSession;
    _quizQuestions = _quizService.questions;
    _currentQuestionIndex = 0;
    _currentAnalysis = null;
    _lastAnswerRecord = null;
    _clearQuestionContext();
    _analysisLoading = false;
    _answerHistory.clear();
    _answerHistory.length = _quizQuestions.length;

    notifyListeners();
  }

  Future<void> submitAnswer(String userAnswer) async {
    final question = _quizService.currentQuestion;
    if (question == null) return;

    // v1.0.2 设计审查修复（async gap 竞态）：await DB 写入期间用户可能切题，
    // 必须用提交时刻的题号/题目 id 写历史槽位与统计，否则记录会写入错误槽
    final submitIndex = _currentQuestionIndex;
    final submitQid = question.id!;

    // v1.0.2 完善：该题已有作答记录（返回上一题重新作答）→ 走更新路径，
    // 不新增记录、不污染刷题量统计
    final hasPrev = submitIndex < _answerHistory.length &&
        _answerHistory[submitIndex] != null;
    if (hasPrev) {
      _lastAnswerRecord = await _quizService.resubmitAnswer(userAnswer);
    } else {
      _lastAnswerRecord = await _quizService.submitAnswer(userAnswer);
    }
    _currentSession = _quizService.currentSession;

    // 存储答题历史（按提交时刻的槽位）
    if (submitIndex < _answerHistory.length) {
      _answerHistory[submitIndex] = _lastAnswerRecord;
    }

    // 加载单题统计（按提交时刻的题目；切题后由 _restoreAnswerState 覆盖）
    final stats = await _quizService.getQuestionStats(submitQid);
    if (_currentQuestionIndex == submitIndex) {
      _currentQuestionStats = stats;
    }

    // 不再自动加载解析，由用户手动触发（仅当前题未变时才复位展示状态）
    if (_currentQuestionIndex == submitIndex) {
      _currentAnalysis = null;
      _analysisLoading = false;
    }

    // 更新 FSRS 状态（重答路径已由改判逻辑补记，不再重复更新）
    if (!_skipFSRS && !hasPrev) {
      try {
        await _updateFSRSIfNeeded(submitQid);
      } catch (e) {
        DebugLogService.instance.log('FSRS', '更新 FSRS 失败: $e');
      }
    }
    // v1.0.2 FSRS 可见化：提交后重读复习卡（间隔已更新），题号不变才回显
    if (_currentQuestionIndex == submitIndex) {
      _currentFsrsCard = await _db.getFSRSCard(submitQid);
    }

    notifyListeners();
  }

  /// v1.0.2 设计审查修复：进入「重新作答」只清 UI 展示状态。
  /// 保留 _answerHistory 记录 → 再提交时 hasPrev 为 true，走 resubmitAnswer
  /// 更新路径（不新增记录、不双计会话统计）；此前置 null 会走新增路径
  void resetCurrentAnswer() {
    _lastAnswerRecord = null;
    _clearQuestionContext();
    _currentAnalysis = null;
    _analysisLoading = false;
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
    final q = currentQuestion!;

    // v1.28.1 新生引导：未配置 Key 时回落展示题目自带解析（示例题库每题都有），
    // 有 Key 才走 AI（缓存 / 实时请求）。无自带解析则置空，由 UI 显示引导卡。
    if (!_settings.isConfigured) {
      final builtin = q.analysis?.trim() ?? '';
      _currentAnalysis = builtin.isNotEmpty ? builtin : null;
      _analysisLoading = false;
      notifyListeners();
      return;
    }

    _analysisLoading = true;
    notifyListeners();

    // 流式输出：边生成边显示。命中缓存时 streamAnalysis 会整段给出（不流式），
    // 因此这里的消费逻辑对「缓存 / 流式 / 回退一次性」三种情况都成立。
    //
    // 三处必须的防护：
    //   · 切题竞态：chunk 到达时比对题号，不是当前题就丢弃（流已随切题取消，
    //     但取消与在途 chunk 之间有窗口）
    //   · 节流：markdown 每帧全量重解析，逐 chunk 通知会掉帧 → 60ms 合并一次
    //   · 异常兜底：finally 复位 loading，防止加载圈永久卡死（沿用原逻辑）
    final questionId = q.id;
    // 必须先取消上一条流，并用**代次**而非题号做守卫：
    // 「点重新生成解析」「切走再切回」都会让同一题有两条流在跑，题号相等挡不住，
    // 两条流的 chunk 会交错写入 currentAnalysis（文本抖动、缓存被旧版本覆盖、
    // 还多花一份 token）。旧订阅若只是被覆盖赋值，就再也取消不掉了。
    _cancelAnalysisStream();
    final gen = ++_analysisGen;
    final sub = _aiService!.streamAnalysis(q).listen(
      (accumulated) {
        // 注意：不要在这里写 onError/onDone —— 下面的 `asFuture()` 会**覆盖**
        // listen 时传入的这两个回调（Dart SDK 行为），写了也不会执行。
        // 收尾统一由 catch / finally 负责。
        if (gen != _analysisGen || currentQuestion?.id != questionId) return;
        _currentAnalysis = accumulated;
        _analysisLoading = false; // 首个 chunk 到达即撤掉转圈
        _notifyAnalysisThrottled();
      },
      cancelOnError: true,
    );
    _analysisSub = sub;

    try {
      await sub.asFuture<void>();
    } catch (e) {
      DebugLogService.instance.log('AI', '解析加载失败: $e');
      if (gen == _analysisGen && currentQuestion?.id == questionId) {
        _currentAnalysis = null;
      }
    } finally {
      if (gen == _analysisGen && currentQuestion?.id == questionId) {
        _analysisLoading = false;
        notifyListeners();
      }
    }
  }

  /// 解析流的节流通知：60ms 内的多个 chunk 合并成一次 notifyListeners。
  void _notifyAnalysisThrottled() {
    final now = DateTime.now();
    if (now.difference(_lastAnalysisNotify) < const Duration(milliseconds: 60)) {
      return;
    }
    _lastAnalysisNotify = now;
    notifyListeners();
  }

  void _cancelAnalysisStream() {
    _analysisSub?.cancel();
    _analysisSub = null;
    // 代次自增：让在途 chunk 的回调立刻失效（取消与在途 chunk 之间有窗口）
    _analysisGen++;
  }

  /// 手动查看解析
  Future<void> showAnalysis() async {
    // 流式改造：**不再 await 解析**。对话页进入时会调它，若在这里等整条流结束，
    // 页面就一直显示转圈，「边生成边显示」等于白做。解析结果通过
    // currentAnalysis 的增量通知驱动 UI，调用方不需要等。
    unawaited(_loadAnalysis());
    await _loadFollowUpHistory();
  }

  /// 加载当前题的追问历史（聊天气泡式）
  Future<void> _loadFollowUpHistory() async {
    final q = currentQuestion;
    if (q?.id == null) {
      if (_followUpHistory.isNotEmpty) {
        _followUpHistory = [];
        notifyListeners();
      }
      return;
    }
    final rows = await _db.getFollowUpMessages(q!.id!);
    _followUpHistory = rows.map(FollowUpMessage.fromMap).toList();
    notifyListeners();
  }

  /// 供独立「AI 对话页」主动拉取当前题历史（页面进入时调用）
  Future<void> loadFollowUpHistory() => _loadFollowUpHistory();

  /// 清空当前题的追问历史（对话页右上角「清空对话」）
  Future<void> clearFollowUpHistory() async {
    final q = currentQuestion;
    if (q?.id == null) return;
    await _db.deleteFollowUpMessages(q!.id!);
    _followUpHistory = [];
    notifyListeners();
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

  /// 追问题目（聊天气泡式：用户消息与 AI 回复均入历史并持久化）
  Future<void> sendFollowUp(String question) async {
    final q = currentQuestion;
    if (_aiService == null || q?.id == null || _currentAnalysis == null) return;
    if (_followUpLoading) return; // 发送中防重复
    _followUpLoading = true;

    final qId = q!.id!;
    final userMsg = FollowUpMessage(role: 'user', content: question);
    _followUpHistory = [..._followUpHistory, userMsg];
    notifyListeners();
    await _db.saveFollowUpMessage(qId, 'user', question);

    var reply = '';
    // 流式输出：边生成边显示。_streamingReply 供对话页渲染进行中的气泡，
    // 生成完成后清空并照旧写入历史 + 落库（数据库只存最终完整文本）。
    //
    // 切题时**不能 break**——break 会取消底层订阅并留下半截回答，随后被当作
    // 最终结果落库（改造前只有完整结果才会存）。这里改成：继续把流读完，
    // 只是不再刷新 UI，这样回到那道题看到的是完整回答。
    _streamingReply = '';
    final onCurrentQuestion = () => currentQuestion?.id == qId;
    try {
      await for (final acc
          in _aiService!.streamFollowUp(q, _currentAnalysis!, question)) {
        reply = acc;
        if (!onCurrentQuestion()) continue; // 已切题：不更新 UI，但继续收完
        _streamingReply = acc;
        _notifyAnalysisThrottled();
      }
    } catch (e) {
      DebugLogService.instance.log('AI', '追问失败: $e');
    }
    _streamingReply = '';
    if (_isAiError(reply)) reply = '追问失败，请检查网络后重试。';

    _followUpLoading = false;
    // 竞态保护：期间切题则不再插入当前 UI 历史（数据库已按捕获题号保存）
    if (currentQuestion?.id == qId) {
      final aiMsg = FollowUpMessage(role: 'assistant', content: reply);
      _followUpHistory = [..._followUpHistory, aiMsg];
      notifyListeners();
    }
    await _db.saveFollowUpMessage(qId, 'assistant', reply);
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

  /// 直接跳转到指定题号（答题卡/底部圆点）。
  /// v1.0.2 设计审查修复：单次变更替代 while 逐题循环
  /// （每次 previous/next 都触发 notifyListeners + 逐题 DB 统计查询）
  void jumpToQuestion(int index) {
    if (_quizService.jumpToIndex(index)) {
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
    // v1.0.2 修复：返回已答题时保留单题统计（异步加载，避免切题竞态覆盖）
    final q = currentQuestion;
    if (q?.id != null) {
      final qid = q!.id!;
      _quizService.getQuestionStats(qid).then((stats) {
        if (_quizService.currentQuestion?.id == qid) {
          _currentQuestionStats = stats;
          notifyListeners();
        }
      });
      // v1.0.2 FSRS 可见化：切题异步读复习卡（竞态守卫）
      _db.getFSRSCard(qid).then((card) {
        if (_quizService.currentQuestion?.id == qid) {
          _currentFsrsCard = card;
          notifyListeners();
        }
      });
    } else {
      _clearQuestionContext();
    }
  }

  /// 当前会话是否已有作答记录
  bool get hasSessionAnswers => _quizService.hasAnyAnswers;

  /// 放弃当前会话（练习退出/未作答退出）：不保存记录、不产生幽灵会话
  Future<void> abortSession() async {
    _skipFSRS = false;
    await _quizService.abortSession();
    _currentSession = null;
    _quizQuestions = [];
    _clearQuestionContext();
    _lastAnswerRecord = null;
    // 会话行被删掉，首页续刷入口可能需要跟着消失
    await bumpStatsRevision();
  }

  /// 暂停当前会话（v1.0.2 七项改进：断点续刷）。
  /// 保留 DB 会话行（end_time 为空，历史列表显示「未完成」），
  /// 作答记录已逐题落库，下次继续时不丢进度
  Future<void> pauseSession() async {
    _skipFSRS = false;
    _quizService.pauseSession();
    _quizService.reset();
    _currentSession = null;
    _quizQuestions = [];
    _clearQuestionContext();
    _lastAnswerRecord = null;
    // 已答题 → 今天已刷，续排明天提醒
    try {
      await ReminderService.instance.rescheduleNextDay();
    } catch (_) {}
    // 必须走 bumpStatsRevision：本轮的作答已落库，但没走「答题结束」路径，
    // 而首页的续刷卡片与本周战绩都是页面私有 state，只在版本号变化时重载。
    // 只 notifyListeners 的话首页会拿旧值渲染 —— 实测表现为「暂停退出后回首页，
    // 续刷入口不出现、本周刷题仍显示 0，点一下刷新才出来」。
    await bumpStatsRevision();
  }

  /// 断点续刷：恢复最新未完成会话（题目顺序 + 作答历史 + 跳到第一个未答题）。
  /// 返回 true 表示恢复成功，调用方应进入 QuizScreen
  Future<bool> resumeUnfinishedSession() async {
    final unfinished = await _db.getLatestUnfinishedSession();
    if (unfinished == null) return false;
    final (session, _) = unfinished;
    if (session.id == null) return false;
    final questions = await _db.getSessionQuestions(session.id!);
    if (questions.isEmpty) return false;
    final records = await _db.getAnswerRecordsBySession(session.id!);

    _skipFSRS = false;
    _quizService.loadQuiz(questions: questions, session: session);
    _quizQuestions = questions;
    _currentSession = session;
    _currentAnalysis = null;
    _clearQuestionContext();
    _analysisLoading = false;
    _answerHistory.clear();
    _answerHistory.length = questions.length;
    for (var i = 0; i < questions.length; i++) {
      final q = questions[i];
      if (q.id != null && records.containsKey(q.id)) {
        _answerHistory[i] = records[q.id];
      }
    }
    // 跳到第一个未答题（全部答完则停在最后一题，走完成路径）
    var target = questions.length - 1;
    for (var i = 0; i < _answerHistory.length; i++) {
      if (_answerHistory[i] == null) {
        target = i;
        break;
      }
    }
    _quizService.jumpToIndex(target);
    _currentQuestionIndex = target;
    _lastAnswerRecord = _answerHistory[target];
    notifyListeners();
    return true;
  }

  /// 首页续刷卡片数据：最新未完成会话（含已答题数）
  Future<(QuizSession, int)?> getUnfinishedSessionInfo() =>
      _db.getLatestUnfinishedSession();

  /// 会话关联的题库名（统计页历史副标题用）
  Future<List<String>> getSessionBankNames(int sessionId) =>
      _db.getSessionBankNames(sessionId);

  /// v1.0.2 FSRS 可见化：批量取题目复习卡（错题本知识点弹窗逐题展示用）
  Future<Map<int, FSRSCardState>> getFsrsCardsByIds(List<int> questionIds) =>
      _db.getFsrsCardsByIds(questionIds);

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

  /// v1.0.2 设计审查修复：编辑题目后，若当前题已作答，按新正确答案重判该记录，
  /// 使判定显示与落库记录一致（会话统计/FSRS 由 rejudge 差量修正）
  Future<void> rejudgeCurrentAnswerAfterEdit() async {
    final record = _lastAnswerRecord;
    final q = currentQuestion;
    if (record == null || record.id == null || q == null) return;
    final isCorrect = QuizService.judgeAnswer(q, record.userAnswer ?? '');
    if (isCorrect == record.isCorrect) return;
    await _db.rejudgeAnswerRecord(record.id!, isCorrect);
    _quizService.adjustSessionCounts(toCorrect: isCorrect);
    _currentSession = _quizService.currentSession;
    final updated = record.copyWith(isCorrect: isCorrect);
    _lastAnswerRecord = updated;
    if (_currentQuestionIndex < _answerHistory.length) {
      _answerHistory[_currentQuestionIndex] = updated;
    }
    notifyListeners();
  }

  Future<QuizSession> endSession() async {
    // 会话落库后统计口径变化（末尾统一 bump）
    _skipFSRS = false;
    _currentSession = await _quizService.endSession();
    _quizService.reset();
    // v1.0.2: 答题完成后续排明天提醒
    try {
      await ReminderService.instance.rescheduleNextDay();
    } catch (_) {}
    // 首页的续刷卡片要在这里消失、本周战绩要在这里更新，都靠版本号触发
    await bumpStatsRevision();
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

  /// 获取错题本统计（按题库分组）：到期题数 + 收藏题数 + 全部去重
  Future<List<Map<String, dynamic>>> getErrorBookStats() async {
    return await _db.getErrorStatsByBank();
  }

  // ======================== v1.0.2: 错题本筛选/知识点 ========================

  /// 按筛选模式取错题全量题列表（mode: all/wrong/bookmark）
  Future<List<Question>> getFullErrorQuestions(String mode,
          {Set<int>? bankIds}) =>
      _db.getFullErrorQuestions(mode, bankIds: bankIds);

  /// 按筛选模式的错题总数
  Future<int> getFullErrorCount(String mode, {Set<int>? bankIds}) =>
      _db.getFullErrorCount(mode, bankIds: bankIds);

  /// 知识点分组统计（与主列表同口径）
  Future<List<Map<String, dynamic>>> getKnowledgePointStats(String mode,
          {Set<int>? bankIds}) =>
      _db.getKnowledgePointStats(mode, bankIds: bankIds);

  /// 按知识点取题（复习范围与主列表同口径）
  Future<List<Question>> getFullQuestionsByKnowledgePoint(
          String kp, String mode,
          {Set<int>? bankIds}) =>
      _db.getFullQuestionsByKnowledgePoint(kp, mode, bankIds: bankIds);

  /// 错题复习：按筛选模式取题（all/wrong/bookmark）+ 可选知识点
  /// [kp] 非空时复习指定知识点（会话 mode = kp_review）
  Future<void> startErrorReview({
    String mode = 'all',
    Set<int>? bankIds,
    String? kp,
  }) async {
    final List<Question> questions;
    if (kp != null && kp.isNotEmpty) {
      questions =
          await _db.getFullQuestionsByKnowledgePoint(kp, mode, bankIds: bankIds);
    } else {
      questions = await _db.getFullErrorQuestions(mode, bankIds: bankIds);
    }
    if (questions.isEmpty) return;

    questions.shuffle();
    // v1.0.2 修复：错题复习不再被 selectedQuestionCount（默认 50）静默截断，
    // 复习范围与错题本展示口径一致
    final selectedQuestions = questions;

    // 开始新会话前，清空上一次未完成会话的断档记录（新会话取代旧中断会话）
    await _db.deleteUnfinishedSessions();

    final session = QuizSession(
      bankIds: bankIds?.join(',') ?? 'all',
      mode: kp != null && kp.isNotEmpty ? 'kp_review' : 'error_review',
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
    // v1.0.2 七项改进：会话题目顺序 + 题库关联（断点续刷/历史副标题用）
    final questionBankIds =
        selectedQuestions.map((q) => q.bankId).toSet().toList();
    await _db.insertSessionBanks(sessionWithId.id!, questionBankIds);
    await _db.insertSessionQuestions(sessionWithId.id!, selectedQuestions);
    _quizQuestions = _quizService.questions;
    _currentSession = _quizService.currentSession;
    _currentQuestionIndex = 0;
    _currentAnalysis = null;
    _lastAnswerRecord = null;
    _clearQuestionContext();
    _answerHistory.clear();
    _answerHistory.length = _quizQuestions.length;

    notifyListeners();
  }

  // ======================== v1.0.2 对齐里程碑：打标签 / 改判 / 隐藏今日 ========================

  /// 未打知识标签的错题数（设置页入口角标）
  Future<int> getUntaggedErrorCount() => _db.getUntaggedErrorCount();

  /// 未打知识标签的错题列表（批处理上限）
  Future<List<Question>> getUntaggedErrorQuestions({int limit = 200}) =>
      _db.getUntaggedErrorQuestions(limit: limit);

  /// 更新题目知识点标签
  Future<void> updateQuestionKnowledgePoint(int questionId, String kp) =>
      _db.updateQuestionKnowledgePoint(questionId, kp);

  /// 改判一条作答记录（会话统计 + FSRS 同步修正）
  Future<void> rejudgeAnswerRecord(int recordId, bool isCorrect) async {
    await _db.rejudgeAnswerRecord(recordId, isCorrect);
    await bumpStatsRevision();
  }

  /// 隐藏今日全部作答记录
  Future<int> hideTodayRecords() async {
    final n = await _db.hideTodayRecords();
    await bumpStatsRevision();
    return n;
  }

  /// 恢复被隐藏的今日作答记录
  Future<int> restoreTodayRecords() async {
    final n = await _db.restoreTodayRecords();
    await bumpStatsRevision();
    return n;
  }

  /// 今日被隐藏记录条数
  Future<int> getHiddenTodayRecordCount() => _db.getHiddenTodayRecordCount();

  // ======================== v1.0.2 对齐里程碑：错题导出 JSON ========================

  /// 导出错题为 .json 题库文件（带 format 标记），返回 `(文件路径, 题数)`；
  /// 无题可导出时返回 `(null, 0)`。
  ///
  /// 排序与筛选都在 SQL 里做（默认「错得最多」= `ORDER BY wrong_count DESC`），
  /// 不把全量题拉到 Dart 再排。
  ///
  /// - [window]：按最近一次作答时间过滤，`'7d'` / `'30d'`
  /// - [recentFirst]：true = 最近做过的在前；默认错得最多的在前
  /// - [questionIds]：自定义选题导出
  /// - [knowledgePoint]：只导出某个知识点（「最薄弱点」导出走这里）
  /// - [includeStats]：给每题附 `stats` / `fsrs` 元数据。**向后兼容**：
  ///   导入侧只读已知键、忽略未知键，所以带统计的导出文件仍可被当前版本导入。
  Future<(String?, int)> exportErrorQuestionsJson(
    String mode, {
    Set<int>? bankIds,
    Set<int>? questionIds,
    String? knowledgePoint,
    String? window,
    bool recentFirst = false,
    bool includeStats = false,
  }) async {
    final rows = await _db.getErrorQuestionsWithStats(
      mode,
      bankIds: bankIds,
      questionIds: questionIds,
      knowledgePoint: knowledgePoint,
      window: window,
      recentFirst: recentFirst,
    );
    if (rows.isEmpty) return (null, 0);

    // 只有需要统计时才批量取 FSRS 卡（一次 IN 查询，不是逐题）
    Map<int, FSRSCardState> cards = const {};
    if (includeStats) {
      final ids = rows.map((r) => r['id'] as int).toList();
      cards = await _db.getFsrsCardsByIds(ids);
    }

    final list = rows.map((m) {
      final q = Question.fromMap(m);
      final entry = <String, dynamic>{
        'title': q.title,
        'options': q.options,
        'correct_answer': q.correctAnswer,
        'analysis': q.analysis,
        'question_type': q.questionType,
        'knowledge_point': q.knowledgePoint,
      };
      if (includeStats) {
        entry['stats'] = {
          'answered': (m['answered_count'] as int?) ?? 0,
          'correct': (m['correct_count'] as int?) ?? 0,
          'wrong': (m['wrong_count'] as int?) ?? 0,
          'last_answered_at': m['last_answered_at'],
        };
        final card = q.id == null ? null : cards[q.id];
        if (card != null) {
          entry['fsrs'] = {
            'stability': card.stability,
            'difficulty': card.difficulty,
            'review_count': card.reviewCount,
            'last_review_at': card.lastReviewAt.toIso8601String(),
            'next_review_at': card.nextReviewAt.toIso8601String(),
          };
        }
      }
      return entry;
    }).toList();

    final stamp = DateTime.now();
    final json = const JsonEncoder.withIndent('  ').convert({
      'format': BankFileService.formatMarker,
      'name': '错题导出_${stamp.millisecondsSinceEpoch}',
      'count': list.length,
      'exported_at': stamp.toIso8601String(),
      'filter': {
        'mode': mode,
        if (window != null) 'window': window,
        if (knowledgePoint != null) 'knowledge_point': knowledgePoint,
      },
      'questions': list,
    });
    // 写在系统临时目录（Android 上即应用缓存目录），不建子目录；
    // 文件名带毫秒 + 亚毫秒，同一毫秒内连续导出两次不会互相覆盖。
    final name = '错题导出_${stamp.millisecondsSinceEpoch}'
        '${stamp.microsecond % 1000}';
    final dir = Directory.systemTemp;
    _recycleOldExports(dir, stamp);
    final file = File('${dir.path}/$name.json');
    await file.writeAsString(json);
    return (file.path, list.length);
  }

  /// 生成打印用的错题练习卷（.docx），返回 `(文件路径, 题数)`；无题时 `(null, 0)`。
  ///
  /// 与 [exportErrorQuestionsJson] 共用同一套范围筛选（bankIds / questionIds /
  /// knowledgePoint / window / recentFirst），差别只在**产物**：
  /// JSON 是给猫卷自己再导入用的，docx 是给学生打印纸质题目的。
  /// 两种 [DocxAnswerPlacement] 的内容完全一样，只有答案块的位置不同。
  Future<(String?, int)> exportErrorQuestionsDocx(
    String mode, {
    Set<int>? bankIds,
    Set<int>? questionIds,
    String? knowledgePoint,
    String? window,
    bool recentFirst = false,
    required DocxAnswerPlacement placement,
    String? subtitle,
  }) async {
    final rows = await _db.getErrorQuestionsWithStats(
      mode,
      bankIds: bankIds,
      questionIds: questionIds,
      knowledgePoint: knowledgePoint,
      window: window,
      recentFirst: recentFirst,
    );
    if (rows.isEmpty) return (null, 0);
    final questions = rows.map((m) => Question.fromMap(m)).toList();

    final bytes = DocxExportService.build(
      questions: questions,
      placement: placement,
      subtitle: subtitle,
    );
    final stamp = DateTime.now();
    final name = '错题练习_${stamp.millisecondsSinceEpoch}'
        '${stamp.microsecond % 1000}';
    final dir = Directory.systemTemp;
    _recycleOldExports(dir, stamp);
    final file = File('${dir.path}/$name.docx');
    await file.writeAsBytes(bytes, flush: true);
    return (file.path, questions.length);
  }

  /// 回收一小时前的旧导出文件。
  ///
  /// 分享用的是 share_plus 复制出去的副本，但刚导出那份可能还在分享目标手里，
  /// 所以按时间留一段宽限期，而不是导一次删一次。
  void _recycleOldExports(Directory dir, DateTime now) {
    try {
      final cutoff = now.subtract(const Duration(hours: 1));
      for (final f in dir.listSync()) {
        final base = f.path.split(RegExp(r'[\\/]')).last;
        final ours = (base.startsWith('错题导出_') && base.endsWith('.json')) ||
            (base.startsWith('错题练习_') && base.endsWith('.docx'));
        if (f is File && ours && f.lastModifiedSync().isBefore(cutoff)) {
          f.deleteSync();
        }
      }
    } catch (_) {
      // 清理失败（权限/占用）不影响导出本身
    }
  }

  /// 批量取逐题作答统计（做过几次 / 正确数）。一次聚合查询，供错题列表与卡片使用。
  Future<Map<int, (int total, int correct)>> getQuestionStatsByIds(
          List<int> questionIds) =>
      _db.getQuestionStatsByIds(questionIds);

  /// 错题卡片数据：题目 + 作答次数/正确数 + FSRS 卡。
  ///
  /// 两条批量查询（题目+统计一条、FSRS 一条），**避免 N+1**；
  /// 卡片上要显示的「做过几次 / 正确率 / 下次复习」都来自这里。
  Future<List<({Question question, int answered, int correct, FSRSCardState? card})>>
      getErrorQuestionCards(
    String mode, {
    Set<int>? bankIds,
    String? window,
    bool recentFirst = false,
  }) async {
    final rows = await _db.getErrorQuestionsWithStats(
      mode,
      bankIds: bankIds,
      window: window,
      recentFirst: recentFirst,
    );
    if (rows.isEmpty) return const [];
    final ids = rows.map((r) => r['id'] as int).toList();
    final cards = await _db.getFsrsCardsByIds(ids);
    return rows.map((m) {
      final q = Question.fromMap(m);
      return (
        question: q,
        answered: (m['answered_count'] as int?) ?? 0,
        correct: (m['correct_count'] as int?) ?? 0,
        card: q.id == null ? null : cards[q.id],
      );
    }).toList();
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
    final result = await _aiService!.generateSessionSummary(
      session.totalQuestions,
      session.correctCount,
      session.wrongCount,
      session.durationSeconds,
    );
    // v1.0.2 对齐里程碑：失败统一提示
    if (_isAiError(result)) return '小结生成失败，请检查网络或 API 配置后重试。';
    return result;
  }

  /// AI 错误串判定（AI请求失败/AI服务返回错误/解析生成失败）
  bool _isAiError(String s) =>
      s.startsWith('AI请求失败') ||
      s.startsWith('AI服务返回错误') ||
      s.contains('解析生成失败');

  @override
  void dispose() {
    _cancelAnalysisStream();
    _aiService?.dispose();
    super.dispose();
  }
}

/// 后台导入任务类型（v1.27）
enum ImportTaskKind { json, sample, docxParse }

/// 后台导入完成结果：主壳据此弹「导入完成」提示（仅一次，
/// 消费后清除）；docxParse 成功时引导去预览确认页。
class ImportTaskResult {
  final ImportTaskKind kind;
  final bool success;
  final String message;
  final int questionCount;

  const ImportTaskResult({
    required this.kind,
    required this.success,
    required this.message,
    this.questionCount = 0,
  });
}
