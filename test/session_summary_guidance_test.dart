// 小结引导回归：没配 API Key 时不能再报「小结生成失败，请检查网络或 API
// 配置后重试」——实机冒烟里 BYOK 未配置时就是这个提示，用户会先去排查网络。
// 未配置应当直接指向「设置 → API Key」，与解析/追问入口同一口径。
import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/models/quiz_session.dart';
import 'package:flashcard_app/services/app_state.dart';

void main() {
  test('未配置 API Key：小结直接给配置指引，而不是「生成失败」', () async {
    final appState = AppState();
    expect(appState.settings.isConfigured, isFalse, reason: '前提：默认无 Key');

    final text = await appState.generateSessionSummary(QuizSession(
      bankIds: '1',
      mode: 'single',
      totalQuestions: 10,
      startTime: '2026-01-01T00:00:00',
    ));

    expect(text, contains('配置 API Key'));
    expect(text, isNot(contains('小结生成失败')));
    expect(text, isNot(contains('检查网络')));
  });
}
