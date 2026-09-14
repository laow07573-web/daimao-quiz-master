# 猫卷 UI 设计与开发指南（Mao Des 设计语言）

> 版本：v1.28（2026-09-11）· 目的：给 AI 助手 / 新成员无缝接手 UI 开发
> 配套材料：`docs/功能实现路径.md`（功能链路）、`lib/utils/design_tokens.dart`（令牌定义，权威来源）
> 本轮重设计提交：`010fe43`(B1 基座) `04ae420`(B2 核心页) `a742fe7`(B3 次要页) `8726252`(B4 收口) `8a0ea7d`(B5 推广页)

---

## 1. 项目速览

- **定位**：面向医学生的本地优先开源免费刷题 App（Android + Windows），无账号/无广告/无会员，AI 讲解走 BYOK
- **技术栈**：Flutter 3.24.5 / Dart 3.5.4 · SQLite（schema v11）· Provider · FSRS-5 · DeepSeek API
- **工程规模**：179 项自动化测试全绿 · 发布四维基线校验 · APK 签名锁定防篡改
- **核心不变量**：包名 `com.flashcard.app`、签名证书 SHA-256 `43a9e0a1…60fe`、main 分支

---

## 2. 设计语言「Mao Des」

上一版的问题不是"某处丑"，而是**设计语言缺失**：18 种字号（含 12.5/11.5 半像素）、
卡片圆角 10/12/14/16 混用、组件主题只有 AppBar/Card 两个（其余裸用 Material 默认，
导致胶囊按钮与方角卡片两套语言打架）、全局仅 3 处阴影（页面发平发闷）。
本轮以**令牌层 + 全套组件主题**系统性重建。

### 2.1 设计令牌（唯一取值来源）

**所有** 字号 / 间距 / 圆角 / 阴影 / 动效时长必须引用 `lib/utils/design_tokens.dart`，
页面内不得再写零散字面量。当前令牌化程度：字号与圆角字面量残留 **0** 处，令牌引用 **453** 处。

#### 字阶（7 级，基准 14，无半像素）

| 令牌 | 字号/字重/行高 | 用途 |
|---|---|---|
| `MaoType.display` | 30 / 700 / 1.15 | 大数字（正确率、题量） |
| `MaoType.h1` | 22 / 600 / 1.35 | 页面标题 |
| `MaoType.h2` | 17 / 600 / 1.35 | 区块标题 |
| `MaoType.h3` | 15 / 600 / 1.35 | 卡片标题、列表主文字 |
| `MaoType.body` | 14 / 400 / 1.6 | 正文（主力） |
| `MaoType.caption` | 12 / 400 / 1.5 | 次要说明 |
| `MaoType.micro` | 11 / 500 / 1.4 | 标签、极小文字 |

> 也提供组合样式：`MaoType.h1Style` / `bodyStyle` / `captionStyle` 等，直接 `.copyWith(color:)` 使用。

#### 间距（4pt 栅格）
`MaoSpace.xxs/xs/sm/md/lg/xl/xxl` = **4/8/12/16/20/24/32**
预设：`pagePadding` / `cardPadding`；常量 `page`(16) / `card`(16) / `section`(16) / `item`(12)

#### 圆角
`MaoRadius.chip`(6) 标签 · `small`(10) 小控件 · `control`(14) **按钮与输入框** ·
`card`(18) **卡片** · `large`(24) **弹窗与底部弹层** · `pill`(999) 胶囊
预设 `chipBorder` / `smallBorder` / `controlBorder` / `cardBorder` / `largeBorder`

#### 层次（阴影三级）
`MaoShadow.level1` 卡片（`0 1px 3px @4%`）· `level2` 悬浮/底部栏（`0 4px 14px @7%`）·
`level3` 弹窗（`0 16px 40px @14%`）· `hairline`(1) 描边宽度

#### 动效
`MaoMotion.fast/normal/slow` = 160/240/320ms · `standard`(easeOutCubic) / `emphasized`(easeOutBack)

### 2.2 主题（3 套，替代旧 5 套）

