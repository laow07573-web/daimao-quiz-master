import 'package:flutter/material.dart';

import '../services/guide_service.dart';
import '../services/theme_service.dart';
import '../utils/design_tokens.dart';
import '../widgets/kit/mj_kit.dart';
import '../widgets/kit/mj_logo.dart';
import 'main_shell.dart';

/// 引导页内容（三页 · 与真实功能对齐，不承诺界面上不存在的行为）
class _GuidePage {
  const _GuidePage(this.icon, this.title, this.body, this.tags);

  final IconData icon;
  final String title;
  final String body;
  final List<String> tags;
}

const List<_GuidePage> _guidePages = [
  _GuidePage(
    Icons.library_add_outlined,
    '先导入一份题库',
    'DOCX、PDF、JSON 与题库文件都能导入；也可以一键导入内置的「医学基础速练」，先跑通一遍流程。',
    ['DOCX / PDF', 'JSON 题库', '示例题库'],
  ),
  _GuidePage(
    Icons.quiz_outlined,
    '然后开始刷题',
    '单选、多选、填空、简答都支持；提交即判对错，没掌握的题会按记忆曲线排进复习。',
    ['四类题型', '错题本', 'FSRS 复习'],
  ),
  _GuidePage(
    Icons.insights_outlined,
    '再看数据说话',
    '正确率、连击、年度热力图与薄弱知识点一屏看完；错题本按「到期 / 收藏」筛选。'
        'AI 解析与追问填自己的 API Key 即可用，不填也能刷题与看自带解析。',
    ['统计 / 热力图', '薄弱知识点', 'BYOK 可选'],
  ),
];

