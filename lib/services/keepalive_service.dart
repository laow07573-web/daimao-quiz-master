import 'dart:io';

import 'package:flutter/services.dart';

/// 保活服务（v1.0.2 设计审查修复：简化保活）
///
/// 已移除无障碍拉活与开机自启（过度保活 + 商店合规风险），
/// 仅保留电池优化豁免：让前台提醒服务不被系统激进清理。
class KeepAliveService {
  KeepAliveService._();
  static final KeepAliveService instance = KeepAliveService._();

  static const _channel = MethodChannel('com.flashcard.app/keepalive');

  /// 是否已忽略电池优化（设置页可引导）。
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
