import '../services/theme_service.dart';
import 'package:flutter/material.dart';

import '../models/ink_annotation.dart';
import 'annotation_controller.dart';

/// 手写批注画布（v1.0.3 手写批注，REQ-013 流畅性）
///
/// 叠放在题目内容之上：
/// - [interactive] = true（批注模式中）：Listener 接收指针，滚动已由外层锁死
/// - [interactive] = false（只读回显）：IgnorePointer 穿透，仅渲染已存批注
///
/// 渲染：二次贝塞尔中点平滑 + 圆头笔帽；荧光笔半透明；选中笔迹虚线包围盒。
class AnnotationCanvas extends StatefulWidget {
  const AnnotationCanvas({
    super.key,
    required this.controller,
    required this.interactive,
    this.frameFilter,
  });

  final AnnotationController controller;
  final bool interactive;

  /// v1.0.3 画布扩区：只渲染指定坐标基准的笔迹（'question'/'page'）；
  /// null = 全部渲染（窄屏单画布场景）。
  final String? frameFilter;

  @override
  State<AnnotationCanvas> createState() => _AnnotationCanvasState();
}

class _AnnotationCanvasState extends State<AnnotationCanvas> {
  // 选择工具的按下锚点 / 拖动参考点（画布局部坐标）
  Offset? _selectAnchor;
  Offset _lastSelectPos = Offset.zero;

  AnnotationController get c => widget.controller;

  Size get _canvasSize =>
      (context.findRenderObject() as RenderBox?)?.size ?? Size.zero;

  Offset _normalize(Offset local) {
    final size = _canvasSize;
    if (size.width == 0 || size.height == 0) return Offset.zero;
    return Offset(
      (local.dx / size.width).clamp(0.0, 1.0),
      (local.dy / size.height).clamp(0.0, 1.0),
    );
  }

  /// 压感回退（v1.0.3 数位板兼容）：部分鼠标/驱动上报 pressure 为 0，
  /// 回退 1.0 避免笔画消失级细线；支持压感的触摸/触控笔/Windows Ink 正常取真实值。
  double _pressure(double raw) => raw <= 0 ? 1.0 : raw;

  void _onDown(PointerDownEvent e) {
    final size = _canvasSize;
    switch (c.tool) {
      case AnnoTool.pen:
        c.beginStroke(_normalize(e.localPosition), _pressure(e.pressure));
      case AnnoTool.eraser:
        c.eraseAt(e.localPosition, size);
      case AnnoTool.select:
        // down 只记锚点，up 时无位移才算 tap 选择（拖动交给 move 逻辑）；
        // _lastSelectPos 同步到落点（否则首个 move 的 delta 相对 (0,0)，
        // 选中笔迹会被瞬间甩飞）
        _selectAnchor = e.localPosition;
        _lastSelectPos = e.localPosition;
    }
  }

  void _onMove(PointerMoveEvent e) {
    final size = _canvasSize;
    switch (c.tool) {
      case AnnoTool.pen:
        c.extendStroke(_normalize(e.localPosition), _pressure(e.pressure));
      case AnnoTool.eraser:
        c.eraseAt(e.localPosition, size);
      case AnnoTool.select:
        if (_selectAnchor == null) return;
        if (c.selectedIndex != null) {
          // 拖动选中笔迹：按本次事件位移增量平移
          final delta = e.localPosition - _lastSelectPos;
          c.moveSelected(delta, size);
          _lastSelectPos = _lastSelectPos + delta;
        } else {
          // 未选中：拖动中做热区预选（命中即选中，可继续拖）
          if (c.selectAt(e.localPosition, size)) {
            _lastSelectPos = e.localPosition;
          }
        }
    }
  }

  void _onUp(PointerUpEvent e) {
    switch (c.tool) {
      case AnnoTool.pen:
        c.endStroke();
      case AnnoTool.eraser:
        break;
      case AnnoTool.select:
        if (_selectAnchor != null) {
          final moved = (e.localPosition - _selectAnchor!).distance;
          // tap（位移 < 8px）：命中选择；未命中清除选中
          if (moved < 8) {
            c.selectAt(e.localPosition, _canvasSize);
          }
        }
        _selectAnchor = null;
    }
  }

  void _onCancel(PointerCancelEvent e) {
    c.cancelStroke();
    _selectAnchor = null;
  }

