import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flashcard_app/main.dart';
import 'package:flashcard_app/services/app_state.dart';
import 'package:flashcard_app/services/theme_service.dart';

void main() {
  testWidgets('App smoke test（启动闪屏 → 主界面）', (WidgetTester tester) async {
    final appState = AppState();
    final themeService = ThemeService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: appState),
          ChangeNotifierProvider<ThemeService>.value(value: themeService),
        ],
        child: const FlashcardApp(),
      ),
    );
    await tester.pump();

    // 启动闪屏页：软件名字 + 今日一言（v1.0.2 对齐原版开页面）
    expect(find.text('猫卷'), findsOneWidget);
    expect(find.text('今日一言'), findsOneWidget);
    // 测试环境网络不可用 → 一言回退默认文案
    await tester.pump();
    expect(find.text('刷题使我快乐，坚持就是胜利！'), findsOneWidget);

    // 2 秒后自动进入主界面（闪屏页 CircularProgressIndicator 为无限动画，
    // pumpAndSettle 永不收敛，改用显式 pump 推进过渡动画）
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    // 主界面：AppBar 标题 + 首页顶部 hero 卡片软件名字
    expect(find.text('猫卷'), findsNWidgets(2));
    // 首页顶部一言（闪屏已替换，仅 hero 一处，同样回退默认文案）
    expect(find.text('刷题使我快乐，坚持就是胜利！'), findsOneWidget);
  });
}
