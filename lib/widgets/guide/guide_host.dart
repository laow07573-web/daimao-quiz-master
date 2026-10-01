import 'package:flutter/widgets.dart';

import 'guide_anchor.dart';
import 'guide_controller.dart';
import 'guide_tour.dart';

/// 全 App 的引导宿主：把引导遮罩挂在 **Navigator 之上**
///
/// 位置很关键——放在主壳里的话，用户点高亮处跳进二级页面（导入题库、
/// 错题本、配置弹窗）时遮罩会被新路由盖住，引导就断了；
/// 挂在 Navigator 之上，引导才能跟着用户跨页面继续指。
class GuideHost extends StatelessWidget {
  const GuideHost({super.key, required this.controller, required this.child});

  final GuideController controller;

  /// 通常是 [MaterialApp.builder] 传进来的 Navigator
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GuideScope(
      controller: controller,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => Stack(
          fit: StackFit.expand,
          children: [
            child,
            if (controller.active) GuideTour(controller: controller),
          ],
        ),
      ),
    );
  }
}
