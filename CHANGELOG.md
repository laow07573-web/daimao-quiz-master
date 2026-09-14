# 更新日志

本文件记录猫卷的所有重要变更。

格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循[语义化版本](https://semver.org/lang/zh-CN/)。

分类约定：`新增` / `改进` / `修复` / `安全` / `移除` / `升级说明`

> 版本号的唯一来源是 `pubspec.yaml` 的 `version:` 字段。
> 本文件按版本倒序记录，每个正式版的条目与 GitHub Release 说明保持一致。

---

## [Unreleased]

### 新增
- 持续集成：每次推送到 `main` 自动执行静态分析与全量测试（`.github/workflows/ci.yml`）
- 自动发版流水线：推送 `v*` tag 即产出 Android（arm64 / 通用）与 Windows
  （安装版 / 便携版）四个产物并自动创建 Release（`.github/workflows/release.yml`）
- 贡献指南、安全政策、依赖自动更新配置、Issue / PR 模板

### 改进
- 许可证更换为 **GNU AGPL-3.0**：原 CC BY-NC-SA 4.0 是内容协议（缺专利授权条款、
  且含非商业限制），不适用于软件，也与「开源」表述不符
- 版本号改为单一来源（`pubspec.yaml`）：应用内版本号由构建时注入，
  README 版本徽章改为动态徽章，推广页版本号随发版自动同步；
  新增测试 `test/version_single_source_test.dart` 防止版本号漂移
- 修复 Windows 安装包脚本的缺陷：`maojuan_setup.iss` 的源目录曾写死为某个
  带日期的目录且发布脚本从不更新它，存在打包旧内容的风险；现改为由发布脚本传入
- 安装包随附 `LICENSE.txt`（AGPL 要求随二进制分发协议文本）
- README 下载表不再写死版本号，统一指向 Releases 最新版

### 安全
- 移除文档中记录的签名证书口令（改为离线保管说明），并从历史提交中清除
- 备份导出默认不再包含 API Key；如需包含则须设置备份口令并对备份文件整体加密
  （详见下文「安全」小节与 README 的数据与隐私说明）

### 计划中
- iOS 版本评估
- Web 体验版（无需安装即可试用）
- 题库分享生态（仅限用户自制题库）
- 代码签名证书（消除 Windows SmartScreen 提示）

---

## [1.28.1] - 2026-09-12

### 新增
- 无 API Key 时显示题目自带示例解析
- 首页新生引导卡：一键导入题库并直接选库
- 统计页空状态文案

### 改进
- 无 Key 拦截提示可一键直达设置页
- 面向新生推广场景的交互优化

---

## [1.28.0] - 2026-09-11

### 新增
- 全新设计语言：字号 / 间距 / 圆角 / 阴影全部令牌化
- 3 套主题（清蓝 / 松绿 / 墨黑）× 深浅两版 = 6 套配色，支持跟随系统
- AI 回答篇幅三档：简洁（≤150 字）/ 标准（≤300 字）/ 详细
- 关键词彩色标记：答案绿、题眼蓝、避坑红
- 追问改为独立全屏对话页，问答按题保存
- 兼容任意 OpenAI 兼容接口，支持第三方订阅
- 设置页一键测试连接、拉取模型列表
- 数据可视化：年度坚持贡献图（53 周 × 7 天）
- 近一年趋势：题量柱状 + 正确率曲线双轴对照

### 修复
- APK versionName 误标为 1.27.0 的问题（现修正为 1.28.0，versionCode 19）

### 升级说明
- 覆盖安装不丢数据

---

## [1.26.6.24] - 2026-06-24

### 新增
- 练习模式：限时 / 不限时，答题卡漫游，统一提交批改
- 背题模式：高亮正确选项，不计统计，顺序浏览
- 五套主题切换
- 左右滑动切换题目
- 刷题数量自定义 + 全部刷题

### 安全
- API Key 加密存储
- APK 签名校验
- 代码混淆

---

## [1.0] - 2026-06-14

### 新增
- 首个版本发布（呆猫刷题宝）
- DOCX 题库导入 + AI 自动解析
- AI 解析 + AI 追问
- 薄弱分析 + 刷题小结
- 错题本 + 错题重刷
- Windows + Android 双端支持

[Unreleased]: https://github.com/laow07573-web/daimao-quiz-master/compare/v1.28.1...HEAD
[1.28.1]: https://github.com/laow07573-web/daimao-quiz-master/compare/v1.28.0...v1.28.1
[1.28.0]: https://github.com/laow07573-web/daimao-quiz-master/compare/v1.26.6.24...v1.28.0
[1.26.6.24]: https://github.com/laow07573-web/daimao-quiz-master/compare/v1.0...v1.26.6.24
[1.0]: https://github.com/laow07573-web/daimao-quiz-master/releases/tag/v1.0
