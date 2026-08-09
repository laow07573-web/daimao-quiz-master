import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 签名校验：首次运行锁定签名，后续检测变化则弹窗告警
class TamperCheck {
  static const _prefKey = 'tamper_sig';

  static Future<bool> verify() async {
    try {
      if (kDebugMode) return true;
      
      if (Platform.isAndroid) {
        return await _verifyAndroid();
      } else if (Platform.isWindows) {
        return await _verifyWindows_skip();
      }
      return true;
    } catch (_) {
      return true; // 出错不阻塞
    }
  }

  static Future<bool> _verifyAndroid() async {
    const channel = MethodChannel('com.flashcard.app/tamper');
    try {
      final hash = await channel.invokeMethod<String>('getSignatureHash');
      if (hash == null) return true;
      return await _check(hash);
    } catch (_) {
      return true;
    }
  }

  static Future<bool> _verifyWindows_skip() async {
    return true;
  }

  static Future<bool> _check(String currentHash) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefKey);
    if (stored == null) {
      // 首次运行，锁定签名
      await prefs.setString(_prefKey, currentHash);
      return true;
    }
    return stored == currentHash;
  }

  static String _quickHash(List<int> bytes) {
    var h = 0x811C9DC5;
    for (final b in bytes) {
      h ^= b;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16);
  }
}
