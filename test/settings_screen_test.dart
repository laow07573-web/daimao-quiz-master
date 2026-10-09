import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flashcard_app/models/app_settings.dart';
import 'package:flashcard_app/screens/settings_screen.dart';
import 'package:flashcard_app/services/app_state.dart';
import 'package:flashcard_app/services/sync/sync_engine.dart';
import 'package:flashcard_app/services/sync/sync_models.dart';
import 'package:flashcard_app/services/theme_service.dart';

class FakeSettingsState extends AppState {
  AppSettings current = AppSettings(autoSync: false);
  bool reminder = false;
  DateTime? time;
  @override
  AppSettings get settings => current;
  @override
  Future<void> updateSettings(AppSettings settings) async {
    current = settings;
    notifyListeners();
  }

  @override
  bool get reminderEnabled => reminder;
  @override
  DateTime? get reminderTime => time;
  @override
  Future<void> setReminderSettings(
      {required bool enabled, DateTime? time}) async {
    reminder = enabled;
    this.time = time ?? this.time;
    notifyListeners();
  }

  @override
  Future<double?> fetchAIBalance() async => null;
  @override
  Future<int> getUntaggedErrorCount() async => 0;
}

class FailingSync extends ChangeNotifier implements SyncEngine {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  bool get syncing => false;
  @override
  String get statusMessage => '';
  @override
  DateTime? get lastSyncAt => null;
  @override
  List<DiscoveredPeer> get peers => [];
  bool running = false;
  bool fail = true;
  @override
  bool get started => running;
  @override
  Future<void> start({required bool autoSync}) async {
    if (fail) throw StateError('service unavailable');
    running = true;
  }

  @override
  Future<void> applyAutoSync(bool enabled) async {
    if (fail && enabled) throw StateError('apply unavailable');
  }

  // ── 识别码与同步范围（2026-10-08 新增的 SyncEngine API）──
  // mock 必须显式实现，否则 noSuchMethod 抛错会让整个同步区块渲染失败
  @override
  String get deviceCode => 'TESTCODE0000AAAA';
  @override
  String get peerCode => '';
  @override
  bool get paired => false;
  @override
  String get tempCode => '';
  @override
  DateTime? get tempExpiry => null;
  @override
  bool get tempCodeAlive => false;
  @override
  bool get banksOnly => false;
  @override
  void applyPeerCode(String raw) {}
  @override
  void generateTempCode() {}
  @override
  void clearTempCode() {}
  @override
  void applyBanksOnly(bool banksOnly) {}
}

class FakeReminderActions extends SettingsReminderActions {
  bool granted = false;
  bool failSchedule = false;
  int schedules = 0;
  @override
  Future<bool> hasPermission() async => granted;
  @override
  Future<bool> requestPermission() async => granted;
  @override
  Future<void> syncSchedule() async {
    schedules++;
    if (failSchedule) throw StateError('schedule unavailable');
  }
}

void main() {
  Future<void> showSettings(WidgetTester tester, FakeSettingsState app,
      FailingSync sync, FakeReminderActions reminder) async {
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: app),
        ChangeNotifierProvider<SyncEngine>.value(value: sync),
        ChangeNotifierProvider<ThemeService>(create: (_) => ThemeService()),
      ],
      child: MaterialApp(
          home: SettingsScreen(
        group: SettingsGroup.sync,
        reminderActions: reminder,
      )),
    ));
    await tester.pumpAndSettle();
  }

  for (final started in [false, true]) {
    testWidgets(
        'auto sync ${started ? 'application' : 'startup'} failure keeps off and allows retry',
        (tester) async {
      final app = FakeSettingsState();
      final sync = FailingSync()..running = started;
      await showSettings(tester, app, sync, FakeReminderActions());
      await tester.tap(find.text('自动同步已关闭'));
      await tester.pumpAndSettle();
      expect(app.settings.autoSync, isFalse);
      expect(find.textContaining('自动同步设置失败'), findsOneWidget);
      sync.fail = false;
      await tester.tap(find.text('自动同步已关闭'));
      await tester.pumpAndSettle();
      expect(app.settings.autoSync, isTrue);
      expect(find.text('自动同步已开启'), findsOneWidget);
      expect(find.textContaining('自动同步设置失败'), findsNothing);
    });
  }

  testWidgets('denied permission never enables reminder; granting allows retry',
      (tester) async {
    final app = FakeSettingsState();
    final actions = FakeReminderActions();
    await showSettings(tester, app, FailingSync(), actions);
    final toggle = find.byKey(const ValueKey('settings-reminder-switch'));
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(app.reminderEnabled, isFalse);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    expect(find.textContaining('提醒未开启'), findsOneWidget);
    actions.granted = true;
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(app.reminderEnabled, isTrue);
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
  });

  testWidgets('reminder schedule failure rolls back and displays failure',
      (tester) async {
    final app = FakeSettingsState();
    final actions = FakeReminderActions()
      ..granted = true
      ..failSchedule = true;
    await showSettings(tester, app, FailingSync(), actions);
    final toggle = find.byKey(const ValueKey('settings-reminder-switch'));
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(app.reminderEnabled, isFalse);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    expect(find.textContaining('提醒设置失败'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stored reminder is not shown enabled without permission',
      (tester) async {
    final app = FakeSettingsState()..reminder = true;
    await showSettings(tester, app, FailingSync(), FakeReminderActions());
    expect(
        tester
            .widget<SwitchListTile>(
                find.byKey(const ValueKey('settings-reminder-switch')))
            .value,
        isFalse);
    expect(find.textContaining('提醒不可用'), findsOneWidget);
  });
}
