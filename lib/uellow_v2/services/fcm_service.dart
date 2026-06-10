// =============================================================================
// FcmService (v2.1.64) — Firebase Cloud Messaging glue.
// Background/killed messages are shown by the OS automatically (we send
// a `notification` block from the server). Foreground messages are
// surfaced through the existing flutter_local_notifications channel.
// The FCM token is registered with the backend on startup, after login,
// and on every token refresh — /notifications/register-device mirrors it
// onto mobile.session + res.partner so the server can target customers.
// =============================================================================
import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../api/uellow_api.dart';
import 'push_service.dart';

@pragma('vm:entry-point')
Future<void> _onBackgroundMessage(RemoteMessage message) async {
  // Notification-type messages are displayed by the system tray itself —
  // nothing to do. Data-only messages could be handled here later.
}

class FcmService {
  FcmService._();
  static final FcmService instance = FcmService._();
  bool _inited = false;

  Future<void> init() async {
    if (_inited) return;
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(_onBackgroundMessage);
      final fm = FirebaseMessaging.instance;
      await fm.requestPermission(alert: true, badge: true, sound: true);
      // Foreground messages → local notification (system tray look).
      FirebaseMessaging.onMessage.listen((m) {
        final n = m.notification;
        if (n != null) {
          PushService.instance.showRemote(
              title: n.title ?? 'Uellow', body: n.body ?? '');
        }
      });
      fm.onTokenRefresh.listen((t) => _register(t));
      final token = await fm.getToken();
      if (token != null && token.isNotEmpty) await _register(token);
      _inited = true;
    } catch (_) {
      // Devices without Google services (e.g. Huawei HMS) land here —
      // the in-app inbox keeps working regardless.
    }
  }

  /// Re-send the current token (call after login so the backend links
  /// the token to the customer).
  Future<void> register() async {
    try {
      final t = await FirebaseMessaging.instance.getToken();
      if (t != null && t.isNotEmpty) await _register(t);
    } catch (_) {}
  }

  Future<void> _register(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var deviceId = prefs.getString('uellow_device_id_v1') ?? '';
      if (deviceId.isEmpty) {
        deviceId =
            'dev_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
        await prefs.setString('uellow_device_id_v1', deviceId);
      }
      await UellowApi.instance.notifications.registerDevice(
        deviceId: deviceId,
        pushToken: token,
        platform: 'android',
      );
    } catch (_) {}
  }
}
