import 'guide_step.dart';

export 'guide_step.dart';

/// 引导锚点 id（与 `GuideAnchor(id: ...)` 一一对应）
///
/// 集中定义：步骤文案与锚点挂载点分处不同文件，靠常量对齐。
/// 写错 id 的后果是「这一步没有洞」——由 `GuideTour` 的兜底处理收住，不会崩。
class GuideAnchorIds {
  GuideAnchorIds._();

  /// 底部导航 / 侧边导航（两种宽屏形态共用同一 id）
  static const String shellNav = 'shell.nav';

  /// 首页「本周战绩」卡
  static const String homeWeekly = 'home.weekly';

  /// 开始页「导入题库」入口
  static const String quickImport = 'quick.import';

  /// 开始页「定向爆破」（开始刷题）主行动
  static const String quickPrimary = 'quick.primary';

  /// 开始页「错题本」入口
  static const String quickErrorBook = 'quick.errorbook';

  /// 统计页顶部概览区
  static const String statsOverview = 'stats.overview';

  /// 我的页「设置」入口
  static const String profileSettings = 'profile.settings';

  /// 导入页「一键导入示例题库」（二级页锚点）
  static const String importSample = 'import.sample';

  /// 「开始刷题」弹窗里的最终确认按钮「开始」（弹层锚点）
  static const String sheetConfirm = 'sheet.confirm';
}

/// 首启引导步骤（互动式：高亮真实控件，切页与前进都跟着真实操作走）
///
/// 前几步是「认路」（看进度 → 认四个 Tab → 认开始页的三个入口 → 统计 → 我的），
/// 最后四步是**真的走一遍**「导入 → 刷题」——其中第 9、11 步分别在
/// 导入页与配置弹窗里，用户点高亮处跳进去，引导会跟着进去继续指。
///
/// 文案只讲界面上确实存在的东西，不承诺没有的功能
/// （例如错题本的筛选芯片实际叫「全部 / 错题 / 收藏」）。
const List<GuideStep> kGuideSteps = [
  GuideStep(
    title: '一分钟上手猫卷',
    body: '跟着走一遍：导入题库 → 刷题 → 看统计。每一步只高亮一个地方，照着点就行；'
        '点进二级页面时引导也会跟进去，随时能跳过。',
    nextLabel: '开始',
  ),
  GuideStep(
    title: '首页：先看进度',
    body: '累计刷题时长、总题量、正确率，以及本周战绩与打卡日历都在这一屏。',
    // 必须声明 tab：IndexedStack 的未选中页每帧照常布局，不声明就可能把洞
    // 打到「当前看不见那一页」的坐标上（从「我的 → 重看」重播时必现）
    tab: 0,
    anchorId: GuideAnchorIds.homeWeekly,
  ),
  GuideStep(
    title: '底部这四个 Tab',
    body: '「首页」看进度、「开始」动手、「统计」看数据、「我的」做设置。'
        '点一下底部的「开始」，我们接着往下走。',
    anchorId: GuideAnchorIds.shellNav,
    // 用户自己点到「开始」就自动前进：这一步要的是他真的动手
    autoAdvanceTab: 1,
  ),
  GuideStep(
    title: '动手都在「开始」页',
    body: '导入题库、开始刷题、错题本、题库管理都收在这一页。先认个门，'
        '最后几步我们真的走一遍「导入 → 刷题」。',
    tab: 1,
    anchorId: GuideAnchorIds.quickImport,
  ),
  GuideStep(
    title: '错题本：到期就复习',
    body: '答错的题会按记忆曲线排进复习，进错题本可以按「全部 / 错题 / 收藏」筛选。',
    tab: 1,
    anchorId: GuideAnchorIds.quickErrorBook,
  ),
  GuideStep(
    title: '统计：用数据找薄弱点',
    body: '正确率、近一年趋势、年度热力图与知识点排行，帮你决定下一步补哪里。',
    tab: 2,
    anchorId: GuideAnchorIds.statsOverview,
  ),
  GuideStep(
    title: '我的：主题、提醒、API Key',
    body: '换主题、设学习提醒、填自己的 API Key 开启 AI 解析与追问；'
        '也能在这里随时重看这段引导。',
    tab: 3,
    anchorId: GuideAnchorIds.profileSettings,
  ),
  GuideStep(
    title: '现在真的试一次：导入题库',
    body: '回到「开始」页——点这个入口进导入页，引导会跟着进去继续指。',
    tab: 1,
    anchorId: GuideAnchorIds.quickImport,
  ),
  GuideStep(
    title: '一键导入示例题库',
    body: '第一次用不用自己准备文件：点这一块就能导入 10 道内置医学示例题，'
        '不需要 API Key，导完会自动回到「开始」页。',
    tab: 1,
    anchorId: GuideAnchorIds.importSample,
  ),
  GuideStep(
    title: '有题了，开始刷题',
    body: '点「定向爆破」，选题库和题数就能开刷；单选、多选、填空、简答都支持。',
    tab: 1,
    anchorId: GuideAnchorIds.quickPrimary,
  ),
  GuideStep(
    title: '弹窗里点「开始」',
    body: '题数与模式调好后点「开始」就进入答题，提交即判对错。'
        '到这儿就上手了，之后随时可以在「我的」里重看这段引导。',
    tab: 1,
    anchorId: GuideAnchorIds.sheetConfirm,
    nextLabel: '完成',
  ),
];
