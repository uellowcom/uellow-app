// =============================================================================
// DynamicPageScreen — renders a JSON-driven page designed in the in-browser
// Uellow App Builder. Fetches `/api/mobile/v2/pages/<slug>` and dispatches
// each block kind to a small renderer. Tapping a block's CTA resolves the
// stored link target (page slug / built-in screen / url / product / category).
// =============================================================================
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../api/uellow_api.dart';
import '../router/uellow_router.dart';

class DynamicPageScreen extends StatefulWidget {
  const DynamicPageScreen({super.key, required this.slug});
  final String slug;

  @override
  State<DynamicPageScreen> createState() => _DynamicPageScreenState();
}

class _DynamicPageScreenState extends State<DynamicPageScreen> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<Map<String, dynamic>> _fetch() async {
    final api = UellowApi.instance;
    final url = Uri.parse('${api.baseUrl}/api/mobile/v2/pages/${widget.slug}');
    final lang = api.lang;
    final res = await http.get(url, headers: {
      'Accept': 'application/json',
      'X-Lang': lang,
    });
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}');
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    if (j['success'] != true) {
      throw Exception(j['error']?['message']?.toString() ?? 'Failed');
    }
    return (j['data'] as Map).cast<String, dynamic>();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            backgroundColor: Color(0xFFFAF6EB),
            body: Center(child: CircularProgressIndicator(color: Color(0xFF412402))),
          );
        }
        if (snap.hasError) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
                const SizedBox(height: 12),
                const Text('Page not available', style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text(snap.error.toString(), textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black54)),
              ]),
            )),
          );
        }
        return _build(snap.data!);
      },
    );
  }

  Widget _build(Map<String, dynamic> data) {
    final theme = _DynTheme.fromJson(data['theme'] as Map? ?? const {});
    final blocks = (data['blocks'] as List? ?? const []).cast<dynamic>();
    final name = (data['name'] ?? '').toString();
    return Scaffold(
      backgroundColor: theme.pageBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        iconTheme: IconThemeData(color: theme.dark),
        title: Text(name, style: TextStyle(
            color: theme.dark, fontWeight: FontWeight.w900, fontSize: 16)),
      ),
      body: RefreshIndicator(
        color: theme.dark,
        onRefresh: () async => setState(() => _future = _fetch()),
        child: ListView.builder(
          padding: const EdgeInsets.only(top: 8, bottom: 32),
          itemCount: blocks.length,
          itemBuilder: (_, i) {
            final b = (blocks[i] as Map).cast<String, dynamic>();
            return _renderBlock(context, b, theme);
          },
        ),
      ),
    );
  }
}

// ─── THEME ─────────────────────────────────────────────────────────────────

class _DynTheme {
  _DynTheme({
    required this.primary, required this.dark, required this.pageBg,
    required this.heroBg, required this.accent,
  });
  final Color primary;
  final Color dark;
  final Color pageBg;
  final String heroBg;   // CSS gradient string — we approximate it
  final Color accent;

  factory _DynTheme.fromJson(Map j) {
    return _DynTheme(
      primary: _hex(j['primary'], const Color(0xFFF5C320)),
      dark:    _hex(j['dark'],    const Color(0xFF412402)),
      pageBg:  _hex(j['page_bg'], const Color(0xFFFAF6EB)),
      heroBg:  (j['hero_bg'] as String?) ?? '',
      accent:  _hex(j['accent'],  const Color(0xFF1F8A40)),
    );
  }

  /// Build a real Flutter LinearGradient that approximates the CSS string
  /// stored on the theme. We extract every hex color in the string in order.
  LinearGradient heroGradient() {
    final regex = RegExp(r'#[0-9A-Fa-f]{6}');
    final hexes = regex.allMatches(heroBg).map((m) => m.group(0)!).toList();
    if (hexes.length < 2) {
      return LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [dark, primary],
      );
    }
    return LinearGradient(
      begin: Alignment.topLeft, end: Alignment.bottomRight,
      colors: hexes.map((h) => _hex(h, dark)).toList(),
    );
  }

  static Color _hex(dynamic v, Color fallback) {
    final s = v?.toString() ?? '';
    final m = RegExp(r'#([0-9A-Fa-f]{6})').firstMatch(s);
    if (m == null) return fallback;
    return Color(int.parse('FF${m.group(1)}', radix: 16));
  }
}

