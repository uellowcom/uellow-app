// =============================================================================
// CollectionScreen — single-category browse page (NOT the shop sidebar).
// Tapping a category opens this with that category's products.
//
// Layout:
//   • App bar with category name + back
//   • Sub-categories chip row at top (if any)
//   • Sort + filter bar
//   • Infinite-load 2-col products grid (server-paginated)
//
// Also serves as the global "search results" page when launched with
// `arguments: {'search': 'query'}`. The two flows share the same grid +
// pagination, so we keep one code path.
// =============================================================================
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../api/uellow_api.dart';
import '../../api/uellow_models.dart';
import '../router/uellow_router.dart';
import '../theme/uellow_theme.dart';
import '../widgets/product_card.dart';

class CollectionScreen extends StatefulWidget {
  const CollectionScreen({
    super.key, this.categoryId, this.searchQuery,
    this.brandValueId, this.brandName,
  });
  final int? categoryId;
  final String? searchQuery;
  final int? brandValueId;
  final String? brandName;
  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  UellowCategory? _category;
  final List<UellowProductCard> _items = [];
  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;
  String _sort = 'newest';
  final _scroll = ScrollController();
  // Selected filter value IDs across attributes
  final Set<int> _selectedValueIds = {};
  // v2.0.80 — extra filters from the redesigned dialog
  double? _minPrice;
  double? _maxPrice;
  int _minRating = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _bootstrap();
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (widget.categoryId != null) {
      try {
        _category = await UellowApi.instance.categories.detail(widget.categoryId!);
        if (mounted) setState(() {});
      } catch (_) {/* ignore */}
    }
    await _loadMore();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      UellowPage<UellowProductCard> page;
      if (widget.searchQuery != null && widget.searchQuery!.isNotEmpty) {
        page = (await UellowApi.instance.search.search(widget.searchQuery!,
                page: _page, perPage: 20)).asProductsPage();
      } else if (widget.brandValueId != null) {
        page = await UellowApi.instance.products.list(
              brandId: widget.brandValueId,
              page: _page, perPage: 20, sort: _sort);
      } else {
        // v2.0.80 — value_ids + new optional filters (min/max price,
        // min rating) flowing through to the products controller.
        final uri = Uri.parse('${UellowApi.instance.baseUrl}/api/mobile/v2/products')
            .replace(queryParameters: {
              if (widget.categoryId != null) 'category_id': '${widget.categoryId}',
              'page': '$_page', 'per_page': '20', 'sort': _sort,
              if (_selectedValueIds.isNotEmpty)
                'value_ids': _selectedValueIds.join(','),
              if (_minPrice != null) 'min_price': '${_minPrice!.toStringAsFixed(2)}',
              if (_maxPrice != null) 'max_price': '${_maxPrice!.toStringAsFixed(2)}',
              if (_minRating > 0) 'min_rating': '$_minRating',
            });
        final r = await http.get(uri, headers: {'Accept': 'application/json'});
        final body = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
        page = UellowPage.fromJson(body, (m) => UellowProductCard.fromJson(m));
      }
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _hasMore = page.hasNext;
        _page++;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _hasMore = false; });
    }
  }

  void _changeSort(String s) {
    if (s == _sort) return;
    setState(() {
      _sort = s;
      _items.clear();
      _page = 1;
      _hasMore = true;
    });
    _loadMore();
  }

  void _resetAndReload() {
    setState(() {
      _items.clear();
      _page = 1;
      _hasMore = true;
    });
    _loadMore();
  }

  Future<void> _openFilterSheet() async {
    if (widget.categoryId == null) return;
    final url = Uri.parse(
      '${UellowApi.instance.baseUrl}/api/mobile/v2/categories/${widget.categoryId}/filters'
    );
    Map<String, dynamic>? data;
    try {
      final r = await http.get(url);
      final body = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (body['success'] == true) data = body['data'] as Map<String, dynamic>;
    } catch (_) {}
    if (data == null || !mounted) return;
    final result = await showModalBottomSheet<FilterResult>(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FilterSheet(
        spec: data!,
        initial: Set<int>.from(_selectedValueIds),
        initialMinPrice: _minPrice,
        initialMaxPrice: _maxPrice,
        initialMinRating: _minRating,
        initialSort: _sort,
      ),
    );
    if (result != null) {
      _selectedValueIds
        ..clear()
        ..addAll(result.valueIds);
      _minPrice = result.minPrice;
      _maxPrice = result.maxPrice;
      _minRating = result.minRating;
      if (result.sortOverride != null) _sort = result.sortOverride!;
      _resetAndReload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = UellowApi.instance.lang;
    final title = widget.searchQuery != null && widget.searchQuery!.isNotEmpty
        ? 'Results for "${widget.searchQuery}"'
        : widget.brandName != null && widget.brandName!.isNotEmpty
          ? widget.brandName!
          : (_category?.name.current(lang) ?? 'Products');
    final subs = _category?.children ?? const <UellowCategory>[];
    return Scaffold(
      backgroundColor: UellowColors.bg,
      body: SafeArea(child: CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: Colors.white,
            elevation: 0.5,
            scrolledUnderElevation: 1,
            iconTheme: const IconThemeData(color: UellowColors.darkBrown),
            title: Text(title, style: const TextStyle(
                color: UellowColors.ink, fontWeight: FontWeight.w900, fontSize: 16)),
            actions: [
              IconButton(
                onPressed: () => Navigator.pushNamed(context, '/search'),
                icon: const Icon(Icons.search),
              ),
            ],
          ),
          if (subs.isNotEmpty) SliverToBoxAdapter(child: _SubcatStrip(subs: subs)),
          SliverToBoxAdapter(child: _SortBar(
            count: _items.length, sort: _sort, onSort: _changeSort,
            hideSort: widget.searchQuery != null,
            onFilter: widget.categoryId != null ? _openFilterSheet : null,
            activeFilterCount: _selectedValueIds.length,
          )),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, crossAxisSpacing: 8, mainAxisSpacing: 8,
                childAspectRatio: 0.58,
              ),
              delegate: SliverChildBuilderDelegate(
                (_, i) => ProductCard(product: _items[i]),
                childCount: _items.length,
              ),
            ),
          ),
          if (_loading) const SliverToBoxAdapter(child: Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator(
                color: UellowColors.darkBrown)),
          )),
          if (!_loading && _items.isEmpty) SliverToBoxAdapter(
            child: Padding(padding: const EdgeInsets.all(40),
              child: Column(children: [
                const Icon(Icons.search_off, size: 56, color: UellowColors.muted),
                const SizedBox(height: 12),
                Text(widget.searchQuery != null
                    ? 'No products match "${widget.searchQuery}"'
                    : 'No products in this category yet',
                    style: UT.body, textAlign: TextAlign.center),
              ]),
            ),
          ),
          if (!_hasMore && _items.isNotEmpty) const SliverToBoxAdapter(
            child: Padding(padding: EdgeInsets.all(20),
                child: Center(child: Text('—  end of results  —',
                    style: TextStyle(color: UellowColors.muted)))),
          ),
        ],
      )),
    );
  }
}

