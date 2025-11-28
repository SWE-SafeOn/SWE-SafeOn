import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/alert.dart';

/// Handles local push notifications for new alerts.
class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _alertChannel =
      AndroidNotificationChannel(
    'safeon_alerts',
    'SafeOn Alerts',
    description: '새로운 보안 이벤트 알림',
    importance: Importance.high,
    playSound: true,
  );

  static Future<void> initialize() async {
    if (kIsWeb) return;

    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );

    await _plugin.initialize(initializationSettings);

    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(_alertChannel);
    }

    await requestPermission();
  }

  /// Requests notification permission from the platform.
  /// Returns true when permission is granted.
  static Future<bool> requestPermission() async {
    if (kIsWeb) return false;

    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      final granted = await androidPlugin?.requestNotificationsPermission();
      return granted ?? true;
    }

    final iosPlugin = _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
    if (iosPlugin != null) {
      final granted = await iosPlugin.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }

    final macOsPlugin = _plugin
        .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin>();
    if (macOsPlugin != null) {
      final granted = await macOsPlugin.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }

    return false;
  }

  /// Cancels any delivered notifications so the user no longer sees them
  /// when push is turned off.
  static Future<void> disableNotifications() async {
    if (kIsWeb) return;
    await _plugin.cancelAll();
  }

  static Future<void> showAlertNotification(SafeOnAlert alert) async {
    if (kIsWeb) return;

    final androidDetails = AndroidNotificationDetails(
      _alertChannelId,
      _alertChannelName,
      channelDescription: _alertChannelDescription,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    final body = '${alert.reason} • ${alert.severity.label}';

    await _plugin.show(
      alert.id.hashCode,
      '새로운 안전 알림',
      body,
      notificationDetails,
    );
  }

  static String get _alertChannelId => _alertChannel.id;
  static String get _alertChannelName => _alertChannel.name;
  static String? get _alertChannelDescription => _alertChannel.description;
}
