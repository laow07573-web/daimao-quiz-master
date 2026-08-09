import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// 一言服务（v1.0.2）：常驻通知文案来源，失败静默回退默认文案
class HitokotoService {
  static const _defaultText = '刷题使我快乐，坚持就是胜利！';

  /// 拉取一言，失败或超时返回 null（调用方回退默认文案）
  static Future<String?> fetch() async {
    try {
      final resp = await http
          .get(Uri.parse('https://v1.hitokoto.cn/?c=k&c=i&c=d'), headers: {
        'User-Agent': 'daimao-flashcard/1.0',
      }).timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(utf8.decode(resp.bodyBytes));
      final text = data['hitokoto'] as String?;
      if (text == null || text.trim().isEmpty) return null;
      return text.trim();
    } catch (_) {
      return null;
    }
  }

  static String get defaultText => _defaultText;

  /// 获取一言或默认文案（供常驻通知使用）
  static Future<String> fetchOrDefault() async {
    final t = await fetch();
    return t ?? _defaultText;
  }

  /// 平台判定（便于测试）
  static bool get isNetworkAvailable => !Platform.environment.containsKey('FLUTTER_TEST_NETWORK_OFF');
}
