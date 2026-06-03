// =============================================================================
// SettingsScreen — compact list of tiles. Country + Language each open a
// search dialog. A Notifications section toggles push categories
// (promotion / order_update / general / master switch) wired to
// /api/mobile/v2/notifications/preferences.
// =============================================================================
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../api/uellow_api.dart';
import '../../api/uellow_endpoints.dart';
import '../theme/uellow_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.onRestart});
  final VoidCallback? onRestart;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _lang = UellowApi.instance.lang;
  String? _countryCode;
  List<Map<String, dynamic>> _countries = [];
  List<Map<String, dynamic>> _langs = [];
  Map<String, dynamic>? _prefs;       // notification preferences payload
  bool _loading = true;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final base = UellowApi.instance.baseUrl;
      final token = await UellowApi.instance.tokenStore.readToken();
      final headers = {
        if (token != null) 'Authorization': 'Bearer $token',
      };
      final results = await Future.wait([
        http.get(Uri.parse('$base${EP.appCountriesList()}')),
        http.get(Uri.parse('$base/api/mobile/v2/app/languages')),
        http.get(Uri.parse('$base/api/mobile/v2/notifications/preferences'),
            headers: headers),
      ]);
      final cBody = jsonDecode(utf8.decode(results[0].bodyBytes)) as Map<String, dynamic>;
      if (cBody['success'] == true) {
        _countries = (cBody['data'] as List).cast<Map<String, dynamic>>();
      }
      final lBody = jsonDecode(utf8.decode(results[1].bodyBytes)) as Map<String, dynamic>;
      if (lBody['success'] == true) {
        _langs = (lBody['data'] as List).cast<Map<String, dynamic>>();
        // Override the Arabic flag to Kuwait — Odoo returns 🌐 for ar_001
        // because the locale has no country, but our primary AR market
        // is Kuwait so that flag reads better.
        for (final l in _langs) {
          final code = (l['code'] as String?) ?? '';
          if (code.startsWith('ar')) l['flag'] = '🇰🇼';
        }
        // Normalize the active lang to a FULL code that actually exists
        // in the server-provided list (UellowApi.lang is short — 'ar'/'en'
        // — but the picker IDs are full like 'ar_001'/'en_US').
        final short = UellowApi.instance.lang;
        for (final l in _langs) {
          final code = (l['code'] as String?) ?? '';
          if (code.toLowerCase().startsWith(short)) {
            _lang = code;
            break;
          }
        }
      }
      final pBody = jsonDecode(utf8.decode(results[2].bodyBytes)) as Map<String, dynamic>;
      if (pBody['success'] == true) {
        _prefs = Map<String, dynamic>.from(pBody['data'] as Map);
      }
      final prefs = await SharedPreferences.getInstance();
      _countryCode = prefs.getString('uellow_country_code_v1');
      if (_countryCode == null && _countries.isNotEmpty) {
        final base = UellowApi.instance.baseUrl;
        for (final c in _countries) {
          final w = c['website'] as Map?;
          final dom = (w?['api_base'] as String?) ?? (w?['domain'] as String?) ?? '';
          if (dom.isNotEmpty && base.contains(dom.replaceAll(RegExp(r'^https?://'), ''))) {
            _countryCode = c['country']?['code'] as String?;
            break;
          }
        }
      }
      _countryCode ??= (_countries.isNotEmpty
          ? (_countries.first['country']?['code'] as String?) : null);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Map<String, dynamic>? get _currentCountry {
    if (_countryCode == null) return null;
    for (final c in _countries) {
      if ((c['country']?['code'] as String?) == _countryCode) return c;
    }
    return null;
  }

  Map<String, dynamic>? get _currentLang {
    for (final l in _langs) {
      if ((l['code'] as String?) == _lang) return l;
    }
    return null;
  }

  // ── Pickers ────────────────────────────────────────────────

  Future<void> _pickCountry() async {
    final picked = await showModalBottomSheet<String>(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SearchPickerSheet(
        title: UellowApi.instance.lang == 'ar' ? 'اختر دولة' : 'Select country',
        items: _countries.map((c) => _PickerItem(
          id:    (c['country']?['code'] as String?) ?? '',
          label: (c['country']?['name']?['en'] as String?) ?? '',
          subtitle: (c['currency'] as String?) ?? '',
          leadingEmoji: _flag((c['country']?['code'] as String?) ?? ''),
        )).toList(),
        currentId: _countryCode,
      ),
    );
    if (picked != null && picked != _countryCode) {
      setState(() { _countryCode = picked; _dirty = true; });
    }
  }

  Future<void> _pickLang() async {
    final picked = await showModalBottomSheet<String>(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SearchPickerSheet(
        title: UellowApi.instance.lang == 'ar' ? 'اختر اللغة' : 'Select language',
        items: _langs.map((l) => _PickerItem(
          id: (l['code'] as String?) ?? '',
          label: (l['name'] as String?) ?? '',
          subtitle: (l['code'] as String?) ?? '',
          leadingEmoji: (l['flag'] as String?) ?? '🌐',
        )).toList(),
        currentId: _lang,
      ),
    );
    if (picked != null && picked != _lang) {
      setState(() { _lang = picked; _dirty = true; });
    }
  }

  Future<void> _savePref(String key, bool value) async {
    if (_prefs == null) return;
    setState(() => _prefs![key] = value);
    try {
      final token = await UellowApi.instance.tokenStore.readToken();
      await http.post(
        Uri.parse('${UellowApi.instance.baseUrl}/api/mobile/v2/notifications/preferences/save'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({key: value}),
      );
    } catch (_) {}
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('uellow_lang_v1', _lang);
    if (_countryCode != null) {
      await prefs.setString('uellow_country_code_v1', _countryCode!);
      final c = _currentCountry;
      final website = c?['website'] as Map?;
      final apiBase = website?['api_base'] as String?
          ?? website?['domain'] as String?;
      if (apiBase != null && apiBase.isNotEmpty) {
        await UellowApi.instance.setBaseUrl(apiBase);
      }
      // v2.1.16 — store the website id for per-website API scoping.
      final wid = website?['id'] as int?;
      if (wid != null && wid > 0) {
        await UellowApi.instance.tokenStore.writeWebsiteId(wid);
      }
    }
    // setLang() bumps a ValueNotifier that the root MaterialApp listens
    // to — the entire app re-keys and rebuilds with the new Directionality
    // + Locale immediately. No need to pop everything or warm-restart.
    UellowApi.instance.setLang(_lang);
    if (!mounted) return;
    setState(() => _dirty = false);
    // If a baseUrl swap happened, push back to home so all FutureBuilders
    // re-fetch from the new country's API.
    Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return Scaffold(
      backgroundColor: UellowColors.bg,
      appBar: AppBar(
        title: Text(ar ? 'الإعدادات' : 'Settings'),
        backgroundColor: Colors.white,
      ),
      body: SafeArea(child: _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(padding: const EdgeInsets.all(16), children: [
            _section(ar ? 'الحساب' : 'Account'),
            _selectorTile(
              icon: Icons.language,
              label: ar ? 'اللغة' : 'Language',
              value: _currentLang?['name'] as String? ?? _lang,
              leadingEmoji: _currentLang?['flag'] as String?,
              onTap: _pickLang,
            ),
            const SizedBox(height: 6),
            _selectorTile(
              icon: Icons.public,
              label: ar ? 'الدولة' : 'Country',
              value: _currentCountry?['country']?['name']?['en'] as String?
                  ?? _countryCode ?? '—',
              subtitle: _currentCountry?['currency'] as String?,
              leadingEmoji: _flag(_countryCode ?? ''),
              onTap: _pickCountry,
            ),
            const SizedBox(height: 24),
            _section(ar ? 'الإشعارات' : 'Notifications'),
            if (_prefs == null) Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(ar
                  ? 'سجّل الدخول لإدارة الإشعارات.'
                  : 'Sign in to manage notifications.', style: UT.small),
            ) else ...[
              _toggleTile(
                icon: Icons.notifications_active_outlined,
                label: ar ? 'تفعيل الإشعارات' : 'Push notifications',
                description: ar
                    ? 'المفتاح الرئيسي — عند الإغلاق لن تصلك أي إشعارات.'
                    : 'Master switch — when off, no push is delivered.',
                value: (_prefs!['push_enabled'] ?? true) as bool,
                onChanged: (v) => _savePref('push_enabled', v),
              ),
              const SizedBox(height: 4),
              ...((_prefs!['categories'] as List?) ?? const []).map((cat) {
                final m = cat as Map<String, dynamic>;
                final code = (m['code'] ?? '').toString();
                final key = {
                  'promotion':    'receive_promotions',
                  'order_update': 'receive_order_updates',
                  'general':      'receive_general',
                }[code] ?? code;
                final label = (m['label'] as Map?)?[ar ? 'ar' : 'en'] as String?
                    ?? code;
                final desc = (m['description'] as Map?)?[ar ? 'ar' : 'en'] as String?;
                final icon = {
                  'promotion':    Icons.local_offer_outlined,
                  'order_update': Icons.local_shipping_outlined,
                  'general':      Icons.tips_and_updates_outlined,
                }[code] ?? Icons.notifications_outlined;
                return _toggleTile(
                  icon: icon, label: label, description: desc,
                  value: (_prefs![key] ?? true) as bool,
                  onChanged: (v) => _savePref(key, v),
                  enabled: (_prefs!['push_enabled'] ?? true) as bool,
                );
              }),
            ],
            const SizedBox(height: 30),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: _dirty ? _save : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: UellowColors.yellow,
                foregroundColor: UellowColors.darkBrown,
                disabledBackgroundColor: UellowColors.yellowSoft,
                disabledForegroundColor: UellowColors.muted,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(ar
                  ? (_dirty ? 'حفظ التغييرات' : 'لا توجد تغييرات')
                  : (_dirty ? 'Save changes' : 'No changes'),
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
            )),
          ])),
    );
  }

  Widget _section(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 4),
    child: Text(label.toUpperCase(), style: const TextStyle(
        fontSize: 11, fontWeight: FontWeight.w800,
        color: UellowColors.muted, letterSpacing: 0.8)),
  );

  Widget _selectorTile({
    required IconData icon, required String label,
    required String value, String? subtitle, String? leadingEmoji,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            border: Border.all(color: UellowColors.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            if (leadingEmoji != null && leadingEmoji.isNotEmpty)
              Padding(padding: const EdgeInsets.only(right: 10),
                  child: Text(leadingEmoji, style: const TextStyle(fontSize: 20)))
            else Padding(padding: const EdgeInsets.only(right: 10),
                child: Icon(icon, color: UellowColors.darkBrown, size: 20)),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min, children: [
              Text(label, style: const TextStyle(fontSize: 11,
                  color: UellowColors.muted, fontWeight: FontWeight.w700,
                  letterSpacing: 0.5)),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(fontSize: 14,
                  fontWeight: FontWeight.w800, color: UellowColors.ink)),
            ])),
            if (subtitle != null && subtitle.isNotEmpty) Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(subtitle, style: const TextStyle(
                  color: UellowColors.muted, fontWeight: FontWeight.w700)),
            ),
            const Icon(Icons.chevron_right, color: UellowColors.muted),
          ]),
        ),
      ),
    );
  }

  Widget _toggleTile({
    required IconData icon, required String label, String? description,
    required bool value, required ValueChanged<bool> onChanged,
    bool enabled = true,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: UellowColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Icon(icon, color: enabled ? UellowColors.darkBrown : UellowColors.muted, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: enabled ? UellowColors.ink : UellowColors.muted)),
          if (description != null && description.isNotEmpty) Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(description, style: UT.small),
          ),
        ])),
        Switch(
          value: value && enabled,
          onChanged: enabled ? onChanged : null,
          activeColor: UellowColors.yellow,
          activeTrackColor: UellowColors.yellowSoft,
        ),
      ]),
    );
  }

  String _flag(String code) {
    if (code.length != 2) return '🌐';
    const base = 127397;
    return String.fromCharCodes([code.codeUnitAt(0) + base, code.codeUnitAt(1) + base]);
  }
}

