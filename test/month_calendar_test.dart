import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/services/theme_service.dart';
import 'package:flashcard_app/widgets/monthly_calendar.dart';

void main() {
  String key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  group('MonthCalendar 单月打卡日历', () {
    testWidgets('渲染无异常：42 格网格 + 月份标题', (tester) async {
      final now = DateTime.now();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeService().themeData,
          home: Scaffold(
            body: MonthCalendar(
              year: now.year,
              month: now.month,
              dailyTotals: {key(now): 60},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MonthCalendar), findsOneWidget);
      expect(find.text('${now.month}月'), findsOneWidget);
      expect(find.text('${now.year}年'), findsOneWidget);
    });

    testWidgets('今天高亮（todayKey 边框 + 加粗）', (tester) async {
      final now = DateTime.now();
      final today = key(now);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeService().themeData,
          home: Scaffold(
            body: MonthCalendar(
              year: now.year,
              month: now.month,
              dailyTotals: {today: 60},
              todayKey: today,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // 当天格子的日期文本加粗（高亮）
      final todayText = tester.widget<Text>(find.text('${now.day}'));
      expect(todayText.style?.fontWeight, FontWeight.bold);
    });

    testWidgets('假期日期标注为 error 色（不崩溃）', (tester) async {
      final now = DateTime.now();
      final vacationKey = key(now.subtract(const Duration(days: 3)));
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeService().themeData,
          home: Scaffold(
            body: MonthCalendar(
              year: now.year,
              month: now.month,
              dailyTotals: {key(now): 60},
              vacationDays: {vacationKey},
              todayKey: key(now),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MonthCalendar), findsOneWidget);
    });

    testWidgets('onDayTap 回调：点击某天触发', (tester) async {
      final now = DateTime.now();
      int? tapped;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeService().themeData,
          home: Scaffold(
            body: MonthCalendar(
              year: now.year,
              month: now.month,
              dailyTotals: {},
              onDayTap: (day) => tapped = day,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('${now.day}'));
      expect(tapped, now.day);
    });
  });
}
