import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/app_state.dart';
import '../services/debug_log_service.dart';
import '../models/app_settings.dart';
import '../services/theme_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _apiKeyController = TextEditingController();
  final _endpointController = TextEditingController();
  final _modelController = TextEditingController();
  bool _obscureKey = true;
  bool _debugEnabled = false;
  double? _balance;
  int _estimated = -1;
  bool _balanceLoading = false;

  @override
  void initState() {
    super.initState();
    _debugEnabled = DebugLogService.instance.enabled;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settings = context.read<AppState>().settings;
      _apiKeyController.text = settings.apiKey;
      _endpointController.text = settings.apiEndpoint;
      _modelController.text = settings.model;
      _fetchBalance();
    });
  }

  Future<void> _fetchBalance() async {
    if (_balanceLoading) return;
    setState(() => _balanceLoading = true);
    final appState = context.read<AppState>();
    final balance = await appState.fetchAIBalance();
    if (mounted) {
      setState(() {
        _balance = balance;
        _estimated = appState.getEstimatedRemainingQuestions();
        _balanceLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _endpointController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // API 配置卡片
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.api, color: cs.primary, size: 20),
                      const SizedBox(width: 8),
                      Text('AI 接口配置',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16, color: cs.onSurface)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '默认使用 DeepSeek API，填写你的 API Key 即可使用。也可自定义接口地址和模型。',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),

                  // API Key
                  Text('API Key',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: cs.onSurface)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _apiKeyController,
                    obscureText: _obscureKey,
                    decoration: InputDecoration(
                      hintText: 'sk-xxxxxxxxxxxxxxxxxxxxxxxx',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      suffixIcon: IconButton(
                        icon: Icon(
                            _obscureKey
                                ? Icons.visibility_off
                                : Icons.visibility,
                            size: 20),
                        onPressed: () =>
                            setState(() => _obscureKey = !_obscureKey),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 余额展示
                  if (_balance != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.account_balance_wallet, size: 18, color: Color(0xFFF0AD4E)),
                          const SizedBox(width: 8),
                          Text('剩余 ¥${_balance!.toStringAsFixed(2)}',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onPrimaryContainer)),
                          if (_estimated > 0) ...[
                            const SizedBox(width: 8),
                            Text('≈ ${_estimated} 题',
                                style: TextStyle(fontSize: 12, color: cs.onPrimaryContainer.withOpacity(0.7))),
                          ],
                          const Spacer(),
                          _balanceLoading
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : IconButton(
                                  icon: const Icon(Icons.refresh, size: 18),
                                  onPressed: _fetchBalance,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // API Endpoint
                  Text('API 地址',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: cs.onSurface)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _endpointController,
                    decoration: InputDecoration(
                      hintText: AppSettings.defaultApiEndpoint,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 14),

                  // Model
                  Text('模型名称',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: cs.onSurface)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _modelController,
                    decoration: InputDecoration(
                      hintText: AppSettings.defaultModel,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 保存按钮
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final newSettings = AppSettings(
                    apiKey: _apiKeyController.text.trim(),
                    apiEndpoint: _endpointController.text.trim().isEmpty
                        ? AppSettings.defaultApiEndpoint
                        : _endpointController.text.trim(),
                    model: _modelController.text.trim().isEmpty
                        ? AppSettings.defaultModel
                        : _modelController.text.trim(),
                  );
                  context.read<AppState>().updateSettings(newSettings);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('设置已保存'),
                      backgroundColor: cs.tertiary,
                    ),
                  );
                  Navigator.pop(context);
                },
                child: const Text('保存设置', style: TextStyle(fontSize: 16)),
              ),
            ),

            const SizedBox(height: 24),

            const SizedBox(height: 24),

            // 音效开关
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.music_note, color: cs.tertiary, size: 20),
                      const SizedBox(width: 8),
                      Text('音效', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: cs.onSurface)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('答对/答错时播放提示音', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  Consumer<AppState>(
                    builder: (context, appState, _) => SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(appState.settings.soundEnabled ? '音效已开启' : '音效已关闭',
                          style: TextStyle(fontSize: 14, color: cs.onSurface)),
                      value: appState.settings.soundEnabled,
                      onChanged: (v) {
                        appState.updateSettings(appState.settings.copyWith(soundEnabled: v));
                      },
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 主题切换
            Text('主题外观', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: cs.onSurface)),
            const SizedBox(height: 8),
            Consumer<ThemeService>(
              builder: (context, themeService, _) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(children: [
                    ...AppTheme.values.map((t) {
                      final label = ThemeService.labelOf(t);
                      final selected = themeService.current == t;
                      return RadioListTile<AppTheme>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(label, style: const TextStyle(fontSize: 14)),
                        value: t,
                        groupValue: themeService.current,
                        onChanged: (v) => themeService.switchTo(v!),
                      );
                    }),
                  ]),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 调试日志
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.bug_report, color: cs.secondary, size: 20),
                      const SizedBox(width: 8),
                      Text('调试日志',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16, color: cs.onSurface)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '开启后记录 AI 渲染链路、答案提交等关键数据，帮助排查前端 Bug。',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            _debugEnabled ? '日志已开启' : '日志已关闭',
                            style: TextStyle(fontSize: 14, color: cs.onSurface),
                          ),
                          value: _debugEnabled,
                          onChanged: (v) {
                            setState(() => _debugEnabled = v);
                            if (v) {
                              DebugLogService.instance.enable();
                            } else {
                              DebugLogService.instance.disable();
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.file_download, size: 16),
                          label: const Text('导出日志文件', style: TextStyle(fontSize: 13)),
                          onPressed: () async {
                            try {
                              if (!DebugLogService.instance.enabled) {
                                DebugLogService.instance.enable();
                              }
                              final file = await DebugLogService.instance.exportToFile();
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('日志已导出到: ${file.path}'),
                                    backgroundColor: cs.tertiary,
                                    duration: const Duration(seconds: 4),
                                  ),
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('导出失败: $e'),
                                    backgroundColor: cs.error,
                                  ),
                                );
                              }
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.delete_outline, size: 16),
                        label: const Text('清空', style: TextStyle(fontSize: 13)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: cs.error,
                        ),
                        onPressed: () {
                          DebugLogService.instance.clear();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text('日志已清空'),
                                backgroundColor: cs.onSurfaceVariant,
                              ),
                            );
                          }
                        },
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.share, size: 16),
                        label: const Text('分享', style: TextStyle(fontSize: 13)),
                        style: OutlinedButton.styleFrom(foregroundColor: cs.primary),
                        onPressed: () async {
                          try {
                            if (!DebugLogService.instance.enabled) {
                              DebugLogService.instance.enable();
                            }
                            final file = await DebugLogService.instance.exportToFile();
                            if (mounted) {
                              await Share.shareXFiles(
                                [XFile(file.path)], subject: '呆猫刷题宝调试日志',
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('分享失败: $e'), backgroundColor: cs.error),
                              );
                            }
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // 使用说明
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('使用说明',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: cs.onSurface)),
                  const SizedBox(height: 12),
                  _HelpItem(
                    icon: Icons.lock_outline,
                    text: 'API Key 仅保存在本地，不会上传到任何服务器',
                    cs: cs,
                  ),
                  _HelpItem(
                    icon: Icons.cached,
                    text: 'AI 解析结果会本地缓存，同一道题不会重复消耗 Token',
                    cs: cs,
                  ),
                  _HelpItem(
                    icon: Icons.file_present,
                    text: '支持导入 DOC/DOCX 格式题库文件，自动识别题目和选项',
                    cs: cs,
                  ),
                  _HelpItem(
                    icon: Icons.phone_android,
                    text: '支持 Windows 和 Android 双平台运行',
                    cs: cs,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HelpItem extends StatelessWidget {
  final IconData icon;
  final String text;
  final ColorScheme cs;

  const _HelpItem({required this.icon, required this.text, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, height: 1.4)),
          ),
        ],
      ),
    );
  }
}
