import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../services/theme_service.dart';
import '../utils/app_constants.dart';
import '../utils/design_tokens.dart';
import '../utils/format_utils.dart';
import '../utils/responsive.dart';
import '../widgets/kit/mj_kit.dart';
import '../widgets/kit/mj_logo.dart';
import 'developer_options_screen.dart';
import 'settings_hub_screen.dart';

/// 我的页（Mao Des 2.0 · 精密暗色）
///
/// 问候卡（平坦面板 + 左侧强调条）+ 入口列表 + 产品定位卡。
/// 与首页语言一致：层级靠发丝描边与明度差，不用大色块与阴影。
class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  // v1.0.2 设计审查修复：问候语逻辑收敛到 format_utils.greetingNow
  String get _greeting => greetingNow();

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    final nickname = context.watch<AppState>().settings.nickname;
    // v1.0.3 宽屏重设计：入口卡片提取为列表，窄屏纵列 / 宽屏三列并排
    final entries = [
      _EntryTile(
        icon: Icons.settings_outlined,
        title: '设置',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SettingsHubScreen()),
        ),
      ),
      _EntryTile(
        icon: Icons.developer_mode,
        title: '开发者选项',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DeveloperOptionsScreen()),
        ),
      ),
      _EntryTile(
        icon: Icons.info_outline,
        title: '关于',
        // v1.0.2 修复：版本号统一（常量 kAppVersion）
        subtitle: kAppVersion,
        onTap: () => _showAbout(context),
      ),
    ];

    return Scaffold(
      backgroundColor: ac.background,
      appBar: AppBar(title: const Text('我的')),
      // 平板适配：内容限宽居中（手机无影响）；宽屏限宽自动提升至 1080
      body: ResponsivePage(
        child: ListView(
          padding: const EdgeInsets.all(MaoSpace.md),
          children: [
            // ── 问候卡：平坦面板 + 左侧强调条 + 单色 logo 方块 ──
            MJSurface(
              accentEdge: true,
              padding: const EdgeInsets.all(MaoSpace.md),
              child: Row(
                children: [
                  // 品牌位：矢量标记（与首页/启动页同一组件，三处形状与描边一致）
                  const MJLogoBadge(box: 38),
                  const SizedBox(width: MaoSpace.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_greeting,
                            style:
                                MaoType.h1Style.copyWith(color: ac.textPrimary)),
                        const SizedBox(height: MaoSpace.xxs),
                        Text(
                          // v1.0.2 对齐里程碑：昵称（设置后首页显示专属问候）
                          nickname.isEmpty ? '猫卷' : nickname,
                          style: MaoType.captionStyle
                              .copyWith(color: ac.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: MaoSpace.sm),
            // ── 入口列表：宽屏三列并排，窄屏纵列 ──
            if (isWideLayout(context))
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: entries[0]),
                  const SizedBox(width: MaoSpace.xs),
                  Expanded(child: entries[1]),
                  const SizedBox(width: MaoSpace.xs),
                  Expanded(child: entries[2]),
                ],
              )
            else ...[
              entries[0],
              const SizedBox(height: MaoSpace.xs),
              entries[1],
              const SizedBox(height: MaoSpace.xs),
              entries[2],
            ],
            const SizedBox(height: MaoSpace.lg),
            // ── 产品定位卡（消除下半屏空白） ──
            MJSurface(
              tone: MJTone.alt,
              padding: const EdgeInsets.all(MaoSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('猫卷 · 医学备考刷题平台',
                      style: MaoType.h3Style.copyWith(
                          fontWeight: FontWeight.w600,
                          color: ac.textPrimary)),
                  const SizedBox(height: MaoSpace.xs),
                  Text(
                    '开源免费，无广告无会员\n题库与记录本地存储，数据自有\nAI 讲解由你的 API Key 直连，隐私无忧\n许可：AGPL-3.0（可自由使用 / 修改 / 分发）',
                    style: MaoType.captionStyle
                        .copyWith(height: 1.75, color: ac.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: MaoSpace.lg),
            Center(
              child: Text(
                // v1.0.2 对齐里程碑：页脚带版本号
                '本软件由b站：笨蛋鱼坏蛋猫开发|$kAppVersion',
                style: MaoType.microStyle.copyWith(color: ac.textTertiary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAbout(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('猫卷'),
        content: Text(
          // v1.0.2 定位：医学生备考（未来拓展通用场景）
          '医学备考刷题工具\n支持本地题库、AI 解析、FSRS 间隔复习、数据统计。\n\n版本：$kAppVersion',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('好的'),
          ),
        ],
      ),
    );
  }
}

/// 入口行：单色描边小图标 + 标题（+ 尾部版本号）+ 细箭头。
class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    return MJSurface(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
          horizontal: MaoSpace.sm, vertical: MaoSpace.sm),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: ac.surfaceAlt,
              borderRadius: MaoRadius.smallBorder,
              border: Border.all(color: ac.border, width: MaoLine.width),
            ),
            child: Icon(icon, size: 16, color: ac.accent),
          ),
          const SizedBox(width: MaoSpace.sm),
          Expanded(
            child: Text(title,
                style: MaoType.h3Style.copyWith(
                    fontWeight: FontWeight.w600, color: ac.textPrimary)),
          ),
          if (subtitle != null)
            Text(subtitle!,
                style: MaoType.captionStyle.copyWith(color: ac.textTertiary)),
          const SizedBox(width: MaoSpace.xxs),
          Icon(Icons.chevron_right_rounded,
              size: 16, color: ac.textTertiary),
        ],
      ),
    );
  }
}
