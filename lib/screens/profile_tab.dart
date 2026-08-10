import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import 'developer_options_screen.dart';
import 'settings_screen.dart';

/// 我的页（v1.0.2 对齐里程碑）：问候语（昵称）、入口
class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 5) return '夜深了，注意休息…';
    if (h < 9) return '早上好！';
    if (h < 12) return '上午好！';
    if (h < 14) return '中午好！';
    if (h < 18) return '下午好！';
    if (h < 23) return '晚上好！';
    return '夜深了，注意休息…';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          // 问候语 + 名字
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [cs.primary, cs.primary.withOpacity(0.7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.asset(
                        'assets/app_logo.png',
                        width: 44,
                        height: 44,
                        errorBuilder: (_, __, ___) => Icon(
                            Icons.school, size: 36, color: cs.onPrimary),
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
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: cs.onPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            // v1.0.2 对齐里程碑：昵称（设置后首页显示专属问候）
                            context.watch<AppState>().settings.nickname.isEmpty
                                ? '呆猫刷题宝'
                                : context.read<AppState>().settings.nickname,
                            style: TextStyle(
                              fontSize: 14,
                              color: cs.onPrimary.withOpacity(0.85),
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
          // 入口列表
          _EntryTile(
            icon: Icons.settings_outlined,
            title: '设置',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          const SizedBox(height: 8),
          _EntryTile(
            icon: Icons.developer_mode,
            title: '开发者选项',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const DeveloperOptionsScreen()),
            ),
          ),
          const SizedBox(height: 8),
          _EntryTile(
            icon: Icons.info_outline,
            title: '关于',
            subtitle: 'v1.0.2',
            onTap: () => _showAbout(context),
          ),
          const SizedBox(height: 20),
          Center(
            child: Text(
              // v1.0.2 对齐里程碑：页脚带版本号
              '本软件由b站：笨蛋鱼坏蛋猫开发|v1.26.6.17',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  void _showAbout(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('呆猫刷题宝'),
        content: const Text(
          '医学检验考试刷题工具\n支持本地题库、AI 解析、FSRS 间隔复习、数据统计。\n\n版本：1.26.6 (build 17)',
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
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withOpacity(0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: cs.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(fontSize: 14, color: cs.onSurface),
              ),
            ),
            if (subtitle != null)
              Text(subtitle!,
                  style:
                      TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 18, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
