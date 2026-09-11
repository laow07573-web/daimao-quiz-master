import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'sync_models.dart';

/// 局域网设备发现（纯 `dart:io` RawDatagramSocket）——三通道：
///
/// 1. 子网单播扫描（主力，最可靠）：周期扫描本机各网段的全部主机地址，
///    逐个单播信标。单播属于「出站流量」不受入站防火墙规则限制；对端收到后
///    单播应答自己的信标 → 双向发现互不依赖广播可达性。
/// 2. 多播（辅助）：加入固定多播组互发信标（dart:io 正式支持）。
/// 3. 广播（辅助）：受限广播 + 子网定向广播。
///    实测部分平台广播「发送不抛错但包不达」，故仅作为补充通道。
///
/// 维护「发现的设备」列表：按 device_id 去重、[peerTimeout] 未刷新剔除。
class SyncDiscovery {
  /// 信标端口（主 + 备；绑定用，收发都覆盖两个端口以兼容对端降级绑定）
  static const int primaryPort = 51620;
  static const int fallbackPort = 51621;

  /// 多播组与端口（固定；两端约定一致即可）
  static final InternetAddress multicastGroup = InternetAddress('239.192.93.93');
  static const int multicastPort = 51622;

  static const Duration beaconInterval = Duration(seconds: 3);
  static const Duration scanInterval = Duration(seconds: 6);
  static const Duration peerTimeout = Duration(seconds: 10);

  /// 收到信标后的应答节流：同一设备最近一次应答时间（防扫描风暴）
  final Map<String, DateTime> _lastReplyAt = {};
  static const Duration replyCooldown = Duration(seconds: 3);

  RawDatagramSocket? _socket;
  RawDatagramSocket? _mcastSocket;
  StreamSubscription<RawSocketEvent>? _subscription;
  StreamSubscription<RawSocketEvent>? _mcastSubscription;
  Timer? _broadcastTimer;
  Timer? _scanTimer;
  Timer? _pruneTimer;
  bool _broadcasting = false;
  bool _scanning = false;
  final List<int> _boundPorts = [];
  String _selfDeviceId = '';

  final Map<String, DiscoveredPeer> _peers = {};

  /// 构造本机信标（引擎注入：携带最新的同步服务端口与设备名）
  Future<SyncBeacon> Function()? buildBeacon;

  /// 新设备首次被发现（引擎据此触发自动同步）
  void Function(DiscoveredPeer peer)? onPeerDiscovered;

  /// 设备列表增删变化（设置页状态刷新；lastSeen 刷新不触发）
  VoidCallbackLike? onPeersChanged;

  bool get running => _socket != null;
  bool get broadcasting => _broadcasting;

  /// 当前发现的对端（已剔除超时）
  List<DiscoveredPeer> get peers {
    _prunePeers(DateTime.now());
    return _peers.values.toList()
      ..sort((a, b) => a.deviceName.compareTo(b.deviceName));
  }

  /// 启动发现：绑定监听 + 多播组；[broadcast] 为 true 时开始周期
  /// 广播与子网扫描。监听始终开启（手动「立即同步」也依赖被发现列表）
  Future<void> start({
    required String deviceId,
    required Future<SyncBeacon> Function() beacon,
    bool broadcast = false,
  }) async {
    if (running) return;
    _selfDeviceId = deviceId;
    buildBeacon = beacon;

    RawDatagramSocket? socket;
    // 绑定第一个可用端口监听；收发都同时覆盖主/备两个端口，
    // 兼容对端降级绑定到另一端口的情形
    for (final port in [primaryPort, fallbackPort]) {
      try {
        socket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          port,
          reuseAddress: true,
        );
        _boundPorts.add(port);
        break;
      } on SocketException {
        // 该端口不可用，继续尝试下一个
      }
    }
    if (socket == null) {
      throw const SocketException('局域网发现：无法绑定信标端口');
    }
    _socket = socket;
    _subscription = socket.listen(_onSocketEvent, onError: (_) {});

