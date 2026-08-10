import 'dart:io';

import 'package:flutter/services.dart';

/// 保活服务（v1.0.2）：GKD 式无障碍保活
///
/// 无障碍服务被系统强杀后会自动重启并拉起 App。
/// isAccessibilityEnabled 必须用 ComponentName(...).flattenToString()
/// 匹配系统设置值（缩写形式匹配不上会误报「未开启」）
class KeepAliveService {
  KeepAliveService._();
  static final KeepAliveService instance = KeepAliveService._();

  static const _channel = MethodChannel('com.flashcard.app/keepalive');

  /// 无障碍服务是否已开启（Android）
  Future<bool> isAccessibilityEnabled() async {
    if (!Platform.isAndroid) return false;
    try {
      final result = await _channel.invokeMethod<bool>('isAccessibilityEnabled');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 引导用户开启无障碍保活
  Future<void> openAccessibilitySettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('openAccessibilitySettings');
    } catch (_) {}
  }

  /// 是否已忽略电池优化（v1.0.2：与里程碑一致，设置页可引导）。
  /// 查询失败返回 false（fail-closed），避免误导用户以为已豁免
  Future<bool> isIgnoringBatteryOptimizations() async {
    if (!Platform.isAndroid) return false;
    try {
      final result =
          await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 请求忽略电池优化（弹出系统授权页）
  Future<void> requestIgnoreBatteryOptimizations() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
    } catch (_) {}
  }
}
