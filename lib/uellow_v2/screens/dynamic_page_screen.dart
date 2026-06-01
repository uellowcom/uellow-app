// =============================================================================
// DynamicPageScreen — renders a JSON-driven page designed in the in-browser
// Uellow App Builder. Fetches `/api/mobile/v2/pages/<slug>` and dispatches
// each block kind to a small renderer. Tapping a block's CTA resolves the
// stored link target (page slug / built-in screen / url / product / category).
// =============================================================================
import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../api/uellow_api.dart';
import '../../api/uellow_models.dart';
import '../router/uellow_router.dart';
import '../widgets/product_card.dart';

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
    final theme = DynTheme.fromJson(data['theme'] as Map? ?? const {});
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

class DynTheme {
  DynTheme({
    required this.primary, required this.dark, required this.pageBg,
    required this.heroBg, required this.accent,
  });
  final Color primary;
  final Color dark;
  final Color pageBg;
  final String heroBg;   // CSS gradient string — we approximate it
  final Color accent;

  factory DynTheme.fromJson(Map j) {
    return DynTheme(
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

/// Render a single block from a `mobile.page.blocks_json` element using the
/// supplied theme. Public so HomeScreen (and any other screen) can reuse the
/// renderers without duplicating widget code.
Widget renderDynamicBlock(BuildContext c, Map<String, dynamic> b, DynTheme t) =>
    _renderBlock(c, b, t);

Widget _renderBlock(BuildContext c, Map<String, dynamic> b, DynTheme t) {
  if (b['hidden'] == true) return const SizedBox.shrink();
  final kind = b['kind'] as String? ?? '';
  final p = ((b['props'] as Map?) ?? const {}).cast<String, dynamic>();
  // `data` is the server-resolved payload (real categories/products/vendors)
  final data = ((b['data'] as Map?) ?? const {}).cast<String, dynamic>();
  final ar = UellowApi.instance.lang == 'ar';
  switch (kind) {
    case 'hero':       return _Hero(p: p, t: t, ar: ar);
    case 'carousel':   return _CarouselBlock(p: p, data: data, t: t, ar: ar);
    case 'searchbar':  return _SearchBarBlock(p: p, t: t, ar: ar);
    case 'countdown':  return _CountdownBlock(p: p, t: t, ar: ar);
    case 'cats-grid':
    case 'cats-strip': return _CategoriesBlock(p: p, data: data, t: t, ar: ar);
    case 'flash':      return _FlashBlock(p: p, data: data, t: t, ar: ar);
    case 'products':
    case 'bestsellers':
    case 'rec-ai':
    case 'recent':
    case 'grid':       return _ProductsBlock(p: p, data: data, t: t, ar: ar, kind: kind);
    case 'banner-1':   return _Banner1(p: p, t: t, ar: ar);
    case 'banner-2':   return _BannerMulti(p: p, t: t, columns: 2);
    case 'banner-3':   return _BannerMulti(p: p, t: t, columns: 3);
    case 'vendors':
    case 'vendor-feat':return _VendorsBlock(p: p, data: data, t: t, ar: ar);
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
  final DynTheme t;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    final link = (p['link'] as Map?)?.cast<String, dynamic>();
    final imgUrl = (p['image_url'] as String?) ?? '';
    return GestureDetector(
      onTap: () => _openLink(context, link),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        height: 180,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: imgUrl.isEmpty ? t.heroGradient() : null,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 14, offset: const Offset(0, 6))],
        ),
        child: Stack(fit: StackFit.expand, children: [
          if (imgUrl.isNotEmpty)
            CachedNetworkImage(imageUrl: imgUrl, fit: BoxFit.cover,
              errorWidget: (_, __, ___) => Container(decoration: BoxDecoration(gradient: t.heroGradient()))),
          if (imgUrl.isNotEmpty)
            Container(decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black.withValues(alpha: 0.6)],
              ),
            )),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: Column(mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_tx(p, ar, 'title', 'Welcome'),
                  style: const TextStyle(color: Colors.white,
                      fontSize: 22, fontWeight: FontWeight.w900, height: 1.2,
                      shadows: [Shadow(color: Colors.black54, blurRadius: 6)])),
              if ((p['subEn'] ?? p['subAr']) != null) ...[
                const SizedBox(height: 4),
                Text(_tx(p, ar, 'sub', ''),
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.92), fontSize: 13,
                        shadows: const [Shadow(color: Colors.black54, blurRadius: 6)])),
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
        ]),
      ),
    );
  }
}

