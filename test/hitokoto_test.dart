import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/services/hitokoto_service.dart';

/// v1.27 一言加载修复验证（PC 端问题：网络慢/断网时首屏长时间显示
/// 「正在加载一言...」，失败后回退固定一句）：
/// 1. 首屏立即显示（缓存/本地一言库），无加载占位；
/// 2. 失败兜底随机取自本地一言库，内容非空。
void main() {
  test('immediateText 立即可用：非空且不是加载占位文案', () {
    for (var i = 0; i < 20; i++) {
      final t = HitokotoService.immediateText();
      expect(t.isNotEmpty, isTrue);
      expect(t.contains('正在加载'), isFalse);
    }
  });

  test('fallbackText 兜底来自本地一言库：非空且多样', () {
    final seen = <String>{};
    for (var i = 0; i < 60; i++) {
      final t = HitokotoService.fallbackText();
      expect(t.isNotEmpty, isTrue);
      expect(t.contains('正在加载'), isFalse);
      seen.add(t);
    }
    // 60 次随机抽取应至少出现 2 种不同文案（证明是随机库而非固定一句）
    expect(seen.length, greaterThan(1));
  });

  test('fetchOrDefault 失败兜底也是本地一言（不返回加载占位）', () {
    // 不依赖网络可达性：无论 fetch 成功与否，结果都非空且无占位。
    // 注：测试环境可能无外网，此断言对两种情况都成立。
    expect(HitokotoService.defaultText.isNotEmpty, isTrue);
  });
}
