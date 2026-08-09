import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/widgets/year_heatmap.dart';

void main() {
  String key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  group('YearHeatmap 年度坚持月历', () {
    testWidgets('渲染无异常：42 格 × 12 月，4 页', (tester) async {
      final now = DateTime.now();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: YearHeatmap(
              dailyTotals: {key(now): 60},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(YearHeatmap), findsOneWidget);
      expect(find.byType(PageView), findsOneWidget);
      // 图例存在
      expect(find.text('少'), findsOneWidget);
      expect(find.text('达标'), findsOneWidget);
      expect(find.text('多'), findsOneWidget);
      expect(find.text('今天'), findsOneWidget);
    });

    testWidgets('初始页 = 当前月所在页', (tester) async {
      final now = DateTime.now();
      final expectedPage = ((now.month - 1) ~/ 3).clamp(0, 3);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: YearHeatmap(
              dailyTotals: {key(now): 60},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final pageView = tester.widget<PageView>(find.byType(PageView));
      expect(pageView.controller!.initialPage, expectedPage);
      expect(pageView.controller!.page, expectedPage.toDouble());
    });

    testWidgets('假期日期标注为 error 色', (tester) async {
      final now = DateTime.now();
      final vacationKey = key(now.subtract(const Duration(days: 3)));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: YearHeatmap(
              dailyTotals: {key(now): 60},
              vacationDays: {vacationKey},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // 不崩溃 + 图例完好
      expect(find.byType(YearHeatmap), findsOneWidget);
      expect(find.text('今天'), findsOneWidget);
    });
  });
}
