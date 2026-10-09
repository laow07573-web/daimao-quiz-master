import 'package:flutter/widgets.dart';

import 'guide_controller.dart';

/// 把引导控制器提供给整棵树（挂在 [MaterialApp.builder] 里、Navigator 之上）
///
/// 任何页面（含二级页、弹窗）都能用它：
/// - [GuideAnchor] 靠它把真实控件登记进锚点表；
/// - 「我的 → 重看使用引导」靠它重新播放引导。
class GuideScope extends InheritedWidget {
  const GuideScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final GuideController controller;

  static GuideController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GuideScope>()?.controller;

  @override
  bool updateShouldNotify(GuideScope oldWidget) =>
      oldWidget.controller != controller;
}

/// 给真实控件打引导锚点：把目标控件包一层即可，不改变布局
///
/// 用 StatefulWidget 而不是无状态包 KeyedSubtree：**每个实例自己一把
/// GlobalKey**。同一 id 可能有多个实例（错题本空态的「去刷题」历史上会
/// `pushReplacement` 出第二个开始页，已于 2026-10-09 修掉；二级页压住
/// 一级页时同一 id 仍可能共存），一 id 一 key 会撞 GlobalKey。
/// 注册表按「最上层路由」挑可见的那个（见 [GuideAnchorRegistry]）。
///
/// 作用域不存在时（普通页面构建、单页测试）直接返回 [child]，
/// 零开销、也不影响任何既有行为。
class GuideAnchor extends StatefulWidget {
  const GuideAnchor({super.key, required this.id, required this.child});

  final String id;
  final Widget child;

  @override
  State<GuideAnchor> createState() => _GuideAnchorState();
}

class _GuideAnchorState extends State<GuideAnchor> {
  final GlobalKey _key = GlobalKey();

  GuideController? _controller;
  Route<dynamic>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = GuideScope.maybeOf(context);
    // 在这里（而不是 build 里）查路由：didChangeDependencies 阶段可以合法
    // 访问 InheritedWidget，且只会随依赖变化触发，不在每帧热路径上。
    final route = ModalRoute.of(context);
    if (controller == _controller && route == _route) return;
    _unregister();
    _controller = controller;
    _route = route;
    controller?.registry.register(widget.id, _key, route);
  }

  @override
  void didUpdateWidget(GuideAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      _unregister();
      _controller?.registry.register(widget.id, _key, _route);
    }
  }

  @override
  void dispose() {
    _unregister();
    super.dispose();
  }

  void _unregister() {
    _controller?.registry.unregister(widget.id, _key);
    _controller = null;
    _route = null;
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null) return widget.child;
    // KeyedSubtree 挂 key：currentContext 找不到 RenderObject 时会落到
    // 子树最近的 RenderObject 上，正好就是目标控件的真实矩形。
    return KeyedSubtree(key: _key, child: widget.child);
  }
}