// ─── BLOCK DISPATCHER ──────────────────────────────────────────────────────

Widget _renderBlock(BuildContext c, Map<String, dynamic> b, _DynTheme t) {
  if (b['hidden'] == true) return const SizedBox.shrink();
  final kind = b['kind'] as String? ?? '';
  final p = ((b['props'] as Map?) ?? const {}).cast<String, dynamic>();
  final ar = UellowApi.instance.lang == 'ar';
  switch (kind) {
    case 'hero':       return _Hero(p: p, t: t, ar: ar);
    case 'carousel':   return _Hero(p: p, t: t, ar: ar);   // approximate
    case 'searchbar':  return _SearchBarBlock(p: p, t: t, ar: ar);
    case 'countdown':  return _CountdownBlock(p: p, t: t, ar: ar);
    case 'cats-grid':
    case 'cats-strip': return _CategoriesBlock(p: p, t: t, ar: ar);
    case 'flash':
    case 'products':
    case 'bestsellers':
    case 'rec-ai':
    case 'recent':
    case 'grid':       return _ProductsBlock(p: p, t: t, ar: ar, kind: kind);
    case 'banner-1':   return _Banner1(p: p, t: t, ar: ar);
    case 'banner-2':   return _BannerMulti(p: p, t: t, columns: 2);
    case 'banner-3':   return _BannerMulti(p: p, t: t, columns: 3);
    case 'vendors':
    case 'vendor-feat':return _VendorsBlock(p: p, t: t, ar: ar);
    case 'loyalty':    return _LoyaltyBlock(p: p, t: t, ar: ar, wallet: false);
    case 'wallet':     return _LoyaltyBlock(p: p, t: t, ar: ar, wallet: true);
    case 'coupons':    return _CouponsBlock(p: p, t: t, ar: ar);
    case 'newsletter': return _NewsletterBlock(p: p, t: t, ar: ar);
    case 'app-promo':  return _AppPromoBlock(p: p, t: t, ar: ar);
    case 'beena':      return _BeenaBlock(p: p, t: t, ar: ar);
    case 'reviews':    return _ReviewsBlock(p: p, t: t, ar: ar);
    case 'text':       return _TextBlock(p: p, t: t, ar: ar);
    case 'video':      return _VideoBlock(p: p, t: t);
    case 'spacer':     return const SizedBox(height: 16);
    case 'divider':    return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Divider(height: 1));
    default:           return const SizedBox.shrink();
  }
}

// ─── LINK HANDLER ──────────────────────────────────────────────────────────

void _openLink(BuildContext c, Map<String, dynamic>? link) {
  if (link == null) return;
  final type = link['type']?.toString();
  final value = link['value']?.toString();
  if (type == null || value == null) return;
  switch (type) {
    case 'page':
      Navigator.of(c).push(MaterialPageRoute(
          builder: (_) => DynamicPageScreen(slug: value)));
      break;
    case 'screen':
      _gotoScreen(c, value);
      break;
    case 'product':
      final id = int.tryParse(value) ?? 0;
      if (id > 0) UellowRouter.goProduct(c, id);
      break;
    case 'category':
      final id = int.tryParse(value) ?? 0;
      if (id > 0) UellowRouter.goCollection(c, id);
      break;
    case 'url':
      launchUrl(Uri.parse(value), mode: LaunchMode.externalApplication);
      break;
  }
}

void _gotoScreen(BuildContext c, String name) {
  const map = {
    'shop': Routes.category, 'cart': Routes.cart,
    'wishlist': Routes.wishlist, 'account': Routes.account,
    'orders': Routes.orders, 'beena': Routes.beena,
    'loyalty': Routes.loyalty, 'wallet': Routes.wallet,
    'coupons': Routes.coupons, 'notifications': Routes.notifications,
    'search': Routes.search, 'home': Routes.home,
  };
  final r = map[name];
  if (r != null) Navigator.of(c).pushNamed(r);
}

String _tx(Map p, bool ar, String key, String fallback) {
  final v = (ar ? p['${key}Ar'] : p['${key}En'])?.toString();
  if (v != null && v.isNotEmpty) return v;
  final fb = p['${key}En']?.toString();
  return (fb != null && fb.isNotEmpty) ? fb : fallback;
}

// ─── BLOCK WIDGETS ─────────────────────────────────────────────────────────

