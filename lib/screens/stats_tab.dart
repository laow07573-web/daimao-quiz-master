import '../utils/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/quiz_session.dart';
import '../services/app_state.dart';
import '../utils/app_constants.dart';
import '../services/theme_service.dart';
import '../utils/format_utils.dart';
import '../utils/responsive.dart';
import '../widgets/monthly_calendar.dart';
import '../widgets/trend_chart.dart';
import 'error_book_screen.dart';
import 'session_detail_screen.dart';

/// 统计页（v1.0.2 UI 设计稿）：
/// 统计概览（本周/本月/全部 + 四指标）/ 年度坚持（3 月横排日历 + 图例）/
/// 近30天趋势（双 Y 轴）/ 正确率排行 / 错题统计 / 历史记录
class StatsTab extends StatefulWidget {
  const StatsTab({super.key});

  @override
  State<StatsTab> createState() => StatsTabState();
}

class StatsTabState extends State<StatsTab> {
  String _period = 'week';

  Map<String, int> _yearlyTotals = {};
  Set<String> _vacationDays = {};
  List<Map<String, dynamic>> _trendData = [];

  int _periodQuestions = 0;
  double _periodAccuracy = 0;
  int _periodDuration = 0;
  int _longestStreak = 0;

  List<Map<String, dynamic>> _bankAccuracy = [];
  List<Map<String, dynamic>> _kpAccuracy = [];
  List<Map<String, dynamic>> _errorStats = [];
  List<QuizSession> _recentSessions = [];
  // v1.0.2 七项改进：历史会话关联的题库名（session_banks）
  Map<int, List<String>> _sessionBankNames = {};

  bool _loading = true;
  String? _error;

  /// v1.28 年度坚持：三个月一页（季度页，初始当前季度）
  late final PageController _quarterController;
  int _quarterPage = 4 * kYearPageSpan; // 大初始页：前后 200 年范围可翻

  @override
  void initState() {
    super.initState();
    _quarterController = PageController(initialPage: _quarterPage);
    _quarterController.addListener(() {
      final p = _quarterController.page?.round();
      if (p != null && p != _quarterPage && mounted) {
        setState(() => _quarterPage = p);
      }
    });
    _loadAll();
  }

  @override
  void dispose() {
    _quarterController.dispose();
    super.dispose();
  }

