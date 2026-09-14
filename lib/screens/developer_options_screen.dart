import '../utils/design_tokens.dart';
import '../services/theme_service.dart';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/app_state.dart';
import '../services/database_service.dart';
import '../services/debug_log_service.dart';
import '../services/keepalive_service.dart';
import '../utils/responsive.dart';

/// 开发者选项（v1.0.2）：密码进入，调试专用
/// 日志 / 模拟长期使用 / 保活状态 / DB 备份导入导出
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
    final bat = await KeepAliveService.instance.isIgnoringBatteryOptimizations();
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
        content: const Text('将删除全部模拟生成的刷题记录、复习卡与错题条目，且不可恢复。\n\n你的真实刷题数据不受影响。确定清除？'),
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
                Text('生成天数：$days 天', style: const TextStyle(fontSize: MaoType.body)),
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
                          fontSize: MaoType.body, color: Theme.of(ctx).colorScheme.error)),
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

  /// 导出备份。
  ///
  /// 备份是整库拷贝，默认会把 API Key 一起带出去，而那条密文的密钥写死在
  /// App 里——拿到备份就能解出 Key。所以这里先让用户选：
  ///   · 不含 API Key（默认，推荐）：换机后重新填一次 Key 即可；
  ///   · 含 API Key：必须设置备份口令，整个备份文件会被加密。
  Future<void> _exportBackup() async {
    final choice = await _askExportMode();
    if (choice == null || !mounted) return;

    String? password;
    if (choice == _ExportMode.withApiKey) {
      final pwd = await _askBackupPassword();
      if (pwd == null) return; // 用户取消
      password = pwd;
    }

    // v1.0.2 设计审查修复：复用系统临时目录单文件（此前每次 createTemp('backup')
    // 目录且从不清理，累积垃圾）
    final dir = Directory.systemTemp;
    final suffix = choice == _ExportMode.withApiKey ? 'encrypted' : '';
    final name = 'flashcard_backup_${DateTime.now().millisecondsSinceEpoch}'
        '${suffix.isEmpty ? '' : '_$suffix'}.db';
    final path = '${dir.path}/$name';

    if (mounted) setState(() => _status = '正在导出…');
    final err = await DatabaseService.instance.exportBackup(
      path,
      includeApiKey: choice == _ExportMode.withApiKey,
      password: password,
    );
    if (err != null) {
      if (!mounted) return;
      setState(() => _status = '导出失败: $err');
      return;
    }
    if (!mounted) return;
    setState(() => _status = choice == _ExportMode.withApiKey
        ? '已导出（含 API Key，口令加密）。请牢记口令，丢失无法恢复。'
        : '已导出（不含 API Key）。');
    try {
      await Share.shareXFiles([XFile(path)], subject: '猫卷数据库备份');
    } catch (e) {
      // v1.0.2 设计审查修复：分享失败不再静默
      if (!mounted) return;
      setState(() => _status = '分享失败: $e');
    }
  }

  /// 选择导出模式；返回 null 表示用户取消。
  Future<_ExportMode?> _askExportMode() {
    return showDialog<_ExportMode>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导出数据库备份'),
        content: const Text(
          '备份包含题库、刷题记录、错题与批注。\n\n'
          '是否包含 API Key？\n'
          '· 不含（推荐）：备份是明文文件，换机后重新填一次 Key。\n'
          '· 包含：会要求设置备份口令，整个文件加密后才可分享。',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, _ExportMode.withApiKey),
              child: const Text('含 API Key')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, _ExportMode.withoutApiKey),
              child: const Text('不含（推荐）')),
        ],
      ),
    );
  }

  /// 要求设置备份口令（至少 6 位，需二次确认一致）。返回 null 表示取消。
  Future<String?> _askBackupPassword() async {
    final c1 = TextEditingController();
    final c2 = TextEditingController();
    String? error;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          title: const Text('设置备份口令'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '导入这个备份时需要输入同一口令。口令丢失则备份无法恢复，请自行记牢。',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: c1,
                obscureText: true,
                decoration: InputDecoration(
                    labelText: '备份口令', errorText: error),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: c2,
                obscureText: true,
                decoration: const InputDecoration(labelText: '再输入一次'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
              onPressed: () {
                final a = c1.text;
                if (a.length < 6) {
                  setInner(() => error = '口令至少 6 位');
                  return;
                }
                if (a != c2.text) {
                  setInner(() => error = '两次输入不一致');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
    final pwd = c1.text;
    c1.dispose();
    c2.dispose();
    return ok == true ? pwd : null;
  }

  Future<void> _importBackup() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['db'],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null) return;
    if (!mounted) return;

    // 口令加密的备份先要口令——在确认覆盖之前问，避免用户确认完才发现没口令
    String? password;
    if (await DatabaseService.instance.isEncryptedBackup(path)) {
      if (!mounted) return;
      password = await _askImportPassword();
      if (password == null) return; // 取消
    }
    if (!mounted) return;

    // v1.0.2 对齐里程碑：导入前确认（覆盖当前所有数据）
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入数据库备份'),
        content: Text(password == null
            ? '导入将覆盖当前所有数据，且需要重启App才能生效。'
            : '这是一个口令加密的备份。导入将覆盖当前所有数据，且需要重启App才能生效。'),
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

    if (mounted) setState(() => _status = '正在导入…');
    final err = await DatabaseService.instance
        .importBackup(path, password: password);
    if (!mounted) return;
    setState(() {
      // v1.0.2 对齐里程碑：数据库已替换，请重启App使数据生效。
      _status = err == null
          ? '数据库已替换，请重启App使数据生效。'
          : '导入失败: $err';
    });
  }

  /// 输入备份口令。返回 null 表示用户取消。
  Future<String?> _askImportPassword() async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('备份已加密'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('这个备份导出时设置了口令，请输入以继续。',
                style: TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: c,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(labelText: '备份口令'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确定')),
        ],
      ),
    );
    final pwd = c.text;
    c.dispose();
    return ok == true ? pwd : null;
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
            final hidden =
                await context.read<AppState>().hideTodayRecords();
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
        const SizedBox(height: 8),
        _DevCard(
          icon: Icons.backup_outlined,
          title: '导出数据库备份',
          subtitle: '默认不含 API Key；含 Key 时整包口令加密',
          onTap: _exportBackup,
        ),
        const SizedBox(height: 8),
        _DevCard(
          icon: Icons.restore,
          title: '导入数据库备份',
          subtitle: '校验 SQLite 魔数与核心表；加密备份需输入口令',
          onTap: _importBackup,
        ),
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
                            fontSize: MaoType.caption, color: ac.textSecondary)),
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

/// 导出备份时对 API Key 的处理方式。
enum _ExportMode {
  /// 不含 API Key（默认）：备份是明文文件，换机后重新填 Key。
  withoutApiKey,

  /// 含 API Key：必须设置备份口令，整个备份文件加密。
  withApiKey,
}
