import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../debug_log_service.dart';
import '../device_service.dart';
import 'sync_discovery.dart';
import 'sync_code.dart';
import 'sync_models.dart';
import 'sync_pair_payload.dart';
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

  /// 本机设备码（长码，由 deviceId 派生；同一台设备恒定）
  String _deviceCode = '';

  /// 对端识别码（用户输入或扫码得到）。**为空时不发起任何同步**——
  /// 用户要求「接入端需要输入识别码才可以与目标设备进行自动同步」。
  String _peerCode = '';

  /// 本机临时码（6 位数字，一次性分享用）
  String _tempCode = '';
  DateTime? _tempExpiry;

  /// 同步范围：false=整库；true=只同步题库（用户之间分享题库）
  bool _banksOnly = false;

  /// 数据合并落库后回调（主入口用于刷新 AppState）
  void Function()? onSyncApplied;

  bool get started => _started;
  bool get autoSync => _autoSync;
  bool get syncing => _syncing;
  DateTime? get lastSyncAt => _lastSyncAt;
  String get statusMessage => _statusMessage;
  List<DiscoveredPeer> get peers => _discovery.peers;

  /// 本机设备码（展示给对端：可复制、可生成二维码）
  String get deviceCode => _deviceCode;

  /// 对端识别码（空 = 尚未配对，不会自动同步）
  String get peerCode => _peerCode;
  bool get paired => _peerCode.trim().isNotEmpty;

  /// 本机当前临时码与是否仍有效
  String get tempCode => _tempCode;
  DateTime? get tempExpiry => _tempExpiry;
  bool get tempCodeAlive => SyncCode.tempCodeAlive(_tempCode, _tempExpiry);

  /// 同步范围：true=仅题库
  bool get banksOnly => _banksOnly;

  /// 启动：同步服务端常开（接收他端推送不依赖本机开关），
  /// 信标广播常开（否则双方都关自动同步时互相不可见，手动同步也没法用），
  /// [autoSync] 只控制「发现后是否自动触发同步」
  Future<void> start({required bool autoSync}) async {
    _autoSync = autoSync;
    if (_started) return;
    final deviceId = await DeviceService.instance.deviceId;
    _deviceCode = SyncCode.deviceCodeOf(deviceId);

    await _server.start(
      onReceived: (snapshot) async {
        final found = <SyncBankConflict>[];
        final merged =
            await _repository.importSnapshot(snapshot, conflictSink: found);
        _collectConflicts(found);
        if (merged > 0) {
          _lastSyncAt = DateTime.now();
          _statusMessage = '已接收并合并对端数据（$merged 项）';
          notifyListeners();
          onSyncApplied?.call();
        }
      },
      snapshot: ({required bool banksOnly}) =>
          _repository.exportSnapshot(banksOnly: banksOnly),
    );

    // 识别码门禁：设备长码 或 未过期的临时码，任一命中才放行
    _server.verifyCode = (presented) => SyncCode.accepts(
          presented: presented,
          deviceCode: _deviceCode,
          tempCode: tempCodeAlive ? _tempCode : null,
          tempExpiry: _tempExpiry,
        );

    _discovery.onPeerDiscovered = (peer) {
      DebugLogService.instance
          .log('SYNC', '发现设备：${peer.deviceName}（${peer.ip}:${peer.port}）');
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
    DebugLogService.instance.log(
        'SYNC', '同步服务已启动：HTTP 端口 ${_server.port}，自动同步=${autoSync ? "开" : "关"}');
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

  /// 保存对端识别码（用户手动输入或扫码得到）。空串 = 解除配对。
  ///
  /// 归一化后存储：去掉连字符/空格、统一大写，并宽容 O→0、I/L→1 的抄写误差。
  /// 6 位数字（临时码）保持数字形式原样。
  void applyPeerCode(String raw) {
    final normalized = SyncCode.normalize(raw);
    if (_peerCode == normalized) return;
    _peerCode = normalized;
    _statusMessage = normalized.isEmpty
        ? '已解除配对，将不再自动同步'
        : '已保存对端识别码（${normalized.length} 位）';
    DebugLogService.instance
        .log('SYNC', normalized.isEmpty ? '解除配对' : '已保存对端识别码');
    notifyListeners();
  }

  /// 生成 6 位临时码（当面分享题库这种一次性场景），默认 10 分钟有效。
  void generateTempCode() {
    _tempCode = SyncCode.generateTempCode();
    _tempExpiry = DateTime.now().add(SyncCode.tempCodeTtl);
    notifyListeners();
  }

  /// 立即作废本机临时码（分享完毕即可关闭）
  void clearTempCode() {
    if (_tempCode.isEmpty && _tempExpiry == null) return;
    _tempCode = '';
    _tempExpiry = null;
    notifyListeners();
  }

  /// 切换同步范围：true = 只同步题库（用户之间分享题库），false = 整库。
  void applyBanksOnly(bool banksOnly) {
    if (_banksOnly == banksOnly) return;
    _banksOnly = banksOnly;
    notifyListeners();
  }

  // ── 同名题库冲突（2026-10-09 用户要求「若不一样则提示是否覆盖或者增添」）──

  final List<SyncBankConflict> _pendingConflicts = [];

  /// 待用户决策的同名题库冲突。挂在内存里即可：冲突本身带着对端数据，
  /// 而且下次同步会再次发现（对端快照每次都带它的题库）。
  List<SyncBankConflict> get pendingConflicts =>
      List.unmodifiable(_pendingConflicts);

  bool get hasPendingConflicts => _pendingConflicts.isNotEmpty;

  void _collectConflicts(List<SyncBankConflict> found) {
    if (found.isEmpty) return;
    for (final c in found) {
      final dup = _pendingConflicts
          .any((e) => e.name == c.name && e.peerBankUid == c.peerBankUid);
      if (!dup) _pendingConflicts.add(c);
    }
    _statusMessage = '有 ${_pendingConflicts.length} 个同名题库待处理';
    notifyListeners();
  }

  /// 用户在首页决定：覆盖（用对端整套替换）或 增添（只并对方多出来的题）。
  /// 返回受影响的题目数。
  Future<int> resolveConflict(SyncBankConflict conflict,
      {required bool overwrite}) async {
    final affected =
        await _repository.resolveBankConflict(conflict, overwrite: overwrite);
    _pendingConflicts.removeWhere((e) =>
        e.name == conflict.name && e.peerBankUid == conflict.peerBankUid);
    _statusMessage = overwrite
        ? '已覆盖「${conflict.name}」（$affected 题）'
        : '已增添「${conflict.name}」（$affected 题）';
    notifyListeners();
    onSyncApplied?.call();
    return affected;
  }

  /// 暂不处理：从待办里移除，本机数据保持不动。
  void dismissConflict(SyncBankConflict conflict) {
    _pendingConflicts.removeWhere((e) =>
        e.name == conflict.name && e.peerBankUid == conflict.peerBankUid);
    notifyListeners();
  }

  /// 本机在局域网里的 IPv4 地址（生成配对二维码时带上，对方扫完可立即同步）
  Future<String?> localIpv4() async {
    try {
      final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4, includeLoopback: false);
      for (final ni in interfaces) {
        for (final addr in ni.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (e) {
      DebugLogService.instance.log('SYNC', '取本机 IP 失败: $e');
    }
    return null;
  }

  /// 生成配对载荷：识别码 + 设备名 + 当前地址。
  /// 地址只是加速项（DHCP 会变），UDP 发现仍是主力。
  Future<SyncPairPayload> buildPairPayload() async {
    final ip = await localIpv4();
    return SyncPairPayload(
      code: _deviceCode,
      deviceName: await DeviceService.instance.deviceName,
      ip: ip,
      port: _server.port > 0 ? _server.port : null,
    );
  }

  /// 扫码配对：保存识别码；若二维码带地址则**立即发起一次同步**，
  /// 这样用户扫完就能看到数据过来（用户要的「扫码就可以连上」）。
  Future<bool> pairFromScan(SyncPairPayload payload) async {
    applyPeerCode(payload.code);
    if (!payload.hasAddress) {
      // 没带地址：等 UDP 发现后自动同步（已配对即会触发）
      _statusMessage = '已配对，等对端被发现后自动同步';
      notifyListeners();
      return true;
    }
    final peer = DiscoveredPeer(
      deviceId: 'scan:${payload.ip}:${payload.port}',
      deviceName: payload.deviceName.isEmpty ? payload.ip! : payload.deviceName,
      ip: payload.ip!,
      port: payload.port!,
      lastSeen: DateTime.now(),
    );
    return syncWith(peer, source: '扫码');
  }

  Future<void> _autoSyncWith(DiscoveredPeer peer) async {
    if (_syncing) return;
    // 未配对（没输入对端识别码）时绝不自动同步
    if (!paired) return;
    final last = _lastAutoSyncAt[peer.deviceId];
    if (last != null && DateTime.now().difference(last) < autoSyncCooldown) {
      return; // 冷却期内，等下次发现事件
    }
    _lastAutoSyncAt[peer.deviceId] = DateTime.now();
    await syncWith(peer, source: '自动');
  }

  /// 手动「立即同步」：对已发现设备逐一同步。
  /// 返回 (尝试数, 成功数)
  Future<(int, int)> manualSync() async {
    // 未配对时明确提示，而不是静默什么都不做
    if (!paired) {
      _statusMessage = '请先输入对端识别码再同步';
      notifyListeners();
      return (0, 0);
    }
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
    // 识别码是硬门禁：没配对就不发请求（用户要求「接入端需要输入识别码
    // 才可以与目标设备进行自动同步」）
    if (!paired) {
      _statusMessage = '请先输入对端识别码再同步';
      notifyListeners();
      return false;
    }
    _syncing = true;
    _statusMessage = '正在与 ${peer.deviceName} 同步...';
    notifyListeners();
    try {
      final mySnapshot =
          await _repository.exportSnapshot(banksOnly: _banksOnly);
      final payload = utf8.encode(jsonEncode(mySnapshot));
      // 图片随同步走，但 64MB 单次上限是硬约束：超限给出清晰错误，
      // 不把大半请求发过去让对端拒收
      if (payload.length > SyncServer.maxBodyBytes) {
        throw Exception(
            '同步数据 ${(payload.length / 1048576).toStringAsFixed(1)}MB 超过 64MB 上限'
            '（题库配图较多），请减少同步范围');
      }
      final uri = Uri.parse('http://${peer.ip}:${peer.port}/sync/exchange');
      final response = await _httpClient
          .post(uri,
              headers: {
                'Content-Type': 'application/json; charset=utf-8',
                SyncServer.codeHeader: _peerCode,
                SyncServer.scopeHeader: _banksOnly ? 'banks' : 'full',
              },
              body: payload)
          .timeout(exchangeTimeout);
      if (response.statusCode == 403) {
        throw Exception('识别码不匹配，对端拒绝了本次同步');
      }
      if (response.statusCode != 200) {
        throw Exception('对端返回 ${response.statusCode}');
      }
      final dynamic parsed = jsonDecode(utf8.decode(response.bodyBytes));
      if (parsed is Map<String, dynamic>) {
        final found = <SyncBankConflict>[];
        final merged =
            await _repository.importSnapshot(parsed, conflictSink: found);
        _collectConflicts(found);
        if (merged > 0) onSyncApplied?.call();
      }
      _lastSyncAt = DateTime.now();
      _statusMessage = '$source同步完成：${peer.deviceName}';
      DebugLogService.instance.log('SYNC', '与 ${peer.deviceName} 同步成功');
      return true;
    } catch (e) {
      _statusMessage = '同步失败：${peer.deviceName}（${_brief(e)}）';
      DebugLogService.instance.log('SYNC', '与 ${peer.deviceName} 同步失败: $e');
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
