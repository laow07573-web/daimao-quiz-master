import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'services/app_state.dart';
import 'services/database_service.dart';
import 'services/debug_log_service.dart';
import 'services/theme_service.dart';
import 'services/tamper_check.dart';
import 'services/reminder_service.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 签名校验（v1.0.2 里程碑一致：原版含防篡改）
  final ok = await TamperCheck.verify();
  if (!ok) {
    runApp(const _TamperedApp());
    return;
  }

  final appState = AppState();
  try {
    await appState.init();
  } catch (e) {
    // v1.0.2 修复：数据库损坏/半替换导致初始化失败时不再黑屏，
    // 展示恢复页（可重置数据库或退出）
    runApp(_DbErrorApp(error: '$e'));
    return;
  }
  final themeService = ThemeService();
  await themeService.init(); // v1.0.2 修复：恢复上次选择的主题

  // v1.0.2: 每日提醒（前台服务 + AlarmManager 双保险）；
  // 通知服务初始化异常不阻塞进入主界面
  try {
    await ReminderService.instance.init();
    await ReminderService.instance.syncSchedule();
  } catch (e) {
    // v1.0.2 设计审查修复：初始化失败至少留日志，不再完全静默
    DebugLogService.instance.log('REMINDER', '提醒服务初始化失败: $e');
  }
  try {
    ReminderService.instance.catchUpReminderIfMissed();
  } catch (_) {}

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
              // v1.0.2 设计审查修复：文案如实（本地存储为混淆级，不再宣称防泄露）
              const Text('检测到应用签名异常，可能是盗版或已被篡改。\n\n请从官方渠道重新下载安装。', textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: Colors.grey, height: 1.6)),
              const SizedBox(height: 32),
              FilledButton.tonalIcon(onPressed: () => SystemNavigator.pop(), icon: const Icon(Icons.exit_to_app), label: const Text('退出应用')),
            ]),
          ),
        ),
      ),
    );
  }
}

/// 数据库初始化失败时显示的恢复页（v1.0.2 修复：启动不再黑屏）
class _DbErrorApp extends StatefulWidget {
  const _DbErrorApp({required this.error});

  final String error;

  @override
  State<_DbErrorApp> createState() => _DbErrorAppState();
}

class _DbErrorAppState extends State<_DbErrorApp> {
  bool _resetting = false;

  Future<void> _resetAndRetry() async {
    setState(() => _resetting = true);
    try {
      await DatabaseService.instance.resetDatabase();
      final appState = AppState();
      await appState.init();
      final themeService = ThemeService();
      await themeService.init();
      try {
        await ReminderService.instance.init();
        await ReminderService.instance.syncSchedule();
      } catch (_) {}
      if (!mounted) return;
      runApp(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: appState),
            ChangeNotifierProvider.value(value: themeService),
          ],
          child: const FlashcardApp(),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _resetting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('重置失败：$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.error_outline, size: 72, color: Colors.deepOrange),
              const SizedBox(height: 24),
              const Text('数据初始化失败', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Text(
                '本地数据文件可能已损坏。可以重置数据后重新开始（将清空全部题库与记录），\n或退出应用。\n\n错误详情：${widget.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Colors.grey, height: 1.6),
              ),
              const SizedBox(height: 32),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                FilledButton.icon(
                  onPressed: _resetting ? null : _resetAndRetry,
                  icon: _resetting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh),
                  label: Text(_resetting ? '重置中...' : '重置数据并重试'),
                ),
                const SizedBox(width: 16),
                OutlinedButton.icon(
                  onPressed: () => SystemNavigator.pop(),
                  icon: const Icon(Icons.exit_to_app),
                  label: const Text('退出'),
                ),
              ]),
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
    // v1.0.2 设计审查修复：状态栏图标亮度跟随导航栏色
    // （星际穿越/碧海银河深色导航栏下此前深色图标不可见）
    final navBar = theme.extension<AppThemeColors>()?.navBar;
    final statusBarIconBrightness =
        ThemeData.estimateBrightnessForColor(navBar ?? Colors.black) ==
                Brightness.dark
            ? Brightness.light
            : Brightness.dark;
    return MaterialApp(
      title: '呆猫刷题宝',
      debugShowCheckedModeBanner: false,
      theme: theme,
      // v1.0.2 对齐原版设计：启动闪屏页（Logo + 标题 + 今日一言，2 秒进主界面）
      home: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: statusBarIconBrightness,
        ),
        child: const SplashScreen(),
      ),
    );
  }
}