class _Hero extends StatelessWidget {
  const _Hero({required this.p, required this.t, required this.ar});
  final Map<String, dynamic> p;
  final _DynTheme t;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    final link = (p['link'] as Map?)?.cast<String, dynamic>();
    return GestureDetector(
      onTap: () => _openLink(context, link),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        height: 180,
        decoration: BoxDecoration(
          gradient: t.heroGradient(),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 14, offset: const Offset(0, 6))],
        ),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_tx(p, ar, 'title', 'Welcome'),
              style: const TextStyle(color: Colors.white,
                  fontSize: 22, fontWeight: FontWeight.w900, height: 1.2)),
          if ((p['subEn'] ?? p['subAr']) != null) ...[
            const SizedBox(height: 4),
            Text(_tx(p, ar, 'sub', ''),
                style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
          ],
          if ((p['ctaEn'] ?? p['ctaAr']) != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: t.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('${_tx(p, ar, 'cta', 'Shop')} →',
                  style: TextStyle(color: t.dark,
                      fontWeight: FontWeight.w900, fontSize: 12)),
            ),
          ],
        ]),
      ),
    );
  }
}

class _SearchBarBlock extends StatelessWidget {
  const _SearchBarBlock({required this.p, required this.t, required this.ar});
  final Map<String, dynamic> p;
  final _DynTheme t;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, Routes.search),
      child: Container(
        margin: const EdgeInsets.fromLTRB(14, 8, 14, 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: t.dark.withValues(alpha: 0.1)),
        ),
        child: Row(children: [
          Icon(Icons.search, size: 18, color: t.dark.withValues(alpha: 0.5)),
          const SizedBox(width: 8),
          Text(ar ? 'ابحث عن منتجات…' : 'Search products…',
              style: TextStyle(color: t.dark.withValues(alpha: 0.5), fontSize: 13)),
        ]),
      ),
    );
  }
}

class _CountdownBlock extends StatefulWidget {
  const _CountdownBlock({required this.p, required this.t, required this.ar});
  final Map<String, dynamic> p;
  final _DynTheme t;
  final bool ar;
  @override
  State<_CountdownBlock> createState() => _CountdownBlockState();
}

class _CountdownBlockState extends State<_CountdownBlock> {
  Timer? _tick;
  Duration _left = const Duration(hours: 23, minutes: 59);

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _left -= const Duration(seconds: 1));
    });
  }

  @override
  void dispose() { _tick?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final h = _left.inHours.toString().padLeft(2, '0');
    final m = (_left.inMinutes % 60).toString().padLeft(2, '0');
    final s = (_left.inSeconds % 60).toString().padLeft(2, '0');
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFC0392B), Color(0xFFE74C3C)]),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(children: [
        Text(_tx(widget.p, widget.ar, 'title', widget.ar ? 'ينتهي خلال' : 'Ends in'),
            style: const TextStyle(color: Colors.white,
                fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: .5)),
        const SizedBox(height: 4),
        Text('$h : $m : $s',
            style: const TextStyle(color: Colors.white,
                fontSize: 28, fontWeight: FontWeight.w900,
                fontFeatures: [FontFeature.tabularFigures()])),
      ]),
    );
  }
}

