import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../services/database_service.dart';
import '../services/theme_service.dart';
import '../utils/design_tokens.dart';
import '../utils/responsive.dart';
import '../widgets/kit/mj_kit.dart';

/// 数据库备份（导出 / 导入）。
///
/// 2026-10-08 用户要求：从「开发者选项」移入普通设置——整库备份/恢复是常规
/// 数据管理能力，不该藏在开发者模式里。入口在 设置 → 同步与提醒 → 数据库备份。
///
/// 导出：整库拷贝，可选是否包含 API Key（含 Key 必须设置口令、整包加密）。
/// 导入：覆盖当前全部数据，需要重启 App 生效；加密备份要求先输入口令。
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  String? _status;
  String? _importStatus;
  bool _importing = false;

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

    // 复用系统临时目录单文件（此前每次 createTemp('backup') 目录且从不清理）
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
      // 分享失败不再静默
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
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
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
                decoration:
                    InputDecoration(labelText: '备份口令', errorText: error),
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
    if (_importing || !mounted) return;
    setState(() {
      _importing = true;
      _importStatus = '正在打开文件选择器…';
    });
    var picking = true;
    try {
      // Android 可能无法将 .db 映射到 MIME 类型，custom 过滤会导致选择器失败。
      // 允许选择任意文件；真正的备份内容仍由 DatabaseService 在导入时校验。
      final result = await FilePicker.platform.pickFiles(type: FileType.any);
      picking = false;
      if (!mounted) return;
      if (result == null || result.files.isEmpty) {
        setState(() => _importStatus = '已取消选择备份文件');
        return;
      }
      final path = result.files.first.path;
      if (path == null || path.trim().isEmpty) {
        setState(() => _importStatus = '无法获取文件的本地路径，请先下载到本机后重试');
        return;
      }
      setState(() => _importStatus = '正在读取备份信息…');

      // 加密备份先询问口令，再确认覆盖；取消任何一步都不替换数据库。
      String? password;
      if (await DatabaseService.instance.isEncryptedBackup(path)) {
        if (!mounted) return;
        password = await _askImportPassword();
        if (!mounted) return;
        if (password == null) {
          setState(() => _importStatus = '已取消导入备份');
          return;
        }
      }
      if (!mounted) return;
      setState(() => _importStatus = '等待确认导入备份');
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
      if (!mounted) return;
      if (sure != true) {
        setState(() => _importStatus = '已取消导入备份');
        return;
      }
      setState(() => _importStatus = '正在导入…');
      final err =
          await DatabaseService.instance.importBackup(path, password: password);
      if (!mounted) return;
      setState(() =>
          _importStatus = err == null ? '数据库已替换，请重启App使数据生效。' : '导入失败: $err');
    } catch (e) {
      if (!mounted) return;
      setState(
          () => _importStatus = picking ? '打开文件选择器失败，请重试: $e' : '导入失败: $e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
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
            const Text('这个备份导出时设置了口令，请输入以继续。', style: TextStyle(fontSize: 13)),
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
      backgroundColor: ac.background,
      appBar: AppBar(title: const Text('数据库备份')),
      body: ResponsivePage(
        child: ListView(
          padding: const EdgeInsets.all(MaoSpace.md),
          children: [
            const MJSectionHeader(
              title: '整库备份',
              subtitle: '换机、重装或留档时使用；备份包含题库、刷题记录、错题与批注',
            ),
            const SizedBox(height: MaoSpace.sm),
            MJListRow(
              leading: Icon(Icons.ios_share, size: 18, color: ac.accent),
              title: '导出数据库备份',
              subtitle: '默认不含 API Key；含 Key 时整包口令加密',
              chevron: true,
              onTap: _exportBackup,
            ),
            const SizedBox(height: MaoSpace.xs),
            MJListRow(
              leading: Icon(Icons.restore, size: 18, color: ac.accent),
              title: '导入数据库备份',
              // 进度与结果统一在下方状态行显示，避免同一句话出现两遍
              subtitle: '可选择任意文件；导入时校验备份内容，加密备份需输入口令',
              chevron: true,
              onTap: _importing ? null : _importBackup,
            ),
            if (_status != null) ...[
              const SizedBox(height: MaoSpace.sm),
              _StatusLine(text: _status!, ac: ac),
            ],
            if (_importStatus != null) ...[
              const SizedBox(height: MaoSpace.xxs),
              _StatusLine(text: _importStatus!, ac: ac),
            ],
            const SizedBox(height: MaoSpace.md),
            Text(
              '提示：导入会覆盖当前全部数据，完成后需要重启 App 才会生效。'
              '如果你只是想把自己的题库给别的设备用，优先用「局域网同步」里的题库分享。',
              style: MaoType.captionStyle.copyWith(color: ac.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// 备份操作的进度/结果提示行。
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.text, required this.ac});

  final String text;
  final AppThemeColors ac;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, size: 14, color: ac.textTertiary),
        const SizedBox(width: MaoSpace.xxs),
        Expanded(
          child: Text(text,
              style: MaoType.captionStyle.copyWith(color: ac.textSecondary)),
        ),
      ],
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
