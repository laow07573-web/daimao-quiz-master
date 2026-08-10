import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/quiz_session.dart';
import '../services/app_state.dart';
import '../widgets/trend_chart.dart';
import '../widgets/year_heatmap.dart';
import 'error_book_screen.dart';
import 'session_detail_screen.dart';

/// 统计页（v1.0.2）6 大板块：
/// 总览 / 年度坚持 / 近30天趋势 / 正确率排行 / 错题统计 / 历史记录
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
  // v1.0.2 对齐里程碑：隐藏/恢复今日记录
  int _hiddenTodayCount = 0;

  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  /// 供 MainShell 切 Tab 时调用
  Future<void> refresh() async {
    await _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final appState = context.read<AppState>();
      final yearly = await appState.getYearlyTotals();
      final trend = await appState.getTrendData();
      final periodStats = await appState.getPeriodStats(_period);
      final longestStreak = await appState.getPeriodLongestStreak(_period);
      // 周期切换防竞态
      if (!mounted) return;
      setState(() {
        _yearlyTotals = yearly;
        _vacationDays = {
          for (final d in appState.vacationDateRange)
            '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}'
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
    final appState = context.read<AppState>();
    final banks = await appState.getBankAccuracies();
    final kps = await appState.getAccuracyByKnowledgePoint();
    final errors = await appState.getErrorBookStats();
    final sessions = await appState.getRecentSessions(10);
    final hidden = await appState.getHiddenTodayRecordCount();
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
      _kpAccuracy = kps;
      _errorStats = errors;
      _recentSessions = sessions;
      _hiddenTodayCount = hidden;
    });
  }

  /// v1.0.2 对齐里程碑：隐藏今日答题记录（确认说明）
  Future<void> _hideToday() async {
    final appState = context.read<AppState>();
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('隐藏今日记录'),
        // v1.0.2 对齐里程碑：将今日答题记录暂时隐藏（可恢复），今日将显示为未刷题。
        content: const Text('将今日答题记录暂时隐藏（可恢复），今日将显示为未刷题。\n将同步更新本次统计、错题本和复习计划。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('隐藏')),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    final hidden = await appState.hideTodayRecords();
    if (!mounted) return;
    await _loadAll();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(hidden > 0 ? '已隐藏 $hidden 条今日记录' : '今日暂无答题记录'),
        backgroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }

  /// v1.0.2 对齐里程碑：恢复被隐藏的今日记录
  Future<void> _restoreToday() async {
    final appState = context.read<AppState>();
    await appState.restoreTodayRecords();
    if (!mounted) return;
    await _loadAll();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('统计')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(error: _error!, onRetry: _loadAll)
              : RefreshIndicator(
                  onRefresh: _loadAll,
                  child: ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      _buildOverview(context),
                      const SizedBox(height: 14),
                      _SectionCard(
                        title: '年度坚持',
                        child: YearHeatmap(
                          dailyTotals: _yearlyTotals,
                          vacationDays: _vacationDays,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _SectionCard(
                        title: '近 30 天趋势',
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
                      // v1.0.2 对齐里程碑：恢复被隐藏的今日记录
                      if (_hiddenTodayCount > 0)
                        _SectionCard(
                          title: '今日记录',
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '已隐藏 $_hiddenTodayCount 条今日记录，可通过下方按钮恢复',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: cs.onSurfaceVariant),
                                ),
                              ),
                              TextButton(
                                onPressed: _restoreToday,
                                child: const Text('恢复今日刷题记录',
                                    style: TextStyle(fontSize: 12)),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 14),
                      _SectionCard(
                        title: '历史记录',
                        trailing: TextButton(
                          onPressed: _hideToday,
                          child: const Text('隐藏今日记录',
                              style: TextStyle(fontSize: 12)),
                        ),
                        child: _HistorySection(sessions: _recentSessions),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
    );
  }

  Widget _buildOverview(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _SectionCard(
      title: '总览',
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
              color: cs.primary,
            ),
          ),
          Expanded(
            child: _OverviewStat(
              label: '正确率',
              value: _periodAccuracy.toStringAsFixed(1),
              suffix: '%',
              color: cs.primary,
            ),
          ),
          Expanded(
            child: _OverviewStat(
              label: '学习时长',
              value: _formatDuration(_periodDuration),
              color: cs.secondary,
            ),
          ),
          Expanded(
            child: _OverviewStat(
              label: '最长连击',
              value: '$_longestStreak',
              suffix: ' 天',
              color: cs.error,
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
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (value, label) in _options)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => onChanged(value),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: current == value
                      ? cs.primary.withOpacity(0.15)
                      : Colors.transparent,
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: current == value ? cs.primary : cs.onSurfaceVariant,
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
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(
          value + suffix,
          style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.bold, color: color),
        ),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                ),
              ),
              const Spacer(),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
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
    final cs = Theme.of(context).colorScheme;
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
            child: Text('暂无数据',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
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
                          TextStyle(fontSize: 12, color: cs.onSurface),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accuracyTierColor(
                          (item['accuracy'] as num?)?.toDouble() ?? 0, cs),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${(item['accuracy'] as num?)?.toStringAsFixed(1) ?? '0.0'}%',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface),
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
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: active ? cs.primary.withOpacity(0.15) : Colors.transparent,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: active ? cs.primary : cs.onSurfaceVariant,
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
    final cs = Theme.of(context).colorScheme;
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
                color: cs.error,
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
                color: cs.tertiary,
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
        Text('按题库分布', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        const SizedBox(height: 6),
        if (stats.isEmpty)
          Text('暂无错题', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))
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
                      style: TextStyle(fontSize: 12, color: cs.onSurface),
                    ),
                  ),
                  Text(
                    '到期 ${s['due_count'] ?? 0} · 收藏 ${s['bookmark_count'] ?? 0}',
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
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
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: color.withOpacity(0.1),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color)),
            Text(label,
                style:
                    TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

/// 历史记录：最近 10 次会话
class _HistorySection extends StatelessWidget {
  const _HistorySection({required this.sessions});

  final List<QuizSession> sessions;

  String _modeLabel(String mode) {
    switch (mode) {
      case 'kp_review':
        return '知识点复习';
      case 'error_review':
        return '错题重刷';
      case 'mixed':
        return '混合题库';
      case 'single':
        return '全部题库';
      case 'practice':
        return '练习模式';
      case 'memorize':
        return '背题模式';
      default:
        return '全部题库';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (sessions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text('暂无刷题记录',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        ),
      );
    }
    return Column(
      children: [
        for (final s in sessions)
          InkWell(
            borderRadius: BorderRadius.circular(8),
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
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface),
                        ),
                        Text(
                          _formatTime(s.startTime),
                          style: TextStyle(
                              fontSize: 11, color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${s.totalQuestions} 题 · ${s.accuracy.toStringAsFixed(0)}%',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right,
                      size: 16, color: cs.onSurfaceVariant),
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
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: cs.error, size: 40),
          const SizedBox(height: 10),
          Text('加载失败', style: TextStyle(color: cs.onSurface)),
          const SizedBox(height: 4),
          Text(error,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          const SizedBox(height: 10),
          FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}
