import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/reminder_item.dart';
import 'notification_service.dart';

/// A [NotificationService] backed by `flutter_local_notifications`.
///
/// Active only on Android and iOS; every method is a no-op on other platforms
/// so the same code path runs everywhere. Timers and alarms are scheduled with
/// `zonedSchedule`, which the OS delivers even when the app isn't running.
class LocalNotificationService implements NotificationService {
  LocalNotificationService([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;

  /// The single Android channel reminders post to.
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'reminders',
    'Reminders',
    description: 'Scheduled reminder alerts',
    importance: Importance.max,
  );

  /// Whether OS scheduling is available on this platform.
  bool get _supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  Future<void> init() async {
    if (!_supported) return;
    tzdata.initializeTimeZones();
    final String localZone =
        (await FlutterTimezone.getLocalTimezone()).identifier;
    tz.setLocalLocation(tz.getLocation(localZone));
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          // Permission is requested later, on the first reminder enabled, so we
          // don't prompt on an empty first launch.
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_channel);
    _ready = true;
  }

  @override
  Future<bool> requestPermissions() async {
    if (!_supported) return true;
    if (Platform.isAndroid) {
      final AndroidFlutterLocalNotificationsPlugin? android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final bool granted =
          await android?.requestNotificationsPermission() ?? false;
      await android?.requestExactAlarmsPermission();
      return granted;
    }
    final IOSFlutterLocalNotificationsPlugin? ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    return await ios?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        ) ??
        false;
  }

  @override
  Future<void> scheduleReminder({
    required int notificationId,
    required ReminderItem item,
    required DateTime firesAt,
  }) async {
    if (!_supported || !_ready) return;
    final tz.TZDateTime scheduled = tz.TZDateTime.from(firesAt, tz.local);
    // Never schedule in the past — a stale moment would fire immediately.
    if (!scheduled.isAfter(tz.TZDateTime.now(tz.local))) return;
    await _schedule(
      notificationId,
      item,
      scheduled,
      notificationMatchComponents(item),
      AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  /// Issues the schedule, degrading to an inexact alarm if exact alarms are
  /// denied (so a missing permission doesn't surface as an error in the UI).
  Future<void> _schedule(
    int id,
    ReminderItem item,
    tz.TZDateTime when,
    DateTimeComponents? match,
    AndroidScheduleMode mode,
  ) async {
    try {
      await _plugin.zonedSchedule(
        id: id,
        title: item.title.isEmpty ? 'Reminder' : item.title,
        body: item.subtitle,
        scheduledDate: when,
        notificationDetails: _details,
        androidScheduleMode: mode,
        matchDateTimeComponents: match,
      );
    } on PlatformException {
      if (mode == AndroidScheduleMode.exactAllowWhileIdle) {
        await _schedule(
          id,
          item,
          when,
          match,
          AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    }
  }

  @override
  Future<void> cancel(int notificationId) async {
    if (!_supported) return;
    await _plugin.cancel(id: notificationId);
  }

  @override
  Future<void> cancelAll() async {
    if (!_supported) return;
    await _plugin.cancelAll();
  }

  NotificationDetails get _details => NotificationDetails(
    android: AndroidNotificationDetails(
      _channel.id,
      _channel.name,
      channelDescription: _channel.description,
      importance: Importance.max,
      priority: Priority.high,
    ),
    iOS: const DarwinNotificationDetails(),
  );
}

/// The repeat rule for [item]'s scheduled notification: a recurring alarm
/// repeats weekly (same weekday and time); a one-off alarm or any timer fires
/// once. Pulled out as a pure function so the mapping is unit-testable without
/// the platform plugin.
DateTimeComponents? notificationMatchComponents(ReminderItem item) =>
    item.recurring && item.type == ReminderType.alarm
    ? DateTimeComponents.dayOfWeekAndTime
    : null;
