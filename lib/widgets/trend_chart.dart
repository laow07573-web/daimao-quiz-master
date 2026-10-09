import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import '../services/theme_service.dart';
import '../utils/design_tokens.dart';

/// 近一年趋势：学习量行情图（单图叠加正确率虚线）。
///
/// 用户需求（2026-10-08 原话）：「开盘价和收盘价用昨天最高刷题量替代，收盘价用
/// 今日刷题量替代，比昨天低就是红色，比昨天高就是绿色。影线就不要了；正确率用
/// 虚线折线表示，图层在柱状图之上，把刷题量和正确率做到一张图里。坐标轴不应
/// 跟随滑动，要固定在原处，上面的数值要根据显示的内容变化。」
///
/// 于是这里的约定是：
/// - 柱体：开盘 = 前一自然日的最终刷题量（日累计量单调不减，所以「昨天最高」就是
///   它当天的最终值），收盘 = 今日刷题量；涨绿、跌红、持平或缺前一天用中性细柱；
///   不画影线。缺前一天数据时不伪造开盘价。
/// - 正确率：虚线折线，绘制顺序在所有柱体之后（图层压在柱体之上），用右侧
///   0..100 的独立百分比刻度（窄屏可隐藏右侧刻度）。
/// - 坐标轴：画在固定位置，不参与平移/缩放；纵轴刻度随**当前可视范围**的数据重算，
///   所以拖动后刻度数值会跟着变。
/// - 视口渲染：只绘制可视范围内的那几天（另加相邻一天用于虚线接续），不是把整块
///   大画布缩小——这是为了保证 365 天数据下拖动依然跟手。
/// - 交互：横向连续拖动 + 双指/滚轮缩放（以焦点为中心，带边界）；默认窗口锚定在
///   **最新数据**那一端（见 _TrendChartState._anchorToLatest），否则打开看到的是
///   一年前那段空白。点击某天通过 [onDaySelected] 回调。
///
/// days 元素为 `{date: DateTime, total: int, accuracy: double}`，按时间升序。
class TrendChart extends StatefulWidget {
  const TrendChart({
    super.key,
    required this.days, // [{date: DateTime, total: int, accuracy: double}]
    this.checkInThreshold = 50,
    this.onDaySelected,
  });

  final List<Map<String, dynamic>> days;
  final int checkInThreshold;
  final ValueChanged<Map<String, dynamic>>? onDaySelected;

  @override
  State<TrendChart> createState() => _TrendChartState();
}

List<List<Map<String, dynamic>>> chunkDays(List<Map<String, dynamic>> days) {
  final pages = <List<Map<String, dynamic>>>[];
  if (days.isEmpty) return pages;
  final n = days.length;
  if (n < 7) {
    pages.add(List.of(days));
    return pages;
  }
  final startIdx = n % 7;
  var i = startIdx == 0 ? 0 : startIdx;
  while (i < n) {
    pages.add(days.sublist(i, math.min(i + 7, n)));
    i += 7;
  }
  return pages;
}

/// 鏁存暟鍒诲�?步长�?/2/5�?0鈦匡�?
double niceStep(double raw) {
  if (raw <= 0) return 1;
  final exp = (math.log(raw) / math.ln10).floor();
  final base = math.pow(10, exp).toDouble();
  final frac = raw / base;
  if (frac <= 1) return 1 * base;
  if (frac <= 2) return 2 * base;
  if (frac <= 5) return 5 * base;
  return 10 * base;
}

///
///
Color levelShade(Color base, Color surface, double strength) {
  final t = strength.clamp(0.0, 1.0);
  final mixed = Color.lerp(surface, base, t)!;
  final baseHsl = HSLColor.fromColor(base);
  if (baseHsl.saturation == 0 || baseHsl.saturation >= 0.16) return mixed;
  return HSLColor.fromColor(mixed)
      .withHue(baseHsl.hue)
      .withSaturation((0.18 + 0.22 * t).clamp(0.0, 1.0))
      .toColor();
}

///
Color accuracyTierColor(double rate, AppThemeColors ac) {
  if (rate >= 80) return levelShade(ac.accent, ac.surface, 0.75);
  if (rate >= 60) return levelShade(ac.accent, ac.surface, 0.45);
  return levelShade(ac.danger, ac.surface, 0.75);
}

