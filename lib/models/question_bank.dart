class QuestionBank {
  final int? id;
  final String name;
  final String? fileSource;
  final int questionCount;
  final String createdAt;

  QuestionBank({
    this.id,
    required this.name,
    this.fileSource,
    this.questionCount = 0,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'file_source': fileSource,
      'question_count': questionCount,
      'created_at': createdAt,
    };
  }

  factory QuestionBank.fromMap(Map<String, dynamic> map) {
    return QuestionBank(
      id: map['id'] as int?,
      name: map['name'] as String,
      fileSource: map['file_source'] as String?,
      questionCount: map['question_count'] as int? ?? 0,
      createdAt: map['created_at'] as String,
    );
  }

  QuestionBank copyWith({
    int? id,
    String? name,
    String? fileSource,
    int? questionCount,
    String? createdAt,
  }) {
    return QuestionBank(
      id: id ?? this.id,
      name: name ?? this.name,
      fileSource: fileSource ?? this.fileSource,
      questionCount: questionCount ?? this.questionCount,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
