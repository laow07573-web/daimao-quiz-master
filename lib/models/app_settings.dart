import '../services/key_crypto.dart';

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
