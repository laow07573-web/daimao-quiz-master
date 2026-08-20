import 'dart:convert';

import 'package:http/http.dart' as http;

/// 一言服务（v1.0.2）：常驻通知文案来源，失败静默回退默认文案
class HitokotoService {
  static const _defaultText = '刷题使我快乐，坚持就是胜利！';

  static String? _cache;
  static DateTime? _cacheTime;
  static const _cacheDuration = Duration(minutes: 10);
  static Future<String?>? _inflight;

  /// 拉取一言，失败或超时返回 null（调用方回退默认文案）。
  /// v1.0.2 修复：10 分钟内缓存 + 并发合并——闪屏与首页只发一次网络请求
  static Future<String?> fetch() async {
    final now = DateTime.now();
    if (_cache != null && _cacheTime != null &&
        now.difference(_cacheTime!) < _cacheDuration) {
      return _cache;
    }
    if (_inflight != null) return _inflight;
    final future = _doFetch();
    _inflight = future;
    try {
      final result = await future;
      if (result != null) {
        _cache = result;
        _cacheTime = DateTime.now();
      }
      return result;
    } finally {
      _inflight = null;
    }
  }

  static Future<String?> _doFetch() async {
    try {
      final resp = await http
          .get(Uri.parse('https://v1.hitokoto.cn/?c=k&c=i&c=d'), headers: {
        'User-Agent': 'maojuan-quiz/1.0',
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
}
