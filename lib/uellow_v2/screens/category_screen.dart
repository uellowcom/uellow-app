// =============================================================================
// CategoryScreen — SHEIN/Banggood pattern: sidebar of main categories
// (left) + content (right). Content shows:
//   1. Sub-categories grid (if any)
//   2. Latest products in the selected main category — horizontal slider
//   3. All products grid
// =============================================================================
import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../api/uellow_api.dart';
import '../../api/uellow_models.dart';
import '../router/uellow_router.dart';
import '../theme/uellow_theme.dart';
import '../widgets/product_card.dart';
import '../widgets/uellow_bottom_nav.dart';

class CategoryScreen extends StatefulWidget {
  const CategoryScreen({super.key});
  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  Future<List<UellowCategory>>? _tree;
  int _selectedRoot = 0;
  int? _initialCategoryId;
  String? _searchQuery;
  bool _initialised = false;

  @override
  void initState() {
    super.initState();
    _tree = UellowApi.instance.categories.tree();
  }

  void _ensureInit(BuildContext context) {
    if (_initialised) return;
    _initialised = true;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      _initialCategoryId = args['category_id'] as int?;
      _searchQuery = args['search'] as String?;
    }
  }

  @override
  Widget build(BuildContext context) {
    _ensureInit(context);
    return Scaffold(
      backgroundColor: UellowColors.bg,
      bottomNavigationBar: const UellowBottomNav(active: UNavTab.shop),
      body: SafeArea(child: Column(children: [
        const _CatTopBar(),
        if (_searchQuery != null && _searchQuery!.isNotEmpty)
          _SearchResultsHeader(query: _searchQuery!),
        Expanded(
          child: FutureBuilder<List<UellowCategory>>(
            future: _tree,
            builder: (_, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator(color: UellowColors.darkBrown));
              }
              if (snap.hasError || (snap.data?.isEmpty ?? true)) {
                return Center(child: Text(
                    UellowApi.instance.lang == 'ar'
                        ? 'لا توجد أقسام بعد.'
                        : 'No categories yet.',
                    style: UT.body));
              }
              final roots = snap.data!;
              if (_initialCategoryId != null) {
                final idx = roots.indexWhere((c) => c.id == _initialCategoryId);
                if (idx >= 0) _selectedRoot = idx;
                _initialCategoryId = null;
              }
              final current = roots[_selectedRoot.clamp(0, roots.length - 1)];
              return Row(children: [
                _Sidebar(roots: roots, selected: _selectedRoot,
                    onSelect: (i) => setState(() => _selectedRoot = i)),
                Expanded(child: _Content(
                  category: current, searchQuery: _searchQuery)),
              ]);
            },
          ),
        ),
      ])),
    );
  }
}

class _SearchResultsHeader extends StatelessWidget {
  const _SearchResultsHeader({required this.query});
  final String query;
  @override
  Widget build(BuildContext context) {
    return Container(
      color: UellowColors.yellowSoft,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(children: [
        const Icon(Icons.search, size: 16, color: UellowColors.darkBrown),
        const SizedBox(width: 8),
        Expanded(child: Text.rich(TextSpan(
          style: const TextStyle(fontSize: 12.5, color: UellowColors.darkBrown),
          children: [
            TextSpan(text: UellowApi.instance.lang == 'ar'
                ? 'نتائج البحث عن '
                : 'Results for '),
            TextSpan(text: '"$query"', style: const TextStyle(fontWeight: FontWeight.w900)),
          ],
        ))),
        GestureDetector(
          onTap: () => Navigator.pushReplacementNamed(context, '/search'),
          child: const Icon(Icons.close, size: 18, color: UellowColors.darkBrown),
        ),
      ]),
    );
  }
}

// ─── Top bar ──────────────────────────────────────────────────────

