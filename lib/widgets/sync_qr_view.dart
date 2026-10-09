import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

/// 同步配对二维码（纯 Dart 绘制，不依赖图片编码/平台插件）。
///
/// 用户要求「直接生成一个二维码，另一台设备只要通过猫卷扫码就可以连上」。
/// 这里用 qr 包算出模块矩阵，再用 CustomPainter 画成方块——省掉一次
/// 位图编码，也让二维码跟着主题色走。
class SyncQrView extends StatelessWidget {
  const SyncQrView({
    super.key,
    required this.data,
    this.size = 210,
  });

  /// 二维码内容（SyncPairPayload.encode() 的结果）
  final String data;
  final double size;

  @override
  Widget build(BuildContext context) {
    // 纠错级别 M：扫码容错与容量平衡；配对串很短，余量充足
    // qr 包的用法是 QrCode.fromData(...) 之后交给 QrImage 生成矩阵
    final qr = QrImage(QrCode.fromData(
      data: data,
      errorCorrectLevel: QrErrorCorrectLevel.M,
    ));
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        // 二维码必须白底深码，不能用主题底色，否则识别率骤降
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: CustomPaint(
        painter: _QrPainter(qr: qr, color: const Color(0xFF111111)),
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  _QrPainter({required this.qr, required this.color});

  final QrImage qr;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final modules = qr.moduleCount;
    final cell = size.width / modules;
    final paint = Paint()..color = color;
    for (var r = 0; r < modules; r++) {
      for (var c = 0; c < modules; c++) {
        if (!qr.isDark(r, c)) continue;
        // +0.5 消除相邻模块间的亚像素缝
        canvas.drawRect(
          Rect.fromLTWH(c * cell, r * cell, cell + 0.5, cell + 0.5),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QrPainter old) =>
      old.qr != qr || old.color != color;
}
