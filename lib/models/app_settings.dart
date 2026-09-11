import '../services/key_crypto.dart';

/// 预设供应商（v1.28）：一键填入端点 + 模型，降低第三方接入门槛。
/// 所有条目均为 OpenAI 兼容协议；用户也可手动填任意官方/第三方地址。
class ApiPreset {
  final String name;
  final String endpoint;
  final String model;
  final String hint;
  const ApiPreset(this.name, this.endpoint, this.model, this.hint);
}

/// 常见供应商预设（端点写基址即可，运行时会自动补全 /chat/completions）
const List<ApiPreset> kApiPresets = [
  ApiPreset('DeepSeek 官方', 'https://api.deepseek.com/v1', 'deepseek-chat',
      '国内直连，性价比高'),
  ApiPreset('阿里云百炼（通义）',
      'https://dashscope.aliyuncs.com/compatible-mode/v1', 'qwen-plus',
      '阿里云百炼，OpenAI 兼容模式'),
  ApiPreset('硅基流动', 'https://api.siliconflow.cn/v1',
      'deepseek-ai/DeepSeek-V3', '聚合多家开源模型'),
  ApiPreset('智谱 GLM', 'https://open.bigmodel.cn/api/paas/v4',
      'glm-4-flash', '清华智谱，有免费额度'),
  ApiPreset('月之暗面 Kimi', 'https://api.moonshot.cn/v1',
      'moonshot-v1-8k', '长文本见长'),
  ApiPreset('OpenAI 官方', 'https://api.openai.com/v1', 'gpt-4o-mini',
      '需自备网络环境'),
  ApiPreset('OpenRouter', 'https://openrouter.ai/api/v1',
      'deepseek/deepseek-chat', '聚合全球模型（含免费额度）'),
  ApiPreset('OpenCode Go', 'https://opencode.ai/zen/go/v1', 'glm-5.3-flash',
      'Go 订阅（\$10/月），点「选择模型」可列出全部'),
  ApiPreset('本地 Ollama', 'http://localhost:11434/v1', 'llama3.1',
      '本地部署，需自行启动服务'),
];

class AppSettings {
  static const String defaultApiEndpoint = 'https://api.deepseek.com/v1/chat/completions';
  static const String defaultModel = 'deepseek-chat';

  String apiKey;
  String apiEndpoint;
  String model;
  bool soundEnabled;
  String nickname; // v1.0.2 对齐里程碑：昵称（首页专属问候）
  bool autoSync; // 局域网同步：自动同步开关（开启后广播信标并自动与发现的设备同步）
  String deviceName; // 局域网同步：本机设备名（缺省由 DeviceService 生成「猫卷-平台」）

  AppSettings({
    this.apiKey = '',
    this.apiEndpoint = defaultApiEndpoint,
    this.model = defaultModel,
    this.soundEnabled = true,
    this.nickname = '',
    this.autoSync = false,
    this.deviceName = '',
  });

  bool get isConfigured => apiKey.isNotEmpty;

  Map<String, String> toMap() {
    return {
      'api_key': KeyCrypto.encrypt(apiKey),
      'api_endpoint': apiEndpoint,
      'model': model,
      'sound_enabled': soundEnabled ? '1' : '0',
      'nickname': nickname,
      'auto_sync': autoSync ? '1' : '0',
      'device_name': deviceName,
    };
  }

  factory AppSettings.fromMap(Map<String, String> map) {
    return AppSettings(
      apiKey: KeyCrypto.decrypt(map['api_key'] ?? ''),
      apiEndpoint: map['api_endpoint'] ?? defaultApiEndpoint,
      model: map['model'] ?? defaultModel,
      soundEnabled: map['sound_enabled'] != '0',
      nickname: map['nickname'] ?? '',
      autoSync: map['auto_sync'] == '1',
      deviceName: map['device_name'] ?? '',
    );
  }

  AppSettings copyWith({
    String? apiKey,
    String? apiEndpoint,
    String? model,
    bool? soundEnabled,
    String? nickname,
    bool? autoSync,
    String? deviceName,
  }) {
    return AppSettings(
      apiKey: apiKey ?? this.apiKey,
      apiEndpoint: apiEndpoint ?? this.apiEndpoint,
      model: model ?? this.model,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      nickname: nickname ?? this.nickname,
      autoSync: autoSync ?? this.autoSync,
      deviceName: deviceName ?? this.deviceName,
    );
  }
}