class _CatTopBar extends StatelessWidget {
  const _CatTopBar();
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: UellowColors.border)),
      ),
      child: Row(children: [
        Expanded(child: GestureDetector(
          onTap: () => Navigator.pushNamed(context, '/search'),
          behavior: HitTestBehavior.opaque,
          child: Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
              color: UellowColors.border,
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
            child: Row(children: [
              const Icon(Icons.search, size: 18, color: UellowColors.muted),
              const SizedBox(width: 10),
              Text(UellowApi.instance.lang == 'ar'
                  ? 'ابحث عن منتج، ماركة، أو تاجر…'
                  : 'Search products, brands, vendors…',
                  style: const TextStyle(fontSize: 13, color: UellowColors.muted)),
            ]),
          ),
        )),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => Navigator.pushNamed(context, '/scan'),
          child: _topIcon(Icons.qr_code_scanner_outlined)),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => Navigator.pushNamed(context, '/search'),
          child: _topIcon(Icons.camera_alt_outlined)),
      ]),
    );
  }

  Widget _topIcon(IconData icon) => Container(
        width: 38, height: 38,
        decoration: const BoxDecoration(
          color: UellowColors.border,
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        child: Icon(icon, size: 18, color: UellowColors.text),
      );
}

// ─── Left sidebar ──────────────────────────────────────────────────

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.roots, required this.selected, required this.onSelect});
  final List<UellowCategory> roots;
  final int selected;
  final ValueChanged<int> onSelect;
  @override
  Widget build(BuildContext context) {
    final lang = UellowApi.instance.lang;
    return Container(
      width: 90, color: Colors.white,
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: UellowColors.border)),
      ),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: roots.length,
        itemBuilder: (_, i) {
          final c = roots[i];
          final on = i == selected;
          return GestureDetector(
            onTap: () => onSelect(i),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
              decoration: BoxDecoration(
                color: on ? UellowColors.yellowFaint : null,
                border: Border(left: BorderSide(
                  color: on ? UellowColors.yellow : Colors.transparent, width: 3,
                )),
              ),
              child: Column(children: [
                Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    color: c.image == null ? UellowColors.yellowSoft : null,
                    borderRadius: BorderRadius.circular(12),
                    image: c.image != null
                        ? DecorationImage(image: CachedNetworkImageProvider(c.image!),
                            fit: BoxFit.cover)
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: c.image == null
                      ? Text(_emoji(c.name.current(lang)),
                          style: const TextStyle(fontSize: 22))
                      : null,
                ),
                const SizedBox(height: 5),
                Text(c.name.current(lang), maxLines: 2,
                    overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 9.5, height: 1.2,
                      color: on ? UellowColors.darkBrown : UellowColors.text,
                      fontWeight: on ? FontWeight.w800 : FontWeight.w600,
                    )),
              ]),
            ),
          );
        },
      ),
    );
  }

  String _emoji(String name) {
    final n = name.toLowerCase();
    if (n.contains('phone') || n.contains('mobile')) return '📱';
    if (n.contains('fashion') || n.contains('cloth')) return '👗';
    if (n.contains('home')) return '🏠';
    if (n.contains('beauty')) return '💄';
    if (n.contains('watch')) return '⌚';
    if (n.contains('game') || n.contains('toy')) return '🎮';
    if (n.contains('shoe')) return '👟';
    if (n.contains('food')) return '🛒';
    if (n.contains('baby')) return '👶';
    return '📦';
  }
}

// ─── Right content ─────────────────────────────────────────────────

class _Content extends StatefulWidget {
  const _Content({required this.category, this.searchQuery});
  final UellowCategory category;
  final String? searchQuery;
  @override
  State<_Content> createState() => _ContentState();
}

