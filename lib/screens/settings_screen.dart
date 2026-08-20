import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/question.dart';
import '../services/ai_service.dart';
import '../services/app_state.dart';
import '../services/debug_log_service.dart';
import '../services/keepalive_service.dart';
import '../services/reminder_service.dart';
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
  final _nicknameController = TextEditingController();
  bool _obscureKey = true;
  bool _debugEnabled = false;
  double? _balance;
  int _estimated = -1;
  bool _balanceLoading = false;
  // v1.0.2 设计审查修复（简化保活）：移除无障碍状态，仅保留电池优化
  // v1.0.2 修复：初始为 false（未知状态），加载真实值前不误导"已豁免"
  bool _batteryIgnored = false;
  int _untaggedCount = 0;

  @override
  void initState() {
    super.initState();
    _debugEnabled = DebugLogService.instance.enabled;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settings = context.read<AppState>().settings;
      _apiKeyController.text = settings.apiKey;
      _endpointController.text = settings.apiEndpoint;
      _modelController.text = settings.model;
      _nicknameController.text = settings.nickname;
      _fetchBalance();
      _loadKeepaliveStatus();
      _loadUntaggedCount();
    });
  }

  Future<void> _loadKeepaliveStatus() async {
    final bat = await KeepAliveService.instance.isIgnoringBatteryOptimizations();
    if (!mounted) return;
    setState(() {
      _batteryIgnored = bat;
    });
  }

  Future<void> _loadUntaggedCount() async {
    final count = await context.read<AppState>().getUntaggedErrorCount();
    if (!mounted) return;
    setState(() => _untaggedCount = count);
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
    _nicknameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // v1.0.2: 未保存修改拦截
    final settings = context.watch<AppState>().settings;
    final dirty = _apiKeyController.text != settings.apiKey ||
        _endpointController.text != settings.apiEndpoint ||
        _modelController.text != settings.model ||
        _nicknameController.text != settings.nickname;
    return PopScope(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('有未保存的设置修改'),
            // v1.0.2 对齐里程碑：退出后将丢失
            content: const Text('有未保存的设置修改，退出后将丢失。'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('继续编辑')),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('离开', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );
        if (leave == true && mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
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
                          // v1.0.2 设计审查修复：硬编码色 → 主题语义色
                          Icon(Icons.account_balance_wallet, size: 18,
                              color: AppThemeColors.of(context).warning),
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

                  // v1.0.2 对齐里程碑：余额不足提示
                  if (_balance != null && _balance! < 1) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: cs.error.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          // v1.0.2 设计审查修复：硬编码色 → 主题错误色
                          Icon(Icons.warning_amber, size: 16, color: cs.error),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text('API 余额不足 ¥1，建议尽快充值以免影响使用',
                                style: TextStyle(
                                    fontSize: 12, color: cs.error)),
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
                  const SizedBox(height: 14),

                  // v1.0.2 对齐里程碑：昵称（首页专属问候）
                  Text('你的昵称',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: cs.onSurface)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _nicknameController,
                    decoration: InputDecoration(
                      hintText: '设置后，首页会显示对你的专属问候。',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 保存按钮
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final newSettings = AppSettings(
                    apiKey: _apiKeyController.text.trim(),
                    apiEndpoint: _endpointController.text.trim().isEmpty
                        ? AppSettings.defaultApiEndpoint
                        : _endpointController.text.trim(),
                    model: _modelController.text.trim().isEmpty
                        ? AppSettings.defaultModel
                        : _modelController.text.trim(),
                    nickname: _nicknameController.text.trim(),
                  );
                  // v1.0.2 修复：等待保存完成再提示/返回（此前 fire-and-forget）
                  await context.read<AppState>().updateSettings(newSettings);
                  if (!mounted) return;
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

            // v1.0.2 对齐里程碑：为剩余题目打标签
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
                      Icon(Icons.sell_outlined, color: cs.primary, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('为剩余题目打标签',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: cs.onSurface)),
                      ),
                      if (_untaggedCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: cs.error.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text('$_untaggedCount 题未打标签',
                              style: TextStyle(
                                  fontSize: 11, color: cs.error)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // v1.0.2 对齐里程碑：打标签用途说明
                  Text(
                    '用于：根据错题分析薄弱知识点、错题本按章节分组。按知识点统计错题分布，优先攻克薄弱类型',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, height: 1.4),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '部分错题未打知识点标签，可去设置页「为剩余题目打标签」补齐后精炼更准。',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      icon: const Icon(Icons.auto_awesome, size: 16),
                      label: Text(
                          _untaggedCount > 0 ? '开始打标签' : '暂无未打标签题目',
                          style: const TextStyle(fontSize: 13)),
                      onPressed: (_untaggedCount > 0 &&
                              context.read<AppState>().settings.isConfigured)
                          ? () => _startTagging(context)
                          : null,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

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

            // 假期模式（v1.0.2）
            Consumer<AppState>(
              builder: (context, appState, _) {
                final now = DateTime.now();
                return Container(
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
                        Icon(Icons.beach_access, color: cs.error, size: 20),
                        const SizedBox(width: 8),
                        Text('寒暑假模式',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: cs.onSurface)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // v1.0.2 对齐里程碑：寒暑假模式说明文案
                    Text(
                      '作用：开启后暂停每日提醒、错题 FSRS 复习与答题练习，本周战绩日历自动标注假期区间；连击冻结，假期不刷题也不断卡。',
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurfaceVariant, height: 1.4),
                    ),
                    // v1.0.2 修复：提示默认区间为当前自然月，需按实际假期调整
                    Text(
                      '默认区间为当前自然月，请开启后按实际假期调整起止日期。',
                      style: TextStyle(
                          fontSize: 11, color: cs.onSurfaceVariant.withOpacity(0.8)),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(appState.vacationModeEnabled ? '已开启' : '已关闭',
                          style:
                              TextStyle(fontSize: 14, color: cs.onSurface)),
                      value: appState.vacationModeEnabled,
                      onChanged: (v) async {
                        final now = DateTime.now();
                        final start = appState.vacationStartDate ??
                            DateTime(now.year, now.month, 1);
                        final end = appState.vacationEndDate ??
                            DateTime(now.year, now.month + 1, 0);
                        await appState.setVacationMode(
                            enabled: v, start: start, end: end);
                        // v1.0.2: 假期切换同步提醒启停
                        await ReminderService.instance.syncSchedule();
                      },
                    ),
                    if (appState.vacationModeEnabled) ...[
                      // 起止日期联动：选开始上限=结束日，选结束下限=开始日。
                      // v1.0.2 设计审查修复：选择范围收窄为前后 1 年
                      // （此前 2000~2100 可产生 3.6 万个假期日期）
                      Row(
                        children: [
                          Expanded(
                            child: _DateField(
                              // v1.0.2 对齐里程碑：选择假期开始日期
                              label: '选择假期开始日期',
                              value: appState.vacationStartDate,
                              firstDate:
                                  DateTime(now.year - 1, now.month, now.day),
                              lastDate: appState.vacationEndDate ??
                                  DateTime(now.year + 1, now.month, now.day),
                              onChanged: (d) => appState.setVacationMode(
                                  enabled: true,
                                  start: d,
                                  end: appState.vacationEndDate),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _DateField(
                              // v1.0.2 对齐里程碑：选择假期结束日期
                              label: '选择假期结束日期',
                              value: appState.vacationEndDate,
                              firstDate: appState.vacationStartDate ??
                                  DateTime(now.year - 1, now.month, now.day),
                              lastDate: DateTime(now.year + 1, now.month, now.day),
                              onChanged: (d) => appState.setVacationMode(
                                  enabled: true,
                                  start: appState.vacationStartDate,
                                  end: d),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              );
              },
            ),

            const SizedBox(height: 16),

            // 每日提醒（v1.0.2）
            Consumer<AppState>(
              builder: (context, appState, _) => Container(
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
                        Icon(Icons.notifications_outlined,
                            color: cs.primary, size: 20),
                        const SizedBox(width: 8),
                        // v1.0.2 对齐里程碑：提醒与复习
                        Text('提醒与复习',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: cs.onSurface)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // v1.0.2 对齐里程碑：到点会提醒你刷题打卡，保持连胜
                    Text('到点会提醒你刷题打卡，保持连胜',
                        style: TextStyle(
                            fontSize: 12, color: cs.onSurfaceVariant)),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(appState.reminderEnabled ? '已开启' : '已关闭',
                          style:
                              TextStyle(fontSize: 14, color: cs.onSurface)),
                      value: appState.reminderEnabled,
                      onChanged: (v) async {
                        // v1.0.2 修复：开启提醒前请求 Android 13+ 通知运行时权限
                        if (v) {
                          await ReminderService.instance
                              .requestNotificationPermission();
                          // v1.0.2 设计审查修复：被拒后如实提示，
                          // 不再无提示静默开启一个"看不到的提醒"
                          final granted = await ReminderService.instance
                              .hasNotificationPermission();
                          if (!mounted) return;
                          if (!granted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('通知权限未开启：提醒将不可见。'
                                      '请到系统设置中允许本应用的通知权限。')),
                            );
                          }
                        }
                        await appState.setReminderSettings(
                            enabled: v,
                            time: appState.reminderTime ??
                                DateTime(DateTime.now().year,
                                    DateTime.now().month, DateTime.now().day, 20));
                        // v1.0.2: 提醒开关同步启停前台服务与闹钟
                        await ReminderService.instance.syncSchedule();
                      },
                    ),
                    if (appState.reminderEnabled)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: const Icon(Icons.schedule, size: 20),
                        title: Text(
                          '提醒时间：${_fmtTime(appState.reminderTime)}',
                          style: const TextStyle(fontSize: 14),
                        ),
                        trailing: const Icon(Icons.edit, size: 18),
                        onTap: () async {
                          final now = DateTime.now();
                          final current = appState.reminderTime ??
                              DateTime(now.year, now.month, now.day, 20);
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.fromDateTime(current),
                          );
                          if (picked != null) {
                            await appState.setReminderSettings(
                                enabled: true,
                                time: DateTime(current.year, current.month,
                                    current.day, picked.hour, picked.minute));
                            await ReminderService.instance.syncSchedule();
                          }
                        },
                      ),
                    const SizedBox(height: 4),
                    // v1.0.2 对齐里程碑：测试通知
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.notifications_active, size: 16),
                        label: const Text('发送测试通知', style: TextStyle(fontSize: 13)),
                        onPressed: () async {
                          // v1.0.2 修复：Android 13+ 先请求通知权限，再发测试通知
                          await ReminderService.instance
                              .requestNotificationPermission();
                          final sent = await ReminderService.instance
                              .sendTestNotification();
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(sent
                                    ? '测试通知已发送，下拉通知栏查看'
                                    // v1.0.2 设计审查修复：按真实原因提示
                                    : (Platform.isAndroid
                                        ? '通知权限未开启，请到系统设置允许通知权限'
                                        : '当前平台不支持发送测试通知'))),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // v1.0.2 设计审查修复（简化保活）：移除无障碍保活
            // （过度保活 + 商店合规风险），保留电池优化豁免
            // （前台提醒服务不被系统激进清理）
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
                      Icon(Icons.battery_charging_full,
                          color: cs.primary, size: 20),
                      const SizedBox(width: 8),
                      Text('电池优化',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: cs.onSurface)),
                      const Spacer(),
                      Icon(
                        _batteryIgnored
                            ? Icons.check_circle
                            : Icons.error_outline,
                        size: 18,
                        color: _batteryIgnored ? cs.primary : cs.error,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _batteryIgnored ? '电池优化：已豁免' : '电池优化：未豁免',
                    style: TextStyle(
                        fontSize: 12,
                        color: _batteryIgnored ? cs.primary : cs.error),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '允许忽略电池优化，防止系统在后台清理每日提醒服务',
                    style:
                        TextStyle(fontSize: 12, color: cs.onSurfaceVariant, height: 1.4),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '若仍收不到提醒：最近任务中长按本应用并锁定',
                    style:
                        TextStyle(fontSize: 12, color: cs.onSurfaceVariant, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.battery_alert, size: 16),
                          label: Text(
                              _batteryIgnored ? '电池优化：已豁免' : '请求忽略电池优化',
                              style: const TextStyle(fontSize: 12)),
                          onPressed: _batteryIgnored
                              ? null
                              : () async {
                                  await KeepAliveService.instance
                                      .requestIgnoreBatteryOptimizations();
                                  await _loadKeepaliveStatus();
                                },
                        ),
                      ),
                    ],
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

            // v1.0.2 七项改进：深色模式（跟随系统/浅色/深色）
            Text('深色模式', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: cs.onSurface)),
            const SizedBox(height: 8),
            Consumer<ThemeService>(
              builder: (context, themeService, _) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(children: [
                    for (final (mode, label) in [
                      (ThemeMode.system, '跟随系统'),
                      (ThemeMode.light, '浅色'),
                      (ThemeMode.dark, '深色'),
                    ])
                      RadioListTile<ThemeMode>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(label, style: const TextStyle(fontSize: 14)),
                        value: mode,
                        groupValue: themeService.themeMode,
                        onChanged: (v) => themeService.switchThemeMode(v!),
                      ),
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
                                [XFile(file.path)], subject: '猫卷调试日志',
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
                    icon: Icons.shield_outlined,
                    // v1.0.2 设计审查修复：如实说明保护强度（本地混淆存储，非强加密）
                    text: 'API Key 本地混淆存储（防随手翻看，非强加密保护）',
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
                    // v1.0.2 只做 Android 端（Windows 平台工程已移除）
                    text: '支持 Android 端使用',
                    cs: cs,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  String _fmtTime(DateTime? t) {
    if (t == null) return '20:00';
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  /// v1.0.2 对齐里程碑：为剩余题目打标签（进度 + 暂停/继续 + 预览确认）
  Future<void> _startTagging(BuildContext context) async {
    final appState = context.read<AppState>();
    final ai = appState.aiService;
    if (ai == null) return;
    final questions = await appState.getUntaggedErrorQuestions();
    if (!mounted || questions.isEmpty) return;
    final applied = await showDialog<({int applied, int skipped})>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TaggingDialog(
          questions: questions, ai: ai, appState: appState),
    );
    if (!mounted) return;
    if (applied != null && applied.applied > 0) {
      final msg = applied.skipped > 0
          // v1.0.2 修复：跳过 AI 失败标记，不把失败串当作知识点入库
          ? '已应用 ${applied.applied} 道标签，跳过 ${applied.skipped} 道失败标记'
          // v1.0.2 对齐里程碑：全部题目已打标签完成
          : '全部题目已打标签完成';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: Theme.of(context).colorScheme.tertiary,
        ),
      );
    }
    await _loadUntaggedCount();
  }
}

/// 打标签进度对话框：逐题调用 AI，支持暂停/继续，完成后预览确认应用
class _TaggingDialog extends StatefulWidget {
  final List<Question> questions;
  final AIService ai;
  final AppState appState;

  const _TaggingDialog({
    required this.questions,
    required this.ai,
    required this.appState,
  });

  @override
  State<_TaggingDialog> createState() => _TaggingDialogState();
}

class _TaggingDialogState extends State<_TaggingDialog> {
  int _done = 0;
  bool _paused = false;
  bool _finished = false;
  bool _applying = false;
  bool _cancelled = false;
  Completer<void>? _resumeCompleter;
  final List<(Question, String)> _labels = [];

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    for (final q in widget.questions) {
      if (_cancelled) break;
      while (_paused) {
        final c = _resumeCompleter;
        if (c == null) break;
        await c.future;
      }
      if (_cancelled) break;
      final kp = await widget.ai.tagKnowledgePoint(q);
      if (_cancelled) break;
      _labels.add((q, kp));
      if (mounted) setState(() => _done++);
    }
    if (!mounted) return;
    setState(() => _finished = true);
  }

  void _togglePause() {
    if (_paused) {
      final c = _resumeCompleter;
      setState(() => _paused = false);
      c?.complete();
    } else {
      _resumeCompleter = Completer<void>();
      setState(() => _paused = true);
    }
  }

  Future<void> _apply() async {
    setState(() => _applying = true);
    var skipped = 0;
    for (final (q, kp) in _labels) {
      if (kp.startsWith('AI')) {
        // v1.0.2 修复：失败标记（AI请求失败 等）不写入知识点，避免污染错题本统计
        skipped++;
        continue;
      }
      if (q.id != null) {
        await widget.appState.updateQuestionKnowledgePoint(q.id!, kp);
      }
    }
    if (!mounted) return;
    Navigator.pop(
        context, (applied: _labels.length - skipped, skipped: skipped));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // v1.0.2 修复：系统返回键关闭对话框时终止打标签循环（不再后台白跑浪费额度）
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _cancelled = true;
        _resumeCompleter?.complete();
        Navigator.pop(context, (applied: 0, skipped: 0));
      },
      child: AlertDialog(
        title: Text(_finished
          ? '预览确认'
          : _paused
              ? '打标签已暂停，可随时继续'
              : '正在打标签：已打 $_done/${widget.questions.length} 道题目，请预览确认'),
      content: SizedBox(
        width: 340,
        height: 340,
        child: _finished
            ? ListView.builder(
                itemCount: _labels.length,
                itemBuilder: (context, i) {
                  final (q, kp) = _labels[i];
                  final failed = kp.startsWith('AI');
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                        failed ? Icons.warning_amber : Icons.label_outline,
                        size: 16,
                        color: failed ? cs.error : cs.primary),
                    title: Text(q.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12)),
                    trailing: Text(kp,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: failed ? cs.error : cs.primary)),
                  );
                },
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(strokeWidth: 3)),
                  const SizedBox(height: 16),
                  Text(
                    _paused ? '已暂停，可随时继续' : '正在逐题识别知识点...',
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
      ),
      actions: _finished
          ? [
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, (applied: 0, skipped: 0)),
                child: const Text('放弃'),
              ),
              TextButton(
                onPressed: _applying ? null : _apply,
                child: _applying
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('确认应用'),
              ),
            ]
          : [
              TextButton(
                onPressed: () {
                  _cancelled = true;
                  _resumeCompleter?.complete();
                  Navigator.pop(context, (applied: 0, skipped: 0));
                },
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: _togglePause,
                child: Text(_paused ? '继续' : '暂停'),
              ),
            ],
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final DateTime firstDate;
  final DateTime lastDate;
  final ValueChanged<DateTime> onChanged;

  const _DateField({
    required this.label,
    required this.value,
    required this.firstDate,
    required this.lastDate,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: firstDate,
          lastDate: lastDate,
          helpText: label,
        );
        if (picked != null) onChanged(picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today, size: 14, color: cs.primary),
            const SizedBox(width: 8),
            Text(
              value == null
                  ? label
                  : '${value!.year}-${value!.month.toString().padLeft(2, '0')}-${value!.day.toString().padLeft(2, '0')}',
              style: TextStyle(fontSize: 13, color: cs.onSurface),
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
