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
  String? _status;

  @override
  void initState() {
    super.initState();
    _checkAccessibility();
  }

  Future<void> _checkAccessibility() async {
    final on = await KeepAliveService.instance.isAccessibilityEnabled();
    if (!mounted) return;
    setState(() => _accessibilityOn = on);
  }

  Future<void> _simulate() async {
    setState(() => _simulating = true);
    await context.read<AppState>().simulateLongTermUse();
    if (!mounted) return;
    setState(() {
      _simulating = false;
      _status = '模拟数据已生成（幂等，重复调用不会新增）';
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
    final err = await DatabaseService.instance.importBackup(path);
    if (!mounted) return;
    setState(() {
      _status = err == null
          ? '导入成功（数据已替换，重启应用后生效）'
          : '导入失败: $err';
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('开发者选项')),
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
                labelText: '输入开发者密码',
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
          subtitle: _simulating ? '生成中...' : '生成 90 天刷题数据（幂等）',
          onTap: _simulating ? null : _simulate,
        ),
        const SizedBox(height: 8),
        _DevCard(
          icon: Icons.health_and_safety_outlined,
          title: '保活（无障碍）状态',
          subtitle: _accessibilityOn ? '已开启 ✅' : '未开启 ⚠️',
          onTap: () async {
            await KeepAliveService.instance.openAccessibilitySettings();
            await _checkAccessibility();
          },
        ),
        const SizedBox(height: 8),
        _DevCard(
          icon: Icons.backup_outlined,
          title: '导出数据库备份',
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
