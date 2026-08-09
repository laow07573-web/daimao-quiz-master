import 'package:flutter/material.dart';

/// 年度坚持月历（v1.0.2）
///
/// 每页 3 个月历并排（Row + Expanded ×3），共 4 页覆盖 1-12 月。
/// 每列 GridView.count(7 列) 42 格（前导空白 + 天数 + 尾部补空），
/// 高度预算：monthTitleH(24) + 6 × 格高，LayoutBuilder 按实际宽度计算。
/// 热力色阶与首页一致：0=空 / <50=少(0.2) / 50~199=达标(0.4) / 200+=多(0.65)
/// 今天：primary 1.5 边框 + 加粗；寒暑假：cs.error 深红
/// 图例单行（少50 → 多200 + 今天）
class YearHeatmap extends StatefulWidget {
  const YearHeatmap({
    super.key,
    required this.dailyTotals, // key: 'YYYY-MM-DD' -> 刷题数
    this.vacationDays = const {}, // 假期日期 key 集合
    this.onMonthPageChanged,
  });

  final Map<String, int> dailyTotals;
  final Set<String> vacationDays;
  final ValueChanged<int>? onMonthPageChanged;

  /// 热力色阶（首页/统计页统一口径）
  static Color heatColor(int total, ColorScheme cs) {
    if (total <= 0) return cs.surfaceContainerHighest.withOpacity(0.55);
    if (total < 50) return cs.primary.withOpacity(0.2);
    if (total < 200) return cs.primary.withOpacity(0.4);
    return cs.primary.withOpacity(0.65);
  }

  @override
  State<YearHeatmap> createState() => _YearHeatmapState();
}

class _YearHeatmapState extends State<YearHeatmap> {
  static const int _pageCount = 4;
  late final PageController _controller;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _page = ((now.month - 1) ~/ 3).clamp(0, _pageCount - 1);
    _controller = PageController(initialPage: _page);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final todayKey = _dateKey(now);

    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final monthWidth = (constraints.maxWidth - 8) / 3;
            final cellWidth = (monthWidth - 2 * 6) / 7;
            final cellHeight = cellWidth * 1.05;
            final height = 24 + 6 * cellHeight + 4;
            return SizedBox(
              height: height,
              child: PageView.builder(
                controller: _controller,
                itemCount: _pageCount,
                onPageChanged: (p) {
                  setState(() => _page = p);
                  widget.onMonthPageChanged?.call(p);
                },
                itemBuilder: (context, page) {
                  final baseMonth = page * 3 + 1;
                  return Row(
                    children: [
                      for (var i = 0; i < 3; i++)
                        Expanded(
                          child: _MonthCalendar(
                            month: baseMonth + i,
                            year: now.year,
                            cellWidth: cellWidth,
                            cellHeight: cellHeight,
                            dailyTotals: widget.dailyTotals,
                            vacationDays: widget.vacationDays,
                            todayKey: todayKey,
                            colorScheme: cs,
                          ),
                        ),
                    ],
                  );
                },
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        // 页码指示器 + 图例
        Row(
          children: [
            for (var i = 0; i < _pageCount; i++)
              Container(
                width: 8,
                height: 4,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: i == _page ? cs.primary : cs.outlineVariant,
                ),
              ),
            const Spacer(),
            _LegendItem(color: YearHeatmap.heatColor(25, cs), label: '少'),
            _LegendItem(color: YearHeatmap.heatColor(100, cs), label: '达标'),
            _LegendItem(color: YearHeatmap.heatColor(300, cs), label: '多'),
            const SizedBox(width: 6),
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                border: Border.all(color: cs.primary, width: 1.5),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 2),
            Text('今天', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ],
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 2),
        Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        const SizedBox(width: 6),
      ],
    );
  }
}

/// 单个月历（42 格：前导空白 + 天数 + 尾部补空）
class _MonthCalendar extends StatelessWidget {
  const _MonthCalendar({
    required this.month,
    required this.year,
    required this.cellWidth,
    required this.cellHeight,
    required this.dailyTotals,
    required this.vacationDays,
    required this.todayKey,
    required this.colorScheme,
  });

  final int month;
  final int year;
  final double cellWidth;
  final double cellHeight;
  final Map<String, int> dailyTotals;
  final Set<String> vacationDays;
  final String todayKey;
  final ColorScheme colorScheme;

  String _dateKey(int day) =>
      '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final firstWeekday = DateTime(year, month, 1).weekday; // 1=周一
    final leading = firstWeekday - 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 24,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              '$month月',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        SizedBox(
          height: 6 * cellHeight,
          width: double.infinity,
          child: GridView.count(
            crossAxisCount: 7,
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: cellWidth / cellHeight,
            children: [
              for (var i = 0; i < 42; i++)
                _buildCell(i - leading + 1, daysInMonth, cs),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCell(int day, int daysInMonth, ColorScheme cs) {
    if (day < 1 || day > daysInMonth) {
      // 未来日期格保留 margin（防列错位）
      return const SizedBox.shrink();
    }
    final key = _dateKey(day);
    final total = dailyTotals[key] ?? 0;
    final isToday = key == todayKey;
    final isVacation = vacationDays.contains(key);
    final color = isVacation
        ? cs.error.withOpacity(0.55)
        : YearHeatmap.heatColor(total, cs);

    return Container(
      margin: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
        border: isToday
            ? Border.all(color: cs.primary, width: 1.5)
            : null,
      ),
      alignment: Alignment.center,
      child: Text(
        '$day',
        style: TextStyle(
          fontSize: 10,
          color: isToday ? cs.primary : cs.onSurfaceVariant,
          fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}
