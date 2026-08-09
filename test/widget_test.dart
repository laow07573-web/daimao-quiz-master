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

    expect(find.text('呆猫刷题宝'), findsOneWidget);
  });
}
