import '../models/question.dart';

/// 内置示例题库（一键导入按钮用）
///
/// 面向医学生用户的演示题库：无需文件、无需 AI 解析，
/// 让新用户装完 App 即可体验刷题、判题反馈、错题本与知识点统计。
/// 覆盖单选/多选/判断三种题型，均带解析与知识点。
const String sampleBankName = '示例题库·医学基础速练';

/// 生成示例题目（绑定到指定题库）
List<Question> sampleQuestions({
  required int bankId,
  required String createdAt,
}) {
  return [
    Question(
      bankId: bankId,
      title: '正常成人安静状态下，心率的主要调节方式是？',
      options: ['体液调节', '自身调节', '神经调节', '局部代谢产物调节'],
      correctAnswer: 'C',
      analysis:
          '安静状态下心率主要受自主神经（心迷走神经与心交感神经）调节，其中迷走神经的紧张性活动占主导，是心率最重要的调节方式。',
      questionType: 'single_choice',
      knowledgePoint: '心血管生理',
      createdAt: createdAt,
    ),
    Question(
      bankId: bankId,
      title: '下列关于动作电位特点的描述，正确的是？',
      options: [
        '刺激强度越大，动作电位幅度越高',
        '动作电位可沿细胞膜不衰减传导',
        '动作电位可以总和',
        '动作电位幅度与细胞外 K⁺ 浓度无关',
      ],
      correctAnswer: 'B',
      analysis:
          '动作电位具有"全或无"现象，幅度不随刺激强度改变，也不可总和；其传导为不衰减传导。幅度主要取决于细胞外 Na⁺ 浓度。',
      questionType: 'single_choice',
      knowledgePoint: '细胞生理',
      createdAt: createdAt,
    ),
    Question(
      bankId: bankId,
      title: '革兰染色中，革兰阳性菌被染成的颜色是？',
      options: ['红色', '紫色', '绿色', '黄色'],
      correctAnswer: 'B',
      analysis:
          '革兰阳性菌细胞壁肽聚糖层厚，结晶紫-碘复合物不易被酒精脱色，最终保留初染的紫色；革兰阴性菌则被复染成红色。',
      questionType: 'single_choice',
      knowledgePoint: '微生物学',
      createdAt: createdAt,
    ),
    Question(
      bankId: bankId,
      title: '阿司匹林的主要作用机制是？',
      options: [
        '抑制环氧酶（COX）',
        '阻断 H₁ 受体',
        '抑制磷脂酶 A₂',
        '阻断白三烯受体',
      ],
      correctAnswer: 'A',
      analysis:
          '阿司匹林通过不可逆乙酰化环氧酶（COX-1/COX-2）活性位点，抑制前列腺素与血栓素 A₂ 的合成，发挥解热、镇痛、抗炎与抗血小板作用。',
      questionType: 'single_choice',
      knowledgePoint: '药理学',
      createdAt: createdAt,
    ),
    Question(
      bankId: bankId,
      title: '属于腹膜内位器官的是？',
      options: ['胃', '肝', '胰', '肾'],
      correctAnswer: 'A',
      analysis:
          '胃几乎全部被腹膜覆盖，为腹膜内位器官；肝为间位器官；胰、肾为腹膜外位器官。',
      questionType: 'single_choice',
      knowledgePoint: '解剖学',
      createdAt: createdAt,
    ),
    Question(
      bankId: bankId,
      title: '下列属于糖皮质激素生理作用的有哪些？',
      options: [
        '升高血糖',
        '促进蛋白质分解',
        '抑制免疫反应',
        '促进钙吸收',
      ],
      correctAnswer: 'A,B,C',
      analysis:
          '糖皮质激素可促进糖异生升高血糖、促进蛋白质分解、抑制免疫与炎症反应；但它减少钙吸收、促进钙排泄，长期使用可致骨质疏松。',
      questionType: 'multi_choice',
      knowledgePoint: '内分泌生理',
      createdAt: createdAt,
    ),
    Question(
      bankId: bankId,
      title: '关于缺氧的类型，下列说法正确的有？',
      options: [
        '贫血引起的缺氧属于血液性缺氧',
        '一氧化碳中毒属于低张性缺氧',
        '氰化物中毒属于组织性缺氧',
        '心力衰竭可引起循环性缺氧',
      ],
      correctAnswer: 'A,C,D',
      analysis:
          '贫血与 CO 中毒均属血液性缺氧（CO 与血红蛋白结合使其丧失携氧能力）；氰化物抑制细胞色素氧化酶，属组织性缺氧；心衰使组织灌注不足，为循环性缺氧。',
      questionType: 'multi_choice',
      knowledgePoint: '病理生理学',
      createdAt: createdAt,
    ),
    Question(
      bankId: bankId,
      title: '血浆渗透压主要由晶体渗透压构成，其中贡献最大的是 NaCl。',
      options: ['对', '错'],
      correctAnswer: '对',
      analysis:
          '血浆渗透压约 300 mOsm/L，晶体渗透压占绝大部分，其中 Na⁺ 和 Cl⁻ 数量最多、贡献最大；胶体渗透压主要由白蛋白维持，数值很小但对血管内外水平衡意义重大。',
      questionType: 'true_false',
      knowledgePoint: '血液生理',
      createdAt: createdAt,
    ),
    Question(
      bankId: bankId,
      title: '内脏痛的主要特点是定位准确、对切割刺激敏感。',
      options: ['对', '错'],
      correctAnswer: '错',
      analysis:
          '内脏痛定位模糊、对切割/烧灼等刺激不敏感，但对牵拉、缺血、痉挛和炎症等刺激敏感，常伴有牵涉痛和情绪反应。',
      questionType: 'true_false',
      knowledgePoint: '神经生理',
      createdAt: createdAt,
    ),
    Question(
      bankId: bankId,
      title: '青霉素最严重的不良反应是过敏性休克，用药前需询问过敏史并做皮试。',
      options: ['对', '错'],
      correctAnswer: '对',
      analysis:
          '青霉素毒性低，但可引发Ⅰ型超敏反应，最严重为过敏性休克，可危及生命，故用药前必须详细询问过敏史并进行皮肤试验。',
      questionType: 'true_false',
      knowledgePoint: '药理学',
      createdAt: createdAt,
    ),
  ];
}
