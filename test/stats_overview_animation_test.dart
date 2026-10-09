import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flashcard_app/screens/stats_tab.dart';
import 'package:flashcard_app/services/app_state.dart';
import 'package:flashcard_app/services/theme_service.dart';

/// 2026-10-08 真机反馈：统计页上下滑动时，概览里的数字会重新播放滚动动画。
///
/// 根因：概览卡在 ListView 里，滚出屏幕会被回收、滚回来重新挂载；当“入场动画”
/// 写在数字子组件（挂载即从 0 演一遍）里时，每次重新挂载都会重播。
///
/// 修法：概览数字由页面持有的 `AnimationController` 驱动进度，初始值 1（终态），
/// 只有点「本周/本月/全部」时才 `forward(from: 0)`。因此：
///   · 首次加载与滚动重挂载都必须立刻显示终值（进度 1）；
///   · 只有周期切换期间，读数才按进度缩放。
///
/// 这里不碰数据库（概览卡首帧是骨架屏，造数测试易在假异步区挂起），
/// 直接对驱动读数的纯函数做断言。
void main() {
  group('概览读数按进度缩放（滚动不重播动画的核心保证）', () {
    test('进度 1（默认/重挂载）直接是终值，绝不回到 0', () {
      expect(overviewReadoutValue(7, 1), 7);
      expect(overviewReadoutValue(0, 1), 0);
      expect(overviewReadoutValue(4471, 1), 4471);
      expect(overviewReadoutValue(60.5, 1), 60.5);
    });

    test('只有周期切换把进度从 0 推上来时，读数才滚动', () {
      expect(overviewReadoutValue(100, 0), 0);
      expect(overviewReadoutValue(100, 0.5), 50);
      expect(overviewReadoutValue(7, 0.5), 3.5);
    });

    test('进度越界被夹住，不会出现负值或超过终值', () {
      expect(overviewReadoutValue(100, 1.4), 100);
      expect(overviewReadoutValue(100, -0.3), 0);
    });
  });

  testWidgets('统计页首帧渲染骨架屏且不抛异常（概览数据未到位时不演数字）', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: AppState()),
        ChangeNotifierProvider<ThemeService>.value(value: ThemeService()),
      ],
      child: MaterialApp(
        theme: ThemeService().themeData,
        home: const Scaffold(body: StatsTab()),
      ),
    ));
    await tester.pump();

    expect(find.byType(StatsTab), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