class _CategoriesBlock extends StatelessWidget {
  const _CategoriesBlock({required this.p, required this.t, required this.ar});
  final Map<String, dynamic> p;
  final _DynTheme t;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    // For v1 we just open the Shop screen on tap of any tile. Real source
    // selection ("All categories auto") is wired in a follow-up.
    final title = _tx(p, ar, 'title', ar ? 'تسوّق حسب الفئة' : 'Shop by category');
    const seeds = ['📱','👕','👟','💄','🏠','🎮','⌚','🎁'];
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 8, 0, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(title, style: TextStyle(
              color: t.dark, fontSize: 14, fontWeight: FontWeight.w900))),
        SizedBox(height: 78,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            scrollDirection: Axis.horizontal,
            itemCount: seeds.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => GestureDetector(
              onTap: () => Navigator.pushNamed(context, Routes.category),
              child: Column(children: [
                Container(width: 56, height: 56,
                  decoration: BoxDecoration(
                    color: t.primary.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                    border: Border.all(color: t.primary.withValues(alpha: 0.35)),
                  ),
                  alignment: Alignment.center,
                  child: Text(seeds[i], style: const TextStyle(fontSize: 24))),
                const SizedBox(height: 4),
                Text('Cat ${i+1}',
                    style: TextStyle(color: t.dark, fontSize: 11, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

class _ProductsBlock extends StatelessWidget {
  const _ProductsBlock({required this.p, required this.t, required this.ar, required this.kind});
  final Map<String, dynamic> p;
  final _DynTheme t;
  final bool ar;
  final String kind;
  @override
  Widget build(BuildContext context) {
    final title = _tx(p, ar, 'title', _fallbackTitle(kind, ar));
    // Hand off to a real product list — for v1 we link to /collection or /flash.
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 8, 0, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(children: [
            Expanded(child: Text(title, style: TextStyle(
                color: t.dark, fontSize: 14, fontWeight: FontWeight.w900))),
            TextButton(
              onPressed: () => Navigator.pushNamed(context,
                  kind == 'flash' ? Routes.flash : Routes.category),
              style: TextButton.styleFrom(
                  foregroundColor: t.primary,
                  textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  minimumSize: const Size(40, 28)),
              child: Text(ar ? 'الكل ←' : 'See all →'),
            ),
          ])),
        SizedBox(height: 170,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            scrollDirection: Axis.horizontal,
            itemCount: 6,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => Container(
              width: 130,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: t.dark.withValues(alpha: 0.08)),
              ),
              padding: const EdgeInsets.all(8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(height: 84,
                  decoration: BoxDecoration(
                    color: t.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8)),
                  child: Icon(Icons.shopping_bag_outlined,
                      size: 32, color: t.dark.withValues(alpha: 0.5))),
                const SizedBox(height: 6),
                Text('Product ${i+1}',
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.dark, fontSize: 11.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('${(i+1) * 4.5} KD',
                    style: TextStyle(color: t.dark, fontSize: 13, fontWeight: FontWeight.w900)),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  String _fallbackTitle(String k, bool ar) {
    switch (k) {
      case 'flash':       return ar ? '⚡ صفقات سريعة' : '⚡ Flash deals';
      case 'bestsellers': return ar ? 'الأكثر مبيعاً' : 'Bestsellers';
      case 'rec-ai':      return ar ? 'مقترحة لك' : 'Recommended for you';
      case 'recent':      return ar ? 'شاهدتها مؤخراً' : 'Recently viewed';
      default:            return ar ? 'منتجات' : 'Products';
    }
  }
}

class _Banner1 extends StatelessWidget {
  const _Banner1({required this.p, required this.t, required this.ar});
  final Map<String, dynamic> p;
  final _DynTheme t;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    final color = _DynTheme._hex(p['color'], t.accent);
    final link = (p['link'] as Map?)?.cast<String, dynamic>();
    final text = _tx(p, ar, 'title', 'Promo banner');
    return GestureDetector(
      onTap: () => _openLink(context, link),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [color, color.withValues(alpha: 0.7)],
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          Expanded(child: Text(text,
              style: const TextStyle(color: Colors.white,
                  fontSize: 14, fontWeight: FontWeight.w800))),
          if (link != null) const Icon(Icons.arrow_forward, color: Colors.white, size: 18),
        ]),
      ),
    );
  }
}

class _BannerMulti extends StatelessWidget {
  const _BannerMulti({required this.p, required this.t, required this.columns});
  final Map<String, dynamic> p;
  final _DynTheme t;
  final int columns;
  @override
  Widget build(BuildContext context) {
    final colors = [
      const Color(0xFF1D6FB7), const Color(0xFF1F8A40), const Color(0xFFC0392B),
    ];
    final labels = ['Free shipping', 'Tabby', 'COD'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(children: List.generate(columns, (i) {
        return Expanded(child: Padding(
          padding: EdgeInsets.only(right: i == columns - 1 ? 0 : 8),
          child: Container(
            height: 80,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                colors[i % colors.length],
                colors[i % colors.length].withValues(alpha: 0.7),
              ]),
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(12),
            alignment: Alignment.bottomLeft,
            child: Text(labels[i % labels.length],
                style: const TextStyle(color: Colors.white,
                    fontWeight: FontWeight.w800, fontSize: 12)),
          ),
        ));
      })),
    );
  }
}

class _VendorsBlock extends StatelessWidget {
  const _VendorsBlock({required this.p, required this.t, required this.ar});
  final Map<String, dynamic> p;
  final _DynTheme t;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    final title = _tx(p, ar, 'title', ar ? 'أفضل البائعين' : 'Top sellers');
    final names = ['Eureka','HainoTeko','BelleVie','Cherie','TechZone'];
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 8, 0, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(title, style: TextStyle(
              color: t.dark, fontSize: 14, fontWeight: FontWeight.w900))),
        SizedBox(height: 110,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            scrollDirection: Axis.horizontal,
            itemCount: names.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => Container(
              width: 96,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(10),
                border: Border.all(color: t.dark.withValues(alpha: 0.08)),
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: t.primary.withValues(alpha: 0.2),
                    shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: Text(names[i][0],
                      style: TextStyle(color: t.dark,
                          fontSize: 18, fontWeight: FontWeight.w900))),
                const SizedBox(height: 4),
                Text(names[i],
                    style: TextStyle(color: t.dark,
                        fontSize: 11.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('★ 4.${5+i}',
                    style: TextStyle(color: t.primary.withValues(alpha: 0.9),
                        fontSize: 10, fontWeight: FontWeight.w800)),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

class _LoyaltyBlock extends StatelessWidget {
  const _LoyaltyBlock({required this.p, required this.t, required this.ar, required this.wallet});
  final Map<String, dynamic> p;
  final _DynTheme t;
  final bool ar;
  final bool wallet;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, wallet ? Routes.wallet : Routes.loyalty),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: wallet
              ? const LinearGradient(colors: [Color(0xFF1F8A40), Color(0xFF5BC97A)])
              : LinearGradient(colors: [t.dark, _DynTheme._hex('#6B3A05', t.dark)]),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(wallet
                  ? (ar ? 'رصيد المحفظة' : 'Wallet balance')
                  : (ar ? 'نقاطك' : 'Loyalty points'),
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 11, fontWeight: FontWeight.w700,
                    letterSpacing: .5)),
            const SizedBox(height: 4),
            Text(wallet ? '12.500 KD' : '2,840',
                style: TextStyle(color: wallet ? Colors.white : t.primary,
                    fontSize: 24, fontWeight: FontWeight.w900)),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              border: Border.all(color: wallet ? Colors.white : t.primary),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(wallet ? (ar ? 'إعادة شحن' : 'Top up') : '🥇 GOLD',
                style: TextStyle(
                    color: wallet ? Colors.white : t.primary,
                    fontWeight: FontWeight.w800, fontSize: 11)),
          ),
        ]),
      ),
    );
  }
}

