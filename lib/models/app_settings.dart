import '../services/key_crypto.dart';

class AppSettings {
  static const String defaultApiEndpoint = 'https://api.deepseek.com/v1/chat/completions';
  static const String defaultModel = 'deepseek-chat';

  String apiKey;
  String apiEndpoint;
  String model;
  bool soundEnabled;

  AppSettings({
    this.apiKey = '',
    this.apiEndpoint = defaultApiEndpoint,
    this.model = defaultModel,
    this.soundEnabled = true,
  });

  bool get isConfigured => apiKey.isNotEmpty;

  Map<String, String> toMap() {
    return {
      'api_key': KeyCrypto.encrypt(apiKey),
      'api_endpoint': apiEndpoint,
      'model': model,
      'sound_enabled': soundEnabled ? '1' : '0',
    };
  }

  factory AppSettings.fromMap(Map<String, String> map) {
    return AppSettings(
      apiKey: KeyCrypto.decrypt(map['api_key'] ?? ''),
      apiEndpoint: map['api_endpoint'] ?? defaultApiEndpoint,
      model: map['model'] ?? defaultModel,
      soundEnabled: map['sound_enabled'] != '0',
    );
  }

  AppSettings copyWith({
    String? apiKey,
    String? apiEndpoint,
    String? model,
    bool? soundEnabled,
  }) {
    return AppSettings(
      apiKey: apiKey ?? this.apiKey,
      apiEndpoint: apiEndpoint ?? this.apiEndpoint,
      model: model ?? this.model,
      soundEnabled: soundEnabled ?? this.soundEnabled,
    );
  }
}
