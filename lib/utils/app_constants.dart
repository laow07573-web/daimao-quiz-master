/// v1.0.2 设计审查修复：魔法数集中管理（此前散落各页面，改一处漏一处）。
library;

/// 版本号（首页页脚 / 我的页入口 / 关于弹窗共用）。
///
/// **唯一来源是 `pubspec.yaml` 的 `version:` 字段**（形如 `1.28.1+20`）：
/// 构建脚本与 CI 会传 `--dart-define=APP_VERSION=v<版本名>.<构建号>` 覆盖它，
/// 因此发布产物里的版本号必然来自 pubspec，不需要第二处手工填写。
///
/// 下面的 defaultValue 只服务本地 `flutter run` / `flutter test`（两者都不传
/// dart-define）。它与 pubspec 是否一致由 `test/version_single_source_test.dart`
/// 把关——改了 pubspec 却忘了同步这里，测试会红。这正是「APK versionName 误标」
/// 那类事故的根因，所以用测试锁住，而不是靠记性。
const String kAppVersion =
    String.fromEnvironment('APP_VERSION', defaultValue: 'v1.28.1.20');

/// 刷题数量「全部」哨兵值（9999）
const int kQuestionCountAll = 9999;

/// 日历 PageView 前后可翻页的年份跨度（初始页 = 当月 * 跨度，详见
/// weekly_stats_board / stats_tab 的 PageController 说明）
const int kYearPageSpan = 200;

/// AI 单题解析成本估算（余额提示文案用，元/题）
const double kAiCostPerQuestionYuan = 0.002;
