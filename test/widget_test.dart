import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flashcard_app/main.dart';
import 'package:flashcard_app/services/app_state.dart';
import 'package:flashcard_app/services/theme_service.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
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
    await tester.pump();

    // AppBar 标题 + 顶部 hero 卡片软件名字（v1.0.2 扩展）
    expect(find.text('呆猫刷题宝'), findsNWidgets(2));
    // 顶部今日一言：测试环境网络不可用 → 回退默认文案
    expect(find.text('刷题使我快乐，坚持就是胜利！'), findsOneWidget);
  });
}
