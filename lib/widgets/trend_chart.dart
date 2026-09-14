import '../utils/design_tokens.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../services/theme_service.dart';

/// 近 30 天趋势图（v1.0.2）
///
/// - 分页：从尾部每 7 天一页（头部不足 7 天碎片丢弃；n<7 时保留全部单页）
/// - Y 轴：chartMax = max(total) * 1.15 全量计算跨页统一；_niceStep 整数刻度
///   （1/2/5×10ⁿ），max(raw, 1.0) 防 0/0/1 重复刻度
/// - 分层折线：只连有记录的天；段色 = accuracyTierColor(min(两端 rate))
/// - 打卡虚线 + 「打卡 N 题」胶囊（防 clamp 上下限反转）
/// - 右侧正确率轴 0/50/100%
/// - 点击气泡：跳过 total<=0 的天；气泡 y = max(barTop - 34, topPad) 防负值裁剪
class TrendChart extends StatefulWidget {
  const TrendChart({
    super.key,
    required this.days, // [{date: DateTime, total: int, accuracy: double}]
    this.checkInThreshold = 50,
    this.onDaySelected, // 点击某天（仅 total>0 时触发，测试/外部联动用）
  });

  final List<Map<String, dynamic>> days;
  final int checkInThreshold;
  final ValueChanged<Map<String, dynamic>>? onDaySelected;

  @override
  State<TrendChart> createState() => _TrendChartState();
}

/// 从尾部每 7 天分页（头部碎片丢弃；不足 7 天保留全部）
List<List<Map<String, dynamic>>> chunkDays(
    List<Map<String, dynamic>> days) {
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

/// 整数刻度步长（1/2/5×10ⁿ）
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

/// 正确率三档取色（共享：趋势图/排行）
///
/// 三档统一走强调色不同透明度表达"好/中/差"，最差档用 danger 语义色。
/// 参数采用 Mao Des 的 [AppThemeColors]（页面已完成迁移）。
Color accuracyTierColor(double rate, AppThemeColors ac) {
  if (rate >= 80) return ac.accent.withOpacity(0.75);
  if (rate >= 60) return ac.accent.withOpacity(0.45);
  return ac.danger.withOpacity(0.75);
}

class _TrendChartState extends State<TrendChart> {
  late List<List<Map<String, dynamic>>> _pages;
  late final PageController _controller;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _pages = chunkDays(widget.days);
    _page = math.max(0, _pages.length - 1);
    _controller = PageController(initialPage: _page);
  }

  @override
  void didUpdateWidget(TrendChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.days != widget.days) {
      final newPages = chunkDays(widget.days);
      setState(() {
        _pages = newPages;
        _page = math.min(_page, math.max(0, newPages.length - 1));
      });
      _controller.jumpToPage(_page);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double get _chartMax {
    // v1.0.2 UI 审查修复：原固定 0-100 轴使 2~30 题的小量柱仅有数像素、
    // 图表观感"空白"；改为下限 20 的自适应轴，小数据量时柱高可见，
    // 数据超过 100 时仍自适应上扩。
    var maxTotal = 1.0;
    for (final d in widget.days) {
      final t = (d['total'] as int?) ?? 0;
      if (t > maxTotal) maxTotal = t.toDouble();
    }
    if (maxTotal <= 0) return 100.0;
    return math.max(20.0, maxTotal * 1.15);
  }

  @override
  Widget build(BuildContext context) {
    if (_pages.isEmpty) {
      return const SizedBox(
        height: 200,
        child: Center(child: Text('暂无数据')),
      );
    }
    final ac = AppThemeColors.of(context);
    // 可空取色：测试等裸 MaterialApp 场景未挂载 AppThemeColors 时回退 cs.error
    final danger = Theme.of(context).extension<AppThemeColors>()?.danger;
    return Column(
      children: [
        SizedBox(
          height: 200,
          child: PageView.builder(
            controller: _controller,
            itemCount: _pages.length,
            onPageChanged: (p) => setState(() => _page = p),
            itemBuilder: (context, i) => _TrendPage(
              key: ValueKey(i),
              days: _pages[i],
              chartMax: _chartMax,
              checkInThreshold: widget.checkInThreshold,
              onDaySelected: widget.onDaySelected,
              ac: ac,
              danger: danger,
            ),
          ),
        ),
        const SizedBox(height: 6),
        // v1.0.3 历史数据可查：左右箭头翻页（桌面鼠标无拖拽习惯时必需）；
        // 页数 ≤ 6 显示可点圆点，>6 页改显当前页日期范围。
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_pages.length > 1)
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(Icons.chevron_left,
                    size: 18,
                    color: _page > 0 ? ac.accent : ac.border),
                onPressed:
                    _page > 0 ? () => _controller.animateToPage(_page - 1, duration: const Duration(milliseconds: 250), curve: Curves.easeOut) : null,
              ),
            if (_pages.length <= 6) ...[
              for (var i = 0; i < _pages.length; i++)
                GestureDetector(
                  key: ValueKey('trend_dot_$i'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _controller.animateToPage(i, duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
                  child: Container(
                    width: 16,
                    height: 12,
                    alignment: Alignment.center,
                    child: Container(
                      width: 8,
                      height: 4,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(MaoRadius.chip),
                        color: i == _page ? ac.accent : ac.border,
                      ),
                    ),
                  ),
                ),
            ] else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  _pageRangeLabel,
                  style: TextStyle(fontSize: MaoType.caption, color: ac.textSecondary),
                ),
              ),
            if (_pages.length > 1)
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(Icons.chevron_right,
                    size: 18,
                    color: _page < _pages.length - 1
                        ? ac.accent
                        : ac.border),
                onPressed: _page < _pages.length - 1
                    ? () => _controller.animateToPage(_page + 1, duration: const Duration(milliseconds: 250), curve: Curves.easeOut)
                    : null,
              ),
          ],
        ),
      ],
    );
  }

  /// 当前页日期范围文本（如 3/4 - 3/10）
  String get _pageRangeLabel {
    final page = _pages[_page];
    if (page.isEmpty) return '';
    String fmt(Map<String, dynamic> d) {
      final dt = d['date'] as DateTime;
      return '${dt.month}/${dt.day}';
    }
    return '${fmt(page.first)} - ${fmt(page.last)}';
  }
}

