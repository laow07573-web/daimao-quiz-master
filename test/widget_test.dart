import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flashcard_app/main.dart';
import 'package:flashcard_app/services/app_state.dart';
import 'package:flashcard_app/services/guide_service.dart';
import 'package:flashcard_app/services/theme_service.dart';

void main() {
  Widget app() => MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: AppState()),
          ChangeNotifierProvider<ThemeService>.value(value: ThemeService()),
        ],
        child: const FlashcardApp(),
      );

  testWidgets('App smoke test（启动闪屏 → 主界面）', (WidgetTester tester) async {
    // 老用户路径：引导已看过 → 闪屏之后直接进主界面
    SharedPreferences.setMockInitialValues({GuideService.keyGuideSeenV1: true});
    GuideService.instance.resetCacheForTest();

    await tester.pumpWidget(app());
    await tester.pump();

    // 启动闪屏页：软件名字 + 今日一言（v1.0.2 对齐原版开页面）。
    expect(find.text('猫卷'), findsOneWidget);
    expect(find.text('今日一言'), findsOneWidget);
    // v1.27 PC 加载修复：一言首帧直接显示本地一言库，
    // 永不再出现「正在加载一言...」占位（网络不可用时也如此）。
    await tester.pump();
    expect(find.text('正在加载一言...'), findsNothing);

    // 1.4 秒后自动进入下一步（闪屏页 CircularProgressIndicator 为无限动画，
    // pumpAndSettle 永不收敛，改用显式 pump 推进过渡动画）
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    // 主界面：AppBar 标题 + 首页顶部 hero 卡片软件名字。
    expect(find.text('猫卷'), findsNWidgets(2));
    // 首页顶部一言（v1.27）：同样不再出现加载占位，直接显示本地一言库。
    expect(find.text('正在加载一言...'), findsNothing);
  });

  testWidgets('首启路径：闪屏之后插播使用引导（看完不再插播）', (WidgetTester tester) async {
    // 全新安装：没有已看标记 → 首次启动必须看到引导
    SharedPreferences.setMockInitialValues({});
    GuideService.instance.resetCacheForTest();

    await tester.pumpWidget(app());
    await tester.pump();
    expect(find.text('今日一言'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('先导入一份题库'), findsOneWidget,
        reason: '首启应落在使用引导，而不是直接进主界面');
    expect(find.text('跳过'), findsOneWidget);

    // 收尾：摘掉页面以停掉引导页持续呼吸的动画，避免留下活跃 ticker
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