/// 首次使用引导（v1.28.2 · Mao Des 2.0）
///
/// 三页动效引导：导入题库 → 开始刷题 → 看统计与错题本。
/// 每页内容按 [MaoMotion] 的节奏逐级入场（图标 → 步骤 → 标题 → 正文 → 要点），
/// 可左右滑动，右上角「跳过」随时收尾，末页「开始使用」进入应用。
///
/// 展示时机由 [GuideService] 决定（仅首启一次）；
/// 「我的 → 重看使用引导」用 `asFirstRun: false` 打开，收尾后直接返回原页面。
/// 系统「减弱动态效果」开启时（[MaoMotion.effective] 返回零时长）只呈现终态、不做位移。
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, this.asFirstRun = false});

  /// true：首启插播——收尾/跳过后用 [MainShell] 替换本页，不让返回键回到启动页；
  /// false：从「我的」重看——收尾/跳过后直接 pop 返回。
  final bool asFirstRun;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final PageController _pc = PageController();

  /// 每页入场：切页时 from 0 重播
  late final AnimationController _enter;

  /// 图标柔光呼吸（细分幅度，避免抢注意力）
  late final AnimationController _pulse;

  bool _started = false;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 640));
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2400));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 系统「减弱动态效果」开启时 MaoMotion.effective 返回零时长 → 只呈终态
    final reduced = MaoMotion.effective(context, MaoMotion.slow) == Duration.zero;
    if (!_started) {
      _started = true;
      if (reduced) {
        _enter.value = 1;
        _pulse.value = 0;
      } else {
        _enter.forward();
        _pulse.repeat(reverse: true);
      }
      return;
    }
    // 运行中才打开「减弱动态效果」：停掉呼吸，不再重播入场
    if (reduced && _pulse.isAnimating) _pulse.stop();
  }

  @override
  void dispose() {
    _enter.dispose();
    _pulse.dispose();
    _pc.dispose();
    super.dispose();
  }

  /// 逐级入场：第 [slot] 个元素在自己的时间窗内上浮淡入
  Widget _stagger(int slot, Widget child) {
    final begin = (slot * 0.10).clamp(0.0, 0.55);
    final end = (begin + 0.50).clamp(0.0, 1.0);
    return AnimatedBuilder(
      animation: _enter,
      builder: (_, __) {
        final t = Curves.easeOutCubic
            .transform(((_enter.value - begin) / (end - begin)).clamp(0.0, 1.0));
        return Opacity(
          opacity: t,
          child:
              Transform.translate(offset: Offset(0, (1 - t) * 14), child: child),
        );
      },
    );
  }

  void _onPageChanged(int i) {
    setState(() => _page = i);
    // 切页重播入场（被滑入的页可能早已 build，靠这里补一次动画）
    _enter.forward(from: 0);
  }

  void _next() {
    if (_page >= _guidePages.length - 1) {
      _finish();
      return;
    }
    final d = MaoMotion.effective(context, MaoMotion.slow);
    if (d == Duration.zero) {
      // 减弱动态效果：animateToPage 不接受零时长（内部断言 duration > 0），直接跳页
      _pc.jumpToPage(_page + 1);
      return;
    }
    _pc.nextPage(duration: d, curve: MaoMotion.emphasized);
  }

  /// 收尾（跳过 / 开始使用 / 首启时按返回键）：标记已看过并离开本页
  Future<void> _finish() async {
    await GuideService.instance.markSeen();
    if (!mounted) return;
    if (widget.asFirstRun) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainShell()),
      );
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    final isLast = _page == _guidePages.length - 1;

    return PopScope(
      // 首启插播时不让返回键退回启动页：按返回等同「跳过」
      canPop: !widget.asFirstRun,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && widget.asFirstRun) _finish();
      },
      child: Scaffold(
        backgroundColor: ac.background,
        body: SafeArea(
          child: Column(
            children: [
              // ── 顶栏：品牌标记 + 跳过 ──
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    MaoSpace.md, MaoSpace.sm, MaoSpace.xs, 0),
                child: Row(
                  children: [
                    const MJLogoBadge(box: 28, padding: 4),
                    const Spacer(),
                    MJButton(
                      label: '跳过',
                      kind: MJButtonKind.ghost,
                      dense: true,
                      onPressed: _finish,
                    ),
                  ],
                ),
              ),

              // ── 三页引导 ──
              Expanded(
                child: PageView.builder(
                  controller: _pc,
                  onPageChanged: _onPageChanged,
                  itemCount: _guidePages.length,
                  itemBuilder: (_, i) => _buildPage(i, ac),
                ),
              ),

              // ── 页码指示：当前项拉长 ──
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _guidePages.length; i++)
                    AnimatedContainer(
                      duration: MaoMotion.effective(context, MaoMotion.normal),
                      curve: MaoMotion.standard,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _page ? 18 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: i == _page ? ac.accent : ac.border,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              ),

              // ── 主行动：末页换成「开始使用」 ──
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    MaoSpace.md, MaoSpace.md, MaoSpace.md, MaoSpace.md),
                child: MJButton(
                  label: isLast ? '开始使用' : '下一步',
                  icon: isLast ? Icons.check_rounded : Icons.arrow_forward,
                  expand: true,
                  onPressed: _next,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPage(int index, AppThemeColors ac) {
    final p = _guidePages[index];
    return Center(
      // 小窗口/大字号下不裁内容：页内可纵向滚动
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
            horizontal: MaoSpace.xl, vertical: MaoSpace.sm),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _stagger(0, _iconBadge(p.icon, ac)),
              const SizedBox(height: MaoSpace.lg),
              _stagger(
                1,
                Text('第 ${index + 1} 步 · 共 ${_guidePages.length} 步',
                    style: MaoType.microStyle.copyWith(
                        color: ac.textTertiary, letterSpacing: 1.2)),
              ),
              const SizedBox(height: MaoSpace.xs),
              _stagger(
                2,
                Text(p.title,
                    textAlign: TextAlign.center,
                    style: MaoType.h1Style
                        .copyWith(fontSize: 22, color: ac.textPrimary)),
              ),
              const SizedBox(height: MaoSpace.sm),
              _stagger(
                3,
                Text(p.body,
                    textAlign: TextAlign.center,
                    style: MaoType.bodyStyle
                        .copyWith(height: 1.75, color: ac.textSecondary)),
              ),
              const SizedBox(height: MaoSpace.md),
              _stagger(
                4,
                Wrap(
                  spacing: MaoSpace.xs,
                  runSpacing: MaoSpace.xs,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final t in p.tags)
                      MJTag(t, tone: MJTagTone.neutral),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 图标位：面板 + 3% 呼吸缩放（层级仍靠发丝描边，不用阴影）
  Widget _iconBadge(IconData icon, AppThemeColors ac) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, child) => Transform.scale(
        scale: 1 + 0.03 * _pulse.value,
        child: child,
      ),
      child: MJSurface(
        tone: MJTone.alt,
        radius: MaoRadius.large,
        padding: const EdgeInsets.all(MaoSpace.lg),
        child: Icon(icon, size: 34, color: ac.accent),
      ),
    );
  }
}
