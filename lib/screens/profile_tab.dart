import '../utils/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../services/theme_service.dart';
import '../utils/app_constants.dart';
import '../utils/format_utils.dart';
import '../utils/responsive.dart';
import 'developer_options_screen.dart';
import 'settings_screen.dart';

/// 我的页（v1.0.2 对齐里程碑）：问候语（昵称）、入口
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
    // v1.0.3 宽屏重设计：入口卡片提取为列表，窄屏纵列 / 宽屏三列并排
    final entries = [
      _EntryTile(
        icon: Icons.settings_outlined,
        title: '设置',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        ),
      ),
      _EntryTile(
        icon: Icons.developer_mode,
        title: '开发者选项',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => const DeveloperOptionsScreen()),
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
      appBar: AppBar(title: const Text('我的')),
      // 平板适配：内容限宽居中（手机无影响）；宽屏限宽自动提升至 1080
      body: ResponsivePage(
        child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          // 问候语 + 名字
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [ac.accent, ac.accent.withOpacity(0.7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(MaoRadius.card),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(MaoRadius.control),
                      child: Image.asset(
                        'assets/app_logo.png',
                        width: 44,
                        height: 44,
                        errorBuilder: (_, __, ___) => Icon(
                            Icons.school, size: 36, color: ac.onAccent),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _greeting,
                            style: TextStyle(
                              fontSize: MaoType.h1,
                              fontWeight: FontWeight.w600,
                              color: ac.onAccent,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            // v1.0.2 对齐里程碑：昵称（设置后首页显示专属问候）
                            context.watch<AppState>().settings.nickname.isEmpty
                                ? '猫卷'
                                : context.read<AppState>().settings.nickname,
                            style: TextStyle(
                              fontSize: MaoType.body,
                              color: ac.onAccent.withOpacity(0.85),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // 入口列表：宽屏三列并排，窄屏纵列（原设计）
          if (isWideLayout(context))
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: entries[0]),
                const SizedBox(width: 8),
                Expanded(child: entries[1]),
                const SizedBox(width: 8),
                Expanded(child: entries[2]),
              ],
            )
          else ...[
            entries[0],
            const SizedBox(height: 8),
            entries[1],
            const SizedBox(height: 8),
            entries[2],
          ],
          const SizedBox(height: 20),
          // v1.0.2 UI 审查修复：入口下方补产品定位卡，消除下半屏空白
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: ac.surfaceAlt,
              borderRadius: BorderRadius.circular(MaoRadius.control),
              border: Border.all(color: ac.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('猫卷 · 医学备考刷题平台',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: MaoType.body,
                        color: ac.textPrimary)),
                const SizedBox(height: 6),
                Text(
                  '开源免费，无广告无会员\n题库与记录本地存储，数据自有\nAI 讲解由你的 API Key 直连，隐私无忧\n许可：AGPL-3.0（可自由使用 / 修改 / 分发）',
                  style: TextStyle(
                      fontSize: MaoType.body,
                      height: 1.7,
                      color: ac.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Text(
              // v1.0.2 对齐里程碑：页脚带版本号
              '本软件由b站：笨蛋鱼坏蛋猫开发|$kAppVersion',
              style: TextStyle(fontSize: MaoType.caption, color: ac.textSecondary),
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
    return InkWell(
      borderRadius: BorderRadius.circular(MaoRadius.control),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: ac.surfaceAlt.withOpacity(0.5),
          borderRadius: BorderRadius.circular(MaoRadius.control),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: ac.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(fontSize: MaoType.body, color: ac.textPrimary),
              ),
            ),
            if (subtitle != null)
              Text(subtitle!,
                  style:
                      TextStyle(fontSize: MaoType.body, color: ac.textSecondary)),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 18, color: ac.textSecondary),
          ],
        ),
      ),
    );
  }
}
