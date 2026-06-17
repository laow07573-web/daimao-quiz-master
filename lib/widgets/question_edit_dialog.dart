import 'package:flutter/material.dart';
import '../models/question.dart';

class QuestionEditDialog extends StatefulWidget {
  final Question question;
  final void Function(String title, String answer, String? type) onSave;

  const QuestionEditDialog({
    super.key,
    required this.question,
    required this.onSave,
  });

  @override
  State<QuestionEditDialog> createState() => _QuestionEditDialogState();
}

class _QuestionEditDialogState extends State<QuestionEditDialog> {
  late TextEditingController _titleCtrl;
  late TextEditingController _answerCtrl;
  late String? _type;

  static const _types = {
    'single_choice': '单选',
    'multi_choice': '多选',
    'true_false': '判断',
    'fill_blank': '填空',
    'jian_da': '简答',
    'ming_jie': '名解',
  };

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.question.title);
    _answerCtrl = TextEditingController(text: widget.question.correctAnswer);
    _type = widget.question.questionType;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _answerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('编辑题目'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String?>(
              value: _type,
              decoration: const InputDecoration(labelText: '题型', border: OutlineInputBorder()),
              items: _types.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
              onChanged: (v) => setState(() => _type = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _titleCtrl,
              maxLines: 3,
              decoration: const InputDecoration(labelText: '题干', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _answerCtrl,
              maxLines: 2,
              decoration: const InputDecoration(labelText: '答案', border: OutlineInputBorder()),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () {
            widget.onSave(_titleCtrl.text.trim(), _answerCtrl.text.trim(), _type);
            Navigator.pop(context);
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
