import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

/// 端上离线 OCR：把「图片字」页面（扫描件）认成文字层。
///
/// 为什么在 App 里做：真实题库里扫描版 PDF 很常见，字是画在图里的（无文字层），
/// 让用户先转 DOCX 或换视觉模型都太绕——识别就该发生在导入的那一下。
/// Android 走 ML Kit 中文识别（离线、免 Key、免流量）；其他平台暂无同款
/// 能力，返回 null 由调用方走视觉切题/OCR 工具退路（见 parseForPreview）。
///
/// 设计取舍：OCR 只负责「图 → 字」，**切题仍走现有 AI 通道**——这样任何
/// 文本模型（含 deepseek-chat）都能吃扫描件，不必强求视觉模型。
class OcrService {
  OcrService._();

  /// 当前平台是否支持端上 OCR（Android；Web 不适用）
  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// 识别一张页图（JPEG/PNG 字节）里的文字；不支持的平台返回 null。
  /// 失败（模型缺失等）同样返回 null——OCR 是尽力而为，不该让导入硬失败。
  static Future<String?> recognizeImage(Uint8List jpegBytes) async {
    if (!isSupported) return null;
    TextRecognizer? recognizer;
    File? tmp;
    try {
      // ML Kit 的 fromFilePath 对 JPEG 最稳（fromBytes 需要裸像素+格式元信息）
      final dir = await getTemporaryDirectory();
      tmp = File(
          '${dir.path}/ocr_${DateTime.now().microsecondsSinceEpoch}.jpg')
        ..writeAsBytesSync(jpegBytes);
      recognizer = TextRecognizer(script: TextRecognitionScript.chinese);
      final input = InputImage.fromFilePath(tmp.path);
      final recognized = await recognizer.processImage(input);
      return recognized.text;
    } catch (_) {
      // 模型未就绪/识别异常：交给上层走退路，不把异常抛给用户
      return null;
    } finally {
      await recognizer?.close();
      try {
        tmp?.deleteSync();
      } catch (_) {}
    }
  }

  /// 多页识别文本 → 一份可直接喂 AI 切题的纯文本（页间空行分隔，
  /// 与 PDF 文字层抽取的 rawText 同构）。空页跳过。
  static String mergePageTexts(List<String> pages) {
    final buf = StringBuffer();
    for (final p in pages) {
      final t = p.trim();
      if (t.isEmpty) continue;
      buf
        ..writeln(t)
        ..writeln();
    }
    return buf.toString();
  }
}