| 主题 | 定位 | accent（浅/深） | 背景（浅/深） |
|---|---|---|---|
| `clear` **清蓝**（默认） | 清爽专业 | `#2563EB` / `#5B9BFF` | `#F5F7FA` / `#0B1220` |
| `sage` **松绿** | 护眼低疲劳 | `#2F7D5B` / `#58BE8E` | `#F6F8F5` / `#0C1310` |
| `ink` **墨黑** | 深色优先 | `#1F6F5C` / `#4ECDC4` | `#FAF8F4` / `#0C0D10` |

- 每套**显式定义 12 个语义色位**（`background/surface/surfaceAlt/border/textPrimary/
  textSecondary/textTertiary/accent/accentSoft/onAccent/navBackground/navForeground`），
  **不再使用 `ColorScheme.fromSeed`** —— 那是旧版"色相过载"的根源（M3 自动生成的
  secondary/tertiary 不受控，单屏可出现 7+ 个竞争色块）。
- **旧存档自动迁移**：老用户的 `brand/eyeCare/minimal/starVoyage/oceanGalaxy`
  映射到新 3 套（`ThemeService._migrateLegacyTheme`），升级不丢主题偏好。
- 旧字段名保留为别名（`navBar`/`card`/`cardBorder`/`successContainer`/`dangerContainer`），
  新代码请用新名（`navBackground`/`surface`/`border`/`successSoft`/`dangerSoft`）。

### 2.3 取色规则（必守）

```dart
final ac = AppThemeColors.of(context);   // 唯一姿势
// ❌ 禁止 Colors.red / Color(0xFF...) / Theme.of(context).colorScheme.xxx
```
`AppThemeColors.of` 已做**安全兜底**：未挂扩展时按当前 `colorScheme` 现算，不会返回 null。

语义色别名（页面常用的 Material 名 → Mao Des 名）：
`cs.onSurface→textPrimary` · `cs.onSurfaceVariant→textSecondary` ·
`cs.surfaceContainerHighest→surfaceAlt` · `cs.primary→accent` · `cs.error→danger` ·
`cs.outlineVariant→border`（迁移脚本：`tools/migrate_colors.py`）

判题对错**必须**用 `success`(绿) / `danger`(红)，不随主题偏移。

### 2.4 组件主题（全套，页面不再裸用默认）

`_buildTheme` 内统一定义：`appBarTheme`（**与页面同色 + 底部 hairline**，不再用深色色块）·
`cardTheme`（18 圆角 + 实色描边）· `filledButtonTheme`/`elevatedButtonTheme`/
`outlinedButtonTheme`/`textButtonTheme`（统一 14 圆角、46 高、三级层次）·
`inputDecorationTheme`（14 圆角 + focus 2px 强调环）· `dialogTheme`（24 圆角）·
`bottomSheetTheme`（顶部 24 圆角 + 拖拽柄）· `snackBarTheme`（浮动 + 14 圆角）·
`navigationBarTheme`/`navigationRailTheme` · `chipTheme` · `listTileTheme` ·
`dividerTheme` · `progressIndicatorTheme` · `iconTheme` · `pageTransitionsTheme`
（统一 `FadeUpwardsPageTransitionsBuilder`，替代默认硬切）

### 2.5 图标规范
常态 outlined / 选中态 filled；尺寸 18（行内）/ 20（按钮）/ 24（导航）。

---

## 3. 关键组件地图

| 区域 | 文件 | 注意点 |
|---|---|---|
| 设计令牌 | `lib/utils/design_tokens.dart` | **唯一取值来源**，改设计先改这里 |
| 主题 | `lib/services/theme_service.dart` | 3 主题 × 深浅、12 色位、全套组件主题 |
| 主壳 | `lib/screens/main_shell.dart` | 底部导航加顶部 hairline；宽屏 NavigationRail |
| 首页 | `lib/screens/home_screen.dart` | Hero 卡用**双色位移渐变**（非透明度衰减，避免发灰） |
| 答题页 | `lib/screens/quiz_screen.dart` | 判题色 = success/danger；底部按钮单行；追问气泡 |
| AI 渲染 | `lib/widgets/ai_response_widget.dart` | 自研渲染器，**勿换回 flutter_markdown** |
| 统计页 | `lib/screens/stats_tab.dart` + `trend_chart.dart` | 轴 `max(20, dataMax*1.15)`；排行键 `name/accuracy` |
| 闪屏 | `lib/screens/splash_screen.dart` | 主题底 + 浅色文字 |
| 推广页 | `promo/index.html` | 矢量重绘界面，须与 App 设计同步 |

