import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../debug_log_service.dart';
import '../device_service.dart';
import 'sync_discovery.dart';
import 'sync_models.dart';
import 'sync_repository.dart';
import 'sync_server.dart';

/// 局域网同步引擎：编排发现、传输与合并。
///
/// - 自动同步：开启后广播信标；发现新对端（收到其信标）自动触发同步
/// - 手动同步：设置页「立即同步」对已发现设备逐一同步
/// - 合并入口统一走 [SyncRepository]（按 uid upsert、批注按设备隔离）
/// - 同步完成后回调 [onSyncApplied]（刷新 AppState 题库/统计）
class SyncEngine extends ChangeNotifier {
  SyncEngine._();
  static final SyncEngine instance = SyncEngine._();

  final SyncDiscovery _discovery = SyncDiscovery();
  final SyncServer _server = SyncServer();
  final SyncRepository _repository = SyncRepository();
  final http.Client _httpClient = http.Client();

  /// 自动同步的每设备冷却（避免两端互相发现时反复全量同步）
  static const Duration autoSyncCooldown = Duration(seconds: 120);
  static const Duration exchangeTimeout = Duration(seconds: 30);

  /// Android 组播/广播锁通道（Wi-Fi 默认丢广播包，持锁才能收到对端信标）
  static const MethodChannel _androidSyncChannel =
      MethodChannel('com.flashcard.app/sync');

  bool _started = false;
  bool _autoSync = false;
  bool _syncing = false;
  DateTime? _lastSyncAt;
  String _statusMessage = '';
  final Map<String, DateTime> _lastAutoSyncAt = {};

  /// 数据合并落库后回调（主入口用于刷新 AppState）
  void Function()? onSyncApplied;

  bool get started => _started;
  bool get autoSync => _autoSync;
  bool get syncing => _syncing;
  DateTime? get lastSyncAt => _lastSyncAt;
  String get statusMessage => _statusMessage;
  List<DiscoveredPeer> get peers => _discovery.peers;

  /// 启动：同步服务端常开（接收他端推送不依赖本机开关），
  /// 信标广播常开（否则双方都关自动同步时互相不可见，手动同步也没法用），
  /// [autoSync] 只控制「发现后是否自动触发同步」
  Future<void> start({required bool autoSync}) async {
    _autoSync = autoSync;
    if (_started) return;
    final deviceId = await DeviceService.instance.deviceId;

    await _server.start(
      onReceived: (snapshot) async {
        final merged = await _repository.importSnapshot(snapshot);
        if (merged > 0) {
          _lastSyncAt = DateTime.now();
          _statusMessage = '已接收并合并对端数据（$merged 项）';
          notifyListeners();
          onSyncApplied?.call();
        }
      },
      snapshot: () => _repository.exportSnapshot(),
    );

    _discovery.onPeerDiscovered = (peer) {
      DebugLogService.instance.log(
          'SYNC', '发现设备：${peer.deviceName}（${peer.ip}:${peer.port}）');
      notifyListeners();
      if (_autoSync) unawaited(_autoSyncWith(peer));
    };
    _discovery.onPeersChanged = () => notifyListeners();

    await _discovery.start(
      deviceId: deviceId,
      beacon: () async => SyncBeacon(
        deviceId: deviceId,
        deviceName: await DeviceService.instance.deviceName,
        port: _server.port,
      ),
      broadcast: true, // 信标常广播（可被发现）；自动同步由 _autoSync 另行控制
    );

    // Android：获取组播/广播锁，否则 Wi-Fi 驱动会丢弃对端广播信标，
    // 表现为「接入局域网但发现不了设备」。失败降级（不阻塞启动）。
    if (Platform.isAndroid) {
      try {
        await _androidSyncChannel
            .invokeMethod('acquireMulticastLock')
            .timeout(const Duration(seconds: 3));
      } catch (e) {
        DebugLogService.instance.log('SYNC', '组播锁获取失败（发现可能受限）: $e');
      }
    }

    _started = true;
    DebugLogService.instance.log('SYNC',
        '同步服务已启动：HTTP 端口 ${_server.port}，自动同步=${autoSync ? "开" : "关"}');
    notifyListeners();
  }

  /// 自动同步开关切换（设置页）：只改「发现后是否自动同步」，
  /// 信标广播始终开启（关闭时仍可被发现与手动同步）
  Future<void> applyAutoSync(bool enabled) async {
    if (_autoSync == enabled) return;
    _autoSync = enabled;
    if (_started && enabled) {
      // 开启后立即与已发现的设备同步一次（不等下个信标周期）
      for (final peer in _discovery.peers) {
        unawaited(_autoSyncWith(peer));
      }
    }
    notifyListeners();
  }

  Future<void> _autoSyncWith(DiscoveredPeer peer) async {
    if (_syncing) return;
    final last = _lastAutoSyncAt[peer.deviceId];
    if (last != null &&
        DateTime.now().difference(last) < autoSyncCooldown) {
      return; // 冷却期内，等下次发现事件
    }
    _lastAutoSyncAt[peer.deviceId] = DateTime.now();
    await syncWith(peer, source: '自动');
  }

  /// 手动「立即同步」：对已发现设备逐一同步。
  /// 返回 (尝试数, 成功数)
  Future<(int, int)> manualSync() async {
    final targets = _discovery.peers;
    if (targets.isEmpty) return (0, 0);
    var ok = 0;
    for (final peer in targets) {
      final success = await syncWith(peer, source: '手动');
      if (success) ok++;
    }
    return (targets.length, ok);
  }

  /// 与单个对端同步：推送本机快照 → 对端合并并回传其快照 → 本机合并。
  /// 返回是否成功
  Future<bool> syncWith(DiscoveredPeer peer, {String source = '手动'}) async {
    if (_syncing) return false;
    _syncing = true;
    _statusMessage = '正在与 ${peer.deviceName} 同步...';
    notifyListeners();
    try {
      final mySnapshot = await _repository.exportSnapshot();
      final uri =
          Uri.parse('http://${peer.ip}:${peer.port}/sync/exchange');
      final response = await _httpClient
          .post(uri,
              headers: {'Content-Type': 'application/json; charset=utf-8'},
              body: utf8.encode(jsonEncode(mySnapshot)))
          .timeout(exchangeTimeout);
      if (response.statusCode != 200) {
        throw Exception('对端返回 ${response.statusCode}');
      }
      final dynamic parsed = jsonDecode(utf8.decode(response.bodyBytes));
      if (parsed is Map<String, dynamic>) {
        final merged = await _repository.importSnapshot(parsed);
        if (merged > 0) onSyncApplied?.call();
      }
      _lastSyncAt = DateTime.now();
      _statusMessage = '$source同步完成：${peer.deviceName}';
      DebugLogService.instance.log('SYNC', '与 ${peer.deviceName} 同步成功');
      return true;
    } catch (e) {
      _statusMessage = '同步失败：${peer.deviceName}（${_brief(e)}）';
      DebugLogService.instance
          .log('SYNC', '与 ${peer.deviceName} 同步失败: $e');
      return false;
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  String _brief(Object e) {
    final s = '$e';
    final first = s.split('\n').first;
    return first.length > 60 ? '${first.substring(0, 60)}...' : first;
  }

  Future<void> stop() async {
    if (Platform.isAndroid) {
      try {
        await _androidSyncChannel
            .invokeMethod('releaseMulticastLock')
            .timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
    await _discovery.stop();
    await _server.stop();
    _httpClient.close();
    _started = false;
  }
}