// ============================================================
//
// ============================================================

@immutable
class TrendTick {
  const TrendTick(this.value, this.label);

  final double value;
  final String label;

  @override
  bool operator ==(Object other) =>
      other is TrendTick && other.value == value && other.label == label;

  @override
  int get hashCode => Object.hash(value, label);

  @override
  String toString() => 'TrendTick($value, "$label")';
}

@immutable
class TrendPlot {
  const TrendPlot({
    required this.size,
    required this.dayCount,
    required this.chartMax,
    required this.checkInThreshold,
  });

  final Size size;
  final int dayCount;
  final double chartMax;
  final int checkInThreshold;

  static const double leftPad = 26;

  static const double rightPad = 10;

  static const double topPad = 14;

  static const double bottomPad = 20;

  Rect get rect => Rect.fromLTRB(
        leftPad,
        topPad,
        math.max(leftPad, size.width - rightPad),
        math.max(topPad, size.height - bottomPad),
      );

  double get slotWidth => dayCount <= 0 ? 0 : rect.width / dayCount;

  double x(int i) => rect.left + (i + 0.5) * slotWidth;

  double yForVolume(num value) {
    final t = chartMax <= 0 ? 0.0 : (value / chartMax).clamp(0.0, 1.0);
    return rect.bottom - rect.height * t;
  }

  double yForAccuracy(double percent) => yForVolume(percent / 100 * chartMax);

  List<double> get gridValues =>
      chartMax <= 0 ? const [0.0] : [0.0, chartMax / 2, chartMax];

  List<TrendTick> get ticks => chartMax <= 0
      ? const [TrendTick(0, '0')]
      : [const TrendTick(0, '0'), TrendTick(chartMax, _formatNumber(chartMax))];

  double? get checkInY {
    if (checkInThreshold < 0 || checkInThreshold > chartMax) return null;
    return yForVolume(checkInThreshold);
  }

  int dayIndexAt(double dx) {
    if (slotWidth <= 0) return -1;
    final idx = ((dx - rect.left) / slotWidth).floor();
    return (idx < 0 || idx >= dayCount) ? -1 : idx;
  }
}

