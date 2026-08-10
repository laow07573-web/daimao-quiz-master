import 'dart:math' as math;

import 'package:flutter/material.dart';

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
Color accuracyTierColor(double rate, ColorScheme cs) {
  if (rate >= 80) return cs.primary.withOpacity(0.7);
  if (rate >= 60) return cs.primary.withOpacity(0.45);
  return cs.error.withOpacity(0.7);
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
    // v1.0.2 UI 设计稿：左侧 Y 轴固定 0-100 刻度（打卡线 50 恒在图内，
    // 数据全为 0 时柱子贴合底边）；数据超过 100 时自适应上扩
    var maxTotal = 1.0;
    for (final d in widget.days) {
      final t = (d['total'] as int?) ?? 0;
      if (t > maxTotal) maxTotal = t.toDouble();
    }
    return math.max(100.0, maxTotal * 1.15);
  }

  @override
  Widget build(BuildContext context) {
    if (_pages.isEmpty) {
      return const SizedBox(
        height: 200,
        child: Center(child: Text('暂无数据')),
      );
    }
    final cs = Theme.of(context).colorScheme;
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
              colorScheme: cs,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < _pages.length; i++)
              Container(
                width: 8,
                height: 4,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: i == _page ? cs.primary : cs.outlineVariant,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _TrendPage extends StatefulWidget {
  const _TrendPage({
    super.key,
    required this.days,
    required this.chartMax,
    required this.checkInThreshold,
    required this.colorScheme,
    this.onDaySelected,
  });

  final List<Map<String, dynamic>> days;
  final double chartMax;
  final int checkInThreshold;
  final ColorScheme colorScheme;
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
          colorScheme: widget.colorScheme,
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
    required this.colorScheme,
  });

  final List<Map<String, dynamic>> days;
  final double chartMax;
  final int checkInThreshold;
  final int? selectedIndex;
  final ColorScheme colorScheme;

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
    final gridPaint = Paint()
      ..color = colorScheme.outlineVariant.withOpacity(0.5)
      ..strokeWidth = 0.8;
    for (final v in [0.0, 25.0, 50.0, 75.0, 100.0]) {
      final y = _yFor(v);
      canvas.drawLine(
          Offset(leftPad, y), Offset(_size.width - rightPad, y), gridPaint);
      final tp = TextPainter(
        text: TextSpan(
          text: v.toInt().toString(),
          style: TextStyle(fontSize: 9, color: colorScheme.onSurfaceVariant),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(leftPad - tp.width - 4, y - tp.height / 2));
    }
    // 右侧正确率轴 0/50/100%
    final accPaint = Paint()
      ..color = colorScheme.outlineVariant.withOpacity(0.3)
      ..strokeWidth = 0.6;
    for (final pct in [0.0, 50.0, 100.0]) {
      final y = _yFor(pct / 100 * chartMax);
      canvas.drawLine(
          Offset(_size.width - rightPad, y), Offset(_size.width - 2, y), accPaint);
      final tp = TextPainter(
        text: TextSpan(
          text: '${pct.toInt()}%',
          style: TextStyle(fontSize: 8, color: colorScheme.onSurfaceVariant),
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
        const Radius.circular(3),
      );
      canvas.drawRRect(
        rect,
        Paint()..color = colorScheme.primary.withOpacity(0.55),
      );
    }
  }

  void _drawAccuracyLine(Canvas canvas) {
    // 只连有记录的天；段色 = accuracyTierColor(min(两端 rate))
    for (var i = 0; i < days.length - 1; i++) {
      final t1 = (days[i]['total'] as int?) ?? 0;
      final t2 = (days[i + 1]['total'] as int?) ?? 0;
      if (t1 <= 0 || t2 <= 0) continue;
      final a1 = (days[i]['accuracy'] as double?) ?? 0;
      final a2 = (days[i + 1]['accuracy'] as double?) ?? 0;
      final paint = Paint()
        ..color = accuracyTierColor(math.min(a1, a2), colorScheme)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      canvas.drawLine(
        Offset(_x(i), _yFor(a1 / 100 * chartMax)),
        Offset(_x(i + 1), _yFor(a2 / 100 * chartMax)),
        paint,
      );
    }
  }

  void _drawThreshold(Canvas canvas) {
    final y = _yFor(checkInThreshold.toDouble());
    if (y < topPad || y > _size.height - bottomPad) return;
    final dashPaint = Paint()
      ..color = colorScheme.tertiary.withOpacity(0.6)
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
            fontSize: 9, color: colorScheme.onTertiaryContainer),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final rectW = tp.width + 14;
    final labelX = math.max(leftPad, _size.width - rightPad - rectW - 4);
    final labelY = y - 16;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(labelX, labelY, rectW, 15),
      const Radius.circular(8),
    );
    canvas.drawRRect(rect, Paint()..color = colorScheme.tertiary);
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
          style: TextStyle(fontSize: 8, color: colorScheme.onSurfaceVariant),
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
        style: const TextStyle(fontSize: 10, color: Colors.white),
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
      const Radius.circular(6),
    );
    canvas.drawRRect(rect, Paint()..color = colorScheme.primary);
    tp.paint(canvas, Offset(bubbleX + 8, bubbleY + (rectH - tp.height) / 2));
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.days != days ||
      old.chartMax != chartMax ||
      old.selectedIndex != selectedIndex ||
      old.colorScheme != colorScheme;
}
