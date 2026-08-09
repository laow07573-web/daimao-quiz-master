import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'database_service.dart';
import 'hitokoto_service.dart';

/// 每日提醒（v1.0.2）双保险：
/// - 前台服务（主力）：flutter_foreground_task 每 30 秒轮询，
///   到点窗口 10 分钟内 + 今日未刷 + 未弹过 → 弹通知(id 1002) + 取消当天 alarm(id 1001) 防双弹
/// - AlarmManager（兜底）：zonedSchedule 单次排程，每次启动/答题后续排明天，
///   inexactAllowWhileIdle 免精确闹钟权限
/// - 补弹：App 打开时 catchUpReminderIfMissed：已过时间 + 未刷 + 未弹过 → 补弹；
///   先查通知栏活跃通知（1001/1002）防双弹，先弹后记录
/// - 启动条件：reminderEnabled && !vacationModeEnabled
class ReminderService {
  ReminderService._();
  static final ReminderService instance = ReminderService._();

  static const int alarmId = 1001;
  static const int notifyId = 1002;

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  final DatabaseService _db = DatabaseService.instance;

  bool _initialized = false;
  String _notifiedKeyPrefix = 'reminder_notified_';

  bool get initialized => _initialized;

  // ======================== 初始化 ========================

  Future<void> init() async {
    if (_initialized) return;
    if (!Platform.isAndroid) return;

    // 时区
    tzdata.initializeTimeZones();
    try {
      final tzName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(tzName));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    }

