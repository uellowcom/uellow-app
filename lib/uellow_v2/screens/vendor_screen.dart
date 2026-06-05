// =============================================================================
// VendorScreen — REAL vendor store (v2.1.56 full rewrite).
// Everything on this page is live data from /api/mobile/v2/vendors/<id>:
// hero (brand color/banner), logo, bilingual name + tagline, true rating,
// real stats (products / orders / rating / SLA), category chips, sortable
// paginated product grid, about sheet, working follow (persisted) + share.
// The old screen was hardcoded mock content ("Uellow Official", fake flash,
// placeholder cards) — all removed.
// =============================================================================
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../api/uellow_api.dart';
import '../../api/uellow_models.dart';
import '../theme/uellow_theme.dart';
import '../widgets/product_card.dart';

class VendorScreen extends StatefulWidget {
  const VendorScreen({super.key, required this.vendorId});
  final int vendorId;
  @override
  State<VendorScreen> createState() => _VendorScreenState();
}

class _VendorScreenState extends State<VendorScreen> {
  Map<String, dynamic>? _vendor;     // null = loading
  bool _error = false;

  // products
  final List<UellowProductCard> _items = [];
  String _sort = 'newest';
  int _page = 1;
  bool _hasMore = true;
  bool _loading = false;

  bool _following = false;

  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels >
          _scroll.position.maxScrollExtent - 400) {
        _loadMore();
      }
    });
    _load();
  }

  @override
  void dispose() { _scroll.dispose(); super.dispose(); }

  Future<void> _load() async {
    try {
      final v = await UellowApi.instance.vendors.detail(widget.vendorId);
      final prefs = await SharedPreferences.getInstance();
      final followed = prefs.getStringList('followed_vendors') ?? const [];
      if (!mounted) return;
      setState(() {
        _vendor = v;
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
          widget.vendorId, sort: _sort, page: _page, perPage: 20);
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

  void _changeSort(String s) {
    if (s == _sort) return;
    setState(() {
      _sort = s; _items.clear(); _page = 1; _hasMore = true; _loading = false;
    });
    _loadMore();
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

  String _name() {
    final ar = UellowApi.instance.lang == 'ar';
    final n = (_vendor?['name'] as Map?)?.cast<String, dynamic>();
    return ((ar ? (n?['ar']) : (n?['en'])) ?? n?['en'] ?? '').toString();
  }

  Color _brandColor() {
    try {
      var s = (_vendor?['brand_color'] ?? '#412402')
          .toString().replaceAll('#', '');
      if (s.length == 6) s = 'FF$s';
      return Color(int.parse(s, radix: 16));
    } catch (_) {
      return UellowColors.darkBrown;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: UellowColors.bg,
        body: _error
            ? _ErrorPane(onRetry: () {
                setState(() { _error = false; _vendor = null; });
                _load();
              })
            : _vendor == null
                ? const Center(child: CircularProgressIndicator(
                    color: UellowColors.darkBrown))
                : _content(ar),
      ),
    );
  }

  Widget _content(bool ar) {
    final v = _vendor!;
    final rating = (v['rating'] as Map?)?.cast<String, dynamic>() ?? const {};
    final avg = ((rating['avg'] as num?) ?? 0).toDouble();
    final rCount = ((rating['count'] as num?) ?? 0).toInt();
    final cats = List<Map<String, dynamic>>.from(
        (v['categories'] as List?) ?? const []);
    final aboutMap = (v['about'] as Map?)?.cast<String, dynamic>();
    final about = ((ar ? (aboutMap?['ar']) : (aboutMap?['en']))
        ?? aboutMap?['en'] ?? '').toString().trim();
    final tagMap = (v['tagline'] as Map?)?.cast<String, dynamic>();
    final tagline = ((ar ? (tagMap?['ar']) : (tagMap?['en']))
        ?? tagMap?['en'] ?? '').toString().trim();

    return CustomScrollView(controller: _scroll, slivers: [
      SliverToBoxAdapter(child: _hero(v)),
      SliverToBoxAdapter(child: _infoCard(ar, avg, rCount, tagline, about)),
      SliverToBoxAdapter(child: _stats(ar, v)),
      if (cats.isNotEmpty) SliverToBoxAdapter(child: _catChips(ar, cats)),
      SliverToBoxAdapter(child: _sortBar(ar)),
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
      // soft dark veil so the buttons always read
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
    final v = _vendor!;
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
            decoration: BoxDecoration(
              color: UellowColors.yellowLight,
              borderRadius: const BorderRadius.all(Radius.circular(18)),
              boxShadow: const [BoxShadow(color: Color(0x33000000),
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
            // Real rating — hidden entirely when no reviews yet.
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
    final v = _vendor!;
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

  // ── real stats row ──
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

  // ── real category chips (top categories this vendor sells) ──
  Widget _catChips(bool ar, List<Map<String, dynamic>> cats) {
    return Container(
      transform: Matrix4.translationValues(0, -26, 0),
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: SizedBox(height: 30, child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cats.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final c = cats[i];
          final nm = (c['name'] as Map?)?.cast<String, dynamic>();
          final label = ((ar ? (nm?['ar']) : (nm?['en']))
              ?? nm?['en'] ?? '').toString();
          final count = ((c['count'] as num?) ?? 0).toInt();
          return GestureDetector(
            onTap: () => Navigator.pushNamed(context, '/collection',
                arguments: {'category_id': (c['id'] as num?)?.toInt()}),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFF7F7F7),
                border: Border.all(color: UellowColors.border),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text('$label ($count)', style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700,
                  color: UellowColors.ink)),
            ),
          );
        },
      )),
    );
  }

  // ── sort tabs (real backend sorts) ──
  Widget _sortBar(bool ar) {
    final tabs = <(String, String)>[
      ('newest', ar ? 'الأحدث' : 'Newest'),
      ('top_rated', ar ? 'الأعلى تقييماً' : 'Top rated'),
      ('price_asc', ar ? 'السعر ⬆' : 'Price ↑'),
      ('price_desc', ar ? 'السعر ⬇' : 'Price ↓'),
    ];
    return Container(
      transform: Matrix4.translationValues(0, -26, 0),
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Row(children: [
        for (final t in tabs) Padding(
          padding: const EdgeInsetsDirectional.only(end: 6),
          child: GestureDetector(
            onTap: () => _changeSort(t.$1),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _sort == t.$1
                    ? UellowColors.darkBrown : Colors.white,
                border: Border.all(color: _sort == t.$1
                    ? UellowColors.darkBrown : UellowColors.border),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(t.$2, style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w800,
                  color: _sort == t.$1
                      ? UellowColors.yellowLight : UellowColors.text)),
            ),
          ),
        ),
      ]),
    );
  }

  // ── real product grid ──
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

class _ErrorPane extends StatelessWidget {
  const _ErrorPane({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.cloud_off_outlined, size: 56, color: UellowColors.muted),
      const SizedBox(height: 12),
      Text(ar ? 'تعذّر تحميل المتجر' : 'Could not load this store',
          style: UT.body),
      const SizedBox(height: 14),
      ElevatedButton(onPressed: onRetry,
          child: Text(ar ? 'إعادة المحاولة' : 'Retry')),
    ]));
  }
}
