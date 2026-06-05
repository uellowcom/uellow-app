// =============================================================================
// VendorScreen — premium vendor storefront (v2.1.66 full redesign).
// ONE call to /api/mobile/v2/vendors/<id>/storefront powers the page:
//   hero (banner/brand color) → info card (logo/name/rating/follow)
//   → stats → ⚡ flash sale rail → offers/coupons → categories menu
//   → 🆕 new arrivals rail → 🏆 best sellers rail → per-category rails
//   → customer reviews → "all products" paginated grid (more products).
// Every rail/grid uses the standard adopted ProductCard.
// =============================================================================
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../api/uellow_api.dart';
import '../../api/uellow_models.dart';
import '../theme/uellow_theme.dart';
import '../widgets/product_card.dart';
import '../widgets/updating_pane.dart';

class VendorScreen extends StatefulWidget {
  const VendorScreen({super.key, required this.vendorId});
  final int vendorId;
  @override
  State<VendorScreen> createState() => _VendorScreenState();
}

class _VendorScreenState extends State<VendorScreen> {
  Map<String, dynamic>? _store;      // storefront payload, null = loading
  bool _error = false;

  // "All products" grid (tail of the page)
  final List<UellowProductCard> _items = [];
  int _page = 1;
  bool _hasMore = true;
  bool _loading = false;

