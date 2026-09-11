import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../device_service.dart';

/// 局域网同步服务端：本端起 `dart:io` HttpServer，暴露同步接口。
///
/// 接口（仅局域网内明文，无云端）：
/// - `GET  /sync/info`     → 本机设备信息（连通性探测）
/// - `POST /sync/exchange` → 接收对端快照并合并入库，响应体返回本机快照，
///   对端收到后同样合并——一次请求完成双向同步
class SyncServer {
  /// 同步服务端口（被占用时依次尝试备用端口）
  static const List<int> candidatePorts = [51630, 51631, 51632];
  static const int maxBodyBytes = 64 * 1024 * 1024; // 64MB 上限（局域网全量快照）

  HttpServer? _server;

  /// 对端推送的快照合并回调（引擎注入：SyncRepository.importSnapshot）
  Future<void> Function(Map<String, dynamic> snapshot)? onSnapshotReceived;

  /// 响应给对端的本机快照回调（引擎注入：SyncRepository.exportSnapshot）
  Future<Map<String, dynamic>> Function()? buildSnapshot;

  bool get running => _server != null;
  int get port => _server?.port ?? 0;

  Future<void> start({
    required Future<void> Function(Map<String, dynamic>) onReceived,
    required Future<Map<String, dynamic>> Function() snapshot,
  }) async {
    if (running) return;
    onSnapshotReceived = onReceived;
    buildSnapshot = snapshot;

    HttpServer? server;
    for (final p in candidatePorts) {
      try {
        server = await HttpServer.bind(InternetAddress.anyIPv4, p);
        break;
      } on SocketException {
        server = null;
      }
    }
    // 固定端口全被占用时退化为系统分配（信标携带实际端口，不影响发现）
    server ??= await HttpServer.bind(InternetAddress.anyIPv4, 0);
    _server = server;
    server.listen(_handle, onError: (_) {});
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      final path = request.uri.path;
      if (path == '/sync/info' && request.method == 'GET') {
        await _respondJson(request, 200, {
          'device_id': await DeviceService.instance.deviceId,
          'device_name': await DeviceService.instance.deviceName,
        });
        return;
      }
      if (path == '/sync/exchange' && request.method == 'POST') {
        await _handleExchange(request);
        return;
      }
      await _respondJson(request, 404, {'error': 'not found'});
    } catch (e) {
      try {
        await _respondJson(request, 500, {'error': '$e'});
      } catch (_) {}
    }
  }

  Future<void> _handleExchange(HttpRequest request) async {
    final bytes = await _readBodyLimited(request);
    if (bytes == null) {
      await _respondJson(request, 413, {'error': 'body too large'});
      return;
    }
    Map<String, dynamic> peerSnapshot;
    try {
      final dynamic parsed = jsonDecode(utf8.decode(bytes));
      if (parsed is! Map<String, dynamic>) {
        await _respondJson(request, 400, {'error': 'bad snapshot'});
        return;
      }
      peerSnapshot = parsed;
    } catch (_) {
      await _respondJson(request, 400, {'error': 'bad snapshot'});
      return;
    }

    // 先合并对端数据，再返回本机快照——对端拿到的快照已含本机最新状态
    final receiver = onSnapshotReceived;
    if (receiver != null) {
      await receiver(peerSnapshot);
    }
    final snapshot = buildSnapshot != null
        ? await buildSnapshot!()
        : <String, dynamic>{};
    await _respondJson(request, 200, snapshot);
  }

  Future<List<int>?> _readBodyLimited(HttpRequest request) async {
    final sink = BytesBuilder(copy: false);
    await for (final chunk in request) {
      sink.add(chunk);
      if (sink.length > maxBodyBytes) return null;
    }
    return sink.takeBytes();
  }

  Future<void> _respondJson(
      HttpRequest request, int status, Map<String, dynamic> body) async {
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
    await request.response.close();
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }
}
