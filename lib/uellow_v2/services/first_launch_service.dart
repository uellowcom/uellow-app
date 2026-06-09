// =============================================================================
// FirstLaunchService — runs once after the country picker on a fresh install.
// Requests Location + Notification permissions, then (if location granted)
// fetches a coarse GPS fix and reverse-geocodes it via Nominatim. The result
// is stashed in SharedPreferences so checkout's "Detect my address" button
// can fill the form without a second round-trip.
//
// v2.2.36 — PERMANENT address-capture fix: we now persist the STRUCTURED
// address pieces (country / city / state) parsed from Nominatim's `address`
// object, instead of only the flat `display_name`. Callers used to split
// display_name by commas and guess the city/country by POSITION, which is
// locale-dependent and routinely picked the wrong piece — the long-standing
// "wrong address from current location" bug. Now city/country come straight
// from the structured fields.
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

typedef GeoFix = ({
  double lat,
  double lng,
  String address,
  String city,
  String country,
});

class FirstLaunchService {
  FirstLaunchService._();

  static const _kRanKey = 'uellow_first_launch_perms_v1';
  static const _kLatKey = 'uellow_geo_lat_v1';
  static const _kLngKey = 'uellow_geo_lng_v1';
  static const _kAddrKey = 'uellow_geo_addr_v1';
  static const _kCityKey = 'uellow_geo_city_v1';
  static const _kCountryKey = 'uellow_geo_country_v1';
  static const _kTsKey = 'uellow_geo_ts_v1';

  /// Parse Nominatim's structured `address` object into the pieces we care
  /// about. City falls back through the OSM hierarchy (town/village/…), so
  /// rural and urban fixes both resolve to a sensible "city".
  static ({String display, String city, String country}) _parse(
      Map<String, dynamic> j) {
    final display = (j['display_name'] as String?) ?? '';
    final a = (j['address'] as Map?)?.cast<String, dynamic>() ?? const {};
    String pick(List<String> keys) {
      for (final k in keys) {
        final v = a[k];
        if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
      }
      return '';
    }
    final city = pick(
        ['city', 'town', 'village', 'municipality', 'suburb', 'state_district', 'county']);
    final country = pick(['country']);
    return (display: display, city: city, country: country);
  }

  /// Reverse-geocode a coordinate via Nominatim. Returns null on failure.
  static Future<({String display, String city, String country})?> _reverse(
      double lat, double lng) async {
    try {
      final r = await http.get(
        Uri.parse(
          'https://nominatim.openstreetmap.org/reverse?format=jsonv2'
          '&addressdetails=1'
          '&lat=$lat&lon=$lng'
          '&accept-language=${UellowApi.instance.lang}',
        ),
        headers: {'User-Agent': 'UellowApp/2.0 (support@uellow.com)'},
      ).timeout(const Duration(seconds: 6));
      if (r.statusCode == 200) {
        return _parse(jsonDecode(r.body) as Map<String, dynamic>);
      }
    } catch (_) {}
    return null;
  }

  static Future<void> _store(SharedPreferences prefs, double lat, double lng,
      ({String display, String city, String country})? geo) async {
    await prefs.setDouble(_kLatKey, lat);
    await prefs.setDouble(_kLngKey, lng);
    await prefs.setInt(_kTsKey, DateTime.now().millisecondsSinceEpoch);
    if (geo != null) {
      if (geo.display.isNotEmpty) await prefs.setString(_kAddrKey, geo.display);
      await prefs.setString(_kCityKey, geo.city);
      await prefs.setString(_kCountryKey, geo.country);
    }
  }

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
      final geo = await _reverse(pos.latitude, pos.longitude);
      await _store(prefs, pos.latitude, pos.longitude, geo);
    } catch (_) {/* swallow — best-effort */}
  }

  /// Reads the last-known geo fix from prefs.
  static Future<GeoFix?> lastFix() async {
    final prefs = await SharedPreferences.getInstance();
    final lat = prefs.getDouble(_kLatKey);
    final lng = prefs.getDouble(_kLngKey);
    if (lat == null || lng == null) return null;
    return (
      lat: lat,
      lng: lng,
      address: prefs.getString(_kAddrKey) ?? '',
      city: prefs.getString(_kCityKey) ?? '',
      country: prefs.getString(_kCountryKey) ?? '',
    );
  }

  /// Requests location permission + grabs a fresh GPS fix on demand. Used by
  /// the checkout "Detect my address" button when the user wants to skip
  /// typing.
  static Future<GeoFix?> refreshNow() async {
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
      final geo = await _reverse(pos.latitude, pos.longitude);
      final prefs = await SharedPreferences.getInstance();
      await _store(prefs, pos.latitude, pos.longitude, geo);
      return (
        lat: pos.latitude,
        lng: pos.longitude,
        address: geo?.display ?? '',
        city: geo?.city ?? '',
        country: geo?.country ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  /// v2.2.16 — staleness-aware fix. Returns the cached fix while it is younger
  /// than [maxAge]; otherwise silently re-detects — but ONLY when permission
  /// is already granted (never prompts) — and updates the cache. Falls back to
  /// the stale cache if GPS fails.
  static Future<GeoFix?> freshFix(
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
