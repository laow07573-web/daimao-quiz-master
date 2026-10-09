import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flashcard_app/screens/main_shell.dart';
import 'package:flashcard_app/screens/splash_screen.dart';
import 'package:flashcard_app/services/guide_service.dart';
import 'package:flashcard_app/services/theme_service.dart';
import 'package:flashcard_app/widgets/guide/guide_anchor.dart';
import 'package:flashcard_app/widgets/guide/guide_controller.dart';
import 'package:flashcard_app/widgets/guide/guide_host.dart';
import 'package:flashcard_app/widgets/guide/guide_steps.dart';

/// 按下真实控件时记录一下——用来验证「洞里的控件真的点得穿」
typedef TapLog = void Function(String where);

/// 二级页：模拟「导入题库 / 开始刷题弹窗」这类被 push 出来的页面。
/// 引导必须能跟进来继续指（这是本文件的重点之一）。
class _SubPage extends StatelessWidget {
  const _SubPage({this.dupId, this.onTap});

  /// 非空时再挂一个与外壳同 id 的锚点，用来验证同 id 双实例不撞 GlobalKey
  final String? dupId;
  final TapLog? onTap;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('二级页')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GuideAnchor(
              id: 'sub1',
              child: SizedBox(
                width: 240,
                height: 64,
                child: TextButton(
                  onPressed: () => onTap?.call('sub1'),
                  child: const Text('二级页按钮'),
                ),
              ),
            ),
            if (dupId != null)
              GuideAnchor(
                id: dupId!,
                child: SizedBox(
                  width: 240,
                  height: 64,
                  child: TextButton(
                    onPressed: () => onTap?.call('sub-dup'),
                    child: const Text('二级重复'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 引导测试宿主 = 一屏「真实界面」：三个按钮 + 一个推二级页的入口
class _Host extends StatelessWidget {
  const _Host({required this.controller, this.onTap, this.dupOnShell = false});

  final GuideController controller;
  final TapLog? onTap;
  final bool dupOnShell;

  Widget _box(String id, String label, {VoidCallback? onPressed}) => GuideAnchor(
        id: id,
        child: SizedBox(
          width: double.infinity,
          height: 64,
          child: Center(
            child: TextButton(
              onPressed: onPressed ?? () => onTap?.call(id),
              child: Text(label),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _box('a1', '第一按钮'),
          _box('a2', '第二按钮'),
          if (dupOnShell) _box('dup', '外壳重复'),
          _box('go', '进二级页', onPressed: () {
            Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => _SubPage(dupId: 'dup', onTap: onTap),
            ));
          }),
          const Spacer(),
          // 模拟底部导航：点它 = 用户自己切到了「开始」页
          _box('a3', '去开始页', onPressed: () => controller.setCurrentTab(1)),
        ],
      ),
    );
  }
}

const List<GuideStep> _twoSteps = [
  GuideStep(title: '第一步', body: '说明一', anchorId: 'a1'),
  GuideStep(title: '第二步', body: '说明二', anchorId: 'a2'),
];

/// 减少动效：让 AnimatedPositioned / 淡入都变成 0 时长，断言不看动画时序
void reduceMotion(WidgetTester tester) {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

/// 建树（引导宿主挂在 Navigator 之上）+ 启动引导 + 等「高亮洞落定」：
/// 首帧后测一次、第二次量到同一矩形才落定（躲开位移），故多 pump 几轮。
Future<GuideController> pumpHost(
  WidgetTester tester,
  List<GuideStep> steps, {
  TapLog? onTap,
  bool dupOnShell = false,
}) async {
  final controller = GuideController(steps: steps);
  await tester.pumpWidget(MaterialApp(
    theme: ThemeService().themeData,
    navigatorObservers: [GuideRouteObserver(controller)],
    builder: (context, child) =>
        GuideHost(controller: controller, child: child ?? const SizedBox()),
    home: _Host(controller: controller, onTap: onTap, dupOnShell: dupOnShell),
  ));
  await tester.pump();
  controller.start();
  await tester.pump();
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
  return controller;
}

/// 再等几轮：用于「按了下一步 / 点了高亮处」之后等高亮重新落定
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

/// 引导会留一个跟随滚动的周期巡检定时器；测试收尾必须把树拆掉再销毁控制器
Future<void> disposeHost(WidgetTester tester, GuideController controller) async {
  await tester.pumpWidget(const SizedBox.shrink());
  controller.dispose();
}

void main() {
  group('GuideService', () {
    test('默认未看过；markSeen 后持久化', () async {
      SharedPreferences.setMockInitialValues({});
      GuideService.instance.resetCacheForTest();

      expect(await GuideService.instance.hasSeen(), isFalse);
      await GuideService.instance.markSeen();
      GuideService.instance.resetCacheForTest();
      expect(await GuideService.instance.hasSeen(), isTrue);
    });

    test('存储里已有标记时直接返回已看过', () async {
      SharedPreferences.setMockInitialValues(
          {GuideService.keyGuideSeenV2: true});
      GuideService.instance.resetCacheForTest();

      expect(await GuideService.instance.hasSeen(), isTrue);
    });
  });

  group('SplashScreen 首启分流', () {
    test('首启 → 主壳并插播引导；老用户 → 主壳不插播', () {
      final first = SplashScreen.nextScreen(firstRun: true) as MainShell;
      expect(first.startTour, isTrue);

      final again = SplashScreen.nextScreen(firstRun: false) as MainShell;
      expect(again.startTour, isFalse);
    });
  });

  group('GuideTour 互动式引导', () {
    testWidgets('高亮真实控件：洞里的真实按钮照常可点', (tester) async {
      reduceMotion(tester);
      final taps = <String>[];
      final controller = await pumpHost(tester, _twoSteps, onTap: taps.add);

      expect(find.text('第 1 步 / 共 2 步'), findsOneWidget);
      expect(find.text('第一步'), findsOneWidget);

      // 高亮处没有被遮罩盖住：点下去命中的是真实控件
      await tester.tap(find.text('第一按钮'));
      await tester.pump();
      expect(taps, ['a1']);

      await disposeHost(tester, controller);
    });

    testWidgets('下一步：洞跟着换到第二个目标，两处都能点', (tester) async {
      reduceMotion(tester);
      final taps = <String>[];
      final controller = await pumpHost(tester, _twoSteps, onTap: taps.add);

      await tester.tap(find.text('下一步'));
      await settle(tester);

      expect(find.text('第二步'), findsOneWidget);
      await tester.tap(find.text('第二按钮'));
      await tester.pump();
      expect(taps, ['a2']);

      await disposeHost(tester, controller);
    });

    testWidgets('跳过：结束引导、落「已看过」标记，真实界面留着', (tester) async {
      SharedPreferences.setMockInitialValues({});
      GuideService.instance.resetCacheForTest();
      reduceMotion(tester);
      final controller = await pumpHost(tester, _twoSteps);

      await tester.tap(find.text('跳过'));
      await tester.pump();

      expect(controller.active, isFalse);
      expect(find.text('第一步'), findsNothing);
      expect(find.text('第一按钮'), findsOneWidget);
      expect(find.text('第二按钮'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 50));
      expect(await GuideService.instance.hasSeen(), isTrue);

      await disposeHost(tester, controller);
    });

    testWidgets('末步主按钮收尾（nextLabel）', (tester) async {
      reduceMotion(tester);
      final controller = await pumpHost(tester, const [
        GuideStep(
            title: '唯一步骤', body: '说明', anchorId: 'a1', nextLabel: '开始使用'),
      ]);

      expect(find.text('开始使用'), findsOneWidget);
      await tester.tap(find.text('开始使用'));
      await tester.pump();

      expect(controller.active, isFalse);
      expect(find.text('唯一步骤'), findsNothing);

      await disposeHost(tester, controller);
    });

    testWidgets('用户自己点到目标 Tab 时自动前进', (tester) async {
      reduceMotion(tester);
      final controller = await pumpHost(tester, const [
        GuideStep(title: '点亮底部开始', body: '说明', anchorId: 'a3', autoAdvanceTab: 1),
        GuideStep(title: '第二步', body: '说明二', anchorId: 'a2'),
      ]);

      expect(find.text('点亮底部开始'), findsOneWidget);
      // 真实操作本身就是推进器：点高亮处的「去开始页」，引导自动进下一步
      await tester.tap(find.text('去开始页'));
      await settle(tester);

      expect(find.text('第二步'), findsOneWidget);

      await disposeHost(tester, controller);
    });

    testWidgets('锚点不存在：退化成居中气泡，说明照讲、不卡住、不崩', (tester) async {
      reduceMotion(tester);
      final controller = await pumpHost(tester, const [
        GuideStep(title: '缺锚点的步骤', body: '说明', anchorId: 'not.exists'),
      ]);

      expect(find.text('缺锚点的步骤'), findsOneWidget);
      expect(find.text('点高亮处继续'), findsOneWidget);

      // 重试预算用尽后依然在（说明不会被撤掉）
      for (var i = 0; i < 45; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('缺锚点的步骤'), findsOneWidget);

      await disposeHost(tester, controller);
    });

    testWidgets('没有锚点的欢迎步：居中气泡 + 开始按钮可推进', (tester) async {
      reduceMotion(tester);
      final controller = await pumpHost(tester, const [
        GuideStep(title: '一分钟上手猫卷', body: '说明', nextLabel: '开始'),
        GuideStep(title: '第二步', body: '说明二', anchorId: 'a2'),
      ]);

      expect(find.text('一分钟上手猫卷'), findsOneWidget);
      expect(find.text('读完点右边继续'), findsOneWidget);

      await tester.tap(find.text('开始'));
      await settle(tester);
      expect(find.text('第二步'), findsOneWidget);

      await disposeHost(tester, controller);
    });
  });

  group('引导跨页面继续（用户点高亮处跳进二级页面）', () {
    const steps = [
      GuideStep(title: '第一步：点这个入口', body: '说明', anchorId: 'go'),
      GuideStep(title: '二级页里的引导', body: '说明', anchorId: 'sub1'),
    ];

    testWidgets('点高亮处 push 二级页后：引导跟进来，高亮二级页里的控件', (tester) async {
      reduceMotion(tester);
      final taps = <String>[];
      final controller = await pumpHost(tester, steps, onTap: taps.add);

      // 第 1 步的洞打在「进二级页」上，点进去
      expect(find.text('第一步：点这个入口'), findsOneWidget);
      await tester.tap(find.text('进二级页'));
      await settle(tester);

      // 引导没断：第 2 步已经落在二级页里，并且真的指到了那个控件
      expect(find.text('二级页里的引导'), findsOneWidget);
      expect(controller.index, 1);
      expect(find.text('第 2 步 / 共 2 步'), findsOneWidget);

      // 二级页里高亮的控件同样点得穿（洞打在它上面，而不是被遮罩盖住）
      await tester.tap(find.text('二级页按钮'));
      await tester.pump();
      expect(taps, ['sub1']);

      await disposeHost(tester, controller);
    });

    testWidgets('末步做完真实操作（跳走）即收尾并落「已看过」', (tester) async {
      SharedPreferences.setMockInitialValues({});
      GuideService.instance.resetCacheForTest();
      reduceMotion(tester);
      final controller = await pumpHost(tester, const [
        GuideStep(title: '最后一步：开始刷题', body: '说明', anchorId: 'go'),
      ]);

      await tester.tap(find.text('进二级页'));
      await settle(tester);

      expect(controller.active, isFalse);
      expect(find.text('最后一步：开始刷题'), findsNothing);
      await tester.pump(const Duration(milliseconds: 50));
      expect(await GuideService.instance.hasSeen(), isTrue);

      await disposeHost(tester, controller);
    });

    testWidgets('同 id 双实例不撞 GlobalKey，且取最上层那一个', (tester) async {
      reduceMotion(tester);
      final taps = <String>[];
      // 错题本空态的「去刷题」会 pushReplacement 出第二个开始页：
      // 两个实例同时活着，一 id 一全局 key 会直接炸
      final controller = await pumpHost(
        tester,
        const [
          GuideStep(title: '第一步', body: '说明', anchorId: 'go'),
          GuideStep(title: '第二步', body: '说明', anchorId: 'dup'),
        ],
        onTap: taps.add,
        dupOnShell: true,
      );

      expect(controller.registry.instancesOf('dup'), 1);

      await tester.tap(find.text('进二级页'));
      await settle(tester);

      expect(tester.takeException(), isNull);
      expect(controller.registry.instancesOf('dup'), 2);
      expect(find.text('第二步'), findsOneWidget);

      // 洞落在最上层（二级页）那个实例上：点得穿 → 说明没打到被压住的外壳实例
      await tester.tap(find.text('二级重复'));
      await tester.pump();
      expect(taps, ['sub-dup']);

      // 弹出二级页后，被压在下面的实例重新成为可见锚点
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      nav.pop();
      await settle(tester);
      expect(controller.registry.instancesOf('dup'), 1);

      await disposeHost(tester, controller);
    });
  });

  group('引导文案表', () {
    test('Tab 下标合法，锚点 id 都是已定义常量', () {
      const ids = {
        GuideAnchorIds.shellNav,
        GuideAnchorIds.homeWeekly,
        GuideAnchorIds.quickImport,
        GuideAnchorIds.quickPrimary,
        GuideAnchorIds.quickErrorBook,
        GuideAnchorIds.statsOverview,
        GuideAnchorIds.profileSettings,
        GuideAnchorIds.errorbookBack,
        GuideAnchorIds.settingsBack,
        GuideAnchorIds.importSample,
        GuideAnchorIds.sheetConfirm,
      };
      for (final step in kGuideSteps) {
        if (step.tab != null) {
          expect(step.tab, inInclusiveRange(0, 3),
              reason: '引导步骤的 Tab 下标必须是真实的四个 Tab：${step.title}');
        }
        for (final id in step.anchorIds) {
          expect(ids, contains(id),
              reason: '锚点 id 必须在 GuideAnchorIds 中定义：${step.title}');
        }
      }
      // 首步是欢迎（无锚点），末步有收尾按钮文案
      expect(kGuideSteps.first.anchorId, isNull);
      expect(kGuideSteps.last.nextLabel, isNotNull);
    });

    test('引导必须真的走进二级页面 / 弹层，而不是只高亮主壳按钮', () {
      // 需求回归守卫：点高亮处会跳到二级页面的那几步，
      // 必须在二级页 / 弹层里各留一步引导（否则用户进去就没人带了）
      final anchors = kGuideSteps.map((s) => s.anchorId).toList();
      expect(anchors, contains(GuideAnchorIds.importSample),
          reason: '「导入题库 → 导入页」必须有导进二级页的后续步骤');
      expect(anchors, contains(GuideAnchorIds.errorbookBack),
          reason: '「错题本 → 错题本页」必须有页面里的后续步骤');
      expect(anchors, contains(GuideAnchorIds.settingsBack),
          reason: '「我的 → 设置中心」必须有页面里的后续步骤');
      expect(anchors, contains(GuideAnchorIds.sheetConfirm),
          reason: '「定向爆破 → 开始刷题弹窗」必须有弹层里的后续步骤');
      // 弹层步骤排在最后：用户点下真实「开始」即收尾
      expect(kGuideSteps.last.anchorId, GuideAnchorIds.sheetConfirm);
    });

    test('导航步必须带锚点，且末步要给「完成」出口', () {
      // 导航步（awaitAction）不显示「下一步」：进展只能靠点高亮处。
      // 若这样的步骤没有锚点，用户既看不到高亮、也没有按钮，只剩「跳过」。
      for (final step in kGuideSteps) {
        if (!step.awaitAction) continue;
        expect(step.anchorId, isNotNull,
            reason: '导航步必须指定高亮处：${step.title}');
      }
      // 末步保留「完成」：不想马上开刷的人也要有出口
      expect(kGuideSteps.last.awaitAction, isFalse);
      expect(kGuideSteps.last.nextLabel, isNotNull);
    });

    test('带锚点的步骤必须声明 tab（主壳自带导航除外）', () {
      // 回归守卫：IndexedStack 的隐藏页每帧照常布局，锚点矩形一直取得到，
      // 若步骤不声明 tab，引导可能把洞打到当前看不见的那一页坐标上。
      for (final step in kGuideSteps) {
        if (step.anchorIds.isEmpty || step.anchorId == GuideAnchorIds.shellNav) {
          continue;
        }
        expect(step.tab, isNotNull,
            reason: '锚点位于某个 Tab 页内，必须声明 tab：${step.title}');
      }
    });
  });
}
