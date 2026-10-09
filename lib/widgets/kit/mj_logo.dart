import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/theme_service.dart';

/// Approved cat-ear paper mark, fitted without distorting its 544×512 viewBox.
class MJLogo extends StatelessWidget {
  const MJLogo({super.key, this.size = 24, this.color});

  final double size;

  /// Null follows the current theme accent, including the ink theme.
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _MJLogoPainter(color ?? AppThemeColors.of(context).accent),
        ),
      );
}

/// Exact approved SVG coordinates; generator exports the same commands to JSON.
class MJLogoGeometry {
  const MJLogoGeometry._();
  static const double width = 544;
  static const double height = 512;
  static const double tileRadiusRatio = 0.22;
  static const double markRatio = 1.26;
  static const Color accent = Color(0xFF5E6AD2);
  static const Color fold = Color(0xFFCBCFF4);
  static const Color ink = Color(0xFF0B0C0E);
  static const double eyeWidth = 22;
  static const double mouthWidth = 12;
  static const double lineWidth = 14;
  static const List<List<Object>> body = [
    ['M', 124, 178],
    ['L', 124, 84],
    ['Q', 124, 66, 139, 77],
    ['L', 236, 146],
    ['L', 308, 146],
    ['L', 405, 77],
    ['Q', 420, 66, 420, 84],
    ['L', 420, 342],
    ['L', 326, 436],
    ['L', 162, 436],
    ['Q', 124, 436, 124, 398],
    ['Z'],
  ];
  static const List<List<Object>> corner = [
    ['M', 326, 436],
    ['L', 326, 374],
    ['Q', 326, 342, 358, 342],
    ['L', 420, 342],
    ['Z'],
  ];
  static const List<List<Object>> eyes = [
    ['M', 190, 227],
    ['L', 224, 227],
    ['M', 320, 227],
    ['L', 354, 227],
  ];
  static const List<List<Object>> mouth = [
    ['M', 259, 264],
    ['L', 272, 277],
    ['L', 285, 264],
  ];
  static const List<List<Object>> lines = [
    ['M', 190, 329],
    ['L', 267, 329],
    ['M', 190, 367],
    ['L', 240, 367],
  ];

  /// Select whichever foreground has greater WCAG contrast against the fill.
  static Color detailColor(Color fill) {
    final luminance = fill.computeLuminance();
    final whiteContrast = 1.05 / (luminance + 0.05);
    final inkContrast = (luminance + 0.05) / (ink.computeLuminance() + 0.05);
    return whiteContrast >= inkContrast ? Colors.white : ink;
  }

  static Color foldColor(Color fill) =>
      fill == accent ? fold : Color.lerp(fill, detailColor(fill), 0.70)!;

  static Path path(List<List<Object>> commands) {
    final result = Path();
    for (final command in commands) {
      final p = command.skip(1).map((v) => (v as num).toDouble()).toList();
      switch (command.first) {
        case 'M':
          result.moveTo(p[0], p[1]);
          break;
        case 'L':
          result.lineTo(p[0], p[1]);
          break;
        case 'Q':
          result.quadraticBezierTo(p[0], p[1], p[2], p[3]);
          break;
        case 'Z':
          result.close();
          break;
      }
    }
    return result;
  }
}

class _MJLogoPainter extends CustomPainter {
  _MJLogoPainter(this.color);
  final Color color;
  static final _body = MJLogoGeometry.path(MJLogoGeometry.body);
  static final _corner = MJLogoGeometry.path(MJLogoGeometry.corner);
  static final _eyes = MJLogoGeometry.path(MJLogoGeometry.eyes);
  static final _mouth = MJLogoGeometry.path(MJLogoGeometry.mouth);
  static final _lines = MJLogoGeometry.path(MJLogoGeometry.lines);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(
        size.width / MJLogoGeometry.width, size.height / MJLogoGeometry.height);
    if (scale <= 0) return;
    canvas.save();
    canvas.translate((size.width - MJLogoGeometry.width * scale) / 2,
        (size.height - MJLogoGeometry.height * scale) / 2);
    canvas.scale(scale);
    canvas.drawPath(_body, Paint()..color = color);
    canvas.drawPath(_corner, Paint()..color = MJLogoGeometry.foldColor(color));
    final stroke = Paint()
      ..color = MJLogoGeometry.detailColor(color)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(_eyes, stroke..strokeWidth = MJLogoGeometry.eyeWidth);
    canvas.drawPath(_mouth, stroke..strokeWidth = MJLogoGeometry.mouthWidth);
    canvas.drawPath(_lines, stroke..strokeWidth = MJLogoGeometry.lineWidth);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MJLogoPainter oldDelegate) => oldDelegate.color != color;
}

/// 品牌标记（不垫底色、不加描边）。
///
/// 2026-10-07 真机反馈：此前这里会给标记垫一层描边方块（surfaceAlt 底 +
/// 1px 描边 + 内边距），于是启动页与首页问候卡上的标记被框住，实际绘制尺寸
/// 还要再扣掉内边距，看起来又小又闷。现在直接绘制标记本身，[box] 就是标记
/// 的实际边长，不再有承载它的那一层。
///
/// 若某处确实需要「有底色的方块」（例如背景与标记对比不足），请在该处自己
/// 包一层 [MJSurface]，而不是让品牌标记固定带框。
class MJLogoBadge extends StatelessWidget {
  const MJLogoBadge({super.key, this.box = 34});

  /// 标记边长（不再是「外框边长」）。
  final double box;

  @override
  Widget build(BuildContext context) => MJLogo(size: box);
}
