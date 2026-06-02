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

  Future<void> _persistAndGoHome() async {
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
    if (!mounted) return;
    // Visible confirmation so the user knows the URL switch happened.
    final cname = (_picked?['country']?['name']?['en'] as String?) ?? code ?? '';
    final domain = (apiBase ?? '')
        .replaceFirst(RegExp(r'^https?://'), '').split('/').first;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 2),
        content: Text(_lang == 'ar'
            ? 'تم التحويل إلى $cname · $domain'
            : 'Switched to $cname · $domain')));
    Navigator.of(context).pushReplacementNamed(Routes.home);
  }

  @override
  Widget build(BuildContext context) {
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
                if (_detected != null) ...[
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
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: Text('COUNTRY',
                style: TextStyle(fontSize: 11, color: UellowColors.muted,
                    fontWeight: FontWeight.w800, letterSpacing: 0.8)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: _countryDropdown(),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 6, 14, 6),
            child: Text('LANGUAGE',
                style: TextStyle(fontSize: 11, color: UellowColors.muted,
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
    final name = country?['name']?['en'] as String? ?? 'Kuwait';
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
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Align(alignment: Alignment.centerLeft,
                  child: Text('Select your country',
                      style: TextStyle(color: UellowColors.darkBrown,
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
                  final name = cn?['name']?['en'] as String? ?? '—';
                  final cur = c['currency'] as String? ?? '';
                  return ListTile(
                    leading: Text(flag, style: const TextStyle(fontSize: 22)),
                    title: Text(name,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(cn?['name']?['ar'] as String? ?? '',
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
          const Padding(padding: EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Align(alignment: Alignment.centerLeft,
              child: Text('Select your language',
                style: TextStyle(color: UellowColors.darkBrown,
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
                onTap: () { setState(() => _lang = shortCode); Navigator.pop(context); },
              );
            },
          )),
          const SizedBox(height: 16),
        ]),
      ),
    );
  }

  Widget _detectedHint() {
    final country = _detected?['recommended']?['country'] as Map<String, dynamic>?;
    final domain  = _detected?['recommended']?['website']?['domain'] as String? ?? 'The App';
    final name    = country?['name']?['en'] as String? ?? 'your region';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.7),
        border: Border.all(color: const Color(0x4DF5C320)),
        borderRadius: const BorderRadius.all(Radius.circular(14)),
      ),
      child: Row(
        children: [
          const Text('📍', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 12, color: UellowColors.darkBrown),
                children: [
                  const TextSpan(text: 'Detected: '),
                  TextSpan(text: name,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  const TextSpan(text: ' · Connecting to '),
                  TextSpan(text: domain,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
