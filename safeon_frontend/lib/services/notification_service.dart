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
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      ),
    );

    await _plugin.initialize(initializationSettings);

    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(_alertChannel);
      await androidPlugin?.requestNotificationsPermission();
    }
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
