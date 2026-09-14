import 'package:flutter/material.dart';

import '../services/theme_service.dart';
import '../utils/design_tokens.dart';
import '../utils/responsive.dart';
import '../widgets/kit/mj_kit.dart';
import 'settings_screen.dart';

/// 设置中心（Mao Des 2.0）
///
/// 信息架构改造：原来「设置」是一条 2000 行的长滚动列表，现在拆成
/// 「中心页 → 分组子页」两级结构——分组入口在这里，各组内容在
/// [SettingsScreen]（按 [SettingsGroup] 过滤后只渲染该组）。
class SettingsHubScreen extends StatelessWidget {
  const SettingsHubScreen({super.key});

  static const _groups = <(SettingsGroup, IconData)>[
    (SettingsGroup.ai, Icons.auto_awesome_outlined),
    (SettingsGroup.appearance, Icons.palette_outlined),
    (SettingsGroup.sync, Icons.sync_outlined),
    (SettingsGroup.advanced, Icons.tune_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    return Scaffold(
      backgroundColor: ac.background,
      appBar: AppBar(title: const Text('设置')),
      body: ResponsivePage(
        child: ListView(
          padding: const EdgeInsets.all(MaoSpace.md),
          children: [
            const MJSectionHeader(title: '分组'),
            const SizedBox(height: MaoSpace.sm),
            for (final (group, icon) in _groups) ...[
              MJSurface(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => SettingsScreen(group: group)),
                ),
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
                        border:
                            Border.all(color: ac.border, width: MaoLine.width),
                      ),
                      child: Icon(icon, size: 16, color: ac.accent),
                    ),
                    const SizedBox(width: MaoSpace.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(group.label,
                              style: MaoType.h3Style.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: ac.textPrimary)),
                          const SizedBox(height: 1),
                          Text(group.subtitle,
                              style: MaoType.captionStyle
                                  .copyWith(color: ac.textSecondary)),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        size: 16, color: ac.textTertiary),
                  ],
                ),
              ),
              const SizedBox(height: MaoSpace.xs),
            ],
            const SizedBox(height: MaoSpace.md),
            // 全部设置（保留一次性浏览全部项的能力）
            MJSurface(
              tone: MJTone.alt,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        const SettingsScreen(group: SettingsGroup.all)),
              ),
              padding: const EdgeInsets.symmetric(
                  horizontal: MaoSpace.sm, vertical: MaoSpace.sm),
              child: Row(
                children: [
                  Icon(Icons.list_alt_outlined,
                      size: 16, color: ac.textSecondary),
                  const SizedBox(width: MaoSpace.sm),
                  Expanded(
                    child: Text('全部设置',
                        style: MaoType.h3Style.copyWith(
                            color: ac.textSecondary)),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      size: 16, color: ac.textTertiary),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
