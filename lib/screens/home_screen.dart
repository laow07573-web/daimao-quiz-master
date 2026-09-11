import 'practice_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/quiz_session.dart';
import '../services/app_state.dart';
import '../services/hitokoto_service.dart';
import '../services/theme_service.dart';
import '../utils/app_constants.dart';
import '../utils/design_tokens.dart';
import '../utils/format_utils.dart';
import '../utils/responsive.dart';
import '../widgets/weekly_stats_board.dart';
import 'bank_manage_screen.dart';
import 'import_preview_screen.dart';
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
    // v1.0.2 扩展：今日一言（开页面显示）。
    // v1.27 PC 加载修复：首帧直接显示缓存/本地一言，不再显示「正在加载一言...」，
    // 网络结果到达后静默替换；失败也不回退占位文案。
    String _hitokoto = HitokotoService.immediateText();
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
    // v1.27：成功更新为网络一言；失败保持首帧的缓存/本地一言，
    // 不再回退成固定默认句，也不闪「加载中」占位。
    if (text != null) {
      setState(() => _hitokoto = text);
    }
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
    final ac = AppThemeColors.of(context);
    return Scaffold(
      backgroundColor: ac.background,
      appBar: AppBar(
        title: const Text('猫卷'),
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
              padding: const EdgeInsets.all(MaoSpace.md),
              // 平板适配：内容限宽居中；宽屏双列布局
              child: ResponsivePage(
              child: isWideLayout(context)
                  ? _buildWideBody(appState, ac)
                  : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 后台导入：导入中进度卡（离开导入页后在此展示）
                  if (appState.importTaskActive) ...[
                    _buildImportProgressCard(appState, ac),
                    const SizedBox(height: MaoSpace.md),
                  ],
                  // 后台导入：AI 解析完成待预览确认入口（入库前保留）
                  if (!appState.importTaskActive &&
                      appState.previewQuestions.isNotEmpty) ...[
                    _buildPreviewConfirmCard(appState, ac),
                    const SizedBox(height: MaoSpace.md),
                  ],
                  // 顶部：问候语 + 软件图标/名字 + 今日一言
                  _buildHeroCard(appState, ac),
                  const SizedBox(height: MaoSpace.md),
                  // 断点续刷入口（有未完成会话时显示）
                  if (_unfinished != null)
                    _buildResumeCard(appState, ac),
                  // 寒暑假模式横幅
                  if (appState.vacationModeEnabled)
                    _buildVacationBanner(ac),
                  // API 余额不足警告（首帧加载完成后才显示，防闪现）
                  if (_statsLoaded &&
                      appState.aiService != null &&
                      appState.aiService!.cachedBalance != null &&
                      appState.aiService!.cachedBalance! > 0 &&
                      appState.aiService!.cachedBalance! < 1.0)
                    _buildBalanceWarning(ac),
                  // 本周战绩（双数据块 + 单月打卡日历 + 连续打卡）
                  WeeklyStatsBoard(
                    dailyTotals: _yearlyTotals,
                    streakDays: _streakDays,
                    weekTotal: _weekTotal,
                    weekAccuracy: _weekAccuracy,
                    vacationDays: _vacationDays,
                    onHistoryReport: () => _showHistoryReport(appState),
                  ),
                  const SizedBox(height: MaoSpace.md),
                  _buildStatsCards(appState, ac),
                  const SizedBox(height: MaoSpace.xl),
                  _buildQuickActions(appState, ac),
                  const SizedBox(height: MaoSpace.lg),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Text(
                      '本软件由b站：笨蛋鱼坏蛋猫 开发 | $kAppVersion',
                      style: MaoType.captionStyle
                          .copyWith(color: ac.textTertiary),
                    ),
                  ),
                ],
              ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// v1.0.3 宽屏重设计：双列布局。左列（flex 5）：Hero/续刷/横幅/本周战绩；
  /// 右列（flex 4）：统计卡 + 快速操作网格。
  Widget _buildWideBody(AppState appState, AppThemeColors ac) {
    final left = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // v1.27 后台导入：导入中进度卡 / 待预览确认入口（宽屏左列）
              if (appState.importTaskActive) ...[
                _buildImportProgressCard(appState, ac),
                const SizedBox(height: 16),
              ],
              if (!appState.importTaskActive &&
                  appState.previewQuestions.isNotEmpty) ...[
                _buildPreviewConfirmCard(appState, ac),
                const SizedBox(height: 16),
              ],
              _buildHeroCard(appState, ac),
              const SizedBox(height: 16),
              if (_unfinished != null) _buildResumeCard(appState, ac),
              if (appState.vacationModeEnabled) _buildVacationBanner(ac),
              if (_statsLoaded &&
                  appState.aiService != null &&
                  appState.aiService!.cachedBalance != null &&
                  appState.aiService!.cachedBalance! > 0 &&
                  appState.aiService!.cachedBalance! < 1.0)
                _buildBalanceWarning(ac),
              WeeklyStatsBoard(
                dailyTotals: _yearlyTotals,
                streakDays: _streakDays,
                weekTotal: _weekTotal,
                weekAccuracy: _weekAccuracy,
                vacationDays: _vacationDays,
                onHistoryReport: () => _showHistoryReport(appState),
              ),
            ],
          );
    final right = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // v1.27 呼吸感：宽屏右列模块间距同步加大。
              _buildStatsCards(appState, ac),
              const SizedBox(height: 28),
              _buildQuickActions(appState, ac),
              const SizedBox(height: 28),
              Align(
                alignment: Alignment.bottomRight,
                child: Text(
                  '本软件由b站：笨蛋鱼坏蛋猫 开发 | $kAppVersion',
                  style: TextStyle(
                      fontSize: MaoType.caption,
                      color: ac.textSecondary.withOpacity(0.7)),
                ),
              ),
            ],
          );
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth >= 1100) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 5, child: left),
            // v1.27 呼吸感：双列间距加大。
            const SizedBox(width: 28),
            Expanded(flex: 4, child: right),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [left, const SizedBox(height: 16), right],
      );
    });
  }

  /// 顶部问候语（第一行）+ 软件图标/名字 + 今日一言
  Widget _buildHeroCard(AppState appState, AppThemeColors ac) {
    final nickname = appState.settings.nickname;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(MaoSpace.lg),
      decoration: BoxDecoration(
        // 双色位移渐变（非透明度衰减）——避免旧版"发灰发浊"
        gradient: LinearGradient(
          colors: [ac.accent, Color.lerp(ac.accent, ac.textPrimary, 0.28)!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: MaoRadius.cardBorder,
        boxShadow: MaoShadow.level2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 第一行：问候语 + 昵称
          Text(
            _greeting,
            style: MaoType.h1Style.copyWith(color: ac.onAccent),
          ),
          if (nickname.isNotEmpty) ...[
            const SizedBox(height: MaoSpace.xxs / 2),
            Text(
              nickname,
              style: MaoType.captionStyle
                  .copyWith(color: ac.onAccent.withOpacity(0.86)),
            ),
          ],
          const SizedBox(height: MaoSpace.sm),
          // 软件图标 + 软件名字 + 今日一言
          Row(
            children: [
              ClipRRect(
                borderRadius: MaoRadius.smallBorder,
                child: Image.asset(
                  'assets/app_logo.png',
                  width: 42,
                  height: 42,
                  errorBuilder: (_, __, ___) =>
                      Icon(Icons.school, size: 34, color: ac.onAccent),
                ),
              ),
              const SizedBox(width: MaoSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '猫卷',
                      style: MaoType.h3Style.copyWith(color: ac.onAccent),
                    ),
                    const SizedBox(height: MaoSpace.xxs / 2),
                    Text(
                      _hitokoto,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: MaoType.captionStyle.copyWith(
                        color: ac.onAccent.withOpacity(0.9),
                        height: 1.45,
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
    final ac = AppThemeColors.of(context);
    final daily = await appState.getDailyStats(7);
    final acc = await appState.getDailyAccuracy(7);
    final accByDay = <String, Map<String, dynamic>>{
      for (final a in acc) (a['day'] as String): a,
    };
    if (!mounted) return;
    const week = ['一', '二', '三', '四', '五', '六', '日'];
    showModalBottomSheet(
      context: context,
      backgroundColor: ac.background,
      // 平板适配：弹窗限宽居中
      constraints: const BoxConstraints(maxWidth: kSheetMaxWidth),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(MaoRadius.card))),
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
                      color: ac.textSecondary.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(MaoRadius.chip)),
                ),
              ),
              const SizedBox(height: 16),
              Text('历史报告（近 7 天）',
                  style: TextStyle(
                      fontSize: MaoType.h3,
                      fontWeight: FontWeight.bold,
                      color: ac.textPrimary)),
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
                              fontSize: MaoType.body, color: ac.textPrimary),
                        ),
                      ),
                      Text('${d['total']} 题',
                          style: TextStyle(
                              fontSize: MaoType.body,
                              fontWeight: FontWeight.w600,
                              color: (d['total'] as int) > 0
                                  ? ac.accent
                                  : ac.textSecondary)),
                      const Spacer(),
                      Text(
                        _accuracyText(d, accByDay),
                        style: TextStyle(
                            fontSize: MaoType.body, color: ac.textSecondary),
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
  Widget _buildResumeCard(AppState appState, AppThemeColors ac) {
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
        borderRadius: BorderRadius.circular(MaoRadius.control),
        child: InkWell(
          borderRadius: BorderRadius.circular(MaoRadius.control),
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
              borderRadius: BorderRadius.circular(MaoRadius.control),
              // v1.27 呼吸感：续刷卡边框弱化，降低视觉噪音。
              border: Border.all(color: ac.accent.withOpacity(0.35)),
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
                              fontSize: MaoType.h3,
                              color: ac.textPrimary)),
                      const SizedBox(height: 2),
                      Text(
                        '已答 $answered/${session.totalQuestions} 题 · $modeLabel',
                        style: TextStyle(
                            fontSize: MaoType.body, color: ac.textSecondary),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right,
                    size: 20, color: ac.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 寒暑假模式横幅
  Widget _buildVacationBanner(AppThemeColors ac) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: ac.danger.withOpacity(0.1),
        borderRadius: BorderRadius.circular(MaoRadius.small),
        border: Border.all(color: ac.danger.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.beach_access, color: ac.danger, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '寒暑假模式已开启，答题功能暂停，错题本仍可浏览',
              style: TextStyle(fontSize: MaoType.body, color: ac.danger),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceWarning(AppThemeColors ac) {
    // v1.0.2 UI 设计稿：警告色走主题 tertiary（无硬编码色值）
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: ac.accentSoft.withOpacity(0.5),
        borderRadius: BorderRadius.circular(MaoRadius.small),
        border: Border.all(color: ac.accent.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber, color: ac.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'API 余额不足 ¥1，建议尽快充值以免影响使用',
              style: TextStyle(fontSize: MaoType.body, color: ac.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCards(AppState appState, AppThemeColors ac) {
    final stats = appState.homeStats;
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
                ac: ac,
              ),
            ),
            const SizedBox(width: MaoSpace.sm),
            Expanded(
              child: _StatCard(
                icon: Icons.quiz_outlined,
                label: '总刷题量',
                value: '${stats?.totalQuestions ?? 0} 题',
                ac: ac,
              ),
            ),
            const SizedBox(width: MaoSpace.sm),
            Expanded(
              child: _StatCard(
                icon: Icons.trending_up,
                label: '平均正确率',
                value: stats?.formattedAccuracy ?? '0%',
                ac: ac,
              ),
            ),
          ],
        ),
        const SizedBox(height: MaoSpace.xs),
        Text(
          '仅统计按「结束」完成的会话时长，中途退出不计',
          style: MaoType.microStyle.copyWith(color: ac.textTertiary),
        ),
      ],
    );
  }

  /// 快速操作列表（v1.0.2 UI 设计稿：4 项，每项带状态文案与真实路由）
  Widget _buildQuickActions(AppState appState, AppThemeColors ac) {
    final vacation = appState.vacationModeEnabled;
    final ac = AppThemeColors.of(context);
    // v1.0.3 宽屏重设计：四个入口提取为列表，窄屏纵列 / 宽屏 2×2 网格
    final tiles = [
      // 1. 定向爆破
      _QuickActionTile(
        icon: Icons.rocket_launch_rounded,
        label: '定向爆破',
        subtitle: appState.selectedBankIds.isEmpty
            ? '请先选择题库'
            : '已选${appState.selectedBankIds.length}个题库，${appState.selectedQuestionCount >= kQuestionCountAll ? '全部' : '${appState.selectedQuestionCount}题'}',
        iconColor: ac.accent,
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
        onTap: () => _navigateAndRefresh(
            context, appState, const BankManageScreen()),
      ),
      // 3. 错题本 → 错题复习页
      _QuickActionTile(
        icon: Icons.replay_rounded,
        label: '错题本',
        // v1.0.2 UI 审查修复：文案生硬 → 直白说明功能
        subtitle: '智能排期，只显示应复习的错题',
        iconColor: ac.danger,
        onTap: () =>
            _navigateAndRefresh(context, appState, const ErrorBookScreen()),
      ),
      // 4. 导入题库 → 文件导入页（DOCX 走 AI 解析，JSON 直接入库）
      _QuickActionTile(
        icon: Icons.upload_file,
        label: '导入题库',
        subtitle: 'AI 解析 DOCX，JSON 直接入库',
        iconColor: ac.accent,
        onTap: () =>
            _navigateAndRefresh(context, appState, const ImportScreen()),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('快速操作',
            style: TextStyle(
                fontSize: MaoType.h3, fontWeight: FontWeight.bold, color: ac.textPrimary)),
        const SizedBox(height: 12),
        if (isWideLayout(context))
          // v1.0.3 窗口自适应：按最大单元宽自动决定列数（宽窗 2 列，
          // 拖窄时自动回 1 列）
          GridView.extent(
            maxCrossAxisExtent: 340,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 12,
            // v1.27 字号放大：取消固定单元高，纵横比放宽自适应，
            // 副标题多行换行也不溢出。
            childAspectRatio: 2.0,
            children: tiles,
          )
        else
          ...tiles,
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
    final ac = AppThemeColors.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: ac.background,
      // 平板适配：弹窗限宽居中
      constraints: const BoxConstraints(maxWidth: kSheetMaxWidth),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(MaoRadius.card))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: ac.textSecondary.withOpacity(0.3), borderRadius: BorderRadius.circular(MaoRadius.chip)))),
            const SizedBox(height: 20),
            Text('选择刷题数量', style: TextStyle(fontSize: MaoType.h2, fontWeight: FontWeight.bold, color: ac.textPrimary), textAlign: TextAlign.center),
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
            Text('当前: ${appState.selectedQuestionCount >= kQuestionCountAll ? '全部' : '${appState.selectedQuestionCount} 题'}', style: TextStyle(fontSize: MaoType.body, color: ac.textSecondary), textAlign: TextAlign.center),
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
    final ac = AppThemeColors.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: ac.background,
      // 平板适配：弹窗限宽居中
      constraints: const BoxConstraints(maxWidth: kSheetMaxWidth),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(MaoRadius.card)),
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
                    color: ac.textSecondary.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(MaoRadius.chip),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text('选择刷题模式',
                  style: TextStyle(fontSize: MaoType.h2, fontWeight: FontWeight.bold, color: ac.textPrimary),
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text('已选 ${appState.selectedBankIds.length} 个题库，${appState.selectedQuestionCount >= kQuestionCountAll ? '全部' : '${appState.selectedQuestionCount} 题'}/轮',
                  style: TextStyle(fontSize: MaoType.body, color: ac.textSecondary),
                  textAlign: TextAlign.center),
              const SizedBox(height: 20),
              _ModeOption(
                icon: Icons.flash_on_rounded,
                label: '正常刷题',
                desc: '答完即判，立刻校对解析',
                color: ac.accent,
                onTap: () {
                  Navigator.pop(ctx);
                  _startQuiz(appState);
                },
              ),
              const SizedBox(height: 10),
              _ModeOption(
                icon: Icons.edit_square,
                label: '练习',
                desc: '答题卡模式，限时/不限时，统一批改',
                color: ac.textSecondary,
                onTap: () {
                  Navigator.pop(ctx);
                  _startPractice(appState);
                },
              ),
              const SizedBox(height: 10),
              _ModeOption(
                icon: Icons.visibility_rounded,
                label: '背题模式',
                desc: '直接展示答案，快速浏览记忆',
                color: ac.accent,
                onTap: () {
                  Navigator.pop(ctx);
                  _startMemorize(appState);
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _startQuiz(AppState appState) async {
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

  Future<void> _startPractice(AppState appState) async {
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

  Future<void> _startMemorize(AppState appState) async {
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

  /// v1.27 后台导入：首页进度卡（精确进度条 + 当前状态文字）。
  /// 刷题页是 push 路由，首页不可见，天然满足「刷题中不显示」
  Widget _buildImportProgressCard(AppState appState, AppThemeColors ac) {
    final progress = appState.importProgress.clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ac.surfaceAlt,
        borderRadius: BorderRadius.circular(MaoRadius.control),
        border: Border.all(color: ac.accent.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: ac.accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text('正在导入题库，可先去做别的',
                    style: TextStyle(
                        fontSize: MaoType.body,
                        fontWeight: FontWeight.w600,
                        color: ac.textPrimary)),
              ),
              Text('${(progress * 100).toInt()}%',
                  style: TextStyle(
                      fontSize: MaoType.body,
                      fontWeight: FontWeight.w600,
                      color: ac.accent)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(MaoRadius.chip),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 6),
          Text(appState.importStatus,
              style: TextStyle(fontSize: MaoType.body, color: ac.textSecondary)),
        ],
      ),
    );
  }

  /// v1.27 后台导入：AI 解析完成、待预览确认入口（确认入库或放弃前常驻）
  Widget _buildPreviewConfirmCard(AppState appState, AppThemeColors ac) {
    final ac = AppThemeColors.of(context);
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ImportPreviewScreen()),
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: ac.accent.withOpacity(0.08),
          borderRadius: BorderRadius.circular(MaoRadius.control),
          border: Border.all(color: ac.accent.withOpacity(0.5)),
        ),
        child: Row(
          children: [
            Icon(Icons.fact_check_outlined, color: ac.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('已解析 ${appState.previewQuestions.length} 道题，待确认',
                      style: TextStyle(
                          fontSize: MaoType.body,
                          fontWeight: FontWeight.w600,
                          color: ac.accent)),
                  const SizedBox(height: 2),
                  Text('点击查看预览，确认后入库',
                      style:
                          TextStyle(fontSize: MaoType.body, color: ac.textSecondary)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: ac.accent),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final AppThemeColors ac;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.ac,
  });

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: MaoSpace.xs, vertical: MaoSpace.sm + 2),
      decoration: BoxDecoration(
        color: ac.background,
        borderRadius: MaoRadius.controlBorder,
        border: Border.all(color: ac.border, width: MaoShadow.hairline),
      ),
      child: Column(
        children: [
          Icon(icon, color: ac.accent, size: 24),
          const SizedBox(height: MaoSpace.xs),
          AnimatedSwitcher(
            duration: MaoMotion.normal,
            transitionBuilder: (child, animation) =>
                FadeTransition(opacity: animation, child: child),
            child: Text(value,
                key: ValueKey(value),
                textAlign: TextAlign.center,
                style: MaoType.h3Style.copyWith(color: ac.textPrimary)),
          ),
          const SizedBox(height: MaoSpace.xxs),
          Text(label,
              textAlign: TextAlign.center,
              style: MaoType.microStyle.copyWith(color: ac.textTertiary)),
        ],
      ),
    );
  }
}

