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

/// 同名题库冲突（2026-10-09 用户要求）。
///
/// 用户原话：「同名题库的话，先进行校验比较两份题库和题库附属的内容的文件
/// 是否不一样，若一样则不更新，若不一样则提示是否覆盖或者增添（把题库和附属
/// 文件中相当于本机题库和附属文件中多出来的部分添加到本机的题库和其附属文件
/// 中）。」
///
/// 因此导入时遇到同名（uid 不同、名字相同）题库先比对内容指纹：
/// - 完全一致 → 直接跳过，不动本机数据；
/// - 不一致 → 生成一条冲突挂起，**本批不合并该题库及其题目**，
///   等用户在首页决定「覆盖」还是「增添」。
///
/// 冲突里带着对端该题库的原始数据（题库行 + 题目 + 配图），
/// 所以用户决策时不需要重新联网——这也是可以只放内存的原因。
class SyncBankConflict {
  const SyncBankConflict({
    required this.name,
    required this.peerBankUid,
    required this.peerBank,
    required this.peerQuestions,
    required this.peerImages,
    required this.localBankId,
    required this.localCount,
    required this.peerCount,
    required this.additionCount,
    required this.peerDeviceName,
  });

  /// 题库名（两端同名，这才叫冲突）
  final String name;

  /// 对端该题库的 uid
  final String peerBankUid;

  /// 对端题库行原始数据（覆盖时整行替换用）
  final Map<String, dynamic> peerBank;

  /// 对端题目原始数据
  final List<Map<String, dynamic>> peerQuestions;

  /// 对端题目配图（随题目一起搬）
  final List<Map<String, dynamic>> peerImages;

  /// 本机同名题库的本地 id
  final int localBankId;

  /// 本机题目数 / 对端题目数
  final int localCount;
  final int peerCount;

  /// 选「增添」时能补进来的题数（对端有、本机没有的）
  final int additionCount;

  /// 对端设备名（提示里给用户看「这是谁的题库」）
  final String peerDeviceName;

  /// 给用户看的一句话摘要
  String get summary =>
      '本机 $localCount 题 / 对端 $peerCount 题，其中对端多出 $additionCount 题';
}

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
