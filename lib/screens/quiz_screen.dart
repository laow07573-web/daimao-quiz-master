import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:provider/provider.dart';
import '../models/question.dart';
import '../services/app_state.dart';
import '../services/quiz_service.dart';
import '../widgets/ai_response_widget.dart';
import '../services/debug_log_service.dart';
import 'session_summary_screen.dart';
import '../widgets/answer_sheet_widget.dart';
import '../widgets/question_edit_dialog.dart';
import 'practice_screen.dart';

enum QuizMode { normal, memorize, practice }

/// 统一答题页（v1.0.2 重构：三模式共用一套结构）
/// - normal：答完即判 + 自动跳题 + 解析/收藏/重新作答；末题左滑结束会话回首页
/// - memorize：背题模式，只看答案不落库；末题左滑直接回首页（不接入小结）
/// - practice：练习模式，自由跳题 + 答题卡 + 计时（限时自动交卷）+ 批量提交
class QuizScreen extends StatefulWidget {
  final QuizMode quizMode;
  final PracticeTiming? practiceTiming; // 练习：限时/不限时
  final int practiceDurationMinutes; // 练习限时分钟数

  const QuizScreen({
    super.key,
    this.quizMode = QuizMode.normal,
    this.practiceTiming,
    this.practiceDurationMinutes = 0,
  });

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  final TextEditingController _followUpController = TextEditingController();
  final List<TextEditingController> _fillBlankControllers = [];
  // v1.0.2 完善：填空逐空回车跳转下一空
  final List<FocusNode> _fillBlankFocusNodes = [];
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
  // 练习模式状态（v1.0.2 统一重构：练习能力内聚于本页）
  final List<PracticeAnswerState> _practiceAnswers = [];
  final Map<int, String> _practiceAnswersMap = {};
  int _elapsedSeconds = 0;
  int _remainingSeconds = 0;
  Timer? _practiceTimer;
  bool _practiceSubmitted = false;
  bool _modalOpen = false; // 挡路弹窗标记（答题卡/提交确认）
  // v1.0.2 修复：提交防重（双击不产生重复作答记录）
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    if (widget.quizMode == QuizMode.memorize) {
      _isMemorizeMode = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<AppState>().skipFSRS = true;
      });
    }
    if (widget.quizMode == QuizMode.practice) {
      if (widget.practiceTiming == PracticeTiming.timed) {
        _remainingSeconds = widget.practiceDurationMinutes * 60;
      }
      _startPracticeTimer();
    }
  }

  void _startPracticeTimer() {
    _practiceTimer?.cancel();
    _practiceTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _practiceSubmitted) return;
      setState(() {
        _elapsedSeconds++;
        if (widget.practiceTiming == PracticeTiming.timed) {
          _remainingSeconds--;
          if (_remainingSeconds <= 0) {
            // 限时归零自动交卷：先关闭挡路弹窗
            if (_modalOpen) {
              Navigator.of(context).pop();
              _modalOpen = false;
            }
            _submitPractice(context.read<AppState>());
          }
        }
      });
    });
  }

  String _fmtTime(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  /// 限时练习剩余 10%（60~300s 下限）进入红色警告态
  bool get _isPracticeTimeWarn {
    if (widget.practiceTiming != PracticeTiming.timed) return false;
    final total = widget.practiceDurationMinutes * 60;
    if (total <= 0) return false;
    final warnSec = (total * 0.1).ceil().clamp(60, 300);
    return _remainingSeconds > 0 && _remainingSeconds <= warnSec;
  }

  void dispose() {
    // v1.0.2: 背题模式 dispose 复位 skipFSRS（防泄漏到后续会话）
    try {
      final appState = context.read<AppState>();
      if (appState.skipFSRS) appState.skipFSRS = false;
    } catch (_) {}
    _practiceTimer?.cancel();
    _followUpController.dispose();
    for (final c in _fillBlankControllers) { c.dispose(); }
    _fillBlankControllers.clear();
    for (final f in _fillBlankFocusNodes) { f.dispose(); }
    _fillBlankFocusNodes.clear();
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
        if (question == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('刷题中')),
            body: const Center(child: Text('加载题目中...')),
          );
        }

        final lastRecord = appState.lastAnswerRecord;
        // v1.0.2 统一重构：练习模式"已答"按练习答案表判断（可随时修改，不判定）
        final isPractice = widget.quizMode == QuizMode.practice;
        final isAnswered = isPractice
            ? _practiceAnswersMap.containsKey(appState.currentQuestionIndex)
            : lastRecord != null;

        if (isPractice && _practiceAnswers.length != appState.quizQuestions.length) {
          _practiceAnswers.clear();
          for (int i = 0; i < appState.quizQuestions.length; i++) {
            _practiceAnswers.add(PracticeAnswerState());
          }
        }
        if (appState.currentQuestion?.id != _lastQuestionId) {
          // v1.0.2: 切题清空作答残留（多选状态/填空草稿/简答草稿/追问状态）
          _showAnalysis = false;
          _showManualAnalysis = false;
          _selectedOptions.clear();
          for (final c in _fillBlankControllers) {
            c.clear();
          }
          _textAnswerController.clear();
          _followUpController.clear();
          _followUpResponse = null;
          _followUpLoading = false;
          _lastQuestionId = appState.currentQuestion?.id;
          // v1.0.2 修复：错题本状态移出 build，改在切题时一次性查询
          final qid = appState.currentQuestion?.id;
          if (qid != null) {
            appState.isInErrorBook(qid).then((inBook) {
              if (mounted && _inErrorBook != inBook) {
                setState(() => _inErrorBook = inBook);
              }
            });
          }
        }

        return PopScope(
          // v1.0.2 修复：系统返回键不再产生未结束的幽灵会话
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _handleExit(appState);
          },
          child: Scaffold(
            backgroundColor: cs.surface,
          appBar: AppBar(
            title: Text(
                '第 ${appState.currentQuestionIndex + 1}/${appState.quizQuestions.length} 题'),
            actions: [
              // v1.0.2 统一重构：练习模式计时徽标
              if (isPractice)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: (_isPracticeTimeWarn)
                            ? cs.error
                            : cs.primary.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        widget.practiceTiming == PracticeTiming.timed
                            ? '剩余 ${_fmtTime(_remainingSeconds)}'
                            : '已用 ${_fmtTime(_elapsedSeconds)}',
                        style: TextStyle(
                          fontSize: _isPracticeTimeWarn ? 14 : 12,
                          fontWeight: FontWeight.bold,
                          color: _isPracticeTimeWarn
                              ? Colors.white
                              : cs.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
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
                  onPressed: () => _handleExit(appState),
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
                      // 练习自由前进；刷题/背题需已作答才前进
                      if (isPractice || _isMemorizeMode || isAnswered) {
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
                        // v1.0.2 统一重构：练习模式选项区恒可修改（不显示判定结果）
                        if (_isMemorizeMode)
                          _buildMemorizeOptions(question, cs, appState)
                        else if (isPractice || !isAnswered)
                          ...[_buildOptionsArea(appState, question, cs)]
                        else ...[
                          _buildAnsweredResult(appState, question, cs),
                          const SizedBox(height: 12),
                          _buildResultFeedback(appState, question, cs),
                          // v1.0.2 完善：已答题目可重新作答（更新原记录，不新增）
                          if (isAnswered &&
                              widget.quizMode != QuizMode.memorize &&
                              !isPractice) ...[
                            const SizedBox(height: 4),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                icon: const Icon(Icons.edit_outlined, size: 15),
                                label: const Text('重新作答',
                                    style: TextStyle(fontSize: 12)),
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  foregroundColor: cs.onSurfaceVariant,
                                ),
                                onPressed: () {
                                  _selectedOptions.clear();
                                  for (final c in _fillBlankControllers) {
                                    c.clear();
                                  }
                                  _textAnswerController.clear();
                                  _showAnalysis = false;
                                  _showManualAnalysis = false;
                                  appState.resetCurrentAnswer();
                                },
                              ),
                            ),
                          ],
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
        ),
      );
      },
    );
  }

  /// v1.0.2 修复：统一退出路径（系统返回键/结束按钮）。
  /// 有作答 → 正常结束会话；无作答（练习/背题未作答）→ 放弃会话不落库
  Future<void> _handleExit(AppState appState) async {
    final isPractice = widget.quizMode == QuizMode.practice;
    final hint = isPractice
        ? '退出后本次练习记录将不保存。'
        : (appState.hasSessionAnswers
            ? '本次刷题进度将结束并计入统计。'
            : '尚未作答任何题目，退出后不产生记录。');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出刷题'),
        content: Text(hint),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('继续刷题'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      if (isPractice || !appState.hasSessionAnswers) {
        await appState.abortSession();
      } else {
        await appState.endSession();
      }
    } catch (_) {}
    if (!mounted) return;
    Navigator.pop(context);
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
    final isPractice = widget.quizMode == QuizMode.practice;
    // 练习模式已选内容（可修改）
    final practiceAnswer = _practiceAnswersMap[appState.currentQuestionIndex] ?? '';
    final practiceSel = isMulti
        ? practiceAnswer.split(',').where((e) => e.isNotEmpty).toSet()
        : {practiceAnswer};

    final optionWidgets = options.asMap().entries.map((entry) {
      final int idx = entry.key;
      final option = entry.value;
      final label = String.fromCharCode(65 + idx);
      final selected =
          isPractice ? practiceSel.contains(label) : _selectedOptions.contains(label);

      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            if (isPractice) {
              // v1.0.2 统一重构：练习只记录答案，不提交不判定
              setState(() {
                if (isMulti) {
                  final x = practiceSel.toSet();
                  x.contains(label) ? x.remove(label) : x.add(label);
                  _practiceAnswersMap[appState.currentQuestionIndex] =
                      (x.toList()..sort()).join(',');
                } else {
                  _practiceAnswersMap[appState.currentQuestionIndex] = label;
                }
                _syncPracticeSheet(appState);
              });
              return;
            }
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

    // v1.0.2 统一重构：练习模式多选点击即存（无确认按钮），正常模式需确认提交
    if (isMulti && !isPractice) {
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

    // 清理超过当前题目的旧控制器/焦点
    while (_fillBlankControllers.length > n) {
      _fillBlankControllers.removeLast().dispose();
    }
    while (_fillBlankControllers.length < n) {
      _fillBlankControllers.add(TextEditingController());
    }
    while (_fillBlankFocusNodes.length > n) {
      _fillBlankFocusNodes.removeLast().dispose();
    }
    while (_fillBlankFocusNodes.length < n) {
      _fillBlankFocusNodes.add(FocusNode());
    }

    return Column(
      children: [
        for (int i = 0; i < n; i++) ...[
          TextField(
            controller: _fillBlankControllers[i],
            focusNode: _fillBlankFocusNodes[i],
            decoration: InputDecoration(
              hintText: n == 1 ? '请输入答案...' : '第 ${i + 1} 空',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              prefixIcon: const Icon(Icons.edit),
            ),
            style: TextStyle(fontSize: 15, color: cs.onSurface),
            // v1.0.2 完善：回车跳到下一空，最后一空提交
            onSubmitted: (v) {
              if (i < n - 1) {
                _fillBlankFocusNodes[i + 1].requestFocus();
              } else {
                _submitFillBlank(appState);
              }
            },
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
    final isPractice = widget.quizMode == QuizMode.practice;
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
              if (isPractice) {
                // v1.0.2 统一重构：练习只记录答案
                setState(() {
                  _practiceAnswersMap[appState.currentQuestionIndex] = answer;
                  _syncPracticeSheet(appState);
                });
                return;
              }
              _handleSubmitAnswer(appState, answer);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTrueFalseButtons(AppState appState, ColorScheme cs) {
    final isPractice = widget.quizMode == QuizMode.practice;
    final cur = _practiceAnswersMap[appState.currentQuestionIndex] ?? '';
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () {
              if (isPractice) {
                setState(() {
                  _practiceAnswersMap[appState.currentQuestionIndex] = '对';
                  _syncPracticeSheet(appState);
                });
                return;
              }
              _handleSubmitAnswer(appState, '对');
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isPractice && cur == '对'
                    ? cs.tertiary.withOpacity(0.15)
                    : cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: isPractice && cur == '对' ? cs.tertiary : cs.tertiary),
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
            onTap: () {
              if (isPractice) {
                setState(() {
                  _practiceAnswersMap[appState.currentQuestionIndex] = '错';
                  _syncPracticeSheet(appState);
                });
                return;
              }
              _handleSubmitAnswer(appState, '错');
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isPractice && cur == '错'
                    ? cs.error.withOpacity(0.12)
                    : cs.surfaceContainerHighest,
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
    // v1.0.2: 填空提交要求所有空填满（与逐空判定一致）
    final texts = _fillBlankControllers.map((c) => c.text.trim()).toList();
    if (texts.any((t) => t.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('还有空未填写')),
      );
      return;
    }
    final answer = texts.join('；');
    for (final c in _fillBlankControllers) { c.clear(); }
    if (widget.quizMode == QuizMode.practice) {
      // v1.0.2 统一重构：练习只记录答案
      setState(() {
        _practiceAnswersMap[appState.currentQuestionIndex] = answer;
        _syncPracticeSheet(appState);
      });
      return;
    }
    _handleSubmitAnswer(appState, answer);
  }

  Future<void> _handleSubmitAnswer(AppState appState, String answer) async {
    if (_submitting) return; // v1.0.2 修复：双击防重
    _submitting = true;
    try {
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
        // v1.0.2 修复：600ms 延迟自动跳题前比对题号，
        // 用户在窗口内手动跳题时不重复跳转（避免跳过中间题）
        final answeredIndex = appState.currentQuestionIndex;
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted && appState.currentQuestionIndex == answeredIndex) {
          _advanceQuestion(appState);
        }
      }
    } catch (e) {
      // v1.0.2 完善：提交异常（如数据库写入失败）不崩溃页面，提示后重试
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('提交失败：$e')),
      );
    } finally {
      _submitting = false;
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
    _modalOpen = true;
    showModalBottomSheet(
      context: context,
      builder: (_) => AnswerSheetWidget(
        answers: _practiceAnswers,
        currentIndex: appState.currentQuestionIndex,
        // v1.0.2 统一重构：练习模式答题卡只显示已答/未答（提交前不判定对错）
        showResult: widget.quizMode != QuizMode.practice,
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
    ).then((_) => _modalOpen = false);
  }

  /// v1.0.2 统一重构：同步练习答题卡状态（已答/未答）
  void _syncPracticeSheet(AppState appState) {
    final i = appState.currentQuestionIndex;
    if (i < _practiceAnswers.length) {
      _practiceAnswers[i].answered =
          _practiceAnswersMap.containsKey(i);
    }
  }

  /// v1.0.2 统一重构：末题左滑处理
  /// - normal：结束会话（落统计）直接回首页，不经过小结页
  /// - memorize：背题零落库，直接回首页
  /// - practice：触发提交确认
  Future<void> _handleFinishSwipe(AppState appState) async {
    if (widget.quizMode == QuizMode.memorize) {
      if (!mounted) return;
      Navigator.pop(context);
      return;
    }
    if (widget.quizMode == QuizMode.practice) {
      _showSubmit(appState);
      return;
    }
    try {
      await appState.endSession();
    } catch (_) {}
    if (!mounted) return;
    Navigator.pop(context);
  }

  void _advanceQuestion(AppState appState) {
    if (appState.isLastQuestion) {
      // v1.0.2 统一重构：最后一题继续左滑 = 完成
      _handleFinishSwipe(appState);
      return;
    }
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
        onPressed: () {
          // v1.0.2: API 未配置拦截重新生成
          if (!appState.settings.isConfigured) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('请先在设置中配置 API Key 后再查看解析。'),
                  backgroundColor: Colors.orange),
            );
            return;
          }
          appState.regenerateAnalysis();
        },
      ),
    );
  }

  Widget _buildAnalysisArea(AppState appState, Question question, ColorScheme cs) {
    final lastRecord = appState.lastAnswerRecord;
    final isCorrect = lastRecord?.isCorrect ?? false;

    if (isCorrect && !_showManualAnalysis) {
      return GestureDetector(
        onTap: () {
          // v1.0.2: API 未配置拦截解析请求
          if (!appState.settings.isConfigured) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('请先在设置中配置 API Key 后再查看解析。'),
                  backgroundColor: Colors.orange),
            );
            return;
          }
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
                    // v1.0.2: API 未配置拦截追问（对齐里程碑：后再追问）
                    if (!appState.settings.isConfigured) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('请先在设置中配置 API Key 后再追问。'),
                            backgroundColor: Colors.orange),
                      );
                      return;
                    }
                    final q = _followUpController.text.trim();
                    if (q.isEmpty) return;
                    _followUpController.clear();
                    setState(() {
                      _followUpLoading = true;
                      _followUpResponse = null;
                    });
                    final resp = await appState.askFollowUp(q);
                    if (!mounted) return; // v1.0.2 修复：页面已退出不再 setState
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
    // v1.0.2 统一重构：练习模式底部栏（自由跳题 + 提交练习）
    if (widget.quizMode == QuizMode.practice) {
      final answered = _practiceAnswersMap.length;
      final total = appState.quizQuestions.length;
      return Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
        decoration: BoxDecoration(
          color: cs.surface,
          boxShadow: [
            BoxShadow(
                color: cs.shadow.withOpacity(0.08),
                blurRadius: 10,
                offset: const Offset(0, -2)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios, size: 18),
                  onPressed: appState.hasPrevious
                      ? () {
                          appState.previousQuestion();
                          _scrollController.jumpTo(0);
                        }
                      : null,
                ),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: List.generate(total, (i) {
                        final cur = i == appState.currentQuestionIndex;
                        final ans = _practiceAnswersMap.containsKey(i);
                        return GestureDetector(
                          onTap: () {
                            while (appState.currentQuestionIndex > i &&
                                appState.hasPrevious) {
                              appState.previousQuestion();
                            }
                            while (appState.currentQuestionIndex < i &&
                                !appState.isLastQuestion) {
                              appState.nextQuestion();
                            }
                          },
                          child: Container(
                            width: 26,
                            height: 26,
                            margin: const EdgeInsets.symmetric(horizontal: 1.5),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: cur
                                  ? cs.primary
                                  : ans
                                      ? cs.primary.withOpacity(0.35)
                                      : cs.surfaceContainerHighest,
                              border: cur
                                  ? Border.all(color: cs.onPrimary, width: 2)
                                  : null,
                            ),
                            child: Center(
                              child: Text('${i + 1}',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: cur
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      color: cur
                                          ? cs.onPrimary
                                          : cs.onSurface)),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_forward_ios, size: 18),
                  onPressed: !appState.isLastQuestion
                      ? () {
                          appState.nextQuestion();
                          _scrollController.jumpTo(0);
                        }
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.assignment_turned_in),
                label: Text('提交练习 ($answered/$total)'),
                onPressed: () => _showSubmit(appState),
              ),
            ),
          ],
        ),
      );
    }
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
                  if (widget.quizMode == QuizMode.memorize) {
                    _handleExit(appState);
                  } else {
                    _handleEndSession(context, appState);
                  }
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

  /// v1.0.2 统一重构：练习提交确认弹窗（对齐里程碑文案：确认提交 (已选 X 题)）
  void _showSubmit(AppState appState) {
    if (_practiceSubmitted) return;
    final total = appState.quizQuestions.length;
    final answered = _practiceAnswersMap.length;
    _modalOpen = true;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('确认提交 (已选 $answered 题)'),
        content: Text('共$total题，已答$answered题，未答${total - answered}题。\n\n提交后将无法修改，确定提交？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('继续检查')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _submitPractice(appState);
            },
            child: const Text('确认提交'),
          ),
        ],
      ),
    ).then((_) => _modalOpen = false);
  }

  /// v1.0.2 统一重构：练习批量批改 → 结果页（零落库，纯判定）
  void _submitPractice(AppState appState) {
    if (_practiceSubmitted) return;
    _practiceSubmitted = true;
    _practiceTimer?.cancel();
    final qs = appState.quizQuestions;
    int correct = 0, wrong = 0, blank = 0;
    final wrongList = <Map<String, dynamic>>[];
    for (int i = 0; i < qs.length; i++) {
      final ua = _practiceAnswersMap[i];
      if (ua == null || ua.isEmpty) {
        blank++;
        continue;
      }
      if (QuizService.judgeAnswer(qs[i], ua)) {
        correct++;
      } else {
        wrong++;
        wrongList.add({'idx': i, 'q': qs[i], 'ua': ua});
      }
    }
    Future.delayed(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      final acc =
          qs.isNotEmpty ? (correct / qs.length * 100).toStringAsFixed(1) : '0';
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => PracticeResultScreen(
            correct: correct,
            wrong: wrong,
            blank: blank,
            total: qs.length,
            accuracy: acc,
            elapsedSeconds: _elapsedSeconds,
            timing: widget.practiceTiming ?? PracticeTiming.untimed,
            durationMinutes: widget.practiceDurationMinutes,
            wrongList: wrongList,
            questions: qs,
            answers: _practiceAnswersMap,
          ),
        ),
      );
    });
  }

  Future<void> _handleEndSession(
      BuildContext context, AppState appState) async {
    final session = await appState.endSession();
    if (!mounted) return;

    Navigator.pushReplacement(
      context,      MaterialPageRoute(
        builder: (_) => SessionSummaryScreen(session: session),
      ),
    );
  }
}


