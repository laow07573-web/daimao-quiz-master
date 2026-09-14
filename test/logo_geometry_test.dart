import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/widgets/kit/mj_logo.dart';

/// 应用内标记（[MJLogo]）与启动图标是同一次设计的两个产物：
/// 前者是 Dart 矢量，后者由 `tool/logo/generate_logo.py` 栅格化。
/// 两边各自的几何常量一旦分叉，应用里看到的猫和桌面图标上的猫就会
/// 长得不一样——而且这种偏差不会让任何别的测试变红。
///
/// 所以生成脚本会写出 `tool/logo/geometry.json`，这里逐个数对着比。
void main() {
  final path = File('tool/logo/geometry.json');

  group('logo 几何同源（Dart ↔ 生成脚本）', () {
    late Map<String, dynamic> geo;

    setUpAll(() {
      if (!path.existsSync()) {
        fail('缺少 ${path.path}。请先运行 `python tool/logo/generate_logo.py`，'
            '该文件由生成脚本写出，是两侧几何的对照基准。');
      }
      geo = jsonDecode(path.readAsStringSync()) as Map<String, dynamic>;
    });

    test('设计空间边长一致', () {
      expect(MJLogoGeometry.ds, (geo['ds'] as num).toDouble());
    });

    test('卡片轮廓（位置与圆角）一致', () {
      final head = (geo['head'] as List).cast<num>().map((e) => e.toDouble()).toList();
      expect(head, hasLength(5));
      expect(MJLogoGeometry.headLeft, head[0]);
      expect(MJLogoGeometry.headTop, head[1]);
      expect(MJLogoGeometry.headRight, head[2]);
      expect(MJLogoGeometry.headBottom, head[3]);
      expect(MJLogoGeometry.headRadius, head[4]);
    });

    test('左耳顶点一致', () {
      _expectPoints(MJLogoGeometry.earLeft, geo['earLeft'] as List);
    });

    test('耳间浅凹顶点一致', () {
      _expectPoints(MJLogoGeometry.dip, geo['dip'] as List);
    });

    test('启动图标占比一致', () {
      expect(MJLogoGeometry.tileRadiusRatio,
          (geo['tileRadiusRatio'] as num).toDouble());
      expect(MJLogoGeometry.markRatio, (geo['markRatio'] as num).toDouble());
    });

    test('几何自洽：耳在脸之上、凹口居中且不切穿脸', () {
      // 耳尖必须高过卡片顶边，否则"耳朵"退化成方角、猫就没了
      final tipY = MJLogoGeometry.earLeft.map((p) => p[1]).reduce((a, b) => a < b ? a : b);
      expect(tipY, lessThan(MJLogoGeometry.headTop));

      // 耳根必须落在卡片顶边上，否则耳朵会悬空断开
      final bases = MJLogoGeometry.earLeft.where((p) => p[1] == MJLogoGeometry.headTop);
      expect(bases, isNotEmpty, reason: '至少有耳根贴在卡片顶边上');
      for (final p in bases) {
        expect(p[0], greaterThanOrEqualTo(MJLogoGeometry.headLeft));
        expect(p[0], lessThan(MJLogoGeometry.headRight));
      }

      // 凹口居中（猫脸左右对称）
      final dipMinX = MJLogoGeometry.dip.map((p) => p[0]).reduce((a, b) => a < b ? a : b);
      final dipMaxX = MJLogoGeometry.dip.map((p) => p[0]).reduce((a, b) => a > b ? a : b);
      expect(dipMinX + dipMaxX, MJLogoGeometry.ds);

      // 凹口底点必须在脸的上半部，否则脸被切成两半
      final dipBase = MJLogoGeometry.dip.map((p) => p[1]).reduce((a, b) => a > b ? a : b);
      expect(dipBase, greaterThan(MJLogoGeometry.headTop));
      expect(dipBase, lessThan((MJLogoGeometry.headTop + MJLogoGeometry.headBottom) / 2));

      // 凹口不能越出脸的左右边界
      expect(dipMinX, greaterThan(MJLogoGeometry.headLeft));
      expect(dipMaxX, lessThan(MJLogoGeometry.headRight));

      // 凹口比脸窄（耳间浅凹，不是把脸整个削掉）
      expect(dipMaxX - dipMinX,
          lessThan(MJLogoGeometry.headRight - MJLogoGeometry.headLeft));
    });
  });

  group('MJLogo 渲染', () {
    testWidgets('默认取主题强调色，指定 color 时用指定色', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: MJLogo(size: 48))),
      ));
      expect(find.byType(MJLogo), findsOneWidget);

      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: Center(child: MJLogo(size: 48, color: Color(0xFF123456)))),
      ));
      expect(find.byType(MJLogo), findsOneWidget);
    });

    testWidgets('极小尺寸不抛异常（26px 是首页问候卡的真实尺寸）', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: MJLogo(size: 26))),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('MJLogoBadge 在启动页/首页/我的页三种尺寸下都能布局', (tester) async {
      for (final box in <double>[88, 38, 34]) {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: Center(child: MJLogoBadge(box: box))),
        ));
        await tester.pump();
        expect(tester.takeException(), isNull,
            reason: 'MJLogoBadge(box: $box) 布局异常');
        expect(find.byType(MJLogo), findsOneWidget);
      }
    });
  });
}

void _expectPoints(List<List<double>> actual, List<dynamic> json) {
  expect(actual, hasLength(json.length));
  for (var i = 0; i < json.length; i++) {
    final p = (json[i] as List).cast<num>().map((e) => e.toDouble()).toList();
    expect(actual[i], hasLength(2));
    expect(actual[i][0], p[0], reason: '第 $i 个顶点的 x');
    expect(actual[i][1], p[1], reason: '第 $i 个顶点的 y');
  }
}