class _CouponsBlock extends StatelessWidget {
  const _CouponsBlock({required this.p, required this.t, required this.ar});
  final Map<String, dynamic> p;
  final _DynTheme t;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, Routes.coupons),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: t.primary.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: t.primary, style: BorderStyle.solid),
        ),
        child: Row(children: [
          const Text('🎟', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(ar ? '3 كوبونات متاحة' : '3 coupons available',
                style: TextStyle(color: t.dark, fontWeight: FontWeight.w800, fontSize: 13)),
            Text(ar ? 'اضغط للتفاصيل' : 'Tap to view',
                style: TextStyle(color: t.dark.withValues(alpha: 0.6), fontSize: 11)),
          ])),
          Icon(Icons.chevron_right, color: t.dark),
        ]),
      ),
    );
  }
}

class _NewsletterBlock extends StatelessWidget {
  const _NewsletterBlock({required this.p, required this.t, required this.ar});
  final Map<String, dynamic> p;
  final _DynTheme t;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.primary.withValues(alpha: 0.4)),
      ),
      child: Column(children: [
        Text(_tx(p, ar, 'title', ar ? 'ابق على اطلاع' : 'Stay in the loop'),
            style: TextStyle(color: t.dark, fontSize: 14, fontWeight: FontWeight.w900)),
        const SizedBox(height: 2),
        Text(_tx(p, ar, 'sub', ar ? 'وصول مبكر وعروض خاصة' : 'New arrivals + private deals'),
            style: TextStyle(color: t.dark.withValues(alpha: 0.6), fontSize: 11.5)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: t.pageBg, borderRadius: BorderRadius.circular(20),
              border: Border.all(color: t.dark.withValues(alpha: 0.08)),
            ),
            child: TextField(
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: ar ? 'بريدك الإلكتروني' : 'you@example.com',
                hintStyle: TextStyle(color: t.dark.withValues(alpha: 0.4)),
                isDense: true,
              ),
              style: TextStyle(color: t.dark, fontSize: 13),
            ),
          )),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: t.primary, borderRadius: BorderRadius.circular(20),
            ),
            child: Text(ar ? 'اشترك' : 'Subscribe',
                style: TextStyle(color: t.dark, fontWeight: FontWeight.w900, fontSize: 12)),
          ),
        ]),
      ]),
    );
  }
}

