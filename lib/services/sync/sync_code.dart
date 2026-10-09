import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// 局域网同步识别码（2026-10-08 用户定稿的两种形式）。
///
/// 用户原话：「识别码的形式分成两种，六位数是用于临时分享用的；而长的字符串
/// 是根据设备码加密后生成的值，要支持复制或者直接生成一个二维码，另一台设备
/// 只要通过猫卷扫码就可以连上。」
///
/// 因此有两类码，校验时**任一命中即通过**：
///
/// 1. **设备码**（长）：由本机 deviceId 经 HMAC-SHA256 派生，形如
///    `XXXX-XXXX-XXXX-XXXX`（Crockford Base32，去掉易混字符）。
///    同一台设备恒定不变 —— 适合长期配对，可复制、可生成二维码给对方扫。
///    它不是秘密口令（局域网内可见），作用只是「让对方确认自己连的是哪台设备、
///    并拒绝没带码的陌生设备」，这一点在 UI 文案上必须如实说明。
/// 2. **临时码**（6 位数字）：点一下生成，带有效期（默认 10 分钟），
///    用于当面分享题库这种一次性场景；过期即失效，不会长期留在设备上。
///
/// 码**不放进 UDP 广播信标**——发现阶段只暴露设备名与端口，
/// 校验只发生在 HTTP 请求头里，避免在局域网里被动嗅探到。
class SyncCode {
  /// 派生用的应用盐（写死在 App 内，与备份加密同源思路：只防误连，不做安全承诺）
  static const String _salt = 'maojuan.sync.code.v1';

  /// Crockford Base32 字母表：去掉 I/L/O/U，避免与 1/0 混淆，便于口头报码
  static const String _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  /// 设备码字符数（不含分组连字符）：16 位 ≈ 80 bit，足够区分设备
  static const int codeLength = 16;

  /// 临时码长度与有效期
  static const int tempCodeLength = 6;
  static const Duration tempCodeTtl = Duration(minutes: 10);

  /// 由设备 id 派生设备码（去掉分组连字符的紧凑形式）。
  ///
  /// 纯函数：同一 deviceId 永远得到同一个码，便于测试与跨会话稳定。
  static String deviceCodeOf(String deviceId) {
    final mac =
        Hmac(sha256, utf8.encode(_salt)).convert(utf8.encode(deviceId.trim()));
    final bytes = mac.bytes;
    final buf = StringBuffer();
    for (var i = 0; buf.length < codeLength; i++) {
      // 每个字节取低 5 bit 映射到字母表；用完再继续（sha256 有 32 字节，够用）
      buf.write(_alphabet[bytes[i % bytes.length] & 0x1F]);
    }
    return buf.toString();
  }

  /// 设备码的展示形式（每 4 位一组，方便抄写/报读）。
  static String formatDeviceCode(String compact) {
    final out = <String>[];
    for (var i = 0; i < compact.length; i += 4) {
      out.add(compact.substring(
          i, i + 4 > compact.length ? compact.length : i + 4));
    }
    return out.join('-');
  }

  /// 归一化用户输入：去掉连字符、空格、大小写差异（并把常见误读字符纠正回字母表）。
  static String normalize(String raw) {
    var s = raw.toUpperCase().replaceAll(RegExp(r'[^0-9A-Z]'), '');
    // Crockford 宽容映射：报码时容易把 O 念成 0、I/L 念成 1
    s = s.replaceAll('O', '0').replaceAll('I', '1').replaceAll('L', '1');
    return s;
  }

  /// 生成 6 位临时数字码（首位不为 0，便于口头报读时位数清楚）。
  static String generateTempCode([Random? random]) {
    final r = random ?? Random.secure();
    final first = 1 + r.nextInt(9);
    final rest = List.generate(tempCodeLength - 1, (_) => r.nextInt(10)).join();
    return '$first$rest';
  }

  /// 校验一个出示的码能否通过。
  ///
  /// [presented] 是请求方带来的码；[deviceCode] 是本机设备码（紧凑形式）；
  /// [tempCode]/[tempExpiry] 是当前临时码与过期时间（没有则传 null）；
  /// [now] 便于测试注入时间。
  static bool accepts({
    required String presented,
    required String deviceCode,
    String? tempCode,
    DateTime? tempExpiry,
    DateTime? now,
  }) {
    if (presented.trim().isEmpty) return false;
    final p = normalize(presented);

    // ① 设备码（长码）：允许带或不带分组连字符
    if (p.isNotEmpty && p == normalize(deviceCode)) return true;

    // ② 临时码（6 位数字）：必须未过期
    if (tempCode != null && tempCode.isNotEmpty) {
      final at = now ?? DateTime.now();
      final alive = tempExpiry == null || at.isBefore(tempExpiry);
      if (alive && p == tempCode) return true;
    }
    return false;
  }

  /// 临时码是否仍然有效（UI 用来决定显示「还有 N 分钟」还是「已过期」）。
  static bool tempCodeAlive(String? tempCode, DateTime? tempExpiry,
      {DateTime? now}) {
    if (tempCode == null || tempCode.isEmpty) return false;
    if (tempExpiry == null) return true;
    return (now ?? DateTime.now()).isBefore(tempExpiry);
  }
}
