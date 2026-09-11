import 'package:flutter/material.dart';
import '../services/theme_service.dart';
import '../utils/design_tokens.dart';

/// 年度坚持热力图（Mao Des）
///
/// 一整年 53 周 × 7 天的小方块，看全年坚持情况。
///
/// 关键设计（v1.28 二次修订）：**按可用宽度自动分段**
/// 上一版把 53 周硬挤在一行，手机上每格仅 3~5px，根本看不清。
/// 现在若格子达不到 [_minCell]，就把一年拆成 2~4 段纵向排列
/// （每段仍是周一到周日 7 行），格子始终 ≥ 11px，可读可点。
///
/// - 色阶四档：0 无 / 少(<50) / 达标(50~199) / 多(200+)，与全站口径一致
/// - 今天：描边高亮；假期：淡红置灰
/// - 点击某天：回调 [onDayTap]（传 'YYYY-MM-DD'）
/// - 每段顶部标出月份，左侧标周一/三/五
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

  /// 格子间距
  static const double _gap = 2.4;

  /// 星期标签列宽
  static const double _labelWidth = 16;

  /// 最小可读格子尺寸；低于此值就拆段（核心：不再出现 3~5px 的小格子）
  static const double _minCell = 11.0;

  /// 格子最大尺寸（避免超宽屏下格子过大）
  static const double _maxCell = 22.0;

  static String dateKeyOf(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// 色阶：0 / 少(<50) / 达标(50~199) / 多(200+)
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final avail = (constraints.maxWidth - _labelWidth).clamp(0.0, 1e6);

        // 每段最多放多少周（保证格子 ≥ _minCell）
        var perRow = (avail / (_minCell + _gap)).floor();
        if (perRow < 1) perRow = 1;
        // 需要分几段（上限 4 段，避免纵向过长）
        var segments = (weeks.length / perRow).ceil();
        if (segments < 1) segments = 1;
        if (segments > 4) segments = 4;
        final perSegment = (weeks.length / segments).ceil();

        final cell = (avail / perSegment - _gap).clamp(6.0, _maxCell);

        final blocks = <Widget>[];
        for (var s = 0; s < segments; s++) {
          final start = s * perSegment;
          if (start >= weeks.length) break;
          final end = (start + perSegment) > weeks.length
              ? weeks.length
              : start + perSegment;
          if (s > 0) blocks.add(const SizedBox(height: MaoSpace.xs + 2));
          blocks.add(_segment(weeks.sublist(start, end), ac, cell));
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: blocks,
        );
      },
    );
  }

  /// 渲染一段（perSegment 周 × 7 天）
  Widget _segment(List<_HeatWeek> weeks, AppThemeColors ac, double cell) {
    final rowH = cell + _gap;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 月份标签行（与周列对齐）
        Padding(
          padding: const EdgeInsets.only(left: _labelWidth, bottom: MaoSpace.xxs),
          child: Row(
            children: [
              for (final w in weeks)
                Expanded(
                  child: (w.monthLabel != null)
                      ? FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            w.monthLabel!,
                            style: MaoType.microStyle
                                .copyWith(color: ac.textTertiary, fontSize: 10),
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
            // 星期标签（一/三/五）
            SizedBox(
              width: _labelWidth,
              child: Column(
                children: [
                  for (var d = 0; d < 7; d++)
                    SizedBox(
                      height: rowH,
                      child: (d == 0 || d == 2 || d == 4)
                          ? Align(
                              alignment: Alignment.centerLeft,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  const ['一', '二', '三', '四', '五', '六', '日'][d],
                                  style: MaoType.microStyle.copyWith(
                                      color: ac.textTertiary, fontSize: 10),
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                ],
              ),
            ),
            // 热力网格
            Expanded(
              child: Column(
                children: [
                  for (var d = 0; d < 7; d++)
                    Row(
                      children: [
                        for (final w in weeks)
                          Expanded(child: _cell(w.days[d], ac)),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _cell(_HeatDay? day, AppThemeColors ac) {
    if (day == null) {
      return const Padding(
        padding: EdgeInsets.all(_gap / 2),
        child: AspectRatio(aspectRatio: 1, child: SizedBox.shrink()),
      );
    }
    final total = dailyTotals[day.key] ?? 0;
    final isToday = todayKey == day.key;
    final isVacation = vacationDays.contains(day.key);
    final color =
        isVacation ? ac.danger.withOpacity(0.22) : levelColor(total, ac);

    return Padding(
      padding: const EdgeInsets.all(_gap / 2),
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
                borderRadius: BorderRadius.circular(3),
                border: isToday
                    ? Border.all(color: ac.accent, width: 1.4)
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 把一年切成「周列」，每列 7 天（周一起）。年内日期之外为空。
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
