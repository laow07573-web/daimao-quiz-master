import '../utils/design_tokens.dart';
import 'package:flutter/material.dart';
import '../services/theme_service.dart';
import '../utils/app_constants.dart';
import 'monthly_calendar.dart';

/// 首页本周战绩卡片（v1.0.2 UI 设计稿）
///
/// - 标题「本周战绩」：强调色竖条 + 加粗标题
/// - 双数据块：「本周刷题 X 道」/「平均正确率 X%」
/// - 下方集成单月打卡日历（左右滑动切换月份，今天高亮，热力色阶按刷题量）
/// - 底部「连续打卡 X 周」
/// - 「历史报告」入口保留（近 7 天每日刷题明细）
/// 全部配色走主题 AppThemeColors / ColorScheme，无硬编码色值
class WeeklyStatsBoard extends StatefulWidget {
  const WeeklyStatsBoard({
    super.key,
    required this.dailyTotals, // key: 'YYYY-MM-DD' -> 刷题数
    required this.streakDays,
    required this.weekTotal,
    required this.weekAccuracy,
    this.vacationDays = const {},
    this.onHistoryReport,
  });

  final Map<String, int> dailyTotals;
  final int streakDays;
  final int weekTotal;
  final double weekAccuracy;
  final Set<String> vacationDays;
  final VoidCallback? onHistoryReport;

  @override
  State<WeeklyStatsBoard> createState() => _WeeklyStatsBoardState();
}

class _WeeklyStatsBoardState extends State<WeeklyStatsBoard> {
  // v1.0.2 统一重构：单月日历左右滑动（初始页 = 当前月，前后 200 年可翻）
  late final PageController _monthController;

  @override
  void initState() {
    super.initState();
    _monthController = PageController(initialPage: 12 * kYearPageSpan);
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

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ac.card,
        borderRadius: BorderRadius.circular(MaoRadius.card),
        border: Border.all(color: ac.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行：4px 强调色竖条 + 本周战绩
          Row(
            children: [
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  color: ac.accent,
                  borderRadius: BorderRadius.circular(MaoRadius.chip),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '本周战绩',
                style: TextStyle(
                  fontSize: MaoType.h2,
                  fontWeight: FontWeight.bold,
                  color: ac.textPrimary,
                ),
              ),
              const Spacer(),
              if (widget.onHistoryReport != null)
                InkWell(
                  borderRadius: BorderRadius.circular(MaoRadius.chip),
                  onTap: widget.onHistoryReport,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Row(
                      children: [
                        Icon(Icons.history, size: 15, color: ac.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          '历史报告',
                          style: TextStyle(
                              fontSize: MaoType.body, color: ac.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          // 双数据块：本周刷题 / 平均正确率
          Row(
            children: [
              _StatBlock(
                label: '本周刷题',
                value: '${widget.weekTotal}',
                suffix: ' 道',
                accent: ac.accent,
                ac: ac,
              ),
              const SizedBox(width: 12),
              _StatBlock(
                label: '平均正确率',
                value: widget.weekAccuracy.toStringAsFixed(0),
                suffix: '%',
                accent: ac.accent,
                ac: ac,
              ),
            ],
          ),
          const SizedBox(height: 14),
          // v1.0.2 统一重构：单月打卡日历支持左右滑动切换月份
          // （PageView 无限翻页，初始页 = 当前月）
          _buildSwipeableMonth(context, now, todayKey),
          const SizedBox(height: 10),
          // 底部：连续打卡（v1.0.2 修复：≥7 天折算 "X 周 Y 天"，不足一周显示天数）
          Row(
            children: [
              Icon(Icons.local_fire_department, size: 16, color: ac.accent),
              const SizedBox(width: 6),
              Text(
                streakDays >= 7
                    ? '连续打卡 ${streakDays ~/ 7} 周 ${streakDays % 7} 天'
                    : '连续打卡 $streakDays 天',
                style: TextStyle(
                    fontSize: MaoType.body,
                    fontWeight: FontWeight.w600,
                    color: ac.textPrimary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 左右滑动切换月份的单月日历（绝对月索引 = year*12 + month-1）
  Widget _buildSwipeableMonth(BuildContext context, DateTime now, String todayKey) {
    final ac = AppThemeColors.of(context);
    final initialAbs = now.year * 12 + (now.month - 1);
    const initialPage = 12 * kYearPageSpan; // 大初始页：前后 200 年范围可翻
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final cellH = (w / 7 / 0.95).clamp(0.0, 56.0);
        final height = 6 * cellH + 30; // 30 = 月份标题 + 间距
        return SizedBox(
          height: height,
          child: PageView.builder(
            controller: _monthController,
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
                heatColors: [
                  ac.cardBorder, // 空
                  ac.accent.withOpacity(0.18), // 少 <50
                  ac.accent.withOpacity(0.4), // 达标 50~199
                  ac.accent.withOpacity(0.65), // 多 200+
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
    required this.accent,
    required this.ac,
  });

  final String label;
  final String value;
  final String suffix;
  final Color accent;
  final AppThemeColors ac;

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: accent.withOpacity(0.07),
          borderRadius: BorderRadius.circular(MaoRadius.small),
        ),
        child: Column(
          children: [
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: value,
                    style: TextStyle(
                      fontSize: MaoType.display,
                      fontWeight: FontWeight.bold,
                      color: accent,
                    ),
                  ),
                  TextSpan(
                    text: suffix,
                    style: TextStyle(fontSize: MaoType.body, color: ac.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: MaoType.caption, color: ac.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