String _formatNumber(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

///
Path volumeCurvePath(
  List<Offset> points, {
  double? startX,
  double? endX,
}) {
  final path = Path();
  if (points.isEmpty) return path;
  final first = points.first;
  final last = points.last;
  final left = startX ?? first.dx;
  final right = endX ?? last.dx;
  path.moveTo(left, first.dy);
  if (left != first.dx) path.lineTo(first.dx, first.dy);
  if (points.length == 1) {
    path.lineTo(right, last.dy);
    return path;
  }
  for (var i = 0; i < points.length - 1; i++) {
    _appendSmoothCubic(
      path,
      points[i],
      points[i + 1],
      points[i == 0 ? 0 : i - 1],
      points[i + 2 >= points.length ? points.length - 1 : i + 2],
    );
  }
  if (right != last.dx) path.lineTo(right, last.dy);
  return path;
}

///
Path volumeAreaPath(
  List<Offset> points, {
  required double baselineY,
  double? startX,
  double? endX,
}) {
  final path = Path();
  if (points.isEmpty) return path;
  final left = startX ?? points.first.dx;
  final right = endX ?? points.last.dx;
  path.addPath(
    volumeCurvePath(points, startX: startX, endX: endX),
    Offset.zero,
  );
  path.lineTo(right, baselineY);
  path.lineTo(left, baselineY);
  path.close();
  return path;
}

@immutable
class AccuracyDot {
  const AccuracyDot({
    required this.index,
    required this.center,
    required this.isEndpoint,
  });

  final int index;
  final Offset center;
  final bool isEndpoint;

  @override
  bool operator ==(Object other) =>
      other is AccuracyDot &&
      other.index == index &&
      other.center == center &&
      other.isEndpoint == isEndpoint;

  @override
  int get hashCode => Object.hash(index, center, isEndpoint);

  @override
  String toString() => 'AccuracyDot($index, $center, endpoint: $isEndpoint)';
}

List<AccuracyDot> accuracyDots(List<Offset?> points) {
  final dots = <AccuracyDot>[];
  for (var i = 0; i < points.length; i++) {
    final center = points[i];
    if (center == null) continue;
    final prev = i > 0 ? points[i - 1] : null;
    final next = i + 1 < points.length ? points[i + 1] : null;
    dots.add(AccuracyDot(
      index: i,
      center: center,
      isEndpoint: prev == null || next == null,
    ));
  }
  return dots;
}

List<List<int>> accuracyRuns(List<Offset?> points) {
  final runs = <List<int>>[];
  int? start;
  for (var i = 0; i < points.length; i++) {
    if (points[i] != null) {
      start ??= i;
    } else if (start != null) {
      runs.add([start, i - 1]);
      start = null;
    }
  }
  if (start != null) runs.add([start, points.length - 1]);
  return runs;
}

///
@immutable
class TrendColors {
  const TrendColors({
    required this.areaStroke,
    required this.areaTop,
    required this.areaBottom,
    required this.lineHalo,
    required this.dotRing,
    required this.grid,
    required this.label,
    required this.guide,
    required this.guideLabel,
    required this.selection,
    required this.bubbleBackground,
    required this.bubbleForeground,
  });

  factory TrendColors.of(AppThemeColors ac) => TrendColors(
        areaStroke: ac.accent,
        areaTop: ac.accent.withOpacity(0.30),
        areaBottom: ac.accent.withOpacity(0.0),
        lineHalo: ac.surface.withOpacity(0.70),
        dotRing: ac.surface,
        grid: ac.border,
        label: ac.textSecondary,
        guide: ac.warning.withOpacity(0.75),
        guideLabel: ac.textTertiary,
        selection: ac.accent.withOpacity(0.35),
        bubbleBackground: ac.accent,
        bubbleForeground: ac.onAccent,
      );

  final Color areaStroke;

  final Color areaTop;
  final Color areaBottom;

  /// 姝ｇ‘鐜囨�?绾跨殑闈㈡澘鑹插簳琛笌绔偣鍦嗙幆
  final Color lineHalo;
  final Color dotRing;

  final Color grid;
  final Color label;

  final Color guide;
  final Color guideLabel;

  final Color selection;

  /// 鐐瑰�??�?�?
  final Color bubbleBackground;
  final Color bubbleForeground;
}

/// 默认可视窗口（最近 [span] 天）在 `dayCount` 天数据里的起点。
///
/// 图表默认要停在**最新数据**这一端：days 按时间升序、末尾是今天，从 0 开始看
/// 等于打开就是一年前那段空白（真机反馈「趋势图不显示数据」）。抽成纯函数便于
/// 回归测试，见 test/trend_chart_test.dart。
double latestWindowStart(int dayCount, double span) {
  if (dayCount <= 0) return 0;
  final s = span.clamp(1.0, dayCount.toDouble());
  return math.max(0.0, dayCount - s);
}

/// 行情图配色：参考主流加密货币 K 线（涨青绿、跌玫红、平灰），
/// 正确率曲线改用金色——用户反馈原来的虚线（主题色）和柱体在色相上太接近，
/// 盯久了视觉疲劳，两条数据线要"一眼分得开"。
class TrendPalette {
  const TrendPalette._();

  /// 涨：#0ECB81（交易所常用的绿）
  static const up = Color(0xFF0ECB81);

  /// 跌：#F6465D（交易所常用的红）
  static const down = Color(0xFFF6465D);

  /// 持平 / 缺前一天：中性灰，只画一小段，不参与涨跌叙事
  static const flat = Color(0xFF787B86);

  /// 正确率折线：金色，与涨跌柱体色相拉开
  static const accuracy = Color(0xFFF0B90B);
}

/// 柱体宽度：始终取「一天所占宽度」的固定比例，所以无论放大缩小，
/// 柱与柱的间距都是等比恒定的（用户反馈放大后柱子孤零零、间距忽大忽小）。
double candleWidthFor(double slotWidth) =>
    slotWidth <= 0 ? 1.0 : math.max(1.0, slotWidth * 0.62);

/// 最小可视窗口（天）：再放大就只剩几根巨大的柱子，没有信息量了。
const double minTrendSpan = 7;

class _TrendChartState extends State<TrendChart> {
  /// 可视窗口起点（数组下标，可为小数）。
  ///
  /// 由 [_anchorToLatest] 初始化到「最新数据」这一端：days 按时间升序排列
  /// （末尾是今天），默认从 0 看等于打开就是一年前那段空白，要一路往右拖
  /// 才能看到最近的数据——真机反馈「趋势图不显示数据」就是这个原因。
  double _start = 0;

  /// 可视窗口宽度（天）。默认最近一个月，可缩放 [minTrendSpan]..days.length。
  double _span = 30;

  /// 手势开始时的窗口快照 + 起点焦点位置。
  double? _gestureStart;
  double? _gestureSpan;
  double? _gestureFocalX;

  /// 派生数据缓存：只随 days 变化重算一次（绘制期一律 O(1) 查表）。
  TrendDerived _derived = TrendDerived.of(const []);
  List<Map<String, dynamic>>? _derivedFor;

  TrendDerived get derived {
    if (!identical(_derivedFor, widget.days)) {
      _derivedFor = widget.days;
      _derived = TrendDerived.of(widget.days);
    }
    return _derived;
  }

  /// 被点选的日期（画竖向指示线 + 高亮），null = 未选中。
  int? _selectedIndex;

  double get _maxSpan => math.max(1, widget.days.length.toDouble());

  /// 把可视窗口贴到最新一端（数据末尾 = 今天）。
  ///
  /// 只在数据长度变化时调用：用户手动平移之后刷新（长度不变）不该把他弹回去。
  void _anchorToLatest() {
    final n = widget.days.length;
    if (n == 0) return;
    _span = _span.clamp(
        math.min(minTrendSpan, n).toDouble(), math.max(1, n).toDouble());
    _start = latestWindowStart(n, _span);
  }

  @override
  void initState() {
    super.initState();
    _anchorToLatest();
  }

  @override
  void didUpdateWidget(TrendChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 统计页首帧是空列表、取数完成后才变成 365 天，这里必须重新锚定。
    if (widget.days.length != oldWidget.days.length) {
      _anchorToLatest();
      _selectedIndex = null;
    }
  }

  void _clamp() {
    final lo = math.min(minTrendSpan, _maxSpan);
    _span = _span.clamp(lo, _maxSpan);
    _start = _start.clamp(0.0, math.max(0.0, widget.days.length - _span));
  }

  void _zoom(double factor, double focalX, double width) {
    if (widget.days.isEmpty) return;
    final old = _span;
    final next = (old / factor)
        .clamp(math.min(minTrendSpan, _maxSpan), _maxSpan)
        .toDouble();
    final at = _start + (focalX / math.max(1, width)) * old;
    setState(() {
      _span = next;
      _start = at - (focalX / math.max(1, width)) * next;
      _clamp();
    });
  }

  /// 单指拖动与双指缩放共用一个识别器。
  ///
  /// 之前同时挂了 onScale* 和 onHorizontalDrag*，两个识别器在手势竞技场里互抢：
  /// 捏合经常被判成横向拖动，用户反馈"缩放非常不灵敏、容易误触成左右滑动"。
  /// 现在只留 onScale*，用「焦点锚定的同一个数据点」同时表达缩放与平移。
  void _onScaleStart(ScaleStartDetails d) {
    _gestureStart = _start;
    _gestureSpan = _span;
    _gestureFocalX = d.localFocalPoint.dx;
  }

  void _onScaleUpdate(ScaleUpdateDetails d, double width) {
    if (_gestureStart == null || _gestureSpan == null) return;
    final w = math.max(1.0, width);
    final focal = d.localFocalPoint.dx / w;
    final anchorFocal = (_gestureFocalX ?? d.localFocalPoint.dx) / w;
    // 手势开始时焦点下的那个数据点，要一直待在手指下面：
    //   anchor = 起始窗口里焦点对应的数据下标
    //   缩放 + 平移一次算完，所以双指捏合与单指拖动都跟手
    final anchor = _gestureStart! + anchorFocal * _gestureSpan!;
    setState(() {
      _span = (_gestureSpan! / d.scale)
          .clamp(math.min(minTrendSpan, _maxSpan), _maxSpan);
      _start = anchor - focal * _span;
      _clamp();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.days.isEmpty) {
      return const SizedBox(height: 200, child: Center(child: Text('暂无数据')));
    }
    final ac = AppThemeColors.of(context);
    final first = _clampedDate(_start.round());
    final last = _clampedDate((_start + _span - 1).round());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 可视范围提示：放大后不至于"不知道自己在看哪一段"
        Text(
          '${first.month}/${first.day} – ${last.month}/${last.day} · 共 ${_span.round()} 天',
          style: MaoType.microStyle.copyWith(color: ac.textTertiary),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 200,
          child: LayoutBuilder(builder: (context, c) {
            return Listener(
              key: const ValueKey('trend_interactive_viewer'),
              onPointerSignal: (e) {
                if (e is PointerScrollEvent) {
                  _zoom(e.scrollDelta.dy > 0 ? 0.9 : 1.1, e.localPosition.dx,
                      c.maxWidth);
                }
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onScaleStart: _onScaleStart,
                onScaleUpdate: (d) => _onScaleUpdate(d, c.maxWidth),
                onTapUp: (d) {
                  final p = TrendViewport(
                      size: Size(c.maxWidth, 200),
                      count: widget.days.length,
                      start: _start,
                      span: _span,
                      chartMax: derived.chartMax);
                  final i = p.indexAt(d.localPosition.dx);
                  if (i >= 0 && i < widget.days.length) {
                    final hasData =
                        ((widget.days[i]['total'] as num?)?.toDouble() ?? 0) >
                            0;
                    setState(() => _selectedIndex = hasData ? i : null);
                    if (hasData) widget.onDaySelected?.call(widget.days[i]);
                  }
                },
                child: CustomPaint(
                    painter: _TrendPainter(
                        days: widget.days,
                        derived: derived,
                        start: _start,
                        span: _span,
                        selectedIndex: _selectedIndex,
                        ac: ac,
                        checkInThreshold: widget.checkInThreshold),
                    size: Size.infinite),
              ),
            );
          }),
        ),
      ],
    );
  }

  /// 把可视窗口内的下标安全映射回日期（越界时夹到数据两端）。
  DateTime _clampedDate(int index) {
    final i = index.clamp(0, widget.days.length - 1);
    return widget.days[i]['date'] as DateTime;
  }
}

