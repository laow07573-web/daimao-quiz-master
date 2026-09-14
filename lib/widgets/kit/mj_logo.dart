import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/theme_service.dart';
import '../../utils/design_tokens.dart';
import 'mj_kit.dart';

/// 猫卷标记（MaoJuan mark）——「卡片/书卷轮廓 + 猫耳」。
///
/// 为什么是这个形状：猫卷的「卷」是书卷，卡片形轮廓（圆角矩形）既呼应
/// 「卷」，又天然贴合 [MaoRadius] 的圆角语言；两只三角耳 + 耳间浅凹给出
/// 「猫」。全图只有两个形状元素，缩到 21px 仍可辨认——这是原先那张
/// 「MaoJuan 字标 + 猫剪影 + Study Smarter 副标」三重要素的位图做不到的。
///
/// 用矢量而非位图：应用内三处尺寸跨度大（26 / 68 / 88px），且标记要跟随
/// 主题强调色。位图缩放在小尺寸会糊，也无法随主题变色。
///
/// 几何与 `tool/logo/generate_logo.py` 同源：都由 100×100 设计空间的同一组
/// 常量推导（圆角矩形 ∪ 双耳 △ − 耳间浅凹 ▽）。改这里必须同步改那里，
/// 否则应用内标记与启动图标会长得不一样。
class MJLogo extends StatelessWidget {
  const MJLogo({super.key, this.size = 24, this.color});

  /// 外接正方形边长。标记本身约占其 84% 宽 / 92% 高（四周留白是设计的一部分）。
  final double size;

  /// 标记颜色；null 时取当前主题强调色。
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _MJLogoPainter(color ?? AppThemeColors.of(context).accent),
        isComplex: false,
      ),
    );
  }
}

/// 100×100 设计空间的几何常量。
///
/// 公开而非私有，是为了让 `test/logo_geometry_test.dart` 能对着
/// `tool/logo/geometry.json`（由生成脚本写出）逐个数校验——应用内标记与
/// Android/Windows 启动图标必须永远是同一个形状。
class MJLogoGeometry {
  const MJLogoGeometry._();

  /// 设计空间边长。
  static const double ds = 100;

  /// 卡片/书卷轮廓（左、上、右、下、圆角）。
  static const double headLeft = 11;
  static const double headTop = 34;
  static const double headRight = 89;
  static const double headBottom = 92;
  static const double headRadius = 14;

  /// 左耳三角（三个顶点，顺时针）；右耳是它的水平镜像。
  static const List<List<double>> earLeft = [
    [17, 34],
    [23, 5],
    [47, 34],
  ];

  /// 耳间浅凹（从头顶挖掉的三角）。
  static const List<List<double>> dip = [
    [43, 32],
    [57, 32],
    [50, 43],
  ];

  /// 启动图标：方块圆角占比 / 标记占比。
  static const double tileRadiusRatio = 0.22;
  static const double markRatio = 0.68;
}

class _MJLogoPainter extends CustomPainter {
  _MJLogoPainter(this.color);

  final Color color;

  static const double _ds = MJLogoGeometry.ds;
  static const Rect _head = Rect.fromLTRB(
      MJLogoGeometry.headLeft,
      MJLogoGeometry.headTop,
      MJLogoGeometry.headRight,
      MJLogoGeometry.headBottom);
  static const double _headRadius = MJLogoGeometry.headRadius;

  // 从 MJLogoGeometry 派生（不重复字面量）：常量表是唯一来源，
  // 测试校验的也就是绘制实际用的这份数。
  static final List<Offset> _earLeft = [
    for (final p in MJLogoGeometry.earLeft) Offset(p[0], p[1]),
  ];
  static final List<Offset> _dip = [
    for (final p in MJLogoGeometry.dip) Offset(p[0], p[1]),
  ];

  /// 设计空间内的最终路径，只构建一次。
  static final Path _design = _buildDesignPath();

  static Path _buildDesignPath() {
    final head = Path()
      ..addRRect(RRect.fromRectAndRadius(_head, const Radius.circular(_headRadius)));
    final ears = Path()
      ..addPolygon(_earLeft, true)
      ..addPolygon(
          [for (final o in _earLeft) Offset(_ds - o.dx, o.dy)], true);
    // 顺序不能反：先并耳再挖凹。反过来的话凹口会被紧接着的耳的填充盖回去，
    // 于是头顶变成一条平边，猫就没了。
    final solid = Path.combine(PathOperation.union, head, ears);
    final dip = Path()..addPolygon(_dip, true);
    return Path.combine(PathOperation.difference, solid, dip);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height) / _ds;
    if (s <= 0) return;
    canvas.drawPath(
      _design.transform(Matrix4.diagonal3Values(s, s, 1).storage),
      Paint()
        ..color = color
        ..isAntiAlias = true
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_MJLogoPainter old) => old.color != color;
}

/// 标记配一个发丝描边方块底（启动页 / 问候卡里的「品牌位」）。
///
/// 三处使用（启动页 88 / 首页 34 / 我的页 38）尺寸不同但必须是同一处理，
/// 所以收在这里，避免各页自己拼 Container 拼出三种样子。
class MJLogoBadge extends StatelessWidget {
  const MJLogoBadge({
    super.key,
    this.box = 34,
    this.padding = MaoSpace.xxs,
    this.radius,
    this.tone = MJTone.alt,
  });

  /// 方块边长。
  final double box;

  /// 方块内边距（标记尺寸 = box - 2 × padding）。
  final double padding;

  /// 圆角，默认按尺寸在 control / large 之间取合适值。
  final double? radius;

  /// 底色层级：alt（次级面板）或 base。
  final MJTone tone;

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    final r = radius ?? (box >= 60 ? MaoRadius.large : MaoRadius.control);
    return Container(
      width: box,
      height: box,
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: tone == MJTone.base ? ac.surface : ac.surfaceAlt,
        borderRadius: BorderRadius.circular(r),
        border: Border.all(color: ac.border, width: MaoLine.width),
      ),
      child: MJLogo(size: box - padding * 2),
    );
  }
}
