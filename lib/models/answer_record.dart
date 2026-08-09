class AnswerRecord {
  final int? id;
  final int questionId;
  final int? sessionId;
  final String? userAnswer;
  final bool isCorrect;
  final String? aiAnalysis;
  final String answeredAt;

  AnswerRecord({
    this.id,
    required this.questionId,
    this.sessionId,
    this.userAnswer,
    required this.isCorrect,
    this.aiAnalysis,
    required this.answeredAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'question_id': questionId,
      'session_id': sessionId,
      'user_answer': userAnswer,
      'is_correct': isCorrect ? 1 : 0,
      'ai_analysis': aiAnalysis,
      'answered_at': answeredAt,
    };
  }

  factory AnswerRecord.fromMap(Map<String, dynamic> map) {
    return AnswerRecord(
      id: map['id'] as int?,
      questionId: map['question_id'] as int,
      sessionId: map['session_id'] as int?,
      userAnswer: map['user_answer'] as String?,
      isCorrect: (map['is_correct'] as int) == 1,
      aiAnalysis: map['ai_analysis'] as String?,
      answeredAt: map['answered_at'] as String,
    );
  }
}
