class AnswerRecord {
  final int? id;
  final int questionId;
  final int? sessionId;
  final String? userAnswer;
  final bool isCorrect;
  final String? aiAnalysis;
  final String answeredAt;
  /// 隐藏标记（v1.0.2 模型与表结构同步：隐藏今日记录，统计查询排除 hidden=1）
  final int hidden;
  /// 数据来源（v1.0.2 模型与表结构同步：real / simulation）
  final String source;

  AnswerRecord({
    this.id,
    required this.questionId,
    this.sessionId,
    this.userAnswer,
    required this.isCorrect,
    this.aiAnalysis,
    required this.answeredAt,
    this.hidden = 0,
    this.source = 'real',
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
      'hidden': hidden,
      'source': source,
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
      hidden: (map['hidden'] as int?) ?? 0,
      source: (map['source'] as String?) ?? 'real',
    );
  }

  /// 浅拷贝（改判后刷新内存记录用）
  AnswerRecord copyWith({bool? isCorrect}) {
    return AnswerRecord(
      id: id,
      questionId: questionId,
      sessionId: sessionId,
      userAnswer: userAnswer,
      isCorrect: isCorrect ?? this.isCorrect,
      aiAnalysis: aiAnalysis,
      answeredAt: answeredAt,
      hidden: hidden,
      source: source,
    );
  }
}
