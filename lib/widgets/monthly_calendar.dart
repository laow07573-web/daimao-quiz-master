import 'package:flutter/material.dart';

/// 单月打卡日历（v1.0.2 UI 设计稿）
///
/// 42 格网格（前导空白 + 天数 + 尾部补空），每格热力色阶按当日刷题量：
/// 0=空 / <50=少 / 50~199=达标 / 200+=多（可自定义四级色阶 [heatColors]）。
/// 今天：高亮边框 + 加粗；假期：主题 error 淡色置灰。
/// 供首页「本周战绩」卡片与统计页「年度坚持」3 月横排共用。
class MonthCalendar extends StatelessWidget {
  const MonthCalendar({
    super.key,
    required this.year,
    required this.month,
    required this.dailyTotals, // key: 'YYYY-MM-DD' -> 刷题数
    this.vacationDays = const {},
    this.todayKey,
    this.highlightToday = true,
    this.heatColors, // 自定义四级色阶（空/少/达标/多），默认主题色阶梯
    this.onDayTap, // 点击某天（可选）
  });

  final int year;
  final int month;
  final Map<String, int> dailyTotals;
  final Set<String> vacationDays;
  final String? todayKey;
  final bool highlightToday;
  final List<Color>? heatColors;
  final ValueChanged<int>? onDayTap;

  static String dateKeyOf(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// 热力色阶（与首页/统计页统一口径）
  static Color heatColor(int total, ColorScheme cs) {
    if (total <= 0) return cs.surfaceContainerHighest.withOpacity(0.55);
    // v1.0.2 UI 审查修复：加深色阶（0.2/0.4/0.65 → 0.28/0.52/0.85），
    // 浅色主题下「少/达标/多」区分度不足
    if (total < 50) return cs.primary.withOpacity(0.28);
    if (total < 200) return cs.primary.withOpacity(0.52);
    return cs.primary.withOpacity(0.85);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final firstWeekday = DateTime(year, month, 1).weekday; // 1=周一
    final leading = firstWeekday - 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            children: [
              Text('$month月',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('$year年',
                  style: TextStyle(
                      fontSize: 10, color: cs.onSurfaceVariant)),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // v1.0.2 适配性：格高随屏宽自适应，但限制上限（宽屏/横屏不溢出）
        LayoutBuilder(
          builder: (context, constraints) {
            final cellW = constraints.maxWidth / 7;
            final cellH = (cellW / 0.95).clamp(0.0, 56.0);
            return SizedBox(
              height: 6 * cellH,
              child: GridView.count(
                crossAxisCount: 7,
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: cellW / cellH,
                children: [
                  for (var i = 0; i < 42; i++)
                    _buildCell(i - leading + 1, daysInMonth, cs),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildCell(int day, int daysInMonth, ColorScheme cs) {
    if (day < 1 || day > daysInMonth) {
      return const SizedBox.shrink();
    }
    final key = MonthCalendar.dateKeyOf(DateTime(year, month, day));
    final total = dailyTotals[key] ?? 0;
    final isToday = todayKey != null && key == todayKey;
    final isVacation = vacationDays.contains(key);
    final color = isVacation ? cs.error.withOpacity(0.55) : _heat(total, cs);

    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: onDayTap == null ? null : () => onDayTap!(day),
      child: Container(
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
          border: isToday
              ? Border.all(color: _todayColor(cs), width: 1.5)
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          '$day',
          style: TextStyle(
            // v1.0.2 UI 审查修复：10 → 11，三列月历可读性
            fontSize: 11,
            fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
            color: isVacation
                ? cs.onErrorContainer
                : _cellTextColor(total, cs),
          ),
        ),
      ),
    );
  }

  Color _heat(int total, ColorScheme cs) {
    final custom = heatColors;
    if (custom != null && custom.length >= 4) {
      if (total <= 0) return custom[0];
      if (total < 50) return custom[1];
      if (total < 200) return custom[2];
      return custom[3];
    }
    return MonthCalendar.heatColor(total, cs);
  }

  Color _todayColor(ColorScheme cs) {
    final custom = heatColors;
    if (custom != null && custom.length >= 4) return custom[3];
    return cs.primary;
  }

  Color _cellTextColor(int total, ColorScheme cs) {
    if (total <= 0) return cs.onSurfaceVariant.withOpacity(0.55);
    return cs.onSurface;
  }
}
