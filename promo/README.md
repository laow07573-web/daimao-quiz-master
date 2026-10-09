# 猫卷官网

官网发布源为本目录，而不是历史设计目录 `site/` 或 `site-tech/`。新页面不使用吉祥物，以「做题有数，学习有度」为主题，沿用猫耳试卷 Logo。

## 本地查看

直接用浏览器打开 `index.html`。页面为静态 HTML，基础样式和交互内联，动画独立于 `assets/motion.css` 和 `assets/motion.js`，Logo 使用 `assets/brand.svg`，没有构建步骤或外部运行依赖。FAQ、下载链接及主要内容在禁用 JavaScript 时仍可使用。

## 信息原则

- 依据项目 README、页面和服务实现介绍功能，不展示虚构用户量、提分数据或模拟战绩。
- 本轮改为双栏动态首屏：文档扫描、题卡生成、三阶段进度循环；支持暂停全部自动演示。三种模式自动切换说明，手动选择时停止自动播放；AI 四步讲解轮流强调；内容滚动入场、产品截图切换淡入。尊重系统减弱动态效果设置。保留深色界面浏览区与明亮功能叙事。界面素材来自 `site/assets/shots/`，复制到本目录 `assets/shots/`，注明数据仅作展示、版本可能不同；AI 卡片是功能示意，不是在线 AI 服务。
- 界面浏览按钮支持键盘切换开始页、错题本与统计页，手机菜单支持 Escape 关闭。
- 核心刷题与本地统计不需要 AI Key；AI 解析和文档解析需要用户配置兼容接口，可能产生服务商费用。
- AI 请求会发给用户配置的服务商，不承诺所有数据绝不离开设备。
- 不承诺记忆率、考试结果或永久记住；不将待发布功能当作已发布功能。
- 下载按钮统一前往 GitHub Releases，用户按平台选择安装包，实际版本及功能以发布说明为准。

## 发布兼容

保留 `window.MAOJUAN` 配置块，供 `tools/publish_release.ps1` 同步版本与产物信息。可见下载入口不依赖配置内旧的本地安装包路径。`tools/deploy_pages.ps1` 现复制整个 `assets/` 目录，避免遗漏品牌 SVG。

GitHub Pages 与 Cloudflare 的发布工具分别为 `tools/deploy_pages.ps1`、`tools/deploy_promo.ps1`。这些工具涉及发布；仅改网页或本地预览时不要运行。此次官网重做本身不推送、不部署、不改变 main 分支。

开发者：笨蛋鱼坏蛋猫。
官网：https://laow07573-web.github.io/daimao-quiz-master/
