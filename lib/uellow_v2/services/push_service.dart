// =============================================================================
// PushService — local + remote notifications, plus the "ongoing pinned"
// order-tracking notification used while an order is in transit. Uses
// flutter_local_notifications for the Android pinned banner and any
// foreground FCM messages.
//
// FCM token registration relies on the platform-provided messaging plugin
// when it's added later. For now this service is the surface the rest of
// the app talks to; the token registration call already lives in
// UellowApi.notifications.registerDevice and accepts whatever the
// platform-native code surfaces via MethodChannel.
//
// The pinned notification is updated via showOngoingOrder(...) — call it
// every time the backend reports a stage change, and dismiss it when
// the order is delivered with cancelOrder(orderId).
// =============================================================================
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class PushService {
  PushService._();
  static final PushService instance = PushService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _liveActivityChannel = MethodChannel('com.uellow.liveactivity');

  Future<void> init() async {
    if (_ready) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true, requestBadgePermission: true,
      requestSoundPermission: true);
    await _plugin.initialize(const InitializationSettings(android: android, iOS: ios));
    // Create channels up front so settings UI shows them.
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      await androidImpl.createNotificationChannel(const AndroidNotificationChannel(
        'order_update', 'Order updates',
        description: 'Status changes, driver assignment, arrival alerts.',
        importance: Importance.high));
      await androidImpl.createNotificationChannel(const AndroidNotificationChannel(
        'driver_location', 'Driver location',
        description: 'Silent map heartbeats.',
        importance: Importance.low));
      await androidImpl.createNotificationChannel(const AndroidNotificationChannel(
        'live_tracking', 'Live order tracking',
        description: 'Ongoing pinned notification while order is in transit.',
        importance: Importance.high));
      try { await androidImpl.requestNotificationsPermission(); } catch (_) {}
    }
    _ready = true;
  }

  /// Show / update the pinned ongoing notification while an order is
  /// being delivered. Mirrors Temu / Uber-Eats style. On iOS the
  /// equivalent (Live Activity) is started via [_liveActivityChannel].
  Future<void> showOngoingOrder({
    required int orderId,
    required String title,
    required String body,
    required int progress, // 0..100
  }) async {
    await init();
    final androidDetails = AndroidNotificationDetails(
      'live_tracking', 'Live order tracking',
      channelDescription: 'Ongoing pinned notification while order is in transit.',
      importance: Importance.high, priority: Priority.high,
      ongoing: true, autoCancel: false, onlyAlertOnce: true,
      showProgress: true, maxProgress: 100, progress: progress,
      indeterminate: progress <= 0,
      ticker: title,
      visibility: NotificationVisibility.public,
    );
    final details = NotificationDetails(android: androidDetails);
    await _plugin.show(orderId, title, body, details,
        payload: 'order:$orderId');
    // iOS side — Live Activity update via native MethodChannel.
    try {
      await _liveActivityChannel.invokeMethod('update', {
        'orderId': orderId, 'title': title, 'body': body, 'progress': progress,
      });
    } on PlatformException catch (_) {
      // No native handler attached (older OS) — silently skip.
    } catch (_) {}
  }

  Future<void> cancelOrder(int orderId) async {
    await _plugin.cancel(orderId);
    try {
      await _liveActivityChannel.invokeMethod('end', {'orderId': orderId});
    } catch (_) {}
  }
}