/// 日期键：'YYYY-MM-DD'（与热力图/统计同口径）。
String trendDayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// 行情绘制用的派生数据（**每帧只算一次**）。
///
/// 性能背景：此前 painter 每帧都对每天调用一次 [previousDayTotal]，而后者是
/// 线性遍历 days —— 365 天时等于每帧 13 万次比较（O(n²)），统计页上半部
/// （概览 + 趋势图）滚动明显掉帧，下半部分不卡就是这个原因。
/// 现在把「日期 → 当日总量」索引与纵轴上限预先算好，绘制期一律 O(1) 查表。
@immutable
class TrendDerived {
  const TrendDerived._(this.byDay, this.chartMax);

  /// 'YYYY-MM-DD' → 当日最终刷题量
  final Map<String, double> byDay;

  /// 纵轴上限（含前一天开盘值，向上取整留 15% 余量）
  final double chartMax;

  factory TrendDerived.of(List<Map<String, dynamic>> days) {
    final byDay = <String, double>{};
    for (final d in days) {
      final date = d['date'];
      if (date is! DateTime) continue;
      byDay[trendDayKey(date)] = (d['total'] as num?)?.toDouble() ?? 0;
    }
    var max = 1.0;
    for (final d in days) {
      final date = d['date'];
      if (date is! DateTime) continue;
      final close = byDay[trendDayKey(date)] ?? 0;
      final open = byDay[trendDayKey(DateTime(date.year, date.month, date.day)
          .subtract(const Duration(days: 1)))];
      if (close > max) max = close;
      if (open != null && open > max) max = open;
    }
    return TrendDerived._(byDay, math.max(20, (max * 1.15).ceilToDouble()));
  }

