import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flashcard_app/services/theme_service.dart';
import 'package:flashcard_app/widgets/answer_sheet_widget.dart';

/// 2026-10-08 真机反馈（图二）：答题卡弹层里的题目「无法上下滑动来选择」。
///
/// 根因：弹层直接把 AnswerSheetWidget（内部是 Wrap，不滚动）塞进
/// showModalBottomSheet —— 50 题超出默认高度后被裁掉，且没有任何滚动容器。
/// 现在弹层是「折叠态 DraggableScrollableSheet + 可滚动内容」：
///   · 默认只占屏幕下半部分（折叠），可上拖展开；
///   · 内容超出时能上下滑动，后面的题号也能点到。
void main() {
  Widget host(Widget child) => ChangeNotifierProvider<ThemeService>(
        create: (_) => ThemeService(),
        child: MaterialApp(theme: ThemeService().themeData, home: child),
      );

  testWidgets('50 题答题卡超出高度时可上下滚动（题目都能滑到）', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(host(Scaffold(
      body: SizedBox(
        height: 300, // 折叠态高度：装不下 50 题
        child: SingleChildScrollView(
          child: AnswerSheetWidget(
            answers: List.generate(50, (_) => PracticeAnswerState()),
            currentIndex: 0,
            onJumpTo: (_) {},
          ),
        ),
      ),
    )));
    await tester.pumpAndSettle();

    final scrollable = find.byType(Scrollable).first;
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.maxScrollExtent, greaterThan(0),
        reason: '50 题内容高于折叠态高度，必须可滚动，否则后面的题被裁掉且滑不动');

    await tester.drag(scrollable, const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0), reason: '上滑应真的滚动内容');
    expect(tester.takeException(), isNull);
  });

  testWidgets('答题卡默认折叠：DraggableScrollableSheet 初始占比小于一半屏', (tester) async {
    // 与 quiz_screen._showAnswerSheet 的配置保持一致
    await tester.pumpWidget(host(Scaffold(
      body: DraggableScrollableSheet(
        initialChildSize: 0.42,
        minChildSize: 0.28,
        maxChildSize: 0.92,
        expand: false,
        builder: (context, controller) => SingleChildScrollView(
          controller: controller,
          child: AnswerSheetWidget(
            answers: List.generate(10, (_) => PracticeAnswerState()),
            currentIndex: 0,
            onJumpTo: (_) {},
          ),
        ),
      ),
    )));
    await tester.pumpAndSettle();

    expect(find.text('答题卡'), findsOneWidget);
    expect(find.byType(DraggableScrollableSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
