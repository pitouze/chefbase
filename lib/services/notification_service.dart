import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class TimerPermissionStatus {
  final bool notificationsAllowed;
  final bool exactAlarmsAllowed;

  const TimerPermissionStatus({
    required this.notificationsAllowed,
    required this.exactAlarmsAllowed,
  });
}

class TimerScheduleResult {
  final bool scheduled;
  final bool exact;
  final String? message;

  const TimerScheduleResult({
    required this.scheduled,
    required this.exact,
    this.message,
  });
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static Future<void>? _initFuture;
  static bool _initialized = false;

  static const String _soundKey = 'chefbase_timer_sound_v1';
  static const String defaultSound = 'alarm';
  static const Map<String, String> soundLabels = {
    'alarm': 'Alarme',
    'bell': 'Cloche',
    'alert': 'Alerte',
  };

  static String selectedSound = defaultSound;

  static Future<void> init() {
    if (_initialized) {
      debugPrint('NotificationService: init skipped, already initialized');
      return Future.value();
    }
    final inFlight = _initFuture;
    if (inFlight != null) {
      debugPrint('NotificationService: init reused in-flight future');
      return inFlight;
    }

    _initFuture = _performInit();
    return _initFuture!;
  }

  static Future<void> _performInit() async {
    debugPrint('NotificationService: init start');
    tz.initializeTimeZones();

    try {
      final tzName = await FlutterTimezone.getLocalTimezone().timeout(
        const Duration(seconds: 2),
      );
      tz.setLocalLocation(tz.getLocation(tzName.identifier));
      debugPrint('NotificationService: timezone set to ${tzName.identifier}');
    } catch (error) {
      debugPrint('NotificationService: timezone fallback to UTC: $error');
      tz.setLocalLocation(tz.UTC);
    }

    try {
      await _loadSelectedSound().timeout(const Duration(seconds: 2));
      debugPrint('NotificationService: selected sound ready');
    } catch (error) {
      debugPrint('NotificationService: sound load skipped: $error');
    }

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
      macOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );

    try {
      await _plugin
          .initialize(settings: settings)
          .timeout(const Duration(seconds: 3));
      _initialized = true;
      debugPrint('NotificationService: plugin initialized');
    } catch (error, stackTrace) {
      debugPrint('NotificationService: plugin init failed: $error');
      debugPrint('$stackTrace');
      rethrow;
    } finally {
      _initFuture = null;
    }
  }

  static Future<void> _loadSelectedSound() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_soundKey);
    if (saved != null && soundLabels.containsKey(saved)) {
      selectedSound = saved;
    }
  }

  static Future<void> setSelectedSound(String sound) async {
    if (!soundLabels.containsKey(sound)) return;

    await init();
    selectedSound = sound;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_soundKey, sound);
  }

  static Future<TimerPermissionStatus> requestTimerPermissions() async {
    await init();
    var notificationsAllowed = true;
    var exactAlarmsAllowed = true;

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      final notificationResult =
          await androidPlugin.requestNotificationsPermission();
      final exactResult = await androidPlugin.requestExactAlarmsPermission();
      notificationsAllowed = notificationResult ?? true;
      exactAlarmsAllowed = exactResult ?? true;
    }

    final iosPlugin = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (iosPlugin != null) {
      notificationsAllowed = await iosPlugin.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }

    final macOSPlugin = _plugin.resolvePlatformSpecificImplementation<
        MacOSFlutterLocalNotificationsPlugin>();
    if (macOSPlugin != null) {
      notificationsAllowed = await macOSPlugin.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }

    return TimerPermissionStatus(
      notificationsAllowed: notificationsAllowed,
      exactAlarmsAllowed: exactAlarmsAllowed,
    );
  }

  static NotificationDetails _details() {
    final android = AndroidNotificationDetails(
      'chefbase_timer_$selectedSound',
      'ChefBase Timers ${soundLabels[selectedSound] ?? selectedSound}',
      importance: Importance.max,
      priority: Priority.high,
      sound: RawResourceAndroidNotificationSound(selectedSound),
      playSound: true,
      enableVibration: true,
    );

    final darwin = DarwinNotificationDetails(
      sound: '$selectedSound.wav',
      presentSound: true,
      presentAlert: true,
      presentBadge: true,
      presentBanner: true,
      presentList: true,
      interruptionLevel: InterruptionLevel.active,
    );

    return NotificationDetails(
      android: android,
      iOS: darwin,
      macOS: darwin,
    );
  }

  static Future<void> scheduleTimerNotification({
    required int id,
    required String title,
    required Duration duration,
  }) async {
    await scheduleTimerNotificationWithResult(
      id: id,
      title: title,
      duration: duration,
    );
  }

  static Future<TimerScheduleResult> scheduleTimerNotificationWithResult({
    required int id,
    required String title,
    required Duration duration,
  }) async {
    await init();
    final permissions = await requestTimerPermissions();
    if (!permissions.notificationsAllowed) {
      return const TimerScheduleResult(
        scheduled: false,
        exact: false,
        message: 'Notifications désactivées pour ChefBase.',
      );
    }

    final scheduledDate = tz.TZDateTime.now(tz.local).add(duration);

    try {
      await _zonedSchedule(
        id: id,
        title: title,
        scheduledDate: scheduledDate,
        scheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
      return TimerScheduleResult(
        scheduled: true,
        exact: true,
        message: permissions.exactAlarmsAllowed
            ? null
            : 'Timer lancé. Active les alarmes exactes Android pour plus de précision.',
      );
    } catch (_) {
      await _zonedSchedule(
        id: id,
        title: title,
        scheduledDate: scheduledDate,
        scheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
      return const TimerScheduleResult(
        scheduled: true,
        exact: false,
        message:
            'Timer lancé en mode économie. Il peut sonner avec un léger retard.',
      );
    }
  }

  static Future<void> _zonedSchedule({
    required int id,
    required String title,
    required tz.TZDateTime scheduledDate,
    required AndroidScheduleMode scheduleMode,
  }) async {
    await _plugin.zonedSchedule(
      id: id,
      title: 'ChefBase',
      body: '$title est prêt',
      scheduledDate: scheduledDate,
      notificationDetails: _details(),
      androidScheduleMode: scheduleMode,
    );
  }

  static Future<void> cancelNotification(int id) async {
    await init();
    await _plugin.cancel(id: id);
  }
}
