# 贡献指南

感谢你对猫卷的关注！在提交贡献之前，请先阅读以下约定。

## 报告问题

- 使用仓库的 **Issues** 报告 Bug 或提出建议
- 报告前请先搜索是否已有相同问题
- Bug 报告请附上：平台（Android / Windows）、版本号、复现步骤、期望行为与实际行为
- **安全漏洞请勿公开提交**，见 [SECURITY.md](SECURITY.md)

## 提交代码

1. Fork 本仓库并基于 `main` 创建分支：
   - `feat/xxx` — 新功能
   - `fix/xxx` — 修复
   - `docs/xxx` — 文档
   - `chore/xxx` — 构建 / 杂项
2. 提交信息建议使用语义化前缀：
   - `feat: 新增 xxx`
   - `fix: 修复 xxx`
   - `docs: 更新 xxx`
   - `chore: 调整构建脚本`
3. 提交前请确保本地全部通过：
   ```bash
   flutter analyze --no-fatal-infos   # 应输出 0 error / 0 warning（info 级提示不计）
   flutter test      # 全部测试通过（当前 244 项）
   ```
4. 发起 Pull Request，描述清楚「改了什么、为什么改、怎么验证」

> 推送后 GitHub Actions 会自动再跑一遍 `analyze` + `test`，见 PR 上的 CI 状态。

## 开发约定

- 代码风格以 `analysis_options.yaml` 为准
- 新增功能请补充对应测试；修复类提交建议补充回归测试
- 数据库 schema 变更需提供迁移逻辑，并确保覆盖安装不丢数据
- **版本号只改一处**：`pubspec.yaml` 的 `version:` 字段。
  应用内展示的版本号由构建时 `--dart-define=APP_VERSION` 注入，
  README 徽章是动态的，推广页版本号由发布脚本同步——
  不需要（也不应该）在任何其他文件里手工改版本号。
  两者不一致时 `test/version_single_source_test.dart` 会直接报错
- **签名文件与密钥永不入库**：`android/key.properties`、`**/*.jks`、`**/*.keystore`
  已在 `.gitignore` 排除，请勿私自加回

## 许可

向本项目提交贡献即表示你同意你的贡献以本项目的 [AGPL-3.0](LICENSE) 许可协议发布。

简单说：你可以自由使用、修改、分发（包括商业用途），但**修改后的衍生作品必须
同样以 AGPL-3.0 开源**；若把修改版作为网络服务提供，须向使用者提供完整源码。
