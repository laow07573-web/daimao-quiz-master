import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/services/api_endpoint.dart';
import 'package:flashcard_app/models/app_settings.dart';
import 'package:flashcard_app/services/ai_service.dart';

/// API 端点归一化（v1.28：兼容官方 + 第三方 OpenAI 兼容订阅）。
void main() {
  group('端点归一化', () {
    test('空值 → 兜底端点', () {
      expect(ApiEndpoint.resolve('').toString(),
          'https://api.deepseek.com/v1/chat/completions');
      expect(ApiEndpoint.resolve('   ').toString(),
          'https://api.deepseek.com/v1/chat/completions');
    });

    test('已完整的 chat/completions 原样保留', () {
      expect(
          ApiEndpoint.resolve('https://api.deepseek.com/v1/chat/completions')
              .toString(),
          'https://api.deepseek.com/v1/chat/completions');
    });

    test('以 /completions 结尾 → 补 chat', () {
      expect(ApiEndpoint.resolve('https://x.com/v1/completions').toString(),
          'https://x.com/v1/chat/completions');
    });

    test('仅主机名 → 补 /v1/chat/completions', () {
      expect(ApiEndpoint.resolve('https://api.deepseek.com').toString(),
          'https://api.deepseek.com/v1/chat/completions');
    });

    test('以版本段结尾 → 追加 chat/completions', () {
      expect(ApiEndpoint.resolve('https://api.deepseek.com/v1').toString(),
          'https://api.deepseek.com/v1/chat/completions');
      expect(ApiEndpoint.resolve('https://api.moonshot.cn/v1').toString(),
          'https://api.moonshot.cn/v1/chat/completions');
      expect(ApiEndpoint.resolve('https://open.bigmodel.cn/api/paas/v4').toString(),
          'https://open.bigmodel.cn/api/paas/v4/chat/completions');
      expect(
          ApiEndpoint.resolve(
                  'https://dashscope.aliyuncs.com/compatible-mode/v1')
              .toString(),
          'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions');
    });

    test('无 scheme → 自动补 https', () {
      expect(ApiEndpoint.resolve('api.deepseek.com/v1').toString(),
          'https://api.deepseek.com/v1/chat/completions');
    });

    test('尾部斜杠被清理', () {
      expect(ApiEndpoint.resolve('https://api.deepseek.com/v1/').toString(),
          'https://api.deepseek.com/v1/chat/completions');
      expect(ApiEndpoint.resolve('https://api.deepseek.com/v1///').toString(),
          'https://api.deepseek.com/v1/chat/completions');
    });

    test('未知路径 → 追加 /v1/chat/completions（OpenAI 兼容惯例）', () {
      expect(ApiEndpoint.resolve('https://my-proxy.com/api').toString(),
          'https://my-proxy.com/api/v1/chat/completions');
    });

    test('本地地址（Ollama 等）保持 scheme 与端口', () {
      expect(
          ApiEndpoint.resolve('http://localhost:11434/v1').toString(),
          'http://localhost:11434/v1/chat/completions');
    });

    test('所有内置预设都能归一化出 chat/completions 端点', () {
      for (final p in kApiPresets) {
        final u = ApiEndpoint.resolve(p.endpoint);
        expect(u.toString().endsWith('/chat/completions'), isTrue,
            reason: '${p.name} 应解析为 chat/completions 端点，实际 ${u.toString()}');
        expect(u.host, isNotEmpty, reason: '${p.name} 应有主机名');
      }
    });
  });

  group('辅助能力', () {
    test('OpenRouter 识别（用于注入归因头）', () {
      expect(
          ApiEndpoint.isOpenRouter(
              Uri.parse('https://openrouter.ai/api/v1/chat/completions')),
          isTrue);
      expect(
          ApiEndpoint.isOpenRouter(
              Uri.parse('https://api.deepseek.com/v1/chat/completions')),
          isFalse);
    });

    test('余额地址只保留 scheme+host', () {
      final b = ApiEndpoint.balanceUrl(
          Uri.parse('https://api.deepseek.com/v1/chat/completions'));
      expect(b.toString(), 'https://api.deepseek.com/user/balance');
    });

    test('状态码解释：401 / 404 / 429 有可读文案', () {
      expect(ApiEndpoint.explainStatus(401, ''), contains('API Key'));
      expect(ApiEndpoint.explainStatus(404, ''), contains('地址'));
      expect(ApiEndpoint.explainStatus(429, ''), contains('频繁'));
      expect(ApiEndpoint.explainStatus(500, ''), contains('服务端'));
    });

    test('状态码解释：提取服务商错误信息并截断', () {
      final msg = ApiEndpoint.explainStatus(
          400, '{"error":{"message":"model not found"}}');
      expect(msg, contains('model not found'));
      final long = ApiEndpoint.explainStatus(400, 'x' * 500);
      expect(long.length, lessThan(200), reason: '长错误信息应截断');
    });
  });

  group('预设列表', () {
    test('覆盖主流官方与第三方（含 OpenRouter/Ollama）', () {
      final names = kApiPresets.map((p) => p.name).join(',');
      expect(names, contains('DeepSeek'));
      expect(names, contains('通义'));
      expect(names, contains('OpenRouter'));
      expect(names, contains('Ollama'));
      expect(kApiPresets.length, greaterThanOrEqualTo(6));
    });

    test('每条预设都有端点/模型/hint，且端点 Unique（自定义除外）', () {
      final endpoints = <String>{};
      for (final p in kApiPresets) {
        expect(p.hint, isNotEmpty);
        // 「自定义」预设刻意留空，由用户手填，不参与该不变量
        if (p.isCustom) {
          expect(p.endpoint, isEmpty);
          continue;
        }
        expect(p.endpoint, isNotEmpty);
        expect(p.model, isNotEmpty);
        expect(endpoints.add(p.endpoint), isTrue,
            reason: '端点不应重复：${p.endpoint}');
      }
      // 至少有一个「自定义」入口
      expect(kApiPresets.any((p) => p.isCustom), isTrue);
    });
  });
  group('AIService.testConnection 输入校验（不发网络请求）', () {
    test('未填 API Key → 明确提示', () async {
      final svc = AIService(AppSettings(apiKey: ''));
      final (ok, msg) = await svc.testConnection();
      expect(ok, isFalse);
      expect(msg, contains('API Key'));
      svc.dispose();
    });
  });
  group('供应商专用头（v1.28 第三方兼容）', () {
    test('opencode 网关注入 x-opencode-session（用户 400 报错根因）', () {
      final uri =
          ApiEndpoint.resolve('https://opencode.ai/zen/go/v1/chat/completions');
      final h = ApiEndpoint.vendorHeaders(uri, sessionId: 'sess-123');
      expect(h['x-opencode-session'], 'sess-123',
          reason: '缺少该头会返回 400「cannot be routed efficiently」');
      expect(h['x-opencode-client'], isNotNull);
      expect(h['User-Agent'], ApiEndpoint.userAgent);
    });

    test('OpenRouter 注入归因头', () {
      final uri = ApiEndpoint.resolve('https://openrouter.ai/api/v1');
      final h = ApiEndpoint.vendorHeaders(uri, sessionId: 's');
      expect(h['HTTP-Referer'], isNotNull);
      expect(h['X-Title'], isNotNull);
    });

    test('普通供应商只带自定义 UA（不用 Dart 默认 UA）', () {
      final uri = ApiEndpoint.resolve('https://api.deepseek.com/v1');
      final h = ApiEndpoint.vendorHeaders(uri, sessionId: 's');
      expect(h['User-Agent'], 'MaoJuanQuiz/1.0');
      expect(h.containsKey('x-opencode-session'), isFalse);
    });

    test('UA 不应是通用 SDK 名（部分网关据此限流）', () {
      expect(ApiEndpoint.userAgent, isNot(contains('Dart')));
      expect(ApiEndpoint.userAgent, isNot(contains('http')));
    });
  });

  group('模型列表端点推导', () {
    test('由 chat 端点推导 /models', () {
      expect(
          ApiEndpoint.modelsUrl('https://opencode.ai/zen/go/v1/chat/completions')
              .toString(),
          'https://opencode.ai/zen/go/v1/models');
      expect(ApiEndpoint.modelsUrl('https://api.deepseek.com/v1').toString(),
          'https://api.deepseek.com/v1/models');
      expect(ApiEndpoint.modelsUrl('https://api.deepseek.com').toString(),
          'https://api.deepseek.com/v1/models');
    });
  });
}