class _ContentState extends State<_Content> {
  Future<List<UellowProductCard>>? _products;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _Content old) {
    super.didUpdateWidget(old);
    if (old.category.id != widget.category.id ||
        old.searchQuery != widget.searchQuery) _load();
  }

  void _load() {
    final q = widget.searchQuery;
    if (q != null && q.isNotEmpty) {
      setState(() => _products = UellowApi.instance.search.search(q, perPage: 30)
          .then((r) => r.products));
    } else {
      setState(() => _products = UellowApi.instance.products.list(
          categoryId: widget.category.id, perPage: 20,
        ).then((page) => page.items));
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = UellowApi.instance.lang;
    final ar = lang == 'ar';
    final subs = widget.category.children;
    return ListView(padding: EdgeInsets.zero, children: [
      // v2.1.56 — image slider replaces the old static "up to 50% off"
      // banner. Slides come from the backend (category form ▸ App Header
      // Slides); built-in default banners show until the admin adds some.
      _CategoryHeaderSlider(
          key: ValueKey('slider-${widget.category.id}'),
          category: widget.category),
      // Sub-categories (only if any)
      if (subs.isNotEmpty) _SubCatsGrid(subs: subs, lang: lang),
      // Latest products slider
      _LatestSlider(category: widget.category, products: _products),
      // All products grid — Sort/Filter removed per spec; tighter title.
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
        child: Text(subs.isEmpty
                ? (ar
                    ? 'منتجات ${widget.category.name.current(lang)}'
                    : 'Products in ${widget.category.name.current(lang)}')
                : (ar ? 'كل المنتجات' : 'All products'),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900,
                color: UellowColors.ink)),
      ),
      _ProductsGrid(future: _products),
      const SizedBox(height: 30),
    ]);
  }
}

class _SubCatsGrid extends StatelessWidget {
  const _SubCatsGrid({required this.subs, required this.lang});
  final List<UellowCategory> subs;
  final String lang;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 10, 10, 0),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(children: [
            Text(lang == 'ar' ? 'الأقسام الفرعية' : 'Sub-categories',
                style: const TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w900, color: UellowColors.ink)),
            const Spacer(),
            Text(lang == 'ar' ? '${subs.length} عنصر' : '${subs.length} items',
                style: UT.tiny),
          ]),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 12, childAspectRatio: 0.78,
          ),
          itemCount: subs.length,
          itemBuilder: (_, i) {
            final c = subs[i];
            return GestureDetector(
              onTap: () => Navigator.pushNamed(context, '/collection',
                  arguments: {'category_id': c.id}),
              behavior: HitTestBehavior.opaque,
              child: Column(children: [
              Expanded(child: Container(
                decoration: BoxDecoration(
                  // Always gray bg per latest spec; image (if any) overlays
                  color: const Color(0xFFEFEFEF),
                  borderRadius: BorderRadius.circular(12),
                  image: c.image != null
                      ? DecorationImage(image: CachedNetworkImageProvider(c.image!),
                          fit: BoxFit.cover)
                      : null,
                ),
                alignment: Alignment.center,
                child: c.image == null
                    ? const Text('📦', style: TextStyle(fontSize: 32))
                    : null,
              )),
              const SizedBox(height: 6),
              // v2.1.56 — smaller sub-category font per spec.
              Text(c.name.current(lang), maxLines: 2,
                  overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 8.5, height: 1.25,
                      fontWeight: FontWeight.w700, color: UellowColors.ink)),
              Text('${c.productCount}',
                  style: const TextStyle(fontSize: 8, color: UellowColors.muted,
                      fontWeight: FontWeight.w700)),
            ]));
          },
        ),
      ]),
    );
  }
}

