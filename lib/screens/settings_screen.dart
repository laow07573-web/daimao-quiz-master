import '../utils/design_tokens.dart';
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
import '../services/device_service.dart';
import '../services/sync/sync_engine.dart';
import '../services/theme_service.dart';
import '../utils/responsive.dart';

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
  final _endpointFocus = FocusNode();
  bool _obscureKey = true;
  bool _debugEnabled = false;
  double? _balance;
  int _estimated = -1;
  bool _balanceLoading = false;
  // v1.0.2 设计审查修复（简化保活）：移除无障碍状态，仅保留电池优化
  // v1.0.2 修复：初始为 false（未知状态），加载真实值前不误导"已豁免"
  bool _batteryIgnored = false;
  int _untaggedCount = 0;

  // v1.28 连接测试状态
  bool _testing = false;
  bool _testOk = false;
  String? _testResult;

  // v1.28 模型列表（从接口拉取供选择）
  bool _modelsLoading = false;
  List<String> _modelOptions = const [];
  String? _modelsError;

  // v1.28 AI 回答风格（未保存的本地态，保存时写入设置）
  AnalysisDetail _detail = AnalysisDetail.brief;
  bool _keywordHighlight = true;

  /// 从当前端点拉取模型列表（OpenAI 兼容 GET /models）
  Future<void> _loadModels() async {
    if (_modelsLoading) return;
    final key = _apiKeyController.text.trim();
    if (key.isEmpty) {
      setState(() {
        _modelsError = '请先填写 API Key';
        _modelOptions = const [];
      });
      return;
    }
    setState(() {
      _modelsLoading = true;
      _modelsError = null;
    });

    final temp = AppSettings(
      apiKey: key,
      apiEndpoint: _endpointController.text.trim().isEmpty
          ? AppSettings.defaultApiEndpoint
          : _endpointController.text.trim(),
      model: _modelController.text.trim().isEmpty
          ? AppSettings.defaultModel
          : _modelController.text.trim(),
    );
    final svc = AIService(temp);
    try {
      final (models, err) = await svc.fetchModels();
      if (!mounted) return;
      setState(() {
        _modelsLoading = false;
        _modelOptions = models;
        _modelsError = err;
        // 只有一个模型时直接填入，省一次点击
        if (models.length == 1) _modelController.text = models.first;
      });
    } finally {
      svc.dispose();
    }
  }

  /// 当前填写的地址是否命中某个预设（用于高亮）
  /// v1.28：「自定义」在地址为空或不匹配任何已知预设时高亮
  bool _isPresetActive(ApiPreset p) {
    final cur = _endpointController.text.trim();
    if (p.isCustom) {
      return cur.isEmpty ||
          !kApiPresets.any((q) => !q.isCustom && _matchesPreset(cur, q));
    }
    return _matchesPreset(cur, p);
  }

  bool _matchesPreset(String cur, ApiPreset p) {
    if (cur.isEmpty || p.endpoint.isEmpty) return false;
    return cur == p.endpoint ||
        cur.startsWith('${p.endpoint}/') ||
        cur == '$p.endpoint/chat/completions';
  }

  /// 一键应用预设（端点 + 模型），并清空上一次测试结果
  /// v1.28：「自定义」清空两个输入框并聚焦，方便直接填写自己的地址
  void _applyPreset(ApiPreset p) {
    setState(() {
      if (p.isCustom) {
        _endpointController.clear();
        _modelController.clear();
      } else {
        _endpointController.text = p.endpoint;
        _modelController.text = p.model;
      }
      _testResult = null;
    });
    if (p.isCustom) {
      _endpointFocus.requestFocus();
    }
  }

  /// 连接测试：用当前「未保存」的输入直接验证，避免必须先保存再试
  Future<void> _testConnection() async {
    if (_testing) return;
    final appState = context.read<AppState>();
    final key = _apiKeyController.text.trim();
    if (key.isEmpty) {
      setState(() {
        _testOk = false;
        _testResult = '请先填写 API Key';
      });
      return;
    }
    setState(() {
      _testing = true;
      _testResult = null;
    });

    // 先用临时设置构造 AIService（无需保存即可测试）
    // v1.28：以当前设置为底 copyWith，避免测试成功后把回答风格等字段冲回默认值
    final temp = appState.settings.copyWith(
      apiKey: key,
      apiEndpoint: _endpointController.text.trim().isEmpty
          ? AppSettings.defaultApiEndpoint
          : _endpointController.text.trim(),
      model: _modelController.text.trim().isEmpty
          ? AppSettings.defaultModel
          : _modelController.text.trim(),
      nickname: _nicknameController.text.trim(),
      analysisDetail: _detail,
      keywordHighlight: _keywordHighlight,
    );
    final svc = AIService(temp);
    try {
      final (ok, msg) = await svc.testConnection();
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testOk = ok;
        _testResult = msg;
      });
      // 测试成功顺带刷新余额显示
      if (ok) {
        await appState.updateSettings(temp);
        if (mounted) _fetchBalance();
      }
    } finally {
      svc.dispose();
    }
  }

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
      setState(() {
        _detail = settings.analysisDetail;
        _keywordHighlight = settings.keywordHighlight;
      });
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
    _endpointFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    // v1.0.2: 未保存修改拦截
    final settings = context.watch<AppState>().settings;
    final dirty = _apiKeyController.text != settings.apiKey ||
        _endpointController.text != settings.apiEndpoint ||
        _modelController.text != settings.model ||
        _nicknameController.text != settings.nickname ||
        _detail != settings.analysisDetail ||
        _keywordHighlight != settings.keywordHighlight;
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
                child: Text('离开',
                    style: TextStyle(color: AppThemeColors.of(context).danger)),
              ),
            ],
          ),
        );
        if (leave == true && mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: ac.background,
        appBar: AppBar(
          title: const Text('设置'),
        ),
      // 平板适配：内容限宽居中（手机无影响）；
      // v1.0.3 宽屏重设计：宽屏限宽自动提升至 1080 + 分组双列并排
      body: ResponsivePage(
        child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Builder(builder: (context) {
          final sections = <Widget>[
            // API 配置卡片
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: ac.surfaceAlt,
                borderRadius: BorderRadius.circular(MaoRadius.control),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.api, color: ac.accent, size: 20),
                      const SizedBox(width: 8),
                      Text('AI 接口配置',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: MaoType.h3, color: ac.textPrimary)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '默认使用 DeepSeek API，填写你的 API Key 即可使用。'
                    '也支持任意 OpenAI 兼容的官方或第三方接口。',
                    style: TextStyle(fontSize: MaoType.body, color: ac.textSecondary),
                  ),
                  const SizedBox(height: MaoSpace.md),

                  // v1.28 预设供应商：一键填入端点 + 模型
                  Text('快速选择服务商',
                      style: TextStyle(
                          fontSize: MaoType.body,
                          fontWeight: FontWeight.w500,
                          color: ac.textPrimary)),
                  const SizedBox(height: MaoSpace.xs),
                  Wrap(
                    spacing: MaoSpace.xs,
                    runSpacing: MaoSpace.xs,
                    children: [
                      for (final p in kApiPresets)
                        InkWell(
                          borderRadius: BorderRadius.circular(MaoRadius.pill),
                          onTap: () => _applyPreset(p),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: MaoSpace.sm + 2, vertical: MaoSpace.xs - 1),
                            decoration: BoxDecoration(
                              color: _isPresetActive(p)
                                  ? ac.accentSoft
                                  : ac.surface,
                              borderRadius:
                                  BorderRadius.circular(MaoRadius.pill),
                              border: Border.all(
                                color: _isPresetActive(p)
                                    ? ac.accent
                                    : ac.border,
                                width: _isPresetActive(p) ? 1.4 : 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (p.isCustom) ...[
                                  Icon(Icons.tune,
                                      size: 13,
                                      color: _isPresetActive(p)
                                          ? ac.accent
                                          : ac.textSecondary),
                                  const SizedBox(width: 4),
                                ],
                                Text(p.name,
                                    style: MaoType.captionStyle.copyWith(
                                      color: _isPresetActive(p)
                                          ? ac.accent
                                          : ac.textSecondary,
                                      fontWeight: _isPresetActive(p)
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                    )),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: MaoSpace.md),

                  // API Key
                  Text('API Key',
                      style: TextStyle(fontSize: MaoType.body, fontWeight: FontWeight.w500, color: ac.textPrimary)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _apiKeyController,
                    obscureText: _obscureKey,
                    decoration: InputDecoration(
                      hintText: 'sk-xxxxxxxxxxxxxxxxxxxxxxxx',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(MaoRadius.small)),
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
                        color: ac.accentSoft.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(MaoRadius.small),
                      ),
                      child: Row(
                        children: [
                          // v1.0.2 设计审查修复：硬编码色 → 主题语义色
                          Icon(Icons.account_balance_wallet, size: 18,
                              color: AppThemeColors.of(context).warning),
                          const SizedBox(width: 8),
                          Text('剩余 ¥${_balance!.toStringAsFixed(2)}',
                              style: TextStyle(fontSize: MaoType.body, fontWeight: FontWeight.w600, color: ac.accent)),
                          if (_estimated > 0) ...[
                            const SizedBox(width: 8),
                            Text('≈ ${_estimated} 题',
                                style: TextStyle(fontSize: MaoType.body, color: ac.accent.withOpacity(0.7))),
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
                        color: ac.danger.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(MaoRadius.small),
                      ),
                      child: Row(
                        children: [
                          // v1.0.2 设计审查修复：硬编码色 → 主题错误色
                          Icon(Icons.warning_amber, size: 16, color: ac.danger),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text('API 余额不足 ¥1，建议尽快充值以免影响使用',
                                style: TextStyle(
                                    fontSize: MaoType.body, color: ac.danger)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // API Endpoint
                  Text('API 地址',
                      style: TextStyle(fontSize: MaoType.body, fontWeight: FontWeight.w500, color: ac.textPrimary)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _endpointController,
                    focusNode: _endpointFocus,
                    // v1.0.2 UI 审查修复：长 API 地址单行截断，
                    // 改为最多 2 行换行完整显示
                    minLines: 1,
                    maxLines: 2,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      hintText: AppSettings.defaultApiEndpoint,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(MaoRadius.small)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                    style: const TextStyle(fontSize: MaoType.body),
                  ),
                  const SizedBox(height: 14),

                  // v1.28 连接测试：填完 Key/地址后可直接验证是否可用
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _testing ? null : _testConnection,
                          icon: _testing
                              ? const SizedBox(
                                  width: 15,
                                  height: 15,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.bolt_outlined, size: 18),
                          label: Text(_testing ? '测试中…' : '测试连接'),
                        ),
                      ),
                    ],
                  ),
                  if (_testResult != null) ...[
                    const SizedBox(height: MaoSpace.xs),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(MaoSpace.sm),
                      decoration: BoxDecoration(
                        color: (_testOk ? ac.success : ac.danger)
                            .withOpacity(0.10),
                        borderRadius: MaoRadius.smallBorder,
                        border: Border.all(
                            color: (_testOk ? ac.success : ac.danger)
                                .withOpacity(0.45)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                              _testOk
                                  ? Icons.check_circle_outline
                                  : Icons.error_outline,
                              size: 17,
                              color: _testOk ? ac.success : ac.danger),
                          const SizedBox(width: MaoSpace.xs),
                          Expanded(
                            child: Text(_testResult!,
                                style: MaoType.captionStyle.copyWith(
                                    color:
                                        _testOk ? ac.success : ac.danger,
                                    height: 1.5)),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),

                  // Model
                  Row(
                    children: [
                      Text('模型名称',
                          style: TextStyle(
                              fontSize: MaoType.body,
                              fontWeight: FontWeight.w500,
                              color: ac.textPrimary)),
                      const Spacer(),
                      // v1.28：从接口拉取模型列表供选择（第三方网关模型名各异，
                      // 手填易错；能拉取的供应商直接点选）
                      TextButton.icon(
                        onPressed: _modelsLoading ? null : _loadModels,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: MaoSpace.xs, vertical: 2),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: _modelsLoading
                            ? const SizedBox(
                                width: 13,
                                height: 13,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.list_alt_rounded, size: 15),
                        label: Text(_modelsLoading ? '拉取中…' : '选择模型',
                            style: MaoType.captionStyle
                                .copyWith(color: ac.accent)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _modelController,
                    decoration: InputDecoration(
                      hintText: AppSettings.defaultModel,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(MaoRadius.small)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                  ),
                  if (_modelsError != null) ...[
                    const SizedBox(height: MaoSpace.xs),
                    Text(_modelsError!,
                        style: MaoType.captionStyle.copyWith(color: ac.danger)),
                  ],
                  if (_modelOptions.isNotEmpty) ...[
                    const SizedBox(height: MaoSpace.sm),
                    // 模型选择：点击即填入（超过 12 个时缩略为可横向滚动）
                    Container(
                      constraints: const BoxConstraints(maxHeight: 168),
                      decoration: BoxDecoration(
                        color: ac.surface,
                        borderRadius: MaoRadius.smallBorder,
                        border: Border.all(
                            color: ac.border, width: MaoShadow.hairline),
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(MaoSpace.xs),
                        child: Wrap(
                          spacing: MaoSpace.xs,
                          runSpacing: MaoSpace.xs,
                          children: [
                            for (final m in _modelOptions)
                              InkWell(
                                borderRadius:
                                    BorderRadius.circular(MaoRadius.pill),
                                onTap: () => setState(() {
                                  _modelController.text = m;
                                  _testResult = null;
                                }),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: MaoSpace.sm,
                                      vertical: MaoSpace.xxs + 1),
                                  decoration: BoxDecoration(
                                    color: _modelController.text.trim() == m
                                        ? ac.accentSoft
                                        : ac.surfaceAlt,
                                    borderRadius:
                                        BorderRadius.circular(MaoRadius.pill),
                                    border: Border.all(
                                      color: _modelController.text.trim() == m
                                          ? ac.accent
                                          : Colors.transparent,
                                    ),
                                  ),
                                  child: Text(m,
                                      style: MaoType.microStyle.copyWith(
                                        color: _modelController.text.trim() == m
                                            ? ac.accent
                                            : ac.textSecondary,
                                        fontWeight:
                                            _modelController.text.trim() == m
                                                ? FontWeight.w600
                                                : FontWeight.w400,
                                      )),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),

                  // v1.0.2 对齐里程碑：昵称（首页专属问候）
                  Text('你的昵称',
                      style: TextStyle(fontSize: MaoType.body, fontWeight: FontWeight.w500, color: ac.textPrimary)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _nicknameController,
                    decoration: InputDecoration(
                      hintText: '设置后，首页会显示对你的专属问候。',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(MaoRadius.small)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                    style: const TextStyle(fontSize: MaoType.body),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // v1.28 AI 回答风格：篇幅档位 + 关键词高亮开关
            // 「先试一下吧，或者在设置里面加一个切换的开关」
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: ac.surfaceAlt,
                borderRadius: BorderRadius.circular(MaoRadius.control),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_awesome, color: ac.accent, size: 20),
                      const SizedBox(width: 8),
                      Text('AI 回答风格',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: MaoType.h3,
                              color: ac.textPrimary)),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // 篇幅档位（三选一）
                  Text('回答详细程度',
                      style: TextStyle(
                          fontSize: MaoType.body,
                          fontWeight: FontWeight.w500,
                          color: ac.textPrimary)),
                  const SizedBox(height: 8),
                  Row(
                    children: AnalysisDetail.values.map((d) {
                      final active = _detail == d;
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                              right: d == AnalysisDetail.values.last ? 0 : 8),
                          child: GestureDetector(
                            onTap: () => setState(() => _detail = d),
                            child: AnimatedContainer(
                              duration: MaoMotion.fast,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: active ? ac.accentSoft : ac.surface,
                                borderRadius:
                                    BorderRadius.circular(MaoRadius.small),
                                border: Border.all(
                                  color: active ? ac.accent : ac.border,
                                  width: active ? 1.4 : 1,
                                ),
                              ),
                              child: Center(
                                child: Text(d.label,
                                    style: TextStyle(
                                      fontSize: MaoType.body,
                                      color: active
                                          ? ac.accent
                                          : ac.textSecondary,
                                      fontWeight: active
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                    )),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 6),
                  Text(_detail.hint,
                      style: TextStyle(
                          fontSize: MaoType.caption,
                          color: ac.textTertiary,
                          height: 1.4)),

                  const SizedBox(height: 14),
                  Divider(height: 1, color: ac.border),

                  // 关键词高亮开关
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _keywordHighlight,
                    onChanged: (v) => setState(() => _keywordHighlight = v),
                    title: Text(_keywordHighlight ? '关键词高亮已开启' : '关键词高亮已关闭',
                        style: TextStyle(
                            fontSize: MaoType.h3, color: ac.textPrimary)),
                    subtitle: Text(
                      '开启后，AI 会用颜色标出决定答案的关键词和易错陷阱，一眼抓重点。',
                      style: TextStyle(
                          fontSize: MaoType.caption,
                          color: ac.textSecondary,
                          height: 1.4),
                    ),
                    secondary: Icon(
                      _keywordHighlight
                          ? Icons.format_color_text
                          : Icons.format_color_reset,
                      color: _keywordHighlight ? ac.accent : ac.textTertiary,
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
                onPressed: () async {
                  final newSettings = context
                      .read<AppState>()
                      .settings
                      .copyWith(
                        apiKey: _apiKeyController.text.trim(),
                        apiEndpoint: _endpointController.text.trim().isEmpty
                            ? AppSettings.defaultApiEndpoint
                            : _endpointController.text.trim(),
                        model: _modelController.text.trim().isEmpty
                            ? AppSettings.defaultModel
                            : _modelController.text.trim(),
                        nickname: _nicknameController.text.trim(),
                        analysisDetail: _detail,
                        keywordHighlight: _keywordHighlight,
                      );
                  // v1.0.2 修复：等待保存完成再提示/返回（此前 fire-and-forget）
                  await context.read<AppState>().updateSettings(newSettings);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('设置已保存'),
                      backgroundColor: ac.accent,
                    ),
                  );
                  Navigator.pop(context);
                },
                child: const Text('保存设置', style: TextStyle(fontSize: MaoType.h3)),
              ),
            ),

            const SizedBox(height: 24),

            // v1.0.2 对齐里程碑：为剩余题目打标签
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: ac.surfaceAlt,
                borderRadius: BorderRadius.circular(MaoRadius.control),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.sell_outlined, color: ac.accent, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('为剩余题目打标签',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: MaoType.h3,
                                color: ac.textPrimary)),
                      ),
                      if (_untaggedCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: ac.danger.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(MaoRadius.small),
                          ),
                          child: Text('$_untaggedCount 题未打标签',
                              style: TextStyle(
                                  fontSize: MaoType.caption, color: ac.danger)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // v1.0.2 对齐里程碑：打标签用途说明
                  Text(
                    '用于：根据错题分析薄弱知识点、错题本按章节分组。按知识点统计错题分布，优先攻克薄弱类型',
                    style: TextStyle(fontSize: MaoType.body, color: ac.textSecondary, height: 1.4),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '部分错题未打知识点标签，可去设置页「为剩余题目打标签」补齐后精炼更准。',
                    style: TextStyle(fontSize: MaoType.body, color: ac.textSecondary, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      icon: const Icon(Icons.auto_awesome, size: 16),
                      label: Text(
                          _untaggedCount > 0 ? '开始打标签' : '暂无未打标签题目',
                          style: const TextStyle(fontSize: MaoType.body)),
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
                color: ac.surfaceAlt,
                borderRadius: BorderRadius.circular(MaoRadius.control),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.music_note, color: ac.accent, size: 20),
                      const SizedBox(width: 8),
                      Text('音效', style: TextStyle(fontWeight: FontWeight.bold, fontSize: MaoType.h3, color: ac.textPrimary)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('答对/答错时播放提示音', style: TextStyle(fontSize: MaoType.body, color: ac.textSecondary)),
                  const SizedBox(height: 8),
                  Consumer<AppState>(
                    builder: (context, appState, _) => SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(appState.settings.soundEnabled ? '音效已开启' : '音效已关闭',
                          style: TextStyle(fontSize: MaoType.body, color: ac.textPrimary)),
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

            // 局域网同步（v11：纯本地、无云端，同一局域网设备间同步）
            Consumer2<AppState, SyncEngine>(
              builder: (context, appState, sync, _) {
                final syncSettings = appState.settings;
                final displayName = syncSettings.deviceName.isEmpty
                    ? DeviceService.instance.defaultDeviceName
                    : syncSettings.deviceName;
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: ac.surfaceAlt,
                    borderRadius: BorderRadius.circular(MaoRadius.control),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.sync, color: ac.accent, size: 20),
                          const SizedBox(width: 8),
                          Text('局域网同步',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: MaoType.h3,
                                  color: ac.textPrimary)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '同一局域网内的设备自动发现并同步题库、刷题记录、错题与批注，'
                        '纯本地传输、无云端。批注按设备各自保留，刷题页只显示本机批注。'
                        '若发现不了设备：确认双方接同一 Wi-Fi、对端应用在前台，'
                        'Windows 首次运行需在防火墙弹窗中允许本应用联网。',
                        style: TextStyle(
                            fontSize: MaoType.body,
                            color: ac.textSecondary,
                            height: 1.4),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                            syncSettings.autoSync ? '自动同步已开启' : '自动同步已关闭',
                            style:
                                TextStyle(fontSize: MaoType.body, color: ac.textPrimary)),
                        subtitle: Text('开启后接入同一局域网自动发现并同步；'
                            '关闭时设备仍可互相发现，用「立即同步」手动触发',
                            style: TextStyle(
                                fontSize: MaoType.caption, color: ac.textSecondary)),
                        value: syncSettings.autoSync,
                        onChanged: (v) async {
                          await appState.updateSettings(
                              syncSettings.copyWith(autoSync: v));
                          // 引擎未启动（如启动时端口失败）在此补启动；
                          // 已启动则只切换广播行为，不重启服务。
                          try {
                            if (!sync.started) {
                              await sync.start(autoSync: v);
                            } else {
                              await sync.applyAutoSync(v);
                            }
                          } catch (_) {}
                        },
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: const Icon(Icons.devices_other, size: 20),
                        title: Text('设备名：$displayName',
                            style: const TextStyle(fontSize: MaoType.body)),
                        trailing: const Icon(Icons.edit, size: 18),
                        onTap: () => _editDeviceName(context, displayName),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        sync.syncing
                            ? '同步中...'
                            : '已发现 ${sync.peers.length} 台设备'
                                '${sync.lastSyncAt != null ? ' · 上次同步 ${_fmtTime(sync.lastSyncAt)}' : ''}'
                                '${sync.statusMessage.isNotEmpty ? '\n${sync.statusMessage}' : ''}',
                        style: TextStyle(
                            fontSize: MaoType.body, color: ac.textSecondary, height: 1.5),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.tonalIcon(
                          icon: sync.syncing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))
                              : const Icon(Icons.sync, size: 16),
                          label: Text(sync.syncing ? '同步中...' : '立即同步',
                              style: const TextStyle(fontSize: MaoType.body)),
                          onPressed: sync.syncing ? null : _syncNow,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            const SizedBox(height: 16),

            // 假期模式（v1.0.2）
            Consumer<AppState>(
              builder: (context, appState, _) {
                final now = DateTime.now();
                return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: ac.surfaceAlt,
                  borderRadius: BorderRadius.circular(MaoRadius.control),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.beach_access, color: ac.danger, size: 20),
                        const SizedBox(width: 8),
                        Text('寒暑假模式',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: MaoType.h3,
                                color: ac.textPrimary)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // v1.0.2 对齐里程碑：寒暑假模式说明文案
                    Text(
                      '作用：开启后暂停每日提醒、错题 FSRS 复习与答题练习，本周战绩日历自动标注假期区间；连击冻结，假期不刷题也不断卡。',
                      style: TextStyle(
                          fontSize: MaoType.body, color: ac.textSecondary, height: 1.4),
                    ),
                    // v1.0.2 修复：提示默认区间为当前自然月，需按实际假期调整
                    Text(
                      '默认区间为当前自然月，请开启后按实际假期调整起止日期。',
                      style: TextStyle(
                          fontSize: MaoType.caption, color: ac.textSecondary.withOpacity(0.8)),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(appState.vacationModeEnabled ? '已开启' : '已关闭',
                          style:
                              TextStyle(fontSize: MaoType.body, color: ac.textPrimary)),
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
                  color: ac.surfaceAlt,
                  borderRadius: BorderRadius.circular(MaoRadius.control),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.notifications_outlined,
                            color: ac.accent, size: 20),
                        const SizedBox(width: 8),
                        // v1.0.2 对齐里程碑：提醒与复习
                        Text('提醒与复习',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: MaoType.h3,
                                color: ac.textPrimary)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // v1.0.2 对齐里程碑：到点会提醒你刷题打卡，保持连胜
                    Text('到点会提醒你刷题打卡，保持连胜',
                        style: TextStyle(
                            fontSize: MaoType.body, color: ac.textSecondary)),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(appState.reminderEnabled ? '已开启' : '已关闭',
                          style:
                              TextStyle(fontSize: MaoType.body, color: ac.textPrimary)),
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
                          style: const TextStyle(fontSize: MaoType.body),
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
                        label: const Text('发送测试通知', style: TextStyle(fontSize: MaoType.body)),
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
                color: ac.surfaceAlt,
                borderRadius: BorderRadius.circular(MaoRadius.control),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.battery_charging_full,
                          color: ac.accent, size: 20),
                      const SizedBox(width: 8),
                      Text('电池优化',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: MaoType.h3,
                              color: ac.textPrimary)),
                      const Spacer(),
                      Icon(
                        _batteryIgnored
                            ? Icons.check_circle
                            : Icons.error_outline,
                        size: 18,
                        color: _batteryIgnored ? ac.accent : ac.danger,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _batteryIgnored ? '电池优化：已豁免' : '电池优化：未豁免',
                    style: TextStyle(
                        fontSize: MaoType.body,
                        color: _batteryIgnored ? ac.accent : ac.danger),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '允许忽略电池优化，防止系统在后台清理每日提醒服务',
                    style:
                        TextStyle(fontSize: MaoType.body, color: ac.textSecondary, height: 1.4),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '若仍收不到提醒：最近任务中长按本应用并锁定',
                    style:
                        TextStyle(fontSize: MaoType.body, color: ac.textSecondary, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.battery_alert, size: 16),
                          label: Text(
                              _batteryIgnored ? '电池优化：已豁免' : '请求忽略电池优化',
                              style: const TextStyle(fontSize: MaoType.caption)),
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
            Text('主题外观', style: TextStyle(fontWeight: FontWeight.bold, fontSize: MaoType.h3, color: ac.textPrimary)),
            const SizedBox(height: 8),
            Consumer<ThemeService>(
              builder: (context, themeService, _) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(children: [
                    ...AppTheme.values.map((t) {
                      final label = ThemeService.labelOf(t);
                      // v1.0.2 UI 审查修复：主题选择行加三色预览
                      // （导航/背景/强调），降低切换决策成本
                      final previews = ThemeService.previewColorsOf(t);
                      return RadioListTile<AppTheme>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Row(
                          children: [
                            ...previews.map((c) => Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: Container(
                                    width: 14,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      color: c,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: ac.textPrimary.withOpacity(0.15),
                                          width: 0.8),
                                    ),
                                  ),
                                )),
                            const SizedBox(width: 6),
                            Text(label, style: const TextStyle(fontSize: MaoType.body)),
                          ],
                        ),
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
            Text('深色模式', style: TextStyle(fontWeight: FontWeight.bold, fontSize: MaoType.h3, color: ac.textPrimary)),
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
                        title: Text(label, style: const TextStyle(fontSize: MaoType.body)),
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
                color: ac.surfaceAlt,
                borderRadius: BorderRadius.circular(MaoRadius.control),
                // v1.0.2 UI 审查修复：星际穿越等主题下卡片与页面背景
                // 对比微弱，加细边框分隔
                border: Border.all(color: ac.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.bug_report, color: ac.textSecondary, size: 20),
                      const SizedBox(width: 8),
                      Text('调试日志',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: MaoType.h3, color: ac.textPrimary)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '开启后记录 AI 渲染链路、答案提交等关键数据，帮助排查前端 Bug。',
                    style: TextStyle(fontSize: MaoType.body, color: ac.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            _debugEnabled ? '日志已开启' : '日志已关闭',
                            style: TextStyle(fontSize: MaoType.body, color: ac.textPrimary),
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
                          // v1.0.2 UI 审查修复：短文案 + 单行 + 紧凑，
                          // 原"导出日志文件"在窄按钮内换行两行
                          label: const Text('导出日志',
                              maxLines: 1,
                              softWrap: false,
                              style: TextStyle(fontSize: MaoType.body)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            visualDensity: VisualDensity.compact,
                          ),
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
                                    backgroundColor: ac.accent,
                                    duration: const Duration(seconds: 4),
                                  ),
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('导出失败: $e'),
                                    backgroundColor: ac.danger,
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
                        label: const Text('清空', style: TextStyle(fontSize: MaoType.body)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: ac.danger,
                        ),
                        onPressed: () {
                          DebugLogService.instance.clear();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text('日志已清空'),
                                backgroundColor: ac.textSecondary,
                              ),
                            );
                          }
                        },
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.share, size: 16),
                        label: const Text('分享', style: TextStyle(fontSize: MaoType.body)),
                        style: OutlinedButton.styleFrom(foregroundColor: ac.accent),
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
                                SnackBar(content: Text('分享失败: $e'), backgroundColor: ac.danger),
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
                color: ac.surfaceAlt,
                borderRadius: BorderRadius.circular(MaoRadius.control),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('使用说明',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: MaoType.h3,
                          color: ac.textPrimary)),
                  const SizedBox(height: 12),
                  _HelpItem(
                    icon: Icons.lock_outline,
                    text: 'API Key 仅保存在本地，不会上传到任何服务器',
                     ac: ac,
                  ),
                  _HelpItem(
                    icon: Icons.shield_outlined,
                    // v1.0.2 设计审查修复：如实说明保护强度（本地混淆存储，非强加密）
                    text: 'API Key 本地混淆存储（防随手翻看，非强加密保护）',
                     ac: ac,
                  ),
                  _HelpItem(
                    icon: Icons.cached,
                    text: 'AI 解析结果会本地缓存，同一道题不会重复消耗 Token',
                     ac: ac,
                  ),
                  _HelpItem(
                    icon: Icons.file_present,
                    text: '支持导入 DOC/DOCX 格式题库文件，自动识别题目和选项',
                     ac: ac,
                  ),
                  _HelpItem(
                    icon: Icons.phone_android,
                    // v1.0.2 只做 Android 端（Windows 平台工程已移除）
                    text: '支持 Android 端使用',
                     ac: ac,
                  ),
                ],
              ),
            ),
          ];
          // 窄屏：单列（原设计）；宽屏：分组交错分左右两列并排（近似平衡）
          if (!isWideLayout(context)) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: sections,
            );
          }
          final left = <Widget>[];
          final right = <Widget>[];
          for (var i = 0; i < sections.length; i++) {
            (i.isEven ? left : right).add(sections[i]);
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: left,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: right,
                ),
              ),
            ],
          );
        }),
      ),
      ),
      ),
    );
  }

  String _fmtTime(DateTime? t) {
    if (t == null) return '20:00';
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  /// 手动「立即同步」：引擎未启动时先补启动，再对已发现设备逐一同步。
  /// 未发现设备时如实提示（双方需在同一网段，对端也需开着本应用）
  Future<void> _syncNow() async {
    final appState = context.read<AppState>();
    final engine = context.read<SyncEngine>();
    if (engine.syncing) return;
    try {
      if (!engine.started) {
        await engine.start(autoSync: appState.settings.autoSync);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('同步服务启动失败：$e')),
      );
      return;
    }
    if (engine.peers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('未发现其他设备：请确认双方接入同一局域网，'
                '且对端应用正在前台运行')),      );
      return;
    }
    final (tried, ok) = await engine.manualSync();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok > 0
            ? '同步完成：$ok/$tried 台设备成功'
            : '同步失败：请检查对端应用是否在前台运行'),
        backgroundColor: ok > 0 ? null : Theme.of(context).colorScheme.error,
      ),
    );
  }

  /// 编辑设备名（空值回落缺省名「猫卷-平台」）
  Future<void> _editDeviceName(BuildContext context, String current) async {
    final controller = TextEditingController(text: current);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('设备名'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '如：我的手机 / 平板',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newName == null || !mounted) return;
    final appState = context.read<AppState>();
    await appState.updateSettings(
        appState.settings.copyWith(deviceName: newName));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(newName.isEmpty
              ? '设备名已恢复缺省值'
              : '设备名已保存：$newName')),
    );
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
    final ac = AppThemeColors.of(context);
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
                        color: failed ? ac.danger : ac.accent),
                    title: Text(q.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: MaoType.caption)),
                    trailing: Text(kp,
                        style: TextStyle(
                            fontSize: MaoType.body,
                            fontWeight: FontWeight.w600,
                            color: failed ? ac.danger : ac.accent)),
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
                    style: TextStyle(fontSize: MaoType.body, color: ac.textSecondary),
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
    final ac = AppThemeColors.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(MaoRadius.small),
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
          borderRadius: BorderRadius.circular(MaoRadius.small),
          border: Border.all(color: ac.border),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today, size: 14, color: ac.accent),
            const SizedBox(width: 8),
            Text(
              value == null
                  ? label
                  : '${value!.year}-${value!.month.toString().padLeft(2, '0')}-${value!.day.toString().padLeft(2, '0')}',
              style: TextStyle(fontSize: MaoType.body, color: ac.textPrimary),
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
  final AppThemeColors ac;

  const _HelpItem({required this.icon, required this.text, required this.ac});

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: ac.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: MaoType.body, color: ac.textSecondary, height: 1.4)),
          ),
        ],
      ),
    );
  }
}
