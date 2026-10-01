/// 互动式引导的一步
///
/// 一步只指一个地方：`anchorId` 指向真实控件（打洞高亮），
/// 没有 `anchorId` 的就是一段居中说明（欢迎这类）。
class GuideStep {
  const GuideStep({
    required this.title,
    required this.body,
    this.anchorId,
    this.fallbackAnchorIds = const [],
    this.tab,
    this.autoAdvanceTab,
    this.awaitAction = false,
    this.nextLabel,
  });

  final String title;
  final String body;

  /// 高亮的真实控件锚点 id；null = 居中气泡（没有具体控件可指）
  final String? anchorId;

  /// 备选锚点：主锚点此刻不存在时依次尝试。
  ///
  /// 用在「同一页有两种形态」的地方——错题本有数据才有筛选栏，
  /// 全新安装时那一页是空态：不合适的话高亮就没地方落。
  final List<String> fallbackAnchorIds;

  /// 本步实际要高亮的候选锚点（主锚点在前）
  List<String> get anchorIds =>
      [if (anchorId != null) anchorId!, ...fallbackAnchorIds];

  /// 进入本步前先切到的底部 Tab 下标；null = 不切换。
  ///
  /// 锚点在某张 Tab 页里时**必须**声明：IndexedStack 的未选中页每帧照常布局，
  /// 矩形一直取得到，不声明就可能把洞打到用户看不见的那一页坐标上。
  final int? tab;

  /// 用户自己点到了这个 Tab 就自动进下一步
  /// ——「一步一步带用户操作」的关键：真实操作本身就是推进器
  final int? autoAdvanceTab;

  /// 本步靠用户点高亮处把**页面推出来**（作用是导航），因此不出「下一步」：
  /// 否则一键跳到「还没打开的那一页」的引导步上，用户会找不到高亮处在哪。
  /// 「跳过」一直保留，不把人困住。
  final bool awaitAction;

  /// 主按钮文案（缺省「下一步」，末步「完成」）
  final String? nextLabel;
}
