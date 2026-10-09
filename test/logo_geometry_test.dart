import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/services/theme_service.dart';
import 'package:flashcard_app/widgets/kit/mj_logo.dart';

void main() {
  final geo = jsonDecode(File('tool/logo/geometry.json').readAsStringSync())
      as Map<String, dynamic>;

  test('all approved SVG commands and stroke widths match generated resources',
      () {
    expect(MJLogoGeometry.width, geo['width']);
    expect(MJLogoGeometry.height, geo['height']);
    expect(MJLogoGeometry.body, geo['body']);
    expect(MJLogoGeometry.corner, geo['corner']);
    expect(MJLogoGeometry.eyes, geo['eyes']);
    expect(MJLogoGeometry.mouth, geo['mouth']);
    expect(MJLogoGeometry.lines, geo['lines']);
    expect(MJLogoGeometry.eyeWidth, geo['eyeWidth']);
    expect(MJLogoGeometry.mouthWidth, geo['mouthWidth']);
    expect(MJLogoGeometry.lineWidth, geo['lineWidth']);
    expect(MJLogoGeometry.tileRadiusRatio, geo['tileRadiusRatio']);
    expect(MJLogoGeometry.markRatio, geo['markRatio']);
    expect(geo['accent'], '#5E6AD2');
    expect(geo['fold'], '#CBCFF4');
    // Anchor to the approved source, not just two copies of the same constants.
    expect(MJLogoGeometry.width, 544);
    expect(MJLogoGeometry.height, 512);
    expect(MJLogoGeometry.body[2], ['Q', 124, 66, 139, 77]);
    expect(MJLogoGeometry.corner[2], ['Q', 326, 342, 358, 342]);
    expect(MJLogoGeometry.mouth, [
      ['M', 259, 264],
      ['L', 272, 277],
      ['L', 285, 264],
    ]);
  });

  test('adaptive geometry 留在可见方框内，且按配置安全半径留余量', () {
    final ratio = (geo['fgRatio'] as num).toDouble();
    final canvasDp = (geo['canvasDp'] as num).toDouble();
    final safeRadius = (geo['safeZoneDp'] as num) / 2;
    final margin = (geo['safeMargin'] as num).toDouble();
    // 每个 viewBox 单位对应多少 dp（自适应前景按 108dp 画布铺开）
    final scaleDp = ratio * canvasDp / MJLogoGeometry.width;
    // 2026-10-07 有意把安全半径从 66/2 放到 80/2（见 generate_logo.py 注释）：
    // 严格圆形遮罩会切掉耳尖约 2dp，换取标记在图标里明显变大。
    // 真正不能破的底线是：所有极值点都在「可见 72dp 方框」内——主流圆角方
    // 与超椭圆遮罩至少露出这么大，落在这个框里就不会被裁。
    const visibleHalfDp = 72 / 2;
    for (final command in MJLogoGeometry.body) {
      final p = command.skip(1).cast<num>().toList();
      for (var i = 0; i < p.length; i += 2) {
        final dx = (p[i] - MJLogoGeometry.width / 2) * scaleDp;
        final dy = (p[i + 1] - MJLogoGeometry.height / 2) * scaleDp;
        expect(math.sqrt(dx * dx + dy * dy),
            lessThanOrEqualTo(safeRadius * margin + 1e-9),
            reason: '超出配置的安全半径');
        expect(dx.abs(), lessThanOrEqualTo(visibleHalfDp),
            reason: '越出可见方框左/右边界，圆角方遮罩会裁到');
        expect(dy.abs(), lessThanOrEqualTo(visibleHalfDp),
            reason: '越出可见方框上/下边界，圆角方遮罩会裁到');
      }
    }
  });

  test('face contrasts against clear, both ink accents and custom light fills',
      () {
    for (final color in [
      MJLogoGeometry.accent,
      const Color(0xFF18181B),
      const Color(0xFFE8E8EA),
      Colors.white,
      const Color(0xFF123456)
    ]) {
      final a = color.computeLuminance();
      final b = MJLogoGeometry.detailColor(color).computeLuminance();
      expect((math.max(a, b) + .05) / (math.min(a, b) + .05),
          greaterThanOrEqualTo(4.5));
    }
    expect(MJLogoGeometry.detailColor(MJLogoGeometry.accent), Colors.white);
    expect(MJLogoGeometry.detailColor(const Color(0xFFE8E8EA)),
        MJLogoGeometry.ink);
    expect(
        MJLogoGeometry.foldColor(MJLogoGeometry.accent), MJLogoGeometry.fold);
  });

  for (final fill in <Color?>[
    null,
    MJLogoGeometry.accent,
    const Color(0xFF18181B),
    const Color(0xFFE8E8EA)
  ]) {
    testWidgets('painter pixels preserve paper, fold, face and lines ($fill)',
        (tester) async {
      await tester.pumpWidget(
          MaterialApp(home: Center(child: MJLogo(size: 544, color: fill))));
      final logo = find.byType(MJLogo);
      final context = tester.element(logo);
      final expectedFill = fill ?? AppThemeColors.of(context).accent;
      final paint = tester.widget<CustomPaint>(
          find.descendant(of: logo, matching: find.byType(CustomPaint)));
      final recorder = ui.PictureRecorder();
      paint.painter!.paint(Canvas(recorder), const Size(544, 544));
      final picture = recorder.endRecording();
      final image = (await tester.runAsync(() => picture.toImage(544, 544)))!;
      final bytes = (await tester.runAsync(
          () => image.toByteData(format: ui.ImageByteFormat.rawRgba)))!;
      Color pixel(int x, int y) {
        // 512-high viewBox is centered vertically in the 544 square.
        final i = ((y + 16) * 544 + x) * 4;
        return Color.fromARGB(bytes.getUint8(i + 3), bytes.getUint8(i),
            bytes.getUint8(i + 1), bytes.getUint8(i + 2));
      }

      expect(pixel(150, 210), expectedFill);
      expect(pixel(350, 375), MJLogoGeometry.foldColor(expectedFill));
      for (final p in [
        (200, 227),
        (340, 227),
        (272, 274),
        (220, 329),
        (220, 367)
      ]) {
        expect(pixel(p.$1, p.$2), MJLogoGeometry.detailColor(expectedFill));
      }
      expect(pixel(272, 100).alpha, 0); // between ears is empty
      expect(pixel(400, 410).alpha, 0); // folded-away paper corner is empty
      image.dispose();
      picture.dispose();
    });
  }

  testWidgets('public APIs lay out at all existing sizes, including zero',
      (tester) async {
    for (final size in <double>[0, 21, 26, 48, 68, 88]) {
      await tester.pumpWidget(MaterialApp(home: MJLogo(size: size)));
      expect(tester.takeException(), isNull);
    }
    for (final box in <double>[34, 38, 88]) {
      await tester
          .pumpWidget(MaterialApp(home: Center(child: MJLogoBadge(box: box))));
      expect(find.byType(MJLogo), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('MJLogoBadge 直接绘制标记：不加底色方块/描边，尺寸即 box', (tester) async {
    // 2026-10-07 真机反馈：此前标记被一圈描边方块框住、还要扣内边距，
    // 看起来又小又闷。这里锁住「不再有承载层」这一行为，防止回退。
    for (final box in <double>[34, 42, 104]) {
      await tester.pumpWidget(
          MaterialApp(home: Center(child: MJLogoBadge(box: box))));
      expect(tester.takeException(), isNull);
      // 标记占满 box（不再被 padding 扣小）
      final logoSize = tester.getSize(find.byType(MJLogo));
      expect(logoSize.width, box, reason: 'box=$box 时标记宽度应等于 box');
      expect(logoSize.height, box, reason: 'box=$box 时标记高度应等于 box');
      // 外层不再有 Container/DecoratedBox 之类的「框」
      expect(
          find.descendant(
              of: find.byType(MJLogoBadge),
              matching: find.byType(DecoratedBox)),
          findsNothing,
          reason: '品牌标记不应再有底色方块或描边');
    }
  });
}
