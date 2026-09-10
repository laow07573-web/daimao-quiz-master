import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// 设备标识（局域网同步）
///
/// 每台设备首次启动生成唯一 `device_id`（uuid v4，shared_preferences 持久），
/// 本机产生的作答记录/错题/批注均带此标识，同步时按设备维度隔离合并。
class DeviceService {
  DeviceService._();
  static final DeviceService instance = DeviceService._();

  static const _keyDeviceId = 'sync_device_id';
  static const _keyDeviceName = 'sync_device_name';

  String? _deviceId;
  String? _deviceName;

  /// 本机唯一设备标识（首次启动生成并持久化）。
  /// 测试宿主无插件时回退为进程内稳定值（宿主内同步语义自洽）
  Future<String> get deviceId async {
    if (_deviceId != null) return _deviceId!;
    try {
      final prefs = await SharedPreferences.getInstance();
      var id = prefs.getString(_keyDeviceId);
      if (id == null || id.isEmpty) {
        id = const Uuid().v4();
        await prefs.setString(_keyDeviceId, id);
      }
      _deviceId = id;
    } catch (_) {
      _deviceId = const Uuid().v4();
    }
    return _deviceId!;
  }

  /// 设备名（可编辑，缺省「猫卷-平台」）
  Future<String> get deviceName async {
    if (_deviceName != null) return _deviceName!;
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString(_keyDeviceName);
      _deviceName = (name == null || name.isEmpty) ? defaultDeviceName : name;
    } catch (_) {
      _deviceName = defaultDeviceName;
    }
    return _deviceName!;
  }

  Future<void> setDeviceName(String name) async {
    final trimmed = name.trim();
    _deviceName = trimmed.isEmpty ? defaultDeviceName : trimmed;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyDeviceName, _deviceName!);
    } catch (_) {}
  }

  /// 缺省设备名：猫卷-平台（如「猫卷-Android」「猫卷-Windows」）
  String get defaultDeviceName => '猫卷-$platformLabel';

  /// 平台标签（Android / Windows / macOS / Linux）
  String get platformLabel {
    if (Platform.isAndroid) return 'Android';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isLinux) return 'Linux';
    if (Platform.isIOS) return 'iOS';
    return Platform.operatingSystem;
  }

  /// 测试/迁移注入：覆盖设备标识（不影响已持久化值）
  void overrideDeviceId(String id) => _deviceId = id;

  /// 测试注入：覆盖设备名
  void overrideDeviceName(String name) => _deviceName = name;
}