  /// 某天的开盘价（= 前一自然日最终刷题量）。缺前一天数据时返回 null，
  /// 不伪造开盘价——柱体改用中性标记。
  double? openFor(DateTime date) =>
      byDay[trendDayKey(DateTime(date.year, date.month, date.day)
          .subtract(const Duration(days: 1)))];
}

/// 返回某日期前一日的最终刷题量；缺少前一天数据时返回 null，不伪造开盘价。
///
/// 保留公开签名（测试与其他调用方在用）。绘制热路径请改用 [TrendDerived]，
/// 避免每次调用都线性扫描。
double? previousDayTotal(List<Map<String, dynamic>> days, DateTime date) {
  final target = trendDayKey(DateTime(date.year, date.month, date.day)
      .subtract(const Duration(days: 1)));
  for (final d in days) {
    final x = d['date'];
    if (x is DateTime && trendDayKey(x) == target) {
      return (d['total'] as num?)?.toDouble() ?? 0;
    }
  }
  return null;
}

@immutable
class TrendViewport {
  const TrendViewport(
      {required this.size,
      required this.count,
      required this.start,
      required this.span,
      required this.chartMax});
  final Size size;
  final int count;
  final double start;
  final double span;
  final double chartMax;
  static const leftPad = 38.0, rightPad = 38.0, topPad = 14.0, bottomPad = 30.0;
  Rect get rect => Rect.fromLTRB(
      leftPad,
      topPad,
      math.max(leftPad, size.width - rightPad),
      math.max(topPad, size.height - bottomPad));
  double x(double index) => rect.left + ((index - start) / span) * rect.width;
  double y(double value) =>
      rect.bottom - (value / chartMax).clamp(0.0, 1.0) * rect.height;
  int indexAt(double dx) => (start + ((dx - rect.left) / rect.width) * span)
      .round()
      .clamp(0, count - 1);
}

