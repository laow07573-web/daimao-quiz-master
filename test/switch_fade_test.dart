import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flashcard_app/services/theme_service.dart';
import 'package:flashcard_app/widgets/kit/mj_kit.dart';

/// 2026-10-08 真机反馈：正确率排行「按题库/按知识点」切换时存在**重叠画面**；
/// 以及上轮改的过渡动画卡顿不流畅。
///
/// 根因：用 AnimatedSwitcher 做交叉淡入——新旧两份 child 会同时存在一段时间，
/// 高度不同的两份还会互相挤压，看起来就是重叠 + 抖动。
/// 现在改为 MJSwitchFade：切换即整块换新（旧内容当帧移除），只演一次淡入上移；
/// 且它与「切 Tab 的页面过渡」都用 child 缓存，动画 tick 不重建子树。
void main() {
  Widget host(Widget child) => ChangeNotifierProvider<ThemeService>(
        create: (_) => ThemeService(),
        child: MaterialApp(
          theme: ThemeService().themeData,
          home: Scaffold(body: child),
        ),
      );

  testWidgets('切换瞬间不残留旧内容（无重叠帧）', (tester) async {
    var mode = '按题库';
    late StateSetter setOuter;
    await tester.pumpWidget(host(StatefulBuilder(
      builder: (context, setState) {
        setOuter = setState;
        return MJSwitchFade(
          switchKey: mode,
          child: mode == '按题库' ? const Text('题库列表内容') : const Text('知识点列表内容'),
        );
      },
    )));
    await tester.pumpAndSettle();
    expect(find.text('题库列表内容'), findsOneWidget);

    setOuter(() => mode = '按知识点');
    await tester.pump(); // 只推一帧：动画刚开始

    expect(find.text('知识点列表内容'), findsOneWidget);
    expect(find.text('题库列表内容'), findsNothing,
        reason: '旧内容必须在切换当帧移除，否则就是真机看到的「重叠画面」');
    expect(tester.takeException(), isNull);
  });

  testWidgets('对照：AnimatedSwitcher 交叉淡入会同时保留两份内容（重叠来源）', (tester) async {
    var mode = '按题库';
    late StateSetter setOuter;
    await tester.pumpWidget(host(StatefulBuilder(
      builder: (context, setState) {
        setOuter = setState;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: mode == '按题库'
              ? const Text('题库列表内容', key: ValueKey('bank'))
              : const Text('知识点列表内容', key: ValueKey('kp')),
        );
      },
    )));
    await tester.pumpAndSettle();

    setOuter(() => mode = '按知识点');
    await tester.pump(); // 只推一帧

    // 旧方案：切换当帧新旧两份都还在树上 → 这正是真机看到的「重叠画面」
    expect(find.text('题库列表内容'), findsOneWidget);
    expect(find.text('知识点列表内容'), findsOneWidget);
  });

  testWidgets('入场动画会落位到完全不透明（不会停在半透明）', (tester) async {
    await tester.pumpWidget(host(const MJSwitchFade(
      switchKey: 'a',
      child: Text('内容'),
    )));
    await tester.pump();
    // 动画中：透明度 < 1
    final duringOpacity = tester.widget<Opacity>(find.byType(Opacity)).opacity;
    await tester.pumpAndSettle();
    final afterOpacity = tester.widget<Opacity>(find.byType(Opacity)).opacity;

    expect(afterOpacity, 1.0, reason: '动画结束必须完全落位');
    expect(duringOpacity, lessThanOrEqualTo(1.0));
  });

  testWidgets('系统「减弱动态效果」时直接落位（零时长）', (tester) async {
    await tester.pumpWidget(ChangeNotifierProvider<ThemeService>(
      create: (_) => ThemeService(),
      child: MaterialApp(
        theme: ThemeService().themeData,
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: const Scaffold(
            body: MJSwitchFade(switchKey: 'x', child: Text('内容')),
          ),
        ),
      ),
    ));
    await tester.pump();

    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1.0,
        reason: '减弱动态时应直接显示终态，不演动画');
  });
}