  @override
  Widget build(BuildContext context) {
    final canvas = Listener(
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: _onUp,
      onPointerCancel: _onCancel,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _InkPainter(c, widget.frameFilter, AppThemeColors.of(context)),
          size: Size.infinite,
        ),
      ),
    );
    if (!widget.interactive) return IgnorePointer(child: canvas);
    // v1.27 需求纠偏：批注模式下禁止左右滑动切题——画布不识别横向拖动，
    // 全部指针事件归书写/擦除/选择；切题仅非批注态生效（外层滚动区手势）。
    return canvas;
  }
}

/// 笔迹渲染器
class _InkPainter extends CustomPainter {
  _InkPainter(this.controller, this.frameFilter, this.ac)
      : super(repaint: controller);

  /// 主题语义色（画布选中框等装饰用）
  final AppThemeColors ac;

  final AnnotationController controller;

  /// 只渲染指定坐标基准的笔迹；null = 全部（窄屏单画布）
  final String? frameFilter;

  bool _visible(InkStroke s) => frameFilter == null || s.frame == frameFilter;

  @override
  void paint(Canvas canvas, Size size) {
    final strokes = controller.strokes.where(_visible).toList();
    final live = controller.liveStroke;
    if (live != null && _visible(live)) strokes.add(live);
    for (final s in strokes) {
      _paintStroke(canvas, size, s);
    }
    // 选中笔迹：虚线包围盒 + 淡蓝底高亮（REQ-010 选择反馈；
    // v1.0.3 增强：细线不明显 → 加粗虚线 + 底色填充）
    final i = controller.selectedIndex;
    if (i != null &&
        i < controller.strokes.length &&
        _visible(controller.strokes[i])) {
      final b = controller.strokes[i].bounds();
      final rect = Rect.fromLTWH(
        b.left * size.width - 6,
        b.top * size.height - 6,
        b.width * size.width + 12,
        b.height * size.height + 12,
      );
      // 淡蓝底色填充（选中区域一目了然）
      canvas.drawRect(
        rect,
        Paint()..color = ac.accent.withOpacity(0.10),
      );
      // 虚线描边（宽 2.2 更醒目）
      canvas.drawPath(_dashRect(rect, 7, 5),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2
            ..color = ac.accent);
    }
  }

  /// 矩形虚线路径（dash 长/间隔）
  Path _dashRect(Rect rect, double dash, double gap) {
    final path = Path();
    void edge(Offset a, Offset b) {
      final len = (b - a).distance;
      var t = 0.0;
      var on = true;
      while (t < len) {
        final seg = on ? dash : gap;
        final end = (t + seg).clamp(0.0, len).toDouble();
        if (on) {
          path.moveTo(
              a.dx + (b.dx - a.dx) * (t / len), a.dy + (b.dy - a.dy) * (t / len));
          path.lineTo(
              a.dx + (b.dx - a.dx) * (end / len), a.dy + (b.dy - a.dy) * (end / len));
        }
        t = end;
        on = !on;
      }
    }
    edge(rect.topLeft, rect.topRight);
    edge(rect.topRight, rect.bottomRight);
    edge(rect.bottomRight, rect.bottomLeft);
    edge(rect.bottomLeft, rect.topLeft);
    return path;
  }

  void _paintStroke(Canvas canvas, Size size, InkStroke s) {
    final color = _strokeColor(s);
    if (s.pointCount == 1) {
      // 单点笔迹（点一下）：画圆点
      final p = s.pointAt(0);
      final paint = Paint()
        ..style = PaintingStyle.fill
        ..color = color;
      canvas.drawCircle(
          Offset(p.dx * size.width, p.dy * size.height),
          s.width > 1 ? s.width / 2 : 1,
          paint);
      return;
    }
    if (s.isEmpty) return;
    final path = Path();
    var prev = s.pointAt(0);
    path.moveTo(prev.dx * size.width, prev.dy * size.height);
    for (int i = 1; i < s.pointCount; i++) {
      final cur = s.pointAt(i);
      final mid = Offset((prev.dx + cur.dx) / 2, (prev.dy + cur.dy) / 2);
      path.quadraticBezierTo(
          prev.dx * size.width, prev.dy * size.height,
          mid.dx * size.width, mid.dy * size.height);
      prev = cur;
    }
    path.lineTo(prev.dx * size.width, prev.dy * size.height);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = s.width
      ..color = color;
    canvas.drawPath(path, paint);
  }

  Color _strokeColor(InkStroke s) {
    final c = Color(s.color);
    // 荧光笔半透明（REQ-008 粗头笔，划重点不遮挡内容）
    return s.penType == PenType.highlighter
        ? c.withAlpha((255 * kAnnoHighlighterAlpha).round())
        : c;
  }

  @override
  bool shouldRepaint(_InkPainter oldDelegate) => true;
}
