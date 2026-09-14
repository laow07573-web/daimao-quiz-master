import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/utils/app_constants.dart';

/// 版本号单一来源闸门。
///
/// **为什么需要这个测试**：v1.28.0 曾发生「APK 的 versionName 误标为 1.27.0」
/// 的事故——根因是版本号散落在多处（pubspec、kAppVersion、README、推广页、
/// installer 脚本），改一处漏一处。现在约定 `pubspec.yaml` 是唯一来源，
/// 构建时由 `--dart-define=APP_VERSION=...` 注入到 [kAppVersion]；
/// 而 kAppVersion 的 defaultValue（本地 debug 用）必须与 pubspec 一致。
///
/// 这个测试就是把「必须一致」变成机器可查的事实：改了 pubspec 忘记同步
/// 默认值，这里立刻红，而不是等到发版后用户发现版本号不对。
void main() {
  group('版本号单一来源（pubspec ↔ kAppVersion）', () {
    late String pubspecVersion;

    setUpAll(() {
      final f = File('pubspec.yaml');
      expect(f.existsSync(), isTrue,
          reason: '测试需在包根目录运行（找不到 pubspec.yaml）');
      final line = f
          .readAsLinesSync()
          .firstWhere((l) => l.startsWith('version:'),
              orElse: () => '');
      expect(line, isNotEmpty, reason: 'pubspec.yaml 缺少 version: 字段');
      pubspecVersion = line.split(':').last.trim();
    });

    test('pubspec 版本格式合法（<版本名>+<构建号>）', () {
      expect(pubspecVersion, matches(RegExp(r'^\d+\.\d+\.\d+\+\d+$')),
          reason: '当前值「$pubspecVersion」不符合 versionName+versionCode 格式，'
              '例如 1.28.1+20');
    });

    test('kAppVersion 默认值与 pubspec 一致', () {
      // pubspec: 1.28.1+20  →  kAppVersion: v1.28.1.20
      final parts = pubspecVersion.split('+');
      final expected = 'v${parts[0]}.${parts[1]}';

      expect(kAppVersion, expected,
          reason: 'kAppVersion（$kAppVersion）与 pubspec.yaml（$pubspecVersion）不一致。\n'
              '修法：把 pubspec.yaml 的 version 改成新版本后，同步更新 '
              'lib/utils/app_constants.dart 里 kAppVersion 的 defaultValue。\n'
              '（发布/CI 构建会通过 --dart-define=APP_VERSION 覆盖它，'
              '这里校验的是本地 debug 的默认值。）');
    });

    test('kAppVersion 带 v 前缀，与关于页/页脚展示格式一致', () {
      expect(kAppVersion.startsWith('v'), isTrue,
          reason: '关于页与页脚直接拼接 kAppVersion 展示，需自带 v 前缀');
    });
  });
}