    // 多播通道（辅助）：绑定失败/加组失败降级跳过，不影响单播主力
    try {
      final ms = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4, multicastPort,
          reuseAddress: true);
      ms.joinMulticast(multicastGroup);
      _mcastSocket = ms;
      _mcastSubscription = ms.listen(_onSocketEventMcast, onError: (_) {});
    } catch (_) {
      _mcastSocket = null;
    }

    _pruneTimer = Timer.periodic(
        const Duration(seconds: 5), (_) => _pruneAndNotify());

    await setBroadcasting(broadcast);
  }

  Future<void> _onSocketEvent(RawSocketEvent event) async {
    final socket = _socket;
    if (socket == null || event != RawSocketEvent.read) return;
    Datagram? dg;
    do {
      dg = socket.receive();
      if (dg != null) {
        handleDatagram(dg.data, dg.address);
      }
    } while (dg != null);
  }

  Future<void> _onSocketEventMcast(RawSocketEvent event) async {
    final socket = _mcastSocket;
    if (socket == null || event != RawSocketEvent.read) return;
    Datagram? dg;
    do {
      dg = socket.receive();
      if (dg != null) {
        handleDatagram(dg.data, dg.address);
      }
    } while (dg != null);
  }

  /// 处理一个收到的 UDP 包（抽出供单测直接调用，不走真实网卡）。
  /// 信标统一 UTF-8 编码（设备名含中文）。
  /// 单播扫描的关键机制：收到他端信标后单播应答自己的信标，
  /// 使「我扫到对端」与「对端扫到我」双向成立，互不依赖广播可达性
  void handleDatagram(Uint8List data, InternetAddress address) {
    String raw;
    try {
      raw = utf8.decode(data);
    } catch (_) {
      return;
    }
    final beacon = SyncBeacon.decode(raw);
    if (beacon == null) return; // 他应用/非法包
    if (beacon.deviceId == _selfDeviceId) return; // 忽略自己的回环
    _mergeBeacon(beacon, address.address);
    // 应答机制：收到他端信标即单播回发自己的信标（节流），
    // 使单向扫描也能双向可见，不依赖双方都在扫描。
    unawaited(_replyBeaconTo(address));
  }

  /// 单播回发本机信标给信标来源（每地址节流，防扫描风暴）
  Future<void> _replyBeaconTo(InternetAddress target) async {
    final socket = _socket;
    final builder = buildBeacon;
    if (socket == null || builder == null || !_broadcasting) return;
    final now = DateTime.now();
    final last = _lastReplyAt[target.address];
    if (last != null && now.difference(last) < replyCooldown) return;
    _lastReplyAt[target.address] = now;
    try {
      final beacon = await builder();
      final data = Uint8List.fromList(utf8.encode(beacon.encode()));
      const ports = [primaryPort, fallbackPort];
      for (final port in ports) {
        try {
          socket.send(data, target, port);
        } catch (_) {}
      }
    } catch (_) {
      // 信标构造失败下个周期重试，不影响发现主链路（已合并对端）
    }
  }

  void _mergeBeacon(SyncBeacon beacon, String ip) {
    final existing = _peers[beacon.deviceId];
    final now = DateTime.now();
    if (existing == null) {
      final peer = DiscoveredPeer(
        deviceId: beacon.deviceId,
        deviceName: beacon.deviceName,
        ip: ip,
        port: beacon.port,
        lastSeen: now,
      );
      _peers[beacon.deviceId] = peer;
      onPeersChanged?.call();
      onPeerDiscovered?.call(peer);
      return;
    }
    final changed = existing.deviceName != beacon.deviceName ||
        existing.ip != ip ||
        existing.port != beacon.port;
    _peers[beacon.deviceId] = existing.copyWith(
      deviceName: beacon.deviceName,
      ip: ip,
      port: beacon.port,
      lastSeen: now,
    );
    if (changed) onPeersChanged?.call();
  }

  /// 单测注入：不绑端口直接验证信标合并/去重逻辑
  @visibleForTesting
  set selfDeviceIdForTest(String id) => _selfDeviceId = id;

  /// 启停主动发现（广播 + 多播 + 子网扫描）。监听不受影响
  Future<void> setBroadcasting(bool enabled) async {
    if (enabled == _broadcasting) return;
    _broadcasting = enabled;
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    _scanTimer?.cancel();
    _scanTimer = null;
    if (!enabled) return;
    await _sendBeacon();
    unawaited(_subnetScan());
    _broadcastTimer = Timer.periodic(beaconInterval, (_) => _sendBeacon());
    _scanTimer = Timer.periodic(scanInterval, (_) => unawaited(_subnetScan()));
  }

  /// 广播 + 多播发送（辅助通道；单播扫描见 [_subnetScan]）
  Future<void> _sendBeacon() async {
    final socket = _socket;
    final builder = buildBeacon;
    if (socket == null || builder == null) return;
    try {
      final beacon = await builder();
      final data = Uint8List.fromList(utf8.encode(beacon.encode()));
      // 受限广播 + 各接口子网定向广播，发向主/备两个端口
      final targets = <InternetAddress>[InternetAddress('255.255.255.255')];
      targets.addAll(await _subnetBroadcastAddresses());
      const ports = [primaryPort, fallbackPort];
      for (final addr in targets) {
        for (final port in ports) {
          try {
            socket.send(data, addr, port);
          } catch (_) {
            // 部分平台广播发送被静默拒绝，由单播扫描兜底
          }
        }
      }
      // 多播通道
      final ms = _mcastSocket;
      if (ms != null) {
        try {
          ms.send(data, multicastGroup, multicastPort);
        } catch (_) {}
      }
    } catch (_) {
      // 信标构造失败（如设备名读取异常）下个周期重试，不影响监听
    }
  }

  /// 子网单播扫描（发现主力）：枚举本机各 IPv4 接口的 /24 网段，
  /// 对每个主机地址单播信标。单播属出站流量，不受入站防火墙限制，
  /// 也不依赖网络对广播的转发；配合 [handleDatagram] 的应答机制双向可见
  Future<void> _subnetScan() async {
    final socket = _socket;
    final builder = buildBeacon;
    if (socket == null || builder == null || _scanning) return;
    _scanning = true;
    try {
      final peersAddrs = await _subnetPeerAddresses();
      if (peersAddrs.isEmpty) return;
      final beacon = await builder();
      final data = Uint8List.fromList(utf8.encode(beacon.encode()));
      const ports = [primaryPort, fallbackPort];
      var idx = 0;
      for (final addr in peersAddrs) {
        for (final port in ports) {
          try {
            socket.send(data, addr, port);
          } catch (_) {}
        }
        // 每 32 个地址让出事件循环，避免阻塞 UI/收发（O(1) 计数，非 indexOf）
        idx++;
        if (idx % 32 == 0) {
          await Future<void>.delayed(Duration.zero);
        }
      }
    } catch (_) {
      // 接口枚举/发送异常不阻塞发现（广播/多播通道仍在）
    } finally {
      _scanning = false;
    }
  }

  /// 本机各接口 /24 网段内的全部主机地址（排除网络号/广播号/本机）
  Future<List<InternetAddress>> _subnetPeerAddresses() async {
    final result = <InternetAddress>[];
    final selfIps = <String>{};
    try {
      final ifaces = await NetworkInterface.list(
          includeLoopback: false, type: InternetAddressType.IPv4);
      for (final iface in ifaces) {
        for (final addr in iface.addresses) {
          if (addr.type != InternetAddressType.IPv4) continue;
          final parts = addr.address.split('.');
          if (parts.length != 4) continue;
          selfIps.add(addr.address);
          final prefix = '${parts[0]}.${parts[1]}.${parts[2]}';
          for (var i = 1; i < 255; i++) {
            final ip = '$prefix.$i';
            if (selfIps.contains(ip)) continue;
            result.add(InternetAddress(ip));
          }
        }
      }
    } catch (_) {
      // 枚举失败：仅靠广播/多播通道
    }
    return result;
  }

  /// 各 IPv4 接口的子网定向广播地址（按常见的 /24 掩码推算）
  Future<List<InternetAddress>> _subnetBroadcastAddresses() async {
    final result = <InternetAddress>[];
    try {
      final ifaces = await NetworkInterface.list(
          includeLoopback: false, type: InternetAddressType.IPv4);
      for (final iface in ifaces) {
        for (final addr in iface.addresses) {
          if (addr.type != InternetAddressType.IPv4) continue;
          final parts = addr.address.split('.');
          if (parts.length != 4) continue;
          result.add(InternetAddress(
              '${parts[0]}.${parts[1]}.${parts[2]}.255'));
        }
      }
    } catch (_) {
      // 枚举失败：仅用受限广播
    }
    return result;
  }

  void _pruneAndNotify() {
    final before = _peers.length;
    _prunePeers(DateTime.now());
    if (_peers.length != before) onPeersChanged?.call();
  }

  void _prunePeers(DateTime now) {
    _peers.removeWhere(
        (_, p) => now.difference(p.lastSeen) > peerTimeout);
  }

  Future<void> stop() async {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    _scanTimer?.cancel();
    _scanTimer = null;
    _pruneTimer?.cancel();
    _pruneTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    await _mcastSubscription?.cancel();
    _mcastSubscription = null;
    _socket?.close();
    _socket = null;
    _mcastSocket?.close();
    _mcastSocket = null;
    _broadcasting = false;
    _boundPorts.clear();
    _peers.clear();
    _lastReplyAt.clear();
  }
}

/// 避免引 flutter/foundation 的轻量回调别名（本层为纯 dart:io 服务）
typedef VoidCallbackLike = void Function();
