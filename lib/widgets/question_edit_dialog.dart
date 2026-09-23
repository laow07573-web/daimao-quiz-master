import 'package:flutter/material.dart';
import '../models/question.dart';
import '../models/question_image.dart';
import '../utils/design_tokens.dart';

class QuestionEditDialog extends StatefulWidget {
  final Question question;

  /// [images] 为编辑后保留的配图：删图即连同题内 `{{img:N}}` 占位符一起移除
  final void Function(
          String title, String answer, String? type, List<QuestionImage> images)
      onSave;

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
  late List<QuestionImage> _images;

  static const _types = {
    'single_choice': '单选',
    'multi_choice': '多选',
    'true_false': '判断',
    'fill_blank': '填空',
    'jian_da': '简答',
    'ming_jie': '名解',
    // v1.0.2 修复：问答型题目编辑不再触发 DropdownButton 断言崩溃
    'jie_da': '问答',
  };

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.question.title);
    _answerCtrl = TextEditingController(text: widget.question.correctAnswer);
    // v1.0.2 修复：未知题型兜底为单选，避免 value 不在 items 中触发断言
    _type = _types.containsKey(widget.question.questionType)
        ? widget.question.questionType
        : 'single_choice';
    _images = List.of(widget.question.images);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _answerCtrl.dispose();
    super.dispose();
  }

  /// 删图：图片是题目的一部分，占位符随之从题干移除（挪图则直接改题干文本）
  void _removeImage(QuestionImage img) {
    setState(() {
      _images = _images.where((i) => i.position != img.position).toList();
      _titleCtrl.text = _titleCtrl.text.replaceAll('{{img:${img.position}}}', '');
    });
  }

  @override
  Widget build(BuildContext context) {
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
            if (_images.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('题目配图 · 题干里 {{img:N}} 标位置，可改文本挪图',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
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
                                borderRadius: MaoRadius.smallBorder,
                                child: Image.memory(img.content, fit: BoxFit.cover),
                              ),
                            ),
                            Positioned(
                              top: 0,
                              right: 0,
                              // 删图角标：视觉维持原小角标不动，热区扩到 40×40
                              //（触达目标下限）——原来可点区域只有十几像素，很难点中
                              child: SizedBox(
                                width: 40,
                                height: 40,
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: () => _removeImage(img),
                                  child: Align(
                                    alignment: Alignment.topRight,
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: const BoxDecoration(
                                          color: Colors.black54,
                                          shape: BoxShape.circle),
                                      child: const Icon(Icons.close,
                                          size: 12, color: Colors.white),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () {
            widget.onSave(_titleCtrl.text.trim(), _answerCtrl.text.trim(), _type,
                _images);
            Navigator.pop(context);
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
