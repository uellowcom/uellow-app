// =============================================================================
// AnnouncementStrip (v2.1.57) — slim admin-controlled bar shown on chosen
// screens to a chosen audience (Mobile App ▸ Marketing ▸ Announcement
// Strips). Look + content + CTA all come from the backend; dismissals are
// remembered per strip id.
// =============================================================================
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../api/uellow_api.dart';
import '../router/uellow_router.dart';

class AnnouncementStrip extends StatefulWidget {
  const AnnouncementStrip({super.key, required this.screen});
  /// 'home' | 'cart' | 'shop' | 'account' | 'product'
  final String screen;

  @override
  State<AnnouncementStrip> createState() => _AnnouncementStripState();
}

class _AnnouncementStripState extends State<AnnouncementStrip> {
  Map<String, dynamic>? _strip;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final strips =
          await UellowApi.instance.announcements.forScreen(widget.screen);
      if (strips.isEmpty || !mounted) return;
      final prefs = await SharedPreferences.getInstance();
      final dismissed =
          prefs.getStringList('dismissed_announcements') ?? const [];
      for (final s in strips) {
        if (!dismissed.contains('${s['id']}')) {
          if (mounted) setState(() => _strip = s);
          return;
        }
      }
    } catch (_) {/* strips must never break a screen */}
  }

  Future<void> _dismiss() async {
    final id = '${_strip?['id']}';
    setState(() => _strip = null);
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('dismissed_announcements') ?? <String>[];
      if (!list.contains(id)) list.add(id);
      await prefs.setStringList('dismissed_announcements', list);
    } catch (_) {}
  }

  Color _hex(Object? raw, Color fb) {
    try {
      var s = (raw ?? '').toString().replaceAll('#', '');
      if (s.length == 6) s = 'FF$s';
      return Color(int.parse(s, radix: 16));
    } catch (_) {
      return fb;
    }
  }

  void _open() {
    final link = (_strip?['link'] as Map?)?.cast<String, dynamic>();
    final type = (link?['type'] ?? 'none').toString();
    final value = (link?['value'] ?? '').toString();
    switch (type) {
      case 'screen':
        const map = {
          'coupons': '/coupons', 'shop': '/category', 'flash': '/flash',
          'loyalty': '/loyalty', 'wallet': '/wallet',
          'notifications': '/notifications', 'account': '/account',
        };
        final r = map[value];
        if (r != null) Navigator.pushNamed(context, r);
        break;
      case 'product':
        final id = int.tryParse(value) ?? 0;
        if (id > 0) UellowRouter.goProduct(context, id);
        break;
      case 'category':
        final id = int.tryParse(value) ?? 0;
        if (id > 0) {
          Navigator.pushNamed(context, '/collection',
              arguments: {'category_id': id});
        }
        break;
      case 'url':
        if (value.isNotEmpty) {
          Navigator.pushNamed(context, '/webview',
              arguments: {'url': value, 'title': ''});
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _strip;
    if (s == null) return const SizedBox.shrink();
    final ar = UellowApi.instance.lang == 'ar';
    final l = ar ? 'ar' : 'en';
    final msg = ((s['message'] as Map?)?[l] ?? '').toString();
    final cta = ((s['cta'] as Map?)?[l] ?? '').toString();
    final bg = _hex(s['bg'], const Color(0xFF412402));
    final fg = _hex(s['fg'], Colors.white);
    final btnBg = _hex(s['btn_bg'], const Color(0xFFF5C320));
    final btnFg = _hex(s['btn_fg'], const Color(0xFF412402));
    return Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [BoxShadow(color: Color(0x26000000),
              blurRadius: 8, offset: Offset(0, 3))],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _open,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
              child: Row(children: [
                Text((s['emoji'] ?? '🎁').toString(),
                    style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 9),
                Expanded(child: Text(msg,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: fg, fontSize: 12,
                        fontWeight: FontWeight.w800, height: 1.25))),
                if (cta.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _open,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 13, vertical: 6),
                      decoration: BoxDecoration(
                        color: btnBg,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(cta, style: TextStyle(color: btnFg,
                          fontSize: 11, fontWeight: FontWeight.w900)),
                    ),
                  ),
                ],
                if (s['dismissible'] != false)
                  GestureDetector(
                    onTap: _dismiss,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(Icons.close, size: 15,
                          color: fg.withValues(alpha: 0.7)),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
