import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/theme_service.dart';
import '../../utils/design_tokens.dart';
import '../kit/mj_kit.dart';
import 'guide_controller.dart';
import 'guide_step.dart';

/// 互动式引导遮罩层（由 [GuideHost] 挂在 Navigator 之上）
///
/// 每一步都打在**真实控件**上：四块遮罩夹出一个洞，洞里的控件照常可点。
/// 用户点高亮处跳进二级页面时，[GuideController] 会把引导带到新页面，
/// 这里只负责跟着重新找目标、落定高亮。
class GuideTour extends StatefulWidget {
  const GuideTour({super.key, required this.controller});

  final GuideController controller;

  @override
  State<GuideTour> createState() => _GuideTourState();
}

class _GuideTourState extends State<GuideTour> {
  /// 锚点就绪前的重试间隔
  static const Duration _retryEvery = Duration(milliseconds: 100);

  /// 多久之内找不到锚点算「还在加载 / 用户还没进那一页」，
  /// 这段时间气泡提示「点高亮处继续」
  static const int _waitingTries = 40; // ≈ 4s

  /// 重试上限（≈ 90s）：跨页面引导要等用户自己动手点进二级页，
  /// 不能几秒找不到目标就放弃
  static const int _maxTries = 900;

  /// 落定后跟随滚动/窗口缩放的巡检间隔（用户滚一下，洞要跟着走）
  static const Duration _followEvery = Duration(milliseconds: 300);

  /// 气泡高度估算值：只用来挑「放洞上面还是下面」；
  /// 真实定位用 top/bottom 锚定，与气泡实际高度无关。
  static const double _bubbleEstHeight = 208;

  Rect? _hole;
  Timer? _retry;
  Timer? _follow;
  int _tries = 0;

  /// 本步最终落在哪个锚点上（可能是备选锚点之一），跟随巡检复用它
  String? _anchorId;

  /// 上一次量到的矩形：连续两次一致才落定（躲开异步数据引起的位移）
  Rect? _lastMeasured;
  String? _lastMeasuredId;

  /// 本步是否已经做过「滚进视区」
  bool _revealed = false;

  /// 首帧前不能 setState，也读不到 MediaQuery：先用字段接住，build 后再校准
  bool _built = false;
  Size? _screen;
  EdgeInsets _safe = EdgeInsets.zero;

  /// 上一次见到的步号 / 路由世代：控制器是同一个实例，
  /// 只能自己记住旧值才能判断「变了」
  late int _lastIndex;
  late int _lastRouteEpoch;

  GuideController get _guide => widget.controller;
  GuideStep get _step => _guide.step;

  @override
  void initState() {
    super.initState();
    _lastIndex = _guide.index;
    _lastRouteEpoch = _guide.routeEpoch;
    _prepare();
  }

  @override
  void didUpdateWidget(GuideTour oldWidget) {
    super.didUpdateWidget(oldWidget);
    final index = _guide.index;
    final epoch = _guide.routeEpoch;
    if (index != _lastIndex) {
      _lastIndex = index;
      _lastRouteEpoch = epoch;
      _prepare();
      return;
    }
    if (epoch != _lastRouteEpoch) {
      _lastRouteEpoch = epoch;
      // 路由变了（用户跳进了二级页 / 返回）：重测，当前锚点可能已经不可见
      _tries = 0;
      _revealed = false;
      _lastMeasured = null;
      _lastMeasuredId = null;
      _anchorId = null;
      _measureSoon();
    }
  }

  @override
  void dispose() {
    _retry?.cancel();
    _follow?.cancel();
    super.dispose();
  }

  void _setHole(Rect? r) {
    if (!mounted) return;
    if (!_built) {
      _hole = r;
      return;
    }
    setState(() => _hole = r);
  }

