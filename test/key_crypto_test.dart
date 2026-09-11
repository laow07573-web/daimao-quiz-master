import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/services/key_crypto.dart';

void main() {
  group('KeyCrypto AES-256-GCM v3（改名「猫卷」新盐）', () {
    test('加解密往返', () {
      const plain = 'sk-abc1234567890';
      final enc = KeyCrypto.encrypt(plain);
      expect(KeyCrypto.decrypt(enc), plain);
    });

    test('密文带 v3: 前缀', () {
      final enc = KeyCrypto.encrypt('hello-world');
      expect(enc.startsWith('v3:'), isTrue);
    });

    test('两次加密密文不同（随机 nonce）', () {
      final a = KeyCrypto.encrypt('same-key');
      final b = KeyCrypto.encrypt('same-key');
      expect(a, isNot(b));
      expect(KeyCrypto.decrypt(a), KeyCrypto.decrypt(b));
    });

    test('篡改检测：MAC 校验失败返回空串', () {
      final enc = KeyCrypto.encrypt('secret-api-key');
      final bytes = base64Decode(enc.substring(3));
      bytes[bytes.length - 1] ^= 0x01; // 翻转 tag 的一位
      final tampered = 'v3:' + base64Encode(bytes);
      expect(KeyCrypto.decrypt(tampered), isEmpty);
    });

    test('v2 旧盐密文仍可解（改名升级兼容）', () {
      // 由改名前的 encrypt('sk-test-renaming-123') 生成的真实 v2 密文，
      // 升级后解密链必须仍能解出（旧盐仅保留解密路径）
      const v2Legacy =
          'v2:RGZ98RP7rJLCUvIURRbYfRvegORpfMyV8eD0397wpai2DU9EY37/+yjR6yupIvGh';
      expect(KeyCrypto.decrypt(v2Legacy), 'sk-test-renaming-123');
    });

    test('v1 XOR 旧格式仍可解（兼容回退）', () {
      // 用 v1 算法手工构造：XOR + base64
      final chars = 'old-key-data'.codeUnits;
      final random = Random(0x5EEDC0DE);
      final key = List.generate(chars.length, (_) => random.nextInt(256));
      final encrypted = <int>[];
      for (var i = 0; i < chars.length; i++) {
        encrypted.add(chars[i] ^ key[i]);
      }
      final v1 = base64Encode(encrypted);
      expect(KeyCrypto.decrypt(v1), 'old-key-data');
    });

    test('明文回退：非 base64 内容原样返回', () {
      const plain = 'sk-plaintext-key-not-base64!!!';
      expect(KeyCrypto.decrypt(plain), plain);
    });

    test('空串安全', () {
      expect(KeyCrypto.encrypt(''), '');
      expect(KeyCrypto.decrypt(''), '');
    });

    test('中文内容往返', () {
      const plain = '中文密钥内容-测试';
      expect(KeyCrypto.decrypt(KeyCrypto.encrypt(plain)), plain);
    });
  });
}
