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
import '../widgets/flash_banner.dart' show BannerPattern;
import '../widgets/product_card.dart';
import 'dynamic_block_extras.dart';
import 'promo_page_blocks.dart';

class DynamicPageScreen extends StatefulWidget {
  const DynamicPageScreen({super.key, required this.slug});
  final String slug;

  @override
  State<DynamicPageScreen> createState() => _DynamicPageScreenState();
}

class _DynamicPageScreenState extends State<DynamicPageScreen>
    with AutomaticKeepAliveClientMixin {
  late Future<Map<String, dynamic>> _future;

  // Keep this page alive across nav so we don't refetch when user comes back.
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<Map<String, dynamic>> _fetch() async {
    final api = UellowApi.instance;
    // Cache-buster query keeps Cloudflare/HTTP cache from serving stale
    // JSON when the user just hit Publish in the builder.
    final url = Uri.parse(
        '${api.baseUrl}/api/mobile/v2/pages/${widget.slug}'
        '?_t=${DateTime.now().millisecondsSinceEpoch}');
    final res = await http.get(url, headers: {
      'Accept': 'application/json',
      'X-Lang': api.lang,
      'Cache-Control': 'no-cache',
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
    super.build(context); // AutomaticKeepAliveClientMixin
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
                Text(UellowApi.instance.lang == 'ar' ? 'الصفحة غير متاحة' : 'Page not available',
                    style: const TextStyle(fontWeight: FontWeight.w900)),
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
          // Cache off-screen blocks so they don't rebuild on every scroll —
          // big perf win when the page has many image-heavy blocks.
          cacheExtent: 800,
          addAutomaticKeepAlives: false,
          addRepaintBoundaries: true,
          physics: const ClampingScrollPhysics(),
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
  Widget inner;
  switch (kind) {
    case 'hero':       inner = _Hero(p: p, t: t, ar: ar); break;
    case 'carousel':   inner = _CarouselBlock(p: p, data: data, t: t, ar: ar); break;
    case 'searchbar':  inner = _SearchBarBlock(p: p, t: t, ar: ar); break;
    case 'countdown':  inner = _CountdownBlock(p: p, t: t, ar: ar); break;
    case 'cats-grid':
    case 'cats-strip': inner = _CategoriesBlock(p: p, data: data, t: t, ar: ar); break;
    case 'flash':      inner = _FlashBlock(p: p, data: data, t: t, ar: ar); break;
    case 'products':
    case 'rec-ai':
    case 'recent':
    case 'grid':       inner = _ProductsBlock(p: p, data: data, t: t, ar: ar, kind: kind); break;
    // v2.1.45 — dedicated premium Bestsellers block (podium + ranked list).
    case 'bestsellers': inner = BestsellersBlock(p: p, data: data, t: t, ar: ar); break;
    case 'banner-1':   inner = _Banner1(p: p, t: t, ar: ar); break;
    case 'banner-2':   inner = _BannerMulti(p: p, t: t, columns: 2); break;
    case 'banner-3':   inner = _BannerMulti(p: p, t: t, columns: 3); break;
    case 'vendors':
    case 'vendor-feat':inner = _VendorsBlock(p: p, data: data, t: t, ar: ar); break;
    case 'loyalty':    inner = _LoyaltyBlock(p: p, t: t, ar: ar, wallet: false); break;
    case 'wallet':     inner = _LoyaltyBlock(p: p, t: t, ar: ar, wallet: true); break;
    case 'coupons':    inner = _CouponsBlock(p: p, t: t, ar: ar); break;
    case 'newsletter': inner = _NewsletterBlock(p: p, t: t, ar: ar); break;
    case 'app-promo':  inner = _AppPromoBlock(p: p, t: t, ar: ar); break;
    case 'beena':      inner = _BeenaBlock(p: p, t: t, ar: ar); break;
    case 'reviews':    inner = _ReviewsBlock(p: p, t: t, ar: ar); break;
    case 'text':       inner = _TextBlock(p: p, t: t, ar: ar); break;
    case 'video':      inner = _VideoBlock(p: p, t: t); break;
    case 'spacer':     return const SizedBox(height: 16);
    case 'divider':    return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Divider(height: 1));
    // v2.0.34 new block kinds
    case 'quick-pills':    inner = QuickPillsBlock(p: p, data: data, t: t, ar: ar); break;
    case 'promo-pills':    inner = PromoPillsBlock(p: p, t: t, ar: ar); break;
    case 'themed-promo':   inner = ThemedPromoBlock(p: p, t: t, ar: ar); break;
    case 'mini-cats':      inner = MiniCategoryCardsBlock(p: p, data: data, t: t, ar: ar); break;
    case 'welcome-deal':   inner = WelcomeDealBlock(p: p, data: data, t: t, ar: ar); break;
    case 'discount-strip': inner = DiscountStripBlock(p: p, data: data, t: t, ar: ar); break;
    case 'pill-filter':    inner = PillFilterBlock(p: p, t: t, ar: ar); break;
    // v2.0.36 — Explore More
    case 'explore-more':
      // v2.1.56 — no trailing gap below the Load-more button.
      if (p['pad_bottom'] == null) p['pad_bottom'] = 0;
      inner = ExploreMoreBlock(p: p, data: data, t: t, ar: ar);
      break;
    // v2.0.38 — Slider + 5 pro designs
    case 'slider':         inner = SliderBlock(p: p, t: t, ar: ar); break;
    case 'tab-nav':
      // v2.0.67 — tab-nav defaults to ZERO vertical padding so it sits
      // flush beneath the search bar. Admin can still bump via pad_y.
      if (p['pad_y'] == null) p['pad_y'] = 0;
      inner = TabNavBlock(p: p, t: t, ar: ar);
      break;
    case 'image-banner':   inner = ImageBannerBlock(p: p, t: t, ar: ar); break;
    case 'reels-strip':    inner = ReelsStripBlock(p: p, data: data, t: t, ar: ar); break;
    case 'occasion-header': inner = OccasionHeaderBlock(p: p, t: t, ar: ar); break;
    case 'story-bubbles':  inner = StoryBubblesBlock(p: p, t: t, ar: ar); break;
    case 'lookbook':       inner = LookbookBlock(p: p, t: t, ar: ar); break;
    case 'sticky-cta':     inner = StickyCtaBlock(p: p, t: t, ar: ar); break;
    // v2.1.57 — conversion blocks
    case 'new-user':       inner = NewUserBlock(p: p, data: data, t: t, ar: ar); break;
    // v2.1.75 — 5 promo-section presets share one flexible engine.
    case 'promo-spotlight':
    case 'promo-category':
    case 'promo-rank':
    case 'promo-arrivals':
    case 'promo-mega':
      inner = PromoSectionBlock(
          variant: kind.replaceFirst('promo-', ''),
          p: p, data: data, t: t, ar: ar); break;
    case 'trust-strip':    inner = TrustStripBlock(p: p, t: t, ar: ar); break;
    // v2.2.06 — PROMOTION PAGE blocks (10 designs, see promo_page_blocks).
    case 'promo-hero':
      // full-bleed: kill the envelope side padding by default
      if (p['pad_x'] == null) p['pad_x'] = 0;
      if (p['pad_y'] == null) p['pad_y'] = 0;
      inner = Builder(builder: (ctx) => PromoHeroBlock(p: p, data: data,
          ar: ar, onCta: () {
        final l = (p['link'] as Map?)?.cast<String, dynamic>();
        if (l != null) openBlockLink(ctx, l);
      })); break;
    case 'promo-countdown':  inner = PromoCountdownBlock(p: p, data: data, ar: ar); break;
    case 'promo-carousel':   inner = PromoCarouselBlock(p: p, data: data, ar: ar); break;
    case 'promo-mega2':      inner = PromoMegaGridBlock(p: p, data: data, ar: ar); break;
    case 'promo-flash-rail': inner = PromoFlashRailBlock(p: p, data: data, ar: ar); break;
    case 'promo-masonry':    inner = PromoMasonryBlock(p: p, data: data, ar: ar); break;
    case 'promo-coupon':     inner = PromoCouponBlock(p: p, data: data, ar: ar); break;
    case 'promo-tiers':      inner = PromoTiersBlock(p: p, data: data, ar: ar); break;
    case 'promo-marquee':
      if (p['pad_x'] == null) p['pad_x'] = 0;
      inner = PromoMarqueeBlock(p: p, ar: ar); break;
    case 'promo-banner-cta':
      inner = Builder(builder: (ctx) => PromoBannerCtaBlock(p: p, data: data, ar: ar,
          onTap: () {
        final l = (p['link'] as Map?)?.cast<String, dynamic>();
        if (l != null) openBlockLink(ctx, l);
      })); break;
    case 'promo-showcase':
      inner = PromoShowcaseBlock(p: p, data: data, ar: ar); break;
    case 'new-customer-zone':
      inner = NewCustomerZoneBlock(p: p, data: data, ar: ar); break;
    default:               return const SizedBox.shrink();
  }
  return BlockEnvelope(props: p, theme: t, child: inner);
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
  // v2.0.34: a block can opt out of showing its title via {"show_title": false}.
  // We honor that here so all existing renderers (which already do
  // `if (title.isNotEmpty) ...`) drop the title strip without per-block edits.
  if (key == 'title' && p['show_title'] == false) return '';
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
    final imgUrl = pickLocalizedImage(p, ar);
    return GestureDetector(
      onTap: () => _openLink(context, link),
      child: Container(
        margin: blockMargin(p),
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
          // v2.2.17 — overlay configurable (overlay_color/overlay_opacity);
          // default keeps the bottom legibility gradient.
          if (imgUrl.isNotEmpty && blockOverlayCustom(p))
            Container(color: blockOverlay(p) ?? Colors.transparent)
          else if (imgUrl.isNotEmpty)
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
        physics: const ClampingScrollPhysics(),
        controller: _ctrl,
        onPageChanged: (i) => setState(() => _i = i),
        itemCount: slides.length,
        itemBuilder: (_, i) {
          final s = (slides[i] as Map).cast<String, dynamic>();
          final url = pickLocalizedImage(s, widget.ar);
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
        // v2.0.67 — minimal bottom margin so a Tab-Nav block immediately
        // below the search bar sits flush (the user wanted zero gap).
        margin: blockMargin(p, 14, 8, 14, 2),
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
      margin: blockMargin(widget.p),
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

// ─── Categories Block — v2.0.61 PRO: 4 layouts, 4 shapes, spacing options ─
//
// Layouts:
//   strip        — original single-row horizontal scroll
//   grid         — fixed N-column grid, no scroll, all fits
//   grid_2row    — 2-row horizontal scroll (great for 10+ categories)
//   staggered    — mixed sizes (every 3rd item is larger)
//
// Per-item soft colors cycle through a friendly palette when `colored_bg`
// is on. Product-count badges read from cat['product_count'] if present.
class _CategoriesBlock extends StatelessWidget {
  const _CategoriesBlock({required this.p, required this.data, required this.t, required this.ar});
  final Map<String, dynamic> p;
  final Map<String, dynamic> data;
  final DynTheme t;
  final bool ar;

  static const _palette = [
    Color(0xFFFFE9D6), Color(0xFFD6F5E2), Color(0xFFD8E8F5),
    Color(0xFFF5D8E8), Color(0xFFEEE8D8), Color(0xFFFFE5D6),
    Color(0xFFE0F2EA), Color(0xFFFFE9F3),
  ];

  @override
  Widget build(BuildContext context) {
    final title = _tx(p, ar, 'title', ar ? 'تسوّق حسب الفئة' : 'Shop by category');
    final items = ((data['items'] as List?) ?? const []).cast<dynamic>()
        .map((e) => (e as Map).cast<String, dynamic>()).toList();
    if (items.isEmpty) return const SizedBox.shrink();

    final layout = (p['layout'] as String?) ?? 'strip';
    final columns = int.tryParse((p['columns'] ?? '4').toString()) ?? 4;
    final iconSize = ((p['icon_size'] as num?)?.toDouble() ?? 56).clamp(36, 100).toDouble();
    final gap = ((p['gap'] as num?)?.toDouble() ?? 10).clamp(4, 24).toDouble();
    final showLabel = p['show_label'] != false;
    final labelPos = (p['label_position'] as String?) ?? 'below';
    final coloredBg = p['colored_bg'] == true;
    final showRing = p['show_ring'] != false;
    final showCount = p['show_count'] == true;
    final shape = (p['shape'] as String?) ?? 'circle';
    final showArrows = p['show_arrows'] == true;
    final scrollSnap = p['scroll_snap'] == true;
    final animateIn = p['animate_in'] == true;
    final showTitle = (p['show_title'] != false) && title.isNotEmpty;

    // v2.1.56 — free tile color from the builder (`tile_bg` hex). When
    // unset: palette if colored_bg else neutral GRAY (was yellow tint).
    final customTileBg = (p['tile_bg'] is String &&
            (p['tile_bg'] as String).trim().isNotEmpty &&
            (p['tile_bg'] as String) != 'none')
        ? DynTheme._hex(p['tile_bg'], const Color(0xFFEFEFEF))
        : null;

    Widget itemTile(Map<String, dynamic> cat, int idx) {
      final url = (cat['icon_url'] as String?) ?? '';
      final name = cat['name']?.toString() ?? '';
      final count = (cat['product_count'] as num?)?.toInt() ?? 0;
      final bg = customTileBg ??
          (coloredBg
              ? _palette[idx % _palette.length]
              : const Color(0xFFEFEFEF));
      final borderC = showRing
          ? t.primary.withValues(alpha: 0.30)
          : Colors.transparent;

      BoxDecoration deco;
      double iconRadius;
      switch (shape) {
        case 'square':
          deco = BoxDecoration(color: bg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: borderC));
          iconRadius = 8;
          break;
        case 'rounded':
          deco = BoxDecoration(color: bg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderC));
          iconRadius = 16;
          break;
        case 'capsule':
          deco = BoxDecoration(color: bg,
              borderRadius: BorderRadius.circular(iconSize / 2),
              border: Border.all(color: borderC));
          iconRadius = iconSize / 2;
          break;
        default: // circle
          deco = BoxDecoration(color: bg, shape: BoxShape.circle,
              border: Border.all(color: borderC));
          iconRadius = iconSize / 2;
      }
      final iconWidth = shape == 'capsule' ? iconSize * 0.72 : iconSize;
      final iconHeight = shape == 'capsule' ? iconSize * 1.1 : iconSize;

      Widget icon = Container(
        width: iconWidth, height: iconHeight,
        decoration: deco,
        clipBehavior: Clip.antiAlias,
        child: Stack(fit: StackFit.expand, children: [
          if (url.isNotEmpty)
            CachedNetworkImage(imageUrl: url, fit: BoxFit.cover,
              errorWidget: (_, __, ___) => Icon(Icons.category,
                  color: t.dark.withValues(alpha: 0.5)))
          else
            Icon(Icons.category, color: t.dark.withValues(alpha: 0.5)),
          if (labelPos == 'overlay')
            Container(decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(iconRadius),
              gradient: LinearGradient(begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withValues(alpha: 0.55)]))),
          if (labelPos == 'overlay' && showLabel)
            Positioned(left: 4, right: 4, bottom: 4, child: Text(name,
                textAlign: TextAlign.center, maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 10,
                    fontWeight: FontWeight.w800, height: 1.1))),
          if (showCount && count > 0)
            Positioned(top: -2, right: -2, child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(color: t.dark,
                  borderRadius: BorderRadius.circular(8)),
              child: Text('$count',
                  style: const TextStyle(color: Colors.white, fontSize: 9,
                      fontWeight: FontWeight.w900)),
            )),
        ]),
      );

      final tile = GestureDetector(
        onTap: () => UellowRouter.goCollection(context, (cat['id'] as num).toInt()),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          icon,
          if (showLabel && labelPos != 'overlay') ...[
            const SizedBox(height: 4),
            Text(name, textAlign: TextAlign.center,
                maxLines: 2, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: t.dark, fontSize: 10.5, height: 1.15,
                    fontWeight: FontWeight.w600)),
          ],
        ]),
      );
      // Subtle stagger fade-in
      if (!animateIn) return tile;
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 250 + (idx * 60).clamp(0, 1200)),
        curve: Curves.easeOut,
        builder: (_, v, child) => Opacity(opacity: v,
            child: Transform.translate(offset: Offset(0, (1 - v) * 6), child: child)),
        child: tile,
      );
    }

    Widget body;
    switch (layout) {
      case 'grid': {
        body = Padding(padding: EdgeInsets.symmetric(horizontal: gap),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: gap, mainAxisSpacing: gap,
                childAspectRatio: showLabel ? 0.78 : 1.0),
            itemCount: items.length,
            itemBuilder: (_, i) => itemTile(items[i], i),
          ));
        break;
      }
      case 'grid_2row': {
        // Two-row horizontal scroll: split items pairwise into columns.
        final pairs = <List<Map<String, dynamic>>>[];
        for (int i = 0; i < items.length; i += 2) {
          pairs.add([items[i], if (i + 1 < items.length) items[i + 1]]);
        }
        body = SizedBox(
          height: (iconSize * 2) + (showLabel ? 50 : 14) + gap,
          child: ListView.separated(
            physics: scrollSnap
                ? const PageScrollPhysics()
                : const ClampingScrollPhysics(),
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: gap + 4),
            itemCount: pairs.length,
            separatorBuilder: (_, __) => SizedBox(width: gap),
            itemBuilder: (_, col) {
              final pair = pairs[col];
              return Column(mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  itemTile(pair[0], col * 2),
                  SizedBox(height: gap),
                  if (pair.length > 1) itemTile(pair[1], col * 2 + 1),
                ]);
            },
          ));
        break;
      }
      case 'staggered': {
        body = Padding(padding: EdgeInsets.symmetric(horizontal: gap),
          child: Wrap(spacing: gap, runSpacing: gap, children: [
            for (int i = 0; i < items.length; i++)
              SizedBox(width: (i % 5 == 0) ? iconSize + 28 : iconSize + 10,
                  child: itemTile(items[i], i)),
          ]));
        break;
      }
      default: { // strip — original horizontal scroll
        body = SizedBox(
          height: iconSize + (showLabel ? 32 : 4),
          child: ListView.separated(
            physics: scrollSnap
                ? const PageScrollPhysics()
                : const ClampingScrollPhysics(),
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: gap + 4),
            itemCount: items.length,
            separatorBuilder: (_, __) => SizedBox(width: gap),
            itemBuilder: (_, i) => SizedBox(width: iconSize + 14,
                child: itemTile(items[i], i)),
          ));
      }
    }

    // v2.0.71 — use DynSectionHeader so header_icon + banner mode work here.
    final arrows = (showArrows && layout != 'grid')
        ? Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 28, height: 28,
                decoration: BoxDecoration(
                    color: t.primary.withValues(alpha: 0.15),
                    shape: BoxShape.circle),
                child: Icon(ar ? Icons.chevron_right : Icons.chevron_left,
                    color: t.dark, size: 18)),
            const SizedBox(width: 6),
            Container(width: 28, height: 28,
                decoration: BoxDecoration(
                    color: t.primary.withValues(alpha: 0.15),
                    shape: BoxShape.circle),
                child: Icon(ar ? Icons.chevron_left : Icons.chevron_right,
                    color: t.dark, size: 18)),
          ])
        : null;
    return Container(
      margin: blockMargin(p, 0, 8, 0, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (showTitle)
          DynSectionHeader(
            props: p, theme: t, ar: ar,
            fallbackEn: ar ? 'تسوّق حسب الفئة' : 'Shop by category',
            trailing: arrows,
          ),
        body,
      ]),
    );
  }
}

