import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:provider/provider.dart';
import '../models/follow_up_message.dart';
import '../models/question.dart';
import '../services/app_state.dart';
import '../services/quiz_service.dart';
import '../services/theme_service.dart';
import '../utils/format_utils.dart';
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
  bool _inErrorBook = false;
  int? _lastQuestionId;
  bool _showAnalysis = false;
  final Set<String> _selectedOptions = {};
  bool _isMemorizeMode = false;
  // 练习模式状态（v1.0.2 统一重构：练习能力内聚于本页）
  final List<PracticeAnswerState> _practiceAnswers = [];
  final Map<int, String> _practiceAnswersMap = {};
  // v1.0.2 设计审查修复：计时改 ValueNotifier + 墙钟
  // （每秒 setState 重建整页 → 只重建计时徽标；墙钟保证切后台倒计时依旧准确）
  final ValueNotifier<int> _elapsedSeconds = ValueNotifier(0);
  final ValueNotifier<int> _remainingSeconds = ValueNotifier(0);
  DateTime? _practiceStartAt; // 练习开始墙钟
  DateTime? _practiceDeadline; // 限时截止墙钟
  Timer? _practiceTimer;
  bool _practiceSubmitted = false;
  bool _modalOpen = false; // 挡路弹窗标记（答题卡/提交确认）
  // v1.0.2 修复：提交防重（双击不产生重复作答记录）
  bool _submitting = false;
  // v1.0.2 设计审查修复：结束会话防重（双击"完成刷题"不再抛未捕获 StateError）
  bool _ending = false;

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
      _startPracticeTimer();
    }
  }

  void _startPracticeTimer() {
    _practiceTimer?.cancel();
    _practiceStartAt = DateTime.now();
    _practiceDeadline = widget.practiceTiming == PracticeTiming.timed
        ? _practiceStartAt!.add(Duration(minutes: widget.practiceDurationMinutes))
        : null;
    _elapsedSeconds.value = 0;
    _remainingSeconds.value = widget.practiceTiming == PracticeTiming.timed
        ? widget.practiceDurationMinutes * 60
        : 0;
    _practiceTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _practiceSubmitted) return;
      _tickPracticeClock();
    });
  }

  void _tickPracticeClock() {
    // v1.0.2 设计审查修复：墙钟计时（App 切后台期间 Timer 暂停，
    // 恢复后按真实时间修正；限时归零照常自动交卷）
    final now = DateTime.now();
    final elapsed = now.difference(_practiceStartAt!).inSeconds;
    _elapsedSeconds.value = elapsed < 0 ? 0 : elapsed;
    if (_practiceDeadline != null) {
      final remaining = _practiceDeadline!.difference(now).inSeconds;
      _remainingSeconds.value = remaining < 0 ? 0 : remaining;
      if (remaining <= 0) {
        _practiceTimer?.cancel();
        // 限时归零自动交卷：先关闭挡路弹窗
        if (_modalOpen) {
          Navigator.of(context).pop();
          _modalOpen = false;
        }
        _submitPractice(context.read<AppState>());
      }
    }
  }

  String _fmtTime(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  /// 限时练习剩余 10%（60~300s 下限）进入红色警告态
  bool _isPracticeTimeWarn(int remaining) {
    if (widget.practiceTiming != PracticeTiming.timed) return false;
    final total = widget.practiceDurationMinutes * 60;
    if (total <= 0) return false;
    final warnSec = (total * 0.1).ceil().clamp(60, 300);
    return remaining > 0 && remaining <= warnSec;
  }

  void dispose() {
    _practiceTimer?.cancel();
    _elapsedSeconds.dispose();
    _remainingSeconds.dispose();
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
              // v1.0.2 设计审查修复：ValueListenableBuilder 只重建徽标，不重建整页
              if (isPractice)
                ValueListenableBuilder<int>(
                  valueListenable: _elapsedSeconds,
                  builder: (context, elapsed, _) =>
                      ValueListenableBuilder<int>(
                    valueListenable: _remainingSeconds,
                    builder: (context, remaining, _) {
                      final warn = _isPracticeTimeWarn(remaining);
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: warn ? cs.error : cs.primary.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              widget.practiceTiming == PracticeTiming.timed
                                  ? '剩余 ${_fmtTime(remaining)}'
                                  : '已用 ${_fmtTime(elapsed)}',
                              style: TextStyle(
                                fontSize: warn ? 14 : 12,
                                fontWeight: FontWeight.bold,
                                color: warn ? Colors.white : cs.onSurface,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
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
              // v1.0.2 设计审查修复：仅正常刷题可切背题
              // （练习模式切背题高亮答案属作弊路径）
              if (widget.quizMode == QuizMode.normal)
                IconButton(
                  icon: Icon(_isMemorizeMode ? Icons.visibility_off : Icons.visibility, size: 20),
                  tooltip: _isMemorizeMode ? '切回刷题' : '背题模式',
                  onPressed: () => setState(() => _isMemorizeMode = !_isMemorizeMode),
                ),
              if (widget.quizMode == QuizMode.memorize)
                TextButton(
                  onPressed: () => _handleExit(appState),
                  // v1.0.2 设计审查修复：跟随导航栏前景色（浅色导航栏主题下
                  // 白字不可见）
                  child: Text('结束',
                      style: TextStyle(color: Theme.of(context).appBarTheme.foregroundColor)),
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
                    // v1.0.2 设计审查修复：提交期间禁止切题
                    // （async gap 竞态：否则 await 后的历史槽位写入会错位）
                    if (_submitting) return;
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
                        else if (isPractice || !isAnswered) ...[
                          _buildOptionsArea(appState, question, cs),
                          // v1.0.2 UI 审查修复：未作答时下方大片空白，
                          // 加轻提示引导答题
                          if (!isPractice && !isAnswered) ...[
                            const SizedBox(height: 20),
                            Center(
                              child: Text(
                                '点击选项提交答案，答对自动进入下一题',
                                style: TextStyle(
                                    fontSize: 12, color: cs.onSurfaceVariant),
                              ),
                            ),
                          ],
                        ]
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
                                  if (_submitting) return; // 提交期间禁重做
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
  /// 有作答 → 暂停会话（断点续刷，进度保留）；无作答（练习/背题未作答）→ 放弃不落库
  Future<void> _handleExit(AppState appState) async {
    final isPractice = widget.quizMode == QuizMode.practice;
    final hint = isPractice
        ? '退出后本次练习记录将不保存。'
        : (appState.hasSessionAnswers
            // v1.0.2 七项改进：退出改为暂停，进度保留可下次继续
            ? '本次进度将保留，可下次从首页继续。'
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
        // v1.0.2 七项改进：断点续刷——暂停保留进度，而非直接结束
        await appState.pauseSession();
      }
    } catch (e) {
      // v1.0.2 设计审查修复：保存失败不再静默，留在页面提示重试
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败：$e')),
      );
      return;
    }
    if (!mounted) return;
    Navigator.pop(context);
  }

  /// 背题模式：选项中高亮正确选项
  Widget _buildMemorizeOptions(Question question, ColorScheme cs, AppState appState) {
    // v1.0.2 设计审查修复：硬编码绿色 → 主题语义色（success 系列）
    final ac = AppThemeColors.of(context);
    final options = question.questionType == 'true_false' ? ['对', '错'] : question.options;
    if (options.isEmpty) {
      return Container(
        width: double.infinity, padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: ac.successContainer, borderRadius: BorderRadius.circular(10), border: Border.all(color: ac.success)),
        child: Text('正确答案: ${question.correctAnswer}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: ac.success)),
      );
    }
    final correctSet = question.questionType == 'multi_choice' ? question.correctAnswer.split(',').map((e) => e.trim().toUpperCase()).toSet() : {question.correctAnswer.toUpperCase().trim()};
    return Column(children: List.generate(options.length, (i) {
      final label = question.questionType == 'true_false' ? (i == 0 ? '对' : '错') : String.fromCharCode(65 + i);
      final isCorrect = correctSet.contains(question.questionType == 'true_false' ? (i == 0 ? '对' : '错') : label);
      return Padding(padding: const EdgeInsets.only(bottom: 8), child: Container(
        width: double.infinity, padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: isCorrect ? ac.successContainer : cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(10), border: Border.all(color: isCorrect ? ac.success : cs.outlineVariant)),
        child: Row(children: [
          Container(width: 26, height: 26, decoration: BoxDecoration(color: isCorrect ? ac.success : cs.surfaceContainerHighest, shape: BoxShape.circle), child: Center(child: isCorrect ? const Icon(Icons.check, size: 14, color: Colors.white) : Text(label, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: cs.onSurfaceVariant)))),
          const SizedBox(width: 12),
          Expanded(child: Text(options[i], style: TextStyle(fontSize: 14, color: isCorrect ? ac.success : cs.onSurface, height: 1.4))),
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
                  // v1.0.2 设计审查修复：题型中文标签统一走 Question.typeLabel
                  question.typeLabel,
                  style: TextStyle(fontSize: 12, color: cs.primary),
                ),
              ),
              const Spacer(),
              if (stats.isNotEmpty)
                Text(
                  '作答${stats['total']}次  正确率${stats['total']! > 0 ? ((stats['correct']! / stats['total']!) * 100).toStringAsFixed(0) : 0}%'
                  // v1.0.2 FSRS 可见化：答完题展示下次复习时间
                  '${appState.currentFsrsCard != null ? ' · 下次复习：${relativeDayLabel(appState.currentFsrsCard!.nextReviewAt)}' : ''}',
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
              if (isMulti) {
                final x = practiceSel.toSet();
                x.contains(label) ? x.remove(label) : x.add(label);
                _recordPracticeAnswer(appState, (x.toList()..sort()).join(','));
              } else {
                _recordPracticeAnswer(appState, label);
              }
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
    // v1.0.2 设计审查修复：识别单个下划线（此前 _{2,} 漏掉 "_"）
    final blankCount = RegExp(r'_{1,}|（\s*）|\(\s*\)').allMatches(title).length;
    final n = blankCount > 0 ? blankCount : 1;

    // v1.0.2 设计审查修复：build 中只增不删；多余控制器待帧后销毁，
    // 避免在构建阶段 dispose 尚挂在树上的 controller
    while (_fillBlankControllers.length < n) {
      _fillBlankControllers.add(TextEditingController());
    }
    while (_fillBlankFocusNodes.length < n) {
      _fillBlankFocusNodes.add(FocusNode());
    }
    if (_fillBlankControllers.length > n || _fillBlankFocusNodes.length > n) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        while (_fillBlankControllers.length > n) {
          _fillBlankControllers.removeLast().dispose();
        }
        while (_fillBlankFocusNodes.length > n) {
          _fillBlankFocusNodes.removeLast().dispose();
        }
      });
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
    // v1.0.2 设计审查修复：题型中文标签统一走 Question.typeLabel
    final label = appState.currentQuestion?.typeLabel ?? '题目';
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
                _recordPracticeAnswer(appState, answer);
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
    final ac = AppThemeColors.of(context);
    final cur = _practiceAnswersMap[appState.currentQuestionIndex] ?? '';
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () {
              if (isPractice) {
                _recordPracticeAnswer(appState, '对');
                return;
              }
              _handleSubmitAnswer(appState, '对');
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isPractice && cur == '对'
                    ? ac.successContainer
                    : cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: isPractice && cur == '对' ? ac.success : ac.success),
              ),
              child: Center(
                // v1.0.2 设计审查修复：硬编码绿色 → 语义色
                child: Text('✓  正确',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: ac.success)),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: () {
              if (isPractice) {
                _recordPracticeAnswer(appState, '错');
                return;
              }
              _handleSubmitAnswer(appState, '错');
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isPractice && cur == '错'
                    ? ac.dangerContainer
                    : cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: ac.danger),
              ),
              child: Center(
                child: Text('✗  错误',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: ac.danger)),
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
      _recordPracticeAnswer(appState, answer);
      return;
    }
    _handleSubmitAnswer(appState, answer);
  }

  /// v1.0.2 设计审查修复：练习答案记录 5 处复制粘贴收敛为单方法
  void _recordPracticeAnswer(AppState appState, String answer) {
    setState(() {
      _practiceAnswersMap[appState.currentQuestionIndex] = answer;
      _syncPracticeSheet(appState);
    });
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
        // v1.0.2 修复：延迟自动跳题前比对题号，
        // 用户在窗口内手动跳题时不重复跳转（避免跳过中间题）
        // v1.0.2 UI 审查修复：600 → 800ms，给答案反馈留足节奏
        final answeredIndex = appState.currentQuestionIndex;
        await Future.delayed(const Duration(milliseconds: 800));
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
        onSave: (title, answer, type) async {
          await appState.updateCurrentQuestion(title, answer, type);
          // v1.0.2 设计审查修复：已作答题目修改答案后按新答案重判，
          // 否则判定显示与落库记录脱节
          await appState.rejudgeCurrentAnswerAfterEdit();
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
        onJumpTo: (i) {
          Navigator.pop(context);
          // v1.0.2 设计审查修复：单次跳转替代 while 逐题循环
          appState.jumpToQuestion(i);
          _scrollController.jumpTo(0);
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
      // v1.0.2 设计审查修复：末题左滑不走 endSession/abortSession，
      // 此处显式复位 skipFSRS（生命周期收口，防泄漏到下一会话）
      context.read<AppState>().skipFSRS = false;
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
    } catch (e) {
      // v1.0.2 设计审查修复：保存失败不再静默吞掉
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败：$e')),
      );
      return;
    }
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
    appState.nextQuestion();
    _scrollController.jumpTo(0);
  }

  Widget _buildAnsweredResult(AppState appState, Question question, ColorScheme cs) {
    final qt = question.questionType;
    // v1.0.2 UI 审查修复：对/错反馈统一用语义色 success(绿)/danger(红)，
    // 原 tertiary/error 在部分主题下呈现粉紫/橙，与"绿对红错"心智不符
    final ac = AppThemeColors.of(context);
    if (qt == 'fill_blank' || qt == 'true_false') {
      final lastRecord = appState.lastAnswerRecord;
      final userAnswer = lastRecord?.userAnswer ?? '';
      final correctAnswer = question.correctAnswer;
      final isCorrect = lastRecord?.isCorrect ?? false;

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isCorrect ? ac.successContainer : ac.dangerContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isCorrect ? ac.success : ac.danger),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(isCorrect ? Icons.check_circle : Icons.cancel,
                    color: isCorrect ? ac.success : ac.danger, size: 20),
                const SizedBox(width: 8),
                Text(isCorrect ? '回答正确' : '回答错误',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: isCorrect ? ac.success : ac.danger)),
              ],
            ),
            const SizedBox(height: 10),
            if (qt == 'fill_blank') ...[
              Text('你的答案: $userAnswer',
                  style: TextStyle(fontSize: 14, color: isCorrect ? ac.success : ac.danger)),
              if (!isCorrect) ...[
                const SizedBox(height: 4),
                Text('正确答案: $correctAnswer',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: ac.success)),
              ],
            ],
            if (qt == 'true_false') ...[
              Text('你选择了: ${userAnswer == "对" ? "✓ 正确" : "✗ 错误"}',
                  style: TextStyle(fontSize: 14, color: isCorrect ? ac.success : ac.danger)),
              if (!isCorrect)
                Text('正确答案: ${correctAnswer == "对" ? "✓ 正确" : "✗ 错误"}',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: ac.success)),
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

    // v1.0.2 UI 审查修复：正确/错误高亮统一 success(绿)/danger(红) 语义色
    final ac = AppThemeColors.of(context);

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
          bgColor = ac.successContainer;
          textColor = ac.success;
          borderColor = ac.success;
        } else if (isUserWrong) {
          bgColor = ac.dangerContainer;
          textColor = ac.danger;
          borderColor = ac.danger;
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
                    color: isCorrect ? ac.success : isUserWrong ? ac.danger : cs.outlineVariant,
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
    // v1.0.2 UI 审查修复：tertiary/error → success/danger（绿对红错语义）
    final ac = AppThemeColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('正确答案: $correct',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: ac.success)),
        const SizedBox(height: 4),
        // v1.0.2 设计审查修复：答对时"你的答案"不再恒显示错误红色
        Text('你的答案: $user',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold,
              color: lastRecord.isCorrect ? ac.success : ac.danger)),
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
              SnackBar(
                  content: const Text('请先在设置中配置 API Key 后再查看解析。'),
                  backgroundColor: AppThemeColors.of(context).warning),
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
              SnackBar(
                  content: const Text('请先在设置中配置 API Key 后再查看解析。'),
                  backgroundColor: AppThemeColors.of(context).warning),
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
            // v1.0.2 聊天气泡式追问：历史消息（用户右/AI 左），
            // 按题持久化，切题重新打开后仍可见
            // ignore: use_build_context_synchronously
            ...appState.followUpHistory.map((m) => _FollowUpBubble(
                  message: m,
                  cs: Theme.of(context).colorScheme,
                  ac: AppThemeColors.of(context),
                )),
            // AI 回复中
            if (appState.followUpLoading)
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Flexible(child: _FollowUpTypingBubble())],
              ),
            const SizedBox(height: 10),
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
                    onSubmitted: (_) => _sendFollowUp(appState),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.send, size: 16),
                  label: const Text('发送', style: TextStyle(fontSize: 13)),
                  onPressed: () => _sendFollowUp(appState),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// 发送追问（聊天气泡式）：配置拦截 → 入历史 → AI 回复 → 滚到底部
  Future<void> _sendFollowUp(AppState appState) async {
    if (!appState.settings.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: const Text('请先在设置中配置 API Key 后再追问。'),
            backgroundColor: AppThemeColors.of(context).warning),
      );
      return;
    }
    final q = _followUpController.text.trim();
    if (q.isEmpty) return;
    _followUpController.clear();
    _scrollToFollowUpBottom();
    await appState.sendFollowUp(q);
    if (!mounted) return;
    _scrollToFollowUpBottom();
  }

  /// 追问内容增长后自动滚动到对话末尾（输入框随消息下移）
  void _scrollToFollowUpBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    });
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
                          if (_submitting) return;
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
                            // v1.0.2 设计审查修复：单次跳转替代 while 循环
                            if (_submitting) return;
                            appState.jumpToQuestion(i);
                            _scrollController.jumpTo(0);
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
                          if (_submitting) return;
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
                    // v1.0.2 UI 审查修复：单行不换行 + 紧凑内边距（竖排问题）
                    label: Text(_inErrorBook ? '已收藏' : '错题本',
                        maxLines: 1,
                        softWrap: false,
                        style: const TextStyle(fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
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
                if (appState.hasPrevious) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.arrow_back, size: 18),
                      label: const Text('上一题',
                          maxLines: 1, softWrap: false, style: TextStyle(fontSize: 14)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: cs.onSurfaceVariant,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () {
                        if (_submitting) return; // 提交期间禁切题
                        _showAnalysis = false;
                        _showManualAnalysis = false;
                        _followUpController.clear();
                        appState.previousQuestion();
                        _scrollController.jumpTo(0);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      if (_submitting) return; // 提交期间禁切题
                      _advanceQuestion(appState);
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('下一题',
                        maxLines: 1, softWrap: false, style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
    );
  }

  /// v1.0.2 统一重构：练习提交确认弹窗（对齐里程碑文案：确认提交 (已选 X 题)）
  void _showSubmit(AppState appState) {
    if (_practiceSubmitted) return;
    if (_modalOpen) return; // v1.0.2 设计审查修复：弹窗防重
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
    // v1.0.2 七项改进：复盘答题卡状态（已答 + 判定结果）
    final answerStates = List<PracticeAnswerState>.generate(qs.length, (i) {
      final ua = _practiceAnswersMap[i];
      final st = PracticeAnswerState();
      st.answered = ua != null && ua.isNotEmpty;
      if (st.answered) st.correct = QuizService.judgeAnswer(qs[i], ua!);
      return st;
    });
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
            elapsedSeconds: _elapsedSeconds.value,
            timing: widget.practiceTiming ?? PracticeTiming.untimed,
            durationMinutes: widget.practiceDurationMinutes,
            wrongList: wrongList,
            questions: qs,
            answers: _practiceAnswersMap,
            // v1.0.2 七项改进：复盘答题卡
            answerStates: answerStates,
          ),
        ),
      );
    });
  }

  /// v1.0.2 设计审查修复：结束会话防重（_ending 标志）+ 保存失败提示重试/放弃
  /// （此前双击会因会话已 reset 抛未捕获 StateError）
  Future<void> _handleEndSession(
      BuildContext context, AppState appState) async {
    if (_ending) return;
    _ending = true;
    try {
      final session = await appState.endSession();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => SessionSummaryScreen(session: session),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final retry = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('保存失败'),
          content: Text('会话保存失败：$e\n\n可重试保存，或放弃本次进度。'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('放弃')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('重试')),
          ],
        ),
      );
      if (!mounted) return;
      if (retry == true) {
        _ending = false;
        await _handleEndSession(context, appState);
      } else {
        Navigator.pop(context);
      }
    } finally {
      _ending = false;
    }
  }
}



/// 追问对话气泡（用户右 / AI 左）
class _FollowUpBubble extends StatelessWidget {
  final FollowUpMessage message;
  final ColorScheme cs;
  final AppThemeColors ac;

  const _FollowUpBubble({required this.message, required this.cs, required this.ac});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isUser ? ac.accent : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(12),
                    topRight: const Radius.circular(12),
                    bottomLeft: Radius.circular(isUser ? 12 : 4),
                    bottomRight: Radius.circular(isUser ? 4 : 12),
                  ),
                ),
                child: isUser
                    ? Text(message.content,
                        style: TextStyle(
                            fontSize: 13, color: ac.onAccent, height: 1.5))
                    : AiResponseWidget(text: message.content, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// AI 回复中的提示气泡
class _FollowUpTypingBubble extends StatelessWidget {
  const _FollowUpTypingBubble();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(4),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
          ),
          const SizedBox(width: 8),
          Text('AI 正在回复...',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}
