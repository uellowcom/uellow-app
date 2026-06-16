import 'dart:io' show Platform;
import 'package:flutter/services.dart';

/// Thin Dart wrapper over the native TikTok Business SDK bridge
/// (Android: MainActivity, iOS: AppDelegate) on channel `uellow/tiktok`.
///
/// All calls are fire-and-forget and never throw — analytics must never
/// break a user flow. No-op on platforms without the bridge (web/desktop).
class TikTokTracker {
  TikTokTracker._();
  static final TikTokTracker instance = TikTokTracker._();

  static const MethodChannel _ch = MethodChannel('uellow/tiktok');

  bool get _supported => Platform.isAndroid || Platform.isIOS;

  Future<void> _invoke(String method, [Map<String, dynamic>? args]) async {
    if (!_supported) return;
    try {
      await _ch.invokeMethod(method, args);
    } catch (_) {
      // swallow — never let tracking surface to the user
    }
  }

  /// Call whenever the user identity changes: login, sign-up, profile update.
  Future<void> identify({
    required String externalId,
    String? userName,
    String? phone,
    String? email,
  }) =>
      _invoke('identify', {
        'externalId': externalId,
        'externalUserName': userName,
        'phoneNumber': phone,
        'email': email,
      });

  Future<void> logout() => _invoke('logout');

  // --- simple (parameterless) events ---
  Future<void> launchApp() => _invoke('trackSimple', {'event': 'LAUNCH_APP'});
  Future<void> rate() => _invoke('trackSimple', {'event': 'RATE'});
  Future<void> addPaymentInfo() =>
      _invoke('trackSimple', {'event': 'ADD_PAYMENT_INFO'});
  Future<void> registration() =>
      _invoke('trackSimple', {'event': 'REGISTRATION'});
  Future<void> login() => _invoke('trackSimple', {'event': 'LOGIN'});
  Future<void> search() => _invoke('trackSimple', {'event': 'SEARCH'});

  // --- e-commerce content events ---
  Future<void> _content(
    String type, {
    required String contentId,
    String? contentName,
    String? contentCategory,
    String? brand,
    double? price,
    int quantity = 1,
    double? value,
    String currency = 'KWD',
    String contentType = 'product',
    String? description,
  }) =>
      _invoke('trackContent', {
        'type': type,
        'contentId': contentId,
        'contentName': contentName,
        'contentCategory': contentCategory,
        'brand': brand,
        'price': price,
        'quantity': quantity,
        'value': value ?? ((price ?? 0) * quantity),
        'currency': currency,
        'contentType': contentType,
        'description': description ?? contentName,
      });

  Future<void> viewContent({
    required String contentId,
    String? contentName,
    String? contentCategory,
    String? brand,
    double? price,
    String currency = 'KWD',
  }) =>
      _content('ViewContent',
          contentId: contentId,
          contentName: contentName,
          contentCategory: contentCategory,
          brand: brand,
          price: price,
          value: price,
          currency: currency);

  Future<void> addToCart({
    required String contentId,
    String? contentName,
    String? contentCategory,
    String? brand,
    double? price,
    int quantity = 1,
    String currency = 'KWD',
  }) =>
      _content('AddToCart',
          contentId: contentId,
          contentName: contentName,
          contentCategory: contentCategory,
          brand: brand,
          price: price,
          quantity: quantity,
          currency: currency);

  Future<void> addToWishlist({
    required String contentId,
    String? contentName,
    double? price,
    String currency = 'KWD',
  }) =>
      _content('AddToWishlist',
          contentId: contentId,
          contentName: contentName,
          price: price,
          currency: currency);

  /// Begin checkout. Pass the order subtotal/total as [value].
  Future<void> checkout({
    required String contentId,
    double? value,
    String currency = 'KWD',
  }) =>
      _content('Checkout',
          contentId: contentId, value: value, currency: currency);

  /// Completed purchase. [value] = order total.
  Future<void> purchase({
    required String contentId,
    String? contentName,
    double? value,
    int quantity = 1,
    String currency = 'KWD',
  }) =>
      _content('Purchase',
          contentId: contentId,
          contentName: contentName,
          value: value,
          quantity: quantity,
          currency: currency);
}