class _TrendPage extends StatefulWidget {
  const _TrendPage({
    super.key,
    required this.days,
    required this.chartMax,
    required this.checkInThreshold,
    required this.ac,
    this.danger,
    this.onDaySelected,
  });

  final List<Map<String, dynamic>> days;
  final double chartMax;
  final int checkInThreshold;
  final AppThemeColors ac;
  final Color? danger;
  final ValueChanged<Map<String, dynamic>>? onDaySelected;

  @override
  State<_TrendPage> createState() => _TrendPageState();
}

class _TrendPageState extends State<_TrendPage> {
  int? _selectedIndex;

  @override
  void didUpdateWidget(_TrendPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 数据刷新时清空旧选中气泡
    if (oldWidget.days != widget.days) {
      _selectedIndex = null;
    }
  }

  void _handleTap(Size size, Offset pos) {
    if (size.width <= 0) return;
    const leftPad = 34.0, rightPad = 30.0;
    final plotW = size.width - leftPad - rightPad;
    final slotW = plotW / widget.days.length;
    final idx = ((pos.dx - leftPad) / slotW).floor();
    if (idx < 0 || idx >= widget.days.length) return;
    final total = (widget.days[idx]['total'] as int?) ?? 0;
    if (total <= 0) return; // 跳过无记录的天
    setState(() => _selectedIndex = idx);
    widget.onDaySelected?.call(widget.days[idx]);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) => _handleTap(context.size!, d.localPosition),
      child: CustomPaint(
        size: Size.infinite,
        painter: _TrendPainter(
          days: widget.days,
          chartMax: widget.chartMax,
          checkInThreshold: widget.checkInThreshold,
          selectedIndex: _selectedIndex,
          ac: widget.ac,
          danger: widget.danger,
        ),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.days,
    required this.chartMax,
    required this.checkInThreshold,
    required this.selectedIndex,
    required this.ac,
    this.danger,
  });

  final List<Map<String, dynamic>> days;
  final double chartMax;
  final int checkInThreshold;
  final int? selectedIndex;
  final AppThemeColors ac;
  final Color? danger;

  static const double leftPad = 34;
  static const double rightPad = 30;
  static const double topPad = 12;
  static const double bottomPad = 20;

  double get _plotW => _size.width - leftPad - rightPad;
  double get _plotH => _size.height - topPad - bottomPad;
  late Size _size;

  double _x(int i) => leftPad + (i + 0.5) * (_plotW / days.length);
  double _yFor(double v) => topPad + _plotH * (1 - v / chartMax);

  @override
  void paint(Canvas canvas, Size size) {
    _size = size;
    if (_plotW <= 0 || _plotH <= 0) return;

    _drawGrid(canvas);
    _drawBars(canvas);
    _drawAccuracyLine(canvas);
    _drawThreshold(canvas);
    _drawLabels(canvas);
    if (selectedIndex != null) _drawBubble(canvas);
  }

  void _drawGrid(Canvas canvas) {
    // v1.0.2 UI 设计稿：左侧刻度固定 0-100（每 25 一档）代表刷题量
    // 精密暗色：网格是最底层信息，用发丝线宽 + border 原色（不再叠加透明度）
    final gridPaint = Paint()
      ..color = ac.border
      ..strokeWidth = MaoLine.width;
    for (final v in [0.0, 25.0, 50.0, 75.0, 100.0]) {
      final y = _yFor(v);
      canvas.drawLine(
          Offset(leftPad, y), Offset(_size.width - rightPad, y), gridPaint);
      final tp = TextPainter(
        text: TextSpan(
          text: v.toInt().toString(),
          style: MaoType.microStyle.copyWith(color: ac.textTertiary),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(leftPad - tp.width - 4, y - tp.height / 2));
    }
    // 右侧正确率轴 0/50/100%
    // 右侧正确率轴：比主网格再轻一档，只作参考
    final accPaint = Paint()
      ..color = ac.border.withOpacity(0.6)
      ..strokeWidth = MaoLine.width * 0.75;
    for (final pct in [0.0, 50.0, 100.0]) {
      final y = _yFor(pct / 100 * chartMax);
      canvas.drawLine(
          Offset(_size.width - rightPad, y), Offset(_size.width - 2, y), accPaint);
      final tp = TextPainter(
        text: TextSpan(
          text: '${pct.toInt()}%',
          style: MaoType.microStyle.copyWith(color: ac.textTertiary),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(_size.width - rightPad + 3, y - tp.height / 2));
    }
  }

  void _drawBars(Canvas canvas) {
    final barW = _plotW / days.length * 0.45;
    for (var i = 0; i < days.length; i++) {
      final total = (days[i]['total'] as int?) ?? 0;
      if (total <= 0) continue; // 没刷题的天保留占位不画柱
      final x = _x(i);
      final top = _yFor(total.toDouble());
      final bottom = _yFor(0);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTRB(x - barW / 2, top, x + barW / 2, bottom),
        const Radius.circular(MaoRadius.chip),
      );
      canvas.drawRRect(
        rect,
        Paint()..color = ac.accent.withOpacity(0.5),
      );
    }
  }

  /// 某天是否有记录；有则返回其正确率折线上的坐标，否则 null
  Offset? _accPointAt(int i) {
    if (i < 0 || i >= days.length) return null;
    final t = (days[i]['total'] as int?) ?? 0;
    if (t <= 0) return null;
    final a = (days[i]['accuracy'] as double?) ?? 0;
    return Offset(_x(i), _yFor(a / 100 * chartMax));
  }

  void _drawAccuracyLine(Canvas canvas) {
    // 只连有记录的天；段色 = accuracyTierColor(min(两端 rate))。
    // 逐点画曲线：相邻两点用三次贝塞尔相连（Catmull-Rom 转 Bézier），
    // 控制点限制在该段包围盒内，避免过冲产生假峰谷。
    for (var i = 0; i < days.length - 1; i++) {
      final t1 = (days[i]['total'] as int?) ?? 0;
      final t2 = (days[i + 1]['total'] as int?) ?? 0;
      if (t1 <= 0 || t2 <= 0) continue;
      final a1 = (days[i]['accuracy'] as double?) ?? 0;
      final a2 = (days[i + 1]['accuracy'] as double?) ?? 0;
      final paint = Paint()
        ..color = accuracyTierColor(math.min(a1, a2), ac)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      final p1 = Offset(_x(i), _yFor(a1 / 100 * chartMax));
      final p2 = Offset(_x(i + 1), _yFor(a2 / 100 * chartMax));
      final p0 = _accPointAt(i - 1) ?? p1;
      final p3 = _accPointAt(i + 2) ?? p2;
      canvas.drawPath(smoothSegment(p1, p2, p0, p3), paint);
    }
  }

  void _drawThreshold(Canvas canvas) {
    final y = _yFor(checkInThreshold.toDouble());
    if (y < topPad || y > _size.height - bottomPad) return;
    final dashPaint = Paint()
      ..color = ac.warning.withOpacity(0.6)
      ..strokeWidth = 1.2;
    // 虚线
    const dash = 5.0, gap = 4.0;
    var dx = leftPad;
    while (dx < _size.width - rightPad) {
      canvas.drawLine(
          Offset(dx, y), Offset(math.min(dx + dash, _size.width - rightPad), y), dashPaint);
      dx += dash + gap;
    }
    // 胶囊标签（labelX = max(leftPad, w - rightPad - rectW - 4) 防 clamp 上下限反转）
    final tp = TextPainter(
      text: TextSpan(
        text: '打卡 $checkInThreshold 题',
        style: TextStyle(
            fontSize: MaoType.micro, color: ac.textPrimary),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final rectW = tp.width + 14;
    final labelX = math.max(leftPad, _size.width - rightPad - rectW - 4);
    final labelY = y - 16;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(labelX, labelY, rectW, 15),
      const Radius.circular(MaoRadius.small),
    );
    canvas.drawRRect(rect, Paint()..color = ac.warning);
    tp.paint(canvas, Offset(labelX + 7, labelY + (15 - tp.height) / 2));
  }

  void _drawLabels(Canvas canvas) {
    // X 轴：仅显示有记录天的日期（M/d）
    final shown = <int>{};
    for (var i = 0; i < days.length; i++) {
      if (((days[i]['total'] as int?) ?? 0) > 0) shown.add(i);
    }
    for (final i in shown) {
      final date = days[i]['date'] as DateTime;
      final tp = TextPainter(
        text: TextSpan(
          text: '${date.month}/${date.day}',
          style: MaoType.microStyle.copyWith(color: ac.textTertiary),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(_x(i) - tp.width / 2, _size.height - bottomPad + 4),
      );
    }
  }

  void _drawBubble(Canvas canvas) {
    final i = selectedIndex!;
    final total = (days[i]['total'] as int?) ?? 0;
    if (total <= 0) return;
    final acc = (days[i]['accuracy'] as double?) ?? 0;
    final date = days[i]['date'] as DateTime;

    final tp = TextPainter(
      text: TextSpan(
        text: '${date.month}/${date.day} ${total}题 ${acc.toStringAsFixed(0)}%',
        style: MaoType.microStyle.copyWith(color: ac.onAccent),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final rectW = tp.width + 16;
    final rectH = 24.0;
    final barTop = _yFor(total.toDouble());
    // 气泡 y = max(barTop - 34, topPad) 防负值裁剪
    final bubbleY = math.max(barTop - rectH - 10, topPad);
    // x 水平 clamp（labelX 同款防反转）
    final bubbleX =
        math.max(leftPad, math.min(_x(i) - rectW / 2, _size.width - rightPad - rectW - 4));
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(bubbleX, bubbleY, rectW, rectH),
      const Radius.circular(MaoRadius.chip),
    );
    canvas.drawRRect(rect, Paint()..color = ac.accent);
    tp.paint(canvas, Offset(bubbleX + 8, bubbleY + (rectH - tp.height) / 2));
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.days != days ||
      old.chartMax != chartMax ||
      old.selectedIndex != selectedIndex ||
      old.ac != ac;
}

/// 用三次贝塞尔连接 p1→p2，控制点由 Catmull-Rom（p0→p1→p2→p3）推得，
/// 并收进本段包围盒内，保证曲线平滑、单调、不过冲。
///
/// 抽成纯函数便于单测（绘制本身难以断言）。
Path smoothSegment(Offset p1, Offset p2, Offset p0, Offset p3) {
  var c1 = p1 + (p2 - p0) / 6;
  var c2 = p2 - (p3 - p1) / 6;
  final loY = math.min(p1.dy, p2.dy);
  final hiY = math.max(p1.dy, p2.dy);
  final loX = math.min(p1.dx, p2.dx);
  final hiX = math.max(p1.dx, p2.dx);
  c1 = Offset(c1.dx.clamp(loX, hiX), c1.dy.clamp(loY, hiY));
  c2 = Offset(c2.dx.clamp(loX, hiX), c2.dy.clamp(loY, hiY));
  return Path()
    ..moveTo(p1.dx, p1.dy)
    ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
}
