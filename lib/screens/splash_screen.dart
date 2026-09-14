import 'dart:async';

import 'package:flutter/material.dart';
import '../services/hitokoto_service.dart';
import '../services/theme_service.dart';
import '../utils/design_tokens.dart';
import '../widgets/kit/mj_logo.dart';
import 'main_shell.dart';

/// 启动闪屏页（v1.0.2 对齐原版设计：App Logo + 标题 + 今日一言 + 加载圈）
///
/// 固定 2 秒自动进入主界面；一言异步加载不阻塞（失败回退默认文案）。
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _timer;
  // v1.27 PC 加载修复：首帧直接显示缓存/本地一言，网络结果到达后静默替换，
  // 不再显示「正在加载一言...」占位。
  String _hitokoto = HitokotoService.immediateText();

  @override
  void initState() {
    super.initState();
    _loadHitokoto();
    // v1.0.2 UI 审查修复：固定 2 秒 → 1.4 秒（启动更快，避免等待感）
    _timer = Timer(const Duration(milliseconds: 1400), _enterApp);
  }

  Future<void> _loadHitokoto() async {
    final text = await HitokotoService.fetch();
    if (!mounted) return;
    // v1.27：成功才替换；失败保持首帧的缓存/本地一言。
    if (text != null) {
      setState(() => _hitokoto = text);
    }
  }

  void _enterApp() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainShell()),
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
              // 品牌位：矢量标记 + 发丝描边方块（不再用白底位图，小尺寸不会糊）
              const MJLogoBadge(box: 88, padding: 14),
              const SizedBox(height: MaoSpace.lg),
              // 软件名字
              Text('猫卷',
                  style: MaoType.h1Style.copyWith(
                      fontSize: 28, color: ac.textPrimary)),
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
                  style: MaoType.microStyle.copyWith(
                      color: ac.textTertiary, letterSpacing: 1.2)),
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
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: ac.accent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
