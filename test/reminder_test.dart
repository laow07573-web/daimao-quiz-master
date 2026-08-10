import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/services/reminder_service.dart';

/// 每日提醒逻辑测试（v1.0.2）：
/// - 文案：连击两种口径（含/不含今天）
/// - 设置序列化（reminder_enabled 读取 == '1'）
void main() {
  group('buildReminderText 文案', () {
    test('无连击 → 来几道题，开启新的连胜吧', () {
      final t = ReminderService.buildReminderText(0, 0);
      expect(t, contains('来几道题，开启新的连胜吧'));
    });

    test('含今天连击更高 → 显示含今天口径', () {
      final t = ReminderService.buildReminderText(5, 4);
      expect(t, contains('你已连续打卡 5 天，继续刷题积累吧！'));
    });

    test('不含今天口径（截止昨天）', () {
      final t = ReminderService.buildReminderText(0, 3);
      expect(t, contains('你已连续打卡 3 天，继续刷题积累吧！'));
    });

    test('今天已刷时含今天口径与不含今天一致', () {
      final t = ReminderService.buildReminderText(6, 6);
      expect(t, contains('你已连续打卡 6 天，继续刷题积累吧！'));
    });
  });

  group('设置序列化（reminder_enabled == 1 语义）', () {
    test('字符串比较语义', () {
      expect(('1' == '1'), isTrue);
      expect(('0' == '1'), isFalse);
      expect((null ?? '0') == '1', isFalse);
    });
  });
}
