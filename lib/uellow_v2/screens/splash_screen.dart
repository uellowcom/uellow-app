// =============================================================================
// SplashScreen — first screen on app launch.
//
// Flow:
//   1. Call /app/geo to detect country from IP + see if user already
//      picked one (server tells us via mobile.session).
//   2. If auto-detected and user hasn't manually overridden, navigate to
//      Home directly with the detected country/website pre-applied.
//   3. Otherwise show the picker dropdown (matching the mockup) and let
//      them choose. Their pick goes to /app/set-country and persists.
//
// UX: matches the mockup splash exactly — Uellow logo top, country
// dropdown, language tabs, "Detected" hint, Continue CTA bottom.
// =============================================================================
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../api/uellow_api.dart';
import '../../api/uellow_endpoints.dart';
import '../router/uellow_router.dart';
import '../services/first_launch_service.dart';
import '../theme/uellow_l10n.dart';
import '../theme/uellow_theme.dart';
import '../widgets/uellow_logo.dart';

const _kCountryPickedKey = 'uellow_country_picked_v1';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _loading = true;
  Map<String, dynamic>? _detected;
  List<Map<String, dynamic>> _countries = [];
  List<Map<String, dynamic>> _allLangs = const [];   // fetched from /app/languages
  Map<String, dynamic>? _picked;
  String _lang = 'ar';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // First-install gate: if the user has already chosen a country before,
    // skip the picker and go straight home. They can still change country
    // from Account → Settings.
    try {
      final prefs = await SharedPreferences.getInstance();
      final alreadyPicked = prefs.getBool(_kCountryPickedKey) ?? false;
      if (alreadyPicked) {
        // Resolve persisted language too, if any
        final savedLang = prefs.getString('uellow_lang_v1');
        if (savedLang != null && savedLang.isNotEmpty) {
          UellowApi.instance.setLang(savedLang);
        }
        if (mounted) {
          Navigator.of(context).pushReplacementNamed(Routes.home);
        }
        return;
      }
    } catch (_) {/* fall through to picker */}

    try {
      // Three parallel calls: geo + the full country list + every
      // language res.lang exposes so the picker isn't forced to AR/EN.
      final results = await Future.wait([
        _request('GET', EP.appGeo()),
        _request('GET', EP.appCountriesList()),
        _request('GET', '/api/mobile/v2/app/languages'),
      ]);
      final geo = results[0]['data'] as Map<String, dynamic>;
      final list = (results[1]['data'] as List).cast<Map<String, dynamic>>();
      final langs = (results[2]['data'] as List).cast<Map<String, dynamic>>();
      _detected = geo;
      _countries = list;
      _allLangs = langs;
      _picked = geo['recommended'] as Map<String, dynamic>?;
      // Pre-select language from picked country's default or phone locale
      final fromCountry = (_picked?['default_language'] as String?)?.toLowerCase();
      _lang = (fromCountry?.startsWith('ar') ?? true) ? 'ar' : 'en';
    } catch (_) {
      // network down or backend not reachable; still let user pick manually
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Minimal direct GET — splash runs before tokens exist, so we keep
  /// it standalone instead of going through the typed client.
  Future<Map<String, dynamic>> _request(String method, String path) async {
    final uri = Uri.parse('${UellowApi.instance.baseUrl}$path');
    final resp = await http.get(uri, headers: {
      'Accept': 'application/json',
      'X-Lang': UellowApi.instance.lang,
    });
    final body = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    if (body['success'] != true) throw Exception(body['error'] ?? 'request failed');
    return body;
  }

  // v2.1.69 — professional full-screen progress from the moment Continue
  // is tapped until the app is truly ready (home page prefetched into the
  // snapshot cache, so HomeScreen renders instantly with zero flash).
  bool _going = false;

  Future<void> _prefetchHome() async {
    try {
      final api = UellowApi.instance;
      final r = await http.get(
        Uri.parse('${api.baseUrl}/api/mobile/v2/pages/home'),
        headers: {'Accept': 'application/json', 'X-Lang': api.lang},
      ).timeout(const Duration(seconds: 10));
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (j['success'] == true) {
        final d = (j['data'] as Map).cast<String, dynamic>();
        if ((d['blocks'] as List? ?? const []).isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
              'home_page_cache_v1_${api.lang}', jsonEncode(d));
        }
      }
    } catch (_) {/* home falls back to its own loading */}
  }

  Future<void> _persistAndGoHome() async {
    if (_going) return;
    setState(() => _going = true);
    final code = _picked?['country']?['code'] as String?;
    // Switch the API base URL to the website of the picked country so
    // every subsequent request hits the right backend. We do this BEFORE
    // the set-country POST so the POST also lands on the right domain.
    final website = _picked?['website'] as Map?;
    final apiBase = website?['api_base'] as String?
        ?? website?['domain'] as String?;
    if (apiBase != null && apiBase.isNotEmpty) {
      await UellowApi.instance.setBaseUrl(apiBase);
    }
    // v2.1.16 — remember the website id so every request is scoped to it
    // (per-website settings, builder pages, payment methods…).
    final wid = website?['id'] as int?;
    if (wid != null && wid > 0) {
      await UellowApi.instance.tokenStore.writeWebsiteId(wid);
    }
    if (code != null) {
      try {
        final uri = Uri.parse(
            '${UellowApi.instance.baseUrl}${EP.appSetCountry()}');
        await http.post(uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'country': code, 'lang': _lang}));
      } catch (_) {/* non-blocking */}
    }
    UellowApi.instance.setLang(_lang == 'ar' ? 'ar_001' : 'en_US');
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kCountryPickedKey, true);
      await prefs.setString('uellow_lang_v1', _lang == 'ar' ? 'ar_001' : 'en_US');
      if (code != null) {
        await prefs.setString('uellow_country_code_v1', code);
      }
    } catch (_) {/* ignore */}
    // v2.0.72 (#416) — fire-and-forget first-launch permission prompts +
    // GPS pre-warm. Runs in the background so the home transition stays
    // snappy; idempotent across cold starts.
    unawaited(FirstLaunchService.kickOff());
    // Pre-warm the home page while the progress screen shows — the app
    // then opens straight onto a fully-rendered home.
    await _prefetchHome();
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(Routes.home);
  }

  /// Branded full-screen progress shown between Continue and home.
  Widget _goingGate() {
    final ar = _lang == 'ar';
    final cname = ((_picked?['country']?['name']
            as Map?)?[ar ? 'ar' : 'en'] ?? '').toString();
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Color(0xFFFFF8E1), Colors.white],
        ),
      ),
      alignment: Alignment.center,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const UellowLogo(height: 52),
        const SizedBox(height: 34),
        SizedBox(
          width: 58, height: 58,
          child: Stack(alignment: Alignment.center, children: const [
            SizedBox(width: 58, height: 58,
                child: CircularProgressIndicator(
                    strokeWidth: 3.5, color: UellowColors.yellow)),
            Text('🛍', style: TextStyle(fontSize: 24)),
          ]),
        ),
        const SizedBox(height: 26),
        Text(ar ? 'جارٍ تجهيز تجربتك…' : 'Preparing your experience…',
            style: const TextStyle(fontSize: 16.5,
                fontWeight: FontWeight.w900, color: UellowColors.darkBrown)),
        const SizedBox(height: 6),
        Text(
            cname.isNotEmpty
                ? (ar ? 'متجر $cname · أحدث العروض والمنتجات'
                      : '$cname store · latest deals and products')
                : (ar ? 'أحدث العروض والمنتجات' : 'Latest deals and products'),
            style: const TextStyle(fontSize: 12.5,
                color: UellowColors.muted)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    // v2.1.69 — once Continue is tapped the whole screen becomes the
    // branded progress gate until home is prefetched and opened.
    if (_going) {
      return Scaffold(body: SizedBox.expand(child: _goingGate()));
    }
    return Scaffold(
      // Use SizedBox.expand + a gradient that paints the full viewport
      // (including under the status bar) so the picker truly fills the
      // screen instead of a narrow card.
      body: SizedBox.expand(child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFFFFD340), UellowColors.yellow, Color(0xFFC99000)],
          ),
        ),
        child: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: UellowColors.darkBrown))
              : _buildContent(),
        ),
      )),
    );
  }

  Widget _buildContent() {
    return LayoutBuilder(builder: (context, box) {
      return SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 30, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 30),
                _logo(),
                const SizedBox(height: 24),
                Text(T.t('splash.tagline'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, color: Color(0xFF5B3C00))),
                const SizedBox(height: 6),
                Text(T.t('splash.title'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, color: UellowColors.darkBrown,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 24),
                _pickerCard(),
                if (_picked != null || _detected != null) ...[
                  const SizedBox(height: 14),
                  _detectedHint(),
                ],
                const Spacer(),
                const SizedBox(height: 20),
                SizedBox(width: double.infinity, child: ElevatedButton(
                  onPressed: _persistAndGoHome,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: UellowColors.darkBrown,
                    foregroundColor: UellowColors.yellowLight,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 8,
                    shadowColor: const Color(0x80412402),
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(16))),
                  ),
                  child: Text(T.t('action.continue'),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                )),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
      );
    });
  }

  Widget _logo() {
    return const Center(child: UellowLogo(height: 56));
  }

  Widget _pickerCard() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.all(Radius.circular(20)),
        boxShadow: [BoxShadow(color: const Color(0x40412402),
            blurRadius: 40, offset: const Offset(0, 16))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: Text(_lang == 'ar' ? 'الدولة' : 'COUNTRY',
                style: const TextStyle(fontSize: 11, color: UellowColors.muted,
                    fontWeight: FontWeight.w800, letterSpacing: 0.8)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: _countryDropdown(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
            child: Text(_lang == 'ar' ? 'اللغة' : 'LANGUAGE',
                style: const TextStyle(fontSize: 11, color: UellowColors.muted,
                    fontWeight: FontWeight.w800, letterSpacing: 0.8)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: _langTabs(),
          ),
        ],
      ),
    );
  }

  Widget _countryDropdown() {
    final country = _picked?['country'] as Map<String, dynamic>?;
    final flag = country?['flag'] as String? ?? '🌐';
    // v2.1.60 — localized country name (was English-only).
    final name = (country?['name']?[_lang == 'ar' ? 'ar' : 'en']
        ?? country?['name']?['en'] ?? 'Kuwait').toString();
    final cur  = (_picked?['currency'] as String?) ?? 'KWD';
    return InkWell(
      onTap: _showCountrySheet,
      borderRadius: const BorderRadius.all(Radius.circular(12)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: UellowColors.yellowFaint,
          border: Border.all(color: UellowColors.border, width: 1.5),
          borderRadius: const BorderRadius.all(Radius.circular(12)),
        ),
        child: Row(
          children: [
            Text(flag, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 12),
            Expanded(
              child: Row(
                children: [
                  Text(name,
                      style: const TextStyle(color: UellowColors.darkBrown,
                          fontWeight: FontWeight.w800, fontSize: 15)),
                  const SizedBox(width: 6),
                  Text('· $cur',
                      style: const TextStyle(color: UellowColors.muted,
                          fontWeight: FontWeight.w500, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.keyboard_arrow_down, color: UellowColors.muted),
          ],
        ),
      ),
    );
  }

  void _showCountrySheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        constraints: const BoxConstraints(maxHeight: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(color: UellowColors.border,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Align(alignment: Alignment.centerLeft,
                  child: Text(_lang == 'ar' ? 'اختر دولتك' : 'Select your country',
                      style: const TextStyle(color: UellowColors.darkBrown,
                          fontWeight: FontWeight.w800, fontSize: 16))),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _countries.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final c = _countries[i];
                  final cn = c['country'] as Map<String, dynamic>?;
                  final flag = cn?['flag'] as String? ?? '🌐';
                  // v2.1.60 — primary name in the picked language.
                  final name = (cn?['name']?[_lang == 'ar' ? 'ar' : 'en']
                      ?? cn?['name']?['en'] ?? '—').toString();
                  final other = (cn?['name']?[_lang == 'ar' ? 'en' : 'ar']
                      ?? '').toString();
                  final cur = c['currency'] as String? ?? '';
                  return ListTile(
                    leading: Text(flag, style: const TextStyle(fontSize: 22)),
                    title: Text(name,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(other,
                        style: const TextStyle(fontSize: 11)),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: const BoxDecoration(
                        color: UellowColors.yellow,
                        borderRadius: BorderRadius.all(Radius.circular(999)),
                      ),
                      child: Text(cur,
                          style: const TextStyle(color: UellowColors.darkBrown,
                              fontWeight: FontWeight.w800, fontSize: 11)),
                    ),
                    onTap: () { setState(() => _picked = c); Navigator.pop(context); },
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// Tap-to-open language picker — shows every res.lang the server
  /// exposes (not just AR/EN), with the active one highlighted.
  Widget _langTabs() {
    final current = _allLangs.firstWhere(
      (l) => (l['code'] as String? ?? '').toLowerCase().startsWith(_lang),
      orElse: () => const {'name': 'العربية', 'flag': '🇰🇼', 'code': 'ar_001'});
    return InkWell(
      onTap: _showLangSheet,
      borderRadius: const BorderRadius.all(Radius.circular(12)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: UellowColors.yellowFaint,
          border: Border.all(color: UellowColors.border, width: 1.5),
          borderRadius: const BorderRadius.all(Radius.circular(12)),
        ),
        child: Row(children: [
          Text(((current['code'] as String? ?? '').startsWith('ar'))
              ? '🇰🇼'
              : (current['flag'] as String? ?? '🌐'),
              style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(child: Text(
              (current['name'] as String?) ?? _lang.toUpperCase(),
              style: const TextStyle(color: UellowColors.darkBrown,
                  fontWeight: FontWeight.w800, fontSize: 15))),
          const Icon(Icons.keyboard_arrow_down, color: UellowColors.muted),
        ]),
      ),
    );
  }

  void _showLangSheet() {
    final items = _allLangs.isNotEmpty ? _allLangs : const [
      {'code': 'ar_001', 'name': 'العربية', 'flag': '🇰🇼'},
      {'code': 'en_US',  'name': 'English', 'flag': '🇺🇸'},
    ];
    showModalBottomSheet(
      context: context, backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        constraints: const BoxConstraints(maxHeight: 480),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(padding: const EdgeInsets.symmetric(vertical: 8),
            child: Container(width: 36, height: 4,
              decoration: BoxDecoration(color: UellowColors.border,
                  borderRadius: BorderRadius.circular(2)))),
          Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Align(alignment: Alignment.centerLeft,
              child: Text(_lang == 'ar' ? 'اختر لغتك' : 'Select your language',
                style: const TextStyle(color: UellowColors.darkBrown,
                    fontWeight: FontWeight.w800, fontSize: 16)))),
          Flexible(child: ListView.separated(
            shrinkWrap: true,
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final l = items[i];
              final code = (l['code'] as String? ?? '').toLowerCase();
              final isAr = code.startsWith('ar');
              final isEn = code.startsWith('en');
              final shortCode = isAr ? 'ar' : (isEn ? 'en'
                  : (code.split('_').first));
              final on = shortCode == _lang;
              return ListTile(
                leading: Text(isAr ? '🇰🇼' : ((l['flag'] as String?) ?? '🌐'),
                    style: const TextStyle(fontSize: 22)),
                title: Text((l['name'] as String?) ?? code,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(code, style: const TextStyle(
                    fontSize: 11, color: UellowColors.muted)),
                trailing: on
                    ? const Icon(Icons.check_circle,
                        color: UellowColors.success, size: 22)
                    : null,
                onTap: () {
                  // v2.1.60 — flipping the language re-renders the whole
                  // picker in that language instantly (T.t + labels).
                  setState(() => _lang = shortCode);
                  UellowApi.instance.setLang(
                      shortCode == 'ar' ? 'ar_001' : 'en_US');
                  Navigator.pop(context);
                },
              );
            },
          )),
          const SizedBox(height: 16),
        ]),
      ),
    );
  }

  Widget _detectedHint() {
    // v2.1.60 — the label now follows the PICKED country (updates the
    // moment you choose one), localized, and reads «تطبيق الكويت» /
    // "Kuwait App" instead of the technical "Connecting to <domain>".
    final src = _picked ?? _detected?['recommended'] as Map<String, dynamic>?;
    final country = src?['country'] as Map<String, dynamic>?;
    final name = (country?['name']?[_lang == 'ar' ? 'ar' : 'en']
        ?? country?['name']?['en'] ?? '').toString();
    final flag = country?['flag'] as String? ?? '📍';
    final label = _lang == 'ar' ? 'تطبيق $name' : '$name App';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.7),
        border: Border.all(color: const Color(0x4DF5C320)),
        borderRadius: const BorderRadius.all(Radius.circular(14)),
      ),
      child: Row(
        children: [
          Text(flag, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            // v2.1.68 — domain line removed (no technical URLs on the
            // entry screen per ali@uellow).
            Text(label, style: const TextStyle(fontSize: 13.5,
                fontWeight: FontWeight.w900,
                color: UellowColors.darkBrown)),
          ])),
          const Icon(Icons.check_circle, size: 18,
              color: UellowColors.success),
        ],
      ),
    );
  }
}
