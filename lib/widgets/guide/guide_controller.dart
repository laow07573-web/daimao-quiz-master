import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../services/guide_service.dart';
import 'guide_steps.dart';

/// 引导锚点注册表（整个 App 一份，跨页面共用）
///
/// 互动式引导要在**真实控件**上打洞高亮，就得拿到控件的屏幕矩形。
/// 两个刻意设计：
/// 1. **每个锚点实例自己一把 GlobalKey**（而不是一 id 一把全局 key）：
///    同一 id 可能同时存在两个实例（历史上错题本空态的「去刷题」会
///    `pushReplacement` 出第二个开始页，该行为已于 2026-10-09 修掉），
///    一 id 一 key 会直接撞出「Multiple widgets used the same GlobalKey」。
///    保留「一实例一 key」是因为二级页压住一级页、引导层插在 Navigator 之上时，
///    同一 id 仍可能短暂共存两份。
/// 2. **按路由挑可见的那一个**：被二级页/弹窗压住的页面仍在渲染树里、
///    矩形照样量得到，不判路由就会把洞打到用户看不见的页面上。
class GuideAnchorRegistry {
  GuideAnchorRegistry();

  final Map<String, List<_AnchorEntry>> _entries = {};

  /// 当前最上层路由，由 [GuideController] 在导航事件里维护。
  ///
  /// 用它而不是在测量时现查 `ModalRoute.of`：测量发生在 Timer 回调里，
  /// 那里查路由会平白注册依赖，也可能读到过期状态。
  Route<dynamic>? currentRoute;

  @visibleForTesting
  Iterable<String> get ids => _entries.keys;

  @visibleForTesting
  int instancesOf(String id) => _entries[id]?.length ?? 0;

  void register(String id, GlobalKey key, Route<dynamic>? route) {
    final list = _entries.putIfAbsent(id, () => <_AnchorEntry>[]);
    if (list.any((e) => e.key == key)) return;
    list.add(_AnchorEntry(key, route));
  }

  void unregister(String id, GlobalKey key) {
    final list = _entries[id];
    if (list == null) return;
    list.removeWhere((e) => e.key == key);
    if (list.isEmpty) _entries.remove(id);
  }

  /// 路由过滤：没接观察者（单页测试）或锚点不在路由里时不过滤
  bool _routeOk(Route<dynamic>? route) =>
      currentRoute == null || route == null || route == currentRoute;

  /// 当前「可见且已布局」的那个锚点
  _AnchorEntry? _visible(String id) {
    final list = _entries[id];
    if (list == null) return null;
    for (final e in list) {
      if (!_routeOk(e.route)) continue;
      final ro = e.key.currentContext?.findRenderObject();
      if (ro is! RenderBox || !ro.attached || !ro.hasSize) continue;
      if (ro.size.width <= 0 || ro.size.height <= 0) continue;
      return e;
    }
    return null;
  }

  /// 锚点当前挂载的 [BuildContext]（可见实例都没有则为 null）。
  /// 引导用它把目标滚进视区（`Scrollable.ensureVisible`）：
  /// 列表下方的目标不打滚就量到屏幕外。
  BuildContext? contextOf(String id) => _visible(id)?.key.currentContext;

  /// 锚点当前的真实屏幕矩形；不可见 / 未布局返回 null
  Rect? rectOf(String id) {
    final ro = _visible(id)?.key.currentContext?.findRenderObject();
    if (ro is! RenderBox || !ro.attached || !ro.hasSize) return null;
    return ro.localToGlobal(Offset.zero) & ro.size;
  }
}

class _AnchorEntry {
  _AnchorEntry(this.key, this.route);

  final GlobalKey key;
  final Route<dynamic>? route;
}

/// 引导控制器：引导的唯一状态源，由 App 根节点持有（[MainShell] 之上）
///
/// 为什么必须在根节点：用户点高亮处会跳进二级页面（导入题库、配置弹窗），
/// 引导要**跟着过去继续指**——所以遮罩层要盖在整个 Navigator 之上，
/// 锚点注册表也要跨页面共用一份，路由一变就重新找目标。
class GuideController extends ChangeNotifier {
  GuideController({this.steps = kGuideSteps});

  /// 引导步骤（默认 [kGuideSteps]；测试可注入自己的步骤表）
  final List<GuideStep> steps;

  /// 跨页面共用的锚点注册表
  final GuideAnchorRegistry registry = GuideAnchorRegistry();

  int _index = 0;
  bool _active = false;
  int _routeEpoch = 0;
  int _currentTab = 0;

