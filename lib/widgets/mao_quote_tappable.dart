import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../utils/design_tokens.dart';
import 'mao_quote_bubble.dart';

/// 「老吴模式」：开启后点 Logo 不弹语录，而是播一段音频。
///
/// 2026-10-09 用户需求：「在设置里面加入一个老吴模式，开启之后按照上述的操作
/// 不会弹出语录，而是播放特定音频。」随后提供了两段音频（约 2.6s / 2.2s）。
///
/// 点了必有所得：资源缺失或播放失败时降级为浮空小窗提示一句，并把原因写进
/// 调试日志，不会静默到让人以为坏了。
class LaoWuMode {
  LaoWuMode._();

  /// 音频资源（放在 assets/ 下，pubspec 已整目录声明）。
  ///
  /// 2026-10-09 作者提供，两段短语音。默认**随机**播其中一段（与语录同样的
  /// "避开上一次"策略，连点两下不会重复听见同一段）。
  static const List<String> audioAssets = <String>[
    'laowu_01.mp3',
    'laowu_02.mp3',
  ];

  static AudioPlayer? _player;

  static AudioPlayer get _instance => _player ??= AudioPlayer();

  /// 上一次播的下标：避免连点两次听到同一段。
  static int _lastIndex = -1;

  static bool get hasAudio => audioAssets.isNotEmpty;

  /// 仅供测试：替换真正的播放动作。
  ///
  /// 真机上音频走平台通道，widget 测试里必然失败、只能测到降级分支；
  /// 有了这个钩子才能验证「播成功时**不弹气泡**」这条正向路径。
  /// 生产代码里始终为 null。
  @visibleForTesting
  static Future<bool> Function()? debugPlayOverride;

  /// 挑一段音频，两条以上时避开上一条。
  /// [random] 可注入以便测试；[reset] 供测试清空去重状态。
  static String pickAudio({Random? random, bool reset = false}) {
    if (reset) _lastIndex = -1;
    if (audioAssets.isEmpty) return '';
    if (audioAssets.length == 1) return audioAssets.first;
    final r = random ?? Random();
    var index = r.nextInt(audioAssets.length);
    if (index == _lastIndex) {
      // 撞上上一条时顺移一格：这是**近似**均匀（被顺移到的下一项概率略高，
      // 34 条语录时偏差约 1/34，可忽略），换来的是"连点必不重复"这个体验保证。
      index = (index + 1) % audioAssets.length;
    }
    _lastIndex = index;
    return audioAssets[index];
  }

  /// 播放老吴模式音频。返回是否真的播了（false = 资源缺失/播放失败）。
  static Future<bool> play() async {
    final override = debugPlayOverride;
    if (override != null) return override();
    if (!hasAudio) return false;
    final asset = pickAudio();
    try {
      await _instance.play(AssetSource(asset));
      return true;
    } catch (e) {
      debugPrint('[LAOWU] 音频播放失败（$asset）: $e');
      return false;
    }
  }
  // 说明：播放器是**进程内单例**，与 App 同生命周期（一段几秒的语音，常驻一个
  // 平台播放器不构成按次泄漏），因此这里没有 dispose —— 2026-10-09 代码审查指出
  // 原先那个无人调用的 dispose() 是死代码，已删掉，避免留下「释放意图没落地」
  // 的假象。若将来真的需要释放，记得把 _lastIndex 与 debugPlayOverride 一并重置。
}

/// 点 Logo 的统一入口：按「老吴模式」分流。
///
/// 抽出来是为了首页与我的页的 Logo 尺寸/位置各不相同、但行为完全一致。
///
/// 用 [GestureDetector] 而不是 InkWell：InkWell 需要 Material 祖先，而 Logo 会
/// 被放进各式容器（MJSurface 的 onTap 为空时并不包 Material）——真机上就出现过
/// 首页能点、我的页点不动的情况。`behavior: opaque` 同时保证整块区域（含 Logo
/// 四周内边距）都能命中，触达区不小于 44dp。
class MaoQuoteTappable extends StatelessWidget {
  const MaoQuoteTappable({super.key, required this.child, this.box = 42});

  final Widget child;
  final double box;

  Future<void> _onTap(BuildContext context) async {
    final appState = context.read<AppState>();
    if (appState.settings.laoWuMode) {
      final ok = await LaoWuMode.play();
      if (!context.mounted) return;
      if (!ok) {
        // 音频还没就位时给一次可见反馈，避免「点了没反应」
        MaoQuoteBubble.show(context, text: '老吴的音频还在路上');
      }
      return;
    }
    MaoQuoteBubble.show(context);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '猫卷语录',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _onTap(context),
        child: Padding(
          padding: const EdgeInsets.all(MaoSpace.xxs),
          child: SizedBox(width: box, height: box, child: child),
        ),
      ),
    );
  }
}
