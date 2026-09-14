import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// 加密备份文件（口令保护）的容器格式与加解密。
///
/// **为什么需要它**：导出备份就是整库文件拷贝，`settings` 表里的 `api_key`
/// 密文会随之进入备份；而那条密文的密钥是 [KeyCrypto] 里写死的盐——
/// **拿到备份就能解出 API Key**。所以从 1.28.2 起：
///   · 默认导出**不含** API Key（副本里直接删掉该行）；
///   · 需要带 Key 迁移时，用本类对整个备份文件做口令加密。
///
/// **文件格式**（固定头 + AEAD 密文）：
/// ```
///   偏移  长度  内容
///   0     5     magic "MJBAK"
///   5     1     格式版本（当前 1）
///   6     1     KDF 迭代档位码（见 _iterationsByCode）
///   7     16    PBKDF2 盐（随机）
///   23    12    GCM nonce（随机）
///   35    ...   AES-256-GCM 密文 ‖ 16 字节 tag
/// ```
/// 头里存的是**档位码而不是迭代次数**：将来提高强度时，新文件用新档位，
/// 旧文件仍能按自己记录的档位解密。
///
/// **密钥派生**：PBKDF2-HMAC-SHA256，默认 10 万次迭代（纯 Dart 下本机约
/// 1.3 秒，低端手机约 2–4 秒——导出/导入是一次性操作，可接受；之所以不用
/// 更高档位，是因为 pointycastle 是纯 Dart 实现，迭代成本比原生高得多）。
///
/// **口令错误与文件损坏无法区分**：GCM 的 MAC 校验失败一律返回 null，
/// 由调用方提示「口令错误或文件已损坏」——这是刻意的，不泄露额外信息。
class BackupCrypto {
  BackupCrypto._();

  /// 文件魔数（ASCII "MJBAK"）
  static const List<int> magic = [0x4D, 0x4A, 0x42, 0x41, 0x4B];

  /// 当前格式版本
  static const int formatVersion = 1;

  static const int _saltLen = 16;
  static const int _nonceLen = 12;
  static const int _tagLen = 16;

  /// 固定头长度：magic(5) + version(1) + iterCode(1) + salt(16) + nonce(12)
  static const int headerLength = 5 + 1 + 1 + _saltLen + _nonceLen; // 35

  /// 迭代档位码 → 实际迭代次数。新增档位时往后加，不要改已有映射。
  static const Map<int, int> iterationsByCode = {
    1: 100000,
  };

  /// 默认档位
  static const int defaultIterCode = 1;

  /// 判断一段字节流的开头是否为本类的容器（只比对魔数，不校验完整性）。
  static bool looksEncrypted(List<int> head) {
    if (head.length < magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (head[i] != magic[i]) return false;
    }
    return true;
  }

  /// 派生密钥：PBKDF2-HMAC-SHA256(password, salt, iterations) → 32 字节
  static Uint8List deriveKey(String password, Uint8List salt, int iterations) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, iterations, 32));
    return derivator.process(Uint8List.fromList(password.codeUnits));
  }

  /// 加密整个 [plain]，返回容器字节。
  ///
  /// 入参用 `List<int>` 而不是 Uint8List：调用方（File.readAsBytes 之外的场景、
  /// 测试里的字面量）不必再引入 dart:typed_data。
  static Uint8List encrypt(
    List<int> plain,
    String password, {
    int iterCode = defaultIterCode,
  }) {
    final iterations = iterationsByCode[iterCode];
    if (iterations == null) {
      throw ArgumentError('未知的 KDF 档位码: $iterCode');
    }
    final data = Uint8List.fromList(plain);
    final salt = _randomBytes(_saltLen);
    final nonce = _randomBytes(_nonceLen);
    final key = deriveKey(password, salt, iterations);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), _tagLen * 8, nonce, Uint8List(0)));
    final out = Uint8List(cipher.getOutputSize(data.length));
    final len1 = cipher.processBytes(data, 0, data.length, out, 0);
    final len2 = cipher.doFinal(out, len1);

    final result = Uint8List(headerLength + len1 + len2);
    result.setRange(0, 5, magic);
    result[5] = formatVersion;
    result[6] = iterCode;
    result.setRange(7, 7 + _saltLen, salt);
    result.setRange(7 + _saltLen, headerLength, nonce);
    result.setRange(headerLength, headerLength + len1 + len2, out);
    return result;
  }

  /// 解密容器。口令错误、格式不符或文件损坏一律返回 null。
  static Uint8List? decrypt(List<int> container, String password) {
    if (container.length < headerLength + _tagLen) return null;
    if (!looksEncrypted(container)) return null;

    // sublistView 要求 TypedData，统一转一次
    final data = container is Uint8List ? container : Uint8List.fromList(container);

    final version = data[5];
    if (version != formatVersion) return null; // 未来格式：由调用方提示升级 App

    final iterCode = data[6];
    final iterations = iterationsByCode[iterCode];
    if (iterations == null) return null;

    final salt = Uint8List.sublistView(data, 7, 7 + _saltLen);
    final nonce = Uint8List.sublistView(data, 7 + _saltLen, headerLength);
    final body = Uint8List.sublistView(data, headerLength);

    final key = deriveKey(password, salt, iterations);
    try {
      final cipher = GCMBlockCipher(AESEngine())
        ..init(false, AEADParameters(KeyParameter(key), _tagLen * 8, nonce, Uint8List(0)));
      final out = Uint8List(cipher.getOutputSize(body.length));
      final len1 = cipher.processBytes(body, 0, body.length, out, 0);
      final len2 = cipher.doFinal(out, len1);
      return Uint8List.sublistView(out, 0, len1 + len2);
    } catch (_) {
      return null; // MAC 校验失败：口令错误或数据被改动
    }
  }

  static Uint8List _randomBytes(int len) {
    final bytes = Uint8List(len);
    final rng = Random.secure();
    for (var i = 0; i < len; i++) {
      bytes[i] = rng.nextInt(256);
    }
    return bytes;
  }
}
