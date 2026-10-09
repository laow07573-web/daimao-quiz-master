import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/sync/sync_pair_payload.dart';
import '../services/theme_service.dart';
import '../utils/design_tokens.dart';

/// 扫码配对页：扫对方猫卷的配对二维码即可连上。
///
/// 用户要求：「另一台设备只要通过猫卷扫码就可以连上」。
/// 返回 [SyncPairPayload]（取消则返回 null）。
class SyncScanScreen extends StatefulWidget {
  const SyncScanScreen({super.key});

  @override
  State<SyncScanScreen> createState() => _SyncScanScreenState();
}

class _SyncScanScreenState extends State<SyncScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    // 只认二维码，避免把条形码也当配对码
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  /// 命中一次就停：连续回调会让 Navigator.pop 触发多次
  bool _handled = false;
  String? _hint;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;
      final payload = SyncPairPayload.decode(raw);
      if (payload == null) {
        // 扫到别的二维码：给出可理解的提示，而不是静默无反应
        if (mounted) {
          setState(() => _hint = '这不是猫卷的配对二维码');
        }
        return;
      }
      _handled = true;
      Navigator.pop(context, payload);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ac = AppThemeColors.of(context);
    return Scaffold(
      backgroundColor: ac.background,
      appBar: AppBar(title: const Text('扫码配对')),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error, child) => Center(
              child: Padding(
                padding: const EdgeInsets.all(MaoSpace.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.no_photography_outlined,
                        size: 40, color: ac.textTertiary),
                    const SizedBox(height: MaoSpace.sm),
                    Text('无法使用相机：$error',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: MaoType.body, color: ac.textSecondary)),
                    const SizedBox(height: MaoSpace.xs),
                    Text('可以在设置页手动输入对方的识别码',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: MaoType.caption, color: ac.textTertiary)),
                  ],
                ),
              ),
            ),
          ),
          // 取景框
          Center(
            child: Container(
              width: 230,
              height: 230,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white70, width: 2),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              color: Colors.black54,
              padding: const EdgeInsets.all(MaoSpace.md),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('对准对方「数据库/识别码」里的配对二维码',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 13)),
                  if (_hint != null) ...[
                    const SizedBox(height: 6),
                    Text(_hint!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.orangeAccent, fontSize: 13)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