class _CarouselBlock extends StatefulWidget {
  const _CarouselBlock({required this.p, required this.data, required this.t, required this.ar});
  final Map<String, dynamic> p;
  final Map<String, dynamic> data;
  final DynTheme t;
  final bool ar;
  @override
  State<_CarouselBlock> createState() => _CarouselBlockState();
}

class _CarouselBlockState extends State<_CarouselBlock> {
  final _ctrl = PageController(viewportFraction: 0.92);
  int _i = 0;
  Timer? _auto;

  @override
  void initState() {
    super.initState();
    _auto = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_ctrl.hasClients) return;
      final slides = (widget.data['slides'] as List?) ?? const [];
      if (slides.length < 2) return;
      _i = (_i + 1) % slides.length;
      _ctrl.animateToPage(_i, duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut);
    });
  }
  @override
  void dispose() { _auto?.cancel(); _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final slides = ((widget.data['slides'] as List?) ?? const []).cast<dynamic>();
    if (slides.isEmpty) {
      // No mobile.slider records → fall back to a styled hero from props.
      return _Hero(p: widget.p, t: widget.t, ar: widget.ar);
    }
    return SizedBox(
      height: 180,
      child: PageView.builder(
        controller: _ctrl,
        onPageChanged: (i) => setState(() => _i = i),
        itemCount: slides.length,
        itemBuilder: (_, i) {
          final s = (slides[i] as Map).cast<String, dynamic>();
          final url = s['image_url']?.toString() ?? '';
          final link = (s['link'] is Map) ? (s['link'] as Map).cast<String, dynamic>() : null;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: GestureDetector(
              onTap: () => _openLink(context, link),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: url.isNotEmpty
                    ? CachedNetworkImage(imageUrl: url, fit: BoxFit.cover,
                        placeholder: (_, __) => Container(color: widget.t.dark.withValues(alpha: 0.1)),
                        errorWidget: (_, __, ___) => Container(decoration: BoxDecoration(gradient: widget.t.heroGradient())))
                    : Container(decoration: BoxDecoration(gradient: widget.t.heroGradient())),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SearchBarBlock extends StatelessWidget {
  const _SearchBarBlock({required this.p, required this.t, required this.ar});
  final Map<String, dynamic> p;
  final DynTheme t;
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
  final DynTheme t;
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
  const _CategoriesBlock({required this.p, required this.data, required this.t, required this.ar});
  final Map<String, dynamic> p;
  final Map<String, dynamic> data;
  final DynTheme t;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    final title = _tx(p, ar, 'title', ar ? 'تسوّق حسب الفئة' : 'Shop by category');
    final items = ((data['items'] as List?) ?? const []).cast<dynamic>()
        .map((e) => (e as Map).cast<String, dynamic>()).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 8, 0, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(title, style: TextStyle(
              color: t.dark, fontSize: 14, fontWeight: FontWeight.w900))),
        SizedBox(height: 86,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final cat = items[i];
              final url = (cat['icon_url'] as String?) ?? '';
              return GestureDetector(
                onTap: () => UellowRouter.goCollection(context, (cat['id'] as num).toInt()),
                child: SizedBox(width: 70,
                  child: Column(children: [
                    Container(width: 56, height: 56,
                      decoration: BoxDecoration(
                        color: t.primary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                        border: Border.all(color: t.primary.withValues(alpha: 0.30)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: url.isNotEmpty
                          ? CachedNetworkImage(imageUrl: url, fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => Icon(Icons.category, color: t.dark.withValues(alpha: 0.5)))
                          : Icon(Icons.category, color: t.dark.withValues(alpha: 0.5))),
                    const SizedBox(height: 4),
                    Text(cat['name']?.toString() ?? '',
                        textAlign: TextAlign.center,
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: t.dark, fontSize: 10.5,
                            height: 1.15, fontWeight: FontWeight.w600)),
                  ]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class _ProductsBlock extends StatelessWidget {
  const _ProductsBlock({required this.p, required this.data, required this.t, required this.ar, required this.kind});
  final Map<String, dynamic> p;
  final Map<String, dynamic> data;
  final DynTheme t;
  final bool ar;
  final String kind;
  @override
  Widget build(BuildContext context) {
    final title = _tx(p, ar, 'title', _fallbackTitle(kind, ar));
    final items = ((data['items'] as List?) ?? const []).cast<dynamic>()
        .map((e) => (e as Map).cast<String, dynamic>()).toList();
    if (items.isEmpty) return const SizedBox.shrink();
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
        SizedBox(height: 198,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final prod = items[i];
              final price = (prod['price'] as Map?)?.cast<String, dynamic>();
              final compare = prod['compare_price'];
              final discount = (prod['discount_pct'] as num?)?.toInt() ?? 0;
              final url = (prod['image'] as String?) ?? '';
              return GestureDetector(
                onTap: () => UellowRouter.goProduct(context, (prod['id'] as num).toInt()),
                child: Container(
                  width: 138,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: t.dark.withValues(alpha: 0.08)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Stack(children: [
                      AspectRatio(aspectRatio: 1,
                        child: url.isNotEmpty
                            ? CachedNetworkImage(imageUrl: url, fit: BoxFit.cover,
                                placeholder: (_, __) => Container(color: t.primary.withValues(alpha: 0.06)),
                                errorWidget: (_, __, ___) => Container(
                                    color: t.primary.withValues(alpha: 0.08),
                                    child: Icon(Icons.broken_image_outlined,
                                        color: t.dark.withValues(alpha: 0.4))))
                            : Container(color: t.primary.withValues(alpha: 0.08),
                                child: Icon(Icons.shopping_bag_outlined,
                                    color: t.dark.withValues(alpha: 0.4)))),
                      if (discount > 0) Positioned(
                        top: 4, left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFC0392B),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('-$discount%',
                              style: const TextStyle(color: Colors.white,
                                  fontSize: 9, fontWeight: FontWeight.w900)),
                        ),
                      ),
                    ]),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(prod['name']?.toString() ?? '',
                            maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: t.dark, fontSize: 11,
                                height: 1.25, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text('${(price?['amount'] as num? ?? 0).toStringAsFixed(price?['digits'] ?? 3)} ${price?['symbol'] ?? ''}',
                              style: TextStyle(color: t.dark, fontSize: 13,
                                  fontWeight: FontWeight.w900)),
                          if (compare != null) ...[
                            const SizedBox(width: 4),
                            Text('${(compare as num).toStringAsFixed(price?['digits'] ?? 3)}',
                                style: TextStyle(color: t.dark.withValues(alpha: 0.45),
                                    fontSize: 10, fontWeight: FontWeight.w600,
                                    decoration: TextDecoration.lineThrough)),
                          ],
                        ]),
                      ]),
                    ),
                  ]),
                ),
              );
            },
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
  final DynTheme t;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    final color = DynTheme._hex(p['color'], t.accent);
    final link = (p['link'] as Map?)?.cast<String, dynamic>();
    final text = _tx(p, ar, 'title', 'Promo banner');
    final imgUrl = (p['image_url'] as String?) ?? '';
    return GestureDetector(
      onTap: () => _openLink(context, link),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        height: 90,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: imgUrl.isEmpty
              ? LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [color, color.withValues(alpha: 0.7)])
              : null,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Stack(fit: StackFit.expand, children: [
          if (imgUrl.isNotEmpty)
            CachedNetworkImage(imageUrl: imgUrl, fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(color: color)),
          if (imgUrl.isNotEmpty)
            Container(color: Colors.black.withValues(alpha: 0.35)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Row(children: [
              Expanded(child: Text(text,
                  style: const TextStyle(color: Colors.white,
                      fontSize: 14, fontWeight: FontWeight.w800,
                      shadows: [Shadow(color: Colors.black54, blurRadius: 4)]))),
              if (link != null) const Icon(Icons.arrow_forward, color: Colors.white, size: 18),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _BannerMulti extends StatelessWidget {
  const _BannerMulti({required this.p, required this.t, required this.columns});
  final Map<String, dynamic> p;
  final DynTheme t;
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
  const _VendorsBlock({required this.p, required this.data, required this.t, required this.ar});
  final Map<String, dynamic> p;
  final Map<String, dynamic> data;
  final DynTheme t;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    final title = _tx(p, ar, 'title', ar ? 'أفضل البائعين' : 'Top sellers');
    final items = ((data['items'] as List?) ?? const []).cast<dynamic>()
        .map((e) => (e as Map).cast<String, dynamic>()).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 8, 0, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(title, style: TextStyle(
              color: t.dark, fontSize: 14, fontWeight: FontWeight.w900))),
        SizedBox(height: 118,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final v = items[i];
              final url = (v['logo'] as String?) ?? '';
              final rating = (v['rating'] as num?)?.toDouble();
              final name = v['name']?.toString() ?? '';
              return GestureDetector(
                onTap: () => UellowRouter.goVendor(context, (v['id'] as num).toInt()),
                child: Container(
                  width: 100,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white, borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: t.dark.withValues(alpha: 0.08)),
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Container(width: 48, height: 48,
                      decoration: BoxDecoration(
                        color: t.primary.withValues(alpha: 0.2),
                        shape: BoxShape.circle),
                      clipBehavior: Clip.antiAlias,
                      child: url.isNotEmpty
                          ? CachedNetworkImage(imageUrl: url, fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => Center(child: Text(
                                  (name.isNotEmpty ? name[0] : '?').toUpperCase(),
                                  style: TextStyle(color: t.dark,
                                      fontSize: 18, fontWeight: FontWeight.w900))))
                          : Center(child: Text((name.isNotEmpty ? name[0] : '?').toUpperCase(),
                              style: TextStyle(color: t.dark,
                                  fontSize: 18, fontWeight: FontWeight.w900)))),
                    const SizedBox(height: 4),
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: t.dark,
                            fontSize: 11, fontWeight: FontWeight.w700)),
                    if (rating != null && rating > 0) ...[
                      const SizedBox(height: 2),
                      Text('★ ${rating.toStringAsFixed(1)}',
                          style: TextStyle(color: t.primary.withValues(alpha: 0.9),
                              fontSize: 10, fontWeight: FontWeight.w800)),
                    ],
                  ]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class _LoyaltyBlock extends StatelessWidget {
  const _LoyaltyBlock({required this.p, required this.t, required this.ar, required this.wallet});
  final Map<String, dynamic> p;
  final DynTheme t;
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
              : LinearGradient(colors: [t.dark, DynTheme._hex('#6B3A05', t.dark)]),
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
  final DynTheme t;
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
  final DynTheme t;
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
  final DynTheme t;
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
  final DynTheme t;
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
  final DynTheme t;
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
  final DynTheme t;
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
  final DynTheme t;
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

// ─── FLASH SALE BLOCK — 4 design variants ──────────────────────────────────

class _FlashBlock extends StatelessWidget {
  const _FlashBlock({required this.p, required this.data, required this.t, required this.ar});
  final Map<String, dynamic> p;
  final Map<String, dynamic> data;
  final DynTheme t;
  final bool ar;

  @override
  Widget build(BuildContext context) {
    final variant = (p['variant'] as String?) ?? 'classic';
    final raw = ((data['items'] as List?) ?? const []).cast<dynamic>()
        .map((e) => (e as Map).cast<String, dynamic>()).toList();
    if (raw.isEmpty) return const SizedBox.shrink();
    // Convert resolved maps into real UellowProductCard so we can reuse
    // the shared ProductCard widget across variants.
    final items = raw.map((m) {
      try { return UellowProductCard.fromJson(m); }
      catch (_) { return null; }
    }).whereType<UellowProductCard>().toList();
    if (items.isEmpty) return const SizedBox.shrink();
    final endsAt = _parseEndsAt(p['ends_at']);
    final title = _tx(p, ar, 'title', ar ? 'فلاش سيل' : 'Flash Sale');
    switch (variant) {
      case 'dark':    return _FlashDark(items: items, title: title, ar: ar, endsAt: endsAt);
      case 'minimal': return _FlashMinimal(items: items, title: title, ar: ar, endsAt: endsAt);
      case 'hero':    return _FlashHero(items: items, title: title, ar: ar, endsAt: endsAt);
      case 'classic':
      default:        return _FlashClassic(items: items, title: title, ar: ar, endsAt: endsAt);
    }
  }

  static Duration _parseEndsAt(dynamic v) {
    if (v is String && v.isNotEmpty) {
      final dt = DateTime.tryParse(v);
      if (dt != null) {
        final diff = dt.difference(DateTime.now());
        if (diff.inSeconds > 0) return diff;
      }
    }
    return const Duration(days: 1, hours: 4, minutes: 35);
  }
}

// ── Variant: CLASSIC (the legacy yellow/orange one) ────────────────────────

class _FlashClassic extends StatelessWidget {
  const _FlashClassic({required this.items, required this.title, required this.ar, required this.endsAt});
  final List<UellowProductCard> items;
  final String title;
  final bool ar;
  final Duration endsAt;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, Routes.flash),
      child: Container(
        margin: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [BoxShadow(
              color: Color(0x29F5A800), blurRadius: 18, offset: Offset(0, 6))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(children: [
          Positioned.fill(child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [Color(0xFFFFD340), Color(0xFFF59E0B), Color(0xFFEA580C)],
                stops: [0.0, 0.55, 1.0],
              ),
            ),
          )),
          Positioned.fill(child: IgnorePointer(child: CustomPaint(
            painter: _DiagonalStripes(),
          ))),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.flash_on, color: Colors.white, size: 16),
                const SizedBox(width: 4),
                Text(title, style: const TextStyle(color: Colors.white,
                    fontSize: 13, fontWeight: FontWeight.w900,
                    letterSpacing: 0.2)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: const [BoxShadow(
                        color: Color(0x33000000), blurRadius: 3,
                        offset: Offset(0, 1))],
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(ar ? 'المزيد' : 'See more',
                        style: const TextStyle(color: Color(0xFFEA580C),
                            fontSize: 9.5, fontWeight: FontWeight.w900,
                            letterSpacing: 0.2)),
                    const SizedBox(width: 1),
                    Icon(ar ? Icons.chevron_left : Icons.chevron_right,
                        size: 12, color: const Color(0xFFEA580C)),
                  ]),
                ),
                const Spacer(),
                _DhmsCounter(initial: endsAt),
              ]),
              const SizedBox(height: 10),
              SizedBox(height: 216,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => SizedBox(
                      width: 138,
                      child: ProductCard(product: items[i], inFlashSale: true)),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ── Variant: DARK — premium black/neon ────────────────────────────────────

class _FlashDark extends StatelessWidget {
  const _FlashDark({required this.items, required this.title, required this.ar, required this.endsAt});
  final List<UellowProductCard> items;
  final String title;
  final bool ar;
  final Duration endsAt;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, Routes.flash),
      child: Container(
        margin: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFF0F0F0F), Color(0xFF1A1A1A), Color(0xFF2A0F00)],
          ),
          boxShadow: const [BoxShadow(
              color: Color(0x66FF4500), blurRadius: 22, offset: Offset(0, 8))],
        ),
        clipBehavior: Clip.antiAlias,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFD340), Color(0xFFEA580C)]),
                borderRadius: BorderRadius.circular(6),
                boxShadow: [BoxShadow(
                    color: const Color(0xFFFFD340).withValues(alpha: 0.6),
                    blurRadius: 12)],
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.flash_on, color: Colors.black, size: 14),
                SizedBox(width: 2),
                Text('FLASH', style: TextStyle(color: Colors.black,
                    fontSize: 11, fontWeight: FontWeight.w900,
                    letterSpacing: 1.2)),
              ]),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: const TextStyle(
                color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900))),
            _DhmsCounter(initial: endsAt, dark: true),
          ]),
          const SizedBox(height: 12),
          SizedBox(height: 220,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => SizedBox(
                  width: 138,
                  child: ProductCard(product: items[i], inFlashSale: true)),
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Variant: MINIMAL — clean, red accents ─────────────────────────────────

class _FlashMinimal extends StatelessWidget {
  const _FlashMinimal({required this.items, required this.title, required this.ar, required this.endsAt});
  final List<UellowProductCard> items;
  final String title;
  final bool ar;
  final Duration endsAt;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 8, 0, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFC0392B),
                borderRadius: BorderRadius.circular(4)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.flash_on, color: Colors.white, size: 12),
                SizedBox(width: 2),
                Text('FLASH', style: TextStyle(color: Colors.white,
                    fontSize: 10, fontWeight: FontWeight.w900,
                    letterSpacing: 0.8)),
              ]),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w900,
                color: Color(0xFF1F1206)))),
            _DhmsCounter(initial: endsAt, minimal: true),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => Navigator.pushNamed(context, Routes.flash),
              style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFC0392B),
                  textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  minimumSize: const Size(40, 28)),
              child: Text(ar ? 'الكل ←' : 'See all →'),
            ),
          ])),
        SizedBox(height: 220,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => SizedBox(
                width: 138,
                child: ProductCard(product: items[i], inFlashSale: true)),
          ),
        ),
      ]),
    );
  }
}