  /// 供 MainShell 切 Tab 时调用
  /// v1.0.2 修复：排行/历史/错题统计一并重载（此前只加载一次永不刷新）
  Future<void> refresh() async {
    await _loadAll();
    await _loadRankings();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final appState = context.read<AppState>();
      final yearly = await appState.getYearlyTotals();
      final trend = await appState.getTrendData(days: 365);
      final periodStats = await appState.getPeriodStats(_period);
      final longestStreak = await appState.getPeriodLongestStreak(_period);
      // 周期切换防竞态
      if (!mounted) return;
      setState(() {
        _yearlyTotals = yearly;
        _vacationDays = {
          for (final d in appState.vacationDateRange) dateKeyOf(d)
        };
        _trendData = trend;
        _periodQuestions = periodStats.totalQuestions;
        _periodAccuracy = periodStats.accuracy;
        _periodDuration = periodStats.totalDurationSeconds;
        _longestStreak = longestStreak;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _switchPeriod(String period) async {
    if (_period == period) return;
    setState(() => _period = period);
    try {
      final appState = context.read<AppState>();
      final periodStats = await appState.getPeriodStats(period);
      final longestStreak = await appState.getPeriodLongestStreak(period);
      // 防竞态：切走后的结果丢弃
      if (!mounted || _period != period) return;
      setState(() {
        _periodQuestions = periodStats.totalQuestions;
        _periodAccuracy = periodStats.accuracy;
        _periodDuration = periodStats.totalDurationSeconds;
        _longestStreak = longestStreak;
      });
    } catch (_) {
      // 静默
    }
  }

  Future<void> _loadRankings() async {
    try {
      final appState = context.read<AppState>();
      final banks = await appState.getBankAccuracies();
      final kps = await appState.getAccuracyByKnowledgePoint();
      final errors = await appState.getErrorBookStats();
      final sessions = await appState.getRecentSessions(10);
      // v1.0.2 七项改进：会话关联题库名（历史副标题）
      final bankNames = <int, List<String>>{};
      for (final s in sessions) {
        if (s.id != null) {
          bankNames[s.id!] = await appState.getSessionBankNames(s.id!);
        }
      }
      if (!mounted) return;
      setState(() {
        _bankAccuracy = banks
            .map((b) => {
                  'name': b.bankName,
                  'total': b.total,
                  'correct': b.correct,
                  'accuracy': b.accuracy,
                })
            .toList();
        // v1.0.2 修复：按知识点排行键名归一（UI 读 name/accuracy），
        // 缺失知识点兜底「未打标签」，total=0 不除零
        _kpAccuracy = kps
            .map((k) {
              final total = (k['total'] as num?) ?? 0;
              final correct = (k['correct'] as num?) ?? 0;
              return {
                'name': (k['name'] as String?)?.trim().isNotEmpty ?? false
                    ? k['name'] as String
                    : '未打标签',
                'total': total,
                'correct': correct,
                'accuracy': total > 0 ? correct / total * 100 : 0.0,
              };
            })
            .toList();
        _errorStats = errors;
        _recentSessions = sessions;
        _sessionBankNames = bankNames;
      });
    } catch (_) {
      // 排行加载失败不影响主统计展示
    }
  }

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('统计'),
        // v1.0.2 UI 设计稿：右侧刷新图标（预留刷新数据方法）
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await _loadAll();
              await _loadRankings();
            },
          ),
        ],
      ),
      // 平板适配：内容限宽居中（手机无影响）；
      // v1.0.3 宽屏重设计：宽屏限宽自动提升至 1080 + 区块双列并排
      body: ResponsivePage(
        child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(error: _error!, onRetry: _loadAll)
              : RefreshIndicator(
                  onRefresh: _loadAll,
                  child: ListView(
                    padding: const EdgeInsets.all(14),
                    children: isWideLayout(context)
                        ? _buildWideSections(ac)
                        : [
                      _buildOverview(context),
                      const SizedBox(height: 14),
                      _SectionCard(
                        title: '年度坚持',
                        trailing: _QuarterNav(controller: _quarterController),
                        child: _buildQuarterCalendar(ac),
                      ),
                      const SizedBox(height: 14),
                      _SectionCard(
                        title: '近一年趋势',
                        child: TrendChart(days: _trendData),
                      ),
                      const SizedBox(height: 14),
                      _SectionCard(
                        title: '正确率排行',
                        child: _AccuracyRanking(
                          banks: _bankAccuracy,
                          kps: _kpAccuracy,
                          onLoaded: _loadRankings,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _SectionCard(
                        title: '错题统计',
                        child: _ErrorStatsSection(
                          stats: _errorStats,
                          onLoaded: _loadRankings,
                        ),
                      ),
                      const SizedBox(height: 14),
                      // v1.0.2 七项改进：隐藏/恢复今日记录入口已移入开发者模式
                      _SectionCard(
                        title: '历史记录',
                        child: _HistorySection(
                            sessions: _recentSessions,
                            bankNames: _sessionBankNames),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
      ),
    );
  }

  /// 宽屏并排时「年度坚持」卡片的目标高度。
  /// 按「日历最大高度（约 6×50+34）+ 图例 + 卡片内边距」估算，
  /// 与「近一年趋势」并排时视觉等高（趋势卡内容不足时会被拉伸填满）。
  static const double _quarterCardHeight = 388;

  /// v1.0.3 宽屏重设计：总览全宽；年度坚持/趋势、排行/错题统计两两并排；
  /// 历史记录全宽。窄屏维持原单列（见 build）。
  /// v1.0.3 窗口自适应：并排区块改用 AdaptivePair，窗口拖窄时自动上下堆叠。
  List<Widget> _buildWideSections(AppThemeColors ac) {
    return [
      _buildOverview(context),
      const SizedBox(height: 14),
      // v1.28：并排时两卡片等高（用户反馈要求与趋势卡持平）。
      // 趋势图内容高度固定（图表 200 + 翻页条/图例），据此给年度坚持卡
      // 相同的目标高度，两张卡视觉持平。
      AdaptivePair(
        equalHeight: true,
        targetHeight: _quarterCardHeight,
        first: _SectionCard(
          title: '年度坚持',
          fillHeight: true,
          trailing: _QuarterNav(controller: _quarterController),
          child: _buildQuarterCalendar(ac),
        ),
        second: _SectionCard(
          title: '近一年趋势',
          fillHeight: true,
          child: TrendChart(days: _trendData),
        ),
      ),
      const SizedBox(height: 14),
      AdaptivePair(
        first: _SectionCard(
          title: '正确率排行',
          child: _AccuracyRanking(
            banks: _bankAccuracy,
            kps: _kpAccuracy,
            onLoaded: _loadRankings,
          ),
        ),
        second: _SectionCard(
          title: '错题统计',
          child: _ErrorStatsSection(
            stats: _errorStats,
            onLoaded: _loadRankings,
          ),
        ),
      ),
      const SizedBox(height: 14),
      _SectionCard(
        title: '历史记录',
        child: _HistorySection(
            sessions: _recentSessions, bankNames: _sessionBankNames),
      ),
      const SizedBox(height: 20),
    ];
  }

  /// 年度坚持 = 三个月一页（季度页，初始当前季度）
  ///
  /// v1.28 二次修订：用户反馈改用年度热力图后"太丑"，更喜欢原来的样式。
  /// 故恢复「3 个月横排 + 季度翻页」，仅做两处改进：
  ///   1. 格子放大（月份卡可用宽更大时自动变大，上限提高）
  ///   2. 宽屏并排时与「近一年趋势」卡片等高（见 _buildWideSections 的 IntrinsicHeight）
  Widget _buildQuarterCalendar(AppThemeColors ac) {
    final now = DateTime.now();
    final todayKey = MonthCalendar.dateKeyOf(now);
    // 绝对季度索引 = year*4 + (month-1)~/3
    final initialAbsQuarter = now.year * 4 + (now.month - 1) ~/ 3;
    // v1.28：翻页页数从状态读取（宽屏等高布局下也保持一致）
    final initialPage = _quarterPage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth / 3; // 单月宽
            // v1.28 放大：格子上限 56 → 64，让格子尽量大（旧版手机上偏小）
            final cellH = (w / 7 / 0.98).clamp(0.0, 64.0);
            var height = 6 * cellH + 34; // 34 = 月份标题 + 间距
            // 宽屏等高场景：可用高度受限时收缩日历，避免溢出
            if (constraints.hasBoundedHeight) {
              height = height.clamp(0.0, constraints.maxHeight);
            }
            return SizedBox(
              height: height,
              child: PageView.builder(
                controller: _quarterController,
                itemBuilder: (context, page) {
                  final absQ = initialAbsQuarter + (page - initialPage);
                  final year = absQ ~/ 4;
                  final q = absQ % 4;
                  final baseMonth = q * 3 + 1;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var m = 0; m < 3; m++) ...[
                        if (m > 0) const SizedBox(width: MaoSpace.xs),
                        Expanded(
                          child: MonthCalendar(
                            year: year,
                            month: baseMonth + m,
                            dailyTotals: _yearlyTotals,
                            vacationDays: _vacationDays,
                            todayKey: todayKey,
                            heatColors: [
                              ac.border,
                              ac.accent.withOpacity(0.28),
                              ac.accent.withOpacity(0.52),
                              ac.accent.withOpacity(0.85),
                            ],
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            );
          },
        ),
        const SizedBox(height: MaoSpace.xs + 2),
        // 图例：少/达标/多/今天
        Row(
          children: [
            _LegendItem(color: _heatColor(10, ac), label: '少'),
            _LegendItem(color: _heatColor(80, ac), label: '达标'),
            _LegendItem(color: _heatColor(250, ac), label: '多'),
            const SizedBox(width: MaoSpace.xs),
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                border: Border.all(color: ac.accent, width: 1.5),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: MaoSpace.xxs),
            Text('今天',
                style: MaoType.microStyle.copyWith(color: ac.textTertiary)),
          ],
        ),
      ],
    );
  }

  Color _heatColor(int total, AppThemeColors ac) {
    if (total <= 0) return ac.cardBorder;
    if (total < 50) return ac.accent.withOpacity(0.18);
    if (total < 200) return ac.accent.withOpacity(0.4);
    return ac.accent.withOpacity(0.65);
  }
  Widget _buildOverview(BuildContext context) {
    final ac = AppThemeColors.of(context);
    // v1.0.2 UI 设计稿：统计概览（标签栏切换 本周/本月/全部 + 四指标）
    return _SectionCard(
      title: '统计概览',
      trailing: _PeriodChips(
        current: _period,
        onChanged: _switchPeriod,
      ),
      child: Row(
        children: [
          Expanded(
            child: _OverviewStat(
              label: '刷题量',
              value: '$_periodQuestions',
              color: ac.accent,
            ),
          ),
          Expanded(
            child: _OverviewStat(
              label: '正确率',
              value: _periodAccuracy.toStringAsFixed(1),
              suffix: '%',
              color: ac.accent,
            ),
          ),
          Expanded(
            child: _OverviewStat(
              label: '学习时长',
              value: _formatDuration(_periodDuration),
              color: ac.textSecondary,
            ),
          ),
          Expanded(
            child: _OverviewStat(
              label: '最长连击',
              value: '$_longestStreak',
              suffix: ' 天',
              color: ac.danger,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (hours > 0) return '${hours}h${minutes}m';
    if (minutes > 0) return '${minutes}m';
    return '${seconds}s';
  }
}

class _PeriodChips extends StatelessWidget {
  const _PeriodChips({required this.current, required this.onChanged});

  final String current;
  final ValueChanged<String> onChanged;

  static const _options = [
    ('week', '本周'),
    ('month', '本月'),
    ('all', '全部'),
  ];

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (value, label) in _options)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: InkWell(
              borderRadius: BorderRadius.circular(MaoRadius.control),
              onTap: () => onChanged(value),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(MaoRadius.control),
                  color: current == value
                      ? ac.accent.withOpacity(0.15)
                      : Colors.transparent,
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: MaoType.body,
                    color: current == value ? ac.accent : ac.textSecondary,
                    fontWeight:
                        current == value ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _OverviewStat extends StatelessWidget {
  const _OverviewStat({
    required this.label,
    required this.value,
    this.suffix = '',
    required this.color,
  });

  final String label;
  final String value;
  final String suffix;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    return Column(
      children: [
        Text(
          value + suffix,
          style: TextStyle(
              fontSize: MaoType.h3, fontWeight: FontWeight.bold, color: color),
        ),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(fontSize: MaoType.caption, color: ac.textSecondary)),
      ],
    );
  }
}

/// 热力图例条目（少/达标/多）
class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(MaoRadius.chip),
          ),
        ),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(fontSize: MaoType.caption, color: ac.textSecondary)),
        const SizedBox(width: 8),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
    this.trailing,
    this.fillHeight = false,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  /// v1.28：并排等高时置 true —— 内容区用 Expanded 撑满卡片高度，
  /// 使相邻两张卡片视觉持平（配合 AdaptivePair.equalHeight）。
  /// 单列场景保持 false（高度由内容决定，避免无界高度下 Expanded 报错）。
  final bool fillHeight;

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: fillHeight ? MainAxisSize.max : MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: MaoType.body,
                fontWeight: FontWeight.bold,
                color: ac.textPrimary,
              ),
            ),
            const Spacer(),
            if (trailing != null) trailing!,
          ],
        ),
        const SizedBox(height: MaoSpace.sm),
        // v1.28：不用 flex（单列/堆叠时高度无界会报错）。
        // 等高通过 AdaptivePair 给两侧统一的固定高度实现。
        child,
      ],
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ac.surfaceAlt.withOpacity(0.5),
        borderRadius: BorderRadius.circular(MaoRadius.control),
      ),
      child: content,
    );
  }
}

