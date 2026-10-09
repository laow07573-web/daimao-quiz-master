import '../utils/design_tokens.dart';
import '../services/theme_service.dart';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../services/debug_log_service.dart';
import '../services/keepalive_service.dart';
import '../utils/responsive.dart';

/// 开发者选项（v1.0.2）：密码进入，调试专用
/// 日志 / 模拟长期使用 / 保活状态
/// （数据库备份导入导出已迁至 设置 → 同步与提醒 → 数据库备份）
class DeveloperOptionsScreen extends StatefulWidget {
  const DeveloperOptionsScreen({super.key});

  @override
  State<DeveloperOptionsScreen> createState() => _DeveloperOptionsScreenState();
}

class _DeveloperOptionsScreenState extends State<DeveloperOptionsScreen> {
  // v1.0.2 设计审查修复：不再明文存密码/写注释，改 SHA-256 哈希比对
  static const _passwordHash =
      '4e350f267cd76d000e9d0f99691683ebd989182a1b8266c02bc3739ef2fa1211';

  static bool _checkPassword(String input) =>
      sha256.convert(utf8.encode(input)).toString() == _passwordHash;

  bool _unlocked = false;
  bool _simulating = false;
  bool _batteryIgnored = true;
  String? _status;
  // v1.0.2 修复：密码输入 controller 由 State 管理，避免每次 build 新建泄漏
  final TextEditingController _lockController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkKeepalive();
  }

  @override
  void dispose() {
    _lockController.dispose();
    super.dispose();
  }

  Future<void> _checkKeepalive() async {
    // v1.0.2 设计审查修复（简化保活）：不再查询无障碍状态
    final bat =
        await KeepAliveService.instance.isIgnoringBatteryOptimizations();
    if (!mounted) return;
    setState(() {
      _batteryIgnored = bat;
    });
  }

  /// v1.0.2 对齐里程碑：模拟对话框（基于当前题库 / 确认到期 / 说明）
  /// v1.0.2：清除模拟数据（确认后执行，只清理模拟产生的数据）
  Future<void> _clearSimulated() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除模拟数据'),
        content:
            const Text('将删除全部模拟生成的刷题记录、复习卡与错题条目，且不可恢复。\n\n你的真实刷题数据不受影响。确定清除？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: AppThemeColors.of(ctx).danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    final removed = await context.read<AppState>().clearSimulatedData();
    if (!mounted) return;
    setState(() {
      _status = '已清除 $removed 条模拟会话数据';
    });
  }

  Future<void> _simulate() async {
    var days = 90;
    var randomWeakKp = false;
    var dueToday = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('模拟长期使用'),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('基于当前题库生成过去若干天的使用数据：',
                    style: TextStyle(
                        fontSize: MaoType.body,
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                Text('使用 FSRS 算法全权生成，用于测试每日提醒、连击、首页战绩。',
                    style: TextStyle(
                        fontSize: MaoType.body,
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                const SizedBox(height: 12),
                Text('生成天数：$days 天',
                    style: const TextStyle(fontSize: MaoType.body)),
                Slider(
                  value: days.toDouble(),
                  min: 30,
                  max: 180,
                  divisions: 15,
                  label: '$days 天',
                  onChanged: (v) => setDialogState(() => days = v.round()),
                ),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('随机 1~2 个知识点作为薄弱点',
                      style: TextStyle(fontSize: MaoType.body)),
                  value: randomWeakKp,
                  onChanged: (v) =>
                      setDialogState(() => randomWeakKp = v ?? false),
                ),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('把所有复习卡设为今天到期，便于测试错题复习',
                      style: TextStyle(fontSize: MaoType.body)),
                  value: dueToday,
                  onChanged: (v) => setDialogState(() => dueToday = v ?? false),
                ),
                const SizedBox(height: 4),
                Text('· 答错的题自动进错题本并建复习卡',
                    style: TextStyle(
                        fontSize: MaoType.body,
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                Text('· 重复执行会先清理上次模拟的数据，可放心多试。',
                    style: TextStyle(
                        fontSize: MaoType.body,
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                if (dueToday)
                  Text('· 错题本的「待复习」数量会全部增加。',
                      style: TextStyle(
                          fontSize: MaoType.body,
                          color: Theme.of(ctx).colorScheme.error)),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () async {
                  // 对齐里程碑：设为今天到期前二次确认
                  // 先取 Navigator（同步），避免 await 之后再用 ctx 触发跨异步告警
                  final rootNav = Navigator.of(ctx);
                  if (dueToday) {
                    final sure = await showDialog<bool>(
                      context: ctx,
                      builder: (c2) => AlertDialog(
                        title: const Text('确认操作'),
                        content:
                            const Text('确定把所有复习卡设为今天到期吗？\n错题本的「待复习」数量会全部增加。'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(c2, false),
                              child: const Text('取消')),
                          FilledButton(
                              onPressed: () => Navigator.pop(c2, true),
                              child: const Text('确定')),
                        ],
                      ),
                    );
                    if (sure != true) return;
                  }
                  rootNav.pop(true);
                },
                child: const Text('开始模拟')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _simulating = true);
    final result = await context.read<AppState>().simulateLongTermUse(
        days: days, randomWeakKp: randomWeakKp, dueToday: dueToday);
    if (!mounted) return;
    setState(() {
      _simulating = false;
      _status = result.error ??
          (dueToday
              ? '已将 ${result.cards} 张复习卡设为到期'
              : '已生成 ${result.records} 条记录，复习卡 ${result.cards} 张');
    });
  }

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    return Scaffold(
      // v1.0.2 对齐里程碑：开发者模式（已开启）
      appBar: AppBar(
        title: Text(_unlocked ? '开发者模式（已开启）' : '开发者模式'),
        actions: [
          if (_unlocked)
            TextButton(
              onPressed: () => setState(() => _unlocked = false),
              child: const Text('退出开发者模式'),
            ),
        ],
      ),
      // 平板适配：内容限宽居中（手机无影响）
      body: ResponsivePage(
        child: !_unlocked ? _buildLock(ac) : _buildPanel(ac),
      ),
    );
  }

  Widget _buildLock(AppThemeColors ac) {
    final ac = AppThemeColors.of(context);
    final controller = _lockController;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 56, color: ac.accent),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              obscureText: true,
              decoration: InputDecoration(
                // v1.0.2 对齐里程碑：输入密码开启，调试专用
                labelText: '输入密码开启，调试专用',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(MaoRadius.small)),
              ),
              onSubmitted: (v) {
                if (_checkPassword(v)) {
                  setState(() => _unlocked = true);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('密码错误')),
                  );
                }
              },
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                if (_checkPassword(controller.text)) {
                  setState(() => _unlocked = true);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('密码错误')),
                  );
                }
              },
              child: const Text('进入'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPanel(AppThemeColors ac) {
    final ac = AppThemeColors.of(context);
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _DevCard(
          icon: Icons.memory,
          title: '调试日志',
          subtitle: DebugLogService.instance.enabled ? '已开启' : '已关闭',
          onTap: () {
            if (DebugLogService.instance.enabled) {
              DebugLogService.instance.disable();
            } else {
              DebugLogService.instance.enable();
            }
            setState(() {});
          },
        ),
        const SizedBox(height: 8),
        _DevCard(
          icon: Icons.file_download_outlined,
          title: '导出日志文件',
          onTap: () async {
            final file = await DebugLogService.instance.exportToFile();
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('已导出: ${file.path}')),
            );
          },
        ),
        const SizedBox(height: 8),
        _DevCard(
          icon: Icons.science_outlined,
          title: '模拟长期使用',
          subtitle: _simulating ? '生成中...' : '生成过去 N 天的刷题记录、错题与复习卡',
          onTap: _simulating ? null : _simulate,
        ),
        const SizedBox(height: 8),
        // 统计口径开关：模拟数据默认不进真实统计（避免污染），
        // 但生成后若不可见则该功能失去意义 —— 这里提供显式开关。
        // 生成模拟数据时会自动打开，也可手动关闭以查看「只有真实数据」的效果。
        _DevSwitchCard(
          icon: Icons.analytics_outlined,
          title: '统计包含模拟数据',
          subtitle: context.watch<AppState>().includeSimulatedStats
              ? '当前：首页与统计会显示模拟数据'
              : '当前：统计只计入真实作答（模拟数据被排除）',
          value: context.watch<AppState>().includeSimulatedStats,
          onChanged: (v) async {
            await context.read<AppState>().setIncludeSimulatedStats(v);
            if (!mounted) return;
            setState(() {
              _status = v ? '统计已包含模拟数据' : '统计只计入真实作答';
            });
          },
        ),
        const SizedBox(height: 8),
        // v1.0.2：清除模拟刷题数据（只清理模拟产生的数据，不动真实数据）
        _DevCard(
          icon: Icons.delete_sweep_outlined,
          title: '清除模拟数据',
          subtitle: '清除模拟生成的记录、复习卡与错题条目',
          onTap: _clearSimulated,
        ),
        const SizedBox(height: 8),
        // v1.0.2：隐藏当日刷题记录（与统计页同款，可恢复）
        _DevCard(
          icon: Icons.visibility_off_outlined,
          title: '隐藏当日刷题记录',
          subtitle: '将今日答题记录暂时隐藏（可恢复），今日将显示为未刷题',
          onTap: () async {
            final hidden = await context.read<AppState>().hideTodayRecords();
            if (!mounted) return;
            setState(() {
              _status = hidden > 0 ? '已隐藏 $hidden 条今日记录' : '今日暂无答题记录';
            });
          },
        ),
        const SizedBox(height: 8),
        _DevCard(
          icon: Icons.restore,
          title: '恢复今日刷题记录',
          subtitle: '把隐藏的今日答题记录恢复回来',
          onTap: () async {
            final restored =
                await context.read<AppState>().restoreTodayRecords();
            if (!mounted) return;
            setState(() {
              _status = restored > 0 ? '已恢复 $restored 条今日记录' : '今日没有被隐藏的记录';
            });
          },
        ),
        const SizedBox(height: 8),
        // v1.0.2 设计审查修复（简化保活）：移除无障碍保活入口（服务已删除）
        _DevCard(
          icon: Icons.battery_charging_full,
          title: '电池优化',
          subtitle: _batteryIgnored ? '电池优化：已豁免' : '电池优化：未豁免',
          onTap: () async {
            if (_batteryIgnored) return;
            await KeepAliveService.instance.requestIgnoreBatteryOptimizations();
            await _checkKeepalive();
          },
        ),
        // 数据库导入/导出已迁至 设置 → 同步与提醒 → 数据库备份
        // （2026-10-08 用户要求：整库备份是常规数据管理能力，不该藏在开发者模式里）。
        // 这里不再保留任何入口，避免两处重复。
        if (_status != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_status!,
                style: TextStyle(fontSize: MaoType.body, color: ac.accent)),
          ),
      ],
    );
  }
}

class _DevCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  const _DevCard({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(MaoRadius.control),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: ac.surfaceAlt.withOpacity(0.5),
          borderRadius: BorderRadius.circular(MaoRadius.control),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: ac.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: MaoType.body,
                          fontWeight: FontWeight.w600,
                          color: ac.textPrimary)),
                  if (subtitle != null)
                    Text(subtitle!,
                        style: TextStyle(
                            fontSize: MaoType.caption,
                            color: ac.textSecondary)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: ac.textSecondary),
          ],
        ),
      ),
    );
  }
}

/// 开发者选项里的开关卡片（与 _DevCard 同视觉语言，右侧为开关）。
class _DevSwitchCard extends StatelessWidget {
  const _DevSwitchCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: ac.surfaceAlt.withOpacity(0.5),
        borderRadius: BorderRadius.circular(MaoRadius.control),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: ac.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: MaoType.h3Style.copyWith(
                        fontWeight: FontWeight.w600, color: ac.textPrimary)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style:
                        MaoType.captionStyle.copyWith(color: ac.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
