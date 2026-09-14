import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../models/quiz_session.dart';
import '../services/hitokoto_service.dart';
import '../services/theme_service.dart';
import '../utils/design_tokens.dart';
import '../utils/format_utils.dart';
import '../utils/responsive.dart';
import '../widgets/kit/mj_kit.dart';
import '../widgets/kit/mj_logo.dart';
import '../widgets/weekly_stats_board.dart';
import 'import_preview_screen.dart';
import 'quiz_screen.dart';
import 'settings_hub_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// 用于测量「战绩卡以上固定块」的真实高度：首页要恰好一屏不滚动，
  /// 就必须知道固定块实际占了多少，才能把准确剩余高度交给战绩卡。
  final GlobalKey _fixedBlockKey = GlobalKey();
  double _fixedBlockHeight = 0;

  /// 上次已加载的统计数据版本号：AppState 每次变更统计口径都会自增，
  /// 首页据此自动重载「本周战绩」等本地统计（它们不在 AppState 里）。
  int _loadedStatsRevision = -1;
  // v1.0.2: 战绩数据（本周刷题/连续打卡/年度热力）
  Map<String, int> _yearlyTotals = {};
  Set<String> _vacationDays = {};
  int _streakDays = 0;
  int _weekTotal = 0;
  double _weekAccuracy = 0;
  bool _statsLoaded = false; // 防横幅首帧闪现

  /// 断点续刷：最新未完成会话 + 已答题数。
  /// 首页是用户回来看见的第一个屏幕，「上次刷到一半」的续刷入口必须在这里，
  /// 不能只在「开始」页（那里是主动去做题时才会进）。
  (QuizSession, int)? _unfinished;

    // v1.0.2 扩展：今日一言（开页面显示）。
    // v1.27 PC 加载修复：首帧直接显示缓存/本地一言，不再显示「正在加载一言...」，
    // 网络结果到达后静默替换；失败也不回退占位文案。
    String _hitokoto = HitokotoService.immediateText();

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
      // 续刷卡与统计同批加载：答题结束后 statsRevision 自增会触发本方法，
      // 于是「完成/暂停一轮」回到首页时续刷入口自动出现或消失。
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

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    return Scaffold(
      backgroundColor: ac.background,
      appBar: AppBar(
        title: const Text('猫卷'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '刷新',
            onPressed: () async {
              final appState = context.read<AppState>();
              await appState.init();
              await _loadWeeklyData(appState);
              await _loadHitokoto();
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsHubScreen()),
            ),
          ),
        ],
      ),
      // 首页 = 「看」的一屏：问候（含累计数据）/ 待办提示 / 本周战绩 / 累计数据。
      //
      // 一屏策略（既「恰好铺满」又「绝不溢出」）：
      //   1. 布局后测量固定块真实高度 _fixedBlockHeight；
      //   2. 战绩卡高度 = 视口 − 固定块 − 间距，并夹在 [最小可用, 上限]；
      //   3. 外层 SingleChildScrollView 兜底：空间足够时内容正好等于视口
      //      （不滚动），空间不足（小屏/横屏/大字号）时内容略高，可滚动看全，
      //      而不是挤压内部元素触发 overflow。
      body: Consumer<AppState>(
        builder: (context, appState, _) {
          _measureFixedBlock();
          // 统计口径变化（答题结束 / 导入删除题库 / 改判 / 生成模拟数据…）
          // 就重载本地统计 —— 这是首页数据能自动跟上的关键。
          if (appState.statsRevision != _loadedStatsRevision) {
            _loadedStatsRevision = appState.statsRevision;
            _loadWeeklyData(appState);
          }
          return SafeArea(
            child: LayoutBuilder(
              builder: (context, c) {
                const pad = MaoSpace.md;
                final viewport = c.maxHeight - pad * 2;
                // 首帧尚未测量时给一个偏大的保守估算（宁可先多滚动一点）
                final fixed = _fixedBlockHeight > 0 ? _fixedBlockHeight : 260.0;
                // 交给战绩卡的可用高度；它内部会保证不低于「日历可读」的最小高度，
                // 不足时由外层滚动兜底 —— 因此既不溢出、也不把日历压扁。
                final cardAvail = viewport - fixed - MaoSpace.sm;

                return SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(pad),
                  child: ResponsivePage(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 固定块：问候卡（含累计数据）+ 续刷入口 + 待办提示。
                        // 续刷放在待办之前：它是"接着上次继续做"的第一顺位动作。
                        Column(
                          key: _fixedBlockKey,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildHeroCard(appState, ac),
                            if (_unfinished != null) ...[
                              const SizedBox(height: MaoSpace.sm),
                              MJResumeCard(
                                session: _unfinished!.$1,
                                answered: _unfinished!.$2,
                                onTap: () => _resumeQuiz(appState),
                              ),
                            ],
                            const SizedBox(height: MaoSpace.sm),
                            ..._buildNotices(appState, ac),
                          ],
                        ),
                        // 战绩卡：拿到「可用高度」，内部据此决定是填满还是保底
                        WeeklyStatsBoard(
                          dailyTotals: _yearlyTotals,
                          streakDays: _streakDays,
                          weekTotal: _weekTotal,
                          weekAccuracy: _weekAccuracy,
                          vacationDays: _vacationDays,
                          maxHeight: cardAvail,
                          onHistoryReport: () => _showHistoryReport(appState),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  /// 布局后测量固定块高度；变化时才 setState（避免无谓重建）。
  void _measureFixedBlock() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _fixedBlockKey.currentContext;
      if (ctx == null || !mounted) return;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      final h = box.size.height;
      if ((h - _fixedBlockHeight).abs() > 0.5) {
        setState(() => _fixedBlockHeight = h);
      }
    });
  }

  /// 待办提示聚合：有内容才占位，无内容零高度。
  /// 首页不再放动作入口，但「需要用户知道的事」仍在此提示。
  List<Widget> _buildNotices(AppState appState, AppThemeColors ac) {
    final list = <Widget>[];
    if (appState.vacationModeEnabled) {
      list.add(_buildVacationBanner(ac));
    }
    if (_statsLoaded &&
        appState.aiService != null &&
        appState.aiService!.cachedBalance != null &&
        appState.aiService!.cachedBalance! > 0 &&
        appState.aiService!.cachedBalance! < 1.0) {
      list.add(_buildBalanceWarning(ac));
    }
    if (appState.importTaskActive) {
      list.add(_buildImportProgressCard(appState, ac));
    } else if (appState.previewQuestions.isNotEmpty) {
      list.add(_buildPreviewConfirmCard(appState, ac));
    }
    if (list.isEmpty) return const [];
    return [
      for (final w in list) ...[w, const SizedBox(height: MaoSpace.sm)],
    ];
  }

  Widget _buildHeroCard(AppState appState, AppThemeColors ac) {
    final nickname = appState.settings.nickname;
    // 精密暗色：Hero 不再用大渐变块，改为平坦面板 + 发丝描边 + 左侧强调条。
    // 视觉重量交给排版（大字号问候语）而不是色块。
    return MJSurface(
      accentEdge: true,
      padding: const EdgeInsets.fromLTRB(
          MaoSpace.md, MaoSpace.md, MaoSpace.md, MaoSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_greeting,
                        style: MaoType.h1Style.copyWith(color: ac.textPrimary)),
                    if (nickname.isNotEmpty) ...[
                      const SizedBox(height: MaoSpace.xxs),
                      Text(nickname,
                          style: MaoType.captionStyle
                              .copyWith(color: ac.textSecondary)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: MaoSpace.sm),
              // 品牌位：矢量标记（34px 下位图字标完全糊掉，标记仍然清晰）
              const MJLogoBadge(box: 34),
            ],
          ),
          const SizedBox(height: MaoSpace.sm),
          Container(height: MaoLine.width, color: ac.border),
          const SizedBox(height: MaoSpace.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('猫卷',
                  style: MaoType.microStyle.copyWith(
                      color: ac.textSecondary, fontWeight: FontWeight.w600)),
              const SizedBox(width: MaoSpace.xs),
              Expanded(
                child: Text(
                  _hitokoto,
                  // 一行：一屏布局下省下的每一行都直接变成日历可用高度
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MaoType.captionStyle
                      .copyWith(color: ac.textTertiary, height: 1.45),
                ),
              ),
            ],
          ),
          const SizedBox(height: MaoSpace.sm),
          Container(height: MaoLine.width, color: ac.border),
          const SizedBox(height: MaoSpace.sm),
          // 累计数据并入问候卡：一屏布局下省掉一张独立卡片的高度
          _buildInlineStats(appState, ac),
        ],
      ),
    );
  }

  /// 累计数据（时长 / 题量 / 正确率）：三格横向，发丝竖线分隔。
  /// 数值用等宽数字，保证三格数位对齐。
  Widget _buildInlineStats(AppState appState, AppThemeColors ac) {
    final stats = appState.homeStats;
    // 三格并排，宽度有限：时长值天生最长（'4天23时'），
    // 因此值一律用紧凑格式（fmtDurationCompact），标签也取最简写法，
    // 避免 '累计刷题时长 / 4 天 23 小时' 这类长文本被截断成 "累计刷题…"。
    // 每格 flex 按内容长度分配：时长格稍宽。
    final items = <(IconData, String, String, int)>[
      (
        Icons.timer_outlined,
        '刷题时长',
        fmtDurationCompact(stats?.totalDurationSeconds ?? 0),
        5
      ),
      (
        Icons.quiz_outlined,
        '总题量',
        '${stats?.totalQuestions ?? 0}',
        4
      ),
      (
        Icons.trending_up,
        '正确率',
        stats?.formattedAccuracy ?? '0.0%',
        4
      ),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0)
            Container(
              width: MaoLine.width,
              height: 30,
              margin: const EdgeInsets.symmetric(horizontal: MaoSpace.xs),
              color: ac.border,
            ),
          Expanded(
            flex: items[i].$4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(items[i].$1, size: 12, color: ac.textTertiary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(items[i].$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: MaoType.microStyle
                              .copyWith(color: ac.textTertiary)),
                    ),
                  ],
                ),
                const SizedBox(height: MaoSpace.xs - 2),
                // 数值不设 ellipsis：宁可缩小也不截断（FittedBox 兜底）
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(items[i].$3,
                      maxLines: 1,
                      style: MaoType.number(MaoType.h3,
                              weight: FontWeight.w700)
                          .copyWith(color: ac.textPrimary)),
                ),
              ],
            ),
          ),
        ],
      ],
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

  /// 断点续刷：恢复未完成会话并进入答题页。
  /// 寒暑假模式暂停答题（与「开始」页一致），此时给提示而不是静默失败。
  Future<void> _resumeQuiz(AppState appState) async {
    if (appState.vacationModeEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('寒暑假模式中，答题功能已暂停')),
      );
      return;
    }
    final ok = await appState.resumeUnfinishedSession();
    if (!ok || !mounted) return;
    final nav = Navigator.of(context);
    await nav.push(
      MaterialPageRoute(builder: (_) => const QuizScreen()),
    );
    // 回来后重算：续刷可能已完成该会话，卡片要随之消失
    if (!mounted) return;
    await _loadWeeklyData(appState);
  }

  /// v1.0.2 七项改进：断点续刷卡片（最新未完成会话）
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

  /// 路由占位：跳转页面并返回后刷新战绩
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