// ── Variant: HERO — full-bleed single-product spotlight ───────────────────

class _FlashHero extends StatefulWidget {
  const _FlashHero({required this.items, required this.title, required this.ar, required this.endsAt});
  final List<UellowProductCard> items;
  final String title;
  final bool ar;
  final Duration endsAt;
  @override
  State<_FlashHero> createState() => _FlashHeroState();
}

class _FlashHeroState extends State<_FlashHero> {
  final _ctrl = PageController(viewportFraction: 0.92);
  int _i = 0;
  Timer? _auto;
  @override
  void initState() {
    super.initState();
    _auto = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_ctrl.hasClients || widget.items.length < 2) return;
      _i = (_i + 1) % widget.items.length;
      _ctrl.animateToPage(_i, duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut);
    });
  }
  @override
  void dispose() { _auto?.cancel(); _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      height: 260,
      child: PageView.builder(
        controller: _ctrl,
        onPageChanged: (i) => setState(() => _i = i),
        itemCount: widget.items.length,
        itemBuilder: (_, i) {
          final p = widget.items[i];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: GestureDetector(
              onTap: () => UellowRouter.goProduct(context, p.id),
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [Color(0xFFC0392B), Color(0xFFF59E0B), Color(0xFFFFD340)],
                  ),
                  boxShadow: const [BoxShadow(
                      color: Color(0x44C0392B), blurRadius: 18,
                      offset: Offset(0, 6))],
                ),
                child: Stack(children: [
                  // Product image, full-bleed right side
                  Positioned(right: -20, top: 20, bottom: 20, width: 200,
                    child: CachedNetworkImage(
                      imageUrl: p.image,
                      fit: BoxFit.contain,
                      errorWidget: (_, __, ___) =>
                          const Icon(Icons.shopping_bag, color: Colors.white70, size: 80),
                    ),
                  ),
                  // Content overlay
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20)),
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.flash_on, color: Color(0xFFC0392B), size: 14),
                            SizedBox(width: 2),
                            Text('FLASH',
                                style: TextStyle(color: Color(0xFFC0392B),
                                    fontSize: 11, fontWeight: FontWeight.w900,
                                    letterSpacing: 0.8)),
                          ]),
                        ),
                        const Spacer(),
                        _DhmsCounter(initial: widget.endsAt),
                      ]),
                      // Product name + price
                      SizedBox(width: 200, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p.name.current(widget.ar ? 'ar' : 'en'),
                            maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white,
                                fontSize: 18, fontWeight: FontWeight.w900,
                                height: 1.2,
                                shadows: [Shadow(color: Colors.black54, blurRadius: 6)])),
                        const SizedBox(height: 6),
                        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text(p.price.format(),
                              style: const TextStyle(color: Colors.white,
                                  fontSize: 22, fontWeight: FontWeight.w900,
                                  shadows: [Shadow(color: Colors.black54, blurRadius: 6)])),
                          if (p.comparePrice != null) ...[
                            const SizedBox(width: 6),
                            Text(p.comparePrice!.format(),
                                style: const TextStyle(color: Colors.white70,
                                    fontSize: 13, fontWeight: FontWeight.w600,
                                    decoration: TextDecoration.lineThrough)),
                          ],
                        ]),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20)),
                          child: Text(widget.ar ? 'تسوّق الآن ←' : 'Shop now →',
                              style: const TextStyle(color: Color(0xFFC0392B),
                                  fontSize: 12, fontWeight: FontWeight.w900)),
                        ),
                      ])),
                    ]),
                  ),
                  // Slide indicators
                  Positioned(bottom: 8, left: 0, right: 0,
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children:
                      List.generate(widget.items.length, (k) => Container(
                        width: k == _i ? 18 : 6, height: 4,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: k == _i ? Colors.white : Colors.white54,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      )))),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Shared DHMS countdown cell ────────────────────────────────────────────

