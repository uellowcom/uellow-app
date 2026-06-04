// =============================================================================
// AdsService (v2.1.27) — in-app advertising client.
//   • splash: full-screen flash ad on open, auto-dismisses after N seconds.
//   • popup : dialog ad after open with frequency capping (always/day/once).
//   • infeed: ad tiles injected between products (fetched per category).
// Backend: Mobile App Manager → 📢 الإعلانات.
// =============================================================================
import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/uellow_api.dart';
import '../theme/uellow_theme.dart';

class AdsService {
  AdsService._();
  static bool _openAdsShownThisSession = false;

  static Future<List<Map<String, dynamic>>> fetch(String type,
      {int? categoryId}) async {
    try {
      final q = categoryId != null ? '&category_id=$categoryId' : '';
      final r = await http.get(
        Uri.parse('${UellowApi.instance.baseUrl}'
            '/api/mobile/v2/ads?type=$type$q'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 8));
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (j['success'] == true) {
        return ((j['data'] as List?) ?? const [])
            .cast<Map>().map((m) => m.cast<String, dynamic>()).toList();
      }
    } catch (_) {}
    return const [];
  }

  static void reportEvent(int id, String event) {
    http.post(
      Uri.parse('${UellowApi.instance.baseUrl}'
          '/api/mobile/v2/ads/$id/event'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'event': event}),
    ).catchError((_) => http.Response('', 599));
  }

  static void openTarget(BuildContext context, Map<String, dynamic> ad) {
    reportEvent((ad['id'] as int?) ?? 0, 'click');
    switch (ad['link_type']) {
      case 'product':
        final id = ad['target_product_id'] as int?;
        if (id != null) {
          Navigator.pushNamed(context, '/product', arguments: {'id': id});
        }
        break;
      case 'category':
        final id = ad['target_category_id'] as int?;
        if (id != null) {
          Navigator.pushNamed(context, '/collection',
              arguments: {'category_id': id});
        }
        break;
      case 'url':
        final u = (ad['target_url'] ?? '').toString();
        if (u.isNotEmpty) {
          launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication);
        }
        break;
    }
  }

  /// Run the open sequence ONCE per app session: splash ad first
  /// (auto-dismiss), then the popup (frequency-capped).
  static Future<void> showOpenAds(BuildContext context) async {
    if (_openAdsShownThisSession) return;
    _openAdsShownThisSession = true;
    final splash = await fetch('splash');
    if (splash.isNotEmpty && context.mounted) {
      await _showSplash(context, splash.first);
    }
    final popups = await fetch('popup');
    for (final ad in popups) {
      if (!context.mounted) return;
      if (await _popupAllowed(ad)) {
        final delay = (ad['popup_delay'] as num?)?.toInt() ?? 1;
        await Future.delayed(Duration(seconds: delay.clamp(0, 10)));
        if (!context.mounted) return;
        await _showPopup(context, ad);
        await _markPopupSeen(ad);
        break;                       // one popup per open
      }
    }
  }

  // ── frequency capping ───────────────────────────────────────────
  static Future<bool> _popupAllowed(Map<String, dynamic> ad) async {
    final freq = (ad['popup_frequency'] ?? 'day').toString();
    if (freq == 'always') return true;
    final prefs = await SharedPreferences.getInstance();
    final key = 'uellow_ad_seen_${ad['id']}';
    final seen = prefs.getString(key);
    if (freq == 'once') return seen == null;
    // day
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return seen != today;
  }

  static Future<void> _markPopupSeen(Map<String, dynamic> ad) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('uellow_ad_seen_${ad['id']}',
        DateTime.now().toIso8601String().substring(0, 10));
  }

  // ── splash (flash) ──────────────────────────────────────────────
  static Future<void> _showSplash(
      BuildContext context, Map<String, dynamic> ad) async {
    reportEvent((ad['id'] as int?) ?? 0, 'view');
    await showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, __, ___) => _SplashAd(ad: ad),
    );
  }

  // ── popup ───────────────────────────────────────────────────────
  static Future<void> _showPopup(
      BuildContext context, Map<String, dynamic> ad) async {
    reportEvent((ad['id'] as int?) ?? 0, 'view');
    final ar = UellowApi.instance.lang.toLowerCase().startsWith('ar');
    await showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder: (dctx) {
        final title = ((ad['title'] as Map?)?[ar ? 'ar' : 'en'] ?? '')
            .toString();
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 26),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: InkWell(
                onTap: () => Navigator.pop(dctx),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.92),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close,
                      size: 18, color: UellowColors.darkBrown),
                ),
              ),
            ),
            GestureDetector(
              onTap: () {
                Navigator.pop(dctx);
                openTarget(context, ad);
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: CachedNetworkImage(
                  imageUrl: (ad['image'] ?? '').toString(),
                  fit: BoxFit.contain,
                  placeholder: (_, __) => const SizedBox(
                      height: 200,
                      child: Center(child: CircularProgressIndicator(
                          color: UellowColors.yellow))),
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
            if (title.isNotEmpty) Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(title, textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white,
                      fontSize: 14, fontWeight: FontWeight.w800)),
            ),
          ]),
        );
      },
    );
  }
}

