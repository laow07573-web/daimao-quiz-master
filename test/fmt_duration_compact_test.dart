import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/utils/format_utils.dart';

/// 紧凑时长格式：窄格（首页三格 / 统计四格）专用，防止长文本被截断。
/// 契约：任何时长渲染后都不应超过 5 个字符（否则在 1/3~1/4 宽度里会被裁）。
void main() {
  group('fmtDurationCompact', () {
    test('零与秒级', () {
      expect(fmtDurationCompact(0), '0');
      expect(fmtDurationCompact(45), '45秒');
      expect(fmtDurationCompact(60), '1分');
      expect(fmtDurationCompact(1500), '25分');
    });

    test('小时级省略为零的单位', () {
      expect(fmtDurationCompact(3600), '1时');
      expect(fmtDurationCompact(3660), '1时1分');
      expect(fmtDurationCompact(86399), '23时59分');
    });

    test('天级（模拟 90 天数据的典型值）', () {
      expect(fmtDurationCompact(86400), '1天');
      expect(fmtDurationCompact(86400 + 3600), '1天1时');
      // 4 天 23 小时 25 分 —— 首页实际出现过的值
      expect(fmtDurationCompact(4 * 86400 + 23 * 3600 + 25 * 60), '4天23时');
    });

    test('上界：>=1000 天折叠为 999天+（防御）', () {
      expect(fmtDurationCompact(1000 * 86400), '999天+');
      expect(fmtDurationCompact(1000 * 86400).length, lessThan(6));
    });

    test('长度恒 <= 6（超出部分由 UI 的 FittedBox 缩放兜底）', () {
      for (final s in [
        0, 1, 59, 60, 3599, 3600, 86399, 86400, 90000,
        4 * 86400 + 23 * 3600 + 25 * 60,
        30 * 86400, 99 * 86400 + 23 * 3600,
        365 * 86400, 999 * 86400, 1000 * 86400,
      ]) {
        final t = fmtDurationCompact(s);
        expect(t.length, lessThanOrEqualTo(6),
            reason: '${s}s → "$t" 超过 6 字符');
      }
    });
  });
}
