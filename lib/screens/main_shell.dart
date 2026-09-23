import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../services/theme_service.dart';
import '../utils/design_tokens.dart';
import '../utils/responsive.dart';
import '../widgets/command_palette.dart';
import '../widgets/kit/mj_kit.dart';
import 'home_screen.dart';
import 'import_preview_screen.dart';
import 'profile_tab.dart';
import 'quick_start_screen.dart';
import 'settings_hub_screen.dart';
import 'stats_tab.dart';

/// 主壳：底部四 Tab（首页/开始/统计/我的）
///
/// 「开始」= 快速开始（原首页快速操作区独立成页）：首页只负责「看」，
/// 开始页只负责「做」——开始刷题 / 题库管理 / 错题本 / 导入。
/// IndexedStack 保活；切 Tab 回调刷新
/// （首页 refreshWeeklyStats、统计 StatsTabState.refresh）
/// v1.0.3 宽屏重设计：窗口宽 ≥ 840dp（PC/平板横屏）改用左侧竖向导航；
/// 手机与平板竖屏保留底部导航。两种形态共用保活与刷新逻辑。
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  /// 取证/诊断入口：--dart-define=MAOJUAN_GOTO=stats 启动直达统计页。
  /// 仅在显式构建参数下生效，正常包不受影响。
  static const String _goto = String.fromEnvironment('MAOJUAN_GOTO');

  int _index = _goto == 'stats' ? 2 : 0;

  // 四个 Tab 各挂 GlobalKey：内容层淡入的 key 随 _index 换血重建时，
  // 页面状态随 GlobalKey 迁移（保活语义不丢，见 [_buildPages]）。
  final GlobalKey _homeKey = GlobalKey();
  final GlobalKey _quickStartKey = GlobalKey();
  final GlobalKey<StatsTabState> _statsKey = GlobalKey<StatsTabState>();
  final GlobalKey _profileKey = GlobalKey();

  /// v1.27 后台导入：完成提示弹窗防重复标志。
  bool _showingImportResult = false;

  /// v1.27 后台导入：导入结束时弹「导入完成」提示。
  /// 仅当主页处于栈顶时弹（刷题/导入等页面在上层时不打扰，
  /// 返回后自动补弹）；弹窗仅一次（消费后清除）。
  void _maybeShowImportResult(AppState appState) {
    if (_showingImportResult) return;
    if (appState.pendingImportResult == null) return;
    // 用户已取消的任务：静默丢弃完成提示与解析结果，不打扰
    //（clearPreview 会 notifyListeners，不能在 build 里同步调用，挪到帧后）
    if (MJImportTask.discarded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        appState.consumeImportResult();
        appState.clearPreview();
        MJImportTask.discarded = false;
      });
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _showingImportResult) return;
      final route = ModalRoute.of(context);
      if (route == null || !route.isCurrent) return;
      final result = appState.consumeImportResult();
      if (result == null) return;
      _showingImportResult = true;
      final isPreviewKind =
          result.success && result.kind == ImportTaskKind.docxParse;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(result.success ? '导入完成' : '导入未完成'),
          content: Text(result.message),
          actions: [
            if (isPreviewKind)
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const ImportPreviewScreen()),
                  );
                },
                child: const Text('去预览'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(isPreviewKind ? '稍后' : '知道了'),
            ),
          ],
        ),
      ).whenComplete(() {
        if (mounted) setState(() => _showingImportResult = false);
      });
    });
  }

  void _select(int i) {
    if (i == _index) return;
    setState(() => _index = i);
    // 切 Tab 回调刷新（两形态共用）
    if (i == 0) {
      context.read<AppState>().refreshWeeklyStats();
    } else if (i == 2) {
      _statsKey.currentState?.refresh();
    }
  }

  /// 内容层：IndexedStack 保活 + 切 Tab 轻淡入（克制版）。
  ///
  /// TweenAnimationBuilder 的 key 随 _index 换血触发 0→1 淡入（MaoMotion.fast）；
  /// 四个 Tab 都挂 GlobalKey，换血重建时状态随 GlobalKey 迁移，保活不丢。
  /// NavigationBar 的指示器不做任何动画。
  Widget _buildPages(BuildContext context) => TweenAnimationBuilder<double>(
        key: ValueKey(_index),
        tween: Tween<double>(begin: 0, end: 1),
        duration: MaoMotion.effective(context, MaoMotion.fast),
        curve: MaoMotion.standard,
        builder: (context, t, child) => Opacity(opacity: t, child: child),
        child: IndexedStack(
          index: _index,
          children: [
            HomeScreen(key: _homeKey),
            QuickStartScreen(key: _quickStartKey),
            StatsTab(key: _statsKey),
            ProfileTab(key: _profileKey),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    // 后台导入：监听完成事件，主页栈顶时弹「导入完成」提示。
    _maybeShowImportResult(context.watch<AppState>());
    final ac = AppThemeColors.of(context);

    if (isWideLayout(context)) {
      // 宽屏形态：左侧竖向导航 + 右侧内容区（PC / 平板横屏）
      return CommandPaletteShortcuts(
        child: Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: _select,
              labelType: NavigationRailLabelType.all,
              // 底部设置入口（窄屏在首页 AppBar）
              trailing: Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: MaoSpace.md),
                    child: IconButton(
                      icon: const Icon(Icons.settings_outlined),
                      tooltip: '设置',
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const SettingsHubScreen()),
                      ),
                    ),
                  ),
                ),
              ),
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: Text('首页'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.bolt_outlined),
                  selectedIcon: Icon(Icons.bolt),
                  label: Text('开始'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.bar_chart_outlined),
                  selectedIcon: Icon(Icons.bar_chart),
                  label: Text('统计'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: Text('我的'),
                ),
              ],
            ),
            VerticalDivider(width: 1, color: ac.border),
            Expanded(child: _buildPages(context)),
          ],
        ),
        ),
      );
    }

    // 窄屏形态：底部 Tab
    return CommandPaletteShortcuts(
      child: Scaffold(
      body: _buildPages(context),
      bottomNavigationBar: DecoratedBox(
        // 顶部 hairline，与内容区分层（替代旧版无边界观感）
        decoration: BoxDecoration(
          border: Border(
              top: BorderSide(color: ac.border, width: MaoShadow.hairline)),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _select,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: '首页',
            ),
            NavigationDestination(
              icon: Icon(Icons.bolt_outlined),
              selectedIcon: Icon(Icons.bolt),
              label: '开始',
            ),
            NavigationDestination(
              icon: Icon(Icons.bar_chart_outlined),
              selectedIcon: Icon(Icons.bar_chart),
              label: '统计',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: '我的',
            ),
          ],
        ),
      ),
      ),
    );
  }
}
