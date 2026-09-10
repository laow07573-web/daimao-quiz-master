import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../utils/responsive.dart';
import 'home_screen.dart';
import 'import_preview_screen.dart';
import 'profile_tab.dart';
import 'settings_screen.dart';
import 'stats_tab.dart';

/// 主壳（v1.0.2）：底部三 Tab（首页/统计/我的）
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

  int _index = _goto == 'stats' ? 1 : 0;
  final GlobalKey<StatsTabState> _statsKey = GlobalKey<StatsTabState>();

  /// v1.27 后台导入：完成提示弹窗防重复标志。
  bool _showingImportResult = false;

  /// v1.27 后台导入：导入结束时弹「导入完成」提示。
  /// 仅当主页处于栈顶时弹（刷题/导入等页面在上层时不打扰，
  /// 返回后自动补弹）；弹窗仅一次（消费后清除）。
  void _maybeShowImportResult(AppState appState) {
    if (_showingImportResult) return;
    if (appState.pendingImportResult == null) return;
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
    } else if (i == 1) {
      _statsKey.currentState?.refresh();
    }
  }

  Widget _buildPages() => IndexedStack(
        index: _index,
        children: [
          const HomeScreen(),
          StatsTab(key: _statsKey),
          const ProfileTab(),
        ],
      );

  @override
  Widget build(BuildContext context) {
    // v1.27 后台导入：监听完成事件，主页栈顶时弹「导入完成」提示。
    _maybeShowImportResult(context.watch<AppState>());
    if (isWideLayout(context)) {
      // 宽屏形态：左侧竖向导航 + 右侧内容区（PC / 平板横屏）
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: _select,
              labelType: NavigationRailLabelType.all,
              // v1.0.3 宽屏重设计：底部设置入口（窄屏在首页 AppBar）
              trailing: Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: IconButton(
                      icon: const Icon(Icons.settings_outlined),
                      tooltip: '设置',
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const SettingsScreen()),
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
            const VerticalDivider(width: 1),
            Expanded(child: _buildPages()),
          ],
        ),
      );
    }
    // 窄屏形态：底部三 Tab，原有设计零改动
    return Scaffold(
      body: _buildPages(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _select,
        // v1.0.2 UI 设计稿：底部导航三 Tab（首页/统计/我的）
        // 视觉审查修复：emoji 图标换为 Material 图标（跟随主题、跨机型一致，
        // 选中态由 NavigationBar indicator 表达）
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '首页',
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
    );
  }
}