  /// 进入当前步：清状态、必要时切 Tab，然后等一帧再测量
  void _prepare() {
    _retry?.cancel();
    _follow?.cancel();
    _tries = 0;
    _lastMeasured = null;
    _lastMeasuredId = null;
    _anchorId = null;
    _revealed = false;
    if (_built) {
      setState(() => _hole = null);
    } else {
      _hole = null;
    }

    final tab = _step.tab;
    if (tab != null && tab != _guide.currentTab) {
      // 帧后再请求切页：initState 里同步 setState 到祖先会炸
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _guide.requestTab(tab);
      });
    }
    _measureSoon();
  }

  void _measureSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _measure();
    });
  }

  /// 读锚点矩形并落定高亮洞；一切「还没有」都按节奏重试
  void _measure() {
    final ids = _step.anchorIds;
    if (ids.isEmpty) {
      _setHole(null); // 本步没有可指的控件
      return;
    }
    // IndexedStack 的未选中页每帧照常布局 → 锚点矩形一直存在，只是用户看不见。
    // 必须等「本步该在的 Tab 已经选中」再量，否则会把洞打到别的页面上。
    if (_step.tab != null && _guide.currentTab != _step.tab) {
      _retryLater();
      return;
    }
    // 备选锚点：主锚点此刻不在（例如错题本还是空态）就退到下一个
    String? found;
    Rect? r;
    for (final id in ids) {
      final candidate = _guide.registry.rectOf(id);
      if (candidate != null) {
        found = id;
        r = candidate;
        break;
      }
    }
    if (found == null || r == null) {
      _retryLater();
      return;
    }
    // 目标在列表下方时先滚进视区（零时长立即定位，避免量到滚动中途的矩形）
    if (!_revealed && !_fullyVisible(r)) {
      _revealed = true;
      final ctx = _guide.registry.contextOf(found);
      if (ctx != null) {
        unawaited(Scrollable.ensureVisible(ctx,
            alignment: 0.5, duration: Duration.zero));
      }
      _retryLater();
      return;
    }
    _anchorId = found;
    // 异步数据 / 路由转场会让控件位移：连续两次量到同一矩形才算稳定
    if (_lastMeasured != r || _lastMeasuredId != found) {
      _lastMeasured = r;
      _lastMeasuredId = found;
      _retryLater();
      return;
    }
    final visible = _visiblePart(r);
    if (visible == null) {
      _retryLater();
      return;
    }
    // 稍微放大一圈：留出可点边距，也避免描边切着控件边缘
    _setHole(visible.inflate(MaoSpace.xxs));
    _startFollow();
  }

  void _retryLater() {
    _tries++;
    // 路由变化当时没判成功的那次前进：新页面异步加载完（锚点出现）就补上
    _guide.tickPendingFollow();
    if (_tries > _maxTries) {
      // 兜底：目标始终不出现就保持居中气泡——说明照讲，绝不卡住用户。
      //（也不拿屏幕外的矩形打洞：洞必须落在看得见的地方。）
      _setHole(null);
      return;
    }
    _retry?.cancel();
    _retry = Timer(_retryEvery, () {
      if (mounted) _measure();
    });
  }

  /// 落定后继续盯着锚点：用户滚动列表 / 缩放窗口时洞要跟着走
  void _startFollow() {
    _follow?.cancel();
    _follow = Timer.periodic(_followEvery, (_) {
      if (!mounted) return;
      final id = _anchorId;
      if (id == null) return;
      if (_step.tab != null && _guide.currentTab != _step.tab) return;
      final r = _guide.registry.rectOf(id);
      final visible = r == null ? null : _visiblePart(r);
      if (visible == null) {
        // 落定的锚点没了（例如错题本由空态变成了有数据）：重新挑锚点
        if (_step.anchorIds.length > 1) {
          _measure();
        } else {
          _setHole(null);
        }
        return;
      }
      final next = visible.inflate(MaoSpace.xxs);
      if (next != _hole) _setHole(next);
    });
  }

  /// 目标是否完整落在可视区内（不完整就先滚一下）
  bool _fullyVisible(Rect r) {
    final size = _screen;
    if (size == null) return false;
    final area =
        Rect.fromLTRB(0, _safe.top, size.width, size.height - _safe.bottom);
    return area.contains(r.topLeft) && area.contains(r.bottomRight);
  }

  /// 锚点在可视区内的部分；只露一角就返回 null（这种高亮没有意义）
  Rect? _visiblePart(Rect r) {
    final size = _screen;
    if (size == null) return null;
    final area =
        Rect.fromLTRB(0, _safe.top, size.width, size.height - _safe.bottom);
    final inter = r.intersect(area);
    if (inter.width < 40 || inter.height < 24) return null;
    return inter;
  }

  /// 气泡左下角的状态提示：让用户始终知道「现在该做什么」
  String _hint() {
    if (_hole != null) {
      return _step.awaitAction ? '点高亮处继续，我们跟着你走' : '高亮处可直接点';
    }
    if (_step.anchorIds.isEmpty) return '读完点右边继续';
    if (_tries <= _waitingTries) return '点高亮处继续';
    // 导航步没有「下一步」按钮，兜底提示就不能再让人去找它
    return _step.awaitAction ? '这步的入口还没出现，可点跳过' : '这步的入口还没出现，可点跳过或下一步';
  }

  void _next() => _guide.next();

  void _skip() => unawaited(_guide.skip());

  @override
  Widget build(BuildContext context) {
    _built = true;
    final ac = AppThemeColors.of(context);
    final media = MediaQuery.of(context);
    _screen = media.size;
    _safe = media.padding;

    final hole = _hole;
    final anim = MaoMotion.effective(context, MaoMotion.slow);
    // 中性黑遮罩（不用画布色：浅色主题下画布色等于白色蒙版，压不暗）
    const scrim = MaoScrim.guide;

    return Stack(
      children: [
        if (hole == null)
          Positioned.fill(child: const _ScrimBlock(color: scrim))
        else ...[
          // 四块遮罩夹出洞：洞内不铺遮罩 → 高亮处的真实控件照常可点
          AnimatedPositioned(
            duration: anim,
            curve: MaoMotion.emphasized,
            left: 0,
            right: 0,
            top: 0,
            height: math.max(0, hole.top),
            child: const _ScrimBlock(color: scrim),
          ),
          AnimatedPositioned(
            duration: anim,
            curve: MaoMotion.emphasized,
            left: 0,
            right: 0,
            top: hole.bottom,
            bottom: 0,
            child: const _ScrimBlock(color: scrim),
          ),
          AnimatedPositioned(
            duration: anim,
            curve: MaoMotion.emphasized,
            left: 0,
            top: hole.top,
            width: math.max(0, hole.left),
            height: hole.height,
            child: const _ScrimBlock(color: scrim),
          ),
          AnimatedPositioned(
            duration: anim,
            curve: MaoMotion.emphasized,
            left: hole.right,
            top: hole.top,
            right: 0,
            height: hole.height,
            child: const _ScrimBlock(color: scrim),
          ),
          // 洞的强调描边（不拦截触摸）
          AnimatedPositioned(
            duration: anim,
            curve: MaoMotion.emphasized,
            left: hole.left,
            top: hole.top,
            width: hole.width,
            height: hole.height,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(MaoRadius.large),
                  border: Border.all(
                      color: ac.accent, width: MaoLine.width + 0.5),
                ),
              ),
            ),
          ),
        ],
        _bubble(context, ac, media),
      ],
    );
  }

  Widget _bubble(
      BuildContext context, AppThemeColors ac, MediaQueryData media) {
    final step = _step;
    final total = _guide.steps.length;
    final index = _guide.index;
    final hole = _hole;
    const gap = MaoSpace.sm;

    // 竖排位：优先洞下方，放不下改洞上方（用 bottom 锚定，气泡高度不确定也精确）
    double? top;
    double? bottom;
    if (hole != null) {
      final roomBelow = media.size.height - media.padding.bottom - hole.bottom;
      final roomAbove = hole.top - media.padding.top;
      if (roomBelow >= _bubbleEstHeight + gap) {
        top = hole.bottom + gap;
      } else if (roomAbove >= _bubbleEstHeight + gap) {
        bottom = media.size.height - (hole.top - gap);
      } else {
        // 上下都放不下（目标几乎占满一屏）：气泡压到底部，
        // 让上方仍然看得出「这一块被高亮」，而不是居中去盖住整个洞
        bottom = media.padding.bottom + MaoSpace.md;
      }
    }

    final card = MJSurface(
      padding: const EdgeInsets.all(MaoSpace.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MJTag('第 ${index + 1} 步 / 共 $total 步', tone: MJTagTone.accent),
              const Spacer(),
              // 跳过永远可用：引导不能把人困住
              MJButton(
                label: '跳过',
                kind: MJButtonKind.ghost,
                dense: true,
                onPressed: _skip,
              ),
            ],
          ),
          const SizedBox(height: MaoSpace.sm),
          Text(step.title,
              style: MaoType.h2Style.copyWith(
                  fontWeight: FontWeight.w600, color: ac.textPrimary)),
          const SizedBox(height: MaoSpace.xxs + 2),
          Text(step.body,
              style: MaoType.bodyStyle
                  .copyWith(height: 1.7, color: ac.textSecondary)),
          const SizedBox(height: MaoSpace.md),
          Row(
            children: [
              Expanded(
                child: Text(
                  _hint(),
                  style: MaoType.microStyle.copyWith(color: ac.textTertiary),
                ),
              ),
              // 导航步（awaitAction）不给「下一步」：这一步的进展是用户真的点进去，
              // 一键跳过只会把他带到「页面还没打开」的下一步去。跳过仍在右上角。
              if (!step.awaitAction) ...[
                const SizedBox(width: MaoSpace.xs),
                MJButton(
                  label: step.nextLabel ??
                      (index == total - 1 ? '完成' : '下一步'),
                  icon: index == total - 1
                      ? Icons.check_rounded
                      : Icons.arrow_forward,
                  dense: true,
                  onPressed: _next,
                ),
              ],
            ],
          ),
        ],
      ),
    );

    // 每步入场轻淡入：key 随步号换血重播
    final animated = TweenAnimationBuilder<double>(
      key: ValueKey<int>(index),
      tween: Tween<double>(begin: 0, end: 1),
      duration: MaoMotion.effective(context, MaoMotion.normal),
      curve: MaoMotion.standard,
      builder: (_, t, child) => Opacity(
        opacity: t,
        child:
            Transform.translate(offset: Offset(0, (1 - t) * 10), child: child),
      ),
      child: card,
    );

    final width =
        math.min(380.0, math.max(240.0, media.size.width - MaoSpace.md * 2));

    if (hole == null) {
      return Positioned.fill(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width),
            child: animated,
          ),
        ),
      );
    }
    return Positioned(
      left: MaoSpace.md,
      right: MaoSpace.md,
      top: top,
      bottom: bottom,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width),
          child: animated,
        ),
      ),
    );
  }
}

/// 遮罩块：吞掉点击（洞以外的误触不该穿透到界面）；
/// 洞内不铺遮罩，所以高亮处的真实控件照常可点。
class _ScrimBlock extends StatelessWidget {
  const _ScrimBlock({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: ColoredBox(color: color),
    );
  }
}
