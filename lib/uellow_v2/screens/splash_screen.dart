// =============================================================================
// SplashScreen — first screen on app launch (country + language onboarding).
//
// v2.2.72 — redesigned to the "Locator Hero" concept:
//   • Uellow logo + عربي/EN segmented toggle on top.
//   • Middle-East / Global segmented tabs.
//   • A gold "detected location" hero card (geometric pattern + mini map +
//     fast-delivery / installments / payment methods) with Confirm + Change.
//   • Scrollable country list (tap a country → the hero card becomes that
//     country, exactly like the detected one). Currencies show in Arabic
//     names in AR mode (دينار كويتي…) and the code in EN.
//
// The data flow is unchanged: /app/geo (detected) + /app/countries (list) +
// /app/languages, then _persistAndGoHome() switches the API base URL, writes
// the website id, POSTs set-country, persists lang, and opens Home.
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
import '../theme/uellow_theme.dart';
import '../widgets/uellow_logo.dart';

const _kCountryPickedKey = 'uellow_country_picked_v1';

// Global (non-Middle-East) stores live under the "عالمي" tab.
const Set<String> _kGlobalCodes = {'CN', 'US'};

// Arabic currency names (shown in AR mode instead of the ISO code).
const Map<String, String> _kCurAr = {
  'KWD': 'دينار كويتي', 'SAR': 'ريال سعودي', 'AED': 'درهم إماراتي',
  'QAR': 'ريال قطري', 'BHD': 'دينار بحريني', 'OMR': 'ريال عُماني',
  'JOD': 'دينار أردني', 'EGP': 'جنيه مصري', 'IQD': 'دينار عراقي',
  'LBP': 'ليرة لبنانية', 'ILS': 'شيكل', 'YER': 'ريال يمني',
  'TRY': 'ليرة تركية', 'USD': 'دولار أمريكي', 'CNY': 'يوان صيني',
};

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _loading = true;
  Map<String, dynamic>? _detected;
  List<Map<String, dynamic>> _countries = [];
  Map<String, dynamic>? _picked;
  String _lang = 'ar';
  String _tab = 'me'; // 'me' | 'global'

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // First-install gate: if the user has already chosen a country before,
    // skip the picker and go straight home.
    try {
      final prefs = await SharedPreferences.getInstance();
      final alreadyPicked = prefs.getBool(_kCountryPickedKey) ?? false;
      if (alreadyPicked) {
        final savedLang = prefs.getString('uellow_lang_v1');
        if (savedLang != null && savedLang.isNotEmpty) {
          UellowApi.instance.setLang(savedLang);
        }
        if (mounted) Navigator.of(context).pushReplacementNamed(Routes.home);
        return;
      }
    } catch (_) {/* fall through to picker */}

    try {
      final results = await Future.wait([
        _request('GET', EP.appGeo()),
        _request('GET', EP.appCountriesList()),
      ]);
      final geo = results[0]['data'] as Map<String, dynamic>;
      final list = (results[1]['data'] as List).cast<Map<String, dynamic>>();
      _detected = geo;
      _countries = list;
      _picked = geo['recommended'] as Map<String, dynamic>?;
      // If the detected country is global, open on the global tab.
      if (_isGlobal(_picked)) _tab = 'global';
      final fromCountry = (_picked?['default_language'] as String?)?.toLowerCase();
      _lang = (fromCountry?.startsWith('ar') ?? true) ? 'ar' : 'en';
    } catch (_) {/* network down — still let user pick manually */}
    finally {
      if (mounted) setState(() => _loading = false);
    }
  }

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
          await prefs.setString('home_page_cache_v1_${api.lang}', jsonEncode(d));
        }
      }
    } catch (_) {/* home falls back to its own loading */}
  }

  Future<void> _persistAndGoHome() async {
    if (_going) return;
    if (_picked == null) return;
    setState(() => _going = true);
    final code = _picked?['country']?['code'] as String?;
    final website = _picked?['website'] as Map?;
    final apiBase = website?['api_base'] as String? ?? website?['domain'] as String?;
    if (apiBase != null && apiBase.isNotEmpty) {
      await UellowApi.instance.setBaseUrl(apiBase);
    }
    final wid = website?['id'] as int?;
    if (wid != null && wid > 0) {
      await UellowApi.instance.tokenStore.writeWebsiteId(wid);
    }
    if (code != null) {
      try {
        final uri = Uri.parse('${UellowApi.instance.baseUrl}${EP.appSetCountry()}');
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
      if (code != null) await prefs.setString('uellow_country_code_v1', code);
    } catch (_) {/* ignore */}
    unawaited(FirstLaunchService.kickOff());
    await _prefetchHome();
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(Routes.home);
  }

  // ------------------------------------------------------------------ //
  // helpers
  // ------------------------------------------------------------------ //
  bool _isGlobal(Map<String, dynamic>? c) {
    final code = (c?['country']?['code'] as String?)?.toUpperCase() ?? '';
    return _kGlobalCodes.contains(code);
  }

  String _curLabel(String code) =>
      _lang == 'ar' ? (_kCurAr[code] ?? code) : code;

  /// Branded full-screen progress shown between Continue and home.
  Widget _goingGate() {
    final ar = _lang == 'ar';
    final cname =
        ((_picked?['country']?['name'] as Map?)?[ar ? 'ar' : 'en'] ?? '')
            .toString();
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
            style: const TextStyle(fontSize: 12.5, color: UellowColors.muted)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_going) return Scaffold(body: SizedBox.expand(child: _goingGate()));
    return Scaffold(
      body: SizedBox.expand(child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFFFBF6EC), Color(0xFFF3E7CE)],
          ),
        ),
        child: SafeArea(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: UellowColors.darkBrown))
              : _buildContent(),
        ),
      )),
    );
  }

  Widget _buildContent() {
    final ar = _lang == 'ar';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
          child: Row(children: [
            const UellowLogo(height: 26),
            const Spacer(),
            _langToggle(),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 2, 18, 10),
          child: _segTabs(),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _heroCard(),
                const SizedBox(height: 12),
                Text(
                    _tab == 'global'
                        ? (ar ? 'المتاجر العالمية' : 'Global stores')
                        : (ar ? 'كل دول الشرق الأوسط — اضغط لاختيار دولتك'
                              : 'All Middle East — tap to choose'),
                    style: const TextStyle(fontSize: 11.5,
                        fontWeight: FontWeight.w800, color: Color(0xFF7A5A10))),
                const SizedBox(height: 8),
                ..._countryRows(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _langToggle() {
    Widget seg(String code, String label) {
      final on = _lang == code;
      return GestureDetector(
        onTap: () {
          setState(() => _lang = code);
          UellowApi.instance.setLang(code == 'ar' ? 'ar_001' : 'en_US');
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
          decoration: BoxDecoration(
            color: on ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: on
                ? [const BoxShadow(color: Color(0x33000000),
                    blurRadius: 4, offset: Offset(0, 2))]
                : null,
          ),
          child: Text(label, style: TextStyle(fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: on ? UellowColors.darkBrown : const Color(0x99412402))),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: const Color(0x14412402),
          borderRadius: BorderRadius.circular(11)),
      child: Row(mainAxisSize: MainAxisSize.min,
          children: [seg('ar', 'عربي'), seg('en', 'EN')]),
    );
  }

  Widget _segTabs() {
    final ar = _lang == 'ar';
    Widget tab(String key, String label) {
      final on = _tab == key;
      return Expanded(child: GestureDetector(
        onTap: () => setState(() => _tab = key),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? UellowColors.darkBrown : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(label, style: TextStyle(fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: on ? UellowColors.yellow : const Color(0xAA412402))),
        ),
      ));
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: Colors.white.withOpacity(.55),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: const Color(0x22412402))),
      child: Row(children: [
        tab('me', ar ? 'الشرق الأوسط' : 'Middle East'),
        tab('global', ar ? '🌍 عالمي' : '🌍 Global'),
      ]),
    );
  }

  Widget _heroCard() {
    final ar = _lang == 'ar';
    final c = _picked;
    final country = c?['country'] as Map<String, dynamic>?;
    final flag = country?['flag'] as String? ?? '🌍';
    final name = (country?['name']?[ar ? 'ar' : 'en']
            ?? country?['name']?['en'] ?? (ar ? 'اختر دولة' : 'Choose'))
        .toString();
    final cur = (c?['currency'] as String?) ?? 'KWD';
    final global = _isGlobal(c);
    final detectedCode = _detected?['recommended']?['country']?['code'];
    final detected = c != null && detectedCode != null &&
        detectedCode == country?['code'];

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFFF7CE3F), Color(0xFFE0A800)],
        ),
        boxShadow: [BoxShadow(color: const Color(0xFFE0A800).withOpacity(.5),
            blurRadius: 26, offset: const Offset(0, 14))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(children: [
          Positioned.fill(
              child: CustomPaint(painter: _DotPatternPainter())),
          Positioned.fill(child: IgnorePointer(child: DecoratedBox(
            decoration: BoxDecoration(gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.center,
              colors: [Colors.white.withOpacity(.26), Colors.transparent])),
          ))),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                    detected
                        ? (ar ? '📍 اكتشفنا موقعك'
                              : '📍 We detected your location')
                        : (ar ? '✓ متجرك المختار' : '✓ Your selected store'),
                    style: const TextStyle(fontSize: 9.5,
                        fontWeight: FontWeight.w900, letterSpacing: .4,
                        color: Color(0xCC3A2402))),
                const SizedBox(height: 3),
                Row(children: [
                  Text(flag, style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 8),
                  Flexible(child: Text(name, style: const TextStyle(fontSize: 20,
                      fontWeight: FontWeight.w900, color: Color(0xFF3A2402)))),
                ]),
                const SizedBox(height: 2),
                Text(
                    global
                        ? (ar ? 'شحن دولي مجاني · ١٠–١٤ يوم'
                              : 'Free international shipping · 10–14 days')
                        : (ar ? 'الأسعار: ${_curLabel(cur)}'
                              : 'Currency: $cur'),
                    style: const TextStyle(fontSize: 11,
                        fontWeight: FontWeight.w700, color: Color(0xCC3A2402))),
                const SizedBox(height: 8),
                _mapStrip(),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: global
                    ? [_chip(ar ? '🌍 شحن دولي' : '🌍 Intl shipping'),
                       _chip(ar ? '⏱ ١٠–١٤ يوم' : '⏱ 10–14 days', gold: true)]
                    : [_chip(ar ? '🚚 توصيل سريع' : '🚚 Fast delivery'),
                       _chip(ar ? '💳 أقساط ٤ دفعات' : '💳 4 installments',
                           gold: true)]),
                const SizedBox(height: 7),
                Row(children: [
                  _payPill('Apple Pay'), const SizedBox(width: 4),
                  _payPill('Google Pay'), const SizedBox(width: 4),
                  _payPill('Mastercard'), const SizedBox(width: 4),
                  _payPill('Visa'),
                ]),
                const SizedBox(height: 11),
                Row(children: [
                  Expanded(child: GestureDetector(
                    onTap: _persistAndGoHome,
                    child: Container(
                      height: 42, alignment: Alignment.center,
                      decoration: BoxDecoration(color: const Color(0xFF3A2402),
                          borderRadius: BorderRadius.circular(11)),
                      child: Text(ar ? 'تأكيد ومتابعة' : 'Confirm & continue',
                          style: const TextStyle(color: UellowColors.yellow,
                              fontWeight: FontWeight.w900, fontSize: 13.5)),
                    ),
                  )),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _showCountrySheet,
                    child: Container(
                      height: 42, alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(color: const Color(0x243A2402),
                          borderRadius: BorderRadius.circular(11)),
                      child: Text(ar ? 'تغيير' : 'Change',
                          style: const TextStyle(color: Color(0xFF3A2402),
                              fontWeight: FontWeight.w800, fontSize: 12.5)),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _mapStrip() {
    return SizedBox(
      height: 30,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(alignment: Alignment.center, children: [
          Positioned.fill(child: DecoratedBox(
              decoration: BoxDecoration(color: const Color(0x1F3A2402)))),
          Positioned.fill(
              child: CustomPaint(painter: _DotPatternPainter(dense: true))),
          Container(width: 12, height: 12,
              decoration: const BoxDecoration(shape: BoxShape.circle,
                  color: Color(0xFF3A2402),
                  boxShadow: [BoxShadow(color: Color(0x553A2402),
                      blurRadius: 6, spreadRadius: 3)])),
        ]),
      ),
    );
  }

  Widget _chip(String label, {bool gold = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: gold ? const Color(0xFF3A2402) : const Color(0x243A2402),
        borderRadius: BorderRadius.circular(7)),
      child: Text(label, style: TextStyle(fontSize: 9.5,
          fontWeight: FontWeight.w800,
          color: gold ? UellowColors.yellow : const Color(0xFF4A3005))),
    );
  }

  Widget _payPill(String label) {
    return Expanded(child: Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0x1A3A2402),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: const Color(0x293A2402))),
      child: Text(label, maxLines: 1,
          style: const TextStyle(fontSize: 7.5, fontWeight: FontWeight.w900,
              color: Color(0xFF4A3005))),
    ));
  }

  List<Widget> _countryRows() {
    final ar = _lang == 'ar';
    final list = _countries
        .where((c) => _tab == 'global' ? _isGlobal(c) : !_isGlobal(c))
        .toList();
    if (list.isEmpty) {
      return [Padding(padding: const EdgeInsets.all(16), child: Text(
          ar ? 'لا توجد متاجر' : 'No stores', textAlign: TextAlign.center,
          style: const TextStyle(color: UellowColors.muted)))];
    }
    return list.map((c) {
      final country = c['country'] as Map<String, dynamic>?;
      final flag = country?['flag'] as String? ?? '🌐';
      final name = (country?['name']?[ar ? 'ar' : 'en']
          ?? country?['name']?['en'] ?? '—').toString();
      final cur = c['currency'] as String? ?? '';
      final available = c['available'] != false;
      final selected = _picked?['country']?['code'] == country?['code'];
      return GestureDetector(
        onTap: () {
          if (!available) { showComingSoonDialog(context, c, _lang); return; }
          setState(() => _picked = c);
        },
        child: Opacity(opacity: available ? 1 : .55, child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? const Color(0x22F5C320) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: selected ? const Color(0xFF3A2402) : const Color(0x22412402),
                width: selected ? 1.5 : 1),
          ),
          child: Row(children: [
            Text(flag, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 11),
            Expanded(child: Text(name, style: const TextStyle(fontSize: 14,
                fontWeight: FontWeight.w800, color: UellowColors.darkBrown))),
            Text(available ? _curLabel(cur) : (ar ? '🚀 قريباً' : '🚀 Soon'),
                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700,
                    color: Color(0xFF7A5A10))),
            const SizedBox(width: 6),
            Icon(selected ? Icons.check_circle : Icons.chevron_left,
                size: 18,
                color: selected ? const Color(0xFF3A2402) : const Color(0x66412402)),
          ]),
        )),
      );
    }).toList();
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
        constraints: const BoxConstraints(maxHeight: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Container(width: 36, height: 4,
                  decoration: BoxDecoration(color: UellowColors.border,
                      borderRadius: BorderRadius.circular(2))),
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
                  final name = (cn?['name']?[_lang == 'ar' ? 'ar' : 'en']
                      ?? cn?['name']?['en'] ?? '—').toString();
                  final other = (cn?['name']?[_lang == 'ar' ? 'en' : 'ar'] ?? '')
                      .toString();
                  final cur = c['currency'] as String? ?? '';
                  final available = c['available'] != false;
                  return Opacity(
                    opacity: available ? 1 : 0.55,
                    child: ListTile(
                      leading: Text(flag, style: const TextStyle(fontSize: 22)),
                      title: Text(name,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(other, style: const TextStyle(fontSize: 11)),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: available
                              ? UellowColors.yellow : const Color(0xFFEFEFEF),
                          borderRadius:
                              const BorderRadius.all(Radius.circular(999)),
                        ),
                        child: Text(
                            available
                                ? _curLabel(cur)
                                : (_lang == 'ar' ? '🚀 قريباً' : '🚀 Soon'),
                            style: TextStyle(
                                color: available
                                    ? UellowColors.darkBrown : UellowColors.muted,
                                fontWeight: FontWeight.w800, fontSize: 11)),
                      ),
                      onTap: () {
                        if (!available) {
                          showComingSoonDialog(context, c, _lang);
                          return;
                        }
                        setState(() {
                          _picked = c;
                          _tab = _isGlobal(c) ? 'global' : 'me';
                        });
                        Navigator.pop(context);
                      },
                    ),
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
}

