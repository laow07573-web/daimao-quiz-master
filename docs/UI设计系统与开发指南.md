# 猫卷 UI 设计与开发指南（AI 助手交接文档）

> 版本：v1.0.2（2026-08-22）· 目的：给 Qoder CN / 任何 AI 开发工具无缝接手 UI 设计工作
> 配套材料：`docs/功能实现路径.md`（链路）、`docs/UI交互缺陷审查报告.md`（已修复档案）、`docs/UI交互缺陷审查报告.md` 修复 commit `b9e43db / 4c32adc / 0c077af / a3be67d`

---

## 1. 项目速览

- **定位**：面向医学生的本地优先开源免费刷题 App（Android 端），无账号/无广告/无会员，AI 讲解走 BYOK（用户自持 API Key）
- **技术栈**：Flutter 3.24.5 / Dart 3.5.4 · SQLite（schema **v9**）· Provider · FSRS-5 · DeepSeek API
- **工程规模**：109 项自动化测试全绿 · 发布四维基线校验（组件/权限/文案/资源）· APK 签名锁定防篡改
- **代码目录**：`lib/screens/`（15 个页面）、`lib/widgets/`（自定义组件）、`lib/services/`（状态与数据层）、`lib/models/`、`test/`（109 项）
- **核心不变量**：包名 `com.flashcard.app`、签名证书 SHA-256 `43a9e0a1…60fe`、schema 版本 9、main 分支

---

## 2. UI 设计系统（重设计第一原则：永远通过语义色取色）

### 2.1 主题结构

- 5 套主题（枚举 `AppTheme`）：`brand` 品牌鲜明 / `eyeCare` 护眼柔和 / `minimal` 极简 / `starVoyage` 星际穿越 / `oceanGalaxy` 碧海银河
- 每套主题有**浅色 + 深色两套色板**（`ThemeService._colorsOf` / `_darkColorsOf`），配合 `ThemeMode`（跟随系统 / 浅色 / 深色）共 5×2 形态
- 全局入口：`lib/services/theme_service.dart`（枚举、色板、`AppThemeColors` 扩展、`labelOf`、`previewColorsOf`、切换持久化）

### 2.2 取色规则（必守）

```dart
// ✅ 唯一正确姿势：从上下文取语义色
final ac = AppThemeColors.of(context);   // 或 Theme.of(context).extension<AppThemeColors>()!
// ❌ 禁止：UI 中硬编码 Color(0xFF...)、Colors.xxx（黑/白/红/绿直接写）
```

语义色清单（`AppThemeColors`）：

| 字段 | 用途 | 默认值（未在色板覆盖时） |
|---|---|---|
| `navBar` | AppBar/导航栏 | 主题主色 |
| `background` | 页面背景 | — |
| `accent` | 按钮/高亮/进度条/选中态 | — |
| `onAccent` | accent 上的文字/图标 | 白或深色（随变体） |
| `card` / `cardBorder` | 卡片与描边 | — |
| `success` / `successContainer` | **判题对、背题高亮、正确项**（绿系，跨主题恒绿） | `#5CB85C` / `#E8F5E9` |
| `danger` / `dangerContainer` | **判题错、危险操作**（红系，跨主题恒红） | `#D9534F` / `#FDECEA` |
| `warning` | 余额不足、未配置提示（橙） | `#F0AD4E` |

> ⚠️ 历史教训：曾用 M3 的 `tertiary`（紫）/`error`（红）判题，碧海主题下"正确=粉紫、错误=橙"，与绿对红错心智不符（`quiz_screen.dart` 三处已改语义色）——**重设计时勿回退到 tertiary/error 判题色**。

### 2.3 色板速查（重设计改色时务必双套都改）

**浅色**（navBar / background / accent）：

| 主题 | navBar | background | accent |
|---|---|---|---|
| brand | `#5D5FEF` | `#F5F6FA` | `#5D5FEF` |
| eyeCare | `#DAE1D4` | `#FAFAF9` | `#4A7A5D` |
| minimal | `#E4ECF3` | `#F9FAFB` | `#2DA8A6` |
| starVoyage | `#1D1A1A` | `#E8DDCB` | `#E96D39` |
| oceanGalaxy | `#1A253E` | `#F0F4F9` | `#4C7CD6` |

**深色**（navBar / background / accent / onAccent）：

| 主题 | navBar | background | accent | onAccent |
|---|---|---|---|---|
| brand | `#4344B8` | `#14151F` | `#8B8CF8` | `#14151F` |
| eyeCare | `#2C3A31` | `#131713` | `#7BA98A` | `#131713` |
| minimal | `#17464A` | `#0F1517` | `#57CBC4` | `#0F1517` |
| starVoyage | `#33241B` | `#1A1410` | `#F08A52` | `#1A1410` |
| oceanGalaxy | `#1D2A4A` | `#101624` | `#7CA3E8` | `#101624` |

> 卡片/描边：浅色 = 白 / 各主题浅灰蓝；深色 = `card` 略亮于 `background`、`cardBorder` 再亮一档（详见 `_darkColorsOf`）。

### 2.4 主题切换链路

`settings_screen.dart`（主题单选 + 深色模式单选）→ `ThemeService.switchTo(v)` / `switchThemeMode(v)` → `notifyListeners()` → `main.dart` 重建 MaterialApp（theme/darkTheme/themeMode）→ 全页面即时生效。设置页已做三色预览圆点（`previewColorsOf`）。

---

## 3. 关键 UI 组件地图