class _DhmsCounter extends StatefulWidget {
  const _DhmsCounter({required this.initial, this.dark = false, this.minimal = false});
  final Duration initial;
  final bool dark;
  final bool minimal;
  @override
  State<_DhmsCounter> createState() => _DhmsCounterState();
}

class _DhmsCounterState extends State<_DhmsCounter> {
  Timer? _t;
  late Duration _left;
  @override
  void initState() {
    super.initState();
    _left = widget.initial;
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _left = _left.inSeconds > 0
            ? _left - const Duration(seconds: 1)
            : const Duration(days: 1);
      });
    });
  }
  @override
  void dispose() { _t?.cancel(); super.dispose(); }
  String _two(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final d = _left.inDays;
    final h = _left.inHours.remainder(24);
    final m = _left.inMinutes.remainder(60);
    final s = _left.inSeconds.remainder(60);
    if (widget.minimal) {
      // Inline H:M:S, no boxes
      return Text('${_two(h)}:${_two(m)}:${_two(s)}',
          style: const TextStyle(color: Color(0xFFC0392B),
              fontSize: 12.5, fontWeight: FontWeight.w900,
              fontFeatures: [FontFeature.tabularFigures()]));
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _cell(_two(d), 'D'), const SizedBox(width: 3),
      _cell(_two(h), 'H'), const SizedBox(width: 3),
      _cell(_two(m), 'M'), const SizedBox(width: 3),
      _cell(_two(s), 'S'),
    ]);
  }
  Widget _cell(String v, String u) => Container(
    width: 22, height: 24, alignment: Alignment.center,
    decoration: BoxDecoration(
      color: widget.dark ? const Color(0xFFFFD340) : const Color(0xCC000000),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text(v, style: TextStyle(
          color: widget.dark ? Colors.black : Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 11, height: 1, fontFamily: 'monospace')),
      Text(u, style: TextStyle(
          color: (widget.dark ? Colors.black : Colors.white).withValues(alpha: 0.7),
          fontSize: 7, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
    ]),
  );
}

/// Diagonal-stripe pattern painter (matches the legacy flash sale bg).
class _DiagonalStripes extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x14FFFFFF)
      ..strokeWidth = 6;
    final spacing = 18.0;
    for (var x = -size.height.toDouble(); x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0),
          Offset(x + size.height, size.height), paint);
    }
  }
  @override
  bool shouldRepaint(covariant _) => false;
}
