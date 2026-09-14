import 'dart:async';
import '../utils/design_tokens.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:provider/provider.dart';
import '../models/ink_annotation.dart';
import '../models/question.dart';
import '../services/app_state.dart';
import '../services/annotation_service.dart';
import '../services/quiz_service.dart';
import '../services/theme_service.dart';
import '../utils/format_utils.dart';
import '../widgets/kit/mj_kit.dart';
import '../widgets/quiz/quiz_question_card.dart';
import '../utils/responsive.dart';
import '../widgets/ai_response_widget.dart';
import '../widgets/annotation_canvas.dart';
import '../widgets/annotation_controller.dart';
import '../widgets/annotation_toolbar.dart';
import '../services/debug_log_service.dart';
import 'ai_chat_screen.dart';
import 'session_summary_screen.dart';
import 'settings_screen.dart';
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
  // v1.0.3 手写批注同期优化：AudioPlayer 懒加载（首次播声音才创建，
  // 避免静音/测试环境白建 EventChannel）
  AudioPlayer? _audioPlayerInstance;
  AudioPlayer get _audioPlayer => _audioPlayerInstance ??= AudioPlayer();
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
  // v1.0.2 设计审查修复：结束会话防重（双击“完成刷题”不再抛未捕获 StateError）
  bool _ending = false;
  // v1.0.3 PC 鼠标慢速拖动：累计横向位移（速度为 0 时按位移切题，批注态不使用）
  double _hDragOuter = 0;
  // v1.0.3 手写批注：交互状态机 + 模式标记
  // _annoPersistent：false=答题时即时批注（内存态，切题即弃，REQ-002~005）
  //                 true=答题后持久批注（按题落库，REQ-006~012）
  final AnnotationController _anno = AnnotationController();
  bool _annotating = false;
  bool _annoPersistent = false;

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
        ? _practiceStartAt!
            .add(Duration(minutes: widget.practiceDurationMinutes))
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

  @override
  void dispose() {
    _practiceTimer?.cancel();
    _elapsedSeconds.dispose();
    _remainingSeconds.dispose();
    // v1.0.3 手写批注：退出页面时持久批注兑底保存（fire-and-forget；
    // 正常路径已在切题/完成处保存，此处只覆盖直接退出页面的场景）
    if (_annoPersistent &&
        _anno.strokes.isNotEmpty &&
        _lastQuestionId != null) {
      AnnotationService.instance.save(_lastQuestionId!, _anno.strokes);
    }
    _anno.dispose();
    _followUpController.dispose();
    for (final c in _fillBlankControllers) {
      c.dispose();
    }
    _fillBlankControllers.clear();
    for (final f in _fillBlankFocusNodes) {
      f.dispose();
    }
    _fillBlankFocusNodes.clear();
    _textAnswerController.dispose();
    _scrollController.dispose();
    _audioPlayerInstance?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, _) {
        final ac = AppThemeColors.of(context);
        final question = appState.currentQuestion;
        if (question == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('刷题中')),
            body: const Center(child: Text('加载题目中...')),
          );
        }

        final lastRecord = appState.lastAnswerRecord;
        // v1.0.2 统一重构：练习模式“已答”按练习答案表判断（可随时修改，不判定）
        final isPractice = widget.quizMode == QuizMode.practice;
        final isAnswered = isPractice
            ? _practiceAnswersMap.containsKey(appState.currentQuestionIndex)
            : lastRecord != null;

        // v1.0.3 画布扩区：宽屏开关 + 持久批注显示条件（答案已展示才回显，REQ-006）
        final wide = isWideLayout(context);
        final showPersistCond = !_annoPersistent ||
            _isMemorizeMode ||
            widget.quizMode == QuizMode.memorize ||
            isAnswered;

        // v1.27 需求纠偏：非批注态左右拖动切题（整个答题区域，速度或位移任一达标）；
        // 批注模式由手势入口直接禁止，不再与画布联动。
        void doSwipe(DragEndDetails details, double hDrag) {
          final v = details.primaryVelocity ?? 0.0;
          // v1.0.2 设计审查修复：提交期间禁止切题（防历史槽位写入错位）
          if (_submitting) return;
          // v1.0.3 鼠标慢速拖动：速度或累计位移任一达标即切题（鼠标拖动常无速度）
          final byVelocity = v.abs() >= 300;
          final back = v < -300 || (!byVelocity && hDrag < -60);
          final prev = v > 300 || (!byVelocity && hDrag > 60);
          if (back) {
            // 练习自由前进；刷题/背题需已作答才前进
            if (isPractice || _isMemorizeMode || isAnswered) {
              _advanceQuestion(appState);
            }
          } else if (prev) {
            if (appState.hasPrevious) {
              _showAnalysis = false;
              _showManualAnalysis = false;
              _followUpController.clear();
              appState.previousQuestion();
              _scrollController.jumpTo(0);
            }
          }
        }

        if (isPractice &&
            _practiceAnswers.length != appState.quizQuestions.length) {
          _practiceAnswers.clear();
          for (int i = 0; i < appState.quizQuestions.length; i++) {
            _practiceAnswers.add(PracticeAnswerState());
          }
        }
        if (appState.currentQuestion?.id != _lastQuestionId) {
          // v1.0.3 手写批注：切题前保存当前题持久批注（fire-and-forget，
          // save 幂等），随后退出批注态并清空
          // （REQ-003/004：即时批注不落库不跨题）
          if (_annoPersistent &&
              _anno.strokes.isNotEmpty &&
              _lastQuestionId != null) {
            AnnotationService.instance.save(_lastQuestionId!, _anno.strokes);
          }
          _annotating = false;
          _annoPersistent = false;
          _anno.clearAll();
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
            // v1.0.3 手写批注：预载新题持久批注（已答/背题进入即可见，REQ-006；
            // 渲染条件仍控制未作答时不显示）
            AnnotationService.instance.load(qid).then((strokes) {
              if (!mounted || _annotating) return;
              if (appState.currentQuestion?.id != qid) return; // 又切题了
              if (strokes.isEmpty) return;
              setState(() {
                _annoPersistent = true;
                _anno.loadFrom(strokes);
              });
            });
          }
        }

        final page = PopScope(
          // v1.0.2 修复：系统返回键不再产生未结束的幽灵会话
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _handleExit(appState);
          },
          child: Scaffold(
            backgroundColor: ac.background,
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
                                color: warn
                                    ? ac.danger
                                    : ac.accent.withOpacity(0.2),
                                borderRadius:
                                    BorderRadius.circular(MaoRadius.control),
                              ),
                              child: Text(
                                widget.practiceTiming == PracticeTiming.timed
                                    ? '剩余 ${_fmtTime(remaining)}'
                                    : '已用 ${_fmtTime(elapsed)}',
                                style: TextStyle(
                                  fontSize: warn ? 14 : 12,
                                  fontWeight: FontWeight.bold,
                                  color: warn ? Colors.white : ac.textPrimary,
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
                    onPressed: () => _showAnswerSheet(context, appState, ac),
                  ),
                // v1.0.2 设计审查修复：仅正常刷题可切背题
                // （练习模式切背题高亮答案属作弊路径）
                if (widget.quizMode == QuizMode.normal)
                  IconButton(
                    icon: Icon(
                        _isMemorizeMode
                            ? Icons.visibility_off
                            : Icons.visibility,
                        size: 20),
                    tooltip: _isMemorizeMode ? '切回刷题' : '背题模式',
                    onPressed: () =>
                        setState(() => _isMemorizeMode = !_isMemorizeMode),
                  ),
                // v1.0.3 手写批注（REQ-001/005）：正常刷题与背题模式可入，
                // 练习模式不显示
                if (!isPractice)
                  IconButton(
                    icon: Icon(Icons.draw,
                        size: 20, color: _annotating ? ac.accent : null),
                    tooltip: '手写批注',
                    onPressed: () => _toggleAnnotate(appState),
                  ),
                if (widget.quizMode == QuizMode.memorize)
                  TextButton(
                    onPressed: () => _handleExit(appState),
                    // v1.0.2 设计审查修复：跟随导航栏前景色（浅色导航栏主题下
                    // 白字不可见）
                    child: Text('结束',
                        style: TextStyle(
                            color:
                                Theme.of(context).appBarTheme.foregroundColor)),
                  ),
              ],
            ),
            // 平板适配：内容限宽居中（手机无影响）；
            // v1.0.3 宽屏重设计：宽屏限宽 920（选项双列后信息密度更合理）
            body: ResponsivePage(
              maxWidth: isWideLayout(context) ? 920 : kContentMaxWidth,
              child: Column(
                children: [
                  // v1.0.3 手写批注：批注模式工具栏（REQ-014）
                  if (_annotating)
                    AnnotationToolbar(
                      controller: _anno,
                      persistent: _annoPersistent,
                      onFinish: () => _finishAnnotate(appState),
                      // v1.0.3 PC 快捷键：桌面平台按钮提示追快捷键标注
                      shortcuts: _isDesktop,
                    ),
                  // 进度条
                  TweenAnimationBuilder<double>(
                    tween: Tween(
                      begin: 0,
                      end: (appState.currentQuestionIndex +
                              (isAnswered ? 1 : 0)) /
                          appState.quizQuestions.length,
                    ),
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeInOut,
                    builder: (context, value, _) {
                      return LinearProgressIndicator(
                        value: value,
                        backgroundColor: ac.surfaceAlt,
                        color: ac.accent,
                        minHeight: 4,
                      );
                    },
                  ),

                  // 滚动区域
                  Expanded(
                    child: Stack(
                      children: [
                        GestureDetector(
                          onHorizontalDragEnd: (details) {
                            // v1.27 需求纠偏：批注模式下禁止左右滑动切题（画布接管全部指针）；
                            // 非批注态整个答题区域（本手势包裹全部滚动内容）均可左右拖动切题。
                            if (_annotating) return;
                            // 鼠标慢速拖动：速度为 0 时按累计位移切题（REQ：鼠标左右拖动切题）
                            final dd = _hDragOuter;
                            _hDragOuter = 0;
                            doSwipe(details, dd);
                          },
                          onHorizontalDragUpdate: (details) {
                            // 非批注态累计横向位移（批注态上方直接 return，不累计）
                            if (!_annotating) _hDragOuter += details.delta.dx;
                          },
                          onHorizontalDragCancel: () => _hDragOuter = 0,
                          child: SingleChildScrollView(
                            controller: _scrollController,
                            // v1.0.3 手写批注：批注中锁滚动（画布接管手势）
                            physics: _annotating
                                ? const NeverScrollableScrollPhysics()
                                : null,
                            padding: const EdgeInsets.all(16),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              transitionBuilder:
                                  (Widget child, Animation<double> animation) {
                                return SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0.25, 0),
                                    end: Offset.zero,
                                  ).animate(CurvedAnimation(
                                      parent: animation,
                                      curve: Curves.easeOutCubic)),
                                  child: FadeTransition(
                                      opacity: animation, child: child),
                                );
                              },
                              // v1.0.3 手写批注：渲染条件——持久批注仅答案展示时显示
                              // （REQ-006）；即时批注本题内持续可见（REQ-004 只约束跨题）
                              child: Stack(
                                key: ValueKey(question.id),
                                children: [
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _buildQuestionCard(
                                          question, appState, ac),
                                      const SizedBox(height: 16),
                                      // v1.0.2 统一重构：练习模式选项区恒可修改（不显示判定结果）
                                      if (_isMemorizeMode)
                                        _buildMemorizeOptions(
                                            question, ac, appState)
                                      else if (isPractice || !isAnswered) ...[
                                        _buildOptionsArea(
                                            appState, question, ac),
                                        // v1.0.2 UI 审查修复：未作答时下方大片空白，
                                        // 加轻提示引导答题
                                        if (!isPractice && !isAnswered) ...[
                                          const SizedBox(height: 20),
                                          Center(
                                            child: Text(
                                              '点击选项提交答案，答对自动进入下一题',
                                              style: TextStyle(
                                                  fontSize: MaoType.body,
                                                  color: ac.textSecondary),
                                            ),
                                          ),
                                        ],
                                      ] else ...[
                                        _buildAnsweredResult(
                                            appState, question, ac),
                                        const SizedBox(height: 12),
                                        _buildResultFeedback(
                                            appState, question, ac),
                                        // v1.0.2 完善：已答题目可重新作答（更新原记录，不新增）
                                        if (isAnswered &&
                                            widget.quizMode !=
                                                QuizMode.memorize &&
                                            !isPractice) ...[
                                          const SizedBox(height: 4),
                                          Align(
                                            alignment: Alignment.centerRight,
                                            child: TextButton.icon(
                                              icon: const Icon(
                                                  Icons.edit_outlined,
                                                  size: 15),
                                              label: const Text('重新作答',
                                                  style: TextStyle(
                                                      fontSize:
                                                          MaoType.caption)),
                                              style: TextButton.styleFrom(
                                                visualDensity:
                                                    VisualDensity.compact,
                                                foregroundColor:
                                                    ac.textSecondary,
                                              ),
                                              onPressed: () {
                                                if (_submitting)
                                                  return; // 提交期间禁重做
                                                _selectedOptions.clear();
                                                for (final c
                                                    in _fillBlankControllers) {
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
                                        if (_showAnalysis ||
                                            appState.currentAnalysis != null)
                                          _buildAnalysisArea(
                                              appState, question, ac)
                                        else
                                          _buildShowAnalysisButton(
                                              appState, ac),
                                        if (appState.currentAnalysis !=
                                            null) ...[
                                          const SizedBox(height: 4),
                                          _buildRegenerateButton(appState, ac),
                                        ],
                                      ],
                                    ],
                                  ),
                                  // v1.0.3 手写批注：画布叠放题区上方（REQ-002 题目区域标注），
                                  // 随内容滚动（位于滚动区内部）。
                                  // v1.0.3 画布扩区：宽屏下题区层只渲染存量旧笔迹（question 坐标系，只读），
                                  // 交互画布上移到页面层（见滚动区 Stack）；窄屏维持单层全交互。
                                  if (wide
                                      ? (_anno.strokes.any((s) =>
                                              s.frame == kFrameQuestion) &&
                                          (_annotating || showPersistCond))
                                      : (_annotating ||
                                          (_anno.strokes.isNotEmpty &&
                                              showPersistCond)))
                                    Positioned.fill(
                                      child: AnnotationCanvas(
                                        controller: _anno,
                                        interactive: _annotating && !wide,
                                        frameFilter:
                                            wide ? kFrameQuestion : null,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // v1.0.3 画布扩区（宽屏）：页面层画布覆盖整个滚动区（含题目上下空白），
                        // 可写范围不再局限于题目卡片；批注中滚动已锁，
                        // 坐标以可视区为准（进入批注时已归顶，保证回显位置一致）。
                        if (wide &&
                            (_annotating ||
                                (_anno.strokes
                                        .any((s) => s.frame == kFramePage) &&
                                    showPersistCond)))
                          Positioned.fill(
                            child: AnnotationCanvas(
                              controller: _anno,
                              interactive: _annotating,
                              frameFilter: kFramePage,
                            ),
                          ),
                      ],
                    ),
                  ),

                  // 底部按钮：已答或背题模式均显示
                  if (isAnswered || widget.quizMode == QuizMode.memorize)
                    _buildBottomBar(appState, ac),
                ],
              ),
            ),
          ),
        );
        // v1.0.3 PC 快捷键：桌面平台包 CallbackShortcuts（A/1-4/Q/W/E/R/S/
        // Delete/Ctrl+Delete/Esc）；手机/平板不包，避免误触发。
        if (!_isDesktop) return page;
        return CallbackShortcuts(
          bindings: _annoShortcuts(appState),
          child: Focus(autofocus: true, child: page),
        );
      },
    );
  }

  /// v1.0.3 手写批注：进入/退出批注模式（REQ-001/002/005）
  void _toggleAnnotate(AppState appState) {
    if (_annotating) {
      _finishAnnotate(appState);
      return;
    }
    // v1.0.3 画布扩区：宽屏新笔迹用页面坐标系（覆盖整个内容区）；
    // 窄屏维持题区坐标系。宽屏进入时滚动归顶，保证回显位置一致。
    final wide = isWideLayout(context);
    _anno.activeFrame = wide ? kFramePage : kFrameQuestion;
    if (wide && _scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    final isMemorizeState =
        _isMemorizeMode || widget.quizMode == QuizMode.memorize;
    final answered = appState.lastAnswerRecord != null;
    if (isMemorizeState || answered) {
      // 答题后批注（持久）：加载该题已存批注（REQ-006~012）
      _annoPersistent = true;
      final qid = appState.currentQuestion?.id;
      if (qid != null) {
        AnnotationService.instance.load(qid).then((strokes) {
          if (!mounted || _annotating) return;
          if (appState.currentQuestion?.id != qid) return; // 已切题
          _anno.loadFrom(strokes);
        });
      }
    } else {
      // 答题时批注（即时）：内存态从空白开始，不落库（REQ-002/003）
      _annoPersistent = false;
      _anno.clearAll();
    }
    setState(() => _annotating = true);
  }

  /// v1.0.3 手写批注：完成编辑。持久批注立即落库
  /// （切题与 dispose 另有兑底保存，save 幂等）
  void _finishAnnotate(AppState appState) {
    setState(() => _annotating = false);
    if (_annoPersistent) {
      final qid = appState.currentQuestion?.id;
      if (qid != null) {
        AnnotationService.instance.save(qid, _anno.strokes);
      }
    }
  }

  // ======================== v1.0.3 PC 快捷键（仅桌面平台） ========================

  static final bool _isDesktop =
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  /// 焦点在可编辑文本框（填空/简答）时快捷键让位，不干扰输入
  bool _focusInEditable() =>
      FocusManager.instance.primaryFocus?.context?.widget is EditableText;

  /// Ctrl+Delete 一键清除（弹确认，与工具栏「清全部/清草稿」同逻辑）
  Future<void> _confirmClearByShortcut() async {
    final label = _annoPersistent ? '一键清除旧手写批注' : '清空本次草稿';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        content: const Text('清除后不可恢复，确定继续吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('清除')),
        ],
      ),
    );
    if (ok == true) _anno.clearAll();
  }

  /// 批注快捷键映射（A 进入/退出；1-4 颜色；Q/W/E 笔型；R 橡皮；
  /// S 选择；Delete 删选中；Ctrl+Delete 清除；Esc 完成）
  Map<ShortcutActivator, VoidCallback> _annoShortcuts(AppState appState) {
    void guarded(void Function() fn, {bool needAnnotating = true}) {
      if (_focusInEditable()) return;
      if (needAnnotating && !_annotating) return;
      fn();
    }

    return {
      const SingleActivator(LogicalKeyboardKey.keyA): () {
        if (_focusInEditable()) return;
        _toggleAnnotate(appState);
      },
      const SingleActivator(LogicalKeyboardKey.digit1): () =>
          guarded(() => _anno.setColor(kAnnoColors[0])),
      const SingleActivator(LogicalKeyboardKey.digit2): () =>
          guarded(() => _anno.setColor(kAnnoColors[1])),
      const SingleActivator(LogicalKeyboardKey.digit3): () =>
          guarded(() => _anno.setColor(kAnnoColors[2])),
      const SingleActivator(LogicalKeyboardKey.digit4): () =>
          guarded(() => _anno.setColor(kAnnoColors[3])),
      const SingleActivator(LogicalKeyboardKey.keyQ): () => guarded(() {
            _anno.setPenType(PenType.fine);
            _anno.setTool(AnnoTool.pen);
          }),
      const SingleActivator(LogicalKeyboardKey.keyW): () => guarded(() {
            _anno.setPenType(PenType.normal);
            _anno.setTool(AnnoTool.pen);
          }),
      const SingleActivator(LogicalKeyboardKey.keyE): () => guarded(() {
            _anno.setPenType(PenType.highlighter);
            _anno.setTool(AnnoTool.pen);
          }),
      const SingleActivator(LogicalKeyboardKey.keyR): () =>
          guarded(() => _anno.setTool(AnnoTool.eraser)),
      const SingleActivator(LogicalKeyboardKey.keyS): () => guarded(() {
            // 选择工具仅持久批注提供（与工具栏一致）
            if (_annoPersistent) _anno.setTool(AnnoTool.select);
          }),
      const SingleActivator(LogicalKeyboardKey.delete): () =>
          guarded(() => _anno.deleteSelected()),
      LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.delete):
          () => guarded(_confirmClearByShortcut),
      const SingleActivator(LogicalKeyboardKey.escape): () =>
          guarded(() => _finishAnnotate(appState)),
    };
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
  Widget _buildMemorizeOptions(
      Question question, AppThemeColors ac, AppState appState) {
    // v1.0.2 设计审查修复：硬编码绿色 → 主题语义色（success 系列）
    final ac = AppThemeColors.of(context);
    final options =
        question.questionType == 'true_false' ? ['对', '错'] : question.options;
    if (options.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: ac.successContainer,
            borderRadius: BorderRadius.circular(MaoRadius.small),
            border: Border.all(color: ac.success)),
        child: Text('正确答案: ${question.correctAnswer}',
            style: TextStyle(
                fontSize: MaoType.h3,
                fontWeight: FontWeight.bold,
                color: ac.success)),
      );
    }
    final correctSet = question.questionType == 'multi_choice'
        ? question.correctAnswer
            .split(',')
            .map((e) => e.trim().toUpperCase())
            .toSet()
        : {question.correctAnswer.toUpperCase().trim()};
    return Column(
        children: List.generate(options.length, (i) {
      final label = question.questionType == 'true_false'
          ? (i == 0 ? '对' : '错')
          : String.fromCharCode(65 + i);
      final isCorrect = correctSet.contains(
          question.questionType == 'true_false' ? (i == 0 ? '对' : '错') : label);
      return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: isCorrect ? ac.successContainer : ac.surfaceAlt,
                borderRadius: BorderRadius.circular(MaoRadius.small),
                border: Border.all(color: isCorrect ? ac.success : ac.border)),
            child: Row(children: [
              Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                      color: isCorrect ? ac.success : ac.surfaceAlt,
                      shape: BoxShape.circle),
                  child: Center(
                      child: isCorrect
                          ? Icon(Icons.check, size: 14, color: ac.onAccent)
                          : Text(label,
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: MaoType.body,
                                  color: ac.textSecondary)))),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(options[i],
                      style: TextStyle(
                          fontSize: MaoType.body,
                          color: isCorrect ? ac.success : ac.textPrimary,
                          height: 1.4))),
            ]),
          ));
    }));
  }

  Widget _buildQuestionCard(
      Question question, AppState appState, AppThemeColors ac) {
    final stats = appState.currentQuestionStats;
    final attempts = stats['total'] ?? 0;
    final correct = stats['correct'] ?? 0;
    return QuizQuestionCard(
      question: question,
      attempts: attempts,
      accuracyPercent: attempts > 0 ? (correct / attempts * 100).round() : 0,
      // v1.0.2 FSRS 可见化：答完题展示下次复习时间
      nextReviewLabel: appState.currentFsrsCard == null
          ? null
          : relativeDayLabel(appState.currentFsrsCard!.nextReviewAt),
    );
  }

  Widget _buildOptionsArea(
      AppState appState, Question question, AppThemeColors ac) {
    final qt = question.questionType;
    if (qt == 'fill_blank') {
      return _buildFillBlankInput(appState, ac);
    }
    if (qt == 'true_false') {
      return _buildTrueFalseButtons(appState, ac);
    }
    if (qt == 'ming_jie' || qt == 'jian_da' || qt == 'jie_da') {
      return _buildTextAnswerInput(appState, ac, qt);
    }
    final options = question.options;
    final isMulti = question.questionType == 'multi_choice';
    final isPractice = widget.quizMode == QuizMode.practice;
    // 练习模式已选内容（可修改）
    final practiceAnswer =
        _practiceAnswersMap[appState.currentQuestionIndex] ?? '';
    final practiceSel = isMulti
        ? practiceAnswer.split(',').where((e) => e.isNotEmpty).toSet()
        : {practiceAnswer};

    final optionWidgets = options.asMap().entries.map((entry) {
      final int idx = entry.key;
      final option = entry.value;
      final label = String.fromCharCode(65 + idx);
      final selected = isPractice
          ? practiceSel.contains(label)
          : _selectedOptions.contains(label);

      return QuizOptionRow(
        label: label,
        text: option,
        selected: selected,
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
      );
    }).toList();

    // v1.0.2 统一重构：练习模式多选点击即存（无确认按钮），正常模式需确认提交
    if (isMulti && !isPractice) {
      return Column(
        children: [
          _arrangeOptionWidgets(optionWidgets),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.check_circle),
              label: Text('确认提交 (已选${_selectedOptions.length}项)',
                  style: const TextStyle(fontSize: MaoType.h3)),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _selectedOptions.isEmpty ? ac.surfaceAlt : ac.accent,
                foregroundColor:
                    _selectedOptions.isEmpty ? ac.textSecondary : ac.onAccent,
              ),
              onPressed: _selectedOptions.isEmpty
                  ? null
                  : () {
                      final answer = _selectedOptions.toList()..sort();
                      _selectedOptions.clear();
                      _handleSubmitAnswer(appState, answer.join(','));
                    },
            ),
          ),
        ],
      );
    }

    return _arrangeOptionWidgets(optionWidgets);
  }

  /// v1.0.3 窗口自适应：选项随可用宽度自动排列——
  /// 宽度足够时自然形成多列，窄窗口自动回到单列，
  /// 拖动窗口尺寸时连续适配（替代早期硬编码双列）。
  /// 批注画布覆盖外层 Stack，归一化坐标随排布边界自适应。
  Widget _arrangeOptionWidgets(List<Widget> optionWidgets) {
    if (!isWideLayout(context) || optionWidgets.length < 4) {
      return Column(children: optionWidgets);
    }
    return _AdaptiveOptionsColumn(children: optionWidgets);
  }

  Widget _buildFillBlankInput(AppState appState, AppThemeColors ac) {
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
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(MaoRadius.control)),
              prefixIcon: const Icon(Icons.edit),
            ),
            style: TextStyle(fontSize: MaoType.h3, color: ac.textPrimary),
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

  Widget _buildTextAnswerInput(
      AppState appState, AppThemeColors ac, String type) {
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
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(MaoRadius.control)),
            alignLabelWithHint: true,
          ),
          style: TextStyle(fontSize: MaoType.h3, color: ac.textPrimary),
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

  Widget _buildTrueFalseButtons(AppState appState, AppThemeColors ac) {
    final isPractice = widget.quizMode == QuizMode.practice;
    final cur = _practiceAnswersMap[appState.currentQuestionIndex] ?? '';
    void answer(String v) {
      if (isPractice) {
        _recordPracticeAnswer(appState, v);
        return;
      }
      _handleSubmitAnswer(appState, v);
    }

    return QuizTrueFalseButtons(
      practiceSelected: isPractice ? cur : null,
      onTrue: () => answer('对'),
      onFalse: () => answer('错'),
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
    for (final c in _fillBlankControllers) {
      c.clear();
    }
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

  void _showAnswerSheet(
      BuildContext context, AppState appState, AppThemeColors ac) {
    _modalOpen = true;
    showModalBottomSheet(
      context: context,
      // 平板适配：弹窗限宽居中
      constraints: const BoxConstraints(maxWidth: kSheetMaxWidth),
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
      _practiceAnswers[i].answered = _practiceAnswersMap.containsKey(i);
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

  Widget _buildAnsweredResult(
      AppState appState, Question question, AppThemeColors ac) {
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
          borderRadius: BorderRadius.circular(MaoRadius.control),
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
                        fontSize: MaoType.h3,
                        color: isCorrect ? ac.success : ac.danger)),
              ],
            ),
            const SizedBox(height: 10),
            if (qt == 'fill_blank') ...[
              Text('你的答案: $userAnswer',
                  style: TextStyle(
                      fontSize: MaoType.body,
                      color: isCorrect ? ac.success : ac.danger)),
              if (!isCorrect) ...[
                const SizedBox(height: 4),
                Text('正确答案: $correctAnswer',
                    style: TextStyle(
                        fontSize: MaoType.body,
                        fontWeight: FontWeight.bold,
                        color: ac.success)),
              ],
            ],
            if (qt == 'true_false') ...[
              Text('你选择了: ${userAnswer == "对" ? "✓ 正确" : "✗ 错误"}',
                  style: TextStyle(
                      fontSize: MaoType.body,
                      color: isCorrect ? ac.success : ac.danger)),
              if (!isCorrect)
                Text('正确答案: ${correctAnswer == "对" ? "✓ 正确" : "✗ 错误"}',
                    style: TextStyle(
                        fontSize: MaoType.body,
                        fontWeight: FontWeight.bold,
                        color: ac.success)),
            ],
          ],
        ),
      );
    }
    return _buildAnsweredOptions(appState, question, ac);
  }

  Widget _buildAnsweredOptions(
      AppState appState, Question question, AppThemeColors ac) {
    final lastRecord = appState.lastAnswerRecord;
    final userAnswer = lastRecord?.userAnswer ?? '';
    final correctAnswer = question.correctAnswer.toUpperCase().trim();
    final isMulti = question.questionType == 'multi_choice';
    final userAnswers = isMulti
        ? userAnswer.split(',').map((e) => e.trim().toUpperCase()).toSet()
        : {userAnswer.toUpperCase().trim()};
    final correctAnswers = isMulti
        ? correctAnswer.split(',').map((e) => e.trim().toUpperCase()).toSet()
        : {correctAnswer};

    final options = question.options;
    if (options.isEmpty) return const SizedBox.shrink();

    // v1.0.2 UI 审查修复：正确/错误高亮统一 success(绿)/danger(红) 语义色
    final ac = AppThemeColors.of(context);

    final optionWidgets = options.asMap().entries.map((entry) {
      final idx = entry.key;
      final label = String.fromCharCode(65 + idx);
      final isCorrect = correctAnswers.contains(label);
      final isUserWrong = !isCorrect && userAnswers.contains(label);

      Color bgColor = ac.surfaceAlt;
      Color textColor = ac.textPrimary;
      Color borderColor = ac.border;
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
            borderRadius: BorderRadius.circular(MaoRadius.control),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: isCorrect
                      ? ac.success
                      : isUserWrong
                          ? ac.danger
                          : ac.border,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: isCorrect
                      ? Icon(Icons.check, size: 14, color: ac.onAccent)
                      : isUserWrong
                          ? Icon(Icons.close, size: 14, color: ac.onAccent)
                          : Text(label,
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: MaoType.body,
                                  color: ac.textSecondary)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  entry.value,
                  style: TextStyle(
                      fontSize: MaoType.body, color: textColor, height: 1.4),
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();
    return _arrangeOptionWidgets(optionWidgets);
  }

  Widget _buildResultFeedback(
      AppState appState, Question question, AppThemeColors ac) {
    final lastRecord = appState.lastAnswerRecord;
    if (lastRecord == null) return const SizedBox.shrink();
    final correct = question.correctAnswer;
    final user = lastRecord.userAnswer;
    DebugLogService.instance.logResultFeedback(correct, user ?? 'null');
    return QuizResultFeedback(
      correctAnswer: correct,
      userAnswer: user ?? '',
      isCorrect: lastRecord.isCorrect,
    );
  }

  /// v1.28.1 新生引导：跳转设置页配置 API Key，返回后刷新解析区
  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => const SettingsScreen(group: SettingsGroup.ai)),
    );
    if (mounted) setState(() {});
  }

  Widget _buildShowAnalysisButton(AppState appState, AppThemeColors ac) {
    // 无 Key 时展开的是题目自带解析（见 _loadAnalysis 的回落），标题也照此写明，
    // 免得用户以为点了会调 AI——与 _buildAnalysisArea 里的小条/面板标题保持同一口径。
    final bool noKey = !appState.settings.isConfigured;
    final bool hasBuiltin =
        (appState.currentQuestion?.analysis?.trim() ?? '').isNotEmpty;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        icon: const Icon(Icons.psychology, size: 18),
        label: Text(noKey && hasBuiltin ? '查看示例解析' : '查看 AI 解析'),
        onPressed: () {
          setState(() => _showAnalysis = true);
          appState.showAnalysis();
        },
      ),
    );
  }

  Widget _buildRegenerateButton(AppState appState, AppThemeColors ac) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        icon: const Icon(Icons.refresh, size: 16),
        label: const Text('重新生成解析', style: TextStyle(fontSize: MaoType.body)),
        style: OutlinedButton.styleFrom(
          foregroundColor: ac.textSecondary,
          padding: const EdgeInsets.symmetric(vertical: 8),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(MaoRadius.small)),
        ),
        onPressed: () {
          // v1.0.2: API 未配置拦截重新生成
          if (!appState.settings.isConfigured) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: const Text('请先在设置中配置 API Key 后再查看解析。'),
                  backgroundColor: AppThemeColors.of(context).warning,
                  action:
                      SnackBarAction(label: '去设置', onPressed: _openSettings)),
            );
            return;
          }
          appState.regenerateAnalysis();
        },
      ),
    );
  }

  Widget _buildAnalysisArea(
      AppState appState, Question question, AppThemeColors ac) {
    final lastRecord = appState.lastAnswerRecord;
    final isCorrect = lastRecord?.isCorrect ?? false;
    final bool noKey = !appState.settings.isConfigured;
    // 题目自带解析（示例题库每题都有）：无 Key 时也能看，_loadAnalysis 会回落到它
    final bool hasBuiltin = (question.analysis?.trim() ?? '').isNotEmpty;

    if (isCorrect && !_showManualAnalysis) {
      // 答对后默认折叠解析；点卡片才展示。
      // 注意：只有「既没 Key、又没有自带解析」时才拦截——此前这里无条件要求 Key，
      // 导致无 Key 用户在示例题库里答对题、点开解析却被拦（而答错时同一份自带解析
      // 能正常显示），与 _loadAnalysis 的回落逻辑及产品承诺都矛盾。
      return QuizViewAnalysisCard(
        exampleOnly: noKey && hasBuiltin,
        onTap: () {
          if (noKey && !hasBuiltin) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: const Text('请先在设置中配置 API Key 后再查看解析。'),
                  backgroundColor: AppThemeColors.of(context).warning,
                  action:
                      SnackBarAction(label: '去设置', onPressed: _openSettings)),
            );
            return;
          }
          setState(() => _showManualAnalysis = true);
          appState.showAnalysis();
        },
      );
    }

    return MJSurface(
      padding: const EdgeInsets.all(MaoSpace.sm + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.psychology_outlined, color: ac.accent, size: 20),
              const SizedBox(width: 8),
              Text(noKey ? '示例解析' : 'AI解析',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: MaoType.h3,
                      color: ac.accent)),
              const Spacer(),
              if (appState.analysisLoading)
                SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: ac.accent)),
            ],
          ),
          const SizedBox(height: 10),
          if (appState.currentAnalysis != null)
            AiResponseWidget(text: appState.currentAnalysis!)
          else if (appState.analysisLoading)
            Text('正在生成AI解析...',
                style:
                    TextStyle(color: ac.textSecondary, fontSize: MaoType.body))
          else ...[
            // v1.28.1 新生引导：无 Key 且无自带解析 → 引导去配置，而不是裸错误
            Text('配置 API Key 后，这里会显示 AI 逐题讲解\n（题眼破题 · 关键词高亮 · 追问）。',
                style:
                    TextStyle(color: ac.textSecondary, fontSize: MaoType.body)),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.settings, size: 16),
              label: const Text('去设置'),
              onPressed: _openSettings,
            ),
          ],
          if (appState.currentAnalysis != null &&
              appState.currentAnalysis!.isNotEmpty) ...[
            const SizedBox(height: MaoSpace.sm + 2),
            const Divider(),
            const SizedBox(height: MaoSpace.xs),
            // v1.28：追问改为独立全屏对话页（旧版嵌在解析卡里空间局促）
            _buildChatEntry(appState, ac),
          ],
        ],
      ),
    );
  }

  /// AI 对话入口（v1.28）：进入独立全屏对话页
  ///
  /// 旧版把追问聊天嵌在解析卡内，空间局促、要滚很久才看得到。
  /// 现在解析卡下方只放一个入口，点进去是全屏对话页。
  Widget _buildChatEntry(AppState appState, AppThemeColors ac) {
    final count = appState.followUpHistory.length;
    final hasHistory = count > 0;
    return Material(
      color: ac.surface,
      borderRadius: MaoRadius.controlBorder,
      child: InkWell(
        borderRadius: MaoRadius.controlBorder,
        onTap: () async {
          if (!appState.settings.isConfigured) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: const Text('请先在设置中配置 API Key 后再追问。'),
                  backgroundColor: ac.warning,
                  action:
                      SnackBarAction(label: '去设置', onPressed: _openSettings)),
            );
            return;
          }
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AiChatScreen()),
          );
          if (mounted) setState(() {}); // 返回后刷新入口上的历史条数
        },
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: MaoSpace.sm + 2, vertical: MaoSpace.sm + 2),
          decoration: BoxDecoration(
            borderRadius: MaoRadius.controlBorder,
            border: Border.all(color: ac.border, width: MaoShadow.hairline),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: ac.accentSoft,
                  borderRadius: MaoRadius.smallBorder,
                ),
                child: Icon(Icons.forum_outlined, size: 18, color: ac.accent),
              ),
              const SizedBox(width: MaoSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('向 AI 追问',
                        style: MaoType.h3Style
                            .copyWith(color: ac.textPrimary, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(
                      hasHistory ? '已有 $count 条对话记录' : '没看懂？直接问，对话式讲解',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MaoType.captionStyle
                          .copyWith(color: ac.textSecondary),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  size: 20, color: ac.textTertiary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(AppState appState, AppThemeColors ac) {
    // v1.0.2 统一重构：练习模式底部栏（自由跳题 + 提交练习）
    if (widget.quizMode == QuizMode.practice) {
      final answered = _practiceAnswersMap.length;
      final total = appState.quizQuestions.length;
      return Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
        decoration: BoxDecoration(
          color: ac.background,
          boxShadow: [
            BoxShadow(
                color: ac.border.withOpacity(0.08),
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
                                  ? ac.accent
                                  : ans
                                      ? ac.accent.withOpacity(0.35)
                                      : ac.surfaceAlt,
                              border: cur
                                  ? Border.all(color: ac.onAccent, width: 2)
                                  : null,
                            ),
                            child: Center(
                              child: Text('${i + 1}',
                                  style: TextStyle(
                                      fontSize: MaoType.micro,
                                      fontWeight: cur
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      color:
                                          cur ? ac.onAccent : ac.textPrimary)),
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
      padding: const EdgeInsets.all(MaoSpace.md),
      decoration: BoxDecoration(
        color: ac.background,
        // 精密暗色：底栏与内容的分隔用一条发丝线，不用投影
        border: Border(
            top: BorderSide(color: ac.border, width: MaoLine.width)),
      ),
      child: appState.isLastQuestion
          ? MJButton(
              expand: true,
              label: widget.quizMode == QuizMode.memorize
                  ? '回到首页'
                  : '完成刷题，查看小结',
              onPressed: () {
                if (widget.quizMode == QuizMode.memorize) {
                  _handleExit(appState);
                } else {
                  _handleEndSession(appState);
                }
              },
            )
          : Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: Icon(
                        _inErrorBook ? Icons.bookmark : Icons.bookmark_border,
                        size: 17),
                    // v1.0.2 UI 审查修复：单行不换行 + 紧凑内边距（竖排问题）
                    label: Text(_inErrorBook ? '已收藏' : '错题本',
                        maxLines: 1,
                        softWrap: false,
                        style: const TextStyle(fontSize: MaoType.body)),
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
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(fontSize: MaoType.body)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: ac.textSecondary,
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
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(fontSize: MaoType.h3)),
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
        content: Text(
            '共$total题，已答$answered题，未答${total - answered}题。\n\n提交后将无法修改，确定提交？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('继续检查')),
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
  Future<void> _handleEndSession(AppState appState) async {
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
        await _handleEndSession(appState);
      } else {
        Navigator.pop(context);
      }
    } finally {
      _ending = false;
    }
  }
}

/// v1.0.3 窗口自适应：选项随可用宽度自动排列。
/// 每个选项固定单元宽（300，含底部间距），宽度足够时自然形成多列，
/// 窗口拖窄时自动折行回到单列；单元高度取同排最大值，不裁剪长文本。
class _AdaptiveOptionsColumn extends StatelessWidget {
  const _AdaptiveOptionsColumn({required this.children});

  final List<Widget> children;

  static const double _cellWidth = 300;
  static const double _hGap = 12;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      final cols = (w / (_cellWidth + _hGap)).floor().clamp(1, children.length);
      if (cols <= 1) {
        return Column(children: children);
      }
      final cellW = (w - _hGap * (cols - 1)) / cols;
      final rows = <Widget>[];
      for (var i = 0; i < children.length; i += cols) {
        final row = children.sublist(
            i, i + cols > children.length ? children.length : i + cols);
        rows.add(IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var j = 0; j < row.length; j++) ...[
                if (j > 0) const SizedBox(width: _hGap),
                SizedBox(width: cellW, child: row[j]),
              ],
            ],
          ),
        ));
      }
      return Column(children: rows);
    });
  }
}
