import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/services/sync/sync_discovery.dart';
import 'package:flashcard_app/services/sync/sync_models.dart';

/// 真实网卡级诊断：同一台主机起两个发现实例（各绑一个信标端口），
/// 验证广播信标能否被真实收发（走真实套接字与真实定时器，非假异步）。
/// 若此测试失败，说明平台层广播收发有问题（需换多播或加诊断日志）。
void main() {
  testWidgets('真实 UDP：两实例互相发现（广播收发端到端）', (tester) async {
    await tester.runAsync(() async {
      final a = SyncDiscovery();
      final b = SyncDiscovery();
      final seenByA = <String>{};
      final seenByB = <String>{};
      a.onPeerDiscovered = (p) => seenByA.add(p.deviceId);
      b.onPeerDiscovered = (p) => seenByB.add(p.deviceId);

      try {
        await a.start(
          deviceId: 'diag-a',
          beacon: () async => const SyncBeacon(
              deviceId: 'diag-a', deviceName: '诊断A', port: 51630),
          broadcast: true,
        );
        await b.start(
          deviceId: 'diag-b',
          beacon: () async => const SyncBeacon(
              deviceId: 'diag-b', deviceName: '诊断B', port: 51631),
          broadcast: true,
        );
      } catch (e) {
        fail('发现服务启动失败（端口绑定问题）: $e');
      }

      // 等 4 个信标周期（周期 3s），真实等待
      await Future<void>.delayed(const Duration(seconds: 13));

      await a.stop();
      await b.stop();

      expect(seenByA.contains('diag-b'), isTrue,
          reason: 'A 应通过广播发现 B（真实套接字收发）');
      expect(seenByB.contains('diag-a'), isTrue,
          reason: 'B 应通过广播发现 A（真实套接字收发）');
    });
  });
}
