import 'package:flutter/material.dart';
import '../models/ink_annotation.dart';

/// 批注工具（REQ-009/010/014）
enum AnnoTool { pen, eraser, select }

/// 手写批注交互状态机（v1.0.3 手写批注）
///
/// 纯 Dart ChangeNotifier：画布与工具栏只是视图，全部编辑逻辑在此，可单测。
class AnnotationController extends ChangeNotifier {
  List<InkStroke> _strokes = const [];
  List<InkStroke> get strokes => _strokes;

  AnnoTool tool = AnnoTool.pen;
  int color = kAnnoColors.first;
  PenType penType = PenType.normal;

  /// 新绘制笔迹的坐标基准（v1.0.3 画布扩区）：
  /// 窄屏/题区画布 = 'question'；宽屏页面层画布 = 'page'。
  /// 擦除/选择也只作用于该 frame 的笔迹（存量旧笔迹在宽屏只读）。
  String activeFrame = kFrameQuestion;

  /// 选择工具当前选中笔迹下标（null = 未选中）
  int? selectedIndex;

  /// 正在绘制的笔迹（画布实时渲染，up 时并入 _strokes）
  final List<double> _livePts = [];
  double _livePressureSum = 0;
  int _livePressureCount = 0;
  InkStroke? get liveStroke => _livePts.isEmpty
      ? null
      : InkStroke(
          pts: List.of(_livePts),
          color: color,
          width: _liveWidth(),
          penType: penType,
          frame: activeFrame,
        );

  double _liveWidth() {
    final avg = _livePressureCount == 0
        ? 1.0
        : _livePressureSum / _livePressureCount;
    return kAnnoPenWidths[penType]! * avg.clamp(0.5, 1.5).toDouble();
  }

  // ======================== 模式与批量操作 ========================

  /// 载入持久批注（切题/进入持久批注模式时）
  void loadFrom(List<InkStroke> strokes) {
    _strokes = List.of(strokes);
    _livePts.clear();
    _livePressureSum = 0;
    _livePressureCount = 0;
    selectedIndex = null;
    notifyListeners();
  }

  /// 清空全部（内存态，不落库；落库由调用方决定）
  void clearAll() {
    _strokes = const [];
    selectedIndex = null;
    notifyListeners();
  }

  void setTool(AnnoTool t) {
    tool = t;
    if (t != AnnoTool.select) selectedIndex = null;
    notifyListeners();
  }

  void setColor(int c) {
    color = c;
    notifyListeners();
  }

  void setPenType(PenType p) {
    penType = p;
    notifyListeners();
  }

  // ======================== 绘制（画布回调） ========================

  /// 笔落下（归一化坐标 p、压感 pressure）
  void beginStroke(Offset p, double pressure) {
    if (tool != AnnoTool.pen) return;
    _livePts
      ..clear()
      ..addAll([p.dx, p.dy]);
    _livePressureSum = pressure;
    _livePressureCount = 1;
    notifyListeners();
  }

  /// 笔移动（归一化坐标）；点距过近抽稀（REQ-013 性能）
  void extendStroke(Offset p, double pressure) {
    if (_livePts.isEmpty) return;
    final dx = p.dx - _livePts[_livePts.length - 2];
    final dy = p.dy - _livePts[_livePts.length - 1];
    // 归一化距离 < 0.002（约 640 宽画布上 1.3px）丢弃
    if (dx * dx + dy * dy < 0.000004) return;
    _livePts.addAll([p.dx, p.dy]);
    _livePressureSum += pressure;
    _livePressureCount++;
    notifyListeners();
  }

  /// 笔抬起：并入笔迹列表（单点也保留，画成圆点）
  void endStroke() {
    if (_livePts.isEmpty) return;
    _strokes = [..._strokes, liveStroke!];
    _livePts.clear();
    _livePressureSum = 0;
    _livePressureCount = 0;
    notifyListeners();
  }

  /// 取消当前笔迹（如指针被系统取消、横向滑动意图切题）
  void cancelStroke() {
    if (_livePts.isEmpty) return;
    _livePts.clear();
    _livePressureSum = 0;
    _livePressureCount = 0;
    notifyListeners();
  }

  // ======================== 橡皮擦（REQ-009） ========================

  /// 橡皮擦经过画布像素点 p：命中即删除整条笔迹（Notability 式整笔擦除）。
  /// 只擦除当前 [activeFrame] 的笔迹（宽屏存量旧笔迹只读，不被误删）。
  bool eraseAt(Offset p, Size canvasSize) {
    if (tool != AnnoTool.eraser || _strokes.isEmpty) return false;
    const tol = 12.0;
    final before = _strokes.length;
    _strokes = _strokes
        .where((s) =>
            s.frame != activeFrame || !s.hitTest(p, tol, canvasSize))
        .toList();
    if (selectedIndex != null && selectedIndex! >= _strokes.length) {
      selectedIndex = null;
    }
    final changed = _strokes.length != before;
    if (changed) notifyListeners();
    return changed;
  }

  // ======================== 选择 / 移动（REQ-010/012） ========================

  /// 选择工具 tap：命中笔迹则选中，否则取消选中。返回是否命中。
  /// 只选择当前 [activeFrame] 的笔迹（存量旧笔迹宽屏只读）。
  bool selectAt(Offset p, Size canvasSize) {
    if (tool != AnnoTool.select) return false;
    const tol = 16.0;
    for (int i = _strokes.length - 1; i >= 0; i--) {
      final s = _strokes[i];
      if (s.frame == activeFrame && s.hitTest(p, tol, canvasSize)) {
        selectedIndex = i;
        notifyListeners();
        return true;
      }
    }
    if (selectedIndex != null) {
      selectedIndex = null;
      notifyListeners();
    }
    return false;
  }

  /// 选择工具拖动：平移选中笔迹（dx/dy 像素增量）
  void moveSelected(Offset delta, Size canvasSize) {
    if (tool != AnnoTool.select || selectedIndex == null) return;
    final i = selectedIndex!;
    final dx = canvasSize.width == 0 ? 0.0 : delta.dx / canvasSize.width;
    final dy = canvasSize.height == 0 ? 0.0 : delta.dy / canvasSize.height;
    _strokes = [..._strokes];
    _strokes[i] = _strokes[i].translate(dx, dy);
    notifyListeners();
  }

  /// 删除选中笔迹
  void deleteSelected() {
    if (selectedIndex == null) return;
    _strokes = [..._strokes]..removeAt(selectedIndex!);
    selectedIndex = null;
    notifyListeners();
  }

  /// 选中笔迹的包围盒（归一化），无选中返回 null
  Rect? get selectedBounds =>
      selectedIndex == null ? null : _strokes[selectedIndex!].bounds();
}

/// 批注固定四色（REQ-007）
const List<int> kAnnoColors = [
  0xFFE53935, // 红
  0xFF1E88E5, // 蓝
  0xFF43A047, // 绿
  0xFF212121, // 黑
];

/// 笔型基准宽度（逻辑像素，REQ-008）
const Map<PenType, double> kAnnoPenWidths = {
  PenType.fine: 1.5,
  PenType.normal: 3.0,
  PenType.highlighter: 10.0,
};

/// 荧光笔透明度（粗头半透明，划重点不遮挡内容）
const double kAnnoHighlighterAlpha = 0.35;
