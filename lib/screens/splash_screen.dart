import 'dart:async';

import 'package:flutter/material.dart';
import '../services/hitokoto_service.dart';
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
  String _hitokoto = '正在加载一言...';

  @override
  void initState() {
    super.initState();
    _loadHitokoto();
    // 固定 2 秒自动进入主界面
    _timer = Timer(const Duration(seconds: 2), _enterApp);
  }

  Future<void> _loadHitokoto() async {
    final text = await HitokotoService.fetch();
    if (!mounted) return;
    setState(() => _hitokoto = text ?? HitokotoService.defaultText);
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
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // App Logo（圆角 22px 图片）
            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Image.asset(
                'assets/app_logo.png',
                width: 96,
                height: 96,
                errorBuilder: (_, __, ___) =>
                    Icon(Icons.school, size: 88, color: cs.primary),
              ),
            ),
            const SizedBox(height: 20),
            // 软件名字
            Text(
              '猫卷',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            // 今日一言
            Text(
              '今日一言',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
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
                  fontSize: 14,
                  color: cs.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 32),
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
          ],
        ),
      ),
    );
  }
}
