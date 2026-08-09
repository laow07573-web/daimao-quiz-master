import 'dart:convert';

class Question {
  final int? id;
  final int bankId;
  final String title;
  final List<String> options; // ["热带假丝酵母菌", "新型隐球菌", ...] — 无前缀
  final String correctAnswer; // "A" / "B" / "A,C" / "对" / "错"
  final String? analysis;
  final String questionType; // single_choice, multi_choice, true_false
  final String? source;
  final String createdAt;

  Question({
    this.id,
    required this.bankId,
    required this.title,
    this.options = const [],
    required this.correctAnswer,
    this.analysis,
    this.questionType = 'single_choice',
    this.source,
    required this.createdAt,
  });

  /// 带前缀的选项文本列表：["A. 热带假丝酵母菌", "B. 新型隐球菌", ...]
  List<String> get optionsWithLabels {
    return options.asMap().entries.map((e) {
      final label = _indexToLabel(e.key);
      return '$label. ${e.value}';
    }).toList();
  }

  /// 根据索引获取标签（0→A, 1→B, ... 25→Z）
  static String _indexToLabel(int index) {
    return String.fromCharCode(65 + index);
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'bank_id': bankId,
      'title': title,
      'options': jsonEncode(options),
      'correct_answer': correctAnswer,
      'analysis': analysis,
      'question_type': questionType,
      'source': source,
      'created_at': createdAt,
    };
  }

  factory Question.fromMap(Map<String, dynamic> map) {
    List<String> opts;
    try {
      final raw = map['options'];
      if (raw is String && raw.isNotEmpty) {
        opts = (jsonDecode(raw) as List).map((e) => e.toString()).toList();
      } else if (raw is List) {
        opts = raw.map((e) => e.toString()).toList();
      } else {
        // 兼容旧数据：从 option_a/b/c/d 列读取
        opts = [
          if (map['option_a'] != null && map['option_a'].toString().isNotEmpty)
            map['option_a'].toString(),
          if (map['option_b'] != null && map['option_b'].toString().isNotEmpty)
            map['option_b'].toString(),
          if (map['option_c'] != null && map['option_c'].toString().isNotEmpty)
            map['option_c'].toString(),
          if (map['option_d'] != null && map['option_d'].toString().isNotEmpty)
            map['option_d'].toString(),
        ];
      }
    } catch (_) {
      opts = [];
    }

    return Question(
      id: map['id'] as int?,
      bankId: map['bank_id'] as int,
      title: map['title'] as String,
      options: opts,
      correctAnswer: map['correct_answer'] as String? ?? '',
      analysis: map['analysis'] as String?,
      questionType: map['question_type'] as String? ?? 'single_choice',
      source: map['source'] as String?,
      createdAt: map['created_at'] as String? ?? DateTime.now().toIso8601String(),
    );
  }

  Question copyWith({
    int? id,
    int? bankId,
    String? title,
    List<String>? options,
    String? correctAnswer,
    String? analysis,
    String? questionType,
    String? source,
    String? createdAt,
  }) {
    return Question(
      id: id ?? this.id,
      bankId: bankId ?? this.bankId,
      title: title ?? this.title,
      options: options ?? this.options,
      correctAnswer: correctAnswer ?? this.correctAnswer,
      analysis: analysis ?? this.analysis,
      questionType: questionType ?? this.questionType,
      source: source ?? this.source,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