// ─── PRODUCTS BLOCK — v2.0.68 PRO ────────────────────────────────────────────
//   6 layout variants (carousel / grid_2 / grid_3 / spotlight / tall_split / masonry)
//   Fixes name-as-Map bug (was rendering "{en: foo, ar: bar}").
//   Per-block design options: card_style, card_radius, accent, show_rating,
//   show_save_badge, show_wishlist, show_compare_price, show_brand, name_lines,
//   price_emphasis, quick_add.
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
    final showHeader = title.isNotEmpty;
    // Default variant: kind='grid' → grid_2; everything else → carousel.
    final variant = (p['variant'] as String?) ??
        (kind == 'grid' ? 'grid_2' : 'carousel');

    Widget body;
    switch (variant) {
      case 'grid_2':     body = _grid(items, cols: 2); break;
      case 'grid_3':     body = _grid(items, cols: 3); break;
      case 'spotlight':  body = _spotlight(items); break;
      case 'tall_split': body = _tallSplit(items); break;
      case 'masonry':    body = _masonry(items); break;
      default:           body = _carousel(items);
    }

    // v2.0.71 — use DynSectionHeader so header_icon + banner mode work here.
    final seeAll = TextButton(
      onPressed: () => Navigator.pushNamed(context,
          kind == 'flash' ? Routes.flash : Routes.category),
      style: TextButton.styleFrom(
          foregroundColor: t.primary,
          textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          minimumSize: const Size(40, 28)),
      child: Text(ar ? 'الكل ←' : 'See all →'),
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (showHeader)
        DynSectionHeader(
          props: p, theme: t, ar: ar,
          fallbackEn: _fallbackTitle(kind, false),
          trailing: seeAll,
        ),
      body,
    ]);
  }

  // v2.2.11 — per-element display map from the builder (b.props.card).
  CardDisplay get _display => CardDisplay.fromMap(p['card'] as Map?);

  // v2.1.33 — carousel + grid_2 (incl. Bestsellers) render the SAME
  // rich card as the category page. grid_3 stays compact (too narrow).
  Widget _richCard(Map<String, dynamic> prod) {
    try {
      return ProductCard(rich: true,
          product: UellowProductCard.fromJson(prod), display: _display);
    } catch (_) {
      return _card(prod);
    }
  }

  Widget _carousel(List<Map<String, dynamic>> items) {
    // v2.1.56 — 300→278: the rail was taller than the rich card's
    // natural height (160 image + ~115 content), leaving an empty white
    // band at the bottom of every card (مقترحاتنا لك + carousels).
    // v2.1.62 — small breathing space UNDER the cards so they don't sit
    // flush against the block edge (free-delivery block on home etc.).
    return SizedBox(height: 286,
      child: ListView.separated(
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => SizedBox(width: 160, child: _richCard(items[i])),
      ));
  }

  Widget _grid(List<Map<String, dynamic>> items, {required int cols}) {
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 8, crossAxisSpacing: 8,
            childAspectRatio: cols == 3 ? 0.62 : 0.585),
        itemCount: items.length,
        itemBuilder: (_, i) => cols == 3
            ? _card(items[i], compact: true)
            : _richCard(items[i]),
      ));
  }

  Widget _spotlight(List<Map<String, dynamic>> items) {
    final hero = items.first;
    final tail = items.skip(1).take(4).toList();
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(children: [
        SizedBox(height: 260, child: _card(hero, hero: true)),
        const SizedBox(height: 8),
        if (tail.isNotEmpty) SizedBox(
          height: 152,
          child: ListView.separated(
            physics: const ClampingScrollPhysics(),
            scrollDirection: Axis.horizontal,
            itemCount: tail.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (_, i) => SizedBox(width: 100, child: _card(tail[i], compact: true)),
          )),
      ]));
  }

  Widget _tallSplit(List<Map<String, dynamic>> items) {
    if (items.length < 3) return _carousel(items);
    final left = items.take(2).toList();
    final right = items[2];
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SizedBox(height: 320,
        child: Row(children: [
          Expanded(child: Column(children: [
            Expanded(child: _card(left[0], compact: true)),
            const SizedBox(height: 8),
            Expanded(child: _card(left[1], compact: true)),
          ])),
          const SizedBox(width: 8),
          Expanded(child: _card(right, hero: true)),
        ])));
  }

  Widget _masonry(List<Map<String, dynamic>> items) {
    final left = <Map<String, dynamic>>[];
    final right = <Map<String, dynamic>>[];
    for (int i = 0; i < items.length; i++) {
      (i.isEven ? left : right).add(items[i]);
    }
    Widget col(List<Map<String, dynamic>> col, {required bool offset}) {
      return Column(children: [
        if (offset) const SizedBox(height: 20),
        for (int i = 0; i < col.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _card(col[i]),
        ],
      ]);
    }
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: col(left, offset: false)),
        const SizedBox(width: 8),
        Expanded(child: col(right, offset: true)),
      ]));
  }

  // ─── card builder (all variants funnel through here) ──────────────────────
  Widget _card(Map<String, dynamic> prod, {bool hero = false, bool compact = false}) {
    return _ProductCardPro(
      prod: prod, p: p, t: t, ar: ar, hero: hero, compact: compact,
    );
  }

  String _fallbackTitle(String k, bool ar) {
    switch (k) {
      case 'flash':       return ar ? '⚡ صفقات سريعة' : '⚡ Flash deals';
      case 'bestsellers': return ar ? 'الأكثر مبيعاً' : 'Bestsellers';
      case 'rec-ai':      return ar ? 'مقترحة لك' : 'Recommended for you';
      case 'recent':      return ar ? 'شاهدتها مؤخراً' : 'Recently viewed';
      case 'grid':        return ar ? 'منتجات مختارة' : 'Featured products';
      default:            return ar ? 'منتجات' : 'Products';
    }
  }
}

