import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flashcard_app/models/app_settings.dart';
import 'package:flashcard_app/models/question.dart';
import 'package:flashcard_app/services/ai_service.dart';

/// AI 流式输出（SSE）的回归测试。
///
/// 改造要点与测试对应关系：
///   · SSE 边角情况极多（心跳、`[DONE]`、`\r\n`、无空格的 `data:`、delta 非字符串），
///     且「任意 OpenAI 兼容接口」里有一部分**不老实**——所以要分别覆盖；
///   · 流式失败必须**回退一次性请求**，最终结果与改造前一致（用户无感），
///     这条是「不因新功能而功能退化」的保证，单独测；
///   · 命中缓存（已保存的解析）**不走流式**——这是产品约束。
void main() {
  /// 构造一个「按请求体分流」的假客户端：
  /// `stream:true` 的请求走 [onStream]，其余（回退的一次性请求）走 [onOnce]。
  MockClient splitClient({
    required Future<http.StreamedResponse> Function(http.BaseRequest req) onStream,
    required Future<http.Response> Function(http.BaseRequest req) onOnce,
  }) {
    return MockClient.streaming((request, bodyStream) async {
      final body = await bodyStream.bytesToString();
      if (body.contains('"stream":true')) return onStream(request);
      return http.StreamedResponse(
        Stream.value(utf8.encode((await onOnce(request)).body)),
        (await onOnce(request)).statusCode,
      );
    });
  }

  /// SSE 响应体：把若干段内容包成 OpenAI 风格的流
  http.StreamedResponse sseResponse(List<String> pieces, {int status = 200}) {
    final lines = <String>[
      'data: {"choices":[{"delta":{"role":"assistant"}}]}',
      ': keep-alive',
      for (final p in pieces)
        'data: ${jsonEncode({'choices': [{'delta': {'content': p}}]})}',
      '',
      'data: [DONE]',
      '',
    ];
    return http.StreamedResponse(
      Stream.value(utf8.encode(lines.join('\n'))),
      status,
      headers: {'content-type': 'text/event-stream'},
    );
  }

  AIService service(MockClient client) => AIService(
        AppSettings(apiKey: 'sk-test', model: 'test-model'),
        client: client,
      );

  /// 假响应。必须走 bytes + utf8 —— `http.Response(String, ...)` 在无 charset
  /// 头时按 latin1 编码，中文会抛 "Contains invalid characters"。
  http.Response jsonResponse(Object body) => http.Response.bytes(
        utf8.encode(jsonEncode(body)),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  /// 无 id 的题目 → 跳过缓存查询（本文件不需要起数据库）
  Question question() => Question(
        bankId: 1,
        title: '测试题',
        options: const ['A', 'B'],
        correctAnswer: 'A',
        createdAt: '2026-09-15T00:00:00.000',
      );

  group('SSE 行解析', () {
    test('取出 delta 内容', () {
      expect(
        AIService.deltaFromSseLine(
            'data: {"choices":[{"delta":{"content":"你"}}]}'),
        '你',
      );
    });

    test('data: 后无空格也能解析（部分网关如此）', () {
      expect(
        AIService.deltaFromSseLine(
            'data:{"choices":[{"delta":{"content":"x"}}]}'),
        'x',
      );
    });

    test('非 data 行（事件行 / 注释 / 心跳 / 空行）一律忽略', () {
      expect(AIService.deltaFromSseLine('event: message'), isNull);
      expect(AIService.deltaFromSseLine(': keep-alive'), isNull);
      expect(AIService.deltaFromSseLine(''), isNull);
      expect(AIService.deltaFromSseLine('data: '), isNull);
    });

    test('[DONE] 既不产出内容，也被识别为结束', () {
      expect(AIService.deltaFromSseLine('data: [DONE]'), isNull);
      expect(AIService.isSseDoneLine('data: [DONE]'), isTrue);
      expect(AIService.isSseDoneLine('data: {"choices":[]}'), isFalse);
    });

    test('空 delta / 非字符串 content / 坏 JSON / 缺 choices 都返回 null', () {
      expect(
          AIService.deltaFromSseLine(
              'data: {"choices":[{"delta":{"content":""}}]}'),
          isNull);
      // 某些实现把 content 给成数组 —— 类型保护必须挡住，不能抛
      expect(
          AIService.deltaFromSseLine(
              'data: {"choices":[{"delta":{"content":["a"]}}]}'),
          isNull);
      expect(AIService.deltaFromSseLine('data: {坏掉的 json'), isNull);
      expect(AIService.deltaFromSseLine('data: {"choices":[]}'), isNull);
    });
  });

  group('流式追问', () {
    test('标准 SSE：逐段产出**累计文本**，到 [DONE] 结束', () async {
      final service0 = service(splitClient(
        onStream: (_) async => sseResponse(['你好', '，这是', '回答。']),
        onOnce: (_) async => jsonResponse(
            {'choices': [{'message': {'content': '不应走到这里'}}]}),
      ));

      final chunks = await service0
          .streamFollowUp(question(), '原解析', '追问')
          .toList();

      expect(chunks, ['你好', '你好，这是', '你好，这是回答。']);
    });

    test('服务商忽略 stream:true（返回普通 JSON）→ 整段给出，不报错', () async {
      final service0 = service(splitClient(
        onStream: (_) async => http.StreamedResponse(
          Stream.value(utf8.encode(
              '{"choices":[{"message":{"content":"一次性正文"}}]}')),
          200,
          headers: {'content-type': 'application/json'},
        ),
        onOnce: (_) async => jsonResponse({}),
      ));

      final chunks =
          await service0.streamFollowUp(question(), '原解析', '追问').toList();

      expect(chunks, ['一次性正文']);
    });

    test('流式请求返回非 200 → 回退一次性请求，用户仍拿到完整回答', () async {
      var fallbackCalled = false;
      final service0 = service(splitClient(
        onStream: (_) async => http.StreamedResponse(
          Stream.value(utf8.encode('gateway error')),
          502,
        ),
        onOnce: (_) async {
          fallbackCalled = true;
          return jsonResponse({
              'choices': [
                {'message': {'content': '回退拿到的回答'}}
              ]
            });
        },
      ));

      final chunks =
          await service0.streamFollowUp(question(), '原解析', '追问').toList();

      expect(fallbackCalled, isTrue, reason: '流式失败必须回退一次性请求');
      expect(chunks, ['回退拿到的回答']);
    });

    test('流开了但零内容（如只给 reasoning_content）→ 回退一次性', () async {
      var fallbackCalled = false;
      final service0 = service(splitClient(
        onStream: (_) async => sseResponse([]), // 没有任何 content
        onOnce: (_) async {
          fallbackCalled = true;
          return jsonResponse({
              'choices': [
                {'message': {'content': '回退内容'}}
              ]
            });
        },
      ));

      final chunks =
          await service0.streamFollowUp(question(), '原解析', '追问').toList();

      expect(fallbackCalled, isTrue);
      expect(chunks, ['回退内容']);
    });

    test('流中途断连 → 回退一次性（已收到的部分不当作最终结果）', () async {
      final service0 = service(splitClient(
        // 先给一个 chunk，再让流报错（模拟连接被重置）。
        // 注意不能用 Stream.followedBy —— Dart 的 Stream 没有这个方法，
        // 用 async* 生成器既能 yield 又能 throw。
        onStream: (_) async => http.StreamedResponse(
          () async* {
            yield utf8.encode('data: {"choices":[{"delta":{"content":"半"}}]}\n');
            throw Exception('连接被重置');
          }(),
          200,
          headers: {'content-type': 'text/event-stream'},
        ),
        onOnce: (_) async => jsonResponse({
            'choices': [
              {'message': {'content': '完整回答'}}
            ]
          }),
      ));

      final chunks =
          await service0.streamFollowUp(question(), '原解析', '追问').toList();

      expect(chunks.last, '完整回答', reason: '断连后应回退到完整的一次性结果');
    });
  });

  group('流式讲解', () {
    test('无缓存时走流式并产出累计文本', () async {
      final service0 = service(splitClient(
        onStream: (_) async => sseResponse(['**答案：** A', '\n**题眼：** 测试']),
        onOnce: (_) async => jsonResponse({}),
      ));

      // id 为 null → 跳过缓存，直接流式
      final chunks = await service0.streamAnalysis(question()).toList();

      expect(chunks.length, 2);
      expect(chunks.last, contains('**答案：** A'));
      expect(chunks.last, contains('**题眼：** 测试'));
    });
  });

  group('SSE 边角：字节分片 / CRLF / 结束语义 / token 统计', () {
    /// 把整段 SSE 按**字节**切成小块（模拟 TCP 分片：一个汉字的三字节、
    /// 一行 data: 都可能被切在两块之间）
    http.StreamedResponse chunkedResponse(List<int> bytes, {int size = 5}) =>
        http.StreamedResponse(
          Stream.fromIterable([
            for (var i = 0; i < bytes.length; i += size)
              bytes.sublist(i, i + size > bytes.length ? bytes.length : i + size),
          ]),
          200,
          headers: {'content-type': 'text/event-stream'},
        );

    test('字节分片切开汉字 + CRLF 行尾，仍拼出完整文本', () async {
      final body = utf8.encode([
        'data: {"choices":[{"delta":{"content":"你好"}}]}',
        '',
        'data: {"choices":[{"delta":{"content":"，世界"}}]}',
        '',
        'data: [DONE]',
        '',
      ].join('\r\n'));
      final service0 = service(splitClient(
        onStream: (_) async => chunkedResponse(body, size: 5),
        onOnce: (_) async => jsonResponse({}),
      ));

      final chunks =
          await service0.streamFollowUp(question(), '原解析', '追问').toList();

      // 逐块 utf8.decode 解不出多字节字符，必然出现乱码或丢字
      expect(chunks.last, '你好，世界');
      expect(chunks.last, isNot(contains('\uFFFD')));
    });

    test('[DONE] 之后网关不关连接还继续发内容 → 立刻结束，后续内容不算进来', () async {
      final controller = StreamController<List<int>>();
      controller.add(utf8.encode('data: {"choices":[{"delta":{"content":"正文"}}]}\n\n'
          'data: [DONE]\n\n'));
      // 结束标记之后继续吐内容，并且**不关闭**连接（真实网关常见）
      controller.add(utf8.encode(
          'data: {"choices":[{"delta":{"content":"不该出现"}}]}\n\n'));
      final service0 = service(splitClient(
        onStream: (_) async => http.StreamedResponse(
          controller.stream,
          200,
          headers: {'content-type': 'text/event-stream'},
        ),
        onOnce: (_) async => jsonResponse({}),
      ));

      final chunks = await service0
          .streamFollowUp(question(), '原解析', '追问')
          .toList()
          .timeout(const Duration(seconds: 5),
              onTimeout: () => fail('收到 [DONE] 后没有结束，一直挂到空闲超时了'));

      expect(chunks.last, '正文');
      expect(chunks.last, isNot(contains('不该出现')));
      await controller.close();
    });

    test('只有 usage 没有 content → 仍回退一次性，但 token 要记上', () async {
      var fallbackCalled = false;
      final service0 = service(splitClient(
        onStream: (_) async => http.StreamedResponse(
          Stream.value(utf8.encode([
            'data: ${jsonEncode({'usage': {'total_tokens': 7}})}',
            '',
            'data: [DONE]',
            '',
          ].join('\n'))),
          200,
          headers: {'content-type': 'text/event-stream'},
        ),
        onOnce: (_) async {
          fallbackCalled = true;
          return jsonResponse({
            'choices': [
              {'message': {'content': '回退内容'}}
            ]
          });
        },
      ));

      final chunks =
          await service0.streamFollowUp(question(), '原解析', '追问').toList();

      expect(fallbackCalled, isTrue, reason: '一个内容字都没有 → 必须回退');
      expect(chunks.last, '回退内容');
      expect(service0.totalTokensUsed, 7,
          reason: 'usage 行不该产出内容，但 token 统计要记上');
    });

    test('content 与 usage 同一行 → 文本和统计都要更新', () async {
      final service0 = service(splitClient(
        onStream: (_) async => http.StreamedResponse(
          Stream.value(utf8.encode([
            'data: ${jsonEncode({
                  'choices': [
                    {'delta': {'content': '一次给全'}}
                  ],
                  'usage': {'total_tokens': 12},
                })}',
            '',
            'data: [DONE]',
            '',
          ].join('\n'))),
          200,
          headers: {'content-type': 'text/event-stream'},
        ),
        onOnce: (_) async => jsonResponse({}),
      ));

      final chunks =
          await service0.streamFollowUp(question(), '原解析', '追问').toList();

      expect(chunks.last, '一次给全');
      expect(service0.totalTokensUsed, 12);
    });
  });
}