class _SubcatStrip extends StatelessWidget {
  const _SubcatStrip({required this.subs});
  final List<UellowCategory> subs;
  @override
  Widget build(BuildContext context) {
    final lang = UellowApi.instance.lang;
    // v2.0.78 — subcategory thumbs: light-gray background (was yellow);
    // tighter vertical padding so the gap to the filter/sort bar below
    // doesn't feel like a separate band.
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: SizedBox(height: 92, child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: subs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final c = subs[i];
          return GestureDetector(
            onTap: () => UellowRouter.goCollection(context, c.id),
            child: SizedBox(width: 72, child: Column(children: [
              Container(
                width: 60, height: 60,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFEFEF),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE5E5E5)),
                ),
                clipBehavior: Clip.antiAlias,
                child: (c.image != null && c.image!.isNotEmpty)
                  ? CachedNetworkImage(imageUrl: c.image!, fit: BoxFit.cover,
                      errorWidget: (_,__,___) => const Center(
                          child: Text('📦', style: TextStyle(fontSize: 26))))
                  : const Center(child: Text('📦', style: TextStyle(fontSize: 26))),
              ),
              const SizedBox(height: 4),
              Text(c.name.current(lang), maxLines: 1, overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 10.5,
                      fontWeight: FontWeight.w700, color: UellowColors.darkBrown)),
            ])),
          );
        },
      )),
    );
  }
}

