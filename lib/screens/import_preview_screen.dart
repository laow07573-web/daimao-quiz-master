import '../utils/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/question.dart';
import '../services/app_state.dart';
import '../services/theme_service.dart';
import '../utils/responsive.dart';

class ImportPreviewScreen extends StatefulWidget {
  const ImportPreviewScreen({super.key});

  @override
  State<ImportPreviewScreen> createState() => _ImportPreviewScreenState();
}

class _ImportPreviewScreenState extends State<ImportPreviewScreen> {
  int? _editingIndex;
  // v1.27：顶部统计徽章可点击，点击后列表只展示对应校验分类的题目，
  // 再次点击同一徽章取消筛选。
  _PreviewFilter _filter = _PreviewFilter.all;

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

        return Scaffold(
          backgroundColor: ac.background,
          appBar: AppBar(
            title: Text('预览: ${appState.previewBankName}'),
            elevation: 0,
            backgroundColor: ac.navBar,
            foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
            actions: [
              TextButton(
                // v1.0.2 修复：取消后返回上一页（此前只清数据，停留在死页面）
                onPressed: () {
                  appState.clearPreview();
                  Navigator.pop(context);
                },
                child: Text('取消',
                    style: TextStyle(
                        color: Theme.of(context).appBarTheme.foregroundColor
                            ?.withOpacity(0.8))),
              ),
            ],
          ),
          // 平板适配：内容限宽居中（手机无影响）
          body: ResponsivePage(
            child: questions.isEmpty
              ? Center(
                  child: Text(appState.previewParseErrors.isNotEmpty
                      // v1.0.2 设计审查修复：0 题时展示真实失败原因
                      ? '解析失败\n${appState.previewParseErrors.first}'
                      : '解析完成，共 0 道题目',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: MaoType.body, color: ac.textSecondary)))
              : Column(
                  children: [
                    // 统计栏（v1.27：徽章可点击筛选对应分类题目）
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      color: ac.card,
                      child: Row(
                        children: [
                          _buildStatusBadge(validCount, warnCount, errorCount),
                          const Spacer(),
                          // v1.27：筛选中提示（再点徽章可取消）
                          if (_filter != _PreviewFilter.all) ...[
                            Text('已筛出 ${shown.length} 题 · 再点徽章可取消',
                                style: TextStyle(
                                    fontSize: MaoType.caption, color: ac.textSecondary)),
                            const SizedBox(width: 8),
                          ],
                          Text('共 ${questions.length} 题',
                              style: TextStyle(
                                  fontSize: MaoType.body, color: ac.textSecondary)),
                        ],
                      ),
                    ),

                    // v1.0.2 设计审查修复：分块解析失败横幅（显性提示，不再伪装成功）
                    if (appState.previewParseErrors.isNotEmpty)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: ac.warning.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(MaoRadius.small),
                          border: Border.all(color: ac.warning.withOpacity(0.5)),
                        ),
                        child: Text(
                          '${appState.previewParseErrors.length} 个分块解析失败（已跳过）：'
                          '${appState.previewParseErrors.join('；')}',
                          style: TextStyle(fontSize: MaoType.caption, color: ac.textSecondary),
                        ),
                      ),

