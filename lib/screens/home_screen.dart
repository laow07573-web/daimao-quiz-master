import 'practice_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/quiz_session.dart';
import '../services/app_state.dart';
import '../services/hitokoto_service.dart';
import '../services/theme_service.dart';
import '../utils/app_constants.dart';
import '../utils/format_utils.dart';
import '../widgets/weekly_stats_board.dart';
import 'bank_manage_screen.dart';
import 'import_screen.dart';
import 'settings_screen.dart';
import 'quiz_screen.dart';
import 'error_book_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // v1.0.2: 战绩数据（本周刷题/连续打卡/年度热力）
  Map<String, int> _yearlyTotals = {};
  Set<String> _vacationDays = {};
  int _streakDays = 0;
  int _weekTotal = 0;
  double _weekAccuracy = 0;
  bool _statsLoaded = false; // 防横幅首帧闪现
  // v1.0.2 扩展：今日一言（开页面显示）
  String _hitokoto = '正在加载一言...';
  // v1.0.2 七项改进：断点续刷（最新未完成会话 + 已答题数）
  (QuizSession, int)? _unfinished;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final appState = context.read<AppState>();
      _loadWeeklyData(appState);
    });
    _loadHitokoto();
  }

  Future<void> _loadHitokoto() async {
    final text = await HitokotoService.fetch();
    if (!mounted) return;
    setState(() => _hitokoto = text ?? HitokotoService.defaultText);
  }

  Future<void> _loadWeeklyData(AppState appState) async {
    try {
      final yearly = await appState.getYearlyTotals();
      final streak = await appState.getStreakDays();
      final weekStats = await appState.getPeriodStats('week');
      final vacation = {
        for (final d in appState.vacationDateRange) dateKeyOf(d)
      };
      // v1.0.2 七项改进：断点续刷卡片数据
      final unfinished = await appState.getUnfinishedSessionInfo();
      if (!mounted) return;
      setState(() {
        _yearlyTotals = yearly;
        _streakDays = streak;
        _weekTotal = weekStats.totalQuestions;
        _weekAccuracy = weekStats.accuracy;
        _vacationDays = vacation;
        _unfinished = unfinished;
        _statsLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _statsLoaded = true);
    }
  }

  bool _vacationBlocked(AppState appState) {
    if (!appState.vacationModeEnabled) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('寒暑假模式中，答题功能已暂停')),
    );
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('呆猫刷题宝',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: Consumer<AppState>(
        builder: (context, appState, _) {
          return RefreshIndicator(
            onRefresh: () async {
              await appState.init();
              await _loadWeeklyData(appState);
              await _loadHitokoto();
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 顶部：问候语（第一行）+ 软件图标/名字 + 今日一言
                  _buildHeroCard(appState, cs),
                  const SizedBox(height: 16),
                  // v1.0.2 七项改进：断点续刷入口（有未完成会话时显示）
                  if (_unfinished != null)
                    _buildResumeCard(appState, cs),
                  // 寒暑假模式横幅
                  if (appState.vacationModeEnabled)
                    _buildVacationBanner(cs),
                  // API 余额不足警告（首帧加载完成后才显示，防闪现）
                  if (_statsLoaded &&
                      appState.aiService != null &&
                      appState.aiService!.cachedBalance != null &&
                      appState.aiService!.cachedBalance! > 0 &&
                      appState.aiService!.cachedBalance! < 1.0)
                    _buildBalanceWarning(cs),
                  // 本周战绩（v1.0.2 UI 设计稿：双数据块 + 单月打卡日历 + 连续打卡周）
                  WeeklyStatsBoard(
                    dailyTotals: _yearlyTotals,
                    streakDays: _streakDays,
                    weekTotal: _weekTotal,
                    weekAccuracy: _weekAccuracy,
                    vacationDays: _vacationDays,
                    // v1.0.2 对齐原版：历史报告（近 7 天明细）
                    onHistoryReport: () => _showHistoryReport(appState),
                  ),
                  const SizedBox(height: 16),
                  _buildStatsCards(appState, cs),
                  const SizedBox(height: 24),
                  _buildQuickActions(appState, cs),
                  const SizedBox(height: 24),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Text(
                      // v1.0.2 修复：版本号统一 v1.26.6.17（与我的页/关于弹窗一致）
                      '本软件由b站：笨蛋鱼坏蛋猫 开发 | $kAppVersion',
                      style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant.withOpacity(0.4)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 顶部问候语（第一行）+ 软件图标/名字 + 今日一言
  Widget _buildHeroCard(AppState appState, ColorScheme cs) {
    final nickname = appState.settings.nickname;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.primary, cs.primary.withOpacity(0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 第一行：问候语 + 昵称
          Text(
            _greeting,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: cs.onPrimary,
            ),
          ),
          if (nickname.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              nickname,
              style: TextStyle(
                fontSize: 13,
                color: cs.onPrimary.withOpacity(0.85),
              ),
            ),
          ],
          const SizedBox(height: 14),
          // 软件图标 + 软件名字 + 今日一言
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  'assets/app_logo.png',
                  width: 42,
                  height: 42,
                  errorBuilder: (_, __, ___) =>
                      Icon(Icons.school, size: 36, color: cs.onPrimary),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '呆猫刷题宝',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: cs.onPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _hitokoto,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onPrimary.withOpacity(0.9),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String get _greeting => greetingNow();

  /// v1.0.2 对齐原版：历史报告（近 7 天每日刷题明细）
  Future<void> _showHistoryReport(AppState appState) async {
    final daily = await appState.getDailyStats(7);
    final acc = await appState.getDailyAccuracy(7);
    final accByDay = <String, Map<String, dynamic>>{
      for (final a in acc) (a['day'] as String): a,
    };
    if (!mounted) return;
    final cs = Theme.of(context).colorScheme;
    const week = ['一', '二', '三', '四', '五', '六', '日'];
    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          // v1.0.2 修复：小屏/大字体下可滚动，避免溢出
          child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: cs.onSurfaceVariant.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              Text('历史报告（近 7 天）',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface)),
              const SizedBox(height: 12),
              for (final d in daily)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 76,
                        child: Text(
                          '${(d['date'] as DateTime).month}月'
                          '${(d['date'] as DateTime).day}日 周'
                          '${week[(d['date'] as DateTime).weekday - 1]}',
                          style: TextStyle(
                              fontSize: 13, color: cs.onSurface),
                        ),
                      ),
                      Text('${d['total']} 题',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: (d['total'] as int) > 0
                                  ? cs.primary
                                  : cs.onSurfaceVariant)),
                      const Spacer(),
                      Text(
                        _accuracyText(d, accByDay),
                        style: TextStyle(
                            fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ),
          ),
        ),
      ),
    );
  }

  String _accuracyText(
      Map<String, dynamic> d, Map<String, dynamic> accByDay) {
    final key = dateKeyOf(d['date'] as DateTime);
    final row = accByDay[key];
    final total = (row?['total'] as int?) ?? 0;
    final correct = (row?['correct'] as int?) ?? 0;
    if (total <= 0) return '—';
    return '正确率 ${(correct / total * 100).toStringAsFixed(0)}%';
  }

  /// v1.0.2 七项改进：断点续刷卡片（最新未完成会话）
  Widget _buildResumeCard(AppState appState, ColorScheme cs) {
    final u = _unfinished;
    if (u == null) return const SizedBox.shrink();
    final (session, answered) = u;
    final ac = AppThemeColors.of(context);
    final modeLabel = switch (session.mode) {
      'error_review' => '错题复习',
      'kp_review' => '知识点复习',
      _ => '刷题',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: ac.card,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () async {
            final ok = await appState.resumeUnfinishedSession();
            if (!ok || !mounted) return;
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const QuizScreen()),
            );
            await _loadWeeklyData(appState);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: ac.accent.withOpacity(0.5)),
            ),
            child: Row(
              children: [
                Icon(Icons.play_circle_fill, color: ac.accent, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('继续上次刷题',
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: cs.onSurface)),
                      const SizedBox(height: 2),
                      Text(
                        '已答 $answered/${session.totalQuestions} 题 · $modeLabel',
                        style: TextStyle(
                            fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right,
                    size: 20, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 寒暑假模式横幅
  Widget _buildVacationBanner(ColorScheme cs) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cs.error.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.error.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.beach_access, color: cs.error, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '寒暑假模式已开启，答题功能暂停，错题本仍可浏览',
              style: TextStyle(fontSize: 13, color: cs.error),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceWarning(ColorScheme cs) {
    // v1.0.2 UI 设计稿：警告色走主题 tertiary（无硬编码色值）
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cs.tertiaryContainer.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.tertiary.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber, color: cs.tertiary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'API 余额不足 ¥1，建议尽快充值以免影响使用',
              style: TextStyle(fontSize: 13, color: cs.onTertiaryContainer),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCards(AppState appState, ColorScheme cs) {
    final stats = appState.homeStats;
    final ac = AppThemeColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.timer_outlined,
                label: '累计刷题时长',
                value: stats?.formattedDuration ?? '0 h 0 m',
                color: ac.accent,
                cs: cs,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                icon: Icons.quiz_outlined,
                label: '总刷题量',
                value: '${stats?.totalQuestions ?? 0} 题',
                color: ac.accent.withOpacity(0.8),
                cs: cs,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                icon: Icons.trending_up,
                label: '平均正确率',
                value: stats?.formattedAccuracy ?? '0%',
                color: cs.secondary,
                cs: cs,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '仅统计按「结束」完成的会话时长，中途退出不计',
          style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
        ),
      ],
    );
  }

  /// 快速操作列表（v1.0.2 UI 设计稿：5 项，每项带状态文案与真实路由）
  Widget _buildQuickActions(AppState appState, ColorScheme cs) {
    final vacation = appState.vacationModeEnabled;
    final ac = AppThemeColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('快速操作',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: cs.onSurface)),
        const SizedBox(height: 12),
        // 1. 定向爆破
        _QuickActionTile(
          icon: Icons.rocket_launch_rounded,
          label: '定向爆破',
          subtitle: appState.selectedBankIds.isEmpty
              ? '请先选择题库'
              : '已选${appState.selectedBankIds.length}个题库，${appState.selectedQuestionCount >= kQuestionCountAll ? '全部' : '${appState.selectedQuestionCount}题'}',
          iconColor: ac.accent,
          cs: cs,
          onTap: appState.selectedBankIds.isEmpty
              ? () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('请先在「管理题库」中选择要刷的题库')),
                  );
                }
              : () {
                  if (vacation) {
                    _vacationBlocked(appState);
                    return;
                  }
                  _showCountPicker(context, appState);
                },
        ),
        // 2. 管理题库 → 题库管理页
        _QuickActionTile(
          icon: Icons.library_books_outlined,
          label: '管理题库',
          subtitle: '${appState.banks.length} 个题库',
          iconColor: ac.accent.withOpacity(0.8),
          cs: cs,
          onTap: () => _navigateAndRefresh(
              context, appState, const BankManageScreen()),
        ),
        // 3. 错题本 → 错题复习页
        _QuickActionTile(
          icon: Icons.replay_rounded,
          label: '错题本',
          subtitle: '使用 FSRS 算法全权生成',
          iconColor: cs.error,
          cs: cs,
          onTap: () =>
              _navigateAndRefresh(context, appState, const ErrorBookScreen()),
        ),
        // 4. 导入 DOCX → 文件导入页
        _QuickActionTile(
          icon: Icons.upload_file,
          label: '导入 DOCX',
          subtitle: 'AI 解析题库文档',
          iconColor: cs.tertiary,
          cs: cs,
          onTap: () =>
              _navigateAndRefresh(context, appState, const ImportScreen()),
        ),
        // 5. 题库文件 → 文件导入页（JSON 直接入库）
        _QuickActionTile(
          icon: Icons.folder_open,
          label: '题库文件',
          subtitle: '导入 Json 题库',
          iconColor: cs.secondary,
          cs: cs,
          onTap: () =>
              _navigateAndRefresh(context, appState, const ImportScreen()),
        ),
      ],
    );
  }

  /// 路由占位：跳转页面并返回后刷新战绩
  Future<void> _navigateAndRefresh(
      BuildContext context, AppState appState, Widget page) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
    await _loadWeeklyData(appState);
  }

  void _showCountPicker(BuildContext context, AppState appState) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: cs.onSurfaceVariant.withOpacity(0.3), borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 20),
            Text('选择刷题数量', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: cs.onSurface), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Wrap(spacing: 12, runSpacing: 12, alignment: WrapAlignment.center, children: [
              ...[10, 20, 30, 50, 80, 100].map((n) => ChoiceChip(
                label: Text('$n 题'), selected: appState.selectedQuestionCount == n,
                onSelected: (_) { appState.setQuestionCount(n); Navigator.pop(ctx); _showQuizModePicker(context, appState); },
              )),
              // v1.0.2 设计审查修复：全部/自定义的选中态反馈
              ChoiceChip(label: const Text('全部'), selected: appState.selectedQuestionCount >= kQuestionCountAll, onSelected: (_) { appState.setQuestionCount(kQuestionCountAll); Navigator.pop(ctx); _showQuizModePicker(context, appState); }),
              ChoiceChip(label: const Text('自定义'), selected: false, onSelected: (_) { Navigator.pop(ctx); _showCustomCountDialog(context, appState); }),
            ]),
            const SizedBox(height: 12),
            Text('当前: ${appState.selectedQuestionCount >= kQuestionCountAll ? '全部' : '${appState.selectedQuestionCount} 题'}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant), textAlign: TextAlign.center),
          ]),
        ),
      ),
    );
  }

  void _showCustomCountDialog(BuildContext context, AppState appState) {
    final ctrl = TextEditingController();
    // v1.0.2 修复：弹窗关闭后释放 controller
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('自定义题目数'),
        content: TextField(controller: ctrl, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: '输入题数', border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () {
            final n = int.tryParse(ctrl.text);
            // v1.0.2 设计审查修复：非法输入给出反馈，不再静默无响应
            if (n == null || n <= 0) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('请输入大于 0 的有效题数')),
              );
              return;
            }
            appState.setQuestionCount(n);
            Navigator.pop(ctx);
            _showQuizModePicker(context, appState);
          }, child: const Text('确定')),
        ],
      ),
    ).then((_) => ctrl.dispose());
  }

  void _showQuizModePicker(BuildContext context, AppState appState) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text('选择刷题模式',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: cs.onSurface),
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text('已选 ${appState.selectedBankIds.length} 个题库，${appState.selectedQuestionCount >= kQuestionCountAll ? '全部' : '${appState.selectedQuestionCount} 题'}/轮',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  textAlign: TextAlign.center),
              const SizedBox(height: 20),
              _ModeOption(
                icon: Icons.flash_on_rounded,
                label: '正常刷题',
                desc: '答完即判，立刻校对解析',
                color: cs.primary,
                cs: cs,
                onTap: () {
                  Navigator.pop(ctx);
                  _startQuiz(context, appState);
                },
              ),
              const SizedBox(height: 10),
              _ModeOption(
                icon: Icons.edit_square,
                label: '练习',
                desc: '答题卡模式，限时/不限时，统一批改',
                color: cs.secondary,
                cs: cs,
                onTap: () {
                  Navigator.pop(ctx);
                  _startPractice(context, appState);
                },
              ),
              const SizedBox(height: 10),
              _ModeOption(
                icon: Icons.visibility_rounded,
                label: '背题模式',
                desc: '直接展示答案，快速浏览记忆',
                color: cs.tertiary,
                cs: cs,
                onTap: () {
                  Navigator.pop(ctx);
                  _startMemorize(context, appState);
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _startQuiz(BuildContext context, AppState appState) async {
    if (_vacationBlocked(appState)) return;
    // v1.0.2 修复：刷题不再强制要求 API Key（AI 解析/追问内部单独提示）

    await appState.startQuiz();

    if (appState.quizQuestions.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('所选题库中没有题目，请先导入题目')),
      );
      return;
    }

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const QuizScreen()),
    );
    // 返回首页后刷新战绩（v1.0.2）
    await _loadWeeklyData(appState);
  }

  Future<void> _startPractice(BuildContext context, AppState appState) async {
    if (_vacationBlocked(appState)) return;
    if (appState.selectedBankIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在首页选择题库')),
      );
      return;
    }
    // v1.0.2 修复：练习不落会话行（退出后练习记录不保存的承诺），无需 API Key
    await appState.startQuiz(persistSession: false);
    if (appState.quizQuestions.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('所选题库中没有题目，请先导入题目')),
      );
      return;
    }
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => const PracticeEntryScreen(),
    ));
    await _loadWeeklyData(appState);
  }

  Future<void> _startMemorize(BuildContext context, AppState appState) async {
    if (_vacationBlocked(appState)) return;
    // v1.0.2 修复：背题无需 API Key；不落会话行（背题不计统计）
    if (appState.selectedBankIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在首页选择题库')),
      );
      return;
    }
    appState.noShuffle = true;
    try {
      await appState.startQuiz(persistSession: false);
    } finally {
      appState.noShuffle = false; // v1.0.2 修复：异常时也复位，防泄漏到后续会话
    }
    if (appState.quizQuestions.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('所选题库中没有题目，请先导入题目')),
      );
      return;
    }
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => QuizScreen(quizMode: QuizMode.memorize),
    ));
    await _loadWeeklyData(appState);
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final ColorScheme cs;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
            child: Text(value,
                key: ValueKey(value),
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          ),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// 快速操作列表项（v1.0.2 UI 设计稿：图标 + 标题 + 状态副标题 + 跳转）
class _QuickActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color iconColor;
  final ColorScheme cs;
  final VoidCallback onTap;

  const _QuickActionTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.iconColor,
    required this.cs,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: ac.card,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: ac.cardBorder),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: iconColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: cs.onSurface)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String desc;
  final Color color;
  final ColorScheme cs;
  final VoidCallback onTap;

  const _ModeOption({
    required this.icon,
    required this.label,
    required this.desc,
    required this.color,
    required this.cs,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(label,
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: cs.onSurface)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(desc,
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: cs.onSurfaceVariant, size: 20),
          ],
        ),
      ),
    );
  }
}

