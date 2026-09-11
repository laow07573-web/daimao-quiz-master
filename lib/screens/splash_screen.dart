import 'dart:async';

import 'package:flutter/material.dart';
import '../services/hitokoto_service.dart';
import '../services/theme_service.dart';
import '../utils/design_tokens.dart';
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
    // Mao Des：闪屏用强调色双色位移渐变（品牌感），配白色文字。
    // 旧版用「导航色向黑插值」在浅色导航下会变成脏灰（#A5A5A5），已废弃。
    final ac = AppThemeColors.of(context);
    final bgGradient = LinearGradient(
      colors: [ac.accent, Color.lerp(ac.accent, ac.textPrimary, 0.32)!],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: bgGradient),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // App Logo（大圆角卡片）
              ClipRRect(
                borderRadius: BorderRadius.circular(MaoRadius.large),
                child: Image.asset(
                  'assets/app_logo.png',
                  width: 96,
                  height: 96,
                  errorBuilder: (_, __, ___) =>
                      Icon(Icons.school, size: 84, color: ac.onAccent),
                ),
              ),
              const SizedBox(height: MaoSpace.lg),
              // 软件名字
              Text(
                '猫卷',
                style: MaoType.displayStyle.copyWith(
                    fontSize: 26, color: ac.onAccent),
              ),
              const SizedBox(height: MaoSpace.sm),
              // 今日一言
              Text(
                '今日一言',
                style: MaoType.captionStyle
                    .copyWith(color: ac.onAccent.withOpacity(0.7)),
              ),
              const SizedBox(height: MaoSpace.xxs + 2),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: Text(
                  _hitokoto,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: MaoType.bodyStyle.copyWith(
                    color: ac.onAccent.withOpacity(0.92),
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: MaoSpace.xxl),
              SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                    strokeWidth: 2.6, color: ac.onAccent.withOpacity(0.9)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
