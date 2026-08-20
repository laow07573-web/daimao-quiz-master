import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'database_service.dart';
import 'debug_log_service.dart';
import 'hitokoto_service.dart';
import '../utils/format_utils.dart';

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

  static const _permissionChannel = MethodChannel('com.flashcard.app/notification');

  bool _initialized = false;
  String _notifiedKeyPrefix = 'reminder_notified_';

  bool get initialized => _initialized;

  // ======================== Android 13+ 通知权限 ========================

  /// 请求通知运行时权限（弹系统授权框）。
  /// 已授权或 Android < 13 直接返回 true；发起请求时返回 false（需用户确认后
  /// 通过 [hasNotificationPermission] 复查）。
  /// v1.0.2 设计审查修复：通道异常 fail-closed（此前 fail-open 会把失败当已授权）
  Future<bool> requestNotificationPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _permissionChannel
              .invokeMethod<bool>('requestNotificationPermission') ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// 是否已有通知权限（v1.0.2 设计审查修复：通道异常 fail-closed）
  Future<bool> hasNotificationPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _permissionChannel.invokeMethod<bool>('hasNotificationPermission') ??
          false;
    } catch (_) {
      return false;
    }
  }

  // ======================== 初始化 ========================

  Future<void> init() async {
    if (_initialized) return;
    if (!Platform.isAndroid) return;

    // 时区
    tzdata.initializeTimeZones();
    try {
      final tzName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(tzName));
    } catch (e) {
      // v1.0.2 设计审查修复：兜底不再硬编码上海时区
      // （非中国用户提醒时间会偏移数小时且无感知），改用 UTC 并记录日志
      tz.setLocalLocation(tz.UTC);
      DebugLogService.instance.log('REMINDER', '本地时区获取失败，兜底 UTC: $e');
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
        // v1.0.2 设计审查修复（简化保活）：去开机自启。
        // 重启后提醒恢复依赖 ScheduledNotificationBootReceiver 恢复 pending alarm
        // + 用户打开 App 时 syncSchedule
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
      await _scheduleAlarm();
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

  /// 排程单次 AlarmManager（zonedSchedule；当天时间已过则排明天；
  /// [forceTomorrow] 为 true 时无条件排明天——答题后续排用，避免"已刷当天仍弹"）
  Future<void> _scheduleAlarm({bool forceTomorrow = false}) async {
    final now = DateTime.now();
    var target = await _reminderTimeToday();
    if (forceTomorrow || target.isBefore(now)) {
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
      '猫卷',
      await _buildReminderText(),
      tz.TZDateTime.from(target, tz.local),
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  /// 答题/启动后续排明天（今天已刷，不再重复提醒）
  Future<void> rescheduleNextDay() async {
    if (!Platform.isAndroid || !_initialized) return;
    final enabled = (await _db.getSetting('reminder_enabled') ?? '0') == '1';
    if (!enabled) return;
    await _scheduleAlarm(forceTomorrow: true);
  }

  // ======================== 前台服务 ========================

  Future<void> _startForegroundService() async {
    if (await FlutterForegroundTask.isRunningService) return;
    final hitokoto = await _fetchHitokoto();
    await FlutterForegroundTask.startService(
      notificationTitle: '猫卷',
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
    // 弹通知后取消当天 alarm 防双弹，并接力排明天（保证次日提醒不中断）
    await _notifications.cancel(alarmId);
    await _scheduleAlarm(forceTomorrow: true);
  }

  Future<bool> _practicedToday(DateTime now) async {
    final daily = await _db.getDailyStats(1);
    if (daily.isEmpty) return false;
    return (daily.last['total'] as int) > 0;
  }

  Future<bool> _alreadyNotified(DateTime now) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_notifiedKeyPrefix${dateKeyOf(now)}') ?? false;
  }

  Future<void> _notify(DateTime now) async {
    // 先记录已弹，再弹通知：进程在 show 与记录之间被杀也不会重复弹
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_notifiedKeyPrefix${dateKeyOf(now)}', true);
    await _notifications.show(
      notifyId,
      '猫卷',
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
    // 补弹后同样接力排明天
    await _scheduleAlarm(forceTomorrow: true);
  }

  /// 发送测试通知（设置页按钮，验证通知渠道可用）。
  /// 返回是否实际发出（非 Android 或未初始化返回 false）。
  /// v1.0.2 设计审查修复：权限被拒时如实返回 false（此前无条件报「已发送」）
  Future<bool> sendTestNotification() async {
    if (!Platform.isAndroid || !_initialized) return false;
    if (!await hasNotificationPermission()) return false;
    await _notifications.show(
      9999,
      '猫卷',
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
    return true;
  }

  // ======================== 文案 ========================

  /// 提醒文案（v1.0.2 对齐里程碑）：
  /// 有连击 → 「你已连续打卡 X 天，继续刷题积累吧！」
  /// 无连击 → 「来几道题，开启新的连胜吧」
  /// [streakWithToday]：含今天（今天已刷时的连击）
  /// [streakWithoutToday]：不含今天（截止昨天）
  static String buildReminderText(int streakWithToday, int streakWithoutToday) {
    final cur = streakWithToday > streakWithoutToday
        ? streakWithToday
        : streakWithoutToday;
    if (cur > 0) {
      return '你已连续打卡 $cur 天，继续刷题积累吧！';
    }
    return '来几道题，开启新的连胜吧';
  }

  Future<String> _buildReminderText() async {
    final daily = await _db.getDailyStats(365);
    final totals = <String, int>{
      for (final d in daily) dateKeyOf(d['date'] as DateTime): d['total'] as int,
    };
    final now = DateTime.now();
    final (start, end) = await _vacationRange();
    final withoutToday = DatabaseService.countConsecutiveDays(
      totals,
      now: now,
      vacationStart: start,
      vacationEnd: end,
    );
    // 含今天：把今天当作截止日重新计算
    final upToToday = DatabaseService.countConsecutiveDays(
      totals,
      now: now,
      vacationStart: start,
      vacationEnd: end,
      upTo: now,
    );
    return buildReminderText(upToToday, withoutToday);
  }

  /// 假期区间（起止日期）。v1.0.2 设计审查修复：区间判断，
  /// 不再逐日展开列表
  Future<(DateTime?, DateTime?)> _vacationRange() async {
    final startRaw = await _db.getSetting('vacation_start_date');
    final endRaw = await _db.getSetting('vacation_end_date');
    final enabled = (await _db.getSetting('vacation_mode_enabled') ?? '0') == '1';
    if (!enabled || startRaw == null || endRaw == null) return (null, null);
    return (DateTime.tryParse(startRaw), DateTime.tryParse(endRaw));
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
}

/// 前台服务后台任务处理器（v1.0.2 设计审查修复：仅保 Flutter 引擎存活，
/// 提醒检查由主 isolate Timer 承担；后台 isolate 无法访问 sqflite 插件。
/// 重启后提醒恢复依赖 boot 恢复 pending alarm + 用户下次打开 App 时 syncSchedule）
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
