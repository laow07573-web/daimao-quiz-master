import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/services/database_service.dart';

/// countConsecutiveDays 纯函数测试（口径：截止昨天、>=50 题/天、假期冻结）
void main() {
  String key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  DateTime day(int offset) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day)
        .add(Duration(days: offset));
  }

  Map<String, int> totals(List<DateTime> days) =>
      {for (final d in days) key(d): 80};

  test('连续达标 3 天（截止昨天）', () {
    final stats = totals([day(-1), day(-2), day(-3)]);
    expect(
      DatabaseService.countConsecutiveDays(stats, now: DateTime.now()),
      3,
    );
  });

  test('今天不计入（截止昨天）', () {
    final stats = totals([day(0), day(-1), day(-2)]);
    expect(
      DatabaseService.countConsecutiveDays(stats, now: DateTime.now()),
      2,
    );
  });

  test('中断中断裂', () {
    final stats = totals([day(-1), day(-2), day(-4), day(-5)]);
    expect(
      DatabaseService.countConsecutiveDays(stats, now: DateTime.now()),
      2,
    );
  });

  test('低于阈值的天不达标', () {
    final now = DateTime.now();
    final stats = {
      key(DateTime(now.year, now.month, now.day)
          .subtract(const Duration(days: 1))): 49,
    };
    expect(DatabaseService.countConsecutiveDays(stats, now: now), 0);
  });

  test('假期跳过：不中断也不计入', () {
    final now = DateTime.now();
    final stats = totals([day(-1), day(-2), day(-3), day(-4)]);
    // 昨天和前天是假期，之前 2 天达标 → 连击 2（假期不打断）
    expect(
      DatabaseService.countConsecutiveDays(
        stats,
        now: now,
        vacationDays: [day(-1), day(-2)],
      ),
      2,
    );
  });

  test('假期夹在中间不中断连击', () {
    final now = DateTime.now();
    final stats = totals([day(-1), day(-3), day(-4)]);
    // 昨天达标，前天(day-2)假期跳过，day-3/day-4 达标 → 3 天
    expect(
      DatabaseService.countConsecutiveDays(
        stats,
        now: now,
        vacationDays: [day(-2)],
      ),
      3,
    );
  });

  test('自定义阈值', () {
    final now = DateTime.now();
    final stats = {
      key(DateTime(now.year, now.month, now.day)
          .subtract(const Duration(days: 1))): 30,
    };
    expect(
      DatabaseService.countConsecutiveDays(stats, now: now, threshold: 30),
      1,
    );
  });

  test('假期区间判断：不逐日展开（v1.0.2 设计审查）', () {
    final now = DateTime.now();
    final stats = totals([day(-1), day(-2), day(-3), day(-4)]);
    // 昨天与前天在假期区间内（不展开列表），之前 2 天达标 → 连击 2
    expect(
      DatabaseService.countConsecutiveDays(
        stats,
        now: now,
        vacationStart: day(-2),
        vacationEnd: day(-1),
      ),
      2,
    );
    // 区间包含 day(-3)：连击只剩 day(-4) → 1
    expect(
      DatabaseService.countConsecutiveDays(
        stats,
        now: now,
        vacationStart: day(-3),
        vacationEnd: day(-1),
      ),
      1,
    );
    // 区间只含很久以前 → 不影响 → 4
    expect(
      DatabaseService.countConsecutiveDays(
        stats,
        now: now,
        vacationStart: day(-30),
        vacationEnd: day(-20),
      ),
      4,
    );
  });
}
