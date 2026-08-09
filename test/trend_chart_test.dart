import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/widgets/trend_chart.dart';

List<Map<String, dynamic>> _days(int n, {int Function(int)? totals}) {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day)
      .subtract(Duration(days: n - 1));
  return [
    for (var i = 0; i < n; i++)
      {
        'date': start.add(Duration(days: i)),
        'total': totals?.call(i) ?? 10,
        'accuracy': 70.0,
      }
  ];
}

void main() {
  group('chunkDays 从尾部每7天分页', () {
    test('30 天 → 4 页，每页 7 天，头部碎片丢弃', () {
      final days = _days(30);
      final pages = chunkDays(days);
      expect(pages.length, 4);
      for (final p in pages) {
        expect(p.length, 7);
      }
      // 头部 2 天碎片丢弃（30 % 7 == 2）
      expect(pages.first.first['date'], days[2]['date']);
      // 尾部对齐：最后一页最后一天 = 数据最后一天
      expect(pages.last.last['date'], days.last['date']);
    });

    test('28 天 → 4 页整（无丢弃）', () {
      final days = _days(28);
      final pages = chunkDays(days);
      expect(pages.length, 4);
      expect(pages.first.first['date'], days[0]['date']);
    });

    test('不足 7 天 → 单页保留全部', () {
      final days = _days(5);
      final pages = chunkDays(days);
      expect(pages.length, 1);
      expect(pages.first.length, 5);
    });

    test('空数据 → 空页', () {
      expect(chunkDays([]), isEmpty);
    });
  });

  group('niceStep 整数刻度', () {
    test('1/2/5×10ⁿ 步长', () {
      expect(niceStep(0), 1);
      expect(niceStep(1), 1);
      expect(niceStep(2.5), 5);
      expect(niceStep(7), 10);
      expect(niceStep(100), 100);
      expect(niceStep(101), 200);
      expect(niceStep(1.2), 2);
      expect(niceStep(0.3), 0.5); // max(raw, 1.0) 由调用方保证
    });
  });

  group('accuracyTierColor 三档', () {
    test('>=80 primary 0.7 / >=60 primary 0.45 / <60 error 0.7', () {
      const cs = ColorScheme.light(primary: Color(0xFF000000), error: Color(0xFFEE0000));
      expect(accuracyTierColor(90, cs), const Color(0xFF000000).withOpacity(0.7));
      expect(accuracyTierColor(70, cs), const Color(0xFF000000).withOpacity(0.45));
      expect(accuracyTierColor(50, cs), const Color(0xFFEE0000).withOpacity(0.7));
      expect(accuracyTierColor(0, cs), const Color(0xFFEE0000).withOpacity(0.7));
    });
  });

  group('TrendChart 交互', () {
    testWidgets('渲染 30 天数据无异常，页码指示器存在', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TrendChart(days: _days(30)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TrendChart), findsOneWidget);
      // 4 页指示器
      expect(find.byType(PageView), findsOneWidget);
    });

    testWidgets('点击有记录的天触发 onDaySelected（气泡逻辑）', (tester) async {
      Map<String, dynamic>? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TrendChart(
              days: _days(14),
              onDaySelected: (d) => selected = d,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // 点击 PageView 中心（图表区）
      final pv = tester.getRect(find.byType(PageView));
      await tester.tapAt(pv.center);
      await tester.pump();
      expect(selected, isNotNull);
      expect(selected!['total'], 10);
    });

    testWidgets('点击无记录的天不触发（跳过 total<=0）', (tester) async {
      Map<String, dynamic>? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TrendChart(
              days: _days(7, totals: (_) => 0),
              onDaySelected: (d) => selected = d,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // 点击 PageView 中心（图表区，全部无记录 → 不触发）
      final pv = tester.getRect(find.byType(PageView));
      await tester.tapAt(pv.center);
      await tester.pump();
      expect(selected, isNull);
    });
  });
}
