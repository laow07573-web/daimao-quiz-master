import 'package:flutter/material.dart';
import 'year_heatmap.dart';

/// 首页本周战绩（v1.0.2）
///
/// 顶部：本周战绩标题 + 本周刷题数 + 连续打卡天数
/// 主体：月历分页（PageView，每页 3 个月）+ 热力色阶 + 寒暑假标注 + 图例
class WeeklyStatsBoard extends StatefulWidget {
  const WeeklyStatsBoard({
    super.key,
    required this.dailyTotals, // key: 'YYYY-MM-DD' -> 刷题数
    required this.streakDays,
    required this.weekTotal,
    this.vacationDays = const {},
  });

  final Map<String, int> dailyTotals;
  final int streakDays;
  final int weekTotal;
  final Set<String> vacationDays;

  @override
  State<WeeklyStatsBoard> createState() => _WeeklyStatsBoardState();
}

class _WeeklyStatsBoardState extends State<WeeklyStatsBoard> {
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
                '本周战绩',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                ),
              ),
              const Spacer(),
              _MiniStat(label: '本周刷题', value: '${widget.weekTotal} 题'),
              const SizedBox(width: 12),
              _MiniStat(label: '连续打卡', value: '${widget.streakDays} 天'),
            ],
          ),
          const SizedBox(height: 10),
          YearHeatmap(
            dailyTotals: widget.dailyTotals,
            vacationDays: widget.vacationDays,
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
        Text(value,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: cs.primary)),
      ],
    );
  }
}
