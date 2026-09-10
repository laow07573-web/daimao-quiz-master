import '../utils/design_tokens.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import '../services/hitokoto_service.dart';
import '../services/theme_service.dart';
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
    // v1.0.2 UI 审查修复：浅色主题下白底闪屏与白底 logo 融合不可辨，
    // 改为导航色深底 + 浅色文字；浅色导航主题（护眼/极简）向黑加深
    final ac = AppThemeColors.of(context);
    final nav = ac.navBar;
    final bg = ThemeData.estimateBrightnessForColor(nav) == Brightness.light
        ? Color.lerp(nav, Colors.black, 0.35)!
        : nav;
    return Scaffold(
      backgroundColor: bg,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // App Logo（圆角 22px 图片）
            ClipRRect(
              borderRadius: BorderRadius.circular(MaoRadius.large),
              child: Image.asset(
                'assets/app_logo.png',
                width: 96,
                height: 96,
                errorBuilder: (_, __, ___) =>
                    Icon(Icons.school, size: 88, color: Colors.white),
              ),
            ),
            const SizedBox(height: 20),
            // 软件名字
            Text(
              '猫卷',
              style: TextStyle(
                fontSize: MaoType.display,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            // 今日一言
            Text(
              '今日一言',
              style: TextStyle(fontSize: MaoType.body, color: Colors.white.withOpacity(0.6)),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: Text(
                _hitokoto,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: MaoType.body,
                  color: Colors.white.withOpacity(0.85),
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 32),
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
