import 'dart:convert';

/// 局域网同步：信标与设备模型（纯 `dart:io`，无第三方网络插件）

/// 已发现的同步对端
class DiscoveredPeer {
  final String deviceId;
  final String deviceName;
  final String ip;
  final int port;
  final DateTime lastSeen;

  const DiscoveredPeer({
    required this.deviceId,
    required this.deviceName,
    required this.ip,
    required this.port,
    required this.lastSeen,
  });

  DiscoveredPeer copyWith({
    String? deviceName,
    String? ip,
    int? port,
    DateTime? lastSeen,
  }) {
    return DiscoveredPeer(
      deviceId: deviceId,
      deviceName: deviceName ?? this.deviceName,
      ip: ip ?? this.ip,
      port: port ?? this.port,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DiscoveredPeer && other.deviceId == deviceId;

  @override
  int get hashCode => deviceId.hashCode;
}

/// UDP 广播信标（JSON）：设备发现与同步服务端口通告
class SyncBeacon {
  /// 协议魔数：过滤局域网内其他应用的 UDP 包
  static const String appTag = 'flashcard_sync';
  static const int protocolVersion = 1;

  final String deviceId;
  final String deviceName;
  final int port;

  const SyncBeacon({
    required this.deviceId,
    required this.deviceName,
    required this.port,
  });

  String encode() => jsonEncode({
        'app': appTag,
        'v': protocolVersion,
        'device_id': deviceId,
        'device_name': deviceName,
        'port': port,
      });

  /// 解码信标；非法/他应用数据返回 null
  static SyncBeacon? decode(String raw) {
    try {
      final dynamic parsed = jsonDecode(raw);
      if (parsed is! Map<String, dynamic>) return null;
      if (parsed['app'] != appTag) return null;
      final deviceId = parsed['device_id'];
      final port = parsed['port'];
      if (deviceId is! String || deviceId.isEmpty) return null;
      if (port is! int || port <= 0) return null;
      final name = parsed['device_name'];
      return SyncBeacon(
        deviceId: deviceId,
        deviceName: name is String ? name : '',
        port: port,
      );
    } catch (_) {
      return null;
    }
  }
}