class _TrendPainter extends CustomPainter {
  _TrendPainter(
      {required this.days,
      required this.start,
      required this.span,
      required this.selectedIndex,
      required this.ac,
      required this.checkInThreshold,
      required this.derived});
  final List<Map<String, dynamic>> days;

  /// 预计算的日期索引与纵轴上限（每帧复用，绘制期 O(1)）。
  final TrendDerived derived;
  final double start, span;
  final int? selectedIndex;
  final AppThemeColors ac;
  final int checkInThreshold;
  @override
  void paint(Canvas canvas, Size size) {
    if (days.isEmpty) return;
    final vp = TrendViewport(
        size: size,
        count: days.length,
        start: start,
        span: span,
        chartMax: derived.chartMax);
    final grid = Paint()
      ..color = ac.border
      ..strokeWidth = .7;
    for (final v in [0.0, vp.chartMax / 2, vp.chartMax]) {
      canvas.drawLine(
          Offset(vp.rect.left, vp.y(v)), Offset(vp.rect.right, vp.y(v)), grid);
    }
    final lo = math.max(0, start.floor() - 1),
        hi = math.min(days.length - 1, (start + span).ceil() + 1);
    // 柱宽 = 一天所占宽度的固定比例 → 无论放大缩小，柱间间距都等比恒定，
    // 不会出现"放大后一根柱子孤零零、间距忽大忽小"（真机反馈）。
    final slotWidth = vp.rect.width / math.max(1e-6, span);
    final barWidth = candleWidthFor(slotWidth);
    // 柱体：开盘 = 前一自然日最终刷题量，收盘 = 今日刷题量；涨绿跌红、无影线。
    for (var i = lo; i <= hi; i++) {
      final d = days[i];
      final close = (d['total'] as num?)?.toDouble() ?? 0;
      final open = derived.openFor(d['date'] as DateTime);
      final x = vp.x(i.toDouble());
      if (close <= 0) continue;
      if (open == null || open == close) {
        // 缺前一天或与昨天持平：一小段中性标记，不编造涨跌
        canvas.drawRect(
            Rect.fromCenter(
                center: Offset(x, vp.y(close)),
                width: barWidth,
                height: math.max(2, barWidth * 0.18)),
            Paint()..color = TrendPalette.flat);
      } else {
        final color = close > open ? TrendPalette.up : TrendPalette.down;
        canvas.drawRect(
            Rect.fromLTRB(x - barWidth / 2, vp.y(math.max(open, close)),
                x + barWidth / 2, vp.y(math.min(open, close))),
            Paint()..color = color);
      }
    }
    // 选中日的竖向指示线：画在柱体之上、曲线之下
    if (selectedIndex != null && selectedIndex! >= lo && selectedIndex! <= hi) {
      final sx = vp.x(selectedIndex!.toDouble());
      canvas.drawLine(Offset(sx, vp.rect.top), Offset(sx, vp.rect.bottom),
          Paint()..color = TrendPalette.accuracy.withOpacity(0.35));
    }
    // 正确率虚线：金色、细、画在柱体之后（图层在上），与涨跌柱体色相拉开距离。
    final line = Paint()
      ..color = TrendPalette.accuracy
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    for (var i = lo; i < hi; i++) {
      final a = days[i], b = days[i + 1];
      final ta = (a['total'] as num?)?.toDouble() ?? 0,
          tb = (b['total'] as num?)?.toDouble() ?? 0;
      if (ta <= 0 || tb <= 0) continue;
      final p1 = Offset(
          vp.x(i.toDouble()),
          vp.rect.bottom -
              (((a['accuracy'] as num?)?.toDouble() ?? 0).clamp(0, 100) / 100) *
                  vp.rect.height);
      final p2 = Offset(
          vp.x((i + 1).toDouble()),
          vp.rect.bottom -
              (((b['accuracy'] as num?)?.toDouble() ?? 0).clamp(0, 100) / 100) *
                  vp.rect.height);
      _dash(canvas, p1, p2, line);
    }
    _text(canvas, '0', Offset(4, vp.rect.bottom - 8), ac.textSecondary);
    _text(canvas, _formatNumber(vp.chartMax), Offset(2, vp.rect.top - 2),
        ac.textSecondary);
    _text(canvas, '100%', Offset(vp.rect.right + 3, vp.rect.top - 2),
        ac.textSecondary);
    _text(canvas, '0%', Offset(vp.rect.right + 8, vp.rect.bottom - 8),
        ac.textSecondary);
    final step = math.max(1, (span / 7).ceil()).toInt();
    for (var i = lo; i <= hi; i += step) {
      final d = days[i]['date'] as DateTime;
      _text(canvas, '${d.month}/${d.day}',
          Offset(vp.x(i.toDouble()), vp.rect.bottom + 4), ac.textSecondary,
          center: true);
    }
  }