  bool _following = false;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) {
        _loadMore();
      }
    });
    _load();
  }

  @override
  void dispose() { _scroll.dispose(); super.dispose(); }

  Future<void> _load() async {
    try {
      final res = await UellowApi.instance.getRaw(
          '/api/mobile/v2/vendors/${widget.vendorId}/storefront');
      final data = (res['data'] as Map?)?.cast<String, dynamic>();
      if (data == null) throw Exception('empty');
      final prefs = await SharedPreferences.getInstance();
      final followed = prefs.getStringList('followed_vendors') ?? const [];
      if (!mounted) return;
      setState(() {
        _store = data;
        _following = followed.contains('${widget.vendorId}');
      });
      _loadMore();
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final page = await UellowApi.instance.vendors.products(
          widget.vendorId, sort: 'newest', page: _page, perPage: 20);
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _hasMore = page.hasNext;
        _page += 1;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _hasMore = false; });
    }
  }

  Future<void> _toggleFollow() async {
    final prefs = await SharedPreferences.getInstance();
    final followed = prefs.getStringList('followed_vendors') ?? <String>[];
    final id = '${widget.vendorId}';
    setState(() => _following = !_following);
    if (_following) {
      if (!followed.contains(id)) followed.add(id);
    } else {
      followed.remove(id);
    }
    await prefs.setStringList('followed_vendors', followed);
    if (!mounted) return;
    final ar = UellowApi.instance.lang == 'ar';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 1),
        content: Text(_following
            ? (ar ? 'تتابع هذا المتجر الآن ✓' : 'Now following this store ✓')
            : (ar ? 'ألغيت المتابعة' : 'Unfollowed'))));
  }

  Future<void> _share() async {
    final ar = UellowApi.instance.lang == 'ar';
    final name = _name();
    try {
      await Share.share(ar
          ? 'تسوّق من متجر $name على تطبيق يلو 🛍️\nhttps://uellow.com'
          : 'Shop $name on the Uellow app 🛍️\nhttps://uellow.com');
    } catch (_) {}
  }

  Map<String, dynamic> get _v =>
      (_store?['vendor'] as Map?)?.cast<String, dynamic>() ?? const {};

  String _bi(Map? m) {
    final ar = UellowApi.instance.lang == 'ar';
    final mm = m?.cast<String, dynamic>();
    return ((ar ? (mm?['ar']) : (mm?['en'])) ?? mm?['en'] ?? '').toString();
  }

  String _name() => _bi(_v['name'] as Map?);

  Color _brandColor() {
    try {
      var s = (_v['brand_color'] ?? '#412402').toString().replaceAll('#', '');
      if (s.length == 6) s = 'FF$s';
      return Color(int.parse(s, radix: 16));
    } catch (_) {
      return UellowColors.darkBrown;
    }
  }

  List<UellowProductCard> _cards(String key, [Map? src]) {
    final raw = ((src ?? _store)?[key] as List?) ?? const [];
    final out = <UellowProductCard>[];
    for (final e in raw) {
      try {
        out.add(UellowProductCard.fromJson(
            (e as Map).cast<String, dynamic>()));
      } catch (_) {}
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: UellowColors.bg,
        body: _error
            ? UpdatingPane(onRetry: () {
                setState(() { _error = false; _store = null; });
                _load();
              })
            : _store == null
                ? const Center(child: CircularProgressIndicator(
                    color: UellowColors.darkBrown))
                : _content(ar),
      ),
    );
  }

  Widget _content(bool ar) {
    final v = _v;
    final rating = (v['rating'] as Map?)?.cast<String, dynamic>() ?? const {};
    final avg = ((rating['avg'] as num?) ?? 0).toDouble();
    final rCount = ((rating['count'] as num?) ?? 0).toInt();
    final cats = List<Map<String, dynamic>>.from(
        (_store?['categories'] as List?) ?? const []);
    final about = _bi(v['about'] as Map?).trim();
    final tagline = _bi(v['tagline'] as Map?).trim();
    final flash = (_store?['flash_sale'] as Map?)?.cast<String, dynamic>();
    final offers = List<Map<String, dynamic>>.from(
        (_store?['offers'] as List?) ?? const []);
    final rails = List<Map<String, dynamic>>.from(
        (_store?['category_rails'] as List?) ?? const []);
    final reviews = (_store?['reviews'] as Map?)?.cast<String, dynamic>();
    final reviewItems = List<Map<String, dynamic>>.from(
        (reviews?['items'] as List?) ?? const []);
    final newArrivals = _cards('new_arrivals');
    final bestSellers = _cards('best_sellers');

    return CustomScrollView(controller: _scroll, slivers: [
      SliverToBoxAdapter(child: _hero(v)),
      SliverToBoxAdapter(child: _infoCard(ar, avg, rCount, tagline, about)),
      SliverToBoxAdapter(child: _stats(ar, v)),

      // ⚡ Flash sale — vendor's own live campaign
      if (flash != null && (flash['products'] as List?)?.isNotEmpty == true)
        SliverToBoxAdapter(child: _flashRail(ar, flash)),

      // 🎟 Offers / coupons & joined campaigns
      if (offers.isNotEmpty)
        SliverToBoxAdapter(child: _offersRow(ar, offers)),

      // 📂 Categories menu
      if (cats.isNotEmpty) SliverToBoxAdapter(child: _catChips(ar, cats)),

      // 🆕 New arrivals
      if (newArrivals.isNotEmpty)
        SliverToBoxAdapter(child: _rail(
            ar ? '🆕 وصل حديثاً' : '🆕 New Arrivals', newArrivals)),

      // 🏆 Best sellers
      if (bestSellers.isNotEmpty)
        SliverToBoxAdapter(child: _rail(
            ar ? '🏆 الأكثر مبيعاً' : '🏆 Best Sellers', bestSellers)),

      // 📂 One rail per category that has products
      for (final r in rails)
        SliverToBoxAdapter(child: _rail(
            _bi((r['category'] as Map?)?['name'] as Map?),
            _cards('products', r))),

      // ⭐ Customer reviews
      if (reviewItems.isNotEmpty)
        SliverToBoxAdapter(child: _reviewsBlock(ar, reviews!, reviewItems)),

      // 🛍 All products (more products)
      SliverToBoxAdapter(child: _sectionTitle(
          ar ? '🛍 المزيد من المنتجات' : '🛍 More products')),
      _productsGrid(),
      SliverToBoxAdapter(child: _loading
          ? const Padding(padding: EdgeInsets.all(18),
              child: Center(child: SizedBox(width: 22, height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5,
                      color: UellowColors.darkBrown))))
          : const SizedBox(height: 30)),
    ]);
  }

  // ── hero: brand color gradient + optional banner image ──
  Widget _hero(Map<String, dynamic> v) {
    final brand = _brandColor();
    final banner = (v['banner'] as String?) ?? '';
    return SizedBox(height: 150, child: Stack(fit: StackFit.expand, children: [
      DecoratedBox(decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [brand, Color.lerp(brand, Colors.black, 0.35)!],
        ),
      )),
      if (banner.isNotEmpty)
        CachedNetworkImage(
            imageUrl: banner.startsWith('http')
                ? banner : '${UellowApi.instance.baseUrl}$banner',
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => const SizedBox.shrink()),
      Container(color: Colors.black.withValues(alpha: 0.12)),
      SafeArea(child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(children: [
          _heroBtn(Icons.arrow_back, () => Navigator.maybePop(context)),
          const Spacer(),
          _heroBtn(Icons.share_outlined, _share),
        ]),
      )),
    ]));
  }

  Widget _heroBtn(IconData icon, VoidCallback onTap) => IconButton(
        onPressed: onTap,
        icon: Icon(icon, color: Colors.white),
        style: IconButton.styleFrom(
          backgroundColor: const Color(0x4D000000),
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(10))),
        ),
      );

  // ── info card: logo + name + rating + follow/contact ──
  Widget _infoCard(bool ar, double avg, int rCount,
      String tagline, String about) {
    final v = _v;
    final logo = (v['logo'] as String?) ?? '';
    final name = _name();
    final tier = (v['tier'] ?? 'standard').toString();
    return Container(
      transform: Matrix4.translationValues(0, -26, 0),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20), topRight: Radius.circular(20),
        ),
      ),
      child: Column(children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 72, height: 72,
            clipBehavior: Clip.antiAlias,
            decoration: const BoxDecoration(
              color: UellowColors.yellowLight,
              borderRadius: BorderRadius.all(Radius.circular(18)),
              boxShadow: [BoxShadow(color: Color(0x33000000),
                  blurRadius: 14, offset: Offset(0, 6))],
            ),
            alignment: Alignment.center,
            child: logo.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: logo.startsWith('http')
                        ? logo : '${UellowApi.instance.baseUrl}$logo',
                    fit: BoxFit.cover, width: 72, height: 72,
                    errorWidget: (_, __, ___) => Text(
                        name.isEmpty ? 'U' : name[0].toUpperCase(),
                        style: const TextStyle(fontSize: 26,
                            fontWeight: FontWeight.w900,
                            color: UellowColors.darkBrown)))
                : Text(name.isEmpty ? 'U' : name[0].toUpperCase(),
                    style: const TextStyle(fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: UellowColors.darkBrown)),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(name, maxLines: 1,
                  overflow: TextOverflow.ellipsis, style: UT.h1)),
              if (tier != 'standard') Padding(
                padding: const EdgeInsetsDirectional.only(start: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3D6),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFE8C76B)),
                  ),
                  child: Text(
                      ar ? '⭐ متجر مميز' : '⭐ Premium store',
                      style: const TextStyle(fontSize: 9,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF8B6508))),
                ),
              ),
            ]),
            if (tagline.isNotEmpty) Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(tagline, maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5,
                      color: UellowColors.muted)),
            ),
            const SizedBox(height: 4),
            if (rCount > 0) Row(children: [
              for (var i = 0; i < 5; i++) Icon(
                i < avg.round() ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                size: 13,
                color: i < avg.round()
                    ? const Color(0xFFFFC107) : const Color(0xFFCFCFCF)),
              const SizedBox(width: 4),
              Text('${avg.toStringAsFixed(1)} · '
                   '${ar ? "$rCount تقييم" : "$rCount reviews"}',
                  style: const TextStyle(fontSize: 11,
                      color: UellowColors.muted)),
            ]) else Text(ar ? 'لا توجد تقييمات بعد' : 'No reviews yet',
                style: const TextStyle(fontSize: 11,
                    color: UellowColors.muted)),
          ])),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: ElevatedButton.icon(
            onPressed: _toggleFollow,
            icon: Icon(_following ? Icons.check : Icons.add, size: 15),
            label: Text(_following
                ? (ar ? 'متابَع' : 'Following')
                : (ar ? 'متابعة' : 'Follow'),
                style: const TextStyle(fontSize: 12,
                    fontWeight: FontWeight.w800)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _following
                  ? UellowColors.border : UellowColors.yellowLight,
              foregroundColor: UellowColors.darkBrown,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(10))),
            ),
          )),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(
            onPressed: () => Navigator.pushNamed(context, '/helpdesk'),
            icon: const Icon(Icons.support_agent, size: 15),
            label: Text(ar ? 'تواصل' : 'Contact',
                style: const TextStyle(fontSize: 12,
                    fontWeight: FontWeight.w800)),
            style: OutlinedButton.styleFrom(
              foregroundColor: UellowColors.darkBrown,
              side: const BorderSide(color: UellowColors.border),
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(10))),
            ),
          )),
          if (about.isNotEmpty) ...[
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () => _showAbout(ar, about),
              style: OutlinedButton.styleFrom(
                foregroundColor: UellowColors.darkBrown,
                side: const BorderSide(color: UellowColors.border),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(10))),
              ),
              child: Text(ar ? 'حول' : 'About',
                  style: const TextStyle(fontSize: 12,
                      fontWeight: FontWeight.w800)),
            ),
          ],
        ]),
      ]),
    );
  }

  void _showAbout(bool ar, String about) {
    final v = _v;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(
          top: Radius.circular(18))),
      builder: (_) => Directionality(
        textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
          child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(ar ? 'حول المتجر' : 'About the store', style: UT.h2),
            const SizedBox(height: 10),
            Text(about, style: UT.body),
            if ((v['business_name'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(children: [
                const Icon(Icons.business_outlined, size: 15,
                    color: UellowColors.muted),
                const SizedBox(width: 6),
                Text((v['business_name']).toString(), style: UT.small),
              ]),
            ],
          ]),
        ),
      ),
    );
  }

  // ── stats row ──
  Widget _stats(bool ar, Map<String, dynamic> v) {
    String fmt(num? n) {
      final x = (n ?? 0).toInt();
      if (x >= 1000) return '${(x / 1000).toStringAsFixed(x >= 10000 ? 0 : 1)}k';
      return '$x';
    }
    final rating = (v['rating'] as Map?)?.cast<String, dynamic>() ?? const {};
    final avg = ((rating['avg'] as num?) ?? 0).toDouble();
    final sla = ((v['sla_hours'] as num?) ?? 0).toInt();
    final cells = <(String, String)>[
      (fmt(v['product_count'] as num?), ar ? 'منتج' : 'Products'),
      (fmt(v['order_count'] as num?), ar ? 'طلب' : 'Orders'),
      (avg > 0 ? avg.toStringAsFixed(1) : '—', ar ? 'التقييم' : 'Rating'),
      if (sla > 0) ('$slaس', ar ? 'يشحن خلال' : 'Ships in'),
    ];
    return Container(
      transform: Matrix4.translationValues(0, -26, 0),
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Row(children: [
        for (final s in cells)
          Expanded(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F7F7),
                border: Border.all(color: UellowColors.border),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(children: [
                Text(s.$1, style: const TextStyle(fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: UellowColors.darkBrown)),
                Text(s.$2, style: const TextStyle(fontSize: 9.5,
                    color: UellowColors.text)),
              ]),
            ),
          )),
      ]),
    );
  }

  // ── ⚡ flash sale rail (dark band + countdown-ish end time) ──
  Widget _flashRail(bool ar, Map<String, dynamic> flash) {
    final prods = _cards('products', flash);
    if (prods.isEmpty) return const SizedBox.shrink();
    final pct = ((flash['discount_pct'] as num?) ?? 0).toInt();
    final ends = (flash['ends_at'] as String?) ?? '';
    final endsTxt = ends.length >= 16
        ? ends.replaceFirst('T', ' ').substring(0, 16) : '';
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 10),
      padding: const EdgeInsets.only(bottom: 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF412402), Color(0xFF6B4A1B)],
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Row(children: [
            Text(ar ? '⚡ تخفيضات المتجر' : '⚡ Store Flash Sale',
                style: const TextStyle(color: UellowColors.yellow,
                    fontWeight: FontWeight.w900, fontSize: 14.5)),
            const SizedBox(width: 8),
            if (pct > 0) Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: UellowColors.yellow,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('-$pct%', style: const TextStyle(
                  color: UellowColors.darkBrown,
                  fontWeight: FontWeight.w900, fontSize: 11)),
            ),
            const Spacer(),
            if (endsTxt.isNotEmpty)
              Text(ar ? 'حتى $endsTxt' : 'until $endsTxt',
                  style: const TextStyle(color: Colors.white70,
                      fontSize: 10)),
          ]),
        ),
        SizedBox(height: 290, child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: prods.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) => SizedBox(width: 168,
              child: ProductCard(rich: true, product: prods[i])),
        )),
      ]),
    );
  }

  // ── 🎟 offers / coupons row ──
  Widget _offersRow(bool ar, List<Map<String, dynamic>> offers) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(0, 6, 0, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionTitle(ar ? '🎟 كوبونات وعروض المتجر' : '🎟 Store coupons & offers'),
        SizedBox(height: 74, child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          itemCount: offers.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final o = offers[i];
            final pct = ((o['discount_pct'] as num?) ?? 0).toInt();
            final to = (o['date_to'] as String?) ?? '';
            final toTxt = to.length >= 10 ? to.substring(0, 10) : '';
            return Container(
              width: 230,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFF6D9), Color(0xFFFFEDB3)],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: UellowColors.yellow.withValues(alpha: .7)),
              ),
              child: Row(children: [
                Text((o['emoji'] ?? '🎉').toString(),
                    style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 10),
                Expanded(child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_bi(o['label'] as Map?), maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900,
                          fontSize: 12, color: UellowColors.darkBrown)),
                  const SizedBox(height: 2),
                  Text([
                    if (pct > 0) (ar ? 'خصم حتى $pct%' : 'Up to $pct% off'),
                    if (toTxt.isNotEmpty) (ar ? 'حتى $toTxt' : 'till $toTxt'),
                  ].join(' · '),
                      style: const TextStyle(fontSize: 10,
                          color: Color(0xFF8B6508),
                          fontWeight: FontWeight.w700)),
                ])),
              ]),
            );
          },
        )),
      ]),
    );
  }

  // ── 📂 category chips menu ──
  Widget _catChips(bool ar, List<Map<String, dynamic>> cats) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionTitle(ar ? '📂 أقسام المتجر' : '📂 Store sections'),
        SizedBox(height: 32, child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          itemCount: cats.length,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (_, i) {
            final c = cats[i];
            final label = _bi(c['name'] as Map?);
            final count = ((c['count'] as num?) ?? 0).toInt();
            return GestureDetector(
              onTap: () => Navigator.pushNamed(context, '/collection',
                  arguments: {'category_id': (c['id'] as num?)?.toInt()}),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 13),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: UellowColors.yellowFaint,
                  border: Border.all(
                      color: UellowColors.yellow.withValues(alpha: .55)),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('$label ($count)', style: const TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w800,
                    color: UellowColors.darkBrown)),
              ),
            );
          },
        )),
      ]),
    );
  }

  // ── generic horizontal product rail ──
  Widget _rail(String title, List<UellowProductCard> prods) {
    if (prods.isEmpty) return const SizedBox.shrink();
    return Container(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.only(top: 4, bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionTitle(title),
        SizedBox(height: 290, child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: prods.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) => SizedBox(width: 168,
              child: ProductCard(rich: true, product: prods[i])),
        )),
      ]),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
        child: Text(t, style: const TextStyle(fontSize: 14.5,
            fontWeight: FontWeight.w900, color: UellowColors.ink)),
      );

  // ── ⭐ reviews block ──
  Widget _reviewsBlock(bool ar, Map<String, dynamic> reviews,
      List<Map<String, dynamic>> items) {
    final summary = (reviews['summary'] as Map?)?.cast<String, dynamic>()
        ?? const {};
    final avg = ((summary['avg'] as num?) ?? 0).toDouble();
    final count = ((summary['count'] as num?) ?? 0).toInt();
    return Container(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.only(top: 4, bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
          child: Row(children: [
            Text(ar ? '⭐ آراء العملاء' : '⭐ Customer reviews',
                style: const TextStyle(fontSize: 14.5,
                    fontWeight: FontWeight.w900, color: UellowColors.ink)),
            const Spacer(),
            if (count > 0)
              Text('${avg.toStringAsFixed(1)} · $count',
                  style: const TextStyle(fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: UellowColors.muted)),
          ]),
        ),
        SizedBox(height: 132, child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final r = items[i];
            final stars = ((r['stars'] as num?) ?? 0).round();
            final prod = (r['product'] as Map?)?.cast<String, dynamic>();
            final img = (prod?['image'] as String?) ?? '';
            return Container(
              width: 250,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFAFAFA),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: UellowColors.border),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  if (img.isNotEmpty) ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(imageUrl: img,
                        width: 34, height: 34, fit: BoxFit.cover,
                        errorWidget: (_, __, ___) =>
                            const SizedBox(width: 34, height: 34)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Row(children: [
                      for (var s = 0; s < 5; s++) Icon(
                          s < stars ? Icons.star_rounded
                                    : Icons.star_outline_rounded,
                          size: 12,
                          color: s < stars ? const Color(0xFFFFC107)
                                           : const Color(0xFFCFCFCF)),
                      const SizedBox(width: 4),
                      if (r['verified'] == true)
                        Text(ar ? '✓ شراء موثّق' : '✓ Verified',
                            style: const TextStyle(fontSize: 8.5,
                                color: Color(0xFF15803D),
                                fontWeight: FontWeight.w800)),
                    ]),
                    Text(_bi(prod?['name'] as Map?), maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10,
                            color: UellowColors.muted)),
                  ])),
                ]),
                const SizedBox(height: 6),
                Expanded(child: Text(
                    ((r['title'] ?? '').toString().isNotEmpty
                        ? '${r['title']} — ' : '') +
                    (r['text'] ?? '').toString(),
                    maxLines: 3, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, height: 1.4,
                        color: UellowColors.text))),
                Text((r['customer'] ?? '').toString(),
                    style: const TextStyle(fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: UellowColors.muted)),
              ]),
            );
          },
        )),
      ]),
    );
  }

  // ── all-products grid (the "more products" tail) ──
  Widget _productsGrid() {
    if (_items.isEmpty && !_loading) {
      final ar = UellowApi.instance.lang == 'ar';
      return SliverToBoxAdapter(child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(children: [
          const Icon(Icons.storefront_outlined, size: 56,
              color: UellowColors.muted),
          const SizedBox(height: 10),
          Text(ar ? 'لا توجد منتجات منشورة بعد' : 'No published products yet',
              style: UT.body),
        ]),
      ));
    }
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, mainAxisSpacing: 8, crossAxisSpacing: 8,
          childAspectRatio: 0.585,
        ),
        delegate: SliverChildBuilderDelegate(
          (_, i) => ProductCard(rich: true, product: _items[i]),
          childCount: _items.length,
        ),
      ),
    );
  }
}
