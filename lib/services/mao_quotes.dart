import 'dart:math';

/// 猫卷语录（点首页/我的页的 Logo 触发）。
///
/// 与「一言」是**两套东西**，不要混：
/// - [HitokotoService]：网络 API 拉取，显示在首页问候卡下面那行小字；
/// - 这里：[quotes] 本地固定集合，离线可用、随版本走，点 Logo 随机弹一条。
///
/// 2026-10-09 用户提的需求：「在首页或者我的页面里点击猫卷logo会触发随机语录，
/// 与一言的语录不同」。
///
/// ⚠️ [quotes] 是**作者给的原文**（2026-10-09 由 DOCX 录入），一行一条。
/// 要保持作者的书写习惯与标点：省略号是「……」不是「...」，emoji、波浪号、
/// 全角问号都照原样，不要替他润色或补标点。
class MaoQuotes {
  MaoQuotes._();

  /// 正式语录（一行一条，作者原文）。
  static const List<String> quotes = <String>[
    '老大老大……',
    '喵？',
    '呆猫想吃猫饭',
    '哈！',
    '老大，我来救你了喵',
    '一击就能让装备烂的猎人猫车回家喵！',
    '去码头整点薯条吃……',
    '是啊，吃什么',
    '咕咕咕……',
    '呱?呱！',
    '白眼雄性果蝇抖擞抖擞精神……',
    '9331?!',
    '3301',
    '3401',
    '老大，要饿死了喵',
    '把你种土里，你重新长吧',
    '325?!',
    '韭菜盒子真好吃——',
    '你还不能睡觉，因为附近有怪物在游荡',
    'miss',
    '让我再卫一把吧😭',
    '老大老大，MOS管在发光诶',
    '别点了——会似掉的……',
    '干嘛……',
    '刘氏肠粉天下第一',
    '掉追了……我重进一下',
    '怎么老是对不上焦啊(恼)',
    '做完有奖励，做不完有惩罚(意味深)',
    '嗨，一库走',
    'こ ↑ こ ↓',
    '薯条？!',
    '好，把他们上市！',
    '土豆……',
    '莆田公交真的好贵……(悄悄话)',
  ];

  /// 上一条的下标：避免连点两次弹同一条
  static int _lastIndex = -1;

  static bool get isEmpty => quotes.isEmpty;

  /// 随机取一条。
  ///
  /// 两条以上时会**避开上一条**——连点两下看到同一句会让人觉得"没反应"。
  /// [random] 可注入以便测试；[reset] 供测试清空去重状态。
  static String pick({Random? random, bool reset = false}) {
    if (reset) _lastIndex = -1;
    if (quotes.isEmpty) return '';
    if (quotes.length == 1) return quotes.first;
    final r = random ?? Random();
    var index = r.nextInt(quotes.length);
    if (index == _lastIndex) {
      // 撞上上一条时顺移一格，仍然保持均匀（只是排除单一重复）
      index = (index + 1) % quotes.length;
    }
    _lastIndex = index;
    return quotes[index];
  }
}