class _LatestSlider extends StatelessWidget {
  const _LatestSlider({required this.category, required this.products});
  final UellowCategory category;
  final Future<List<UellowProductCard>>? products;
  @override
  Widget build(BuildContext context) {
    final lang = UellowApi.instance.lang;
    final ar = lang == 'ar';
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 10, 10, 0),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            const Icon(Icons.fiber_new, size: 14, color: UellowColors.warn),
            const SizedBox(width: 4),
            Text(ar ? 'وصل حديثاً' : 'Recently arrived',
                style: const TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w900, color: UellowColors.ink)),
            // v2.0.76 — category-name pill removed per user request; the
            // category name was already in the screen's app bar so it was
            // redundant noise in the section title.
            const Spacer(),
            GestureDetector(
              onTap: () => Navigator.pushNamed(context, '/collection',
                  arguments: {'category_id': category.id}),
              child: Text(ar ? 'عرض الكل ←' : 'See all →',
                  style: const TextStyle(fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: UellowColors.darkBrown)),
            ),
          ]),
        ),
        SizedBox(
          // v2.1.34 — 245→212: the compact card (no save/avail row) left a
          // big empty white band under the price; height now hugs content.
          height: 212,
          child: FutureBuilder<List<UellowProductCard>>(
            future: products,
            builder: (_, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError || (snap.data?.isEmpty ?? true)) {
                return Center(child: Text(
                    UellowApi.instance.lang == 'ar' ? 'لا توجد منتجات' : 'No products',
                    style: UT.small));
              }
              final items = snap.data!.take(10).toList();
              return ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                // v2.0.91 — shop "Recently arrived" row: clean card per
                // user spec (no discount, no save pill, no avail badge).
                itemBuilder: (_, i) => SizedBox(
                  width: 140, child: ProductCard(
                      product: items[i],
                      surface: 'category',
                      compact: true,
                      hideSavePill: true,
                      hideDiscount: true,
                      // v2.1.56 — free-shipping badge off in shop rows.
                      hideFreeShip: true)),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class _ProductsGrid extends StatelessWidget {
  const _ProductsGrid({required this.future});
  final Future<List<UellowProductCard>>? future;
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<UellowProductCard>>(
      future: future,
      builder: (_, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
        }
        if (snap.hasError || (snap.data?.isEmpty ?? true)) {
          return const SizedBox.shrink();
        }
        final items = snap.data!;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, crossAxisSpacing: 8, mainAxisSpacing: 8,
              // v2.0.79 — taller aspect to suit the compact card (no Save/Avail row)
              childAspectRatio: 0.66,
            ),
            itemCount: items.length,
            // v2.0.79 + v2.0.91 — shop "All products" grid: compact
            // card, no Save/Avail row, no discount badge/pill, smaller
            // fonts. The clean grid the user asked for.
            itemBuilder: (_, i) => ProductCard(
                product: items[i], surface: 'category',
                compact: true, hideSavePill: true, hideDiscount: true,
                // v2.1.56 — free-shipping badge off in shop grid.
                hideFreeShip: true),
          ),
        );
      },
    );
  }
}

// ─── Category header slider (v2.1.56) ────────────────────────────────
// Replaces the old static yellow banner. Slides are managed per MAIN
// category from the backend (eCommerce category form ▸ App Header
// Slides); each slide can link to a product, a category or a URL.
// Until the admin uploads slides, tasteful built-in default banners
// rotate (they all open the category collection page).

class _CategoryHeaderSlider extends StatefulWidget {
  const _CategoryHeaderSlider({super.key, required this.category});
  final UellowCategory category;
  @override
  State<_CategoryHeaderSlider> createState() => _CategoryHeaderSliderState();
}

