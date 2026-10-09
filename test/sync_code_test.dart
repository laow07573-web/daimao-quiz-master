import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:flashcard_app/services/sync/sync_code.dart';

/// 2026-10-08 用户定稿：识别码分两种形式。
/// - 6 位数字 = 临时分享用（当面给对方，一次性，有有效期）
/// - 长字符串 = 由设备码派生，可复制/生成二维码，长期配对用
///
/// 这些测试锁住「哪些码能通过、哪些必须被拒」——它是「不把数据同步到
/// 不想同步的设备」这条需求的唯一门禁，必须有回归保护。
void main() {
  group('设备码派生', () {
    test('同一设备 id 永远派生同一个码（跨会话稳定）', () {
      const id = 'device-abc-123';
      expect(SyncCode.deviceCodeOf(id), SyncCode.deviceCodeOf(id));
    });

    test('不同设备 id 派生不同的码', () {
      expect(SyncCode.deviceCodeOf('dev-a'),
          isNot(SyncCode.deviceCodeOf('dev-b')));
    });

    test('派生结果长度固定且只含字母表字符（无易混的 I/L/O/U）', () {
      final code = SyncCode.deviceCodeOf('device-xyz');
      expect(code.length, SyncCode.codeLength);
      expect(code, matches(RegExp(r'^[0-9A-HJKMNP-TV-Z]+$')));
    });

    test('首尾空白不影响派生（设备名/id 可能带空格）', () {
      expect(SyncCode.deviceCodeOf(' dev-a '), SyncCode.deviceCodeOf('dev-a'));
    });

    test('展示形式每 4 位一组', () {
      expect(
          SyncCode.formatDeviceCode('ABCDEFGHIJKLMNOP'), 'ABCD-EFGH-IJKL-MNOP');
    });
  });

  group('临时码生成', () {
    test('是 6 位数字且首位不为 0', () {
      for (var i = 0; i < 50; i++) {
        final code = SyncCode.generateTempCode(Random(i));
        expect(code.length, SyncCode.tempCodeLength);
        expect(code, matches(RegExp(r'^[1-9][0-9]{5}$')));
      }
    });

    test('有效期默认 10 分钟', () {
      expect(SyncCode.tempCodeTtl, const Duration(minutes: 10));
    });
  });

  group('校验 accepts', () {
    const deviceId = 'unit-test-device';
    final deviceCode = SyncCode.deviceCodeOf(deviceId);
    final later = DateTime(2026, 10, 8, 12, 0);

    test('设备码通过——带分组连字符也通过（用户抄写时会带连字符）', () {
      expect(
          SyncCode.accepts(
              presented: deviceCode, deviceCode: deviceCode, now: later),
          isTrue);
      expect(
          SyncCode.accepts(
              presented: SyncCode.formatDeviceCode(deviceCode),
              deviceCode: deviceCode,
              now: later),
          isTrue);
    });

    test('大小写与易混字符宽容（小写、把 0 抄成 O 都能通过）', () {
      expect(
          SyncCode.accepts(
              presented: deviceCode.toLowerCase(),
              deviceCode: deviceCode,
              now: later),
          isTrue);
      final withO = deviceCode.replaceAll('0', 'O');
      expect(
          SyncCode.accepts(
              presented: withO, deviceCode: deviceCode, now: later),
          isTrue);
    });

    test('临时码在有效期内通过', () {
      expect(
          SyncCode.accepts(
              presented: '123456',
              deviceCode: deviceCode,
              tempCode: '123456',
              tempExpiry: later.add(const Duration(minutes: 5)),
              now: later),
          isTrue);
    });

    test('临时码过期后被拒（一次性场景不能长留后门）', () {
      expect(
          SyncCode.accepts(
              presented: '123456',
              deviceCode: deviceCode,
              tempCode: '123456',
              tempExpiry: later.subtract(const Duration(seconds: 1)),
              now: later),
          isFalse);
    });

    test('别的设备的码被拒', () {
      expect(
          SyncCode.accepts(
              presented: SyncCode.deviceCodeOf('someone-else'),
              deviceCode: deviceCode,
              tempCode: '123456',
              tempExpiry: later.add(const Duration(minutes: 5)),
              now: later),
          isFalse);
    });

    test('空码被拒（没带识别码的陌生请求一律拒绝）', () {
      expect(
          SyncCode.accepts(presented: '', deviceCode: deviceCode, now: later),
          isFalse);
      expect(
          SyncCode.accepts(
              presented: '   ', deviceCode: deviceCode, now: later),
          isFalse);
    });

    test('没有临时码时，6 位数字不会被误接受', () {
      expect(
          SyncCode.accepts(
              presented: '123456', deviceCode: deviceCode, now: later),
          isFalse);
    });
  });

  group('临时码存活判断（UI 用）', () {
    final now = DateTime(2026, 10, 8, 12, 0);
    test('未生成时为 false；未过期 true；过期 false', () {
      expect(SyncCode.tempCodeAlive(null, null, now: now), isFalse);
      expect(
          SyncCode.tempCodeAlive('123456', now.add(const Duration(minutes: 1)),
              now: now),
          isTrue);
      expect(
          SyncCode.tempCodeAlive(
              '123456', now.subtract(const Duration(minutes: 1)),
              now: now),
          isFalse);
    });
  });
}
