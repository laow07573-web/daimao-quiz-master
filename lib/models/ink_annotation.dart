import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

/// 笔型（REQ-008）：细笔划线 / 普通笔书写 / 荧光笔粗头划重点
enum PenType { fine, normal, highlighter }

/// 笔迹坐标系基准（v1.0.3 画布扩区）：
/// 'question' = 题区画布（存量数据与窄屏），'page' = 页面内容区画布（宽屏扩区）。
const String kFrameQuestion = 'question';
const String kFramePage = 'page';

/// 手写批注笔迹（v1.0.3 手写批注）
///
/// 坐标归一化到 0~1 存储（按批注画布宽高），跨手机/平板/桌面尺寸复用；
/// [pts] 为 x,y 交替的扁平数组。
class InkStroke {
  final List<double> pts;
  final int color;
  final double width; // 逻辑像素基准宽度（已含压感均值，重放时直接使用）
  final PenType penType;
  final String frame; // 坐标基准：'question'（存量/窄屏）/ 'page'（宽屏扩区）

  const InkStroke({
    required this.pts,
    required this.color,
    required this.width,
    this.penType = PenType.normal,
    this.frame = kFrameQuestion,
  });

  int get pointCount => pts.length ~/ 2;

  /// 第 i 个点的归一化坐标
  Offset pointAt(int i) => Offset(pts[i * 2], pts[i * 2 + 1]);

  bool get isEmpty => pts.length < 2; // 无点不算笔迹（单点 = 点一下，有效）

  /// 命中检测：点 p（画布像素坐标）到任一笔迹线段距离 < tol 即命中
  /// （在像素空间计算，避免归一化后 x/y 尺度不一致）
  bool hitTest(Offset p, double tol, Size canvasSize) {
    if (isEmpty) return false;
    double pxTo(double v) => v * canvasSize.width;
    double pyTo(double v) => v * canvasSize.height;
    final px = p.dx, py = p.dy;
    // 单点笔迹（点一下）：到该点距离
    if (pointCount == 1) {
      final ex = px - pxTo(pts[0]), ey = py - pyTo(pts[1]);
      return math.sqrt(ex * ex + ey * ey) < tol;
    }
    var ax = pxTo(pts[0]), ay = pyTo(pts[1]);
    for (int i = 1; i < pointCount; i++) {
      final bx = pxTo(pts[i * 2]), by = pyTo(pts[i * 2 + 1]);
      if (_distToSegment(px, py, ax, ay, bx, by) < tol) return true;
      ax = bx;
      ay = by;
    }
    return false;
  }

  static double _distToSegment(
      double px, double py, double ax, double ay, double bx, double by) {
    final dx = bx - ax, dy = by - ay;
    final lenSq = dx * dx + dy * dy;
    if (lenSq == 0) {
      final ex = px - ax, ey = py - ay;
      return math.sqrt(ex * ex + ey * ey);
    }
    var t = ((px - ax) * dx + (py - ay) * dy) / lenSq;
    t = t.clamp(0.0, 1.0).toDouble();
    final ex = px - (ax + t * dx), ey = py - (ay + t * dy);
    return math.sqrt(ex * ex + ey * ey);
  }

  /// 整条平移（dx/dy 为归一化增量）
  InkStroke translate(double dx, double dy) {
    final moved = List<double>.of(pts);
    for (int i = 0; i < moved.length; i += 2) {
      moved[i] = (moved[i] + dx).clamp(0.0, 1.0).toDouble();
      moved[i + 1] = (moved[i + 1] + dy).clamp(0.0, 1.0).toDouble();
    }
    return InkStroke(
        pts: moved, color: color, width: width, penType: penType, frame: frame);
  }

  /// 仅替换坐标基准（其他属性不变）
  InkStroke withFrame(String f) =>
      InkStroke(pts: pts, color: color, width: width, penType: penType, frame: f);

  /// 笔迹包围盒（归一化）
  Rect bounds() {
    if (isEmpty) return Rect.zero;
    double minX = 1, minY = 1, maxX = 0, maxY = 0;
    for (int i = 0; i < pointCount; i++) {
      final x = pts[i * 2], y = pts[i * 2 + 1];
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  Map<String, dynamic> toJson() => {
        'pts': pts,
        'c': color,
        'w': width,
        'p': penType.index,
        // 'question' 为存量缺省，省略以减小存储；'page' 显式写入
        if (frame != kFrameQuestion) 'f': frame,
      };

  factory InkStroke.fromJson(Map<String, dynamic> json) {
    final raw = json['pts'];
    List<double> pts = const [];
    if (raw is List) {
      pts = raw.map((e) => (e as num).toDouble()).toList();
    }
    return InkStroke(
      pts: pts,
      color: (json['c'] as num?)?.toInt() ?? 0xFF212121,
      width: (json['w'] as num?)?.toDouble() ?? 3.0,
      penType: PenType.values[(json['p'] as num?)?.toInt() ?? 1],
      frame: (json['f'] as String?) ?? kFrameQuestion, // 存量数据缺省 'question'
    );
  }

  /// 整组批注序列化（DB data 列格式：{"v":1,"strokes":[...]}）
  static String encodeList(List<InkStroke> strokes) => jsonEncode({
        'v': 1,
        'strokes': strokes.map((s) => s.toJson()).toList(),
      });

  static List<InkStroke> decodeList(String? data) {
    if (data == null || data.isEmpty) return const [];
    try {
      final map = jsonDecode(data) as Map<String, dynamic>;
      final list = map['strokes'];
      if (list is! List) return const [];
      return list
          .map((e) => InkStroke.fromJson(e as Map<String, dynamic>))
          .where((s) => !s.isEmpty)
          .toList();
    } catch (_) {
      return const []; // 损坏数据按无批注处理，不阻塞刷题
    }
  }
}
