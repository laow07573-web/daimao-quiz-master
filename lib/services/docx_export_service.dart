import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../models/question.dart';

/// 答案在打印稿里的位置。
///
/// 两种排布的内容完全一样（题干、选项、答案、解析都不变），只有答案块
/// 落在哪儿不同——所以两种模式印出来的长度也基本一致。
enum DocxAnswerPlacement {
  /// 答案紧跟在该题选项下方（适合边看边背）
  underQuestion,

  /// 所有答案集中到最后一页（适合先做题、翻到最后对答案）
  lastPage,
}

/// 生成「纸质题目」用的 .docx（Word 文档）。
///
/// 为什么不用现成包：项目里已经有 `archive` + `xml` 两个直接依赖，
/// 而 .docx 本质就是一个装着 WordprocessingML 的 zip——
/// `[Content_Types].xml` + `_rels/.rels` + `word/document.xml` 三个文件
/// 就是一份 Word / WPS / Google Docs 都能打开的最小文档，不需要新增依赖。
///
/// 两个容易踩的坑：
///   · 文本一律走 XmlElement/XmlText 构造而不是字符串拼接：题干里出现
///     `&`、`<`、`"` 时手拼的 XML 会直接坏掉，Word 报「文件已损坏」；
///   · `w:pPr` 必须是 `w:p` 的**第一个**子元素，顺序错了 Word 同样报损坏。
class DocxExportService {
  DocxExportService._();

  /// 正文字号（半磅）：21 = 五号 10.5pt
  static const _bodySize = '21';

  /// 标题 14pt
  static const _titleSize = '28';

  /// 说明/解析 9pt
  static const _metaSize = '18';

  /// 生成文档，返回完整字节（调用方负责落盘）。
  ///
  /// - [subtitle]：印在卷头的范围说明（如「最薄弱知识点：血液」）
  /// - [now]：注入时间便于测试
  static List<int> build({
    required List<Question> questions,
    required DocxAnswerPlacement placement,
    String? subtitle,
    DateTime? now,
  }) {
    final stamp = now ?? DateTime.now();
    final body = <XmlElement>[];

    // —— 卷头 ——
    body.add(_para('猫卷 · 错题练习',
        bold: true, size: _titleSize, align: 'center', spaceAfter: 60));
    final meta = StringBuffer('共 ${questions.length} 题 · '
        '${stamp.year}-${_two(stamp.month)}-${_two(stamp.day)}');
    if (placement == DocxAnswerPlacement.lastPage) {
      meta.write(' · 答案见最后一页');
    }
    body.add(_para(meta.toString(),
        size: _metaSize, color: '666666', align: 'center', spaceAfter: 160));
    final sub = subtitle?.trim();
    if (sub != null && sub.isNotEmpty) {
      body.add(_para(sub,
          size: _metaSize, color: '666666', align: 'center', spaceAfter: 200));
    }

    // —— 题目 ——
    for (var i = 0; i < questions.length; i++) {
      final q = questions[i];
      // 只有非单选才标题型：「多选」「判断」不写出来，学生可能只选一个
      final label = q.typeLabel == '单选' ? '' : '【${q.typeLabel}】';
      body.add(_para('${i + 1}. $label${q.title}', spaceAfter: 40));

      for (final opt in q.optionsWithLabels) {
        body.add(_para(opt, indentLeft: 420, spaceAfter: 20));
      }

      if (placement == DocxAnswerPlacement.underQuestion) {
        body.addAll(_answerBlock(q, number: i + 1, showNumber: false));
        body.add(_para('', spaceAfter: 60));
      } else {
        // 末页模式：这里留答题空间，与答案块占位相当，两种模式页数一致
        for (var k = 0; k < 3; k++) {
          body.add(_para('', spaceAfter: 40));
        }
      }
    }

    // —— 末页答案 ——
    if (placement == DocxAnswerPlacement.lastPage && questions.isNotEmpty) {
      body.add(_pageBreak());
      body.add(_para('答案',
          bold: true, size: _titleSize, align: 'center', spaceAfter: 160));
      for (var i = 0; i < questions.length; i++) {
        body.addAll(_answerBlock(questions[i], number: i + 1, showNumber: true));
      }
    }

    final document = XmlBuilder()
      ..processing('xml',
          'version="1.0" encoding="UTF-8" standalone="yes"');
    document.element('w:document', attributes: {
      'xmlns:w':
          'http://schemas.openxmlformats.org/wordprocessingml/2006/main',
    }, nest: () {
      document.element('w:body', nest: () {
        for (final el in body) {
          document.xml(el.toXmlString());
        }
        // 页面设置：A4 + 2cm 页边距（必须放在 body 末尾）
        document.element('w:sectPr', nest: () {
          document.element('w:pgSz',
              attributes: {'w:w': '11906', 'w:h': '16838'});
          document.element('w:pgMar', attributes: {
            'w:top': '1134',
            'w:right': '1134',
            'w:bottom': '1134',
            'w:left': '1134',
          });
        });
      });
    });

    return _zip(document.buildDocument().toXmlString());
  }

