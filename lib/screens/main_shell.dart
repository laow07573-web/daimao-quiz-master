import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../services/theme_service.dart';
import '../utils/design_tokens.dart';
import '../utils/responsive.dart';
import '../widgets/command_palette.dart';
import '../widgets/guide/guide_anchor.dart';
import '../widgets/guide/guide_controller.dart';
import '../widgets/guide/guide_steps.dart';
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
/// v1.28.2：首启互动式引导由根节点的 `GuideHost` 负责遮罩，
/// 这里只上报 Tab 状态、把切页能力交给引导，并按 [startTour] 启动。
class MainShell extends StatefulWidget {
  const MainShell({super.key, this.startTour = false});

  /// 首启插播互动式引导（启动页按 `GuideService` 的标记传入）。
  /// 默认 false：既有调用点与测试都按「不插播」走。
  final bool startTour;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell>
    with SingleTickerProviderStateMixin {
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

  /// 引导控制器（挂在根节点；首帧后拿到并接线）
  GuideController? _guide;

  /// 切 Tab 的内容层过渡进度（0→1）。
  ///
  /// 为什么用控制器而不是「TweenAnimationBuilder + ValueKey(_index)」：
  /// 换血式 key 会让 IndexedStack 整棵子树重建——四个 Tab 里含热力图（371 格）
  /// 与趋势图，等于每次切页都重建全部页面，实测就是切页卡顿的来源。
  /// 现在孩子（IndexedStack）作为 AnimatedBuilder 的 child 缓存，动画 tick
  /// 只改透明度/位移，不触发页面重建。
  late final AnimationController _pageAnim;

  @override
  void initState() {
    super.initState();
    _pageAnim = AnimationController(
      vsync: this,
      duration: MaoMotion.normal,
      value: 1,
    );
    // 帧后再接线：引导要等主壳首帧布局落定才能量锚点矩形，
    // 也顺带避开在 initState 里访问 InheritedWidget
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _bindGuide();
    });
  }

  /// 把「切 Tab 的能力」交给引导，并上报当前 Tab / 按需启动首启引导
  void _bindGuide() {
    final guide = GuideScope.maybeOf(context);
    if (guide == null) return;
    _guide = guide;
    guide.attachTabSwitcher(_select);
    guide.setCurrentTab(_index);
    if (widget.startTour) guide.start();
  }

  @override
  void dispose() {
    _guide?.attachTabSwitcher(null);
    _pageAnim.dispose();
    super.dispose();
  }

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
      // 引导播放中不弹导入结果：弹窗会盖住引导，用户也没法边看引导边处理；
      // 结果留在待消费状态，引导结束后下一次 build 自然补弹。
      if (!mounted || _showingImportResult || (_guide?.active ?? false)) return;
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
    // 2026-10-09 用户要求：「切入其他页面的时候就不要显示这个提示了」。
    // SnackBar 挂在 root ScaffoldMessenger 上，切 Tab 不会自己消失——而它讲的
    // 往往是上一个页面的上下文（例如开始页的「先勾选要刷的题库」），跟到别的
    // 页面只会让人莫名其妙。这里连同排队中的一起清掉。
    ScaffoldMessenger.of(context).clearSnackBars();
    setState(() => _index = i);
    // 内容层过渡：每次切 Tab 从头演一次（不动时长则应立刻落位）
    _pageAnim.duration = MaoMotion.effective(context, MaoMotion.primaryPage);
    if (_pageAnim.duration == Duration.zero) {
      _pageAnim.value = 1;
    } else {
      _pageAnim.forward(from: 0);
    }
    // 上报给引导：某一步正等着用户自己点到这个 Tab
    _guide?.setCurrentTab(i);
    // 切 Tab 回调刷新（两形态共用）
    if (i == 0) {
      context.read<AppState>().refreshWeeklyStats();
    } else if (i == 2) {
      _statsKey.currentState?.refresh();
    }
  }

  /// 内容层：IndexedStack 保活 + 切 Tab 淡入并轻微横向落位。
  ///
  /// 关键：IndexedStack 作为 [AnimatedBuilder] 的 child 传入——动画 tick 只重建
  /// 外层 Opacity/FractionalTranslation，四个页面（含热力图与趋势图）不会被重建；
  /// 之前用 ValueKey 换血触发重建，切页会卡。
  /// 四个一级页面的**实例缓存**。
  ///
  /// 2026-10-09 真机反馈「一级页面切换明显卡顿」的真根因：切 Tab 会 setState，
  /// 而此前 children 是在 `_buildPages` 里**现场构造**的——每次 setState 都生成
  /// 四个新的页面 widget，Element 只能逐个 update，于是**四个页面（含统计页的
  /// 热力图 371 格与趋势图）全部 rebuild**。动画 tick 本身很轻，卡的是切换那一帧。
  ///
  /// 把列表缓存成同一个 List 实例后，children 的元素是 identical 的，
  /// Flutter 走「widget 未变」的快速路径，切页只换 IndexedStack 的 index。
  late final List<Widget> _pages = [
    HomeScreen(key: _homeKey),
    QuickStartScreen(key: _quickStartKey),
    StatsTab(key: _statsKey),
    ProfileTab(key: _profileKey),
  ];

  Widget _buildPages(BuildContext context) => AnimatedBuilder(
        animation: _pageAnim,
        child: IndexedStack(index: _index, children: _pages),
        builder: (context, child) {
          final t = _pageAnim.value;
          return Opacity(
            opacity: t,
            child: FractionalTranslation(
              translation: Offset((1 - t) * 0.04, 0),
              child: child,
            ),
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    // 后台导入：监听完成事件，主页栈顶时弹「导入完成」提示。
    _maybeShowImportResult(context.watch<AppState>());
    final ac = AppThemeColors.of(context);
    // 引导遮罩不在这里：它挂在根节点（`GuideHost`，MaterialApp.builder 里、
    // Navigator 之上），这样用户点高亮处跳进二级页面时引导能跟过去继续指。
    // 这里只负责把 Tab 状态与切页能力交给引导（见 [_bindGuide]）。
    return isWideLayout(context) ? _buildWideShell(ac) : _buildNarrowShell(ac);
  }

  /// 宽屏形态：左侧竖向导航 + 右侧内容区（PC / 平板横屏）
  Widget _buildWideShell(AppThemeColors ac) {
    return CommandPaletteShortcuts(
      child: Scaffold(
        body: Row(
          children: [
            GuideAnchor(
              // 锚点=侧边导航（宽屏形态）；引导里「自己点一下」那一步就点它
              id: GuideAnchorIds.shellNav,
              child: NavigationRail(
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
            ),
            VerticalDivider(width: 1, color: ac.border),
            Expanded(child: _buildPages(context)),
          ],
        ),
      ),
    );
  }

  /// 窄屏形态：底部 Tab
  Widget _buildNarrowShell(AppThemeColors ac) {
    return CommandPaletteShortcuts(
      child: Scaffold(
        body: _buildPages(context),
        bottomNavigationBar: GuideAnchor(
          // 锚点=整条底部导航：引导里「自己点一下开始」那一步就点它
          id: GuideAnchorIds.shellNav,
          child: DecoratedBox(
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
      ),
    );
  }
}
