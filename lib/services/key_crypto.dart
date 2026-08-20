import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// API Key 加密（v1.0.2 升级：AES-256-GCM；改名「猫卷」后换新盐 v3）
///
/// 密文格式（v3）：`v3:` + base64(nonce12 ‖ ciphertext ‖ tag16)
/// 密钥 = 固定盐经 SHA-256 派生（与 v1 的固定种子同级别的"混淆级"设计）
///
/// 解密回退链：v3（新盐）→ v2（旧盐，升级前已存密文）→ v1 XOR
/// （严格 base64 字符集校验）→ 明文（旧数据兼容）
/// 篡改检测：GCM MAC 校验失败返回空串
class KeyCrypto {
  static const _seed = 0x5EEDC0DE;

  // ---------------- v3: AES-256-GCM（猫卷新盐） ----------------

  static const _v3Prefix = 'v3:';
  static const _nonceLen = 12;
  static const _tagLen = 16;
  static const _v3Salt = 'maojuan-quiz-salt-v3';

  // ---------------- v2: 旧盐（仅用于解密升级前的历史密文） ----------------

  static const _v2Prefix = 'v2:';
  static const _v2LegacySalt = 'daimao-quiz-flashcard-salt-v2';

  /// 密钥 = 盐 SHA-256 派生
  static Uint8List _deriveKey(String salt) {
    final digest = SHA256Digest();
    var input = Uint8List.fromList(utf8.encode(salt));
    // 多轮哈希增强（轻量 KDF）
    for (var i = 0; i < 1000; i++) {
      input = digest.process(input);
    }
    return input;
  }

  static Uint8List _aesGcmEncrypt(Uint8List key, Uint8List nonce, Uint8List plain) {
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(KeyParameter(key), _tagLen * 8, nonce, Uint8List(0)),
      );
    final out = Uint8List(cipher.getOutputSize(plain.length));
    final len1 = cipher.processBytes(plain, 0, plain.length, out, 0);
    // 注意：doFinal 返回值是实际写入长度，必须 len1 + len2 截取
    // （加密端输出含 tag，解密端输出为明文长度）
    final len2 = cipher.doFinal(out, len1);
    return Uint8List.sublistView(out, 0, len1 + len2);
  }

  static Uint8List? _aesGcmDecrypt(
      Uint8List key, Uint8List nonce, Uint8List ciphertextAndTag) {
    try {
      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          false,
          AEADParameters(KeyParameter(key), _tagLen * 8, nonce, Uint8List(0)),
        );
      final out = Uint8List(cipher.getOutputSize(ciphertextAndTag.length));
      final len1 =
          cipher.processBytes(ciphertextAndTag, 0, ciphertextAndTag.length, out, 0);
      final len2 = cipher.doFinal(out, len1);
      return Uint8List.sublistView(out, 0, len1 + len2);
    } catch (_) {
      return null; // MAC 校验失败或数据损坏
    }
  }

  static String encrypt(String plain) {
    if (plain.isEmpty) return '';
    final key = _deriveKey(_v3Salt);
    final nonce = _randomBytes(_nonceLen);
    final ciphertext = _aesGcmEncrypt(key, nonce, Uint8List.fromList(utf8.encode(plain)));
    final combined = Uint8List(_nonceLen + ciphertext.length)
      ..setRange(0, _nonceLen, nonce)
      ..setRange(_nonceLen, _nonceLen + ciphertext.length, ciphertext);
    return _v3Prefix + base64.encode(combined);
  }

  static String decrypt(String encoded) {
    if (encoded.isEmpty) return '';

    // v3: 猫卷新盐（当前版本加密格式）
    if (encoded.startsWith(_v3Prefix)) {
      return _gcmDecode(encoded.substring(_v3Prefix.length), _v3Salt) ?? '';
    }

    // v2: 旧盐（改名前的历史密文，回退解密保证已存数据可读）
    if (encoded.startsWith(_v2Prefix)) {
      return _gcmDecode(encoded.substring(_v2Prefix.length), _v2LegacySalt) ?? '';
    }

    // v1: XOR（严格 base64 字符集校验，防止把明文当密文解）
    if (_isStrictBase64(encoded)) {
      try {
        final encrypted = base64.decode(encoded);
        final random = Random(_seed);
        final key = List.generate(encrypted.length, (_) => random.nextInt(256));
        final decrypted = <int>[];
        for (var i = 0; i < encrypted.length; i++) {
          decrypted.add(encrypted[i] ^ key[i]);
        }
        final result = String.fromCharCodes(decrypted);
        // 可读性校验：v1 密文解出的必是真实 key（sk- 开头 ASCII）；
        // 乱码（含大量控制字符）说明是"恰好符合 base64 字符集的明文"被误解 → 按明文返回
        if (_isReadable(result)) return result;
      } catch (_) {
        // 落入下方明文回退
      }
    }

    // 旧版明文 Key，直接返回
    return encoded;
  }

  /// GCM 密文体（不含前缀）按指定盐解密；失败（MAC 校验/格式/编码）返回 null
  static String? _gcmDecode(String body, String salt) {
    final raw = _tryBase64(body);
    if (raw == null || raw.length < _nonceLen + _tagLen) return null;
    final nonce = Uint8List.sublistView(raw, 0, _nonceLen);
    final ciphertextAndTag = Uint8List.sublistView(raw, _nonceLen);
    final plain = _aesGcmDecrypt(_deriveKey(salt), nonce, ciphertextAndTag);
    if (plain == null) return null; // MAC 校验失败或数据损坏
    try {
      return utf8.decode(plain);
    } catch (_) {
      return null;
    }
  }

  /// 可读性校验：控制字符/替换符比例低（用于区分 v1 XOR 解出的真实 key 与乱码）
  static bool _isReadable(String s) {
    if (s.isEmpty) return false;
    var bad = 0;
    for (final c in s.codeUnits) {
      if (c < 32 || c == 0xFFFD) bad++;
    }
    return bad / s.length < 0.1;
  }

  static Uint8List _randomBytes(int len) {
    final bytes = Uint8List(len);
    final rng = Random.secure();
    for (var i = 0; i < len; i++) {
      bytes[i] = rng.nextInt(256);
    }
    return bytes;
  }

  static Uint8List? _tryBase64(String s) {
    try {
      return base64.decode(s);
    } catch (_) {
      return null;
    }
  }

  /// 严格 base64 字符集校验（允许尾随 1~2 个 =）
  static bool _isStrictBase64(String s) {
    if (s.isEmpty || s.length % 4 != 0) return false;
    return RegExp(r'^[A-Za-z0-9+/]+={0,2}$').hasMatch(s);
  }
}
