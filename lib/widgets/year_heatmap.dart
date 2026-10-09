import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
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
class YearHeatmap extends StatefulWidget {
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

  /// 网格画布的 Key：测试用来取画布尺寸（断言格子仍是正方形），
  /// 也方便命中测试/定位。放在 Widget 类上作为公开 API。
  static const Key gridCanvasKey = Key('year-heatmap-grid');

  /// 色阶：0 / 少(<50) / 达标(50~199) / 多(200+)，
  /// 与首页、统计页旧日历保持同一口径。
  static Color levelColor(int total, AppThemeColors ac) {
    if (total <= 0) return ac.surfaceAlt;
    if (total < 50) return ac.accent.withOpacity(0.30);
    if (total < 200) return ac.accent.withOpacity(0.58);
    return ac.accent;
  }

  @override
  State<YearHeatmap> createState() => _YearHeatmapState();
}

class _YearHeatmapState extends State<YearHeatmap> {
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
              padding: const EdgeInsets.only(
                  left: _labelWidth, bottom: MaoSpace.xxs),
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
                                      const [
                                        '一',
                                        '二',
                                        '三',
                                        '四',
                                        '五',
                                        '六',
                                        '日'
                                      ][d],
                                      style: MaoType.microStyle.copyWith(
                                          color: ac.textTertiary,
                                          fontSize: 9.5),
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                    ],
                  ),
                ),
                // ── 热力网格：53×7 = 371 格 ──
                //
                // 性能（2026-10-09，用 profile 构建 + FrameTiming 实测得出的结论）：
                // 统计页卡顿的**唯一**大头是进入时的首帧——实测 build 峰值 103ms、
                // raster 峰值 95.5ms（同一页滚动时 build 仅 1.1ms、raster 2.7ms）。
                // 成本来自「371 个格子各是一个 widget」：Container + AspectRatio +
                // Padding + Semantics，一次性构建与绘制 371 份。
                //
                // 因此整块网格改为**一次 CustomPaint**：
                //   · widget 数 371 → 1，首帧构建几乎归零；
                //   · 绘制合并成一批 drawRRect，raster 同步下降；
                //   · 无障碍没有退化——用 CustomPainter.semanticsBuilder 仍然逐格
                //     生成语义节点（标签文案与原来一字不差、可点）；
                //   · 外观完全不变：同样的色阶、1.2 内缩、2 圆角、今天的描边。
                //
                // 手势仍是网格级：一个 Tooltip（manual）+ 一个 GestureDetector +
                // 坐标命中测试，长按气泡与点击回调行为不变。
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, grid) {
                      final gridW = grid.maxWidth;
                      final colW = weeks.isEmpty ? 0.0 : gridW / weeks.length;
                      return Tooltip(
                        // 单实例：manual 触发，由下面的手势层调用
                        key: _tipKey,
                        message: _tipMessage,
                        triggerMode: TooltipTriggerMode.manual,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapUp: (d) {
                            final key =
                                _dayKeyAt(d.localPosition, gridW, weeks);
                            if (key != null) widget.onDayTap?.call(key);
                          },
                          onLongPressStart: (d) =>
                              _showTip(d.localPosition, gridW, weeks),
                          onLongPressMoveUpdate: (d) =>
                              _showTip(d.localPosition, gridW, weeks),
                          onLongPressEnd: (_) => _hideTip(),
                          child: CustomPaint(
                            // 测试与命中测试都靠它精确定位网格画布
                            key: YearHeatmap.gridCanvasKey,
                            size: Size(gridW, colW * 7),
                            painter: _HeatmapPainter(
                              weeks: weeks,
                              colW: colW,
                              dailyTotals: widget.dailyTotals,
                              vacationDays: widget.vacationDays,
                              todayKey: widget.todayKey,
                              accent: ac.accent,
                              danger: ac.danger,
                              empty: ac.surfaceAlt,
                              onDayTap: widget.onDayTap,
                              textDirection: Directionality.of(context),
                            ),
                          ),
                        ),
                      );
                    },
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

  /// 网格级 Tooltip（整块共用一个实例，长按/移动时更新文案并显示）。
  final GlobalKey<TooltipState> _tipKey = GlobalKey<TooltipState>();
  String _tipMessage = '';

  /// 网格坐标 → 该位置是哪个日期（越界返回 null）。
  ///
  /// 每列等宽、每格 AspectRatio 1:1，所以行高 == 列宽，无需再测量具体尺寸。
  String? _dayKeyAt(Offset p, double gridWidth, List<_HeatWeek> weeks) {
    if (weeks.isEmpty || gridWidth <= 0) return null;
    final colW = gridWidth / weeks.length;
    final col = (p.dx / colW).floor();
    final row = (p.dy / colW).floor();
    if (col < 0 || col >= weeks.length || row < 0 || row >= 7) return null;
    return weeks[col].days[row]?.key;
  }

  void _showTip(Offset p, double gridWidth, List<_HeatWeek> weeks) {
    final key = _dayKeyAt(p, gridWidth, weeks);
    if (key == null) return;
    final total = widget.dailyTotals[key] ?? 0;
    final status = widget.vacationDays.contains(key) ? '假期' : '$total 题';
    final message = '$key　$status';
    if (message != _tipMessage) {
      // Tooltip 的 message 要下一帧才生效，改完再触发显示
      setState(() => _tipMessage = message);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _tipKey.currentState?.ensureTooltipVisible();
      });
    } else {
      _tipKey.currentState?.ensureTooltipVisible();
    }
  }

  void _hideTip() {
    // 网格共用一个 Tooltip，全部关掉即可（长按结束）
    Tooltip.dismissAllToolTips();
  }

  /// 把一年切成 53 个「周列」，每列 7 天（周一起）。年内日期之外为空。
  List<_HeatWeek> _buildWeeks() {
    final jan1 = DateTime(widget.year, 1, 1);
    final dec31 = DateTime(widget.year, 12, 31);
    // 起始回退到包含 1/1 的那一周的周一
    final firstMonday = jan1.subtract(Duration(days: jan1.weekday - 1));

    final weeks = <_HeatWeek>[];
    var cursor = firstMonday;
    int? prevMonth;
    while (!cursor.isAfter(dec31)) {
      final days = <_HeatDay?>[];
      for (var i = 0; i < 7; i++) {
        final d = cursor.add(Duration(days: i));
        if (d.year != widget.year || d.isAfter(dec31)) {
          days.add(null);
        } else {
          days.add(_HeatDay(YearHeatmap.dateKeyOf(d)));
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

/// 热力网格的绘制器：一次画完 371 格（原来是 371 个 widget）。
///
/// 视觉与原来的逐格 widget **完全一致**：
/// 每格正方形、内缩 1.2、圆角 2、色阶四档、今天加 accent 描边 1.3。
/// 无障碍通过 [semanticsBuilder] 保留：每格仍然是一个带标签、可点的语义节点，
/// 标签文案与原实现一字不差（'YYYY-MM-DD，N 题'／'假期'／'，今天'）。
class _HeatmapPainter extends CustomPainter {
  _HeatmapPainter({
    required this.weeks,
    required this.colW,
    required this.dailyTotals,
    required this.vacationDays,
    required this.todayKey,
    required this.accent,
    required this.danger,
    required this.empty,
    required this.onDayTap,
    required this.textDirection,
  });

  final List<_HeatWeek> weeks;
  final double colW;
  final Map<String, int> dailyTotals;
  final Set<String> vacationDays;
  final String? todayKey;
  final Color accent;
  final Color danger;
  final Color empty;
  final ValueChanged<String>? onDayTap;

  /// 语义节点必须显式带方向：渲染层无法自行推断
  /// （缺了会触发 'attributedLabel.string == \'\' || textDirection != null' 断言）
  final TextDirection textDirection;

  static const double _gap = 1.2; // 每格内缩（与原 Padding.all(1.2) 一致）
  static const double _radius = 2; // 圆角（与原 BorderRadius.circular(2) 一致）
  static const double _todayBorder = 1.3;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..style = PaintingStyle.fill;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _todayBorder
      ..color = accent;

    for (var w = 0; w < weeks.length; w++) {
      for (var d = 0; d < 7; d++) {
        final day = weeks[w].days[d];
        if (day == null) continue;
        final total = dailyTotals[day.key] ?? 0;
        final rect = Rect.fromLTWH(
          w * colW + _gap,
          d * colW + _gap,
          colW - _gap * 2,
          colW - _gap * 2,
        );
        if (rect.width <= 0 || rect.height <= 0) continue;
        final rrect =
            RRect.fromRectAndRadius(rect, const Radius.circular(_radius));
        fill.color = _levelColor(total, day.key);
        canvas.drawRRect(rrect, fill);
        if (todayKey == day.key) {
          canvas.drawRRect(rrect.deflate(_todayBorder / 2), stroke);
        }
      }
    }
  }

  Color _levelColor(int total, String key) {
    if (vacationDays.contains(key)) return danger.withOpacity(0.22);
    return _Palette.level(accent, total, empty);
  }

  /// 逐格语义（无障碍不退化）：标签文案与原 `_cell` 完全一致
  @override
  SemanticsBuilderCallback get semanticsBuilder => (Size size) {
        final nodes = <CustomPainterSemantics>[];
        for (var w = 0; w < weeks.length; w++) {
          for (var d = 0; d < 7; d++) {
            final day = weeks[w].days[d];
            if (day == null) continue;
            final total = dailyTotals[day.key] ?? 0;
            final isVacation = vacationDays.contains(day.key);
            final status = isVacation ? '假期' : '$total 题';
            final label =
                '${day.key}，$status${todayKey == day.key ? '，今天' : ''}';
            final rect = Rect.fromLTWH(w * colW, d * colW, colW, colW);
            nodes.add(CustomPainterSemantics(
              rect: rect,
              properties: SemanticsProperties(
                label: label,
                textDirection: textDirection,
                button: onDayTap != null,
                enabled: onDayTap != null,
                onTap: onDayTap == null ? null : () => onDayTap!(day.key),
              ),
            ));
          }
        }
        return nodes;
      };

  @override
  bool shouldRepaint(covariant _HeatmapPainter old) =>
      old.weeks != weeks ||
      old.colW != colW ||
      old.todayKey != todayKey ||
      old.accent != accent ||
      old.dailyTotals.length != dailyTotals.length ||
      !identical(old.dailyTotals, dailyTotals) ||
      old.vacationDays.length != vacationDays.length;

  @override
  bool shouldRebuildSemantics(covariant _HeatmapPainter old) =>
      shouldRepaint(old);
}

/// 色阶（与 [YearHeatmap.levelColor] 同口径，供绘制器批量取色）
class _Palette {
  /// 0 / 少(<50) / 达标(50~199) / 多(200+)
  static Color level(Color accent, int total, Color empty) {
    if (total <= 0) return empty;
    if (total < 50) return accent.withOpacity(0.30);
    if (total < 200) return accent.withOpacity(0.58);
    return accent;
  }
}

class _HeatDay {
  const _HeatDay(this.key);
  final String key;
}
