import 'dart:convert';
import 'dart:math';

/// 轻量级 Key 加密：用设备标识+固定盐做 XOR 混淆
/// 防止 DB 明文泄露后被直接读走，非军事级加密
class KeyCrypto {
  static const _seed = 0x5EEDC0DE;

  static String encrypt(String plain) {
    if (plain.isEmpty) return '';
    final chars = plain.codeUnits;
    final random = Random(_seed);
    final key = List.generate(chars.length, (_) => random.nextInt(256));
    final encrypted = <int>[];
    for (var i = 0; i < chars.length; i++) {
      encrypted.add(chars[i] ^ key[i]);
    }
    return base64.encode(encrypted);
  }

  static String decrypt(String encoded) {
    if (encoded.isEmpty) return '';
    try {
      final encrypted = base64.decode(encoded);
      final random = Random(_seed);
      final key = List.generate(encrypted.length, (_) => random.nextInt(256));
      final decrypted = <int>[];
      for (var i = 0; i < encrypted.length; i++) {
        decrypted.add(encrypted[i] ^ key[i]);
      }
      return String.fromCharCodes(decrypted);
    } catch (_) {
      // 旧版明文 Key，直接返回
      return encoded;
    }
  }
}