// ─── Reusable search picker (used for country + language) ─────────────

class _PickerItem {
  final String id, label, subtitle, leadingEmoji;
  const _PickerItem({required this.id, required this.label,
      required this.subtitle, required this.leadingEmoji});
}

class _SearchPickerSheet extends StatefulWidget {
  const _SearchPickerSheet({
      required this.title, required this.items, this.currentId});
  final String title;
  final List<_PickerItem> items;
  final String? currentId;
  @override
  State<_SearchPickerSheet> createState() => _SearchPickerSheetState();
}

class _SearchPickerSheetState extends State<_SearchPickerSheet> {
  final _ctrl = TextEditingController();
  String _q = '';
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final filtered = widget.items.where((i) =>
        _q.isEmpty || i.label.toLowerCase().contains(_q.toLowerCase())).toList();
    final ar = UellowApi.instance.lang == 'ar';
    return DraggableScrollableSheet(
      expand: false, initialChildSize: 0.7, minChildSize: 0.4, maxChildSize: 0.95,
      builder: (_, scroll) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(children: [
          Container(width: 40, height: 4, margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(color: UellowColors.border,
                  borderRadius: BorderRadius.circular(2))),
          Padding(padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
              child: Row(children: [
                Expanded(child: Text(widget.title, style: UT.h2)),
                IconButton(onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: UellowColors.muted)),
              ])),
          Padding(padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
              child: TextField(
                controller: _ctrl,
                onChanged: (v) => setState(() => _q = v),
                decoration: InputDecoration(
                  hintText: ar ? 'بحث…' : 'Search…',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                ),
              )),
          Expanded(child: ListView.separated(
            controller: scroll,
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: UellowColors.border),
            itemBuilder: (_, i) {
              final it = filtered[i];
              final on = it.id == widget.currentId;
              return InkWell(
                onTap: () => Navigator.pop(context, it.id),
                child: Container(
                  color: on ? UellowColors.yellowFaint : Colors.transparent,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  child: Row(children: [
                    Text(it.leadingEmoji, style: const TextStyle(fontSize: 22)),
                    const SizedBox(width: 12),
                    Expanded(child: Text(it.label, style: const TextStyle(
                        fontWeight: FontWeight.w700, color: UellowColors.ink))),
                    if (it.subtitle.isNotEmpty) Text(it.subtitle,
                        style: const TextStyle(color: UellowColors.muted,
                            fontWeight: FontWeight.w700)),
                    if (on) const Padding(padding: EdgeInsets.only(left: 8),
                        child: Icon(Icons.check_circle, color: UellowColors.success, size: 20)),
                  ]),
                ),
              );
            },
          )),
        ]),
      ),
    );
  }
}