  /// 用户刚跳了页面、但「下一步」的目标还没出现（新页面在异步加载中）；
  /// 目标一出现就把引导带过去（见 [tickPendingFollow]）
  bool _pendingFollow = false;
  ValueChanged<int>? _tabSwitcher;

  bool get active => _active;
  int get index => _index;
  int get routeEpoch => _routeEpoch;
  int get currentTab => _currentTab;
  GuideStep get step => steps[_index];
  GuideStep? get nextStep =>
      _index + 1 < steps.length ? steps[_index + 1] : null;
  bool get isLast => _index >= steps.length - 1;

  /// 主壳注册的切 Tab 回调：引导只表达「要切到哪个 Tab」，不直接改别人的状态
  void attachTabSwitcher(ValueChanged<int>? switcher) =>
      _tabSwitcher = switcher;

  /// 主壳上报当前 Tab（用户自己点到了这一步等着的那一页就顺势前进）
  void setCurrentTab(int tab) {
    if (_currentTab == tab) return;
    _currentTab = tab;
    if (!_active) return;
    // 真实操作本身就是推进器：引导说「点一下底部的开始」，用户真点了
    // 就自动进下一步，不必再让他去找「下一步」按钮
    if (step.autoAdvanceTab == tab) {
      if (isLast) {
        unawaited(skip());
        return;
      }
      _index++;
    }
    notifyListeners();
  }

  void requestTab(int tab) {
    if (tab == _currentTab) return;
    _tabSwitcher?.call(tab);
  }

  /// 开始 / 重播引导（已在播放时是无操作）
  void start() {
    if (_active) return;
    _active = true;
    _index = 0;
    _pendingFollow = false;
    _routeEpoch++;
    notifyListeners();
  }

  /// 下一步（末步则收尾）
  void next() {
    if (!_active) return;
    if (isLast) {
      unawaited(skip());
      return;
    }
    _index++;
    notifyListeners();
  }

  /// 跳过 / 收尾：先关掉引导，再落「已看过」标记（幂等）
  Future<void> skip() async {
    if (!_active) return;
    _active = false;
    _pendingFollow = false;
    notifyListeners();
    await GuideService.instance.markSeen();
  }

  /// 路由变化（push / pop / 替换 / 弹窗）：把引导带到用户刚打开的那一页
  ///
  /// 这正是「点高亮处跳进二级页面后引导还要继续」的实现：
  /// 新页面把「下一步」的目标呈现出来了，就顺势前进——
  /// 不必猜用户点了什么，也不用给控件套手势监听（那会干扰真实交互）。
  void onRouteChanged(Route<dynamic>? current) {
    if (current != null) registry.currentRoute = current;
    if (!_active) return;
    // didPush 这一刻新页面还没布局，量不到锚点：等这一帧画完再判定
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_active) return;
      _routeEpoch++;
      if (isLast) {
        // 最后一步就是「做一次真实操作」：操作带来了页面跳转 = 引导功德圆满
        unawaited(skip());
        return;
      }
      if (_nextStepVisible()) {
        _pendingFollow = false;
        _index++;
      } else {
        // 新页面可能是异步加载的（错题本首帧是骨架屏、统计要等数据），
        // 这一刻还没有锚点：登记「等它出现就前进」，由引导层每次重试时催一次
        _pendingFollow = true;
      }
      notifyListeners();
    });
  }

  /// 引导层每次测量重试时催一下：路由变化后一直没等到的那次前进。
  ///
  /// 只在路由变化当时没判成功过（[_pendingFollow]）时才动作，
  /// 且成功一次就清标志——不会「一路跳完所有步骤」。
  void tickPendingFollow() {
    if (!_active || !_pendingFollow) return;
    if (!_nextStepVisible()) return;
    _pendingFollow = false;
    if (isLast) {
      unawaited(skip());
      return;
    }
    _index++;
    notifyListeners();
  }

  bool _nextStepVisible() {
    for (final id in nextStep?.anchorIds ?? const <String>[]) {
      if (registry.rectOf(id) != null) return true;
    }
    return false;
  }
}

/// 导航观察者：把路由事件转给 [GuideController]，
/// 并让注册表知道「现在哪张页面在最上层」
class GuideRouteObserver extends NavigatorObserver {
  GuideRouteObserver(this.controller);

  final GuideController controller;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      controller.onRouteChanged(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      controller.onRouteChanged(previousRoute);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      controller.onRouteChanged(newRoute);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      controller.onRouteChanged(previousRoute);
}
