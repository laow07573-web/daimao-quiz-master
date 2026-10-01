// 首次使用引导回归（v1.28.2）：
//   · 只有首启才插播（GuideService 标记 + 启动页分支），收尾必须落标记
//   · 三页能走通：下一步翻页 → 末页「开始使用」收尾；随时可「跳过」
//   · 系统「减弱动态效果」开启时不演入场，直接给终态
//   · 动效本身真的在动（首帧未完成、播完定格），避免哪天被误删成静态页
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flashcard_app/screens/main_shell.dart';
import 'package:flashcard_app/screens/onboarding_screen.dart';
import 'package:flashcard_app/screens/splash_screen.dart';
import 'package:flashcard_app/services/guide_service.dart';
import 'package:flashcard_app/services/theme_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GuideService.instance.resetCacheForTest();
  });

  Widget host(Widget child) =>
      MaterialApp(theme: ThemeService().themeData, home: child);

  /// 行为类用例先关掉系统动画：引导页有一段持续呼吸的动效，
  /// 开着它 `pumpAndSettle` 永远等不到静止。
  ///
  /// 走的是真实的平台无障碍开关（`MediaQueryData.fromView` 读的就是它），
  /// 因此在 `home` 之外推入的路由同样生效——顺带覆盖了「减弱动态效果」路径。
  /// 动效本身另有用例专门验证（见文件末尾）。
  void reduceMotion(WidgetTester tester) {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }

  /// 从一页「底座」推入引导页：收尾走 pop，需要有东西可返回
  Future<void> openGuide(WidgetTester tester) async {
    await tester.pumpWidget(host(Builder(
      builder: (ctx) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => Navigator.of(ctx).push(
              MaterialPageRoute(builder: (_) => const OnboardingScreen()),
            ),
            child: const Text('打开引导'),
          ),
        ),
      ),
    )));
    await tester.tap(find.text('打开引导'));
    await tester.pumpAndSettle();
  }

  group('GuideService', () {
    test('默认未看过；标记后真的写进存储（清缓存仍为已看过）', () async {
      expect(await GuideService.instance.hasSeen(), isFalse);
      await GuideService.instance.markSeen();
      expect(await GuideService.instance.hasSeen(), isTrue);

      GuideService.instance.resetCacheForTest();
      expect(await GuideService.instance.hasSeen(), isTrue,
          reason: '必须落到存储上，不能只改内存——否则每次启动都会再弹一次');
    });

    test('已有标记能被读到（第二次启动不再插播）', () async {
      SharedPreferences.setMockInitialValues({GuideService.keyGuideSeenV1: true});
      GuideService.instance.resetCacheForTest();
      expect(await GuideService.instance.hasSeen(), isTrue);
    });
  });

  group('启动页分支', () {
    test('首启插播引导，其余直接进主界面', () {
      expect(SplashScreen.nextScreen(firstRun: true), isA<OnboardingScreen>());
      expect(SplashScreen.nextScreen(firstRun: false), isA<MainShell>());
    });
  });

  group('引导页', () {
    testWidgets('三页走通：下一步翻页 → 末页「开始使用」收尾并落标记', (tester) async {
      reduceMotion(tester);
      await openGuide(tester);

      expect(find.text('先导入一份题库'), findsOneWidget);
      expect(find.text('第 1 步 · 共 3 步'), findsOneWidget);
      expect(find.text('下一步'), findsOneWidget);
      expect(find.text('开始使用'), findsNothing);

      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      expect(find.text('然后开始刷题'), findsOneWidget);

      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      expect(find.text('再看数据说话'), findsOneWidget);
      expect(find.text('开始使用'), findsOneWidget);
      expect(find.text('下一步'), findsNothing, reason: '末页不再有「下一步」');

      await tester.tap(find.text('开始使用'));
      await tester.pumpAndSettle();
      // 非首启模式：收尾后返回底座页
      expect(find.text('打开引导'), findsOneWidget);
      expect(await GuideService.instance.hasSeen(), isTrue,
          reason: '收尾必须落标记，否则会被当成首启反复插播');
    });

    testWidgets('「跳过」随时收尾并落标记', (tester) async {
      reduceMotion(tester);
      await openGuide(tester);
      expect(find.text('跳过'), findsOneWidget);

      await tester.tap(find.text('跳过'));
      await tester.pumpAndSettle();
      expect(find.text('打开引导'), findsOneWidget);
      expect(await GuideService.instance.hasSeen(), isTrue);
    });

    testWidgets('首屏文案与要点标签齐备', (tester) async {
      reduceMotion(tester);
      await openGuide(tester);

      expect(find.textContaining('DOCX、PDF、JSON 与题库文件都能导入'), findsOneWidget);
      expect(find.text('示例题库'), findsOneWidget);
      expect(find.text('JSON 题库'), findsOneWidget);
    });

    testWidgets('减弱动态效果：直接给终态，不做入场', (tester) async {
      reduceMotion(tester);
      await tester.pumpWidget(host(const OnboardingScreen()));

      final opacity = tester
          .widget<Opacity>(find
              .ancestor(
                  of: find.text('先导入一份题库'),
                  matching: find.byType(Opacity))
              .first)
          .opacity;
      expect(opacity, 1.0, reason: '关闭动画时应直接定格，不出现半透明中间态');
    });

    testWidgets('动效确实在动：首帧未完成，播完定格为 1', (tester) async {
      await tester.pumpWidget(host(const OnboardingScreen()));
      await tester.pump();

      double titleOpacity() => tester
          .widget<Opacity>(find
              .ancestor(
                  of: find.text('先导入一份题库'),
                  matching: find.byType(Opacity))
              .first)
          .opacity;

      expect(titleOpacity(), lessThan(1.0), reason: '首帧应处于入场过程中');
      await tester.pump(const Duration(milliseconds: 900));
      expect(titleOpacity(), 1.0, reason: '入场结束应定格为完全不透明');

      // 收尾：摘掉页面以停掉持续呼吸的动画，避免留下活跃 ticker
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
