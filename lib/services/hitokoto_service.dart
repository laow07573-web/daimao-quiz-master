import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

/// 一言服务（v1.0.2）：常驻通知文案来源，失败静默回退。
/// v1.27 PC 加载修复：内置本地一言库兜底 + 立即显示（不再先显示「正在加载一言...」）
/// + 失败冷却（断网时不再每次进首页都等 5 秒超时）。
class HitokotoService {
  static const _defaultText = '刷题使我快乐，坚持就是胜利！';
  static final _rng = Random();

  /// v1.27：本地一言库——网络不可达（断网/内网/IPv6 挂起）时随机取用，
  /// 体验上永远有内容可显示，不依赖外网。
  static const List<String> _localQuotes = [
    '刷题使我快乐，坚持就是胜利！',
    '不积跬步，无以至千里。',
    '书山有路勤为径，学海无涯苦作舟。',
    '业精于勤，荒于嬉；行成于思，毁于随。',
    '今日事，今日毕。',
    '学如逆水行舟，不进则退。',
    '天行健，君子以自强不息。',
    '千里之行，始于足下。',
    '锲而不舍，金石可镂。',
    '知之者不如好之者，好之者不如乐之者。',
    '学而不思则罔，思而不学则殆。',
    '三人行，必有我师焉。',
    '温故而知新，可以为师矣。',
    '敏而好学，不耻下问。',
    '读书破万卷，下笔如有神。',
    '少壮不努力，老大徒伤悲。',
    '黑发不知勤学早，白首方悔读书迟。',
    '纸上得来终觉浅，绝知此事要躬行。',
    '问渠那得清如许，为有源头活水来。',
    '欲穷千里目，更上一层楼。',
    '路曼曼其修远兮，吾将上下而求索。',
    '宝剑锋从磨砺出，梅花香自苦寒来。',
    '有志者，事竟成。',
    '功不唐捐，玉汝于成。',
    '日拱一卒，功不唐捐。',
    '种一棵树最好的时间是十年前，其次是现在。',
    '星光不负赶路人。',
    '你背单词时，阿拉斯加的鳕鱼正跃出水面。',
    '将来的你，一定会感谢现在拼命的自己。',
    '每天进步一点点，坚持带来大改变。',
    '与其临渊羡鱼，不如退而结网。',
    '博观而约取，厚积而薄发。',
    '读书不觉已春深，一寸光阴一寸金。',
    '少年易老学难成，一寸光阴不可轻。',
    '盛年不重来，一日难再晨。',
    '及时当勉励，岁月不待人。',
  ];

  static String? _cache;
  static DateTime? _cacheTime;
  static const _cacheDuration = Duration(minutes: 10);
  static Future<String?>? _inflight;

  /// v1.27：上次网络失败时间——冷却期内直接走本地一言库，
  /// 避免断网时每次进首页都干等 5 秒超时。
  static DateTime? _lastFailTime;
  static const _failCooldown = Duration(minutes: 2);

  /// v1.27：首屏立即展示文案（网络缓存 → 本地一言库），
  /// 永远不显示「正在加载一言...」占位。
  static String immediateText() => _cache ?? _localQuote();

  /// 网络失败时的兜底文案：从本地一言库随机取（不再固定一句）。
  static String fallbackText() => _localQuote();

  static String _localQuote() =>
      _localQuotes[_rng.nextInt(_localQuotes.length)];

  /// 拉取一言，失败或超时返回 null（调用方回退本地一言库）。
  /// v1.0.2 修复：10 分钟内缓存 + 并发合并——闪屏与首页只发一次网络请求。
  /// v1.27：失败冷却期内直接返回缓存/本地文案，不发请求。
  static Future<String?> fetch() async {
    final now = DateTime.now();
    if (_cache != null && _cacheTime != null &&
        now.difference(_cacheTime!) < _cacheDuration) {
      return _cache;
    }
    if (_lastFailTime != null &&
        now.difference(_lastFailTime!) < _failCooldown) {
      // 断网冷却：直接用本地一言，不阻塞等待。
      return null;
    }
    if (_inflight != null) return _inflight;
    final future = _doFetch();
    _inflight = future;
    try {
      final result = await future;
      if (result != null) {
        _cache = result;
        _cacheTime = DateTime.now();
        _lastFailTime = null;
      } else {
        _lastFailTime = DateTime.now();
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

  /// 获取一言或兜底文案（供常驻通知使用；失败回退本地一言库）。
  static Future<String> fetchOrDefault() async {
    final t = await fetch();
    return t ?? fallbackText();
  }
}