| 区域 | 文件 | 注意点 |
|---|---|---|
| 主壳三 Tab | `lib/screens/main_shell.dart` | IndexedStack 保活，切 Tab 触发的刷新回调勿丢 |
| 首页 | `lib/screens/home_screen.dart` | 战区卡/指标卡/快速操作/月历热力/断点续刷卡 |
| 答题页（刷题/练习/背题统一） | `lib/screens/quiz_screen.dart` | **判题色=语义色**；底部三按钮单行；未答题有引导提示；**追问=聊天气泡区**（用户右/AI 左） |
| AI 回复渲染 | `lib/widgets/ai_response_widget.dart` | **自研轻量渲染器**：`**加粗**`/`- 列表`/`# 标题`/Markdown 表格/`代码`/缩进嵌套。**勿换回 flutter_markdown 0.7.1**（中文全角标点后星号解析失败 bug）。表格渲染有测试锁定 |
| 统计页 | `lib/screens/stats_tab.dart` + `lib/widgets/trend_chart.dart`、`monthly_calendar.dart` | 趋势图轴 `chartMax=max(20, dataMax*1.15)`（小值柱可见）；「按知识点」排行键为 `name/accuracy`（对齐 `_AccuracyRanking`，勿改回 kp 键） |
| 设置页 | `lib/screens/settings_screen.dart` | API 配置/主题/提醒/保活/调试日志（导出按钮短文案限行） |
| 错题本/练习/小结 | `error_book_screen.dart` / `practice_screen.dart` / `session_summary_screen.dart` | 答错弹窗逐题下次复习（FSRS 可见化） |
| 闪屏 | `lib/screens/splash_screen.dart` | **深底闪屏**（浅色导航主题自动向黑加深 35%），1.4s；白色文字 |

各组件均从 `AppThemeColors` 取色；**新增视觉效果请扩展语义色而非硬编码**。

---

## 4. UI 重设计红线（改完自检清单）

1. **颜色**：所有色值来自 `AppThemeColors`；新增语义色 → 同时在 `_colorsOf` 与 `_darkColorsOf` 两套色板补值（5×2 共 10 处）
2. **深色模式**：任何新页面/组件必须在深色变体下可读（文字对比度、卡片层次）；改完切 5 套主题 × 深/浅跑一遍
3. **文案变化**：发布时 `verify_reference` 会报「多/缺」差异——属预期，走白名单合并流程（见 §5），**不要为了消差异去改 baseline 参考 APK**
4. **数据层勿动**：schema v9、统计口径（`hidden=0 AND source='real'` 过滤）、`follow_up_messages` 表、备份校验 1..9——UI 改动不要触碰
5. **安全体系勿动**：`tamper_check.dart`（签名 hash 锁定）、keystore（`keystore/猫卷_*.jks`，**不在 git 中**）、`key_crypto.dart`（v3 加密链）
6. **测试对应**：`widget_test.dart`（主题/闪屏字）、`ai_response_render_test.dart`（渲染器）、`accuracy_kp_test.dart`、`follow_up_test.dart`、`seven_improvements_test.dart`——改 UI 先看这些测试是否要同步

---

## 5. 命令链（每次改动后按顺序执行，全部通过才算完成）

```bash
# 1. 静态检查
flutter analyze                        # 必须 0 issues

# 2. 自动化测试（109 项）
flutter test                           # 必须全部通过

# 3. 发布构建（Release + 混淆 + 符号表）
flutter build apk --release --obfuscate --split-debug-info=build/symbols

# 4. 四维基线校验（组件/权限/文案/资源 对照 reference 原版 APK）
cmd //c "tools\\reference_check\\verify_reference.bat build\\app\\outputs\\flutter-apk\\app-release.apk"
#    → 若 FAIL：/d/dev/flutter/bin/cache/dart-sdk/bin/dart.exe /tmp/merge_whitelist.dart 合并差异后复验 → 直至 >>> PASS

# 5. 签名复验（必须为 43a9e0a1…60fe，保证可覆盖升级）
"D:/dev/Android/Sdk/build-tools/35.0.0/apksigner.bat" verify --print-certs dist/xxx.apk

# 6. 交付（dist/ 用不混淆版本名，如 猫卷_v1.0.2_描述_日期.apk + .sha256）
sha256sum "dist/猫卷_v1.0.2_xxx.apk" | tee "dist/猫卷_v1.0.2_xxx.apk.sha256"
```

环境变量（Git Bash）：`export PATH="/d/dev/flutter/bin:$PATH"`；JDK21 `D:\dev\jdk21`、Android SDK `D:\dev\Android\Sdk`（构建工具 35.0.0）。

---

## 6. 已修复缺陷档案（防止回踩）

| 轮次 | 修复内容 | commit |
|---|---|---|
| UI 扫描 | 12 项：AI 渲染 Markdown、对错语义色、趋势轴、按钮竖排、月历可读性、闪屏融合、主题预览、日志按钮、API 输入框、未答提示、文案等 | `b9e43db` / `4c32adc` |
| 追问聊天 | 聊天气泡 + Markdown 表格渲染 + 按题持久化（schema v9） | `0c077af` |
| 排行 null | 按知识点键名对齐（name/accuracy） | `a3be67d` |

**已知待办**：深色下系统原生选择器未专项验证；管理题库/导入页 UI 未实机走查（设备交互受限，代码与测试覆盖）。

---

## 7. 给 Qoder CN 的起步 Prompt 骨架

```
你是猫卷（Flutter 刷题 App）的 UI 设计师。先读 docs/UI设计系统与开发指南.md 与
docs/功能实现路径.md，再动手。遵守：
1. 颜色一律走 AppThemeColors.of(context)，新语义色须双色板（浅/深 × 5 主题）补齐；
2. 判题对错用 success/danger 语义色（绿/红），不得用 tertiary/error；
3. 改完跑 §5 命令链（analyze/test/build/verify）；
4. 深色模式 5 套都过一遍；文案差异走白名单合并，不改 baseline。
本轮任务：______
```