                    // 题目列表（v1.27：按徽章筛选展示；题号/编辑/删除用原始序号不错位）
                    Expanded(
                      child: shown.isEmpty
                          ? Center(
                              child: Text('该分类下暂无题目',
                                  style: TextStyle(
                                      fontSize: MaoType.body, color: ac.textSecondary)))
                          : ListView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: shown.length,
                              itemBuilder: (context, si) {
                                final c = shown[si];
                                final isEditing = _editingIndex == c.originalIndex;

                                if (isEditing) {
                                  return _EditCard(
                                    question: c.question,
                                    onSave: (updated) {
                                      appState.updatePreviewQuestion(
                                          c.originalIndex, updated);
                                      setState(() => _editingIndex = null);
                                    },
                                    onCancel: () =>
                                        setState(() => _editingIndex = null),
                                  );
                                }

                                return _QuestionCard(
                                  index: c.originalIndex,
                                  question: c.question,
                                  errors: c.errors,
                                  onEdit: () => setState(
                                      () => _editingIndex = c.originalIndex),
                                  onDelete: () =>
                                      _confirmDelete(c.originalIndex, appState),
                                );
                              },
                            ),
                    ),
                  ],
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
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(MaoRadius.small)),
                        ),
                        onPressed: () async {
                          await appState.confirmImport();
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(appState.importStatus),
                              backgroundColor: ac.success,
                            ),
                          );
                          Navigator.of(context).popUntil((route) => route.isFirst);
                        },
                        child: Text(
                          '确认导入 ${questions.length} 道题目',
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
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withOpacity(active ? 0.22 : 0.1),
            borderRadius: BorderRadius.circular(MaoRadius.small),
            border: active ? Border.all(color: color) : null,
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
        if (errors > 0)
          badge('$errors 有问题', ac.danger, _PreviewFilter.error),
      ],
    );
  }

  void _confirmDelete(int index, AppState appState) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除题目'),
        content: const Text('确定要删除这道题吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              appState.removePreviewQuestion(index);
              Navigator.pop(ctx);
            },
            style: TextButton.styleFrom(
                foregroundColor: AppThemeColors.of(ctx).danger),
            child: const Text('删除'),
          ),
        ],
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
        border: hasError
            ? Border.all(color: ac.danger.withOpacity(0.4))
            : null,
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
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: ac.accent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(MaoRadius.chip),
                  ),
                  child: Text('第 ${index + 1} 题',
                      style: TextStyle(fontSize: MaoType.caption, color: ac.accent)),
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
                    constraints: const BoxConstraints(),
                    onPressed: onEdit),
                const SizedBox(width: 8),
                IconButton(
                    icon: Icon(Icons.delete_outline,
                        size: 18, color: ac.danger.withOpacity(0.6)),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: onDelete),
              ],
            ),
          ),

          // 题干
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text(
              question.title.isEmpty ? '(空题干)' : question.title,
              style: TextStyle(
                fontSize: MaoType.body,
                fontWeight: FontWeight.w500,
                color: question.title.isEmpty ? ac.danger : ac.textPrimary,
              ),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // 选项
          if (question.options.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Wrap(
                spacing: 16,
                runSpacing: 2,
                children: question.optionsWithLabels.map((o) => Text(
                      o,
                      style: TextStyle(
                          fontSize: MaoType.body, color: ac.textSecondary),
                    )).toList(),
              ),
            ),

          // 答案
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: Text(
              '答案: ${question.correctAnswer.isEmpty ? '(未识别)' : question.correctAnswer}',
              style: TextStyle(
                fontSize: MaoType.body,
                color: question.correctAnswer.isEmpty
                    ? ac.danger
                    : ac.success,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),

          // 错误提示
          if (errors.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: errors.map((e) => Row(
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
                    )).toList(),
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
      child: Text(text, style: TextStyle(fontSize: MaoType.micro, color: color)),
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ac.card,
        borderRadius: BorderRadius.circular(MaoRadius.small),
        border: Border.all(color: ac.accent),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 题干
          const Text('题干', style: TextStyle(fontSize: MaoType.body, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          TextField(
            controller: _titleCtrl,
            maxLines: 3,
            decoration: InputDecoration(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(MaoRadius.chip)),
              contentPadding: const EdgeInsets.all(10),
              isDense: true,
            ),
            style: const TextStyle(fontSize: MaoType.body),
          ),
          const SizedBox(height: 10),

          // 选项（v1.27：任意数量动态行，每行两个选项，可增删）
          ..._buildOptionRows(),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed:
                  _optCtrls.length >= _maxOptions ? null : _addOption,
              icon: const Icon(Icons.add, size: 16),
              label: Text(
                  _optCtrls.length >= _maxOptions ? '选项已达上限 (Z)' : '添加选项',
                  style: const TextStyle(fontSize: MaoType.body)),
            ),
          ),
          const SizedBox(height: 6),

          // 答案
          const Text('正确答案', style: TextStyle(fontSize: MaoType.body, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          TextField(
            controller: _answerCtrl,
            decoration: InputDecoration(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(MaoRadius.chip)),
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
              TextButton(
                  onPressed: widget.onCancel, child: const Text('取消')),
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
                    analysis: _analysisCtrl.text.trim().isEmpty ? null : _analysisCtrl.text.trim(),
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
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Expanded(child: _optFieldWithDelete(i)),
            const SizedBox(width: 8),
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
            padding: const EdgeInsets.only(left: 2),
            constraints: const BoxConstraints(),
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
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(MaoRadius.chip)),
        contentPadding: const EdgeInsets.all(10),
        isDense: true,
        labelStyle: const TextStyle(fontSize: MaoType.caption),
      ),
      style: const TextStyle(fontSize: MaoType.body),
    );
  }
}
