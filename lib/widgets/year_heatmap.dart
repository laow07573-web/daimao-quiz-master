import 'package:flutter/material.dart';
import '../services/theme_service.dart';
import '../utils/design_tokens.dart';

/// 年度坚持热力图（Mao Des）
///
/// GitHub 贡献图风格：一整年 53 周 × 7 天的小方块，一眼看全年坚持情况。
/// 相比旧版「3 个月横排小日历」，格子更大（≥11px）、看的是整年、
/// 且能按行（周一…周日）对齐，适合"坚持"这一语义。
///
/// - 色阶四档：0 无 / 少 / 达标 / 多（阈值同全站口径）
/// - 今天：描边高亮；假期：置灰（浅色 danger 淡化）
/// - 点击某天：回调 [onDayTap]（传 'YYYY-MM-DD'）
/// - 月份标签：每列所属月变化时在顶部标注
class YearHeatmap extends StatelessWidget {
  const YearHeatmap({
    super.key,
    required this.year,
    required this.dailyTotals,
    this.vacationDays = const {},
    this.todayKey,
    this.onDayTap,
  });

  final int year;

  /// key: 'YYYY-MM-DD' -> 当日刷题数
  final Map<String, int> dailyTotals;
  final Set<String> vacationDays;
  final String? todayKey;
  final ValueChanged<String>? onDayTap;

  static String dateKeyOf(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// 色阶：0 / 少(<50) / 达标(50~199) / 多(200+)，
  /// 与首页、统计页旧日历保持同一口径。
  static Color levelColor(int total, AppThemeColors ac) {
    if (total <= 0) return ac.surfaceAlt;
    if (total < 50) return ac.accent.withOpacity(0.30);
    if (total < 200) return ac.accent.withOpacity(0.58);
    return ac.accent;
  }

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    final weeks = _buildWeeks();

    // 用 LayoutBuilder 取「本组件实际可用宽度」（而非屏幕宽度）：
    // 统计页在宽屏下是双列卡片，可用宽远小于屏幕。
    // 网格用 Expanded 列均分宽度：无论容器多窄都不会横向溢出。
    return LayoutBuilder(
      builder: (context, constraints) {
        final gridW = constraints.maxWidth - _labelWidth;
        final cellW = (gridW / weeks.length).clamp(3.0, 15.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 月份标签行（与周列对齐）──
            Padding(
              padding: EdgeInsets.only(left: _labelWidth, bottom: MaoSpace.xxs),
              child: Row(
                children: [
                  for (var i = 0; i < weeks.length; i++)
                    Expanded(
                      child: (weeks[i].monthLabel != null)
                          ? FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                weeks[i].monthLabel!,
                                style: MaoType.microStyle.copyWith(
                                    color: ac.textTertiary, fontSize: 9.5),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                ],
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── 星期标签列（一/三/五，避免拥挤）──
                SizedBox(
                  width: _labelWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var d = 0; d < 7; d++)
                        SizedBox(
                          height: cellW,
                          child: (d == 0 || d == 2 || d == 4)
                              ? Align(
                                  alignment: Alignment.centerLeft,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      const ['一', '二', '三', '四', '五', '六', '日'][d],
                                      style: MaoType.microStyle.copyWith(
                                          color: ac.textTertiary, fontSize: 9.5),
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                    ],
                  ),
                ),
                // ── 热力网格：每列 Expanded 均分，格内用 AspectRatio 保证正方形 ──
                Expanded(
                  child: Column(
                    children: [
                      for (var d = 0; d < 7; d++)
                        Row(
                          children: [
                            for (var w = 0; w < weeks.length; w++)
                              Expanded(child: _cell(weeks[w].days[d], ac)),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  static const double _labelWidth = 16;

  Widget _cell(_HeatDay? day, AppThemeColors ac) {
    if (day == null) {
      return const AspectRatio(aspectRatio: 1, child: SizedBox.shrink());
    }
    final total = dailyTotals[day.key] ?? 0;
    final isToday = todayKey == day.key;
    final isVacation = vacationDays.contains(day.key);
    final color = isVacation
        ? ac.danger.withOpacity(0.22)
        : levelColor(total, ac);

    return Padding(
      padding: const EdgeInsets.all(1.2),
      child: Tooltip(
        message: '${day.key}　${isVacation ? "假期" : "$total 题"}',
        waitDuration: const Duration(milliseconds: 400),
        child: GestureDetector(
          onTap: onDayTap == null ? null : () => onDayTap!(day.key),
          child: AspectRatio(
            aspectRatio: 1,
            child: Container(
              decoration: BoxDecoration(
                color: color,
                // 圆角统一走令牌；2px 是热力格在密集网格里的最佳观感
                borderRadius: BorderRadius.circular(2),
                // 今天：强调色细环（暗色下比填充更清晰，且不掩盖当天热力值）
                border: isToday
                    ? Border.all(color: ac.accent, width: 1.3)
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 把一年切成 53 个「周列」，每列 7 天（周一起）。年内日期之外为空。
  List<_HeatWeek> _buildWeeks() {
    final jan1 = DateTime(year, 1, 1);
    final dec31 = DateTime(year, 12, 31);
    // 起始回退到包含 1/1 的那一周的周一
    final firstMonday = jan1.subtract(Duration(days: jan1.weekday - 1));

    final weeks = <_HeatWeek>[];
    var cursor = firstMonday;
    int? prevMonth;
    while (!cursor.isAfter(dec31)) {
      final days = <_HeatDay?>[];
      for (var i = 0; i < 7; i++) {
        final d = cursor.add(Duration(days: i));
        if (d.year != year || d.isAfter(dec31)) {
          days.add(null);
        } else {
          days.add(_HeatDay(dateKeyOf(d)));
        }
      }
      // 该列首个属于本年的日期，决定月份标签
      final firstInYear = days.firstWhere((d) => d != null, orElse: () => null);
      String? label;
      if (firstInYear != null) {
        final m = int.parse(firstInYear.key.split('-')[1]);
        if (prevMonth != m) {
          label = '$m月';
          prevMonth = m;
        }
      }
      weeks.add(_HeatWeek(days, label));
      cursor = cursor.add(const Duration(days: 7));
    }
    return weeks;
  }
}

class _HeatWeek {
  const _HeatWeek(this.days, this.monthLabel);
  final List<_HeatDay?> days;
  final String? monthLabel;
}

class _HeatDay {
  const _HeatDay(this.key);
  final String key;
}
