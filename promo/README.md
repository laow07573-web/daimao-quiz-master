# 猫卷 · 功能展示页

面向推广的静态展示页。**界面全部由代码矢量绘制（HTML/CSS/JS），不是截图**，因此任意缩放
清晰、永不裁切，也能做出真实动效。

## 页面结构

| 区块 | 内容 |
|---|---|
| Hero | 主标题 + 功能标签 + 数据指标 + 手机模型（4 个界面轮播） |
| 为什么做猫卷 | 备考工具的三个痛点 |
| 功能 01–13 | 每个功能区左侧讲功能，右侧是**代码绘制的界面动画** |
| 工程质量 | 8 个数据指标 |
| **开发历程** | 提交活跃图（真实 git 数据）+ 六轮迭代时间线动画 |
| **使用说明** | 8 步自动演示，逐步切换代码绘制的界面 |
| 下载 | Android / Windows / GitHub 仓库入口 |

> 本页刻意**不讲「怎么做到的」**（没有技术栈或实现原理），只把功能用界面动画演示出来。

## 代码绘制的界面

11 个界面模板（`<template id="tpl-*">`）加上若干场景示意：

| 模板 | 界面 |
|---|---|
| `tpl-home` | 首页（问候卡，累计数据并入卡内 + 本周战绩） |
| `tpl-start` | 开始页（三档模式入口，Mao Des 2.0 新增的第四个 Tab） |
| `tpl-quiz` | 答题页（作答判定：正确绿 / 错误红） |
| `tpl-ai` | AI 解析（结构色：答案绿 / 题眼蓝 / 避坑红底 / 记忆蓝底，关键词 `==蓝==`/`!!红!!`） |
| `tpl-stats` | 统计页（含 GitHub 贡献图样式的年度热力图 + 趋势 SVG） |
| `tpl-errbook` | 错题本（FSRS 到期排期 + 薄弱知识点 + 题库卡） |
| `tpl-ai-sample` | AI 解析示例（题眼破题法四步） |
| `tpl-import` | 导入题库（解析进度） |
| `tpl-home-dark` | 深色首页 |
| `tpl-banks` | 题库管理（多库勾选） |
| `tpl-annot` | 手写批注（叠加实时笔迹动画） |

另有场景示意动画：宽屏双栏布局（`.wmock`）、局域网同步（`.sync-schem` 数据包往返）、
加密与数据主权（盾牌光晕）。年度热力图与趋势图由 JS 从 `data-*` 属性实时生成。

## 开发历程（真实数据）

项目 2026-06-15 动工、跨三个阶段（原「呆猫刷题宝」→ v1.0.x 打磨封存 → 接手重建为「猫卷」）：

| 阶段 | 时间 | 内容 |
|---|---|---|
| 第一阶段 | 2026-06-15 → 06-25 | 初版 v1.0 → v1.26.6.17（三模式）→ v1.26.6.24（练习模式/五套主题/安全加固） |
| 第二阶段 | 2026-08-07 → 08-09 | v1.0.0 → v1.0.2（42 项 UI 修复、统计页重构、AES-256-GCM），开发包封存 |
| 第三阶段 | 2026-08-10 → 09-11 | 环境重建、七项改进、更名猫卷、批注/同步/宽屏、全新 UI 与 AI 能力扩展 |

页面上的可视化：
- **三阶段总览卡**：三张卡片概括上面三个阶段
- **提交活跃度图**：仅统计第三阶段（有 git 记录的 7 个工作日、共 61 次提交）
- **九个里程碑时间线**：逐条点亮，每条带「阶段」标签

数据硬编码在 `index.html` 的 `COMMITS` / `ROUNDS` 两个数组里，更新历程时改这两处即可。

## 打开与部署

- **直接双击 `index.html`** 即可（纯静态、无构建、无外部依赖）
- 本地服务器预览：`cd promo && python -m http.server 8899`
- **正式部署**：见 [docs/部署与分发指南.md](../docs/部署与分发指南.md)
  ```powershell
  # 一键暂存 + 上传到 Cloudflare Pages
  powershell -ExecutionPolicy Bypass -File tools\deploy_promo.ps1
  ```

### 下载地址配置

所有下载链接、版本号、校验值都集中在 `index.html` `<head>` 里的 `window.MAOJUAN` 块：

```js
window.MAOJUAN = {
  version:         "1.28.1",                    // 与 pubspec.yaml 一致
  android:          "download/MaoJuan-v1.28.1-android-arm64.apk",     // 同源直链
  androidUniversal: "download/MaoJuan-v1.28.1-android-universal.apk", // 同源直链
  windowsSetup:     "download/MaoJuan-v1.28.1-windows-setup.exe",     // 同源直链
  windowsPortable:  "download/MaoJuan-v1.28.1-windows-portable.zip",  // 同源直链
  githubRelease:    "https://github.com/.../releases/latest",         // 备用
  repo:             "https://github.com/laow07573-web/daimao-quiz-master",
  sha256: { apk: "...", apkUniv: "...", setup: "...", portable: "..." }
};
```

> **发版时不需要手工改这个块**：`tools/publish_release.ps1` 的第 6.5 步会按本次
> 产物就地同步 `version` / `buildDate` / 四个同源下载文件名 / 四个 sha256，
> 所以版本号不可能与产物脱节。手工改只在需要调整链接形式时才有必要。

- HTML 里的 `href` 已预置 GitHub Releases 兜底，**JS 出错也能正常下载**（渐进增强）
- `promo/download/` 里的 Windows 包由 `tools/deploy_promo.ps1` 从 `dist/` 自动拷入并改名成 ASCII
  （Cloudflare 会剥掉非 ASCII 文件名，中文包名会变成 `-Setup-....exe`）
- 页面结构：主渠道 3 个按钮（APK / Windows 安装包 / 绿色版）+ 备用下载行 + 折叠的 SHA-256 校验值

### 关于 25MB 限制

Cloudflare Pages 单文件上限 25 MiB。Windows 两个包（20.7 / 23.5 MB）可以放，APK 34.7 MB 不行，
所以 APK 走国内网盘。`deploy_promo.ps1` 会在上传前检查并明确报错，不会静默传半截。


## 动画说明

- **界面轮播**：Hero 与「三种模式」区块自动切换，并触发界面内部动效
- **内容滚动浏览**：首页/统计页界面缓慢上下平移，展示画框之外的更多内容
- **AI 解析打字机**：逐字打出 + 结构标签整行着色 + 关键词彩色
- **追问气泡**：依次淡入上浮
- **批注笔迹**：红色推导笔迹 + 紫色荧光笔描边动画
- **开发历程**：提交柱状图按高度生长；时间线逐条点亮、竖线同步推进
- **使用说明**：8 步自动演示，可暂停 / 继续 / 重播 / 点步骤跳转
- 全部动画尊重 `prefers-reduced-motion`

## 响应式

已在 390 / 768 / 1024 / 1280 / 1440 px 宽度验证：无横向溢出、无元素越界、无 JS 错误。