class _CategoryHeaderSliderState extends State<_CategoryHeaderSlider> {
  List<Map<String, dynamic>>? _slides;   // null = loading
  final _page = PageController();
  Timer? _auto;
  int _i = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await UellowApi.instance.categories.slides(widget.category.id);
      if (!mounted) return;
      setState(() => _slides = s);
    } catch (_) {
      if (!mounted) return;
      setState(() => _slides = const []);
    }
    _scheduleAuto();
  }

  void _scheduleAuto() {
    _auto?.cancel();
    final n = _count;
    if (n <= 1) return;
    _auto = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_page.hasClients) return;
      final next = (_i + 1) % n;
      _page.animateToPage(next,
          duration: const Duration(milliseconds: 420), curve: Curves.easeOut);
    });
  }

  int get _count =>
      (_slides == null || _slides!.isEmpty) ? 3 : _slides!.length;

  void _openLink(Map<String, dynamic>? slide) {
    final link = (slide?['link'] as Map?)?.cast<String, dynamic>();
    final type = (link?['type'] ?? 'none').toString();
    final value = link?['value'];
    switch (type) {
      case 'product':
        final id = int.tryParse('$value') ?? 0;
        if (id > 0) { UellowRouter.goProduct(context, id); return; }
        break;
      case 'category':
        final id = int.tryParse('$value') ?? 0;
        if (id > 0) {
          Navigator.pushNamed(context, '/collection',
              arguments: {'category_id': id});
          return;
        }
        break;
      case 'url':
        final url = (value ?? '').toString();
        if (url.isNotEmpty) {
          Navigator.pushNamed(context, '/webview',
              arguments: {'url': url, 'title': ''});
          return;
        }
        break;
    }
    // default / no link → category collection
    Navigator.pushNamed(context, '/collection',
        arguments: {'category_id': widget.category.id});
  }

  @override
  void dispose() { _auto?.cancel(); _page.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (_slides == null) {
      return Container(
        height: 120,
        margin: const EdgeInsets.fromLTRB(10, 10, 10, 0),
        decoration: BoxDecoration(color: const Color(0xFFEFEFEF),
            borderRadius: BorderRadius.circular(12)),
      );
    }
    final hasReal = _slides!.isNotEmpty;
    return Container(
      height: 120,
      margin: const EdgeInsets.fromLTRB(10, 10, 10, 0),
      child: Stack(children: [
        PageView.builder(
          controller: _page,
          itemCount: _count,
          onPageChanged: (i) => setState(() => _i = i),
          itemBuilder: (_, i) => GestureDetector(
            onTap: () => _openLink(hasReal ? _slides![i] : null),
            child: Padding(
              padding: const EdgeInsetsDirectional.only(end: 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: hasReal
                    ? CachedNetworkImage(
                        imageUrl:
                            '${UellowApi.instance.baseUrl}${_slides![i]['image_url']}',
                        fit: BoxFit.cover, width: double.infinity,
                        placeholder: (_, __) =>
                            const ColoredBox(color: Color(0xFFEFEFEF)),
                        errorWidget: (_, __, ___) =>
                            _defaultSlide(i),
                      )
                    : _defaultSlide(i),
              ),
            ),
          ),
        ),
        // dots
        if (_count > 1) PositionedDirectional(
          bottom: 8, start: 0, end: 0,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var d = 0; d < _count; d++) AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 2.5),
              width: d == _i ? 16 : 6, height: 6,
              decoration: BoxDecoration(
                color: d == _i
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(999),
                boxShadow: const [BoxShadow(color: Color(0x33000000),
                    blurRadius: 3)],
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  // Built-in default banners (brand palette) — shown until the admin
  // uploads real slides from the backend.
  Widget _defaultSlide(int i) {
    final ar = UellowApi.instance.lang == 'ar';
    final name = widget.category.name.current(UellowApi.instance.lang);
    final presets = [
      (
        const [Color(0xFFF5C320), Color(0xFFFFE066)],
        '🛍️',
        ar ? 'تسوّق $name' : 'Shop $name',
        ar ? 'أفضل المنتجات بأفضل الأسعار' : 'Top picks at the best prices',
        UellowColors.darkBrown,
      ),
      (
        const [Color(0xFF412402), Color(0xFF6B4A1B)],
        '⚡',
        ar ? 'عروض $name' : '$name deals',
        ar ? 'خصومات يومية متجددة' : 'Fresh discounts every day',
        Colors.white,
      ),
      (
        const [Color(0xFF0EA5E9), Color(0xFF38BDF8)],
        '🚚',
        ar ? 'توصيل سريع' : 'Fast delivery',
        ar ? 'اطلب الآن واستلم خلال ساعات' : 'Order now, delivered in hours',
        Colors.white,
      ),
    ];
    final p = presets[i % presets.length];
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: p.$1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        Text(p.$2, style: const TextStyle(fontSize: 34)),
        const SizedBox(width: 12),
        Expanded(child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(p.$3, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w900,
                    fontSize: 15, color: p.$5)),
            const SizedBox(height: 3),
            Text(p.$4, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11,
                    color: p.$5.withValues(alpha: 0.85))),
          ],
        )),
        Icon(Icons.arrow_forward_ios, size: 14,
            color: p.$5.withValues(alpha: 0.8)),
      ]),
    );
  }
}
