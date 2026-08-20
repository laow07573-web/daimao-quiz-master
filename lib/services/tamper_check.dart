import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 签名校验（v1.0.2 设计审查修复：fail-closed）
///
/// - 比对目标为编译期硬编码的官方签名 hash（首次锁存存 SharedPreferences
///   可被「清除应用数据」重置绕过，硬编码不可绕过）
/// - release 构建下校验失败/通道异常一律拒绝启动（此前所有异常路径
///   都放行，防篡改形同虚设）；debug 构建放行便于开发
class TamperCheck {
  /// 官方签名 SHA-256 前 16 位（Base64）。
  /// 由正式证书（android/app/keystore/猫卷_正式签名.jks，别名 quiz）计算：
  /// SHA-256 → Base64 → 取前 16 位（与 MainActivity.getSignatureHash 输出格式一致）
  static const String officialHash = 'Q6ngoZDOGzAlUFW0';

  static Future<bool> verify() async {
    try {
      if (kDebugMode) return true;

      if (Platform.isAndroid) {
        return await _verifyAndroid();
      }
      // 桌面/其他平台无签名校验概念，放行
      return true;
    } catch (_) {
      return false; // v1.0.2 设计审查修复：异常不再放行
    }
  }

  static Future<bool> _verifyAndroid() async {
    const channel = MethodChannel('com.flashcard.app/tamper');
    try {
      final hash = await channel.invokeMethod<String>('getSignatureHash');
      if (hash == null) return false;
      return hash == officialHash;
    } catch (_) {
      return false;
    }
  }
}
