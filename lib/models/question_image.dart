import 'dart:typed_data';

/// 题目配图（schema v12）。
///
/// 图片是题目内容的一部分：题目文本流里用 `{{img:N}}` 占位符标记插入位置，
/// N = [position]（题内槽位，0 起，按阅读顺序 title → options → analysis）。
/// [questionId] 为空表示尚未落库的草稿（导入预览阶段）。
class QuestionImage {
  final int? id;
  final int? questionId;

  /// 题内槽位（与占位符 `{{img:N}}` 的 N 对应）
  final int position;

  final String mime;
  final int width;
  final int height;

  /// 原始归属线索（如 `2:312.5` = 第 2 页 y 中心），仅供排错/二次归属，渲染不用
  final String? anchor;

  /// 压缩后的图片字节（JPEG，长边 ≤1280、单张 ≤512KB）
  final Uint8List content;

  const QuestionImage({
    this.id,
    this.questionId,
    required this.position,
    this.mime = 'image/jpeg',
    required this.width,
    required this.height,
    this.anchor,
    required this.content,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      if (questionId != null) 'question_id': questionId,
      'position': position,
      'mime': mime,
      'width': width,
      'height': height,
      'anchor': anchor,
      'content': content,
    };
  }

  factory QuestionImage.fromMap(Map<String, dynamic> map) {
    final raw = map['content'];
    return QuestionImage(
      id: map['id'] as int?,
      questionId: map['question_id'] as int?,
      position: map['position'] as int? ?? 0,
      mime: map['mime'] as String? ?? 'image/jpeg',
      width: map['width'] as int? ?? 0,
      height: map['height'] as int? ?? 0,
      anchor: map['anchor'] as String?,
      content: raw is Uint8List
          ? raw
          : raw is List
              ? Uint8List.fromList(raw.cast<int>())
              : Uint8List(0),
    );
  }

  /// 落库前的草稿复制：清 id/questionId、换槽位（其余元信息随行）
  QuestionImage asDraftAt(int position) {
    return QuestionImage(
      position: position,
      mime: mime,
      width: width,
      height: height,
      anchor: anchor,
      content: content,
    );
  }

  QuestionImage copyWith({
    int? id,
    int? questionId,
    int? position,
    String? mime,
    int? width,
    int? height,
    String? anchor,
    Uint8List? content,
  }) {
    return QuestionImage(
      id: id ?? this.id,
      questionId: questionId ?? this.questionId,
      position: position ?? this.position,
      mime: mime ?? this.mime,
      width: width ?? this.width,
      height: height ?? this.height,
      anchor: anchor ?? this.anchor,
      content: content ?? this.content,
    );
  }
}
