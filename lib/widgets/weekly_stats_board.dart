import 'package:flutter/material.dart';
import '../services/theme_service.dart';
import 'monthly_calendar.dart';

/// 首页本周战绩卡片（v1.0.2 UI 设计稿）
///
/// - 标题「本周战绩」：强调色竖条 + 加粗标题
/// - 双数据块：「本周刷题 X 道」/「平均正确率 X%」
/// - 下方集成单月打卡日历（当前月，今天高亮，热力色阶按刷题量）
/// - 底部「连续打卡 X 周」
/// - 「历史报告」入口保留（近 7 天每日刷题明细）
/// 全部配色走主题 AppThemeColors / ColorScheme，无硬编码色值
class WeeklyStatsBoard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final todayKey = MonthCalendar.dateKeyOf(now);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ac.card,
        borderRadius: BorderRadius.circular(16),
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
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '本周战绩',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                ),
              ),
              const Spacer(),
              if (onHistoryReport != null)
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: onHistoryReport,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Row(
                      children: [
                        Icon(Icons.history, size: 15, color: cs.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          '历史报告',
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant),
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
                value: '$weekTotal',
                suffix: ' 道',
                accent: ac.accent,
                cs: cs,
              ),
              const SizedBox(width: 12),
              _StatBlock(
                label: '平均正确率',
                value: weekAccuracy.toStringAsFixed(0),
                suffix: '%',
                accent: ac.accent,
                cs: cs,
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 单月打卡日历（当前月，今天高亮）
          MonthCalendar(
            year: now.year,
            month: now.month,
            dailyTotals: dailyTotals,
            vacationDays: vacationDays,
            todayKey: todayKey,
            heatColors: [
              ac.cardBorder, // 空
              ac.accent.withOpacity(0.18), // 少 <50
              ac.accent.withOpacity(0.4), // 达标 50~199
              ac.accent.withOpacity(0.65), // 多 200+
            ],
          ),
          const SizedBox(height: 10),
          // 底部：连续打卡（周）
          Row(
            children: [
              Icon(Icons.local_fire_department, size: 16, color: ac.accent),
              const SizedBox(width: 6),
              Text(
                '连续打卡 ${streakDays ~/ 7} 周',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface),
              ),
              const Spacer(),
              Text(
                streakDays > 0 ? '累计 $streakDays 天' : '',
                style:
                    TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatBlock extends StatelessWidget {
  const _StatBlock({
    required this.label,
    required this.value,
    required this.suffix,
    required this.accent,
    required this.cs,
  });

  final String label;
  final String value;
  final String suffix;
  final Color accent;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: accent.withOpacity(0.07),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: value,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: accent,
                    ),
                  ),
                  TextSpan(
                    text: suffix,
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
