import '../utils/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/question.dart';
import '../models/question_image.dart';
import '../services/app_state.dart';
import '../services/theme_service.dart';
import '../utils/responsive.dart';
import '../utils/question_image_tokens.dart';
import '../widgets/kit/mj_kit.dart';
import '../widgets/kit/mj_rich_question_text.dart';

class ImportPreviewScreen extends StatefulWidget {
  const ImportPreviewScreen({super.key});

  @override
  State<ImportPreviewScreen> createState() => _ImportPreviewScreenState();
}

class _ImportPreviewScreenState extends State<ImportPreviewScreen> {
  int? _editingIndex;
  bool _confirming = false;
  String? _confirmError;
  // v1.27：顶部统计徽章可点击，点击后列表只展示对应校验分类的题目，
  // 再次点击同一徽章取消筛选。
  _PreviewFilter _filter = _PreviewFilter.all;

  /// 逐题删除的「墓碑」：删除只记下原始下标，确认时从写入快照中排除。
  /// 为什么这么绕：应用层只有按下标移除的 API，题一旦真删，撤销时无法
  /// 插回原位——墓碑方案让撤销只是一次反悔，原始题号与编辑/删除回调永不错位。
  final Set<int> _pendingDeletes = {};

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, _) {
        final questions = appState.previewQuestions;
        // v1.0.2 设计审查修复：整页蓝白硬编码 → 主题色。
        final ac = AppThemeColors.of(context);

        // v1.27：按校验结果分类（统计栏计数 + 徽章点击筛选题目共用）。
        // 保留原始题号，筛选态下编辑/删除回调不错位。
        final classified = <_Classified>[];
        var validCount = 0, warnCount = 0, errorCount = 0;
        for (var i = 0; i < questions.length; i++) {
          // 已删（撤销窗口内）不再参与展示与计数
          if (_pendingDeletes.contains(i)) continue;
          final errors = _validateQuestion(questions[i]);
          final cls = errors.isEmpty
              ? _PreviewFilter.valid
              : (errors.any((e) => e.isError)
                  ? _PreviewFilter.error
                  : _PreviewFilter.warn);
          if (cls == _PreviewFilter.valid) {
            validCount++;
          } else if (cls == _PreviewFilter.warn) {
            warnCount++;
          } else {
            errorCount++;
          }
          classified.add(_Classified(i, questions[i], errors, cls));
        }
        final shown = _filter == _PreviewFilter.all
            ? classified
            : classified.where((c) => c.cls == _filter).toList();
        // 有效题数（含撤销窗口内的删除项）
        final alive = questions.length - _pendingDeletes.length;

        return Scaffold(
          backgroundColor: ac.background,
          appBar: AppBar(
            title: Text('预览: ${appState.previewBankName}'),
            elevation: 0,
            backgroundColor: ac.navBar,
            foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
            actions: [
              TextButton(
                // 解析结果与已做的编辑都要放弃——先确认再动手，防误触全毁
                onPressed: _confirming
                    ? null
                    : () async {
                        final nav = Navigator.of(context);
                        final discard = await MJDialog.show<bool>(
                          context,
                          title: '放弃本次导入？',
                          content: Text('放弃 $alive 道题的解析结果？已做的编辑也会丢失'),
                          actions: [
                            MJButton(
                              label: '继续编辑',
                              kind: MJButtonKind.secondary,
                              dense: true,
                              onPressed: () => Navigator.pop(context, false),
                            ),
                            MJButton(
                              label: '放弃',
                              kind: MJButtonKind.danger,
                              dense: true,
                              onPressed: () => Navigator.pop(context, true),
                            ),
                          ],
                        );
                        if (discard != true || !mounted) return;
                        appState.clearPreview();
                        // v1.0.2 修复：放弃后返回上一页（此前只清数据，停留在死页面）
                        nav.pop();
                      },
                child: Text('取消',
                    style: TextStyle(
                        color: Theme.of(context)
                            .appBarTheme
                            .foregroundColor
                            ?.withOpacity(0.8))),
              ),
            ],
          ),
          // 平板适配：内容限宽居中（手机无影响）
          body: AbsorbPointer(
            absorbing: _confirming,
            child: ResponsivePage(
              child: questions.isEmpty
                  ? Center(
                      child: Text(
                          appState.previewParseErrors.isNotEmpty
                              // v1.0.2 设计审查修复：0 题时展示真实失败原因
                              ? '解析失败\n${appState.previewParseErrors.first}'
                              : '解析完成，共 0 道题目',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: MaoType.body, color: ac.textSecondary)))
                  : Column(
                      children: [
                        if (_confirmError != null)
                          Padding(
                            padding: const EdgeInsets.all(MaoSpace.sm),
                            child: Text(_confirmError!,
                                style: TextStyle(color: ac.danger)),
                          ),
                        // 统计栏（v1.27：徽章可点击筛选对应分类题目）
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: MaoSpace.md, vertical: MaoSpace.xs),
                          color: ac.card,
                          child: Row(
                            children: [
                              _buildStatusBadge(
                                  validCount, warnCount, errorCount),
                              const Spacer(),
                              // v1.27：筛选中提示（再点徽章可取消）
                              if (_filter != _PreviewFilter.all) ...[
                                Text('已筛出 ${shown.length} 题 · 再点徽章可取消',
                                    style: TextStyle(
                                        fontSize: MaoType.caption,
                                        color: ac.textSecondary)),
                                const SizedBox(width: 8),
                              ],
                              Text('共 $alive 题',
                                  style: TextStyle(
                                      fontSize: MaoType.body,
                                      color: ac.textSecondary)),
                            ],
                          ),
                        ),

                        // v1.0.2 设计审查修复：分块解析失败横幅（显性提示，不再伪装成功）
                        if (appState.previewParseErrors.isNotEmpty)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.fromLTRB(
                                MaoSpace.sm, MaoSpace.xs, MaoSpace.sm, 0),
                            padding: const EdgeInsets.all(MaoSpace.sm),
                            decoration: BoxDecoration(
                              color: ac.surfaceAlt,
                              borderRadius: MaoRadius.smallBorder,
                              border: Border.all(
                                  color: ac.border, width: MaoLine.width),
                            ),
                            child: Text(
                              '${appState.previewParseErrors.length} 个分块解析失败（已跳过）：'
                              '${appState.previewParseErrors.join('；')}',
                              style: TextStyle(
                                  fontSize: MaoType.caption,
                                  color: ac.textSecondary),
                            ),
                          ),

                        // v12 配图：待指派图（AI 丢占位符又挂不上题）——显性列出、手动挂题，
                        // 图片必须随题保存，宁可待指派也不静默丢
                        if (appState.previewOrphans.isNotEmpty)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.fromLTRB(
                                MaoSpace.sm, MaoSpace.xs, MaoSpace.sm, 0),
                            padding: const EdgeInsets.all(MaoSpace.sm),
                            decoration: BoxDecoration(
                              color: ac.surfaceAlt,
                              borderRadius: MaoRadius.smallBorder,
                              border: Border.all(
                                  color: ac.border, width: MaoLine.width),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${appState.previewOrphans.length} 张图未能自动归题，请指派到所属题目：',
                                  style: TextStyle(
                                      fontSize: MaoType.caption,
                                      color: ac.textSecondary),
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final e
                                        in appState.previewOrphans.entries)
                                      SizedBox(
                                        width: 140,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      MaoRadius.chip),
                                              child: Image.memory(
                                                  e.value.content,
                                                  height: 56,
                                                  width: double.infinity,
                                                  fit: BoxFit.cover),
                                            ),
                                            DropdownButtonHideUnderline(
                                              child: DropdownButton<int>(
                                                isDense: true,
                                                isExpanded: true,
                                                value: null,
                                                hint: Text('挂到第几题',
                                                    style: TextStyle(
                                                        fontSize: MaoType.micro,
                                                        color:
                                                            ac.textTertiary)),
                                                items: [
                                                  for (var i = 0;
                                                      i < questions.length;
                                                      i++)
                                                    // 已删题不再可挂图（挂了也会随删除丢掉）
                                                    if (!_pendingDeletes
                                                        .contains(i))
                                                      DropdownMenuItem(
                                                          value: i,
                                                          child: Text(
                                                              '第 ${i + 1} 题',
                                                              style: const TextStyle(
                                                                  fontSize: MaoType
                                                                      .micro))),
                                                ],
                                                onChanged: (v) {
                                                  if (v != null) {
                                                    appState
                                                        .assignPreviewOrphan(
                                                            e.key, v);
                                                  }
                                                },
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

                        // 题目列表（v1.27：按徽章筛选展示；题号/编辑/删除用原始序号不错位）
                        Expanded(
                          child: shown.isEmpty
                              ? Center(
                                  child: Text('该分类下暂无题目',
                                      style: TextStyle(
                                          fontSize: MaoType.body,
                                          color: ac.textSecondary)))
                              : ListView.builder(
                                  padding: const EdgeInsets.all(MaoSpace.sm),
                                  itemCount: shown.length,
                                  itemBuilder: (context, si) {
                                    final c = shown[si];
                                    final isEditing =
                                        _editingIndex == c.originalIndex;

                                    if (isEditing) {
                                      return _EditCard(
                                        question: c.question,
                                        onSave: (updated) {
                                          appState.updatePreviewQuestion(
                                              c.originalIndex, updated);
                                          setState(() => _editingIndex = null);
                                        },
                                        onCancel: () => setState(
                                            () => _editingIndex = null),
                                      );
                                    }

                                    return _QuestionCard(
                                      index: c.originalIndex,
                                      question: c.question,
                                      errors: c.errors,
                                      onEdit: () => setState(() =>
                                          _editingIndex = c.originalIndex),
                                      onDelete: () =>
                                          _deleteQuestion(c.originalIndex),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
            ),
          ),

          // 底部确认按钮
          bottomNavigationBar: questions.isEmpty
              ? null
              : SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: ac.success,
                          foregroundColor: ac.onAccent,
                          padding:
                              const EdgeInsets.symmetric(vertical: MaoSpace.sm),
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(MaoRadius.small)),
                        ),
                        onPressed:
                            _confirming || alive == 0 || _editingIndex != null
                                ? null
                                : () => _confirmImport(appState),
                        child: Text(
                          _confirming
                              ? '正在导入…'
                              : '${_confirmError == null ? '确认导入' : '重试导入'} $alive 道题目',
                          style: const TextStyle(fontSize: MaoType.h3),
                        ),
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }

  Future<void> _confirmImport(AppState appState) async {
    if (_confirming) return;
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final ac = AppThemeColors.of(context);
    // 提交期间不再允许撤销改变本次快照。
    messenger.clearSnackBars();
    setState(() {
      _confirming = true;
      _confirmError = null;
    });
    try {
      await appState.confirmImport(excludedIndices: Set.of(_pendingDeletes));
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(appState.importStatus),
        backgroundColor: ac.success,
      ));
      nav.popUntil((route) => route.isFirst);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _confirmError = '导入失败：$error\n编辑和删除状态已保留，请重试。';
      });
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  /// v1.27：统计徽章可点击——点击后列表只展示对应分类题目，
  /// 选中态加深底色+描边；再点同一徽章取消筛选。
  Widget _buildStatusBadge(int valid, int warn, int errors) {
    final ac = AppThemeColors.of(context);
    Widget badge(String text, Color color, _PreviewFilter f) {
      final active = _filter == f;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() {
          _filter = active ? _PreviewFilter.all : f;
        }),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: MaoSpace.xs, vertical: 3),
          decoration: BoxDecoration(
            color: color.withOpacity(active ? 0.16 : 0.07),
            borderRadius: MaoRadius.chipBorder,
            border: Border.all(
                color: active ? color : ac.border, width: MaoLine.width),
          ),
          child: Text(text,
              style: TextStyle(
                  fontSize: MaoType.caption,
                  color: color,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
        ),
      );
    }

    return Row(
      children: [
        if (valid > 0) ...[
          badge('$valid 正常', ac.success, _PreviewFilter.valid),
          const SizedBox(width: 8),
        ],
        if (warn > 0) ...[
          badge('$warn 需检查', ac.warning, _PreviewFilter.warn),
          const SizedBox(width: 8),
        ],
        if (errors > 0) badge('$errors 有问题', ac.danger, _PreviewFilter.error),
      ],
    );
  }

  /// 逐题删除：即删 + SnackBar 撤销（5 秒可恢复）。
  /// 删除用墓碑记录（见 [_pendingDeletes]），撤销只是反悔一次，
  /// 原始题号永不错位；只有导入成功才统一清空预览。
  void _deleteQuestion(int index) {
    final number = index + 1;
    setState(() => _pendingDeletes.add(index));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已删除第 $number 题'),
        // 产品口径：删除后 5 秒内可撤回
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () => setState(() => _pendingDeletes.remove(index)),
        ),
      ),
    );
  }

  List<_QuestionError> _validateQuestion(Question q) {
    final errors = <_QuestionError>[];
    if (q.title.trim().isEmpty) {
      errors.add(_QuestionError('缺少题干', true));
    }
    if (q.correctAnswer.trim().isEmpty) {
      errors.add(_QuestionError('缺少答案', true));
    } else if ((q.questionType == 'single_choice' ||
            q.questionType == 'multi_choice') &&
        // v1.27 修复：选项不止四个（E/F…）时，答案含 A-Z 均为合法，
        // 此前正则只认 A-D 导致五选题被误报「答案格式异常」。
        !RegExp(r'^[A-Za-z,]+$').hasMatch(q.correctAnswer)) {
      // v1.0.2: 答案格式校验只查选择题（填空/名解/简答为文本答案）
      errors.add(_QuestionError('答案格式异常', false));
    }
    return errors;
  }
}

