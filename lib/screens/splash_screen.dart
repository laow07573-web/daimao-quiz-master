import 'dart:async';

import 'package:flutter/material.dart';
import '../services/guide_service.dart';
import '../services/hitokoto_service.dart';
import '../services/theme_service.dart';
import '../utils/design_tokens.dart';
import '../widgets/kit/mj_logo.dart';
import 'main_shell.dart';

/// 启动闪屏页（v1.0.2 对齐原版设计：App Logo + 标题 + 今日一言 + 加载圈）
///
/// 固定 1.4 秒自动进入下一步：首次启动进主界面并在其上插播互动式引导
/// （[MainShell.startTour]），其余直接进主界面。
/// 一言异步加载不阻塞（失败回退默认文案）。
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  /// 闪屏结束后的去向：首启进主界面并插播引导，其余直接进主界面。
  ///
  /// 抽成静态纯函数便于单测分支——校验「第二次启动不再插播引导」不需要真的
  /// 起数据库与 Provider 去构建 [MainShell]。
  @visibleForTesting
  static Widget nextScreen({required bool firstRun}) =>
      MainShell(startTour: firstRun);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _timer;
  // v1.27 PC 加载修复：首帧直接显示缓存/本地一言，网络结果到达后静默替换，
  // 不再显示「正在加载一言...」占位。
  String _hitokoto = HitokotoService.immediateText();

  /// 首启判定结果：true = 首启需插播引导；null = 存储还没读回来
  bool? _firstRun;

  @override
  void initState() {
    super.initState();
    _loadHitokoto();
    _checkFirstRun();
    // v1.0.2 UI 审查修复：固定 2 秒 → 1.4 秒（启动更快，避免等待感）
    _timer = Timer(const Duration(milliseconds: 1400), _enterApp);
  }

  /// 首启引导判定：与一言并行读取，不阻塞进入应用
  Future<void> _checkFirstRun() async {
    final seen = await GuideService.instance.hasSeen();
    if (!mounted) return;
    _firstRun = !seen;
  }

  Future<void> _loadHitokoto() async {
    final text = await HitokotoService.fetch();
    if (!mounted) return;
    // v1.27：成功才替换；失败保持首帧的缓存/本地一言。
    if (text != null) {
      setState(() => _hitokoto = text);
    }
  }

  Future<void> _enterApp() async {
    if (!mounted) return;
    // 存储极慢时（判定还没回来）现读一次：宁可多等一瞬，也不漏播首启引导
    final firstRun = _firstRun ?? !(await GuideService.instance.hasSeen());
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
          builder: (_) => SplashScreen.nextScreen(firstRun: firstRun)),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Mao Des 2.0 精密暗色：闪屏不再用大面积渐变，
    // 改为画布底 + 白底 logo 方块 + 大字号标题 + 发丝分隔 + 细指示。
    final ac = AppThemeColors.of(context);
    return Scaffold(
      backgroundColor: ac.background,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 品牌位：标记直接绘制（无底色方块、无描边），尺寸即标记大小
              const MJLogoBadge(box: 104),
              const SizedBox(height: MaoSpace.lg),
              // 软件名字
              Text('猫卷',
                  style: MaoType.h1Style
                      .copyWith(fontSize: 28, color: ac.textPrimary)),
              const SizedBox(height: MaoSpace.sm),
              // 发丝分隔
              Container(
                width: 56,
                height: MaoLine.width,
                color: ac.border,
              ),
              const SizedBox(height: MaoSpace.sm),
              // 今日一言
              Text('今日一言',
                  style: MaoType.microStyle
                      .copyWith(color: ac.textTertiary, letterSpacing: 1.2)),
              const SizedBox(height: MaoSpace.xs),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: Text(
                  _hitokoto,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: MaoType.bodyStyle
                      .copyWith(color: ac.textSecondary, height: 1.5),
                ),
              ),
              const SizedBox(height: MaoSpace.xxl),
              SizedBox(
                width: 18,
                height: 18,
                child:
                    CircularProgressIndicator(strokeWidth: 2, color: ac.accent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