class _DotPatternPainter extends CustomPainter {
  final bool dense;
  _DotPatternPainter({this.dense = false});
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = const Color(0x1A3A2402);
    final step = dense ? 14.0 : 20.0;
    final r = step / 2;
    for (double y = 0; y <= size.height + step; y += step) {
      for (double x = 0; x <= size.width + step; x += step) {
        canvas.drawCircle(Offset(x, y), r, p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// v2.2.00 — professional "coming soon" dialog for gated countries.
void showComingSoonDialog(
    BuildContext context, Map<String, dynamic> mapping, String lang) {
  final ar = lang == 'ar';
  final country = (mapping['country'] as Map?)?.cast<String, dynamic>();
  final flag = country?['flag'] as String? ?? '🌍';
  final cname =
      (country?['name']?[ar ? 'ar' : 'en'] ?? country?['name']?['en'] ?? '')
          .toString();
  final title = ((mapping['unavailable_title'] as Map?)?[ar ? 'ar' : 'en']
      ?? (ar ? 'قريباً! 🚀' : 'Coming soon! 🚀')).toString();
  final msg = ((mapping['unavailable_message'] as Map?)?[ar ? 'ar' : 'en'] ?? '')
      .toString();
  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(flag, style: const TextStyle(fontSize: 44)),
          const SizedBox(height: 8),
          Text(cname, style: const TextStyle(fontSize: 13,
              fontWeight: FontWeight.w700, color: UellowColors.muted)),
          const SizedBox(height: 4),
          Text(title, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900,
                  color: UellowColors.darkBrown)),
          const SizedBox(height: 10),
          Text(msg, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, height: 1.5,
                  color: UellowColors.text)),
          const SizedBox(height: 18),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: UellowColors.yellow,
              foregroundColor: UellowColors.darkBrown,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: Text(ar ? 'حسناً، بانتظاركم!' : 'OK, can\'t wait!',
                style: const TextStyle(fontWeight: FontWeight.w900)),
          )),
        ]),
      ),
    ),
  );
}
