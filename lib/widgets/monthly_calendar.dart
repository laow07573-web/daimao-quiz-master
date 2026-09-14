import '../utils/design_tokens.dart';
import '../services/theme_service.dart';
import 'package:flutter/material.dart';

/// 单月打卡日历（Mao Des 2.0 · 精密暗色）
///
/// 42 格网格（前导空白 + 天数 + 尾部补空），每格热力色阶按当日刷题量：
/// 0=空 / <50=少 / 50~199=达标 / 200+=多（可自定义四级色阶 [heatColors]）。
///
/// 与上一版的视觉差异（精密化）：
///   · **空格子不再铺底色**——只留日期数字，消除"整块像键盘"的噪音
///   · 新增星期表头，网格有结构感
///   · 格子收紧（略扁 + 更小圆角 + 更细间隙），不再主导版面
///   · 今天：强调色细环 + 加粗 + 强调色数字
///   · 假期：语义色淡底 + 语义色数字置灰
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
    this.rows, // 渲染行数；null = 按本月实际需要（4~6 行，不留空行）
    this.cellHeight, // 格子高度；null = 由可用宽度推导（宽高比 0.86）
  });

  final int year;
  final int month;
  final Map<String, int> dailyTotals;
  final Set<String> vacationDays;
  final String? todayKey;
  final bool highlightToday;
  final List<Color>? heatColors;
  final ValueChanged<int>? onDayTap;
  final int? rows;

  /// 格子高度。外部（如首页一屏布局）可按剩余高度反推后传入，
  /// 使日历精确贴合可用空间。
  final double? cellHeight;

  static const List<String> _weekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];

  static String dateKeyOf(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// 该月实际需要几行（4~6）：首日偏移 + 天数，向上取整。
  /// 用于让容器高度贴合内容，避免 5 行月份底部留一整行空白。
  static int rowCountFor(int year, int month) {
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final leading = DateTime(year, month, 1).weekday - 1; // 1=周一
    return ((leading + daysInMonth) / 7).ceil().clamp(4, 6);
  }

  /// 月份标题 + 星期表头占用的固定高度（供外层容器计算总高）
  /// 月份标题 + 星期表头 + 间距的占用高度。
  /// 取宽裕值（字体实际行盒高于 fontSize×height 的理论值）：
  /// 估大只是让日历上下略留白，估小会导致父级 RenderFlex overflow。
  static const double chromeHeight = 62;

  /// 热力色阶（与首页/统计页统一口径）
  static Color heatColor(int total, AppThemeColors ac) {
    if (total <= 0) return ac.surfaceAlt.withOpacity(0.55);
    // 加深色阶：「少/达标/多」区分度足
    if (total < 50) return ac.accent.withOpacity(0.28);
    if (total < 200) return ac.accent.withOpacity(0.52);
    return ac.accent.withOpacity(0.85);
  }

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final firstWeekday = DateTime(year, month, 1).weekday; // 1=周一
    final leading = firstWeekday - 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 月份 / 年份 ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            children: [
              Text('$month月',
                  style: MaoType.h3Style.copyWith(
                      color: ac.textPrimary, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('$year年',
                  style: MaoType.microStyle.copyWith(color: ac.textTertiary)),
            ],
          ),
        ),
        const SizedBox(height: MaoSpace.xs),
        // ── 星期表头：给网格一个结构基准 ──
        LayoutBuilder(
          builder: (context, constraints) {
            final cellW = constraints.maxWidth / 7;
            return Row(
              children: [
                for (final w in _weekdayLabels)
                  SizedBox(
                    width: cellW,
                    child: Center(
                      child: Text(w,
                          style: MaoType.microStyle
                              .copyWith(color: ac.textTertiary)),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: MaoSpace.xxs),
        // ── 42 格 ──
        // 紧凑化：格高约等于格宽的 0.86（略扁），并限制上限，
        // 宽屏/横屏不溢出，同时日历不会抢走版面重心。
        LayoutBuilder(
          builder: (context, constraints) {
            final cellW = constraints.maxWidth / 7;
            final cellH = cellHeight ?? (cellW * 0.86).clamp(24.0, 44.0);
            final rowCount = rows ?? MonthCalendar.rowCountFor(year, month);
            return SizedBox(
              height: rowCount * cellH,
              child: GridView.count(
                crossAxisCount: 7,
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: cellW / cellH,
                children: [
                  for (var i = 0; i < rowCount * 7; i++)
                    _buildCell(i - leading + 1, daysInMonth, ac),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildCell(int day, int daysInMonth, AppThemeColors ac) {
    if (day < 1 || day > daysInMonth) {
      return const SizedBox.shrink();
    }
    final key = MonthCalendar.dateKeyOf(DateTime(year, month, day));
    final total = dailyTotals[key] ?? 0;
    final isToday = highlightToday && todayKey != null && key == todayKey;
    final isVacation = vacationDays.contains(key);
    final hasActivity = total > 0;

    // 空格子不铺底——这是消除"键盘感"的关键
    final Color fill;
    if (isVacation) {
      fill = ac.danger.withOpacity(0.14);
    } else if (hasActivity) {
      fill = _heat(total, ac);
    } else {
      fill = Colors.transparent;
    }

    final Color textColor;
    if (isToday) {
      textColor = ac.accent;
    } else if (isVacation) {
      textColor = ac.danger;
    } else if (hasActivity) {
      textColor = ac.textPrimary;
    } else {
      textColor = ac.textTertiary;
    }

    return InkWell(
      borderRadius: BorderRadius.circular(MaoRadius.small),
      onTap: onDayTap == null ? null : () => onDayTap!(day),
      child: Container(
        margin: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(MaoRadius.small),
          border: isToday
              ? Border.all(color: _todayColor(ac), width: 1.5)
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          '$day',
          style: TextStyle(
            fontSize: MaoType.caption,
            // 测试锚点：今天必须加粗
            fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
            color: textColor,
          ),
        ),
      ),
    );
  }

  Color _heat(int total, AppThemeColors ac) {
    final custom = heatColors;
    if (custom != null && custom.length >= 4) {
      if (total <= 0) return custom[0];
      if (total < 50) return custom[1];
      if (total < 200) return custom[2];
      return custom[3];
    }
    return MonthCalendar.heatColor(total, ac);
  }

  Color _todayColor(AppThemeColors ac) {
    final custom = heatColors;
    if (custom != null && custom.length >= 4) return custom[3];
    return ac.accent;
  }
}
