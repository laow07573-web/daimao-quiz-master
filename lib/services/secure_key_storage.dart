import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'debug_log_service.dart';

/// 安全存储封装（v1.0.2 七项改进）
///
/// - Android：FlutterSecureStorage（Keystore 加密），API Key 不再是
///   SQLite 里的混淆密文
/// - 其他平台（含 Windows 测试环境）：返回 null / 忽略写入，
///   调用方回退到 KeyCrypto + settings 表的旧路径
/// - DB 中仍保留 KeyCrypto 加密副本（updateSettings 双写），
///   保证「导出数据库备份 → 换机导入」后 API Key 仍可随备份恢复
class SecureKeyStorage {
  SecureKeyStorage._();

  static const _storage = FlutterSecureStorage();
  static const _apiKeyKey = 'api_key';

  /// 读取 API Key；非 Android 或读取失败返回 null（调用方走 DB 回退）
  static Future<String?> readApiKey() async {
    if (!Platform.isAndroid) return null;
    try {
      final value = await _storage.read(key: _apiKeyKey);
      return (value == null || value.isEmpty) ? null : value;
    } catch (e) {
      DebugLogService.instance.log('SECURE', '安全存储读取失败，回退 DB: $e');
      return null;
    }
  }

  /// 写入 API Key；非 Android 或写入失败静默（DB 副本仍在）
  static Future<void> writeApiKey(String value) async {
    if (!Platform.isAndroid) return;
    try {
      await _storage.write(key: _apiKeyKey, value: value);
    } catch (e) {
      DebugLogService.instance.log('SECURE', '安全存储写入失败: $e');
    }
  }
}