    // 通知
    await _notifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );

    // 前台服务
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'flashcard_foreground',
        channelName: '刷题提醒服务',
        channelDescription: '保持刷题提醒服务运行（每 30 秒检查一次）',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        interval: 30000,
        autoRunOnBoot: false,
      ),
    );

    _initialized = true;
  }

  /// 同步提醒状态：按设置启停前台服务 + 排程 + 主 isolate 轮询
  Future<void> syncSchedule() async {
    if (!Platform.isAndroid || !_initialized) return;
    final enabled = (await _db.getSetting('reminder_enabled') ?? '0') == '1';
    final vacation = (await _db.getSetting('vacation_mode_enabled') ?? '0') == '1';
    final start = enabled && !vacation;
    if (start) {
      await _startForegroundService();
      _startPolling();
      await _scheduleAlarm(rescheduleIfPassed: true);
    } else {
      _stopPolling();
      await _stopAll();
    }
  }

  Timer? _pollTimer;

  /// 主 isolate 每 30 秒轮询（配合前台服务保活 + AlarmManager 兜底）
  void _startPolling() {
    _pollTimer ??= Timer.periodic(const Duration(seconds: 30), (_) {
      _checkAndNotify();
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  // ======================== 排程 ========================

  /// 今日提醒时间（默认 20:00）
  Future<DateTime> _reminderTimeToday() async {
    final raw = await _db.getSetting('reminder_time');
    final t = raw != null ? DateTime.tryParse(raw) : null;
    final now = DateTime.now();
    if (t == null) return DateTime(now.year, now.month, now.day, 20);
    return DateTime(now.year, now.month, now.day, t.hour, t.minute);
  }

  /// 排程单次 AlarmManager（zonedSchedule；当天时间已过则排明天）
  Future<void> _scheduleAlarm({bool rescheduleIfPassed = false}) async {
    final now = DateTime.now();
    var target = await _reminderTimeToday();
    if (target.isBefore(now)) {
      target = target.add(const Duration(days: 1));
    }
    final details = const NotificationDetails(
      android: AndroidNotificationDetails(
        'flashcard_reminder',
        '每日刷题提醒',
        channelDescription: '每天定时提醒你刷题',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );
    await _notifications.zonedSchedule(
      alarmId,
      '呆猫刷题宝',
      await _buildReminderText(),
      tz.TZDateTime.from(target, tz.local),
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  /// 答题/启动后续排明天
  Future<void> rescheduleNextDay() async {
    if (!Platform.isAndroid || !_initialized) return;
    final enabled = (await _db.getSetting('reminder_enabled') ?? '0') == '1';
    if (!enabled) return;
    await _scheduleAlarm();
  }

  // ======================== 前台服务 ========================

  Future<void> _startForegroundService() async {
    if (await FlutterForegroundTask.isRunningService) return;
    final hitokoto = await _fetchHitokoto();
    await FlutterForegroundTask.startService(
      notificationTitle: '呆猫刷题宝',
      notificationText: hitokoto,
      callback: _foregroundCallback,
    );
  }

  Future<String> _fetchHitokoto() async {
    try {
      final hitokoto = await HitokotoService.fetch();
      return hitokoto ?? HitokotoService.defaultText;
    } catch (_) {
      return HitokotoService.defaultText;
    }
  }

  // ======================== 轮询检查（前台服务每 30 秒调用） ========================

  Future<void> _checkAndNotify() async {
    if (!Platform.isAndroid) return;
    final enabled = (await _db.getSetting('reminder_enabled') ?? '0') == '1';
    final vacation = (await _db.getSetting('vacation_mode_enabled') ?? '0') == '1';
    if (!enabled || vacation) return;

    final now = DateTime.now();
    final target = await _reminderTimeToday();
    // 到点窗口 10 分钟内
    if (now.isBefore(target) || now.isAfter(target.add(const Duration(minutes: 10)))) {
      return;
    }
    if (await _alreadyNotified(now)) return;
    if (await _practicedToday(now)) return;

    await _notify(now);
    // 弹通知后取消当天 alarm 防双弹
    await _notifications.cancel(alarmId);
  }

  Future<bool> _practicedToday(DateTime now) async {
    final daily = await _db.getDailyStats(1);
    if (daily.isEmpty) return false;
    return (daily.last['total'] as int) > 0;
  }

  Future<bool> _alreadyNotified(DateTime now) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_notifiedKeyPrefix${_dateKey(now)}') ?? false;
  }

  Future<void> _notify(DateTime now) async {
    await _notifications.show(
      notifyId,
      '呆猫刷题宝',
      await _buildReminderText(),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'flashcard_reminder',
          '每日刷题提醒',
          channelDescription: '每天定时提醒你刷题',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
    // 先弹后记录
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_notifiedKeyPrefix${_dateKey(now)}', true);
  }

  /// 补弹：App 打开时调用。已过时间 + 未刷 + 未弹过 → 补弹（防双弹：先查通知栏活跃通知）
  Future<void> catchUpReminderIfMissed() async {
    if (!Platform.isAndroid || !_initialized) return;
    final enabled = (await _db.getSetting('reminder_enabled') ?? '0') == '1';
    final vacation = (await _db.getSetting('vacation_mode_enabled') ?? '0') == '1';
    if (!enabled || vacation) return;

    final now = DateTime.now();
    final target = await _reminderTimeToday();
    if (now.isBefore(target)) return; // 还没到点
    if (await _alreadyNotified(now)) return;
    if (await _practicedToday(now)) return;

    // 防双弹：查通知栏活跃通知（1001/1002）
    final active = await _notifications.getActiveNotifications();
    final ids = active.map((n) => n.id).toSet();
    if (ids.contains(alarmId) || ids.contains(notifyId)) return;

    await _notify(now);
    await _notifications.cancel(alarmId);
  }

  /// 发送测试通知（设置页按钮，验证通知渠道可用）
  Future<void> sendTestNotification() async {
    if (!Platform.isAndroid || !_initialized) return;
    await _notifications.show(
      9999,
      '呆猫刷题宝',
      '这是一条测试通知，说明提醒渠道工作正常 ✅',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'flashcard_reminder',
          '每日刷题提醒',
          channelDescription: '每天定时提醒你刷题',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }

  // ======================== 文案 ========================

  /// 提醒文案：连击天数（含/不含今天两种口径）
  /// [streakWithToday]：含今天（今天已刷时的连击）
  /// [streakWithoutToday]：不含今天（截止昨天）
  static String buildReminderText(int streakWithToday, int streakWithoutToday) {
    final base = '今天还没刷题哦，快来打卡吧！';
    if (streakWithToday > 0 || streakWithoutToday > 0) {
      final cur = streakWithToday > streakWithoutToday
          ? streakWithToday
          : streakWithoutToday;
      return '今天还没刷题哦，快来打卡吧！当前已连续打卡 $cur 天 💪';
    }
    return base;
  }

  Future<String> _buildReminderText() async {
    final daily = await _db.getDailyStats(365);
    final totals = <String, int>{
      for (final d in daily)
        '${(d['date'] as DateTime).year}-'
            '${(d['date'] as DateTime).month.toString().padLeft(2, '0')}-'
            '${(d['date'] as DateTime).day.toString().padLeft(2, '0')}':
            d['total'] as int,
    };
    final now = DateTime.now();
    final vacation = await _vacationDates();
    final withoutToday = DatabaseService.countConsecutiveDays(
      totals,
      now: now,
      vacationDays: vacation,
    );
    // 含今天：把今天当作截止日重新计算
    final upToToday = DatabaseService.countConsecutiveDays(
      totals,
      now: now,
      vacationDays: vacation,
      upTo: now,
    );
    return buildReminderText(upToToday, withoutToday);
  }

  Future<List<DateTime>> _vacationDates() async {
    final startRaw = await _db.getSetting('vacation_start_date');
    final endRaw = await _db.getSetting('vacation_end_date');
    final enabled = (await _db.getSetting('vacation_mode_enabled') ?? '0') == '1';
    if (!enabled || startRaw == null || endRaw == null) return const [];
    final start = DateTime.tryParse(startRaw);
    final end = DateTime.tryParse(endRaw);
    if (start == null || end == null) return const [];
    final result = <DateTime>[];
    var cursor = DateTime(start.year, start.month, start.day);
    final last = DateTime(end.year, end.month, end.day);
    while (!cursor.isAfter(last)) {
      result.add(cursor);
      cursor = cursor.add(const Duration(days: 1));
    }
    return result;
  }

  // ======================== 停止 ========================

  Future<void> _stopAll() async {
    await FlutterForegroundTask.stopService();
    await _notifications.cancel(alarmId);
    await _notifications.cancel(notifyId);
  }

  Future<void> stopAll() async {
    _stopPolling();
    await _stopAll();
  }

  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// 前台服务后台任务处理器（保活；轮询检查由主 isolate Timer 承担）
class _ReminderTaskHandler extends TaskHandler {
  @override
  void onStart(DateTime timestamp, SendPort? sendPort) {}

  @override
  void onRepeatEvent(DateTime timestamp, SendPort? sendPort) {}

  @override
  void onDestroy(DateTime timestamp, SendPort? sendPort) {}
}

/// 前台服务回调（后台 isolate 入口）
@pragma('vm:entry-point')
void _foregroundCallback() {
  FlutterForegroundTask.setTaskHandler(_ReminderTaskHandler());
}
