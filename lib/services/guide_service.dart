import 'package:shared_preferences/shared_preferences.dart';

/// 首次使用引导的展示状态（v1.28.2）
///
/// 只负责一件事：记住「首启引导是否已经看过」，供启动页决定是否插播引导。
/// 「我的 → 重看使用引导」是显式打开，不走这里的判定（看完只做一次幂等写入）。
/// 键名带版本后缀：引导内容大改时递增后缀即可让老用户再看一次。
class GuideService {
  GuideService._();
  static final GuideService instance = GuideService._();

  /// 首启引导已看过（互动式引导 · v2）
  ///
  /// v1 是最初的静态三页版；换成逐步高亮真实控件的互动式引导后升 V2，
  /// 使看过旧版的人也能看到新版（旧键不再读取，留在存储里无害）。
  static const String keyGuideSeenV2 = 'first_run_guide_seen_v2';

  bool? _seen;

  /// 是否已经看过首启引导。
  ///
  /// 存储异常时按「已看过」处理：宁可少播一次引导，也不要在插件/存储异常时
  /// 每次启动都拦一道（同一取向下 [DeviceService] 也是给缺省值、不抛）。
  Future<bool> hasSeen() async {
    if (_seen != null) return _seen!;
    try {
      final prefs = await SharedPreferences.getInstance();
      _seen = prefs.getBool(keyGuideSeenV2) ?? false;
    } catch (_) {
      _seen = true;
    }
    return _seen!;
  }

  /// 标记已看过（幂等）。
  Future<void> markSeen() async {
    _seen = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(keyGuideSeenV2, true);
    } catch (_) {}
  }

  /// 仅测试用：清掉进程内缓存，让下一次 [hasSeen] 重新读存储。
  void resetCacheForTest() => _seen = null;
}
