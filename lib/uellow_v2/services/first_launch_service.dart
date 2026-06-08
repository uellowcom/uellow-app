// =============================================================================
// FirstLaunchService — runs once after the country picker on a fresh install.
// Requests Location + Notification permissions, then (if location granted)
// fetches a coarse GPS fix and reverse-geocodes it via Nominatim. The result
// is stashed in SharedPreferences so checkout's "Detect my address" button
// can fill the form without a second round-trip.
//
// All work is non-blocking: callers fire-and-forget so the splash → home
// transition stays snappy.
// =============================================================================
import 'dart:async';
import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../api/uellow_api.dart';

class FirstLaunchService {
  FirstLaunchService._();

  static const _kRanKey = 'uellow_first_launch_perms_v1';
  static const _kLatKey = 'uellow_geo_lat_v1';
  static const _kLngKey = 'uellow_geo_lng_v1';
  static const _kAddrKey = 'uellow_geo_addr_v1';
  static const _kTsKey = 'uellow_geo_ts_v1';

  /// Called once from Splash after the country picker has been resolved.
  /// Idempotent — subsequent calls are no-ops.
  static Future<void> kickOff() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kRanKey) == true) return;
    // Mark first-launch consumed BEFORE doing the work so a crash inside
    // permission_handler / geolocator doesn't trap the user in a permission
    // loop on every cold start.
    await prefs.setBool(_kRanKey, true);

    // Notification permission — best-effort, ignore the result.
    try { await Permission.notification.request(); } catch (_) {}

    // Location — try the higher-level handler first (works on Android 12+
    // with foreground/background nuances), fall back to Geolocator's own
    // request if the package returns "permanentlyDenied" without prompting.
    try {
      var st = await Permission.locationWhenInUse.status;
      if (st.isDenied) st = await Permission.locationWhenInUse.request();
      if (!st.isGranted) {
        var lp = await Geolocator.checkPermission();
        if (lp == LocationPermission.denied) {
          lp = await Geolocator.requestPermission();
        }
        if (lp != LocationPermission.always && lp != LocationPermission.whileInUse) {
          return;
        }
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      );
      await prefs.setDouble(_kLatKey, pos.latitude);
      await prefs.setDouble(_kLngKey, pos.longitude);
      await prefs.setInt(_kTsKey, DateTime.now().millisecondsSinceEpoch);
      // Reverse-geocode (Nominatim, no key needed). Failure is non-fatal —
      // we still have the coords so the checkout map can self-geocode.
      try {
        final r = await http.get(
          Uri.parse(
            'https://nominatim.openstreetmap.org/reverse?format=jsonv2'
            '&lat=${pos.latitude}&lon=${pos.longitude}'
            '&accept-language=${UellowApi.instance.lang}',
          ),
          headers: {'User-Agent': 'UellowApp/2.0 (support@uellow.com)'},
        ).timeout(const Duration(seconds: 6));
        if (r.statusCode == 200) {
          final j = jsonDecode(r.body) as Map<String, dynamic>;
          final addr = (j['display_name'] as String?) ?? '';
          if (addr.isNotEmpty) await prefs.setString(_kAddrKey, addr);
        }
      } catch (_) {}
    } catch (_) {/* swallow — best-effort */}
  }

  /// Reads the last-known geo fix from prefs.
  /// Returns null when location was never granted or coords are stale (not
  /// stored yet). Callers that want a *fresh* fix should call [refreshNow].
  static Future<({double lat, double lng, String address})?> lastFix() async {
    final prefs = await SharedPreferences.getInstance();
    final lat = prefs.getDouble(_kLatKey);
    final lng = prefs.getDouble(_kLngKey);
    if (lat == null || lng == null) return null;
    return (
      lat: lat,
      lng: lng,
      address: prefs.getString(_kAddrKey) ?? '',
    );
  }

  /// Requests location permission + grabs a fresh GPS fix on demand. Used by
  /// the checkout "Detect my address" button when the user wants to skip
  /// typing.
  static Future<({double lat, double lng, String address})?> refreshNow() async {
    try {
      var lp = await Geolocator.checkPermission();
      if (lp == LocationPermission.denied) {
        lp = await Geolocator.requestPermission();
      }
      if (lp != LocationPermission.always && lp != LocationPermission.whileInUse) {
        return null;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      String addr = '';
      try {
        final r = await http.get(
          Uri.parse(
            'https://nominatim.openstreetmap.org/reverse?format=jsonv2'
            '&lat=${pos.latitude}&lon=${pos.longitude}'
            '&accept-language=${UellowApi.instance.lang}',
          ),
          headers: {'User-Agent': 'UellowApp/2.0 (support@uellow.com)'},
        ).timeout(const Duration(seconds: 6));
        if (r.statusCode == 200) {
          final j = jsonDecode(r.body) as Map<String, dynamic>;
          addr = (j['display_name'] as String?) ?? '';
        }
      } catch (_) {}
      // Persist for next time
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_kLatKey, pos.latitude);
      await prefs.setDouble(_kLngKey, pos.longitude);
      await prefs.setInt(_kTsKey, DateTime.now().millisecondsSinceEpoch);
      if (addr.isNotEmpty) await prefs.setString(_kAddrKey, addr);
      return (lat: pos.latitude, lng: pos.longitude, address: addr);
    } catch (_) {
      return null;
    }
  }

  /// v2.2.16 — staleness-aware fix. The first-launch fix used to live
  /// FOREVER, so a user who travelled kept seeing their old location in
  /// the "Deliver to" block even after restarting the app. Returns the
  /// cached fix while it is younger than [maxAge]; otherwise silently
  /// re-detects — but ONLY when permission is already granted (never
  /// prompts) — and updates the cache. Falls back to the stale cache if
  /// GPS fails.
  static Future<({double lat, double lng, String address})?> freshFix(
      {Duration maxAge = const Duration(minutes: 10)}) async {
    final prefs = await SharedPreferences.getInstance();
    final ts = prefs.getInt(_kTsKey) ?? 0;
    final cached = await lastFix();
    if (cached != null &&
        DateTime.now().millisecondsSinceEpoch - ts < maxAge.inMilliseconds) {
      return cached;
    }
    try {
      final lp = await Geolocator.checkPermission();
      if (lp != LocationPermission.always &&
          lp != LocationPermission.whileInUse) {
        return cached;
      }
    } catch (_) {
      return cached;
    }
    return await refreshNow() ?? cached;
  }
}
