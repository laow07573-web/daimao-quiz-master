import 'package:flutter/widgets.dart';

/// 平板断点：按 Material 窗口分类，最短边 ≥ 600dp 视为平板/宽屏。
/// （手机竖屏最短边为屏宽 360~430dp，平板竖屏最短边 ≥ 600dp）
bool isTablet(BuildContext context) =>
    MediaQuery.sizeOf(context).shortestSide >= 600;

/// 宽屏布局断点（Material expanded 档）：窗口宽 ≥ 840dp 启用。
/// 覆盖 Windows 桌面窗口与平板横屏；平板竖屏（约 800dp）
/// 与手机仍走窄屏形态（底部导航 + 限宽单列）。
bool isWideLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= 840;

/// 页面内容最大宽度：平板上内容居中限宽，避免横向拉满；
/// 手机屏宽小于该值，包装后无任何影响。
const double kContentMaxWidth = 640;

/// 宽屏（PC/平板横屏）二级页限宽：信息密度提升但不拉满全屏。
/// v1.0.3 窗口自适应：取 1200（需大于首页双列阈值 1100，否则双列永远不生效）。
const double kWideContentMaxWidth = 1200;

/// 底部弹窗最大宽度（平板上弹窗不再横跨全屏）。
const double kSheetMaxWidth = 480;

/// 页面内容包装器：内容居中 + 限宽。
/// 用法：把 Scaffold 的 body 包一层 `ResponsivePage(child: ...)`。
/// AppBar / bottomNavigationBar / FAB 不受影响，仍为全宽。
/// 宽屏（[isWideLayout]）默认限宽自动提升至 [kWideContentMaxWidth]；
/// 显式传入 [maxWidth] 的用法不受影响。
class ResponsivePage extends StatelessWidget {
  final Widget child;

  /// 可覆盖的限宽值；不传时按断点自动选择（窄 [kContentMaxWidth] /
  /// 宽 [kWideContentMaxWidth]）
  final double maxWidth;

  const ResponsivePage({super.key, required this.child, this.maxWidth = 0});

  @override
  Widget build(BuildContext context) {
    final effectiveMax = maxWidth > 0
        ? maxWidth
        : (isWideLayout(context) ? kWideContentMaxWidth : kContentMaxWidth);
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: effectiveMax),
        child: child,
      ),
    );
  }
}

/// v1.0.3 窗口自适应：两个区块在可用宽度足够（默认 ≥900）时左右并排，
/// 不足时上下堆叠；拖动窗口尺寸时基于 LayoutBuilder 自动重排。
class AdaptivePair extends StatelessWidget {
  const AdaptivePair({
    super.key,
    required this.first,
    required this.second,
    this.minWidth = 900,
    this.gap = 14,
    this.equalHeight = false,
    this.targetHeight = 0,
  });

  final Widget first;
  final Widget second;
  final double minWidth;
  final double gap;

  /// v1.28：并排时是否让两卡片等高。
  /// 用于「年度坚持」与「近一年趋势」持平（用户反馈）。
  final bool equalHeight;

  /// 并排等高的目标高度（>0 时生效）。
  /// 父级高度无界（本组件常位于可滚动列），故用显式高度包一层，
  /// 让 Row 拿到有界高度后 stretch 才能生效。
  final double targetHeight;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth >= minWidth) {
        // v1.28 等高：给一层显式高度（父级高度无界时 stretch 会报无限高），
        // 使 Row 获得有界高度后 CrossAxisAlignment.stretch 生效。
        // 注意不能用 IntrinsicHeight：年度坚持内部含 LayoutBuilder，
        // 而 LayoutBuilder 不支持固有尺寸计算。
        final useStretch = equalHeight && targetHeight > 0;
        final row = Row(
          crossAxisAlignment: useStretch
              ? CrossAxisAlignment.stretch
              : CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            SizedBox(width: gap),
            Expanded(child: second),
          ],
        );
        return useStretch
            ? SizedBox(height: targetHeight, child: row)
            : row;
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          first,
          SizedBox(height: gap),
          second,
        ],
      );
    });
  }
}
