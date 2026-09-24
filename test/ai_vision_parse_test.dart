// 扫描版 PDF「视觉切题」通道回归。
//
// 背景：扫描件/图片字 PDF 的字画在图片里（PDFium 每页对象=1 张整页图、抽字 0），
// 文字切题无从下手。视觉通道把页图交给支持看图的模型直接切题——这里钉住
// 请求形态（OpenAI 兼容 image_url）、解析装配、以及三类失败的可读性与重试行为。
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flashcard_app/models/app_settings.dart';
import 'package:flashcard_app/services/ai_service.dart';

void main() {
  AppSettings settings() => AppSettings.fromMap({
        'api_key': 'sk-test-key',
        'api_endpoint': 'https://api.deepseek.com/v1/chat/completions',
        'model': 'vision-model',
      });

  // charset=utf-8 不能省：package:http 对无 charset 的响应默认 latin1，
  // 中文响应体会直接炸在构造时（真实服务端都带 charset）
  http.Response chat(int status, {String? content, String? rawBody}) {
    final body = rawBody ??
        jsonEncode({
          'choices': [
            {
              'message': {'content': content}
            }
          ],
          'usage': {'total_tokens': 10},
        });
    return http.Response(body, status,
        headers: {'content-type': 'application/json; charset=utf-8'});
  }

  Uint8List fakeJpeg() => Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);

  test('视觉请求形态：OpenAI 兼容 image_url(base64 data) + 切题提示词', () async {
    String? reqBody;
    final client = MockClient((req) async {
      // MockClient 给的是 http.Request：直接读 body；
      // 在处理器里调 finalize() 会把请求体流吞掉（桩自身的坑）
      reqBody = req.body;
      return chat(200,
          content: '{"questions":[{"title":"血红蛋白的辅基是",'
              '"options":["血红素","叶酸"],"correct_answer":"A",'
              '"question_type":"single_choice"}]}');
    });
    final res = await AIService(settings(), client: client)
        .parseQuestionsFromPageImages([fakeJpeg()], 0, null);
    expect(res.questions, hasLength(1));
    expect(reqBody, contains('image_url'));
    expect(reqBody, contains('data:image/jpeg;base64,'));
    expect(reqBody, contains('切出来'), reason: '切题提示词在场');
    expect(reqBody, contains('答案速查表'), reason: '页脚答案速查表要回填');
    expect(reqBody, isNot(contains('出题')), reason: '定位红线：只提取不出题');
  });

  test('正常切题：题干/选项/答案装配正确', () async {
    final client = MockClient((req) async => chat(200,
        content: '{"questions":['
            '{"title":"凝血酶原时间延长见于","options":["肝病","缺铁"],'
            '"correct_answer":"a","question_type":"single_choice"},'
            '{"title":"何谓血沉？","options":[],"correct_answer":"红细胞沉降率",'
            '"question_type":"ming_jie"}]}'));
    final res = await AIService(settings(), client: client)
        .parseQuestionsFromPageImages([fakeJpeg()], 0, null);
    expect(res.questions, hasLength(2));
    expect(res.questions[0].correctAnswer, 'A', reason: '答案统一大写');
    expect(res.questions[1].questionType, 'ming_jie');
  });

  test('模型不支持看图：人话报错 + 终态 1 次即止', () async {
    var calls = 0;
    final client = MockClient((req) async {
      calls++;
      return chat(400,
          rawBody: '{"error":{"message":"image input is not supported by this model"}}');
    });
    final res = await AIService(settings(), client: client)
        .parseQuestionsFromPageImages([fakeJpeg()], 0, null);
    expect(res.errors.single, contains('不支持识别图片'));
    expect(res.errors.single, contains('OCR'), reason: '给出退路');
    expect(res.errors.single, isNot(contains('PERMANENT')));
    expect(calls, 1, reason: '终态错误不重试');
  });

  test('空响应：重试 3 次后报「空响应」', () async {
    var calls = 0;
    final client = MockClient((req) async {
      calls++;
      return chat(200, content: '');
    });
    final res = await AIService(settings(), client: client)
        .parseQuestionsFromPageImages([fakeJpeg()], 0, null);
    expect(res.errors.single, contains('AI 返回了空响应'));
    expect(res.errors.single, isNot(contains('FormatException')));
    expect(calls, 3);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('402 余额不足：人话 + 1 次即止', () async {
    var calls = 0;
    final client = MockClient((req) async {
      calls++;
      return chat(402,
          rawBody: '{"error":{"message":"Insufficient Balance","type":"unknown_error"}}');
    });
    final res = await AIService(settings(), client: client)
        .parseQuestionsFromPageImages([fakeJpeg()], 0, null);
    expect(res.errors.single, contains('账户余额不足'));
    expect(calls, 1);
  });

  test('多页错误聚合为「第 N 页」且成功页照常入题', () async {
    var n = 0;
    final client = MockClient((req) async {
      n++;
      if (n == 1) {
        return chat(200,
            content: '{"questions":[{"title":"第一题","options":[],'
                '"correct_answer":"对","question_type":"true_false"}]}');
      }
      return chat(200, content: '');
    });
    final res = await AIService(settings(), client: client)
        .parseQuestionsFromPageImages([fakeJpeg(), fakeJpeg()], 0, null);
    expect(res.questions, hasLength(1));
    expect(res.errors.single, contains('第 2 页'));
    expect(res.errors.single, contains('空响应'));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
