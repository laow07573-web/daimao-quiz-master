import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/question.dart';
import '../services/app_state.dart';

class ImportPreviewScreen extends StatefulWidget {
  const ImportPreviewScreen({super.key});

  @override
  State<ImportPreviewScreen> createState() => _ImportPreviewScreenState();
}

class _ImportPreviewScreenState extends State<ImportPreviewScreen> {
  int? _editingIndex;

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, _) {
        final questions = appState.previewQuestions;

        return Scaffold(
          backgroundColor: const Color(0xFFF5F7FA),
          appBar: AppBar(
            title: Text('预览: ${appState.previewBankName}'),
            elevation: 0,
            backgroundColor: const Color(0xFF4A90D9),
            foregroundColor: Colors.white,
            actions: [
              TextButton(
                onPressed: () => appState.clearPreview(),
                child: const Text('取消', style: TextStyle(color: Colors.white70)),
              ),
            ],
          ),
          body: questions.isEmpty
              ? const Center(child: Text('解析完成，共 0 道题目'))
              : Column(
                  children: [
                    // 统计栏
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      color: Colors.white,
                      child: Row(
                        children: [
                          _buildStatusBadge(questions),
                          const Spacer(),
                          Text('共 ${questions.length} 题',
                              style: const TextStyle(fontSize: 13, color: Color(0xFF666666))),
                        ],
                      ),
                    ),

                    // 题目列表
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: questions.length,
                        itemBuilder: (context, index) {
                          final q = questions[index];
                          final errors = _validateQuestion(q);
                          final isEditing = _editingIndex == index;

                          if (isEditing) {
                            return _EditCard(
                              question: q,
                              onSave: (updated) {
                                appState.updatePreviewQuestion(index, updated);
                                setState(() => _editingIndex = null);
                              },
                              onCancel: () => setState(() => _editingIndex = null),
                            );
                          }

                          return _QuestionCard(
                            index: index,
                            question: q,
                            errors: errors,
                            onEdit: () => setState(() => _editingIndex = index),
                            onDelete: () => _confirmDelete(index, appState),
                          );
                        },
                      ),
                    ),
                  ],
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
                          backgroundColor: const Color(0xFF5CB85C),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () async {
                          await appState.confirmImport();
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(appState.importStatus),
                              backgroundColor: Colors.green,
                            ),
                          );
                          Navigator.of(context).popUntil((route) => route.isFirst);
                        },
                        child: Text(
                          '确认导入 ${questions.length} 道题目',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }

  Widget _buildStatusBadge(List<Question> questions) {
    int valid = 0, warn = 0;
    for (final q in questions) {
      final errors = _validateQuestion(q);
      if (errors.isEmpty) {
        valid++;
      } else if (!errors.any((e) => e.isError)) {
        warn++;
      }
    }
    final errorCount = questions.length - valid - warn;

    return Row(
      children: [
        if (valid > 0) ...[
          _Badge(text: '$valid 正常', color: const Color(0xFF5CB85C)),
          const SizedBox(width: 8),
        ],
        if (warn > 0) ...[
          _Badge(text: '$warn 需检查', color: const Color(0xFFF0AD4E)),
          const SizedBox(width: 8),
        ],
        if (errorCount > 0)
          _Badge(text: '$errorCount 有问题', color: const Color(0xFFD9534F)),
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
            style: TextButton.styleFrom(foregroundColor: Colors.red),
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
    } else if (q.questionType != 'true_false' &&
        !RegExp(r'^[A-Da-d,]+$').hasMatch(q.correctAnswer)) {
      errors.add(_QuestionError('答案格式异常', false));
    }
    return errors;
  }
}

