/// 互动式引导的一步
///
/// 一步只指一个地方：`anchorId` 指向真实控件（打洞高亮），
/// 没有 `anchorId` 的就是一段居中说明（欢迎 / 收尾这类）。
class GuideStep {
  const GuideStep({
    required this.title,
    required this.body,
    this.anchorId,
    this.tab,
    this.autoAdvanceTab,
    this.nextLabel,
  });

  final String title;
  final String body;

  /// 高亮的真实控件锚点 id；null = 居中气泡（没有具体控件可指）
  final String? anchorId;

  /// 进入本步前先切到的底部 Tab 下标；null = 不切换。
  ///
  /// 锚点在某张 Tab 页里时**必须**声明：IndexedStack 的未选中页每帧照常布局，
  /// 矩形一直取得到，不声明就可能把洞打到用户看不见的那一页坐标上。
  final int? tab;

  /// 用户自己点到了这个 Tab 就自动进下一步
  /// ——「一步一步带用户操作」的关键：真实操作本身就是推进器
  final int? autoAdvanceTab;

  /// 主按钮文案（缺省「下一步」，末步「完成」）
  final String? nextLabel;
}
