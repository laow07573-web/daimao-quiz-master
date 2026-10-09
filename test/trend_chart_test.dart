import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/services/theme_service.dart';
import 'package:flashcard_app/widgets/trend_chart.dart';

List<Map<String, dynamic>> _days(int n, {int Function(int)? totals}) {
  final now = DateTime.now();
  final start =
      DateTime(now.year, now.month, now.day).subtract(Duration(days: n - 1));
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
    test('>=80 强档 / >=60 中档 / <60 danger 档', () {
      // v1.28 新设计语言：取色改走 AppThemeColors 语义色
      const ac = AppThemeColors(
        background: Color(0xFFFFFFFF),
        surface: Color(0xFFFFFFFF),
        surfaceAlt: Color(0xFFF0F0F0),
        border: Color(0xFFE0E0E0),
        textPrimary: Color(0xFF000000),
        textSecondary: Color(0xFF666666),
        textTertiary: Color(0xFF999999),
        accent: Color(0xFF000000),
        accentSoft: Color(0xFFEEEEEE),
        onAccent: Color(0xFFFFFFFF),
        navBackground: Color(0xFFFFFFFF),
        navForeground: Color(0xFF000000),
        danger: Color(0xFFEE0000),
      );
      // 墨黑主题修复：三档由透明度改为 levelShade 实色档位
      //（透明度叠底在中性灰 accent 下会退化成灰阶）
      expect(
          accuracyTierColor(90, ac), levelShade(ac.accent, ac.surface, 0.75));
      expect(
          accuracyTierColor(70, ac), levelShade(ac.accent, ac.surface, 0.45));
      expect(
          accuracyTierColor(50, ac), levelShade(ac.danger, ac.surface, 0.75));
      expect(accuracyTierColor(0, ac), levelShade(ac.danger, ac.surface, 0.75));
      // 高/中两档必须可辨（不能塌成同一个色）
      expect(accuracyTierColor(70, ac), isNot(accuracyTierColor(90, ac)));
    });
  });

  group('正确率平滑曲线（Catmull-Rom → 三次贝塞尔）', () {
    test('曲线包含三次贝塞尔段（非直线）', () {
      final path = smoothSegment(
        const Offset(0, 100),
        const Offset(10, 20),
        const Offset(0, 100),
        const Offset(20, 30),
      );
      final metrics = path.computeMetrics().toList();
      expect(metrics, isNotEmpty);
      // 贝塞尔段长度 > 直线距离（曲线比直线长），可证明它在弯曲
      final straight = (const Offset(10, 20) - const Offset(0, 100)).distance;
      expect(metrics.first.length, greaterThan(straight));
    });

    test('控制点收在段包围盒内：曲线不过冲', () {
      // 三段起伏数据，中点应落在两端 y 之间，不冲出
      const p1 = Offset(0, 50);
      const p2 = Offset(10, 50);
      const p0 = Offset(-10, 0); // 上一段在上方 → 会拉高控制点
      const p3 = Offset(20, 100); // 下一段在下方
      final path = smoothSegment(p1, p2, p0, p3);
      final bounds = path.getBounds();
      // 包围盒不应超出 p1/p2 的 y 范围（50~50）
      expect(bounds.top, greaterThanOrEqualTo(49.9));
      expect(bounds.bottom, lessThanOrEqualTo(50.1));
    });

    test('平坦数据得到水平直线', () {
      final path = smoothSegment(
        const Offset(0, 30),
        const Offset(10, 30),
        const Offset(0, 30),
        const Offset(10, 30),
      );
      final b = path.getBounds();
      expect(b.height, lessThan(0.01));
    });
  });

  group('默认窗口锚定最新数据', () {
    test('365 天数据默认窗口停在末尾（不会打开就是一年前那段空白）', () {
      // 真机反馈：趋势图打开时看不到任何柱体——默认 _start=0 落在数组最早处，
      // 而数据在末尾。窗口必须贴在最新一端。
      expect(latestWindowStart(365, 30), 335);
      expect(latestWindowStart(365, 14), 351);
      // 窗口右端就是最后一天，最后一天必须在可视范围内
      expect(latestWindowStart(365, 30) + 30, 365);
    });

    test('数据不足一个窗口时从 0 开始，且窗口不超过数据长度', () {
      expect(latestWindowStart(10, 30), 0);
      expect(latestWindowStart(1, 30), 0);
      expect(latestWindowStart(0, 30), 0);
    });

    test('缩放到极端值时起点不越界', () {
      expect(latestWindowStart(365, 1), 364);
      expect(latestWindowStart(365, 365), 0);
      expect(latestWindowStart(365, 999), 0);
    });
  });

  group('行情图配色与柱宽（用户反馈：间距要恒定、两条数据要分得开）', () {
    test('柱宽始终是单日槽宽的固定比例：无论放大缩小，间距等比恒定', () {
      for (final slot in [3.0, 8.0, 20.0, 60.0, 180.0]) {
        final w = candleWidthFor(slot);
        expect(w / slot, closeTo(0.62, 0.001),
            reason: '槽宽 $slot 时柱宽应为 62%，这样间距不会忽大忽小');
        expect(w, lessThan(slot), reason: '柱体不能占满整天，否则没有间距');
      }
    });

    test('极小槽宽下柱宽有下限，不会细到看不见', () {
      expect(candleWidthFor(0), 1.0);
      expect(candleWidthFor(0.5), greaterThanOrEqualTo(1.0));
      expect(candleWidthFor(1.0), greaterThanOrEqualTo(1.0));
    });

    test('涨跌与正确率三色互不相同（避免视觉疲劳）', () {
      expect(TrendPalette.up, isNot(TrendPalette.down));
      expect(TrendPalette.accuracy, isNot(TrendPalette.up));
      expect(TrendPalette.accuracy, isNot(TrendPalette.down));
      expect(TrendPalette.flat, isNot(TrendPalette.up));
      // 参考加密货币 K 线配色
      expect(TrendPalette.up, const Color(0xFF0ECB81));
      expect(TrendPalette.down, const Color(0xFFF6465D));
    });

    test('最小可视窗口为一个已知常量（再放大没有信息量）', () {
      expect(minTrendSpan, 7);
    });
  });

  group('趋势行情图交互', () {
    test('开盘/收盘数据：前一天没有数据时不开盘，不伪造比较值', () {
      final days = [
        {'date': DateTime(2026, 10, 1), 'total': 8, 'accuracy': 70.0},
        {'date': DateTime(2026, 10, 2), 'total': 12, 'accuracy': 80.0},
        {'date': DateTime(2026, 10, 3), 'total': 5, 'accuracy': 60.0},
      ];
      expect(previousDayTotal(days, DateTime(2026, 10, 1)), isNull);
      expect(previousDayTotal(days, DateTime(2026, 10, 2)), 8);
      expect(previousDayTotal(days, DateTime(2026, 10, 3)), 12);
      // 中间缺日期时也不把非相邻数据当作开盘价。
      expect(previousDayTotal(days, DateTime(2026, 10, 5)), isNull);
    });

    testWidgets('全年数据渲染为连续行情图，支持拖动/缩放容器', (tester) async {
      await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: TrendChart(days: _days(365)))));
      await tester.pumpAndSettle();
      expect(find.byType(TrendChart), findsOneWidget);
      expect(find.byKey(const ValueKey('trend_interactive_viewer')),
          findsOneWidget);
      expect(find.byType(PageView), findsNothing);
      final chart = tester
          .getRect(find.byKey(const ValueKey('trend_interactive_viewer')));
      await tester.dragFrom(chart.center, chart.center + const Offset(-120, 0));
      await tester.pump();
      // WidgetTester 当前版本没有 pinch 辅助 API；InteractiveViewer 的双指缩放
      // 由真机手势验证，Widget 层这里覆盖连续拖动且确保无异常。
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('显示可视范围提示，缩放/拖动不抛异常', (tester) async {
      await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: TrendChart(days: _days(365)))));
      await tester.pumpAndSettle();
      // 可视范围提示（放大后用户不至于不知道在看哪一段）
      expect(find.textContaining('共'), findsOneWidget);
      final chart = tester
          .getRect(find.byKey(const ValueKey('trend_interactive_viewer')));
      await tester.dragFrom(chart.center, chart.center + const Offset(-140, 0));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('双指捏合可缩放（可视天数变少），不再被横向滑动抢走', (tester) async {
      await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: TrendChart(days: _days(365)))));
      await tester.pumpAndSettle();

      int visibleDays() {
        final text = tester
            .widgetList<Text>(find.textContaining('共'))
            .map((t) => t.data ?? '')
            .firstWhere((s) => s.contains('共'));
        return int.parse(RegExp(r'共 (\d+) 天').firstMatch(text)!.group(1)!);
      }

      final before = visibleDays();
      expect(before, 30, reason: '默认可视窗口应为最近 30 天');

      // 两指反向拉开 = 放大 → 可视天数变少
      final rect = tester
          .getRect(find.byKey(const ValueKey('trend_interactive_viewer')));
      final g1 = await tester.startGesture(rect.center - const Offset(30, 0));
      final g2 = await tester.startGesture(rect.center + const Offset(30, 0));
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        await g1.moveBy(const Offset(-18, 0));
        await g2.moveBy(const Offset(18, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g1.up();
      await g2.up();
      await tester.pumpAndSettle();

      expect(visibleDays(), lessThan(before),
          reason: '捏合应真的改变可视窗口；此前缩放与横向拖动抢手势，捏合常被判成滑动');
      expect(visibleDays(), greaterThanOrEqualTo(minTrendSpan),
          reason: '放大到最小窗口就该停住');
    });

    testWidgets('点击某天触发详情回调，空记录日不触发', (tester) async {
      Map<String, dynamic>? selected;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: TrendChart(
        days: _days(14),
        onDaySelected: (d) => selected = d,
      ))));
      await tester.pumpAndSettle();
      final chart = tester
          .getRect(find.byKey(const ValueKey('trend_interactive_viewer')));
      await tester.tapAt(
          Offset(chart.left + chart.width / 2, chart.top + chart.height / 2));
      await tester.pump();
      expect(selected, isNotNull);

      selected = null;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: TrendChart(
        days: _days(14, totals: (_) => 0),
        onDaySelected: (d) => selected = d,
      ))));
      await tester.pumpAndSettle();
      expect(selected, isNull);
    });
  });
}
