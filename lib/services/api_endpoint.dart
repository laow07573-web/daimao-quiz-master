import 'dart:convert';

/// API 地址归一化 + 连通性诊断（v1.28）
///
/// 用户常直接粘贴服务商给的「基址」，写法五花八门：
///   https://api.deepseek.com
///   https://api.deepseek.com/v1
///   https://api.deepseek.com/v1/chat/completions
///   https://dashscope.aliyuncs.com/compatible-mode/v1
///   https://xxx.com/api/v1
/// 本工具统一解析为可用的 `/chat/completions` 端点，
/// 从而兼容官方 API 与绝大多数第三方（OpenAI 兼容协议）订阅。
class ApiEndpoint {
  const ApiEndpoint._();

  /// 兜底端点（与 AppSettings.defaultApiEndpoint 保持一致）
  static const String fallback =
      'https://api.deepseek.com/v1/chat/completions';

  /// 归一化为 chat/completions 端点。
  ///
  /// 规则（按序匹配，命中即停）：
  /// 1. 空 → 兜底端点
  /// 2. 已以 `/chat/completions` 结尾 → 原样
  /// 3. 以 `/completions` 结尾 → 替换为 `/chat/completions`
  /// 4. 以版本段结尾（`/v1`、`/v2`、`/v1beta`…）或 `/openai` /
  ///    `/compatible-mode` 结尾 → 追加 `/chat/completions`
  /// 5. 其他非空路径 → 追加 `/v1/chat/completions`（OpenAI 兼容惯例）
  ///
  /// 无 scheme 时补 `https://`；尾部斜杠会被去掉。
  static Uri resolve(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return Uri.parse(fallback);
    if (!s.contains('://')) s = 'https://$s';
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    final uri = Uri.tryParse(s);
    if (uri == null || uri.host.isEmpty) return Uri.parse(fallback);

    final path = uri.path;
    final lower = path.toLowerCase();

    String newPath;
    if (lower.isEmpty || lower == '/') {
      newPath = '/v1/chat/completions';
    } else if (lower.endsWith('/chat/completions')) {
      newPath = path;
    } else if (lower.endsWith('/completions')) {
      newPath =
          '${path.substring(0, path.length - '/completions'.length)}/chat/completions';
    } else if (_endsWithBaseSegment(lower)) {
      newPath = '$path/chat/completions';
    } else {
      newPath = '$path/v1/chat/completions';
    }
    return uri.replace(path: newPath);
  }

  /// 是否以「基址段」结尾（版本号 / openai / compatible-mode 等）
  static bool _endsWithBaseSegment(String lowerPath) {
    if (RegExp(r'/v\d+[a-z]*$').hasMatch(lowerPath)) return true; // /v1 /v2 /v1beta
    return lowerPath.endsWith('/openai') ||
        lowerPath.endsWith('/compatible-mode') ||
        lowerPath.endsWith('/openai-compatible');
  }

  /// 是否需要注入 OpenRouter 归因头（其服务要求/建议带上）
  static bool isOpenRouter(Uri uri) =>
      uri.host.toLowerCase().contains('openrouter.ai');

  /// opencode Zen/Go 网关（要求 x-opencode-session 才能路由与缓存）
  static bool isOpenCode(Uri uri) =>
      uri.host.toLowerCase().contains('opencode.ai');

  /// 请求用的 User-Agent。
  ///
  /// 注意：部分网关（含 opencode Zen）明确要求使用「自有产品名」而非通用
  /// SDK/HTTP 库名（Dart 默认会发 `Dart/x.y (dart:io)`，可能被拒或限流）。
  static const String userAgent = 'MaoJuanQuiz/1.0';

  /// 供应商专用请求头（v1.28）。
  ///
  /// [sessionId] 为「同一次对话保持稳定」的标识，opencode 用它做路由与
  /// prompt 缓存优化。这里传入本机设备 ID（安装期内稳定），既满足要求
  /// 又能最大化缓存命中。
  static Map<String, String> vendorHeaders(Uri chatUri,
      {required String sessionId}) {
    if (isOpenCode(chatUri)) {
      return {
        'x-opencode-session': sessionId,
        'x-opencode-client': 'maojuan',
        'x-opencode-project': 'global',
        'User-Agent': userAgent,
      };
    }
    if (isOpenRouter(chatUri)) {
      return {
        // OpenRouter 建议携带来源标识（便于统计与限流豁免）
        'HTTP-Referer': 'https://github.com/maojuan-quiz',
        'X-Title': 'MaoJuan Quiz',
        'User-Agent': userAgent,
      };
    }
    return const {'User-Agent': userAgent};
  }

  /// 由 chat 端点推导「模型列表」端点（OpenAI 兼容的 `GET /models`）。
  ///
  /// 例：`https://opencode.ai/zen/go/v1/chat/completions`
  ///   → `https://opencode.ai/zen/go/v1/models`
  ///
  /// 很多第三方网关（含 opencode）都实现了该接口，用它可以让用户
  /// 直接选模型，避免手填错名字导致 400/422。
  static Uri modelsUrl(String rawEndpoint) {
    final chat = resolve(rawEndpoint);
    var p = chat.path;
    const suffix = '/chat/completions';
    if (p.endsWith(suffix)) {
      p = p.substring(0, p.length - suffix.length);
    }
    return chat.replace(path: '$p/models');
  }

  /// 余额查询地址：官方 DeepSeek 用专用接口，其余供应商按通用路径尝试
  static Uri balanceUrl(Uri chatUri) =>
      Uri(scheme: chatUri.scheme, host: chatUri.host, path: '/user/balance');

  /// 把 HTTP 状态码翻译成用户能看懂的原因
  static String explainStatus(int status, String body) {
    final detail = _extractErrorMessage(body);
    final suffix = detail == null ? '' : '：$detail';
    switch (status) {
      case 400:
        return '请求被拒（400）$suffix';
      case 401:
        return 'API Key 无效或已过期（401）$suffix';
      case 402:
        return '余额不足或未开通（402）$suffix';
      case 403:
        return '无权限（403）$suffix';
      case 404:
        return '地址不对，接口不存在（404）$suffix';
      case 422:
        return '参数被拒（422），模型名称可能不对$suffix';
      case 429:
        return '请求过于频繁，请稍后重试（429）$suffix';
      default:
        if (status >= 500) return '服务端错误（$status），稍后重试$suffix';
        return '请求失败（$status）$suffix';
    }
  }

  /// 从响应体里提取服务商的错误说明（截断，避免过长）
  static String? _extractErrorMessage(String body) {
    if (body.trim().isEmpty) return null;
    try {
      final data = jsonDecode(body);
      final msg = data is Map
          ? (data['error'] is Map
              ? data['error']['message']
              : (data['message'] ?? data['error']))
          : null;
      if (msg == null) return null;
      var s = msg.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
      if (s.isEmpty) return null;
      if (s.length > 120) s = '${s.substring(0, 120)}…';
      return s;
    } catch (_) {
      var s = body.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (s.isEmpty) return null;
      if (s.length > 120) s = '${s.substring(0, 120)}…';
      return s;
    }
  }
}