  void _dash(Canvas c, Offset a, Offset b, Paint p) {
    final d = b - a, n = d.distance;
    if (n == 0) return;
    final u = d / n;
    for (var t = 0.0; t < n; t += 6) {
      c.drawLine(a + u * t, a + u * math.min(t + 3, n), p);
    }
  }

  void _text(Canvas c, String s, Offset p, Color color, {bool center = false}) {
    final tp = TextPainter(
        text: TextSpan(
            text: s, style: TextStyle(fontSize: MaoType.micro, color: color)),
        textDirection: TextDirection.ltr)
      ..layout();
    tp.paint(c, Offset(center ? p.dx - tp.width / 2 : p.dx, p.dy));
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) =>
      old.days != days ||
      old.derived != derived ||
      old.start != start ||
      old.span != span ||
      old.selectedIndex != selectedIndex ||
      old.ac != ac;
}

/// Smooth helper retained for callers; chart now uses discrete daily line segments.
Path smoothSegment(Offset p1, Offset p2, Offset p0, Offset p3) {
  final path = Path()..moveTo(p1.dx, p1.dy);
  _appendSmoothCubic(path, p1, p2, p0, p3);
  return path;
}

void _appendSmoothCubic(Path path, Offset p1, Offset p2, Offset p0, Offset p3) {
  var c1 = p1 + (p2 - p0) / 6;
  var c2 = p2 - (p3 - p1) / 6;
  final loY = math.min(p1.dy, p2.dy);
  final hiY = math.max(p1.dy, p2.dy);
  final loX = math.min(p1.dx, p2.dx);
  final hiX = math.max(p1.dx, p2.dx);
  c1 = Offset(c1.dx.clamp(loX, hiX), c1.dy.clamp(loY, hiY));
  c2 = Offset(c2.dx.clamp(loX, hiX), c2.dy.clamp(loY, hiY));
  path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
}
