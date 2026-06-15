import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/question.dart';
import '../services/app_state.dart';
import '../widgets/ai_response_widget.dart';
import 'session_summary_screen.dart';

class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  final TextEditingController _followUpController = TextEditingController();
  final TextEditingController _fillBlankController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _showManualAnalysis = false;
  String? _followUpResponse;
  bool _followUpLoading = false;
  bool _inErrorBook = false;
  int? _lastQuestionId;
  bool _showAnalysis = false;
  final Set<String> _selectedOptions = {};

  @override
  void dispose() {
    _followUpController.dispose();
    _fillBlankController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, _) {
        final question = appState.currentQuestion;
        // 检查错题本状态
        if (question?.id != null) {
          appState.isInErrorBook(question!.id!).then((inBook) {
            if (mounted && _inErrorBook != inBook) {
              setState(() => _inErrorBook = inBook);
            }
          });
        }

        if (question == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('刷题中')),
            body: const Center(child: Text('加载题目中...')),
          );
        }

        final lastRecord = appState.lastAnswerRecord;
        final isAnswered = lastRecord != null;

        // Reset analysis display on question change
        if (appState.currentQuestion?.id != _lastQuestionId) {
          _showAnalysis = false;
          _lastQuestionId = appState.currentQuestion?.id;
        }

        return Scaffold(
          backgroundColor: const Color(0xFFF5F7FA),
          appBar: AppBar(
            title: Text(
                '第 ${appState.currentQuestionIndex + 1}/${appState.quizQuestions.length} 题'),
            elevation: 0,
            backgroundColor: const Color(0xFF4A90D9),
            foregroundColor: Colors.white,
            actions: [
              if (isAnswered && !appState.isLastQuestion)
                TextButton(
                  onPressed: () => _handleEndSession(context, appState),
                  child:
                      const Text('结束', style: TextStyle(color: Colors.white70)),
                ),
            ],
          ),
          body: Column(
            children: [
              // 进度条
              LinearProgressIndicator(
                value: (appState.currentQuestionIndex + 1) /
                    appState.quizQuestions.length,
                backgroundColor: Colors.grey[200],
                color: const Color(0xFF4A90D9),
                minHeight: 4,
              ),

              // 滚动区域
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildQuestionCard(question, appState),
                      const SizedBox(height: 16),
                      if (!isAnswered)
                        ...[_buildOptionsArea(appState, question)]
                      else ...[
                        _buildAnsweredOptions(appState, question),
                        const SizedBox(height: 12),
                        _buildResultFeedback(appState, question),
                        const SizedBox(height: 8),
                        if (_showAnalysis || appState.currentAnalysis != null)
                          _buildAnalysisArea(appState, question)
                        else
                          _buildShowAnalysisButton(appState),
                        if (appState.currentAnalysis != null) ...[
                          const SizedBox(height: 4),
                          _buildRegenerateButton(appState),
                        ],
                      ],
                    ],
                  ),
                ),
              ),

              // 底部按钮
              if (isAnswered) _buildBottomBar(appState),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQuestionCard(Question question, AppState appState) {
    final stats = appState.currentQuestionStats;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 题型标签 + 统计
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF4A90D9).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  question.questionType == 'multi_choice' ? '多选' :
                  question.questionType == 'fill_blank' ? '填空' :
                  question.questionType == 'true_false' ? '判断' : '单选',
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF4A90D9)),
                ),
              ),
              const Spacer(),
              if (stats.isNotEmpty)
                Text(
                  '作答${stats['total']}次  正确率${stats['total']! > 0 ? ((stats['correct']! / stats['total']!) * 100).toStringAsFixed(0) : 0}%',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(question.title,
              style:
                  const TextStyle(fontSize: 16, height: 1.6, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildOptionsArea(AppState appState, Question question) {
    if (question.questionType == 'fill_blank') {
      return _buildFillBlankInput(appState);
    }
    final options = question.options;
    final isMulti = question.questionType == 'multi_choice';

    final optionWidgets = options.asMap().entries.map((entry) {
      final int idx = entry.key;
      final option = entry.value;
      final label = String.fromCharCode(65 + idx);
      final selected = _selectedOptions.contains(label);

      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: GestureDetector(
          onTap: () {
            if (isMulti) {
              setState(() {
                if (selected) {
                  _selectedOptions.remove(label);
                } else {
                  _selectedOptions.add(label);
                }
              });
            } else {
              _selectedOptions.clear();
              appState.submitAnswer(label);
            }
          },
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: selected ? const Color(0xFF4A90D9).withOpacity(0.08) : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? const Color(0xFF4A90D9) : const Color(0xFFE0E0E0),
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: selected ? const Color(0xFF4A90D9) : const Color(0xFF4A90D9).withOpacity(0.1),
                    shape: isMulti ? BoxShape.rectangle : BoxShape.circle,
                    borderRadius: isMulti ? BorderRadius.circular(4) : null,
                  ),
                  child: Center(
                    child: selected
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF4A90D9), fontSize: 14)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(option, style: const TextStyle(fontSize: 15, height: 1.4)),
                ),
              ],
            ),
          ),
        ),
      );
    }).toList();

    if (isMulti) {
      return Column(
        children: [
          ...optionWidgets,
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.check_circle),
              label: Text('确认提交 (已选${_selectedOptions.length}项)', style: const TextStyle(fontSize: 15)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _selectedOptions.isEmpty ? const Color(0xFFCCCCCC) : const Color(0xFF4A90D9),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _selectedOptions.isEmpty ? null : () {
                final answer = _selectedOptions.toList()..sort();
                _selectedOptions.clear();
                appState.submitAnswer(answer.join(','));
              },
            ),
          ),
        ],
      );
    }

    return Column(children: optionWidgets);
  }

  Widget _buildFillBlankInput(AppState appState) {
    return Column(
      children: [
        TextField(
          controller: _fillBlankController,
          decoration: InputDecoration(
            hintText: '请输入答案...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            prefixIcon: const Icon(Icons.edit),
          ),
          style: const TextStyle(fontSize: 15),
          onSubmitted: (v) => _submitFillBlank(appState),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.check),
            label: const Text('提交答案'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4A90D9),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => _submitFillBlank(appState),
          ),
        ),
      ],
    );
  }

  void _submitFillBlank(AppState appState) {
    final answer = _fillBlankController.text.trim();
    if (answer.isEmpty) return;
    _fillBlankController.clear();
    appState.submitAnswer(answer);
  }

  Widget _buildTrueFalseButtons(AppState appState) {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => appState.submitAnswer('对'),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF5CB85C)),
              ),
              child: const Center(
                child: Text('✓  正确',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF5CB85C))),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: () => appState.submitAnswer('错'),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFD9534F)),
              ),
              child: const Center(
                child: Text('✗  错误',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFD9534F))),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 答题后选项：显示三态（普通/用户错/正确）
  Widget _buildAnsweredOptions(AppState appState, Question question) {
    final lastRecord = appState.lastAnswerRecord;
    final userAnswer = lastRecord?.userAnswer ?? '';
    final correctAnswer = question.correctAnswer.toUpperCase().trim();
    final isMulti = question.questionType == 'multi_choice';
    final userAnswers = isMulti ? userAnswer.split(',').map((e) => e.trim().toUpperCase()).toSet() : {userAnswer.toUpperCase().trim()};
    final correctAnswers = isMulti ? correctAnswer.split(',').map((e) => e.trim().toUpperCase()).toSet() : {correctAnswer};

    final options = question.options;
    if (options.isEmpty) return const SizedBox.shrink();

    return Column(
      children: options.asMap().entries.map((entry) {
        final idx = entry.key;
        final label = String.fromCharCode(65 + idx);
        final isCorrect = correctAnswers.contains(label);
        final isUserWrong = !isCorrect && userAnswers.contains(label);

        Color bgColor = Colors.white;
        Color textColor = const Color(0xFF333333);
        Color borderColor = const Color(0xFFE0E0E0);
        if (isCorrect) {
          bgColor = const Color(0xFFE8F5E9);
          textColor = const Color(0xFF2E7D32);
          borderColor = const Color(0xFF4CAF50);
        } else if (isUserWrong) {
          bgColor = const Color(0xFFFFEBEE);
          textColor = const Color(0xFFC62828);
          borderColor = const Color(0xFFEF5350);
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              children: [
                Container(
                  width: 26, height: 26,
                  decoration: BoxDecoration(
                    color: isCorrect ? const Color(0xFF4CAF50) : isUserWrong ? const Color(0xFFEF5350) : const Color(0xFFE0E0E0),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: isCorrect ? const Icon(Icons.check, size: 14, color: Colors.white)
                        : isUserWrong ? const Icon(Icons.close, size: 14, color: Colors.white)
                        : Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF999999))),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(entry.value,
                    style: TextStyle(fontSize: 14, color: textColor, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  /// 结果反馈：两行加粗正确/用户答案
  Widget _buildResultFeedback(AppState appState, Question question) {
    final lastRecord = appState.lastAnswerRecord;
    if (lastRecord == null) return const SizedBox.shrink();
    final correct = question.correctAnswer;
    final user = lastRecord.userAnswer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('正确答案: ',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF2E7D32))),
        const SizedBox(height: 4),
        Text('你的答案: ',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFFC62828))),
      ],
    );
  }

  /// 查看解析按钮
  Widget _buildShowAnalysisButton(AppState appState) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        icon: const Icon(Icons.psychology, size: 18),
        label: const Text('查看 AI 解析'),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF4A90D9),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onPressed: () {
          setState(() => _showAnalysis = true);
          appState.showAnalysis();
        },
      ),
    );
  }

  /// 重新生成解析按钮
  Widget _buildRegenerateButton(AppState appState) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        icon: const Icon(Icons.refresh, size: 16),
        label: const Text('重新生成解析', style: TextStyle(fontSize: 13)),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF999999),
          padding: const EdgeInsets.symmetric(vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: () => appState.regenerateAnalysis(),
      ),
    );
  }

  Widget _buildAnalysisArea(AppState appState, Question question) {
    final lastRecord = appState.lastAnswerRecord;
    final isCorrect = lastRecord?.isCorrect ?? false;

    // 做对的题，默认不展示解析，除非手动点击查看
    if (isCorrect && !_showManualAnalysis) {
      return GestureDetector(
        onTap: () {
          setState(() => _showManualAnalysis = true);
          appState.showAnalysis();
        },
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE0E0E0)),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lightbulb_outline, color: Color(0xFF999999), size: 18),
              SizedBox(width: 8),
              Text('查看AI解析',
                  style: TextStyle(color: Color(0xFF4A90D9), fontSize: 14)),
            ],
          ),
        ),
      );
    }

    // 显示AI解析
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 8,
              offset: const Offset(0, 1)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.psychology_outlined,
                  color: Color(0xFF4A90D9), size: 20),
              const SizedBox(width: 8),
              const Text('AI解析',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Color(0xFF4A90D9))),
              const Spacer(),
              if (appState.analysisLoading)
                const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          const SizedBox(height: 10),
          if (appState.currentAnalysis != null)
            AiResponseWidget(text: appState.currentAnalysis!)
          else if (appState.analysisLoading)
            const Text('正在生成AI解析...',
                style: TextStyle(color: Color(0xFF999999), fontSize: 14))
          else
            const Text('解析生成失败',
                style: TextStyle(color: Color(0xFF999999), fontSize: 14)),

          // 追问区域
          if (appState.currentAnalysis != null &&
              appState.currentAnalysis!.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _followUpController,
                    decoration: InputDecoration(
                      hintText: '追问AI相关问题...',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.send, size: 16),
                  label: const Text('追问', style: TextStyle(fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4A90D9),
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onPressed: () async {
                    final q = _followUpController.text.trim();
                    if (q.isEmpty) return;
                    _followUpController.clear();
                    setState(() {
                      _followUpLoading = true;
                      _followUpResponse = null;
                    });
                    final resp = await appState.askFollowUp(q);
                    setState(() {
                      _followUpLoading = false;
                      _followUpResponse = resp;
                    });
                  },
                ),
              ],
            ),
            // 追问回复
            if (_followUpLoading)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 8),
                    Text('AI 正在回复...', style: TextStyle(fontSize: 13, color: Color(0xFF999999))),
                  ],
                ),
              ),
            if (_followUpResponse != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4A90D9).withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _buildFollowUpContent(_followUpResponse!),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomBar(AppState appState) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -2)),
        ],
      ),
      child: appState.isLastQuestion
          ? SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4A90D9),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => _handleEndSession(context, appState),
                child: const Text('完成刷题，查看小结',
                    style: TextStyle(fontSize: 16)),
              ),
            )
          : Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: Icon(_inErrorBook ? Icons.bookmark : Icons.bookmark_border, size: 17),
                    label: Text(_inErrorBook ? '已收藏' : '错题本', style: const TextStyle(fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF4A90D9),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () async {
                      final q = appState.currentQuestion;
                      if (q?.id != null) {
                        await appState.toggleErrorBook(q!.id!);
                        if (mounted) {
                          final inBook = await appState.isInErrorBook(q.id!);
                          setState(() => _inErrorBook = inBook);
                        }
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4A90D9),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      _showAnalysis = false;
                      _showManualAnalysis = false;
                      _followUpController.clear();
                      appState.nextQuestion();
                      _scrollController.jumpTo(0);
                    },
                    child: const Text('下一题', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _handleEndSession(
      BuildContext context, AppState appState) async {
    final session = await appState.endSession();
    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => SessionSummaryScreen(session: session),
      ),
    );
  }

  Widget _buildFollowUpContent(String raw) {
    return AiResponseWidget(text: raw, fontSize: 12);
  }
}