---

## 4. 改 UI 的红线

1. **取值走令牌**：字号/间距/圆角/阴影/动效一律引用 `design_tokens.dart`
2. **颜色走语义色**：`AppThemeColors.of(context)`；新增色位须同时在 `_lightOf` 与 `_darkOf` 补齐（3×2 = 6 处）
3. **深色模式**：新页面必须在 3 套主题 × 深/浅共 6 种形态下可读
4. **判题色不动**：success(绿)/danger(红)，不用 M3 的 tertiary/error
5. **文案变化**：会触发 `verify_reference` 文案差异，走白名单合并
   （`REFCHECK_MERGE=1` 强制合并，见 §5），**不要改 baseline 参考 APK**
6. **数据层/安全体系不碰**：schema、统计口径、密钥加密、防篡改、AI 渲染器
7. **测试对应**：`widget_test`（闪屏/首页文案）、`trend_chart_test`（颜色断言）、
   `selection_highlight_test`（像素判据）、`wide_layout/window_adapt`（坐标断言）

---

## 5. 命令链（每次改动后按序执行）

```bash
export PATH="/d/dev/flutter/bin:$PATH"

flutter analyze --no-fatal-infos       # 必须 0 error/0 warning（info 不计）
flutter test                           # 必须 179 项全绿
flutter build apk --release --obfuscate --split-debug-info=build/symbols

# 四维基线校验（组件/权限/文案/资源）
cmd //c "tools\\reference_check\\verify_reference.bat build\\app\\outputs\\flutter-apk\\app-release.apk"
#   FAIL 时：REFCHECK_MERGE=1 cmd //c "...verify_reference.bat <apk>" 强制并入白名单，再复验
#   白名单：reference/known_differences.txt（文案）+ known_manifest_differences.txt（组件权限）

# 签名复验（必须 43a9e0a1…60fe）
"D:/dev/Android/Sdk/build-tools/35.0.0/apksigner.bat" verify --print-certs dist/xxx.apk

sha256sum "dist/猫卷_v1.27.0_xxx_日期.apk" | tee "dist/....sha256"
```

---

## 6. 已修复问题档案（防回踩）

| 轮次 | 内容 | commit |
|---|---|---|
| UI 扫描修复 | 12 项：AI 渲染/语义色/趋势轴/按钮竖排/月历/闪屏/主题预览等 | `b9e43db` `4c32adc` |
| 追问聊天 | 聊天气泡 + Markdown 表格 + 按题持久化（schema v9） | `0c077af` |
| 排行 null | 按知识点键名对齐（name/accuracy） | `a3be67d` |
| **UI 重设计** | **全新设计语言 Mao Des：令牌层 + 3 主题 + 全套组件主题** | **`010fe43`→`8a0ea7d`** |

---

## 7. 给 AI 助手的起步 Prompt

```
你是猫卷（Flutter 刷题 App）的 UI 工程师。先读 lib/utils/design_tokens.dart
与 docs/UI设计系统与开发指南.md，再动手。铁律：
1. 字号/间距/圆角/阴影/动效一律引用 MaoType/MaoSpace/MaoRadius/MaoShadow/MaoMotion，
   不写任何字面量；
2. 颜色一律 AppThemeColors.of(context)，新色位须补齐浅/深两套；
3. 判题对错用 success/danger（绿/红），不用 tertiary/error；
4. 改完跑 §5 命令链（analyze/test/build/verify），3 套主题 × 深浅共 6 形态都过一遍；
5. 文案差异走 REFCHECK_MERGE 白名单合并，不改 baseline。

本轮任务：______
```
