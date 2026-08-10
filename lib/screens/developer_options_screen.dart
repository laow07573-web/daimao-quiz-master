import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/app_state.dart';
import '../services/database_service.dart';
import '../services/debug_log_service.dart';
import '../services/keepalive_service.dart';

/// 开发者选项（v1.0.2）：密码进入 `kskblzdjd`
/// 日志 / 模拟长期使用 / 保活状态 / DB 备份导入导出
class DeveloperOptionsScreen extends StatefulWidget {
  const DeveloperOptionsScreen({super.key});

  @override
  State<DeveloperOptionsScreen> createState() => _DeveloperOptionsScreenState();
}

class _DeveloperOptionsScreenState extends State<DeveloperOptionsScreen> {
  static const _password = 'kskblzdjd';
  bool _unlocked = false;
  bool _simulating = false;
  bool _accessibilityOn = false;
  bool _batteryIgnored = true;
  String? _status;

  @override
  void initState() {
    super.initState();
    _checkKeepalive();
  }

  Future<void> _checkKeepalive() async {
    final acc = await KeepAliveService.instance.isAccessibilityEnabled();
    final bat = await KeepAliveService.instance.isIgnoringBatteryOptimizations();
    if (!mounted) return;
    setState(() {
      _accessibilityOn = acc;
      _batteryIgnored = bat;
    });
  }

  /// v1.0.2 对齐里程碑：模拟对话框（基于当前题库 / 确认到期 / 说明）
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
                        fontSize: 12,
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                Text('使用 FSRS 算法全权生成，用于测试每日提醒、连击、首页战绩。',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                const SizedBox(height: 12),
                Text('生成天数：$days 天', style: const TextStyle(fontSize: 13)),
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
                      style: TextStyle(fontSize: 13)),
                  value: randomWeakKp,
                  onChanged: (v) =>
                      setDialogState(() => randomWeakKp = v ?? false),
                ),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('把所有复习卡设为今天到期，便于测试错题复习',
                      style: TextStyle(fontSize: 13)),
                  value: dueToday,
                  onChanged: (v) => setDialogState(() => dueToday = v ?? false),
                ),
                const SizedBox(height: 4),
                Text('· 答错的题自动进错题本并建复习卡',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                Text('· 重复执行会先清理上次模拟的数据，可放心多试。',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                if (dueToday)
                  Text('· 错题本的「待复习」数量会全部增加。',
                      style: TextStyle(
                          fontSize: 12, color: Theme.of(ctx).colorScheme.error)),
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
                  if (dueToday) {
                    final sure = await showDialog<bool>(
                      context: ctx,
                      builder: (c2) => AlertDialog(
                        title: const Text('确认操作'),
                        content: const Text('确定把所有复习卡设为今天到期吗？\n错题本的「待复习」数量会全部增加。'),
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
                  Navigator.pop(ctx, true);
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

  Future<void> _exportBackup() async {
    final dir = (await Directory.systemTemp.createTemp('backup')).path;
    final path = '$dir/flashcard_backup_${DateTime.now().millisecondsSinceEpoch}.db';
    final err = await DatabaseService.instance.exportBackup(path);
    if (err != null) {
      if (!mounted) return;
      setState(() => _status = '导出失败: $err');
      return;
    }
    await Share.shareXFiles([XFile(path)], subject: '呆猫刷题宝数据库备份');
  }

  Future<void> _importBackup() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['db'],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null) return;
    // v1.0.2 对齐里程碑：导入前确认（覆盖当前所有数据）
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入数据库备份'),
        content: const Text('导入将覆盖当前所有数据，且需要重启App才能生效。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('导入')),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    final err = await DatabaseService.instance.importBackup(path);
    if (!mounted) return;
    setState(() {
      // v1.0.2 对齐里程碑：数据库已替换，请重启App使数据生效。
      _status = err == null
          ? '数据库已替换，请重启App使数据生效。'
          : '导入失败: $err';
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
      body: !_unlocked ? _buildLock(cs) : _buildPanel(cs),
    );
  }

  Widget _buildLock(ColorScheme cs) {
    final controller = TextEditingController();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 56, color: cs.primary),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              obscureText: true,
              decoration: InputDecoration(
                // v1.0.2 对齐里程碑：输入密码开启，调试专用
                labelText: '输入密码开启，调试专用',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onSubmitted: (v) {
                if (v == _password) {
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
                if (controller.text == _password) {
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

  Widget _buildPanel(ColorScheme cs) {
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
        _DevCard(
          icon: Icons.health_and_safety_outlined,
          title: '保活（无障碍）状态',
          subtitle: _accessibilityOn
              ? '无障碍保活：已开启'
              : '无障碍保活：未开启',
          onTap: () async {
            await KeepAliveService.instance.openAccessibilitySettings();
            await _checkKeepalive();
          },
        ),
        const SizedBox(height: 8),
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
        const SizedBox(height: 8),
        _DevCard(
          icon: Icons.backup_outlined,
          title: '导出数据库备份',
          subtitle: '生成一致性快照并分享 .db 文件',
          onTap: _exportBackup,
        ),
        const SizedBox(height: 8),
        _DevCard(
          icon: Icons.restore,
          title: '导入数据库备份',
          subtitle: '校验 SQLite 魔数与核心表',
          onTap: _importBackup,
        ),
        if (_status != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_status!,
                style: TextStyle(fontSize: 12, color: cs.primary)),
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
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withOpacity(0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: cs.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface)),
                  if (subtitle != null)
                    Text(subtitle!,
                        style: TextStyle(
                            fontSize: 11, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