  /// 一道题的答案块：`答案：A` + 解析（有才印）
  static List<XmlElement> _answerBlock(
    Question q, {
    required int number,
    required bool showNumber,
  }) {
    final prefix = showNumber ? '$number. ' : '';
    final out = <XmlElement>[
      _para('$prefix答案：${q.correctAnswer}',
          bold: true, size: _bodySize, spaceAfter: 20),
    ];
    final analysis = q.analysis?.trim();
    if (analysis != null && analysis.isNotEmpty) {
      out.add(_para('解析：', size: _metaSize, color: '444444', spaceAfter: 0));
      for (final line in analysis.split('\n')) {
        out.add(_para(line,
            size: _metaSize, color: '444444', indentLeft: 420, spaceAfter: 0));
      }
    }
    return out;
  }

  /// 分页符
  static XmlElement _pageBreak() => XmlElement(XmlName('w:p'), [], [
        _paraProps(spaceAfter: 0),
        XmlElement(XmlName('w:r'), [], [
          XmlElement(XmlName('w:br'),
              [XmlAttribute(XmlName('w:type'), 'page')]),
        ]),
      ]);

  /// 组装最小可用的 docx 包
  static List<int> _zip(String documentXml) {
    const contentTypes = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
        '</Types>';
    const rels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
        '</Relationships>';

    final archive = Archive();
    void add(String name, String content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    // [Content_Types].xml 先写：它在 OPC 里必须在包根，放第一个兼容性最好
    add('[Content_Types].xml', contentTypes);
    add('_rels/.rels', rels);
    add('word/document.xml', documentXml);
    return ZipEncoder().encode(archive)!;
  }

  /// 一个段落。[text] 为空时产出真正的空行（答题空间）。
  static XmlElement _para(
    String text, {
    bool bold = false,
    String size = _bodySize,
    String? color,
    String? align,
    int indentLeft = 0,
    int spaceAfter = 0,
  }) {
    final children = <XmlElement>[
      _paraProps(align: align, indentLeft: indentLeft, spaceAfter: spaceAfter),
    ];
    if (text.isNotEmpty) {
      children.add(XmlElement(XmlName('w:r'), [], [
        XmlElement(XmlName('w:rPr'), [], [
          if (bold) XmlElement(XmlName('w:b')),
          XmlElement(XmlName('w:sz'), [XmlAttribute(XmlName('w:val'), size)]),
          if (color != null)
            XmlElement(XmlName('w:color'),
                [XmlAttribute(XmlName('w:val'), color)]),
        ]),
        XmlElement(
            XmlName('w:t'),
            [XmlAttribute(XmlName('xml:space'), 'preserve')],
            [XmlText(text)]),
      ]));
    }
    return XmlElement(XmlName('w:p'), [], children);
  }

  /// 段落属性（必须是 w:p 的第一个子元素）
  static XmlElement _paraProps({
    String? align,
    int indentLeft = 0,
    int spaceAfter = 0,
  }) =>
      XmlElement(XmlName('w:pPr'), [], [
        if (align != null)
          XmlElement(XmlName('w:jc'), [XmlAttribute(XmlName('w:val'), align)]),
        if (indentLeft > 0)
          XmlElement(XmlName('w:ind'),
              [XmlAttribute(XmlName('w:left'), indentLeft.toString())]),
        if (spaceAfter > 0)
          XmlElement(XmlName('w:spacing'),
              [XmlAttribute(XmlName('w:after'), spaceAfter.toString())]),
      ]);

  static String _two(int n) => n.toString().padLeft(2, '0');
}
