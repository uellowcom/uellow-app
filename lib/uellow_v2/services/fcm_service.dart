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
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../api/uellow_api.dart';
import '../../main.dart' show rootNavigatorKey;
import '../router/uellow_router.dart';
import '../screens/admin/admin_orders_screen.dart';
import '../screens/admin/admin_pos_screen.dart';
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
      // Foreground messages → local notification (system tray look). Carry
      // the data map so a tap on the foreground notification routes too.
      PushService.onNotificationTap = handleTap;
      FirebaseMessaging.onMessage.listen((m) {
        final n = m.notification;
        if (n != null) {
          PushService.instance.showRemote(
              title: n.title ?? 'Uellow', body: n.body ?? '',
              data: m.data);
        }
      });
      // Tapping a notification (background → foreground) opens the record it
      // refers to. The server attaches a `data` map with a `type` + `id`
      // (admin_order, admin_pos_order, admin_pos_session, order, proximity…).
      FirebaseMessaging.onMessageOpenedApp.listen(
          (m) => handleTap(m.data));
      // Cold start from a tapped notification (app was killed).
      final initial = await fm.getInitialMessage();
      if (initial != null) {
        Future.delayed(const Duration(milliseconds: 900),
            () => handleTap(initial.data));
      }
      fm.onTokenRefresh.listen((t) => _register(t));
      // iOS: the FCM token is only mintable once the APNs token has arrived.
      // Fetch it first (short retry) and forward it so the backend can store
      // the real APNs token alongside the FCM one.
      String? apns;
      if (Platform.isIOS) {
        for (var i = 0; i < 5; i++) {
          apns = await fm.getAPNSToken();
          if (apns != null && apns.isNotEmpty) break;
          await Future.delayed(const Duration(milliseconds: 600));
        }
      }
      final token = await fm.getToken();
      if (token != null && token.isNotEmpty) await _register(token, apns: apns);
      _inited = true;
    } catch (_) {
      // Devices without Google services (e.g. Huawei HMS) land here —
      // the in-app inbox keeps working regardless.
    }
  }

  /// Route a tapped notification to the record it points at. Reads the FCM
  /// `data` map: `type` selects the screen, `id` (or `order_id`) the record.
  /// Public + static-friendly so a local-notification tap can reuse it.
  void handleTap(Map<String, dynamic> data) {
    try {
      final nav = rootNavigatorKey.currentState;
      if (nav == null || data.isEmpty) return;
      final type = (data['type'] ?? '').toString();
      final id = int.tryParse(
          (data['id'] ?? data['order_id'] ?? '').toString());
      switch (type) {
        case 'admin_order':
          if (id != null) {
            nav.push(MaterialPageRoute(
                builder: (_) => AdminOrderDetailScreen(orderId: id)));
          }
          break;
        case 'admin_pos_order':
        case 'admin_pos_session':
          nav.push(MaterialPageRoute(builder: (_) => const AdminPosScreen()));
          break;
        case 'order':
        case 'proximity':
        case 'driver_location':
          if (id != null) {
            nav.pushNamed(Routes.order, arguments: {'id': id});
          }
          break;
        default:
          // Unknown / silent payloads — nothing to open.
          break;
      }
    } catch (_) {}
  }

  /// Re-send the current token (call after login so the backend links
  /// the token to the customer).
  Future<void> register() async {
    try {
      final fm = FirebaseMessaging.instance;
      final apns = Platform.isIOS ? await fm.getAPNSToken() : null;
      final t = await fm.getToken();
      if (t != null && t.isNotEmpty) await _register(t, apns: apns);
    } catch (_) {}
  }

  Future<void> _register(String token, {String? apns}) async {
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
        platform: Platform.isIOS ? 'ios' : 'android',
        apnsToken: Platform.isIOS ? apns : null,
      );
    } catch (_) {}
  }
}
