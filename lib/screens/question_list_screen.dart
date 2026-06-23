import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../models/question.dart';
import '../widgets/question_edit_dialog.dart';

class QuestionListScreen extends StatelessWidget {
  final int bankId;
  final String bankName;
  final List<Question> questions;

  const QuestionListScreen({
    super.key,
    required this.bankId,
    required this.bankName,
    required this.questions,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('$bankName - 题目列表')),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: questions.length,
        itemBuilder: (context, index) {
          final q = questions[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(_typeLabel(q.questionType),
                            style: TextStyle(fontSize: 11, color: cs.onPrimaryContainer)),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.edit, size: 18),
                        onPressed: () => _editQuestion(context, q),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(q.title, style: TextStyle(fontSize: 14, color: cs.onSurface)),
                  const SizedBox(height: 4),
                  Text('答案: ${q.correctAnswer}',
                      style: TextStyle(fontSize: 12, color: cs.secondary)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _typeLabel(String type) {
    const map = {
      'single_choice': '单选', 'multi_choice': '多选', 'true_false': '判断',
      'fill_blank': '填空', 'jian_da': '简答', 'ming_jie': '名解', 'jie_da': '问答',
    };
    return map[type] ?? type;
  }

  void _editQuestion(BuildContext context, Question q) {
    showDialog(
      context: context,
      builder: (ctx) => QuestionEditDialog(
        question: q,
        onSave: (title, answer, type) {
          context.read<AppState>().updateCurrentQuestion(title, answer, type);
        },
      ),
    );
  }
}
