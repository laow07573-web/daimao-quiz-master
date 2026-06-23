import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'services/app_state.dart';
import 'services/theme_service.dart';
import 'services/tamper_check.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 签名校验
  final ok = await TamperCheck.verify();
  if (!ok) {
    runApp(const _TamperedApp());
    return;
  }

  final appState = AppState();
  await appState.init();
  final themeService = ThemeService();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appState),
        ChangeNotifierProvider.value(value: themeService),
      ],
      child: const FlashcardApp(),
    ),
  );
}

/// 签名校验失败时显示的警告页
class _TamperedApp extends StatelessWidget {
  const _TamperedApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.warning_amber_rounded, size: 72, color: Colors.red),
              const SizedBox(height: 24),
              const Text('安全警告', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              const Text('检测到应用签名异常，可能是盗版或已被篡改。\n\n请从官方渠道重新下载安装，避免 API Key 泄露。', textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: Color(0xFF666666), height: 1.6)),
              const SizedBox(height: 32),
              FilledButton.tonalIcon(onPressed: () => SystemNavigator.pop(), icon: const Icon(Icons.exit_to_app), label: const Text('退出应用')),
            ]),
          ),
        ),
      ),
    );
  }
}

class FlashcardApp extends StatelessWidget {
  const FlashcardApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeService>().themeData;
    return MaterialApp(
      title: '呆猫刷题宝',
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: const AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(statusBarColor: Colors.transparent, statusBarIconBrightness: Brightness.dark),
        child: HomeScreen(),
      ),
    );
  }
}
