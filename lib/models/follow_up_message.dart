/// 追问消息（聊天气泡式，按题持久化）
class FollowUpMessage {
  final String role; // 'user' | 'assistant'
  final String content;

  const FollowUpMessage({required this.role, required this.content});

  factory FollowUpMessage.fromMap(Map<String, dynamic> m) => FollowUpMessage(
        role: m['role'] as String? ?? '',
        content: m['content'] as String? ?? '',
      );
}
