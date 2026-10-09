import 'package:flutter_test/flutter_test.dart';

import 'package:flashcard_app/services/sync/sync_code.dart';
import 'package:flashcard_app/services/sync/sync_pair_payload.dart';

/// 2026-10-08 用户要求：「长的字符串……要支持复制或者直接生成一个二维码，
/// 另一台设备只要通过猫卷扫码就可以连上。」
///
/// 二维码载荷是配对入口，解析错了会连到错误设备或直接连不上，所以锁住：
/// 编码/解码往返一致、拒绝非本应用二维码、容忍裸码、版本不认识的拒绝。
void main() {
  const code = 'ABCDEFGH12345678';

  group('编码与往返', () {
    test('带设备名与地址的载荷可原样还原', () {
      const p = SyncPairPayload(
        code: code,
        deviceName: '小米15',
        ip: '192.168.1.7',
        port: 51630,
      );
      final decoded = SyncPairPayload.decode(p.encode());
      expect(decoded, isNotNull);
      expect(decoded!.code, code);
      expect(decoded.deviceName, '小米15');
      expect(decoded.ip, '192.168.1.7');
      expect(decoded.port, 51630);
      expect(decoded.hasAddress, isTrue);
    });

    test('设备名含空格/中文也能往返（走 URL 编码）', () {
      const p = SyncPairPayload(code: code, deviceName: '我的 平板 A');
      final decoded = SyncPairPayload.decode(p.encode())!;
      expect(decoded.deviceName, '我的 平板 A');
    });

    test('只有识别码时也能编码，且 hasAddress 为 false', () {
      const p = SyncPairPayload(code: code);
      final raw = p.encode();
      expect(raw, contains('code=$code'));
      final decoded = SyncPairPayload.decode(raw)!;
      expect(decoded.code, code);
      expect(decoded.hasAddress, isFalse);
    });

    test('端口缺失/非法时 hasAddress 为 false（不能让扫码方连到空地址）', () {
      const p = SyncPairPayload(code: code, ip: '192.168.1.7');
      expect(p.hasAddress, isFalse);
      expect(SyncPairPayload.decode(p.encode())!.hasAddress, isFalse);
    });
  });

  group('解码的拒绝与容忍', () {
    test('别的应用的二维码一律拒绝（避免乱连）', () {
      expect(SyncPairPayload.decode('https://example.com/x'), isNull);
      expect(SyncPairPayload.decode('weixin://abc'), isNull);
      expect(SyncPairPayload.decode(''), isNull);
      expect(SyncPairPayload.decode('   '), isNull);
    });

    test('缺 code 的载荷拒绝', () {
      expect(
          SyncPairPayload.decode('${SyncPairPayload.scheme}:1?name=x'), isNull);
      expect(
          SyncPairPayload.decode('${SyncPairPayload.scheme}:1?code='), isNull);
    });

    test('未来版本号拒绝（不猜未知格式）', () {
      expect(SyncPairPayload.decode('${SyncPairPayload.scheme}:2?code=$code'),
          isNull);
    });

    test('容忍裸识别码：6 位临时码与 16 位长码都能直接填', () {
      final temp = SyncPairPayload.decode('123456');
      expect(temp, isNotNull);
      expect(temp!.code, '123456');

      final long = SyncPairPayload.decode(code);
      expect(long, isNotNull);
      expect(long!.code, code);

      // 带连字符抄写形式也认
      final grouped = SyncPairPayload.decode(SyncCode.formatDeviceCode(code));
      expect(grouped, isNotNull);
      expect(grouped!.code, code);
    });

    test('既不是 6 位数字也不是 16 位长码的裸文本拒绝', () {
      expect(SyncPairPayload.decode('hello world'), isNull);
      expect(SyncPairPayload.decode('12345'), isNull);
    });
  });

  test('scheme 前缀与载荷格式稳定（改动会破坏已发出的二维码）', () {
    expect(SyncPairPayload.scheme, 'maojuan-sync');
    expect(SyncPairPayload.version, 1);
    const p = SyncPairPayload(code: code);
    expect(p.encode(), 'maojuan-sync:1?code=$code');
  });
}
