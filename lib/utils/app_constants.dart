/// v1.0.2 设计审查修复：魔法数集中管理（此前散落各页面，改一处漏一处）。
library;

/// 版本号（首页页脚 / 我的页入口 / 关于弹窗共用，发布时只改这里）
const String kAppVersion = 'v1.28.0.19';

/// 刷题数量「全部」哨兵值（9999）
const int kQuestionCountAll = 9999;

/// 日历 PageView 前后可翻页的年份跨度（初始页 = 当月 * 跨度，详见
/// weekly_stats_board / stats_tab 的 PageController 说明）
const int kYearPageSpan = 200;

/// AI 单题解析成本估算（余额提示文案用，元/题）
const double kAiCostPerQuestionYuan = 0.002;
