class QuizSession {
  final int? id;
  final String bankIds; // 逗号分隔的题库ID列表
  final String mode; // single / mixed
  final int totalQuestions;
  final int correctCount;
  final int wrongCount;
  final String startTime;
  final String? endTime;
  final int durationSeconds;

  QuizSession({
    this.id,
    required this.bankIds,
    required this.mode,
    required this.totalQuestions,
    this.correctCount = 0,
    this.wrongCount = 0,
    required this.startTime,
    this.endTime,
    this.durationSeconds = 0,
  });

  double get accuracy =>
      totalQuestions > 0 ? (correctCount / totalQuestions) * 100 : 0;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'bank_ids': bankIds,
      'mode': mode,
      'total_questions': totalQuestions,
      'correct_count': correctCount,
      'wrong_count': wrongCount,
      'start_time': startTime,
      'end_time': endTime,
      'duration_seconds': durationSeconds,
    };
  }

  factory QuizSession.fromMap(Map<String, dynamic> map) {
    return QuizSession(
      id: map['id'] as int?,
      bankIds: map['bank_ids'] as String,
      mode: map['mode'] as String,
      totalQuestions: map['total_questions'] as int,
      correctCount: map['correct_count'] as int? ?? 0,
      wrongCount: map['wrong_count'] as int? ?? 0,
      startTime: map['start_time'] as String,
      endTime: map['end_time'] as String?,
      durationSeconds: map['duration_seconds'] as int? ?? 0,
    );
  }
}
