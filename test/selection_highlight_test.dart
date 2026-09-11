import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/widgets/annotation_canvas.dart';
import 'package:flashcard_app/widgets/annotation_controller.dart';

/// 选中框渲染像素级验证（v1.28：虚线描边 + 强调色底，跟随主题）。
/// 通过 RenderRepaintBoundary.toImage() 抓取画布渲染像素，
/// 直接断言选中笔迹后虚线框/底色像素存在（不依赖模拟器坐标）。
Future<int> _countBluePixels(WidgetTester tester, Finder finder) async {
  final boundary = tester.renderObject(find
      .descendant(of: finder, matching: find.byType(RepaintBoundary))
      .first) as RenderRepaintBoundary;
  var count = 0;
  await tester.runAsync(() async {
    final img = await boundary.toImage(pixelRatio: 1.0);
    final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    final bytes = bd!.buffer.asUint32List();
    for (final px in bytes) {
      final r = px & 0xFF;
      final b = (px >> 16) & 0xFF;
      final a = (px >> 24) & 0xFF;
      // v1.28 选中框用主题强调色。测试环境未挂 AppThemeColors，
      // of() 兜底取 Material 默认 primary（紫色系，蓝分量显著高于红）。
      // 判据：不透明 + 蓝分量明显高于红（笔迹的红/绿/黑均不满足）
      if (a > 0 && b > r + 30) count++;
    }
    img.dispose();
  });
  return count;
}

void main() {
  testWidgets('选中笔迹后渲染虚线框 + 强调色底（像素级）', (tester) async {
    final controller = AnnotationController();
    // 造一条笔迹（中间偏左）
    controller.beginStroke(const Offset(0.3, 0.4), 1.0);
    controller.extendStroke(const Offset(0.5, 0.5), 1.0);
    controller.extendStroke(const Offset(0.6, 0.45), 1.0);
    controller.endStroke();
    expect(controller.strokes.length, 1);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            height: 400,
            child: AnnotationCanvas(controller: controller, interactive: false),
          ),
        ),
      ),
    ));
    await tester.pump();

    // 未选中：无选中框像素
    final before = await _countBluePixels(tester, find.byType(AnnotationCanvas));
    expect(before, 0, reason: '未选中时不应有选中框像素');

    // 选中该笔迹
    controller.tool = AnnoTool.select;
    const size = Size(400, 400);
    final hit =
        controller.selectAt(const Offset(0.45, 0.45).scale(size.width, size.height), size);
    expect(hit, isTrue, reason: '应命中笔迹');
    expect(controller.selectedIndex, 0);
    await tester.pump();

    // 选中后：出现强调色选中框像素（虚线描边 + 半透明底）
    final after = await _countBluePixels(tester, find.byType(AnnotationCanvas));
    expect(after, greaterThan(100),
        reason: '选中后应渲染虚线框+强调色底（像素数 > 100）');

    controller.dispose();
  });
}