/// 快速操作列表项（图标 + 标题 + 状态副标题 + 跳转）
class _QuickActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color iconColor;
  final VoidCallback onTap;

  const _QuickActionTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: MaoSpace.sm - 2),
      child: Material(
        color: ac.background,
        borderRadius: MaoRadius.controlBorder,
        child: InkWell(
          borderRadius: MaoRadius.controlBorder,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: MaoSpace.md, vertical: MaoSpace.sm + 2),
            decoration: BoxDecoration(
              borderRadius: MaoRadius.controlBorder,
              border: Border.all(color: ac.border, width: MaoShadow.hairline),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.12),
                    borderRadius: MaoRadius.smallBorder,
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                const SizedBox(width: MaoSpace.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: MaoType.h3Style.copyWith(
                              color: ac.textPrimary, fontSize: MaoType.h3)),
                      const SizedBox(height: MaoSpace.xxs / 2),
                      Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: MaoType.captionStyle
                              .copyWith(color: ac.textSecondary)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: ac.textTertiary, size: 20),
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
  final VoidCallback onTap;

  const _ModeOption({
    required this.icon,
    required this.label,
    required this.desc,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: ac.surfaceAlt,
          borderRadius: BorderRadius.circular(MaoRadius.control),
          border: Border.all(color: ac.border),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(MaoRadius.small),
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
                              fontSize: MaoType.h3,
                              color: ac.textPrimary)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(desc,
                      style: TextStyle(fontSize: MaoType.body, color: ac.textSecondary)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: ac.textSecondary, size: 20),
          ],
        ),
      ),
    );
  }
}