/// v1.27：预览列表筛选分类（全部/正常/需检查/有问题）
enum _PreviewFilter { all, valid, warn, error }

/// 校验分类结果（保留原始题号，筛选态下编辑/删除不错位）
class _Classified {
  final int originalIndex;
  final Question question;
  final List<_QuestionError> errors;
  final _PreviewFilter cls;
  _Classified(this.originalIndex, this.question, this.errors, this.cls);
}

class _QuestionError {
  final String message;
  final bool isError; // true=error, false=warning
  _QuestionError(this.message, this.isError);
}

class _QuestionCard extends StatelessWidget {
  final int index;
  final Question question;
  final List<_QuestionError> errors;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _QuestionCard({
    required this.index,
    required this.question,
    required this.errors,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    // v1.0.2 设计审查修复：硬编码色 → 主题色/语义色
    final ac = AppThemeColors.of(context);
    final hasError = errors.any((e) => e.isError);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: ac.card,
        borderRadius: BorderRadius.circular(MaoRadius.small),
        border: hasError ? Border.all(color: ac.danger.withOpacity(0.4)) : null,
        boxShadow: [
          BoxShadow(
              color: ac.border.withOpacity(0.03),
              blurRadius: 6,
              offset: const Offset(0, 1)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 题号 + 操作按钮
          Padding(
            padding: const EdgeInsets.fromLTRB(
                MaoSpace.sm, MaoSpace.xs, MaoSpace.xxs, 0),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: ac.accent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(MaoRadius.chip),
                  ),
                  child: Text('第 ${index + 1} 题',
                      style: TextStyle(
                          fontSize: MaoType.caption, color: ac.accent)),
                ),
                const SizedBox(width: 8),
                if (question.questionType == 'multi_choice')
                  _Tag('多选', ac.warning),
                if (question.questionType == 'true_false')
                  _Tag('判断', ac.success),
                const Spacer(),
                IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    padding: EdgeInsets.zero,
                    // 触达目标 ≥40×40：图标视觉不变，热区达标
                    constraints:
                        const BoxConstraints(minWidth: 40, minHeight: 40),
                    onPressed: onEdit),
                const SizedBox(width: 8),
                IconButton(
                    icon: Icon(Icons.delete_outline,
                        size: 18, color: ac.danger.withOpacity(0.6)),
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 40, minHeight: 40),
                    onPressed: onDelete),
              ],
            ),
          ),

          // 题干（v12：含图题随占位符位置内联出图——预览要能核对图文归属）
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: MaoSpace.sm, vertical: MaoSpace.xxs),
            child: imageSlotsIn(question.title).isNotEmpty
                ? MjRichQuestionText(
                    text: question.title,
                    images: question.images,
                    // 一屏多题：Hero 分组取原始题号，避免同槽位 tag 撞车
                    heroGroup: 'q$index',
                    style: TextStyle(
                      fontSize: MaoType.body,
                      fontWeight: FontWeight.w500,
                      color: ac.textPrimary,
                    ),
                  )
                : Text(
                    question.title.isEmpty ? '(空题干)' : question.title,
                    style: TextStyle(
                      fontSize: MaoType.body,
                      fontWeight: FontWeight.w500,
                      color:
                          question.title.isEmpty ? ac.danger : ac.textPrimary,
                    ),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
          ),

          // 选项（摘要行放不下内联图：去占位符，含图时给标记）
          if (question.options.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  MaoSpace.sm, 0, MaoSpace.sm, MaoSpace.xxs),
              child: Wrap(
                spacing: 16,
                runSpacing: 2,
                children: [
                  ...question.optionsWithLabels.map((o) => Text(
                        stripImageTokens(o),
                        style: TextStyle(
                            fontSize: MaoType.body, color: ac.textSecondary),
                      )),
                  if (question.options.any((o) => imageSlotsIn(o).isNotEmpty))
                    Text('〔选项含图〕',
                        style: TextStyle(
                            fontSize: MaoType.caption, color: ac.textTertiary)),
                ],
              ),
            ),

          // 答案
          Padding(
            padding: const EdgeInsets.fromLTRB(
                MaoSpace.sm, 0, MaoSpace.sm, MaoSpace.xxs),
            child: Text(
              '答案: ${question.correctAnswer.isEmpty ? '(未识别)' : question.correctAnswer}',
              style: TextStyle(
                fontSize: MaoType.body,
                color: question.correctAnswer.isEmpty ? ac.danger : ac.success,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),

          // 错误提示
          if (errors.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  MaoSpace.sm, 0, MaoSpace.sm, MaoSpace.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: errors
                    .map((e) => Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              e.isError ? Icons.error : Icons.warning_amber,
                              size: 14,
                              color: e.isError ? ac.danger : ac.warning,
                            ),
                            const SizedBox(width: 4),
                            Text(e.message,
                                style: TextStyle(
                                    fontSize: MaoType.caption,
                                    color: e.isError ? ac.danger : ac.warning)),
                          ],
                        ))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final Color color;
  const _Tag(this.text, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(MaoRadius.chip),
      ),
      child:
          Text(text, style: TextStyle(fontSize: MaoType.micro, color: color)),
    );
  }
}

