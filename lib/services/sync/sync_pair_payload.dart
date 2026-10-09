/// 同步配对二维码的载荷编解码（纯函数，无平台依赖）。
///
/// 用户要求：「长的字符串是根据设备码加密后生成的值，要支持复制或者直接生成
/// 一个二维码，另一台设备只要通过猫卷扫码就可以连上。」
///
/// 二维码只放**识别码 + 设备展示信息 + 当前地址**，不放任何学习数据：
///
/// ```text
/// maojuan-sync:1?code=ABCDEFGH12345678&name=小米15&ip=192.168.1.7&port=51630
/// ```
///
/// - `code` 必需：对端据此通过识别码门禁
/// - `name` 可选：扫码后给用户看一眼「连的是谁」
/// - `ip`/`port` 可选：带上就能扫完立即同步，不必等 UDP 发现（地址会随
///   DHCP 变化，所以它只是加速项，发现机制仍然是主力）
class SyncPairPayload {
  /// 协议前缀（避免扫到别的应用的二维码就乱连）
  static const String scheme = 'maojuan-sync';

  /// 载荷版本：将来改字段时用它做兼容判断
  static const int version = 1;

  final String code;
  final String deviceName;
  final String? ip;
  final int? port;

  const SyncPairPayload({
    required this.code,
    this.deviceName = '',
    this.ip,
    this.port,
  });

  /// 是否带可用地址（带则扫码后可立即发起同步）
  bool get hasAddress =>
      ip != null && ip!.isNotEmpty && port != null && port! > 0;

  String encode() {
    final params = <String, String>{
      'code': code,
      if (deviceName.isNotEmpty) 'name': deviceName,
      if (ip != null && ip!.isNotEmpty) 'ip': ip!,
      if (port != null && port! > 0) 'port': '$port',
    };
    final query = params.entries
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    return '$scheme:$version?$query';
  }

  /// 解析扫码结果；不是本应用的配对码（或缺少 code）时返回 null。
  static SyncPairPayload? decode(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    // 允许直接扫到裸识别码（用户手抄或用系统相机识别后粘贴）
    if (!text.startsWith('$scheme:')) {
      final bare = _normalizeBare(text);
      return bare == null ? null : SyncPairPayload(code: bare);
    }
    try {
      final rest = text.substring('$scheme:'.length);
      final qIndex = rest.indexOf('?');
      if (qIndex < 0) return null;
      final v = int.tryParse(rest.substring(0, qIndex));
      // 版本不认识就拒绝，避免误读未来格式
      if (v == null || v > version) return null;
      final params = Uri.splitQueryString(rest.substring(qIndex + 1));
      final code = (params['code'] ?? '').trim();
      if (code.isEmpty) return null;
      final port = int.tryParse((params['port'] ?? '').trim());
      final ip = (params['ip'] ?? '').trim();
      return SyncPairPayload(
        code: code,
        deviceName: (params['name'] ?? '').trim(),
        ip: ip.isEmpty ? null : ip,
        port: (port == null || port <= 0) ? null : port,
      );
    } catch (_) {
      return null;
    }
  }

  /// 裸码（不含协议前缀）的宽松识别：6 位数字或 [SyncCode] 长码字符集。
  static String? _normalizeBare(String text) {
    final compact = text.replaceAll(RegExp(r'[^0-9A-Za-z]'), '').toUpperCase();
    if (compact.length == 6 && int.tryParse(compact) != null) return compact;
    if (compact.length == 16 &&
        RegExp(r'^[0-9A-HJKMNP-TV-Z]+$').hasMatch(compact)) {
      return compact;
    }
    return null;
  }
}