class _AppPromoBlock extends StatelessWidget {
  const _AppPromoBlock({required this.p, required this.t, required this.ar});
  final Map<String, dynamic> p;
  final _DynTheme t;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: t.heroGradient(),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        const Text('📱', style: TextStyle(fontSize: 30)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_tx(p, ar, 'title', ar ? 'حمّل تطبيقنا' : 'Get our app'),
              style: const TextStyle(color: Colors.white,
                  fontSize: 14, fontWeight: FontWeight.w900)),
          Text(_tx(p, ar, 'sub', ar ? 'دفع أسرع · تتبع مباشر' : 'Faster checkout · Live tracking'),
              style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 11)),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: t.primary, borderRadius: BorderRadius.circular(20),
          ),
          child: Text(ar ? 'ثبّت' : 'Install',
              style: TextStyle(color: t.dark, fontWeight: FontWeight.w900, fontSize: 12)),
        ),
      ]),
    );
  }
}

class _BeenaBlock extends StatelessWidget {
  const _BeenaBlock({required this.p, required this.t, required this.ar});
  final Map<String, dynamic> p;
  final _DynTheme t;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, Routes.beena),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [t.dark, Colors.black87]),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          Container(width: 42, height: 42,
            decoration: BoxDecoration(color: t.primary, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text('B', style: TextStyle(color: t.dark,
                fontSize: 18, fontWeight: FontWeight.w900))),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_tx(p, ar, 'title', ar ? 'بينة المساعد الذكي' : 'Beena AI'),
                style: TextStyle(color: t.primary,
                    fontSize: 14, fontWeight: FontWeight.w900)),
            Text(ar ? 'اسأل أي شيء · جرّب الملابس عليك'
                    : 'Ask anything · Try outfits on you',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11)),
          ])),
          Icon(Icons.chevron_right, color: t.primary, size: 24),
        ]),
      ),
    );
  }
}

class _ReviewsBlock extends StatelessWidget {
  const _ReviewsBlock({required this.p, required this.t, required this.ar});
  final Map<String, dynamic> p;
  final _DynTheme t;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.dark.withValues(alpha: 0.08)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('★★★★★',
            style: TextStyle(color: t.primary, fontSize: 18, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text(
            ar
                ? '"أسرع توصيل شفته — طلبت الساعة 2 ووصل عند الباب 5."'
                : '"Fastest delivery — ordered at 2pm, at my door by 5pm."',
            style: TextStyle(color: t.dark, fontSize: 12.5, fontStyle: FontStyle.italic)),
        const SizedBox(height: 4),
        Text(ar ? '— أحمد ك.' : '— Ahmed K.',
            style: TextStyle(color: t.dark.withValues(alpha: 0.6), fontSize: 11)),
      ]),
    );
  }
}

class _TextBlock extends StatelessWidget {
  const _TextBlock({required this.p, required this.t, required this.ar});
  final Map<String, dynamic> p;
  final _DynTheme t;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    final title = _tx(p, ar, 'title', '');
    final body = _tx(p, ar, 'text', '');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (title.isNotEmpty) ...[
          Text(title,
              style: TextStyle(color: t.dark, fontSize: 14, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
        ],
        Text(body,
            style: TextStyle(color: t.dark, fontSize: 13, height: 1.5)),
      ]),
    );
  }
}

class _VideoBlock extends StatelessWidget {
  const _VideoBlock({required this.p, required this.t});
  final Map<String, dynamic> p;
  final _DynTheme t;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      height: 180,
      decoration: BoxDecoration(
        color: Colors.black, borderRadius: BorderRadius.circular(12)),
      alignment: Alignment.center,
      child: const Icon(Icons.play_circle_outline,
          color: Colors.white, size: 56),
    );
  }
}
