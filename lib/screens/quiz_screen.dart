import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:provider/provider.dart';
import '../models/question.dart';
import '../services/app_state.dart';
import '../widgets/ai_response_widget.dart';
import '../services/debug_log_service.dart';
import 'session_summary_screen.dart';
import '../widgets/answer_sheet_widget.dart';
import '../widgets/question_edit_dialog.dart';
import 'practice_summary_screen.dart';

enum QuizMode { normal, memorize, practice }

class QuizScreen extends StatefulWidget {
  final QuizMode quizMode;
  const QuizScreen({super.key, this.quizMode = QuizMode.normal});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  final TextEditingController _followUpController = TextEditingController();
  final List<TextEditingController> _fillBlankControllers = [];
  final TextEditingController _textAnswerController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _showManualAnalysis = false;
  String? _followUpResponse;
  bool _followUpLoading = false;
  bool _inErrorBook = false;
  int? _lastQuestionId;
  bool _showAnalysis = false;
  final Set<String> _selectedOptions = {};
  bool _isMemorizeMode = false;
  // 练习模式状态
  final List<PracticeAnswerState> _practiceAnswers = [];
  int _practiceElapsedSeconds = 0;
  DateTime _practiceStartTime = DateTime.now();

  @override
  @override
  void initState() {
    super.initState();
    if (widget.quizMode == QuizMode.practice) _startPracticeTimer();
    if (widget.quizMode == QuizMode.memorize) {
      _isMemorizeMode = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<AppState>().skipFSRS = true;
      });
    }
  }

  void _startPracticeTimer() {
    if (widget.quizMode != QuizMode.practice) return;
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() => _practiceElapsedSeconds = DateTime.now().difference(_practiceStartTime).inSeconds);
      _startPracticeTimer();
    });
  }

  void dispose() {
    _followUpController.dispose();
    for (final c in _fillBlankControllers) { c.dispose(); }
    _fillBlankControllers.clear();
    _textAnswerController.dispose();
    _scrollController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, _) {
        final cs = Theme.of(context).colorScheme;
        final question = appState.currentQuestion;
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

        final isPractice = widget.quizMode == QuizMode.practice;
        if (isPractice && _practiceAnswers.length != appState.quizQuestions.length) {
          _practiceAnswers.clear();
          for (int i = 0; i < appState.quizQuestions.length; i++) {
            _practiceAnswers.add(PracticeAnswerState());
          }
        }
        if (appState.currentQuestion?.id != _lastQuestionId) {
          _showAnalysis = false;
          _lastQuestionId = appState.currentQuestion?.id;
        }

        return Scaffold(
          backgroundColor: cs.surface,
          appBar: AppBar(
            title: Text(
                '第 ${appState.currentQuestionIndex + 1}/${appState.quizQuestions.length} 题'),
            actions: [
              if (!isPractice)
                IconButton(
                  icon: const Icon(Icons.edit, size: 18),
                  tooltip: '编辑此题',
                  onPressed: () => _showEditDialog(context, appState),
                ),
              if (isPractice)
                IconButton(
                  icon: const Icon(Icons.list_alt, size: 20),
                  tooltip: '答题卡',
                  onPressed: () => _showAnswerSheet(context, appState, cs),
                ),
              if (widget.quizMode != QuizMode.memorize)
                IconButton(
                  icon: Icon(_isMemorizeMode ? Icons.visibility_off : Icons.visibility, size: 20),
                  tooltip: _isMemorizeMode ? '切回刷题' : '背题模式',
                  onPressed: () => setState(() => _isMemorizeMode = !_isMemorizeMode),
                ),
              if (widget.quizMode == QuizMode.memorize)
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('结束', style: TextStyle(color: Colors.white70)),
                ),
            ],
          ),
          body: Column(
            children: [
              // 进度条
              TweenAnimationBuilder<double>(
                tween: Tween(
                  begin: 0,
                  end: (appState.currentQuestionIndex + (isAnswered ? 1 : 0)) /
                      appState.quizQuestions.length,
                ),
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeInOut,
                builder: (context, value, _) {
                  return LinearProgressIndicator(
                    value: value,
                    backgroundColor: cs.surfaceContainerHighest,
                    color: cs.primary,
                    minHeight: 4,
                  );
                },
              ),

              // 滚动区域
              Expanded(
                child: GestureDetector(
                  onHorizontalDragEnd: (details) {
                    if (details.primaryVelocity == null) return;
                    if (details.primaryVelocity! < -300) {
                      if (_isMemorizeMode || isAnswered) {
                        _advanceQuestion(appState);
                      }
                    } else if (details.primaryVelocity! > 300) {
                      if (appState.hasPrevious) {
                        _showAnalysis = false;
                        _showManualAnalysis = false;
                        _followUpController.clear();
                        _followUpResponse = null;
                        appState.previousQuestion();
                        _scrollController.jumpTo(0);
                      }
                    }
                  },
                  child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    transitionBuilder: (Widget child, Animation<double> animation) {
                      return SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0.25, 0),
                          end: Offset.zero,
                        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                        child: FadeTransition(opacity: animation, child: child),
                      );
                    },
                    child: Column(
                      key: ValueKey(question.id),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildQuestionCard(question, appState, cs),
                        const SizedBox(height: 16),
                        if (_isMemorizeMode)
                          _buildMemorizeOptions(question, cs, appState)
                        else if (!isAnswered)
                          ...[_buildOptionsArea(appState, question, cs)]
                        else ...[
                          _buildAnsweredResult(appState, question, cs),
                          const SizedBox(height: 12),
                          _buildResultFeedback(appState, question, cs),
                          const SizedBox(height: 8),
                          if (_showAnalysis || appState.currentAnalysis != null)
                            _buildAnalysisArea(appState, question, cs)
                          else
                            _buildShowAnalysisButton(appState, cs),
                          if (appState.currentAnalysis != null) ...[
                            const SizedBox(height: 4),
                            _buildRegenerateButton(appState, cs),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
            ),
          ),

              // 底部按钮：已答或背题模式均显示
              if (isAnswered || widget.quizMode == QuizMode.memorize) _buildBottomBar(appState, cs),
            ],
          ),
        );
      },
    );
  }

  /// 背题模式：选项中高亮正确选项
  Widget _buildMemorizeOptions(Question question, ColorScheme cs, AppState appState) {
    final options = question.questionType == 'true_false' ? ['对', '错'] : question.options;
    if (options.isEmpty) {
      return Container(
        width: double.infinity, padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF4CAF50))),
        child: Text('正确答案: ${question.correctAnswer}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF2E7D32))),
      );
    }
    final correctSet = question.questionType == 'multi_choice' ? question.correctAnswer.split(',').map((e) => e.trim().toUpperCase()).toSet() : {question.correctAnswer.toUpperCase().trim()};
    return Column(children: List.generate(options.length, (i) {
      final label = question.questionType == 'true_false' ? (i == 0 ? '对' : '错') : String.fromCharCode(65 + i);
      final isCorrect = correctSet.contains(question.questionType == 'true_false' ? (i == 0 ? '对' : '错') : label);
      return Padding(padding: const EdgeInsets.only(bottom: 8), child: Container(
        width: double.infinity, padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: isCorrect ? const Color(0xFFE8F5E9) : Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: isCorrect ? const Color(0xFF4CAF50) : cs.outlineVariant)),
        child: Row(children: [
          Container(width: 26, height: 26, decoration: BoxDecoration(color: isCorrect ? const Color(0xFF4CAF50) : cs.surfaceContainerHighest, shape: BoxShape.circle), child: Center(child: isCorrect ? const Icon(Icons.check, size: 14, color: Colors.white) : Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF999999))))),
          const SizedBox(width: 12),
          Expanded(child: Text(options[i], style: TextStyle(fontSize: 14, color: isCorrect ? const Color(0xFF2E7D32) : cs.onSurface, height: 1.4))),
        ]),
      ));
    }));
  }

  Widget _buildMemorizeAnswer(Question question, ColorScheme cs) {
    final correct = question.correctAnswer;
    final qt = question.questionType;
    String display;
    if (qt == 'true_false') {
      display = correct == '对' ? '✓ 正确' : '✗ 错误';
    } else if (qt == 'single_choice' || qt == 'multi_choice') {
      display = correct;
    } else {
      display = correct;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.primary.withOpacity(0.15), cs.primary.withOpacity(0.05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.primary.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          const Icon(Icons.lightbulb_outline, color: Color(0xFFF0AD4E), size: 24),
          const SizedBox(height: 8),
          const Text('参考答案',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFFF0AD4E))),
          const SizedBox(height: 12),
          Text(display,
              style: TextStyle(fontSize: 16, height: 1.6, color: cs.onSurface, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center),
          if (question.analysis != null && question.analysis!.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Text(question.analysis!,
                style: TextStyle(fontSize: 13, height: 1.5, color: cs.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }

  Widget _buildQuestionCard(Question question, AppState appState, ColorScheme cs) {
    final stats = appState.currentQuestionStats;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  question.questionType == 'multi_choice' ? '多选' :
                  question.questionType == 'fill_blank' ? '填空' :
                  question.questionType == 'true_false' ? '判断' :
                  question.questionType == 'ming_jie' ? '名解' :
                  question.questionType == 'jian_da' ? '简答' :
                  question.questionType == 'jie_da' ? '问答' : '单选',
                  style: TextStyle(fontSize: 12, color: cs.primary),
                ),
              ),
              const Spacer(),
              if (stats.isNotEmpty)
                Text(
                  '作答${stats['total']}次  正确率${stats['total']! > 0 ? ((stats['correct']! / stats['total']!) * 100).toStringAsFixed(0) : 0}%',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(question.title,
              style: TextStyle(fontSize: 16, height: 1.6, fontWeight: FontWeight.w500, color: cs.onSurface)),
        ],
      ),
    );
  }

  Widget _buildOptionsArea(AppState appState, Question question, ColorScheme cs) {
    final qt = question.questionType;
    if (qt == 'fill_blank') {
      return _buildFillBlankInput(appState, cs);
    }
    if (qt == 'true_false') {
      return _buildTrueFalseButtons(appState, cs);
    }
    if (qt == 'ming_jie' || qt == 'jian_da' || qt == 'jie_da') {
      return _buildTextAnswerInput(appState, cs, qt);
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
            HapticFeedback.selectionClick();
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
              _handleSubmitAnswer(appState, label);
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: selected ? cs.primary.withOpacity(0.08) : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? cs.primary : cs.outlineVariant,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: selected ? cs.primary : cs.primary.withOpacity(0.12),
                    shape: isMulti ? BoxShape.rectangle : BoxShape.circle,
                    borderRadius: isMulti ? BorderRadius.circular(4) : null,
                  ),
                  child: Center(
                    child: selected
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: cs.primary, fontSize: 14)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(option, style: TextStyle(fontSize: 15, height: 1.4, color: cs.onSurface)),
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
                backgroundColor: _selectedOptions.isEmpty ? cs.surfaceContainerHighest : cs.primary,
                foregroundColor: _selectedOptions.isEmpty ? cs.onSurfaceVariant : cs.onPrimary,
              ),
              onPressed: _selectedOptions.isEmpty ? null : () {
                final answer = _selectedOptions.toList()..sort();
                _selectedOptions.clear();
                _handleSubmitAnswer(appState, answer.join(','));
              },
            ),
          ),
        ],
      );
    }

    return Column(children: optionWidgets);
  }

  Widget _buildFillBlankInput(AppState appState, ColorScheme cs) {
    final title = appState.currentQuestion?.title ?? '';
    final blankCount = RegExp(r'_{2,}|（\s*）|\(\s*\)').allMatches(title).length;
    final n = blankCount > 0 ? blankCount : 1;

    // 清理超过当前题目的旧控制器
    while (_fillBlankControllers.length > n) {
      _fillBlankControllers.removeLast().dispose();
    }
    while (_fillBlankControllers.length < n) {
      _fillBlankControllers.add(TextEditingController());
    }

    return Column(
      children: [
        for (int i = 0; i < n; i++) ...[
          TextField(
            controller: _fillBlankControllers[i],
            decoration: InputDecoration(
              hintText: n == 1 ? '请输入答案...' : '第 ${i + 1} 空',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              prefixIcon: const Icon(Icons.edit),
            ),
            style: TextStyle(fontSize: 15, color: cs.onSurface),
            onSubmitted: (v) => _submitFillBlank(appState),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.check),
            label: const Text('提交答案'),
            onPressed: () => _submitFillBlank(appState),
          ),
        ),
      ],
    );
  }

  Widget _buildTextAnswerInput(AppState appState, ColorScheme cs, String type) {
    final label = type == 'ming_jie' ? '名解' : type == 'jian_da' ? '简答' : '问答';
    return Column(
      children: [
        TextField(
          controller: _textAnswerController,
          maxLines: 6,
          decoration: InputDecoration(
            hintText: '请输入$label答案...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            alignLabelWithHint: true,
          ),
          style: TextStyle(fontSize: 15, color: cs.onSurface),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.check),
            label: const Text('提交答案'),
            onPressed: () {
              final answer = _textAnswerController.text.trim();
              if (answer.isEmpty) return;
              _textAnswerController.clear();
              _handleSubmitAnswer(appState, answer);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTrueFalseButtons(AppState appState, ColorScheme cs) {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => _handleSubmitAnswer(appState, '对'),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.tertiary),
              ),
              child: const Center(
                child: Text('✓  正确',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF5CB85C))),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: () => _handleSubmitAnswer(appState, '错'),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.error),
              ),
              child: const Center(
                child: Text('✗  错误',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFD9534F))),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _submitFillBlank(AppState appState) {
    final answer = _fillBlankControllers
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .join('；');
    if (answer.isEmpty) return;
    for (final c in _fillBlankControllers) { c.clear(); }
    _handleSubmitAnswer(appState, answer);
  }

  Future<void> _handleSubmitAnswer(AppState appState, String answer) async {
    await appState.submitAnswer(answer);
    if (!mounted) return;
    final record = appState.lastAnswerRecord;
    if (record != null) {
      if (record.isCorrect) {
        HapticFeedback.lightImpact();
        _playSound('correct.wav', appState);
      } else {
        HapticFeedback.mediumImpact();
        _playSound('wrong.wav', appState);
      }
    }
    if (record != null && record.isCorrect && !appState.isLastQuestion) {
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) {
        _advanceQuestion(appState);
      }
    }
  }

  void _playSound(String asset, AppState appState) {
    if (!appState.settings.soundEnabled) return;
    try {
      _audioPlayer.play(AssetSource(asset));
    } catch (_) {}
  }

  void _showEditDialog(BuildContext context, AppState appState) {
    final q = appState.currentQuestion;
    if (q == null) return;
    showDialog(
      context: context,
      builder: (ctx) => QuestionEditDialog(
        question: q,
        onSave: (title, answer, type) {
          appState.updateCurrentQuestion(title, answer, type);
        },
      ),
    );
  }

  void _showAnswerSheet(BuildContext context, AppState appState, ColorScheme cs) {
    showModalBottomSheet(
      context: context,
      builder: (_) => AnswerSheetWidget(
        answers: _practiceAnswers,
        currentIndex: appState.currentQuestionIndex,
        onJumpTo: (i) {
          Navigator.pop(context);
          while (appState.currentQuestionIndex > i && appState.hasPrevious) {
            appState.previousQuestion();
          }
          while (appState.currentQuestionIndex < i && !appState.isLastQuestion) {
            appState.nextQuestion();
          }
        },
      ),
    );
  }

  String _formatSeconds(int total) {
    final m = total ~/ 60;
    final s = total % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _showPracticeSubmitDialog(BuildContext context, int blankCount) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('存在未作答题目'),
        content: Text('还有 $blankCount 道题未作答，确定提交？\n\n空白题将不计入正确率。'),
        actions: [
          TextButton(onPressed: () { Navigator.pop(ctx); _jumpToFirstBlank(); }, child: const Text('继续作答')),
          FilledButton(onPressed: () { Navigator.pop(ctx); _submitPractice(context.read<AppState>()); }, child: const Text('直接提交')),
        ],
      ),
    );
  }

  void _jumpToFirstBlank() {
    final appState = context.read<AppState>();
    for (int i = 0; i < _practiceAnswers.length; i++) {
      if (!_practiceAnswers[i].answered) {
        while (appState.currentQuestionIndex > i && appState.hasPrevious) appState.previousQuestion();
        while (appState.currentQuestionIndex < i) appState.nextQuestion();
        return;
      }
    }
  }

  Future<void> _submitPractice(AppState appState) async {
    await appState.endSession();
    final correct = _practiceAnswers.where((a) => a.answered && a.correct).length;
    final wrong = _practiceAnswers.where((a) => a.answered && !a.correct).length;
    final blank = _practiceAnswers.where((a) => !a.answered).length;
    _audioPlayer.dispose();
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(
      builder: (_) => PracticeSummaryScreen(correct: correct, wrong: wrong, blank: blank, elapsedSeconds: _practiceElapsedSeconds),
    ));
  }

  void _advanceQuestion(AppState appState) {
    _showAnalysis = false;
    _showManualAnalysis = false;
    _followUpController.clear();
    _followUpResponse = null;
    appState.nextQuestion();
    _scrollController.jumpTo(0);
  }

  Widget _buildAnsweredResult(AppState appState, Question question, ColorScheme cs) {
    final qt = question.questionType;
    if (qt == 'fill_blank' || qt == 'true_false') {
      final lastRecord = appState.lastAnswerRecord;
      final userAnswer = lastRecord?.userAnswer ?? '';
      final correctAnswer = question.correctAnswer;
      final isCorrect = lastRecord?.isCorrect ?? false;

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isCorrect ? cs.tertiaryContainer : cs.errorContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isCorrect ? cs.tertiary : cs.error),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(isCorrect ? Icons.check_circle : Icons.cancel,
                    color: isCorrect ? cs.tertiary : cs.error, size: 20),
                const SizedBox(width: 8),
                Text(isCorrect ? '回答正确' : '回答错误',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: isCorrect ? cs.onTertiaryContainer : cs.onErrorContainer)),
              ],
            ),
            const SizedBox(height: 10),
            if (qt == 'fill_blank') ...[
              Text('你的答案: $userAnswer',
                  style: TextStyle(fontSize: 14, color: isCorrect ? cs.onTertiaryContainer : cs.onErrorContainer)),
              if (!isCorrect) ...[
                const SizedBox(height: 4),
                Text('正确答案: $correctAnswer',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: cs.tertiary)),
              ],
            ],
            if (qt == 'true_false') ...[
              Text('你选择了: ${userAnswer == "对" ? "✓ 正确" : "✗ 错误"}',
                  style: TextStyle(fontSize: 14, color: isCorrect ? cs.onTertiaryContainer : cs.onErrorContainer)),
              if (!isCorrect)
                Text('正确答案: ${correctAnswer == "对" ? "✓ 正确" : "✗ 错误"}',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: cs.tertiary)),
            ],
          ],
        ),
      );
    }
    return _buildAnsweredOptions(appState, question, cs);
  }

  Widget _buildAnsweredOptions(AppState appState, Question question, ColorScheme cs) {
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

        Color bgColor = cs.surfaceContainerHighest;
        Color textColor = cs.onSurface;
        Color borderColor = cs.outlineVariant;
        if (isCorrect) {
          bgColor = cs.tertiaryContainer;
          textColor = cs.onTertiaryContainer;
          borderColor = cs.tertiary;
        } else if (isUserWrong) {
          bgColor = cs.errorContainer;
          textColor = cs.onErrorContainer;
          borderColor = cs.error;
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              children: [
                Container(
                  width: 26, height: 26,
                  decoration: BoxDecoration(
                    color: isCorrect ? cs.tertiary : isUserWrong ? cs.error : cs.outlineVariant,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: isCorrect ? const Icon(Icons.check, size: 14, color: Colors.white)
                        : isUserWrong ? const Icon(Icons.close, size: 14, color: Colors.white)
                        : Text(label, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: cs.onSurfaceVariant)),
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

  Widget _buildResultFeedback(AppState appState, Question question, ColorScheme cs) {
    final lastRecord = appState.lastAnswerRecord;
    if (lastRecord == null) return const SizedBox.shrink();
    final correct = question.correctAnswer;
    final user = lastRecord.userAnswer;
    DebugLogService.instance.logResultFeedback(correct, user ?? 'null');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('正确答案: $correct',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: cs.tertiary)),
        const SizedBox(height: 4),
        Text('你的答案: $user',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: cs.error)),
      ],
    );
  }

  Widget _buildShowAnalysisButton(AppState appState, ColorScheme cs) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        icon: const Icon(Icons.psychology, size: 18),
        label: const Text('查看 AI 解析'),
        onPressed: () {
          setState(() => _showAnalysis = true);
          appState.showAnalysis();
        },
      ),
    );
  }

  Widget _buildRegenerateButton(AppState appState, ColorScheme cs) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        icon: const Icon(Icons.refresh, size: 16),
        label: const Text('重新生成解析', style: TextStyle(fontSize: 13)),
        style: OutlinedButton.styleFrom(
          foregroundColor: cs.onSurfaceVariant,
          padding: const EdgeInsets.symmetric(vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: () => appState.regenerateAnalysis(),
      ),
    );
  }

  Widget _buildAnalysisArea(AppState appState, Question question, ColorScheme cs) {
    final lastRecord = appState.lastAnswerRecord;
    final isCorrect = lastRecord?.isCorrect ?? false;

    if (isCorrect && !_showManualAnalysis) {
      return GestureDetector(
        onTap: () {
          setState(() => _showManualAnalysis = true);
          appState.showAnalysis();
        },
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lightbulb_outline, color: cs.onSurfaceVariant, size: 18),
              const SizedBox(width: 8),
              Text('查看AI解析',
                  style: TextStyle(color: cs.primary, fontSize: 14)),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.psychology_outlined,
                  color: cs.primary, size: 20),
              const SizedBox(width: 8),
              Text('AI解析',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: cs.primary)),
              const Spacer(),
              if (appState.analysisLoading)
                SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary)),
            ],
          ),
          const SizedBox(height: 10),
          if (appState.currentAnalysis != null)
            AiResponseWidget(text: appState.currentAnalysis!)
          else if (appState.analysisLoading)
            Text('正在生成AI解析...',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14))
          else
            Text('解析生成失败',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14)),

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
            if (_followUpLoading)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary)),
                    const SizedBox(width: 8),
                    Text('AI 正在回复...', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
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
                    color: cs.primary.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: AiResponseWidget(text: _followUpResponse!, fontSize: 12),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomBar(AppState appState, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        boxShadow: [
          BoxShadow(
              color: cs.shadow.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, -2)),
        ],
      ),
      child: appState.isLastQuestion
          ? SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  if (widget.quizMode == QuizMode.memorize) { Navigator.pop(context); }
                  else { _handleEndSession(context, appState); }
                },
                child: Text(
                    widget.quizMode == QuizMode.memorize ? '回到首页' : '完成刷题，查看小结',
                    style: const TextStyle(fontSize: 16)),
              ),
            )
          : Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: Icon(_inErrorBook ? Icons.bookmark : Icons.bookmark_border, size: 17),
                    label: Text(_inErrorBook ? '已收藏' : '错题本', style: const TextStyle(fontSize: 13)),
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
                if (appState.hasPrevious) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.arrow_back, size: 18),
                      label: const Text('上一题', style: TextStyle(fontSize: 14)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: cs.onSurfaceVariant,
                      ),
                      onPressed: () {
                        _showAnalysis = false;
                        _showManualAnalysis = false;
                        _followUpController.clear();
                        _followUpResponse = null;
                        appState.previousQuestion();
                        _scrollController.jumpTo(0);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _advanceQuestion(appState),
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
}