/// Full-screen flash ad with countdown auto-dismiss.
class _SplashAd extends StatefulWidget {
  const _SplashAd({required this.ad});
  final Map<String, dynamic> ad;
  @override
  State<_SplashAd> createState() => _SplashAdState();
}

class _SplashAdState extends State<_SplashAd> {
  late int _left;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _left = ((widget.ad['splash_seconds'] as num?)?.toInt() ?? 4).clamp(1, 30);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _left--);
      if (_left <= 0) {
        _timer?.cancel();
        if (mounted) Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final ad = widget.ad;
    final ar = UellowApi.instance.lang.toLowerCase().startsWith('ar');
    final skippable = ad['splash_skippable'] != false;
    return Material(
      color: Colors.black,
      child: SafeArea(child: Stack(children: [
        Positioned.fill(child: GestureDetector(
          onTap: () {
            _timer?.cancel();
            Navigator.of(context).pop();
            AdsService.openTarget(context, ad);
          },
          child: CachedNetworkImage(
            imageUrl: (ad['image'] ?? '').toString(),
            fit: BoxFit.contain,
            placeholder: (_, __) => const Center(
                child: CircularProgressIndicator(color: UellowColors.yellow)),
            errorWidget: (_, __, ___) => const SizedBox.shrink(),
          ),
        )),
        // countdown chip
        PositionedDirectional(top: 12, start: 12, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white24),
          ),
          child: Text('$_left',
              style: const TextStyle(color: Colors.white,
                  fontWeight: FontWeight.w900, fontSize: 13)),
        )),
        if (skippable) PositionedDirectional(top: 12, end: 12, child: InkWell(
          onTap: () { _timer?.cancel(); Navigator.of(context).pop(); },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(ar ? 'تخطي ›' : 'Skip ›',
                style: const TextStyle(color: UellowColors.darkBrown,
                    fontWeight: FontWeight.w900, fontSize: 12)),
          ),
        )),
      ])),
    );
  }
}

/// In-feed ad tile for product grids.
class AdTile extends StatefulWidget {
  const AdTile({super.key, required this.ad});
  final Map<String, dynamic> ad;
  @override
  State<AdTile> createState() => _AdTileState();
}

class _AdTileState extends State<AdTile> {
  static final Set<int> _viewed = {};

  @override
  void initState() {
    super.initState();
    final id = (widget.ad['id'] as int?) ?? 0;
    if (id != 0 && !_viewed.contains(id)) {
      _viewed.add(id);
      AdsService.reportEvent(id, 'view');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang.toLowerCase().startsWith('ar');
    final title = ((widget.ad['title'] as Map?)?[ar ? 'ar' : 'en'] ?? '')
        .toString();
    return GestureDetector(
      onTap: () => AdsService.openTarget(context, widget.ad),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: UellowRadius.all_lg,
          boxShadow: [BoxShadow(color: Color(0x0A000000),
              blurRadius: 8, offset: Offset(0, 2))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(fit: StackFit.expand, children: [
          CachedNetworkImage(
            imageUrl: (widget.ad['image'] ?? '').toString(),
            fit: BoxFit.cover,
            placeholder: (_, __) =>
                const ColoredBox(color: UellowColors.border),
            errorWidget: (_, __, ___) =>
                const ColoredBox(color: UellowColors.border),
          ),
          PositionedDirectional(top: 6, start: 6, child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(ar ? 'إعلان' : 'AD',
                style: const TextStyle(color: Colors.white, fontSize: 8.5,
                    fontWeight: FontWeight.w900, letterSpacing: 0.5)),
          )),
          if (title.isNotEmpty) Positioned(
            left: 0, right: 0, bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
              decoration: const BoxDecoration(gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0xCC000000)],
              )),
              child: Text(title, maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white,
                      fontSize: 11.5, fontWeight: FontWeight.w800)),
            ),
          ),
        ]),
      ),
    );
  }
}