// Pull a bilingual product name out of the resolver shape:
//   {'name': {'en': '...', 'ar': '...'}}  OR  {'name': 'flat string'}
String _productName(Map<String, dynamic> prod, bool ar) {
  final n = prod['name'];
  if (n is Map) {
    final m = n.cast<String, dynamic>();
    final v = ar ? m['ar'] : m['en'];
    final s = v?.toString() ?? '';
    if (s.isNotEmpty) return s;
    return (m['en'] ?? m['ar'] ?? '').toString();
  }
  return n?.toString() ?? '';
}

class _ProductCardPro extends StatelessWidget {
  const _ProductCardPro({
    required this.prod, required this.p, required this.t, required this.ar,
    this.hero = false, this.compact = false,
  });
  final Map<String, dynamic> prod;
  final Map<String, dynamic> p;
  final DynTheme t;
  final bool ar;
  final bool hero, compact;

  @override
  Widget build(BuildContext context) {
    final price = (prod['price'] as Map?)?.cast<String, dynamic>();
    final compare = prod['compare_price'];
    final discount = (prod['discount_pct'] as num?)?.toInt() ?? 0;
    final url = (prod['image'] as String?) ?? '';
    final badges = ((prod['badges'] as List?) ?? const []).cast<dynamic>();
    final rating = (prod['rating'] as Map?)?.cast<String, dynamic>();
    final ratingAvg = (rating?['avg'] as num?)?.toDouble() ?? 0.0;
    final ratingCount = (rating?['count'] as num?)?.toInt() ?? 0;
    final priceAmt = (price?['amount'] as num?)?.toDouble() ?? 0;
    final compareAmt = (compare is Map ? compare['amount'] : compare) as num?;
    double saving = 0;
    if (compareAmt != null && compareAmt > priceAmt) saving = compareAmt - priceAmt;
    final name = _productName(prod, ar);
    final brand = ((prod['vendor'] as Map?)?.cast<String, dynamic>())?['name']?.toString();

    // Per-block design options
    final style = (p['card_style'] as String?) ?? 'shadow';
    final radius = ((p['card_radius'] as num?)?.toDouble() ?? 12).clamp(0, 32).toDouble();
    final accent = _hex(p['accent']) ?? const Color(0xFFC0392B);
    final showRating = p['show_rating'] != false;
    final showSave = p['show_save_badge'] != false;
    final showWish = p['show_wishlist'] != false;
    final showCompare = p['show_compare_price'] != false;
    final showBrand = p['show_brand'] == true && brand != null && brand.isNotEmpty;
    final nameLines = ((p['name_lines'] as num?)?.toInt() ?? 2).clamp(1, 3);
    final priceEm = (p['price_emphasis'] as String?) ?? 'medium';
    final showQuickAdd = p['quick_add'] == true;

    final priceFont = hero ? 18.0 : (priceEm == 'large' ? 16.0 : priceEm == 'small' ? 12.0 : 14.0);
    final nameFont  = hero ? 13.5 : (compact ? 10.5 : 11.5);

    BoxDecoration deco;
    switch (style) {
      case 'flat':
        deco = BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(radius));
        break;
      case 'outlined':
        deco = BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: t.dark.withValues(alpha: 0.10), width: 1));
        break;
      case 'minimal':
        deco = BoxDecoration(color: Colors.transparent, borderRadius: BorderRadius.circular(radius));
        break;
      case 'gradient':
        deco = BoxDecoration(
          gradient: const LinearGradient(
              colors: [Colors.white, Color(0xFFFFF6E0)],
              begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(radius));
        break;
      case 'shadow':
      default:
        deco = BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(radius),
          boxShadow: [BoxShadow(color: t.dark.withValues(alpha: 0.06), blurRadius: 6, offset: const Offset(0, 2))]);
    }

    return GestureDetector(
      onTap: () => UellowRouter.goProduct(context, (prod['id'] as num).toInt()),
      child: Container(
        decoration: deco,
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Stack(children: [
            Positioned.fill(child: url.isNotEmpty
                ? CachedNetworkImage(imageUrl: url, fit: BoxFit.cover,
                    placeholder: (_, __) => Container(color: t.primary.withValues(alpha: 0.06)),
                    errorWidget: (_, __, ___) => Container(
                        color: t.primary.withValues(alpha: 0.08),
                        child: Icon(Icons.broken_image_outlined, color: t.dark.withValues(alpha: 0.4))))
                : Container(color: t.primary.withValues(alpha: 0.08),
                    child: Icon(Icons.shopping_bag_outlined, color: t.dark.withValues(alpha: 0.4)))),
            if (discount > 0) Positioned(top: 6, left: 6, child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(4)),
              child: Text('-$discount%',
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900)),
            )),
            if (badges.isNotEmpty && !compact) Positioned(top: 6, right: 6, child: Wrap(
              spacing: 3, direction: Axis.vertical, children: [
                for (final b in badges.take(2))
                  if (b is Map) Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white, borderRadius: BorderRadius.circular(4),
                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2)],
                    ),
                    child: Text((b['label_en']?.toString() ?? '').split(' ').first,
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
                  ),
              ])),
            if (showWish) Positioned(bottom: 6,
              right: ar ? null : 6, left: ar ? 6 : null,
              child: Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: Colors.white, shape: BoxShape.circle,
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)],
                ),
                child: Icon(Icons.favorite_border, size: 15, color: t.dark),
              ),
            ),
            if (showQuickAdd) Positioned(bottom: 6,
              right: ar ? 6 : null, left: ar ? null : 6,
              child: Container(
                width: 28, height: 28,
                decoration: BoxDecoration(color: t.primary, shape: BoxShape.circle,
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)]),
                child: Icon(Icons.add_rounded, size: 18, color: t.dark),
              ),
            ),
          ])),
          Padding(
            padding: EdgeInsets.fromLTRB(8, compact ? 5 : 7, 8, compact ? 6 : 7),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              if (showBrand) Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(brand, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.dark.withValues(alpha: 0.55),
                        fontSize: compact ? 9 : 9.5, fontWeight: FontWeight.w700,
                        letterSpacing: 0.3)),
              ),
              Text(name, maxLines: nameLines, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: t.dark, fontSize: nameFont,
                      height: 1.2, fontWeight: FontWeight.w600)),
              SizedBox(height: compact ? 3 : 4),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Flexible(child: Text(
                  '${priceAmt.toStringAsFixed(price?['digits'] ?? 3)} ${price?['symbol'] ?? ''}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: t.dark, fontSize: priceFont, fontWeight: FontWeight.w900),
                )),
                if (showCompare && compareAmt != null && compareAmt > priceAmt) ...[
                  const SizedBox(width: 4),
                  Text('${compareAmt.toStringAsFixed(price?['digits'] ?? 3)}',
                      style: TextStyle(color: t.dark.withValues(alpha: 0.45),
                          fontSize: compact ? 9 : 10, fontWeight: FontWeight.w600,
                          decoration: TextDecoration.lineThrough)),
                ],
              ]),
              if (showSave && saving > 0) Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFFE6F7EF), Color(0xFFD4F0DD)]),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: const Color(0xFF1F8A40).withValues(alpha: 0.18), width: 0.6),
                  ),
                  child: Text('${ar ? 'وفر' : 'Save'} ${saving.toStringAsFixed(price?['digits'] ?? 3)} ${price?['symbol'] ?? ''}',
                      style: const TextStyle(color: Color(0xFF1F8A40),
                          fontSize: 9.5, fontWeight: FontWeight.w900)),
                ),
              ),
              if (showRating && (ratingAvg > 0 || ratingCount > 0)) Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(children: [
                  const Icon(Icons.star, size: 11, color: Color(0xFFFFC107)),
                  const SizedBox(width: 2),
                  Text(ratingAvg > 0 ? ratingAvg.toStringAsFixed(1) : '—',
                      style: TextStyle(fontSize: 10, color: t.dark, fontWeight: FontWeight.w700)),
                  if (ratingCount > 0) ...[
                    const SizedBox(width: 3),
                    Text('($ratingCount)',
                        style: TextStyle(fontSize: 9.5, color: t.dark.withValues(alpha: 0.5))),
                  ],
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Color? _hex(dynamic v) {
    if (v is! String) return null;
    final s = v.trim();
    if (s.isEmpty || s == 'transparent') return null;
    final hex = s.startsWith('#') ? s.substring(1) : s;
    if (RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)) {
      return Color(int.parse('FF$hex', radix: 16));
    }
    return null;
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
    final imgUrl = pickLocalizedImage(p, ar);
    return GestureDetector(
      onTap: () => _openLink(context, link),
      child: Container(
        margin: blockMargin(p),
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
          // v2.2.17 — configurable overlay (Style tab), default .35.
          if (imgUrl.isNotEmpty && blockOverlay(p, defOpacity: .35) != null)
            Container(color: blockOverlay(p, defOpacity: .35)),
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
      margin: blockMargin(p, 0, 8, 0, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(title, style: TextStyle(
              color: t.dark, fontSize: 14, fontWeight: FontWeight.w900))),
        SizedBox(height: 118,
          child: ListView.separated(
            physics: const ClampingScrollPhysics(),
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
        margin: blockMargin(p),
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
        margin: blockMargin(p),
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
      margin: blockMargin(p),
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
      margin: blockMargin(p),
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
        margin: blockMargin(p),
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
      margin: blockMargin(p),
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
      margin: blockMargin(p),
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
    // v2.1.37 — when the block is LINKED (flash sale or promotion), the
    // backend sends the live end-time + label in the resolved data; they
    // beat any manual props so the countdown is always the real one.
    final endsAt = _parseEndsAt(
        (data['flash_end_datetime'] ?? '').toString().isNotEmpty
            ? data['flash_end_datetime']
            : p['ends_at']);
    final linkedLabel = ((data['flash_label'] as Map?)?[ar ? 'ar' : 'en']
        ?? '').toString();
    final title = _tx(p, ar, 'title',
        linkedLabel.isNotEmpty
            ? linkedLabel
            : (ar ? 'فلاش سيل' : 'Flash Sale'));
    final display = CardDisplay.fromMap(p['card'] as Map?);
    switch (variant) {
      case 'dark':    return _FlashDark(items: items, title: title, ar: ar, endsAt: endsAt, onOpen: _open, display: display);
      case 'minimal': return _FlashMinimal(items: items, title: title, ar: ar, endsAt: endsAt, onOpen: _open, display: display);
      case 'hero':    return _FlashHero(items: items, title: title, ar: ar, endsAt: endsAt, onOpen: _open, display: display);
      // v2.1.36 — new promo designs:
      case 'royal':   return _FlashRoyal(items: items, title: title, ar: ar, endsAt: endsAt, onOpen: _open, display: display);
      case 'custom':  return _FlashCustom(items: items, title: title, ar: ar, endsAt: endsAt, p: p, onOpen: _open, display: display);
      case 'classic':
      default:        return _FlashClassic(items: items, title: title, ar: ar, endsAt: endsAt, onOpen: _open, display: display);
    }
  }

  // v2.1.40 — tap target: a builder-designed promotion PAGE (props.link
  // set from the builder) wins over the default /flash screen. So you can
  // design a campaign landing page and point this block at it.
  void _open(BuildContext context) {
    final l = (p['link'] as Map?)?.cast<String, dynamic>();
    if (l != null && (l['value'] ?? '').toString().isNotEmpty) {
      openBlockLink(context, l);
      return;
    }
    Navigator.pushNamed(context, Routes.flash);
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
  const _FlashClassic({required this.items, required this.title, required this.ar, required this.endsAt, required this.onOpen, this.display = const CardDisplay()});
  final List<UellowProductCard> items;
  final String title;
  final bool ar;
  final Duration endsAt;
  final void Function(BuildContext) onOpen;
  final CardDisplay display;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onOpen(context),
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
              SizedBox(height: 178,
                child: ListView.separated(
            physics: const ClampingScrollPhysics(),
                  scrollDirection: Axis.horizontal,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => SizedBox(
                      width: 124,
                      child: ProductCard(product: items[i], inFlashSale: true, display: display)),
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
  const _FlashDark({required this.items, required this.title, required this.ar, required this.endsAt, required this.onOpen, this.display = const CardDisplay()});
  final List<UellowProductCard> items;
  final String title;
  final bool ar;
  final Duration endsAt;
  final void Function(BuildContext) onOpen;
  final CardDisplay display;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onOpen(context),
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
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.flash_on, color: Colors.black, size: 14),
                const SizedBox(width: 2),
                Text(UellowApi.instance.lang == 'ar' ? 'فلاش' : 'FLASH',
                    style: const TextStyle(color: Colors.black,
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
            physics: const ClampingScrollPhysics(),
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => SizedBox(
                  width: 138,
                  child: ProductCard(product: items[i], inFlashSale: true, display: display)),
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Variant: MINIMAL — clean, red accents ─────────────────────────────────

class _FlashMinimal extends StatelessWidget {
  const _FlashMinimal({required this.items, required this.title, required this.ar, required this.endsAt, required this.onOpen, this.display = const CardDisplay()});
  final List<UellowProductCard> items;
  final String title;
  final bool ar;
  final Duration endsAt;
  final void Function(BuildContext) onOpen;
  final CardDisplay display;
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
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.flash_on, color: Colors.white, size: 12),
                const SizedBox(width: 2),
                Text(UellowApi.instance.lang == 'ar' ? 'فلاش' : 'FLASH',
                    style: const TextStyle(color: Colors.white,
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
              onPressed: () => onOpen(context),
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
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => SizedBox(
                width: 138,
                child: ProductCard(product: items[i], inFlashSale: true, display: display)),
          ),
        ),
      ]),
    );
  }
}

// ── Variant: ROYAL — premium deep-purple & gold (v2.1.36) ─────────────────

class _FlashRoyal extends StatelessWidget {
  const _FlashRoyal({required this.items, required this.title, required this.ar, required this.endsAt, required this.onOpen, this.display = const CardDisplay()});
  final List<UellowProductCard> items;
  final String title;
  final bool ar;
  final Duration endsAt;
  final void Function(BuildContext) onOpen;
  final CardDisplay display;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onOpen(context),
      child: Container(
        margin: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFF2E1065), Color(0xFF4C1D95), Color(0xFF6D28D9)],
          ),
          boxShadow: const [BoxShadow(
              color: Color(0x554C1D95), blurRadius: 20, offset: Offset(0, 7))],
        ),
        clipBehavior: Clip.antiAlias,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFFFFE082), Color(0xFFD4AF37)]),
                borderRadius: BorderRadius.circular(999),
                boxShadow: [BoxShadow(
                    color: const Color(0xFFD4AF37).withValues(alpha: 0.5),
                    blurRadius: 10)],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Text('👑', style: TextStyle(fontSize: 11)),
                const SizedBox(width: 3),
                Text(ar ? 'عروض ملكية' : 'ROYAL DEALS',
                    style: const TextStyle(color: Color(0xFF2E1065),
                    fontSize: 9.5, fontWeight: FontWeight.w900,
                    letterSpacing: 0.8)),
              ]),
            ),
            const SizedBox(width: 9),
            Expanded(child: Text(title, style: const TextStyle(
                color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900))),
            _DhmsCounter(initial: endsAt, dark: true),
          ]),
          const SizedBox(height: 12),
          SizedBox(height: 220,
            child: ListView.separated(
              physics: const ClampingScrollPhysics(),
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => SizedBox(
                  width: 138,
                  child: ProductCard(product: items[i], inFlashSale: true, display: display)),
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Variant: CUSTOM — every visual knob editable from the builder ─────────
// (v2.1.36) colors 1+2 (1 = solid), pattern on/off, badge emoji + label,
// text color, corner radius, card width — change anything later without
// touching the app.

Color _flashHexColor(dynamic raw, Color fallback) {
  try {
    var s = (raw ?? '').toString().replaceAll('#', '').trim();
    if (s.isEmpty) return fallback;
    if (s.length == 6) s = 'FF$s';
    return Color(int.parse(s, radix: 16));
  } catch (_) {
    return fallback;
  }
}

class _FlashCustom extends StatelessWidget {
  const _FlashCustom({required this.items, required this.title,
      required this.ar, required this.endsAt, required this.p,
      required this.onOpen, this.display = const CardDisplay()});
  final List<UellowProductCard> items;
  final String title;
  final bool ar;
  final Duration endsAt;
  final Map<String, dynamic> p;
  final void Function(BuildContext) onOpen;
  final CardDisplay display;
  @override
  Widget build(BuildContext context) {
    final c1 = _flashHexColor(p['flash_c1'], const Color(0xFFF5C320));
    final c2raw = (p['flash_c2'] ?? '').toString().trim();
    final c2 = c2raw.isEmpty ? c1 : _flashHexColor(c2raw, c1);
    final txt = _flashHexColor(p['flash_text_color'], Colors.white);
    final radius = ((p['flash_radius'] as num?)?.toDouble() ?? 18).clamp(0, 32).toDouble();
    final cardW = ((p['flash_card_width'] as num?)?.toDouble() ?? 132).clamp(100, 180).toDouble();
    final showPattern = p['flash_pattern'] != false;
    final showCounter = p['flash_show_counter'] != false;
    final emoji = ((p['flash_emoji'] ?? '⚡').toString());
    final badge = _tx(p, ar, 'flash_badge', '');
    return GestureDetector(
      onTap: () => onOpen(context),
      child: Container(
        margin: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [BoxShadow(
              color: c2.withValues(alpha: 0.35),
              blurRadius: 16, offset: const Offset(0, 6))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(children: [
          Positioned.fill(child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [c1, c2],
              ),
            ),
          )),
          if (showPattern)
            // v2.1.39 — 22 selectable pattern styles (builder-controlled).
            Positioned.fill(child: IgnorePointer(child: CustomPaint(
              painter: BannerPattern(
                  style: (p['flash_pattern_style'] ?? 'stripes').toString()),
            ))),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(emoji, style: const TextStyle(fontSize: 15)),
                const SizedBox(width: 4),
                Flexible(child: Text(title, maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: txt,
                        fontSize: 13, fontWeight: FontWeight.w900,
                        letterSpacing: 0.2))),
                if (badge.isNotEmpty) Container(
                  margin: const EdgeInsetsDirectional.only(start: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: txt,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(badge, style: TextStyle(
                      color: c2, fontSize: 9,
                      fontWeight: FontWeight.w900)),
                ),
                const Spacer(),
                if (showCounter) _DhmsCounter(initial: endsAt),
              ]),
              const SizedBox(height: 10),
              SizedBox(height: 178,
                child: ListView.separated(
                  physics: const ClampingScrollPhysics(),
                  scrollDirection: Axis.horizontal,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => SizedBox(
                      width: cardW,
                      child: ProductCard(product: items[i], inFlashSale: true, display: display)),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ── Variant: HERO — full-bleed single-product spotlight ───────────────────

class _FlashHero extends StatefulWidget {
  const _FlashHero({required this.items, required this.title, required this.ar, required this.endsAt, required this.onOpen, this.display = const CardDisplay()});
  final List<UellowProductCard> items;
  final String title;
  final bool ar;
  final Duration endsAt;
  final void Function(BuildContext) onOpen;
  final CardDisplay display;
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
    // v2.2.14 — refined, shorter hero: deep premium gradient, gold FLASH
    // chip, compact countdown, discount badge, clean image plate.
    final ar = widget.ar;
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 6),
      height: 196,
      child: PageView.builder(
        physics: const ClampingScrollPhysics(),
        controller: _ctrl,
        onPageChanged: (i) => setState(() => _i = i),
        itemCount: widget.items.length,
        itemBuilder: (_, i) {
          final p = widget.items[i];
          final hasCmp = p.comparePrice != null;
          final disc = p.discountPct;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: GestureDetector(
              onTap: () => UellowRouter.goProduct(context, p.id),
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [Color(0xFF7A1420), Color(0xFFC0392B), Color(0xFFE85D2A)],
                  ),
                  boxShadow: const [BoxShadow(
                      color: Color(0x40C0392B), blurRadius: 16,
                      offset: Offset(0, 6))],
                ),
                child: Stack(children: [
                  // soft corner glow for depth
                  Positioned(top: -40, right: -30, child: Container(
                    width: 150, height: 150,
                    decoration: BoxDecoration(shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: .07)))),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                                colors: [Color(0xFFFFD340), Color(0xFFF5A623)]),
                            borderRadius: BorderRadius.circular(20)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.bolt, color: Color(0xFF7A1420), size: 14),
                            const SizedBox(width: 2),
                            Text(ar ? 'فلاش سيل' : 'FLASH SALE',
                                style: const TextStyle(color: Color(0xFF7A1420),
                                    fontSize: 10.5, fontWeight: FontWeight.w900,
                                    letterSpacing: 0.6)),
                          ]),
                        ),
                        const Spacer(),
                        _DhmsCounter(initial: widget.endsAt, minimal: true),
                      ]),
                      const SizedBox(height: 12),
                      Expanded(child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                        // ── text lane ──
                        Expanded(flex: 11, child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          if (widget.display.name) Text(
                              p.name.current(ar ? 'ar' : 'en'),
                              maxLines: 2, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white,
                                  fontSize: 14.5, fontWeight: FontWeight.w800,
                                  height: 1.2)),
                          const SizedBox(height: 6),
                          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Text(p.price.format(),
                                style: const TextStyle(color: Colors.white,
                                    fontSize: 22, fontWeight: FontWeight.w900,
                                    height: 1.0)),
                            if (disc > 0) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: Colors.white,
                                    borderRadius: BorderRadius.circular(6)),
                                child: Text('-$disc%', style: const TextStyle(
                                    color: Color(0xFFC0392B), fontSize: 11,
                                    fontWeight: FontWeight.w900)),
                              ),
                            ],
                          ]),
                          if (hasCmp) Text(p.comparePrice!.format(),
                              style: const TextStyle(color: Colors.white70,
                                  fontSize: 11.5, fontWeight: FontWeight.w600,
                                  decoration: TextDecoration.lineThrough)),
                          const SizedBox(height: 9),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 13, vertical: 6),
                            decoration: BoxDecoration(color: Colors.white,
                                borderRadius: BorderRadius.circular(20)),
                            child: Text(ar ? 'تسوّق الآن ←' : 'Shop now →',
                                style: const TextStyle(color: Color(0xFFC0392B),
                                    fontSize: 11.5, fontWeight: FontWeight.w900)),
                          ),
                        ])),
                        const SizedBox(width: 12),
                        // ── image plate ──
                        Expanded(flex: 8, child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: const [BoxShadow(
                                color: Color(0x33000000), blurRadius: 8,
                                offset: Offset(0, 3))],
                          ),
                          clipBehavior: Clip.antiAlias,
                          padding: const EdgeInsets.all(6),
                          child: CachedNetworkImage(
                            imageUrl: p.image, fit: BoxFit.contain,
                            errorWidget: (_, __, ___) => const Icon(
                                Icons.shopping_bag,
                                color: Color(0xFFC0392B), size: 48),
                          ),
                        )),
                      ])),
                    ]),
                  ),
                  if (widget.items.length > 1) Positioned(bottom: 6, left: 0, right: 0,
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children:
                      List.generate(widget.items.length, (k) => AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        width: k == _i ? 16 : 5, height: 4,
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

// ─── v2.2.11 — 🌟 New-Customer Zone teaser block ───────────────────────────
// Gradient hero + preview rail that deep-links into the full NewCustomerScreen.
// Offer config + preview items come from the resolver (data.offer / data.items).
class NewCustomerZoneBlock extends StatelessWidget {
  const NewCustomerZoneBlock(
      {super.key, required this.p, required this.data, required this.ar});
  final Map<String, dynamic> p;
  final Map<String, dynamic> data;
  final bool ar;

  Color _c(Object? raw, Color fb) {
    try {
      var s = (raw ?? '').toString().replaceAll('#', '');
      if (s.length == 6) s = 'FF$s';
      return Color(int.parse(s, radix: 16));
    } catch (_) { return fb; }
  }

  @override
  Widget build(BuildContext context) {
    final offer = (data['offer'] as Map?)?.cast<String, dynamic>();
    if (offer == null) return const SizedBox.shrink();
    final items = ((data['items'] as List?) ?? const [])
        .map((e) {
          try { return UellowProductCard.fromJson((e as Map).cast<String, dynamic>()); }
          catch (_) { return null; }
        }).whereType<UellowProductCard>().toList();
    final c1 = _c(offer['c1'], const Color(0xFF7C3AED));
    final c2 = _c(offer['c2'], const Color(0xFF2563EB));
    final tc = _c(offer['text_color'], Colors.white);
    final title = ((offer['title'] as Map?)?[ar ? 'ar' : 'en'] ?? '').toString();
    final sub = ((offer['subtitle'] as Map?)?[ar ? 'ar' : 'en'] ?? '').toString();
    final emoji = (offer['emoji'] ?? '🎁').toString();
    final pct = (offer['discount_pct'] as num?)?.toInt() ?? 0;

    void open() => Navigator.pushNamed(context, Routes.newCustomer);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        GestureDetector(
          onTap: open,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [c1, c2]),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [BoxShadow(color: c1.withValues(alpha: .3),
                  blurRadius: 12, offset: const Offset(0, 6))],
            ),
            child: Row(children: [
              Text(emoji, style: const TextStyle(fontSize: 34)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min, children: [
                Text(title.isNotEmpty ? title
                    : (ar ? 'حصري للعملاء الجدد' : 'Exclusive for New Customers'),
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: tc, fontSize: 16,
                        fontWeight: FontWeight.w900, height: 1.2)),
                if (sub.isNotEmpty) Text(sub, maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: tc.withValues(alpha: .9), fontSize: 11.5)),
                if (pct > 0) Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: .22),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: tc.withValues(alpha: .5))),
                    child: Text(ar ? 'خصم حتى $pct%' : 'Up to $pct% OFF',
                        style: TextStyle(color: tc, fontWeight: FontWeight.w900,
                            fontSize: 11)),
                  ),
                ),
              ])),
              Icon(ar ? Icons.chevron_left : Icons.chevron_right,
                  color: tc, size: 26),
            ]),
          ),
        ),
        if (items.isNotEmpty) Padding(
          padding: const EdgeInsets.only(top: 10),
          child: SizedBox(height: 286, child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => SizedBox(width: 160,
                child: ProductCard(rich: true, product: items[i],
                    display: CardDisplay.fromMap(p['card'] as Map?))),
          )),
        ),
      ]),
    );
  }
}
