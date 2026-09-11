import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/utils/responsive.dart';

/// AdaptivePair 等高能力（v1.28：年度坚持与近一年趋势并排持平）。
void main() {
  testWidgets('equalHeight + targetHeight：并排时两卡片等高', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AdaptivePair(
            equalHeight: true,
            targetHeight: 300,
            minWidth: 600,
            first: Container(key: const Key('a'), color: const Color(0xFFEEEEEE)),
            second: Container(key: const Key('b'), color: const Color(0xFFDDDDDD)),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final a = tester.getSize(find.byKey(const Key('a')));
    final b = tester.getSize(find.byKey(const Key('b')));
    expect(a.height, b.height, reason: '并排两卡片应等高');
    expect(a.height, 300, reason: '应等于目标高度');
  });

  testWidgets('堆叠（低于阈值）时高度无界也不报错', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AdaptivePair(
            equalHeight: true,
            targetHeight: 300,
            minWidth: 900,
            first: Container(key: const Key('a'), height: 120, color: const Color(0xFFEEEEEE)),
            second: Container(key: const Key('b'), height: 200, color: const Color(0xFFDDDDDD)),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // 堆叠时各按自身高度，不强制等高
    expect(find.byKey(const Key('a')), findsOneWidget);
    expect(find.byKey(const Key('b')), findsOneWidget);
  });
}