/// 正确率排行：按题库 + 按知识点（懒加载）
class _AccuracyRanking extends StatefulWidget {
  const _AccuracyRanking({
    required this.banks,
    required this.kps,
    required this.onLoaded,
  });

  final List<Map<String, dynamic>> banks;
  final List<Map<String, dynamic>> kps;
  final Future<void> Function() onLoaded;

  @override
  State<_AccuracyRanking> createState() => _AccuracyRankingState();
}

class _AccuracyRankingState extends State<_AccuracyRanking> {
  bool _byBank = true;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      widget.onLoaded();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    final data = _byBank ? widget.banks : widget.kps;
    return Column(
      children: [
        Row(
          children: [
            _SegBtn(
              label: '按题库',
              active: _byBank,
              onTap: () => setState(() => _byBank = true),
            ),
            const SizedBox(width: 8),
            _SegBtn(
              label: '按知识点',
              active: !_byBank,
              onTap: () => setState(() => _byBank = false),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (data.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            // v1.0.2 UI 设计稿：空状态提示
            child: Text('暂无数据，刷几道题后再来看看',
                style: TextStyle(color: ac.textSecondary, fontSize: MaoType.caption)),
          )
        else
          for (final item in data.take(8))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${item['name']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: MaoType.body, color: ac.textPrimary),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accuracyTierColor(
                          (item['accuracy'] as num?)?.toDouble() ?? 0,
                          AppThemeColors.of(context)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${(item['accuracy'] as num?)?.toStringAsFixed(1) ?? '0.0'}%',
                    style: TextStyle(
                        fontSize: MaoType.body,
                        fontWeight: FontWeight.w600,
                        color: ac.textPrimary),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

class _SegBtn extends StatelessWidget {
  const _SegBtn({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(MaoRadius.control),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(MaoRadius.control),
          color: active ? ac.accent.withOpacity(0.15) : Colors.transparent,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: MaoType.body,
            color: active ? ac.accent : ac.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// 错题统计：总数/待复习卡片 + 按题库分布
class _ErrorStatsSection extends StatelessWidget {
  const _ErrorStatsSection({required this.stats, required this.onLoaded});

  final List<Map<String, dynamic>> stats;
  final Future<void> Function() onLoaded;

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    final totalCount =
        stats.fold<int>(0, (sum, s) => sum + ((s['all_count'] as int?) ?? 0));
    final dueCount =
        stats.fold<int>(0, (sum, s) => sum + ((s['due_count'] as int?) ?? 0));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _ErrorCard(
                label: '错题总数',
                value: '$totalCount',
                color: ac.danger,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ErrorBookScreen(initialFilter: 'all'),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ErrorCard(
                label: '待复习',
                value: '$dueCount',
                color: ac.accent,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ErrorBookScreen(initialFilter: 'wrong'),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text('按题库分布', style: TextStyle(fontSize: MaoType.body, color: ac.textSecondary)),
        const SizedBox(height: 6),
        if (stats.isEmpty)
          // v1.0.2 UI 设计稿：空状态「0题错题总数」
          Text('0题错题总数', style: TextStyle(fontSize: MaoType.body, color: ac.textSecondary))
        else
          for (final s in stats.take(5))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${s['bank_name']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: MaoType.body, color: ac.textPrimary),
                    ),
                  ),
                  Text(
                    '到期 ${s['due_count'] ?? 0} · 收藏 ${s['bookmark_count'] ?? 0}'
                    // v1.0.2 FSRS 可见化：该题库最早到期卡
                    '${s['next_due_at'] != null ? ' · 下次到期：${relativeDayLabel(DateTime.parse(s['next_due_at'] as String))}' : ''}',
                    style: TextStyle(fontSize: MaoType.caption, color: ac.textSecondary),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({
    required this.label,
    required this.value,
    required this.color,
    required this.onTap,
  });

  final String label;
  final String value;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(MaoRadius.small),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(MaoRadius.small),
          color: color.withOpacity(0.1),
        ),
        child: Column(
          children: [
            // v1.0.2 UI 设计稿：数值带单位（0题错题总数 / 0题待复习）
            Text('$value 题',
                style: TextStyle(
                    fontSize: MaoType.h2,
                    fontWeight: FontWeight.bold,
                    color: color)),
            Text(label,
                style:
                    TextStyle(fontSize: MaoType.caption, color: ac.textSecondary)),
          ],
        ),
      ),
    );
  }
}

/// 历史记录：最近 10 次会话
class _HistorySection extends StatelessWidget {
  const _HistorySection({required this.sessions, required this.bankNames});

  final List<QuizSession> sessions;
  // v1.0.2 七项改进：session_id → 关联题库名
  final Map<int, List<String>> bankNames;

  String _modeLabel(String mode) {
    switch (mode) {
      case 'kp_review':
        return '知识点复习';
      case 'error_review':
        return '错题重刷';
      case 'mixed':
        return '混合题库';
      case 'single':
        // v1.0.2 修复：单题库模式不再误标为「全部题库」
        return '单题库';
      case 'practice':
        return '练习模式';
      case 'memorize':
        return '背题模式';
      case 'simulation':
        return '模拟数据';
      default:
        return '全部题库';
    }
  }

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    if (sessions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          // v1.0.2 UI 设计稿：空状态提示
          child: Text('暂无练习记录',
              style: TextStyle(fontSize: MaoType.body, color: ac.textSecondary)),
        ),
      );
    }
    return Column(
      children: [
        for (final s in sessions)
          InkWell(
            borderRadius: BorderRadius.circular(MaoRadius.small),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SessionDetailScreen(session: s),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _modeLabel(s.mode),
                          style: TextStyle(
                              fontSize: MaoType.body,
                              fontWeight: FontWeight.w600,
                              color: ac.textPrimary),
                        ),
                        // v1.0.2 七项改进：会话关联题库名副标题
                        if (s.id != null &&
                            (bankNames[s.id]?.isNotEmpty ?? false))
                          Text(
                            (() {
                              final names = bankNames[s.id]!;
                              return names.take(2).join('、') +
                                  (names.length > 2 ? ' 等${names.length}个' : '');
                            })(),
                            style: TextStyle(
                                fontSize: MaoType.caption, color: ac.textSecondary),
                          ),
                        Text(
                          // v1.0.2 修复：未完成会话（异常退出遗留）加标识
                          s.endTime == null || s.endTime!.isEmpty
                              ? '${_formatTime(s.startTime)} · 未完成'
                              : _formatTime(s.startTime),
                          style: TextStyle(
                              fontSize: MaoType.caption, color: ac.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${s.totalQuestions} 题 · ${s.accuracy.toStringAsFixed(0)}%',
                    style: TextStyle(fontSize: MaoType.body, color: ac.textSecondary),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right,
                      size: 16, color: ac.textSecondary),
                ],
              ),
            ),
          ),
      ],
    );
  }

  String _formatTime(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: ac.danger, size: 40),
          const SizedBox(height: 10),
          Text('加载失败', style: TextStyle(color: ac.textPrimary)),
          const SizedBox(height: 4),
          Text(error,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: MaoType.caption, color: ac.textSecondary)),
          const SizedBox(height: 10),
          FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

/// v1.0.3 历史数据可查：年度坚持季度翻页箭头。
/// PageView 范围极大（前后 200 年），不做边界禁用。

/// 季度翻页控件（年度坚持卡片右上角）
class _QuarterNav extends StatelessWidget {
  const _QuarterNav({required this.controller});

  final PageController controller;

  void _go(int delta) {
    final cur = (controller.page ?? 0).round();
    controller.animateToPage(cur + delta,
        duration: MaoMotion.normal, curve: MaoMotion.standard);
  }

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          tooltip: '上一季度',
          icon: Icon(Icons.chevron_left_rounded, size: 20, color: ac.accent),
          onPressed: () => _go(-1),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          tooltip: '下一季度',
          icon: Icon(Icons.chevron_right_rounded, size: 20, color: ac.accent),
          onPressed: () => _go(1),
        ),
      ],
    );
  }
}
