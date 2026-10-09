import 'dart:async';
import 'package:flutter/scheduler.dart';

/// 帧时间探针：把「卡」变成可测量的数字。
///
/// 2026-10-09 用户第二次报「统计页与首页存在明显卡顿」。此前几轮都是靠代码审查
/// 猜瓶颈（趋势图 O(n²)、热力图 371 个 Tooltip、切页重建），虽然都修到了真问题，
/// 但没有一次能拿数据确认「修完还有多卡、卡在 build 还是 raster」。
///
/// 这里用 [SchedulerBinding.addTimingsCallback] 收集 [FrameTiming]：
/// - `buildDuration`：widget 构建 + 布局（Dart 侧，CPU）
/// - `rasterDuration`：光栅化（GPU 侧，绘制复杂度）
///
/// 两者能直接区分病因：build 高＝树太重/重建太多；raster 高＝绘制/图层太重
/// （大范围 Opacity 的 saveLayer、未分层的复杂绘制等）。
///
/// 只在 debug/profile 启用（release 不注册回调，零开销），超阈值帧写进日志，
/// 真机复现后用 `adb logcat` 取数据。
// ignore_for_file: avoid_print
class PerfProbe {
  PerfProbe._();
  static final PerfProbe instance = PerfProbe._();

  /// 判定「卡」的阈值：60fps 的预算是 16.6ms，这里取 16ms
  static const Duration slowFrame = Duration(milliseconds: 16);

  /// 明显掉帧的阈值（一帧超过两倍预算）
  static const Duration verySlowFrame = Duration(milliseconds: 33);

  static const int _capacity = 200;

  final List<FrameTiming> _slow = [];
  bool _running = false;
  int _total = 0;
  int _verySlow = 0;

  bool get running => _running;
  int get totalFrames => _total;
  int get slowCount => _slow.length;
  int get verySlowCount => _verySlow;

  List<FrameTiming> get slowFrames => List.unmodifiable(_slow);

  // ── 窗口统计 ──
  // 只看「超过 16ms 的帧」会漏掉「一直停在 12~15ms 高位」的情况，而那在真机上
  // 同样体感发涩。所以再按时间窗口输出**所有帧**的分布（平均 / P90 / 最大）。
  final List<int> _winBuild = [];
  final List<int> _winRaster = [];
  int _winStartMs = 0;
  static const int _winMs = 2000;
  static const int _winMinFrames = 20;

  void start() {
    if (_running) return;
    _running = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _winStartMs = DateTime.now().millisecondsSinceEpoch;
    // 心跳：确认探针活着，并暴露「这段时间到底有没有帧」。
    // 静止页面 Flutter 不渲染帧、timings 回调自然不来——没有心跳就分不清
    // 「没掉帧」和「根本没采集到」。
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 2), (_) {
      print(
          '[PERF] HB frames=$_total slow=${_slow.length} win=${_winBuild.length} '
          'lastBuild=${_lastBuildMs.toStringAsFixed(1)}ms '
          'lastRaster=${_lastRasterMs.toStringAsFixed(1)}ms');
    });
    print('[PERF] probe started, slowFrame=${slowFrame.inMilliseconds}ms');
  }

  Timer? _heartbeat;
  double _lastBuildMs = 0;
  double _lastRasterMs = 0;

  void stop() {
    if (!_running) return;
    _running = false;
    _heartbeat?.cancel();
    _heartbeat = null;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
  }

  void reset() {
    _slow.clear();
    _total = 0;
    _verySlow = 0;
    _winBuild.clear();
    _winRaster.clear();
    _winStartMs = DateTime.now().millisecondsSinceEpoch;
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      _total++;
      final build = t.buildDuration;
      final raster = t.rasterDuration;
      final worst = build > raster ? build : raster;

      _winBuild.add(build.inMicroseconds);
      _winRaster.add(raster.inMicroseconds);
      _lastBuildMs = build.inMicroseconds / 1000;
      _lastRasterMs = raster.inMicroseconds / 1000;

      if (worst >= slowFrame) {
        _slow.add(t);
        if (_slow.length > _capacity) _slow.removeAt(0);
        if (worst >= verySlowFrame) _verySlow++;
        // 一行一帧，便于 logcat 过滤统计
        print('[PERF] SLOW build=${_ms(build)}ms raster=${_ms(raster)}ms '
            'vsync=${_ms(t.vsyncOverhead)}ms total=${_ms(t.totalSpan)}ms');
      }
    }
    _maybeFlushWindow();
  }

  /// 每 [_winMs] 输出一段窗口摘要（所有帧，不只是慢帧）
  void _maybeFlushWindow() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _winStartMs < _winMs) return;
    if (_winBuild.length < _winMinFrames) {
      _winStartMs = now;
      _winBuild.clear();
      _winRaster.clear();
      return;
    }
    print('[PERF] WIN frames=${_winBuild.length} '
        'build(avg/p90/max)=${_us(_avg(_winBuild))}/${_us(_p90(_winBuild))}/${_us(_max(_winBuild))} '
        'raster(avg/p90/max)=${_us(_avg(_winRaster))}/${_us(_p90(_winRaster))}/${_us(_max(_winRaster))}');
    _winStartMs = now;
    _winBuild.clear();
    _winRaster.clear();
  }

  static int _avg(List<int> v) =>
      v.isEmpty ? 0 : v.reduce((a, b) => a + b) ~/ v.length;
  static int _max(List<int> v) =>
      v.isEmpty ? 0 : v.reduce((a, b) => a > b ? a : b);
  static int _p90(List<int> v) {
    if (v.isEmpty) return 0;
    final sorted = [...v]..sort();
    return sorted[(sorted.length * 0.9).floor().clamp(0, sorted.length - 1)];
  }

  static String _us(int micros) => (micros / 1000).toStringAsFixed(1);

  static String _ms(Duration d) => (d.inMicroseconds / 1000).toStringAsFixed(1);

  /// 一行摘要（开发者选项 / 日志用）
  String summary() {
    if (_total == 0) return '未采集到帧';
    if (_slow.isEmpty) {
      return '共 $_total 帧，全部在 ${slowFrame.inMilliseconds}ms 内';
    }
    var worstBuild = Duration.zero;
    var worstRaster = Duration.zero;
    var sumBuild = Duration.zero;
    var sumRaster = Duration.zero;
    for (final t in _slow) {
      if (t.buildDuration > worstBuild) worstBuild = t.buildDuration;
      if (t.rasterDuration > worstRaster) worstRaster = t.rasterDuration;
      sumBuild += t.buildDuration;
      sumRaster += t.rasterDuration;
    }
    return '共 $_total 帧，慢帧 ${_slow.length}（其中 ≥${verySlowFrame.inMilliseconds}ms '
        '$_verySlow 帧）；慢帧里 build 平均 ${_ms(Duration(microseconds: sumBuild.inMicroseconds ~/ _slow.length))}ms/'
        '最慢 ${_ms(worstBuild)}ms，raster 平均 '
        '${_ms(Duration(microseconds: sumRaster.inMicroseconds ~/ _slow.length))}ms/'
        '最慢 ${_ms(worstRaster)}ms';
  }
}
