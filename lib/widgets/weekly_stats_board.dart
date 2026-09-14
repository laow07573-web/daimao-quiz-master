import 'dart:math' as math;

import '../utils/design_tokens.dart';
import 'package:flutter/material.dart';
import '../services/theme_service.dart';
import '../utils/app_constants.dart';
import 'kit/mj_kit.dart';
import 'monthly_calendar.dart';

/// 首页本周战绩卡片（Mao Des 2.0 · 精密暗色）
///
/// - 标题「本周战绩」：MJSectionHeader（细强调条 + 标题）+ 右侧「历史报告」入口
/// - 双数据块：「本周刷题 X 道」/「平均正确率 X%」，等宽数字
/// - 单月打卡日历（左右滑动切换月份，今天高亮，热力色阶按刷题量）
/// - 底部「连续打卡 X 周 Y 天」
///
/// 视觉要点：整卡是发丝描边面板；数据块用次级面色而非强调色淡底，
/// 让强调色只出现在真正需要的地方（标题条 / 热力格 / 连续打卡）。
class WeeklyStatsBoard extends StatefulWidget {
  const WeeklyStatsBoard({
    super.key,
    required this.dailyTotals, // key: 'YYYY-MM-DD' -> 刷题数
    required this.streakDays,
    required this.weekTotal,
    required this.weekAccuracy,
    this.vacationDays = const {},
    this.onHistoryReport,
    this.maxHeight,
  });

  final Map<String, int> dailyTotals;
  final int streakDays;
  final int weekTotal;
  final double weekAccuracy;
  final Set<String> vacationDays;
  final VoidCallback? onHistoryReport;

  /// 可用高度预算（首页一屏布局下传入）。有值时卡片会据此选择日历行数，
  /// 优先保证「完整可见」；为 null（如统计页复用）时按月份实际行数渲染。
  final double? maxHeight;

  @override
  State<WeeklyStatsBoard> createState() => _WeeklyStatsBoardState();

  /// 日历格子高度下限。低于此值日期数字会被裁切，因此空间不足时
  /// 宁可让卡片变高（外层滚动兜底），也不压缩日历。
  static const double minCellHeight = 24;

  /// 日历格子高度上限（避免大屏上日历过度膨胀）
  static const double maxCellHeight = 44;

  /// 卡片内「除日历外」的固定部分高度（标题 + 数据块 + 连续打卡 + 内边距）。
  /// 取保守上界：估算偏大只会让卡片略高（多滚动几像素），偏小则会溢出。
  /// 卡片内「除日历外」的固定部分高度（标题 + 数据块 + 连续打卡 + 内边距）。
  /// 仅用于计算「最小可读高度」下限；精确布局由 Expanded 承担，
  /// 因此这个估算即使偏差也不会造成 overflow。
  static const double _fixedPartHeight = 150;

  /// 该行数下卡片的最小可用高度（日历按可读下限计算）。
  static double minHeightFor(int rows) =>
      _fixedPartHeight + MonthCalendar.chromeHeight + rows * minCellHeight;

  /// 该行数下卡片的最大有意义高度（日历按上限计算）。
  ///
  /// 超过这个高度，多出来的空间日历也用不上（格子已到上限），
  /// 只会让卡片在宽屏/平板上被拉成一大块空白 —— 故选高度时以此封顶。
  static double maxUsefulHeightFor(int rows) =>
      _fixedPartHeight + MonthCalendar.chromeHeight + rows * maxCellHeight;
}

class _WeeklyStatsBoardState extends State<WeeklyStatsBoard> {
  // v1.0.2 统一重构：单月日历左右滑动（初始页 = 当前月，前后 200 年可翻）
  late final PageController _monthController;

  /// 当前显示月份需要的行数（4~6）。翻月时随之更新，
  /// 让卡片高度贴合内容——5 行的月份不会在底部留一整行空白。
  int _visibleRows = 6;