class _EditCard extends StatefulWidget {
  final Question question;
  final void Function(Question) onSave;
  final VoidCallback onCancel;

  const _EditCard({
    required this.question,
    required this.onSave,
    required this.onCancel,
  });

  @override
  State<_EditCard> createState() => _EditCardState();
}

class _EditCardState extends State<_EditCard> {
  late TextEditingController _titleCtrl;
  // v1.27 修复：选项不再写死 A~D 四个——动态控制器列表，
  // 支持任意数量选项（A~Z）的查看、修改、增删。
  late List<TextEditingController> _optCtrls;
  late TextEditingController _answerCtrl;
  late TextEditingController _analysisCtrl;

  /// v12 配图：编辑期持有（删图连同占位符一起移除）
  late List<QuestionImage> _images;

  /// 选择题初始至少展示 4 行选项输入（保持原有手感；判断题无选项时也留 4 行备用）
  static const int _minOptionRows = 4;

  /// 选项上限：标签只支持 A~Z
  static const int _maxOptions = 26;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.question.title);
    final existing = widget.question.options;
    final count =
        existing.length > _minOptionRows ? existing.length : _minOptionRows;
    _optCtrls = [
      for (var i = 0; i < count; i++)
        TextEditingController(text: i < existing.length ? existing[i] : ''),
    ];
    _answerCtrl = TextEditingController(text: widget.question.correctAnswer);
    _analysisCtrl = TextEditingController(text: widget.question.analysis ?? '');
    _images = List.of(widget.question.images);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    for (final c in _optCtrls) {
      c.dispose();
    }
    _answerCtrl.dispose();
    _analysisCtrl.dispose();
    super.dispose();
  }

  /// 选项标签：0→A, 1→B … 25→Z（与 Question.optionsWithLabels 同口径）
  String _optLabel(int i) => String.fromCharCode(65 + i);

  /// 删图：占位符随之从题干/选项/解析移除（图片是题目的一部分）
  void _removeImage(QuestionImage img) {
    final token = '{{img:${img.position}}}';
    setState(() {
      _images = _images.where((i) => i.position != img.position).toList();
      _titleCtrl.text = _titleCtrl.text.replaceAll(token, '');
      for (final c in _optCtrls) {
        c.text = c.text.replaceAll(token, '');
      }
      _analysisCtrl.text = _analysisCtrl.text.replaceAll(token, '');
    });
  }

  void _addOption() {
    if (_optCtrls.length >= _maxOptions) return;
    setState(() => _optCtrls.add(TextEditingController()));
  }

  void _removeOption(int i) {
    if (_optCtrls.length <= 2) return; // 至少保留 2 行选项输入。
    setState(() {
      _optCtrls[i].dispose();
      _optCtrls.removeAt(i);
    });
  }

  @override
  Widget build(BuildContext context) {
    // v1.0.2 设计审查修复：硬编码色 → 主题色
    final ac = AppThemeColors.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(MaoSpace.sm),
      decoration: BoxDecoration(
        color: ac.card,
        borderRadius: BorderRadius.circular(MaoRadius.small),
        border: Border.all(color: ac.accent),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 题干
          const Text('题干',
              style: TextStyle(
                  fontSize: MaoType.body, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          TextField(
            controller: _titleCtrl,
            maxLines: 3,
            decoration: InputDecoration(
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(MaoRadius.chip)),
              contentPadding: const EdgeInsets.all(10),
              isDense: true,
            ),
            style: const TextStyle(fontSize: MaoType.body),
          ),
          const SizedBox(height: 10),

          // v12 配图：图片是题目的一部分（{{img:N}} 位置可在文本里挪，缩略图可删）
          if (_images.isNotEmpty) ...[
            const Text('题目配图',
                style: TextStyle(
                    fontSize: MaoType.body, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final img in _images)
                  SizedBox(
                    width: 64,
                    height: 64,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(MaoRadius.chip),
                            child: Image.memory(img.content, fit: BoxFit.cover),
                          ),
                        ),
                        Positioned(
                          top: 0,
                          right: 0,
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => _removeImage(img),
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              // 图上删除徽标：底取主文字半透明、图标取 surface——
                              // 反转双色在两套主题任意图片上都保持对比，不写死黑白
                              decoration: BoxDecoration(
                                  color: ac.textPrimary.withOpacity(0.55),
                                  shape: BoxShape.circle),
                              child: Icon(Icons.close,
                                  size: 12, color: ac.surface),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
          ],

          // 选项（v1.27：任意数量动态行，每行两个选项，可增删）
          ..._buildOptionRows(),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _optCtrls.length >= _maxOptions ? null : _addOption,
              icon: const Icon(Icons.add, size: 16),
              label: Text(
                  _optCtrls.length >= _maxOptions ? '选项已达上限 (Z)' : '添加选项',
                  style: const TextStyle(fontSize: MaoType.body)),
            ),
          ),
          const SizedBox(height: 6),

          // 答案
          const Text('正确答案',
              style: TextStyle(
                  fontSize: MaoType.body, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          TextField(
            controller: _answerCtrl,
            decoration: InputDecoration(
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(MaoRadius.chip)),
              contentPadding: const EdgeInsets.all(10),
              isDense: true,
              hintText: 'A / B / …（多选逗号分隔） / 对 / 错 / 文本答案',
            ),
            style: const TextStyle(fontSize: MaoType.body),
          ),
          const SizedBox(height: 10),

          // 操作按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: widget.onCancel, child: const Text('取消')),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {
                  widget.onSave(widget.question.copyWith(
                    title: _titleCtrl.text.trim(),
                    // v1.27：收集全部非空选项（不再限四个，选项顺序即标签顺序）
                    options: [
                      for (final c in _optCtrls)
                        if (c.text.trim().isNotEmpty) c.text.trim(),
                    ],
                    correctAnswer: _answerCtrl.text.trim().toUpperCase(),
                    analysis: _analysisCtrl.text.trim().isEmpty
                        ? null
                        : _analysisCtrl.text.trim(),
                    images: _images,
                  ));
                },
                child: const Text('保存'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// v1.27：选项输入动态布局——每行两个选项，行尾可删除（保留至少 2 行）
  List<Widget> _buildOptionRows() {
    final rows = <Widget>[];
    for (var i = 0; i < _optCtrls.length; i += 2) {
      final hasSecond = i + 1 < _optCtrls.length;
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: MaoSpace.xs),
        child: Row(
          children: [
            Expanded(child: _optFieldWithDelete(i)),
            const SizedBox(width: MaoSpace.xs),
            hasSecond
                ? Expanded(child: _optFieldWithDelete(i + 1))
                : const Expanded(child: SizedBox.shrink()),
          ],
        ),
      ));
    }
    return rows;
  }

  Widget _optFieldWithDelete(int i) {
    return Row(
      children: [
        Expanded(child: _optField(_optLabel(i), _optCtrls[i])),
        if (_optCtrls.length > 2)
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            tooltip: '删除选项 ${_optLabel(i)}',
            padding: EdgeInsets.zero,
            // 触达目标 ≥40×40：图标视觉不变，热区达标
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            onPressed: () => _removeOption(i),
          ),
      ],
    );
  }

  Widget _optField(String label, TextEditingController ctrl) {
    return TextField(
      controller: ctrl,
      decoration: InputDecoration(
        labelText: '选项 $label',
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(MaoRadius.chip)),
        contentPadding: const EdgeInsets.all(10),
        isDense: true,
        labelStyle: const TextStyle(fontSize: MaoType.caption),
      ),
      style: const TextStyle(fontSize: MaoType.body),
    );
  }
}