class _QuestionError {
  final String message;
  final bool isError; // true=error, false=warning
  _QuestionError(this.message, this.isError);
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  const _Badge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text,
          style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
    );
  }
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
    final hasError = errors.any((e) => e.isError);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: hasError
            ? Border.all(color: const Color(0xFFD9534F).withOpacity(0.4))
            : null,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.03),
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
                    color: const Color(0xFF4A90D9).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('第 ${index + 1} 题',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF4A90D9))),
                ),
                const SizedBox(width: 8),
                if (question.questionType == 'multi_choice')
                  _Tag('多选', const Color(0xFFF0AD4E)),
                if (question.questionType == 'true_false')
                  _Tag('判断', const Color(0xFF5CB85C)),
                const Spacer(),
                IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: onEdit),
                const SizedBox(width: 8),
                IconButton(
                    icon: Icon(Icons.delete_outline, size: 18, color: Colors.red[300]),
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
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: question.title.isEmpty ? const Color(0xFFD9534F) : const Color(0xFF333333),
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
                      style: const TextStyle(fontSize: 12, color: Color(0xFF888888)),
                    )).toList(),
              ),
            ),

          // 答案
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: Text(
              '答案: ${question.correctAnswer.isEmpty ? '(未识别)' : question.correctAnswer}',
              style: TextStyle(
                fontSize: 12,
                color: question.correctAnswer.isEmpty
                    ? const Color(0xFFD9534F)
                    : const Color(0xFF5CB85C),
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
                          color: e.isError ? const Color(0xFFD9534F) : const Color(0xFFF0AD4E),
                        ),
                        const SizedBox(width: 4),
                        Text(e.message,
                            style: TextStyle(
                                fontSize: 11,
                                color: e.isError
                                    ? const Color(0xFFD9534F)
                                    : const Color(0xFFF0AD4E))),
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
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(text, style: TextStyle(fontSize: 10, color: color)),
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
  late TextEditingController _optACtrl;
  late TextEditingController _optBCtrl;
  late TextEditingController _optCCtrl;
  late TextEditingController _optDCtrl;
  late TextEditingController _answerCtrl;
  late TextEditingController _analysisCtrl;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.question.title);
    _optACtrl = TextEditingController(text: widget.question.options.isNotEmpty ? widget.question.options[0] : '');
    _optBCtrl = TextEditingController(text: widget.question.options.length > 1 ? widget.question.options[1] : '');
    _optCCtrl = TextEditingController(text: widget.question.options.length > 2 ? widget.question.options[2] : '');
    _optDCtrl = TextEditingController(text: widget.question.options.length > 3 ? widget.question.options[3] : '');
    _answerCtrl = TextEditingController(text: widget.question.correctAnswer);
    _analysisCtrl = TextEditingController(text: widget.question.analysis ?? '');
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _optACtrl.dispose();
    _optBCtrl.dispose();
    _optCCtrl.dispose();
    _optDCtrl.dispose();
    _answerCtrl.dispose();
    _analysisCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF4A90D9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 题干
          const Text('题干', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          TextField(
            controller: _titleCtrl,
            maxLines: 3,
            decoration: InputDecoration(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
              contentPadding: const EdgeInsets.all(10),
              isDense: true,
            ),
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 10),

          // 选项
          Row(
            children: [
              Expanded(child: _optField('A', _optACtrl)),
              const SizedBox(width: 8),
              Expanded(child: _optField('B', _optBCtrl)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _optField('C', _optCCtrl)),
              const SizedBox(width: 8),
              Expanded(child: _optField('D', _optDCtrl)),
            ],
          ),
          const SizedBox(height: 10),

          // 答案
          const Text('正确答案', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          TextField(
            controller: _answerCtrl,
            decoration: InputDecoration(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
              contentPadding: const EdgeInsets.all(10),
              isDense: true,
              hintText: 'A / B / C / D / 对 / 错',
            ),
            style: const TextStyle(fontSize: 13),
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
                    options: [
                      if (_optACtrl.text.trim().isNotEmpty) _optACtrl.text.trim(),
                      if (_optBCtrl.text.trim().isNotEmpty) _optBCtrl.text.trim(),
                      if (_optCCtrl.text.trim().isNotEmpty) _optCCtrl.text.trim(),
                      if (_optDCtrl.text.trim().isNotEmpty) _optDCtrl.text.trim(),
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

  Widget _optField(String label, TextEditingController ctrl) {
    return TextField(
      controller: ctrl,
      decoration: InputDecoration(
        labelText: '选项 $label',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
        contentPadding: const EdgeInsets.all(10),
        isDense: true,
        labelStyle: const TextStyle(fontSize: 12),
      ),
      style: const TextStyle(fontSize: 13),
    );
  }
}