  @override
  void initState() {
    super.initState();
    _monthController = PageController(initialPage: 12 * kYearPageSpan);
    final now = DateTime.now();
    _visibleRows = MonthCalendar.rowCountFor(now.year, now.month);
  }

  @override
  void dispose() {
    _monthController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    final now = DateTime.now();
    final todayKey = MonthCalendar.dateKeyOf(now);
    final streakDays = widget.streakDays;

    // 先定卡片高度：
    //   · 外层给的空间够 → 用外层空间（恰好填满，首页因此一屏）
    //   · 不够 → 用「最小可读高度」，超出部分由外层滚动兜底
    //     （而不是把日历格子压到看不清，或硬撑导致 overflow）
    final rows = MonthCalendar.rowCountFor(now.year, now.month);
    final needRows = _visibleRows > rows ? _visibleRows : rows;
    final minH = WeeklyStatsBoard.minHeightFor(needRows);
    final maxUseful = WeeklyStatsBoard.maxUsefulHeightFor(needRows);
    final avail = widget.maxHeight;
    // 高度选择：够用就填满（首页一屏），但不超过「日历能用上的最大高度」，
    // 否则宽屏/平板上卡片会被拉出大片空白（实测平板下曾撑到 1000px）。
    final cardH = (avail == null || !avail.isFinite || avail < minH)
        ? minH
        : math.min(avail, maxUseful);

    return SizedBox(
      height: cardH,
      child: MJSurface(
      padding: const EdgeInsets.all(MaoSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题行：区块头 + 历史报告入口（小号单色，不做按钮感）
          Align(
            alignment: Alignment.centerLeft,
            child: MJSectionHeader(
            title: '本周战绩',
            trailing: widget.onHistoryReport == null
                ? null
                : InkWell(
                    borderRadius: MaoRadius.chipBorder,
                    onTap: widget.onHistoryReport,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 4),
                      child: Row(
                        children: [
                          Icon(Icons.history,
                              size: 14, color: ac.textSecondary),
                          const SizedBox(width: 4),
                          Text('历史报告',
                              style: MaoType.captionStyle
                                  .copyWith(color: ac.textSecondary)),
                        ],
                      ),
                    ),
                  ),
            ),
          ),
          const SizedBox(height: MaoSpace.xs),
          // 紧凑指标行：本周刷题 / 平均正确率 的数值与标签同排。
          // （原先两个大块占约 78dp，是「一屏装不下」的主因之一）
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              _InlineMetric(
                value: '${widget.weekTotal}',
                suffix: ' 道',
                label: '本周刷题',
                ac: ac,
              ),
              Container(
                width: MaoLine.width,
                height: 14,
                margin: const EdgeInsets.symmetric(horizontal: MaoSpace.sm),
                color: ac.border,
              ),
              _InlineMetric(
                value: widget.weekAccuracy.toStringAsFixed(0),
                suffix: '%',
                label: '平均正确率',
                ac: ac,
              ),
            ],
          ),
          const SizedBox(height: MaoSpace.sm),
          // 日历区用 Expanded 吃掉「卡片高度 − 固定部分实际高度」的精确余量：
          // 不依赖任何估算，因此既不溢出、也不留空。
          Expanded(
            // 居中：日历高度按「行数×格子 + chrome 估算」得出，
            // 估算的余量表现为上下均匀留白，视觉更稳。
            child: Center(
              child: _buildSwipeableMonth(context, now, todayKey),
            ),
          ),
          const SizedBox(height: MaoSpace.sm),
          // 底部：连续打卡（v1.0.2 修复：≥7 天折算 "X 周 Y 天"，不足一周显示天数）
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.local_fire_department, size: 15, color: ac.accent),
              const SizedBox(width: MaoSpace.xs - 2),
              Text(
                streakDays >= 7
                    ? '连续打卡 ${streakDays ~/ 7} 周 ${streakDays % 7} 天'
                    : '连续打卡 $streakDays 天',
                style: MaoType.h3Style.copyWith(
                    fontWeight: FontWeight.w600, color: ac.textPrimary),
              ),
            ],
          ),
        ],
      ),
      ),
    );
  }

  /// 左右滑动切换月份的单月日历（绝对月索引 = year*12 + month-1）。
  ///
  /// 高度由父级给定（首页一屏布局下是「卡内剩余高度」），
  /// 再按「行数 + chrome」反推每格高度——所以日历总是不多不少地铺满。
  Widget _buildSwipeableMonth(
      BuildContext context, DateTime now, String todayKey) {
    final ac = AppThemeColors.of(context);
    final initialAbs = now.year * 12 + (now.month - 1);
    const initialPage = 12 * kYearPageSpan; // 大初始页：前后 200 年范围可翻
    return LayoutBuilder(
      builder: (context, constraints) {
        // 格子高度由「被给到的实际高度」反推；夹在可读区间内。
        // 卡片高度已由 build 保证 >= 最小可读高度，所以这里通常不会触到下限；
        // 万一触到（外层约束异常小），仍用 min 兜底避免超出 → 不产生 overflow。
        final maxH = constraints.maxHeight;
        final availH = maxH - MonthCalendar.chromeHeight;
        final cellH = (availH / _visibleRows)
            .clamp(WeeklyStatsBoard.minCellHeight, WeeklyStatsBoard.maxCellHeight);
        final wantH = _visibleRows * cellH + MonthCalendar.chromeHeight;
        return SizedBox(
          height: wantH > maxH ? maxH : wantH,
          child: PageView.builder(
            controller: _monthController,
            onPageChanged: (page) {
              final abs = initialAbs + (page - initialPage);
              final y = abs ~/ 12;
              final m = abs % 12 + 1;
              final r = MonthCalendar.rowCountFor(y, m);
              if (r != _visibleRows) setState(() => _visibleRows = r);
            },
            itemBuilder: (context, page) {
              final abs = initialAbs + (page - initialPage);
              final year = abs ~/ 12;
              final month = abs % 12 + 1;
              return MonthCalendar(
                year: year,
                month: month,
                dailyTotals: widget.dailyTotals,
                vacationDays: widget.vacationDays,
                todayKey: todayKey,
                cellHeight: cellH,
                rows: _visibleRows,
                heatColors: [
                  Colors.transparent, // 空：不铺底（精密化的关键）
                  ac.accent.withOpacity(0.22), // 少 <50
                  ac.accent.withOpacity(0.46), // 达标 50~199
                  ac.accent.withOpacity(0.78), // 多 200+
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _StatBlock extends StatelessWidget {
  const _StatBlock({
    required this.label,
    required this.value,
    required this.suffix,
    required this.ac,
  });

  final String label;
  final String value;
  final String suffix;
  final AppThemeColors ac;

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: MaoSpace.sm, vertical: MaoSpace.sm),
        decoration: BoxDecoration(
          color: ac.surfaceAlt,
          borderRadius: MaoRadius.controlBorder,
          border: Border.all(color: ac.border, width: MaoLine.width),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MaoNumber(value,
                size: MaoType.display,
                weight: FontWeight.w700,
                color: ac.textPrimary,
                suffix: suffix),
            const SizedBox(height: MaoSpace.xxs),
            Text(label,
                style: MaoType.captionStyle.copyWith(color: ac.textSecondary)),
          ],
        ),
      ),
    );
  }
}


/// 紧凑指标：数值（等宽）+ 单位 + 灰色标签同排，高度远小于独立数据块。
class _InlineMetric extends StatelessWidget {
  const _InlineMetric({
    required this.value,
    required this.suffix,
    required this.label,
    required this.ac,
  });

  final String value;
  final String suffix;
  final String label;
  final AppThemeColors ac;

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        MaoNumber(value,
            size: MaoType.h1,
            weight: FontWeight.w700,
            color: ac.textPrimary,
            suffix: suffix),
        const SizedBox(width: MaoSpace.xs - 2),
        Text(label,
            style: MaoType.microStyle.copyWith(color: ac.textTertiary)),
      ],
    );
  }
}