class _SortBar extends StatelessWidget {
  const _SortBar({required this.count, required this.sort, required this.onSort,
      this.hideSort = false, this.onFilter, this.activeFilterCount = 0});
  final int count;
  final String sort;
  final ValueChanged<String> onSort;
  final bool hideSort;
  final VoidCallback? onFilter;
  final int activeFilterCount;
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: UellowColors.border)),
      ),
      child: Row(children: [
        Text.rich(TextSpan(style: const TextStyle(fontSize: 12, color: UellowColors.muted), children: [
          TextSpan(text: '$count', style: const TextStyle(
              fontWeight: FontWeight.w900, color: UellowColors.ink)),
          const TextSpan(text: '+ products'),
        ])),
        const Spacer(),
        if (!hideSort) GestureDetector(
          onTap: () async {
            final picked = await showModalBottomSheet<String>(
              context: context,
              builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
                _opt(context, 'newest', 'Newest first'),
                _opt(context, 'price_asc', 'Price: low → high'),
                _opt(context, 'price_desc', 'Price: high → low'),
                _opt(context, 'popular', 'Most popular'),
                _opt(context, 'top_rated', 'Top rated'),
              ]),
            );
            if (picked != null) onSort(picked);
          },
          child: Row(children: const [
            Icon(Icons.swap_vert, size: 14, color: UellowColors.darkBrown),
            SizedBox(width: 3),
            Text('Sort', style: TextStyle(fontSize: 12,
                fontWeight: FontWeight.w700, color: UellowColors.darkBrown)),
          ]),
        ),
        const SizedBox(width: 16),
        if (onFilter != null) GestureDetector(
          onTap: onFilter,
          child: Row(children: [
            const Icon(Icons.tune, size: 14, color: UellowColors.darkBrown),
            const SizedBox(width: 3),
            const Text('Filter', style: TextStyle(fontSize: 12,
                fontWeight: FontWeight.w700, color: UellowColors.darkBrown)),
            if (activeFilterCount > 0) Padding(
              padding: const EdgeInsets.only(left: 5),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: const BoxDecoration(
                    color: UellowColors.yellow, shape: BoxShape.rectangle,
                    borderRadius: BorderRadius.all(Radius.circular(6))),
                child: Text('$activeFilterCount',
                    style: const TextStyle(fontSize: 10,
                        fontWeight: FontWeight.w900, color: UellowColors.darkBrown)),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
  Widget _opt(BuildContext context, String key, String label) => ListTile(
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        selected: sort == key,
        onTap: () => Navigator.pop(context, key),
      );
}

// ─── Filter bottom sheet ──────────────────────────────────────────

// v2.0.80 — return type for the redesigned filter sheet so the screen
// can pull every choice out (was just a Set<int> of attribute values).
class FilterResult {
  FilterResult({
    required this.valueIds,
    this.minPrice, this.maxPrice,
    this.minRating = 0,
    this.sortOverride,
  });
  final Set<int> valueIds;
  final double? minPrice;
  final double? maxPrice;
  final int minRating;
  final String? sortOverride;
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.spec, required this.initial,
    this.initialMinPrice, this.initialMaxPrice,
    this.initialMinRating = 0, this.initialSort,
  });
  final Map<String, dynamic> spec;
  final Set<int> initial;
  final double? initialMinPrice;
  final double? initialMaxPrice;
  final int initialMinRating;
  final String? initialSort;
  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late Set<int> _selected;
  RangeValues? _priceRange;
  late double _priceMin, _priceMax;
  late int _minRating;
  late String _sort;
  @override
  void initState() {
    super.initState();
    _selected = Set<int>.from(widget.initial);
    final price = widget.spec['price'] as Map<String, dynamic>?;
    _priceMin = ((price?['min'] as num?)?.toDouble()) ?? 0;
    _priceMax = ((price?['max'] as num?)?.toDouble()) ?? 1000;
    if (_priceMax <= _priceMin) _priceMax = _priceMin + 100;
    final lo = widget.initialMinPrice ?? _priceMin;
    final hi = widget.initialMaxPrice ?? _priceMax;
    _priceRange = RangeValues(
        lo.clamp(_priceMin, _priceMax),
        hi.clamp(_priceMin, _priceMax));
    _minRating = widget.initialMinRating;
    _sort = widget.initialSort ?? 'newest';
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    final attrs = (widget.spec['attributes'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    final price = widget.spec['price'] as Map<String, dynamic>?;
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // ── Header ─────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(bottom: BorderSide(color: UellowColors.border)),
          ),
          child: Column(children: [
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: UellowColors.border,
                    borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 14),
            Row(children: [
              const Icon(Icons.tune, color: UellowColors.darkBrown),
              const SizedBox(width: 10),
              Text(ar ? 'تصفية النتائج' : 'Filter results', style: UT.h2),
              const Spacer(),
              if (_selected.isNotEmpty) TextButton.icon(
                onPressed: () => setState(_selected.clear),
                icon: const Icon(Icons.refresh, size: 16, color: UellowColors.danger),
                label: Text(ar ? 'إعادة ضبط' : 'Reset',
                    style: const TextStyle(color: UellowColors.danger,
                        fontWeight: FontWeight.w800)),
              ),
            ]),
          ]),
        ),
        // ── Filter list ────────────────────────────────────
        // v2.0.80 — sectioned layout: Sort, Price slider, Rating, then
        // the attribute groups. Each is in its own card with a divider
        // between for clear visual grouping.
        Flexible(child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            children: [
          _sortCard(ar),
          const SizedBox(height: 12),
          if (price != null) _priceSliderCard(price, ar),
          if (price != null) const SizedBox(height: 12),
          _ratingCard(ar),
          const SizedBox(height: 18),
          for (final a in attrs) _attrGroup(a),
        ])),
        // ── Footer CTAs ────────────────────────────────────
        SafeArea(top: false, child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: UellowColors.border)),
            boxShadow: [BoxShadow(
                color: Color(0x14000000), blurRadius: 12, offset: Offset(0, -2))],
          ),
          child: Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: UellowColors.border, width: 1.5),
              ),
              child: Text(ar ? 'إلغاء' : 'Cancel',
                  style: const TextStyle(color: UellowColors.text,
                      fontWeight: FontWeight.w800)),
            )),
            const SizedBox(width: 10),
            Expanded(flex: 2, child: ElevatedButton.icon(
              onPressed: () {
                final r = _priceRange;
                Navigator.pop(context, FilterResult(
                  valueIds: _selected,
                  minPrice: (r != null && r.start > _priceMin) ? r.start : null,
                  maxPrice: (r != null && r.end < _priceMax) ? r.end : null,
                  minRating: _minRating,
                  sortOverride: _sort,
                ));
              },
              icon: const Icon(Icons.check, size: 16, color: UellowColors.darkBrown),
              label: Text(ar
                  ? 'تطبيق ${_selected.isNotEmpty ? "(${_selected.length})" : ""}'.trim()
                  : 'Apply ${_selected.isNotEmpty ? "(${_selected.length})" : ""}'.trim(),
                  style: const TextStyle(fontWeight: FontWeight.w900,
                      color: UellowColors.darkBrown, fontSize: 15)),
              style: ElevatedButton.styleFrom(
                backgroundColor: UellowColors.yellow,
                foregroundColor: UellowColors.darkBrown,
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 4,
                shadowColor: UellowColors.yellow.withValues(alpha: 0.45),
              ),
            )),
          ]),
        )),
      ]),
    );
  }

  // v2.0.80 — interactive price range slider replacing the static card.
  Widget _priceSliderCard(Map<String, dynamic> p, bool ar) {
    final currency = (p['currency'] as String?) ?? '';
    final r = _priceRange ?? RangeValues(_priceMin, _priceMax);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: UellowColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.local_offer_outlined, size: 16,
              color: UellowColors.darkBrown),
          const SizedBox(width: 6),
          Text(ar ? 'نطاق السعر' : 'Price range',
              style: const TextStyle(fontSize: 12.5,
                  fontWeight: FontWeight.w900, color: UellowColors.ink,
                  letterSpacing: 0.2)),
          const Spacer(),
          Text('${r.start.toStringAsFixed(0)} – ${r.end.toStringAsFixed(0)} $currency',
              style: const TextStyle(fontSize: 11.5,
                  color: UellowColors.darkBrown, fontWeight: FontWeight.w900)),
        ]),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: UellowColors.yellow,
            inactiveTrackColor: UellowColors.bg,
            thumbColor: UellowColors.darkBrown,
            overlayColor: UellowColors.yellow.withValues(alpha: 0.2),
            valueIndicatorColor: UellowColors.darkBrown,
            trackHeight: 3,
          ),
          child: RangeSlider(
            min: _priceMin, max: _priceMax,
            divisions: ((_priceMax - _priceMin).clamp(1, 200)).toInt(),
            values: r,
            labels: RangeLabels(
                r.start.toStringAsFixed(0), r.end.toStringAsFixed(0)),
            onChanged: (v) => setState(() => _priceRange = v),
          ),
        ),
      ]),
    );
  }

  // v2.0.80 — minimum-rating chips (Any · 4★+ · 3★+ · 2★+).
  Widget _ratingCard(bool ar) {
    Widget chip(int v, String label) {
      final on = _minRating == v;
      return GestureDetector(
        onTap: () => setState(() => _minRating = v),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: on ? UellowColors.yellow : Colors.white,
            border: Border.all(
                color: on ? UellowColors.yellow : UellowColors.border,
                width: on ? 0 : 1),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (v > 0) ...[
              const Icon(Icons.star_rounded, size: 13,
                  color: UellowColors.darkBrown),
              const SizedBox(width: 2),
            ],
            Text(label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: on ? UellowColors.darkBrown : UellowColors.ink,
                )),
          ]),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: UellowColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.star_outline_rounded, size: 16,
              color: UellowColors.darkBrown),
          const SizedBox(width: 6),
          Text(ar ? 'الحد الأدنى للتقييم' : 'Minimum rating',
              style: const TextStyle(fontSize: 12.5,
                  fontWeight: FontWeight.w900, color: UellowColors.ink,
                  letterSpacing: 0.2)),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          chip(0, ar ? 'الكل' : 'Any'),
          chip(4, '4+'),
          chip(3, '3+'),
          chip(2, '2+'),
        ]),
      ]),
    );
  }

  // v2.0.80 — in-dialog sort chips so the user can re-order without
  // leaving the sheet (was only outside in the SortBar).
  Widget _sortCard(bool ar) {
    final sorts = ar
      ? const [
          ['popular',    '🏆 الأكثر مبيعاً'],
          ['newest',     '✨ الأحدث'],
          ['top_rated',  '⭐ الأعلى تقييماً'],
          ['price_asc',  '⬆️ السعر تصاعدي'],
          ['price_desc', '⬇️ السعر تنازلي'],
        ]
      : const [
          ['popular',    '🏆 Bestsellers'],
          ['newest',     '✨ Newest'],
          ['top_rated',  '⭐ Top rated'],
          ['price_asc',  '⬆️ Price low–high'],
          ['price_desc', '⬇️ Price high–low'],
        ];
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: UellowColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.sort, size: 16, color: UellowColors.darkBrown),
          const SizedBox(width: 6),
          Text(ar ? 'الترتيب' : 'Sort by',
              style: const TextStyle(fontSize: 12.5,
                  fontWeight: FontWeight.w900, color: UellowColors.ink,
                  letterSpacing: 0.2)),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final s in sorts)
            GestureDetector(
              onTap: () => setState(() => _sort = s[0]),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: _sort == s[0] ? UellowColors.yellow : Colors.white,
                  border: Border.all(
                      color: _sort == s[0] ? UellowColors.yellow : UellowColors.border,
                      width: _sort == s[0] ? 0 : 1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(s[1],
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: _sort == s[0] ? UellowColors.darkBrown : UellowColors.ink,
                    )),
              ),
            ),
        ]),
      ]),
    );
  }

  Widget _attrGroup(Map<String, dynamic> a) {
    final lang = UellowApi.instance.lang;
    final attrName = ((a['name'] as Map?)?[lang] as String?) ??
                     ((a['name'] as Map?)?['en'] as String?) ?? '';
    final attrLow = attrName.toLowerCase();
    final isColor = attrLow.contains('color') || attrName.contains('لون');
    final isBrand = attrLow.contains('brand') || attrName.contains('ماركة')
                 || attrName.contains('براند');
    final values = (a['values'] as List? ?? const []).cast<Map<String, dynamic>>();
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(isColor ? Icons.palette
                       : (isBrand ? Icons.local_offer : Icons.label),
              size: 16, color: UellowColors.darkBrown),
          const SizedBox(width: 6),
          Text(attrName, style: const TextStyle(
              fontSize: 13.5, color: UellowColors.ink,
              fontWeight: FontWeight.w900, letterSpacing: 0.2)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: UellowColors.bg,
                borderRadius: BorderRadius.circular(999)),
            child: Text('${values.length}', style: const TextStyle(
                fontSize: 10, color: UellowColors.muted, fontWeight: FontWeight.w800)),
          ),
        ]),
        const SizedBox(height: 12),
        if (isBrand)
          // 3-column grid of brand logo tiles — visually distinct from
          // plain text chips, makes scanning huge brand lists fast.
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8,
              childAspectRatio: 1.7,
            ),
            itemCount: values.length,
            itemBuilder: (_, i) => _brandTile(values[i]),
          )
        else
          Wrap(spacing: 8, runSpacing: 8, children: values.map((v) =>
              isColor ? _colorChip(v) : _textChip(v)).toList()),
      ]),
    );
  }

  Widget _brandTile(Map<String, dynamic> v) {
    final id = v['id'] as int;
    final on = _selected.contains(id);
    final name = ((v['name'] as Map?)?[UellowApi.instance.lang] as String?) ??
                 ((v['name'] as Map?)?['en'] as String?) ?? '';
    final logo = v['image'] as String?;
    final cnt = v['count'] as int? ?? 0;
    return GestureDetector(
      onTap: () => setState(() {
        on ? _selected.remove(id) : _selected.add(id);
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: on ? UellowColors.yellowFaint : Colors.white,
          border: Border.all(
              color: on ? UellowColors.yellow : UellowColors.border,
              width: on ? 2 : 1),
          borderRadius: BorderRadius.circular(12),
          boxShadow: on ? [BoxShadow(
              color: UellowColors.yellow.withValues(alpha: 0.25),
              blurRadius: 8, offset: const Offset(0, 2))]
            : const [BoxShadow(
              color: Color(0x0A000000),
              blurRadius: 4, offset: Offset(0, 1))],
        ),
        child: Stack(children: [
          if (on) Positioned(top: 0, right: 0, child: Container(
            width: 18, height: 18, alignment: Alignment.center,
            decoration: const BoxDecoration(
                color: UellowColors.darkBrown, shape: BoxShape.circle),
            child: const Icon(Icons.check, size: 11, color: UellowColors.yellowLight))),
          Column(mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: (logo != null && logo.isNotEmpty)
                ? Image.network(logo, fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => _brandTextFallback(name))
                : _brandTextFallback(name)),
            const SizedBox(height: 4),
            if (cnt > 0) Text('$cnt', textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 9.5,
                    fontWeight: FontWeight.w800, color: UellowColors.muted)),
          ]),
        ]),
      ),
    );
  }

  Widget _brandTextFallback(String name) => Container(
    alignment: Alignment.center,
    child: Text(name, textAlign: TextAlign.center, maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11,
            fontWeight: FontWeight.w900, color: UellowColors.darkBrown)),
  );

  Color _parseHex(String hex) {
    final h = hex.replaceAll('#', '');
    if (h.length == 6) {
      try { return Color(int.parse('ff$h', radix: 16)); } catch (_) {}
    }
    return UellowColors.border;
  }

  Widget _colorChip(Map<String, dynamic> v) {
    final id = v['id'] as int;
    final hex = (v['html_color'] as String?) ?? '';
    final color = _parseHex(hex);
    final on = _selected.contains(id);
    final name = ((v['name'] as Map?)?[UellowApi.instance.lang] as String?) ??
                 ((v['name'] as Map?)?['en'] as String?) ?? '';
    return GestureDetector(
      onTap: () => setState(() {
        on ? _selected.remove(id) : _selected.add(id);
      }),
      child: Tooltip(
        message: name,
        child: Container(
          width: 44, height: 44,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(
                color: on ? UellowColors.darkBrown : UellowColors.border,
                width: on ? 3 : 1.5),
            boxShadow: on ? const [BoxShadow(
                color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2))]
              : null,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: color, shape: BoxShape.circle,
              border: Border.all(color: const Color(0x14000000)),
            ),
            alignment: Alignment.center,
            child: on
              ? Icon(Icons.check, size: 16,
                  color: ThemeData.estimateBrightnessForColor(color) == Brightness.light
                      ? UellowColors.darkBrown : Colors.white)
              : null,
          ),
        ),
      ),
    );
  }

  Widget _textChip(Map<String, dynamic> v) {
    final id = v['id'] as int;
    final on = _selected.contains(id);
    final name = ((v['name'] as Map?)?[UellowApi.instance.lang] as String?) ??
                 ((v['name'] as Map?)?['en'] as String?) ?? '';
    final cnt = v['count'] as int? ?? 0;
    return GestureDetector(
      onTap: () => setState(() {
        on ? _selected.remove(id) : _selected.add(id);
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: on ? UellowColors.yellow : Colors.white,
          border: Border.all(
              color: on ? UellowColors.yellow : UellowColors.border,
              width: 1.5),
          borderRadius: BorderRadius.circular(999),
          boxShadow: on ? [BoxShadow(
              color: UellowColors.yellow.withValues(alpha: 0.3),
              blurRadius: 8, offset: const Offset(0, 2))] : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (on) const Padding(
            padding: EdgeInsets.only(right: 4),
            child: Icon(Icons.check_circle, size: 14, color: UellowColors.darkBrown),
          ),
          Text(name, style: TextStyle(
            fontWeight: FontWeight.w800,
            color: on ? UellowColors.darkBrown : UellowColors.text,
            fontSize: 13,
          )),
          if (cnt > 0 && !on) Padding(
            padding: const EdgeInsets.only(left: 5),
            child: Text('$cnt', style: const TextStyle(
                fontSize: 10.5, color: UellowColors.muted,
                fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
    );
  }
}

extension on UellowSearchResult {
  UellowPage<UellowProductCard> asProductsPage() => UellowPage<UellowProductCard>(
        items: products, page: 1, perPage: products.length,
        total: products.length, pages: 1, hasNext: false,
      );
}
