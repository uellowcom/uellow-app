// =============================================================================
// BundlesScreen — full catalogue of published bundles (v2.2.23). Opened from
// the yellow "View more" on the Bundles Showcase block. 2-col grid with
// infinite scroll + sort/filter chips. Each card shows a clear bundle price,
// the struck "bought separately" total and the savings.
// =============================================================================
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../api/uellow_api.dart';
import '../../api/uellow_models.dart';
import '../router/uellow_router.dart';
import '../theme/uellow_theme.dart';

class BundlesScreen extends StatefulWidget {
  const BundlesScreen({super.key});
  @override
  State<BundlesScreen> createState() => _BundlesScreenState();
}

class _BundlesScreenState extends State<BundlesScreen> {
  final _scroll = ScrollController();
  final List<Map<String, dynamic>> _items = [];
  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;
  bool _loadedOnce = false;
  String _sort = 'featured';

  static const _sorts = [
    ('featured', 'Featured', 'مميّزة'),
    ('savings', 'Biggest savings', 'الأكثر توفيراً'),
    ('price_asc', 'Cheapest', 'الأرخص'),
    ('price_desc', 'Priciest', 'الأغلى'),
    ('items', 'Most items', 'الأكثر قطعاً'),
  ];

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 320) {
        _load();
      }
    });
    _load();
  }

  @override
  void dispose() { _scroll.dispose(); super.dispose(); }

  Future<void> _load() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final r = await http.get(
        Uri.parse('${UellowApi.instance.baseUrl}/api/mobile/v2/bundles'
            '?page=$_page&per_page=12&sort=$_sort'),
        headers: const {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 12));
      final body = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      final list = ((body['data']?['items'] as List?) ?? const [])
          .cast<dynamic>().map((e) => (e as Map).cast<String, dynamic>())
          .toList();
      final meta = (body['meta'] as Map?)?.cast<String, dynamic>();
      if (!mounted) return;
      setState(() {
        _items.addAll(list);
        _hasMore = (meta?['has_next'] as bool?)
            ?? (meta?['has_more'] as bool?) ?? (list.length >= 12);
        _page++;
        _loading = false;
        _loadedOnce = true;
      });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _loadedOnce = true; _hasMore = false; });
    }
  }

  void _changeSort(String s) {
    if (s == _sort) return;
    setState(() {
      _sort = s; _items.clear(); _page = 1; _hasMore = true; _loadedOnce = false;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang.toLowerCase().startsWith('ar');
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        title: Text(ar ? 'الباقات' : 'Bundles'),
        backgroundColor: Colors.white,
        foregroundColor: UellowColors.darkBrown,
        elevation: 0.5,
      ),
      body: Column(children: [
        // ── sort / filter chips ──
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: SizedBox(height: 34, child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _sorts.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final s = _sorts[i];
              final on = s.$1 == _sort;
              return GestureDetector(
                onTap: () => _changeSort(s.$1),
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: on ? const Color(0xFF7C3AED) : const Color(0xFFF1ECFB),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(ar ? s.$3 : s.$2, style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800,
                      color: on ? Colors.white : const Color(0xFF7C3AED))),
                ),
              );
            },
          )),
        ),
        Expanded(child: _body(ar)),
      ]),
    );
  }

  Widget _body(bool ar) {
    if (!_loadedOnce && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty) {
      return Center(child: Text(ar ? 'لا توجد باقات حالياً' : 'No bundles right now',
          style: UT.body));
    }
    return GridView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10,
        childAspectRatio: 0.66,
      ),
      itemCount: _items.length + (_hasMore ? 2 : 0),
      itemBuilder: (_, i) {
        if (i >= _items.length) {
          return const Center(child: Padding(
            padding: EdgeInsets.all(8),
            child: SizedBox(width: 22, height: 22,
                child: CircularProgressIndicator(strokeWidth: 2)),
          ));
        }
        return _BundleGridCard(b: _items[i], ar: ar);
      },
    );
  }
}

class _BundleGridCard extends StatelessWidget {
  const _BundleGridCard({required this.b, required this.ar});
  final Map<String, dynamic> b;
  final bool ar;

  @override
  Widget build(BuildContext context) {
    final lang = UellowApi.instance.lang;
    final card = (b['card'] as Map?)?.cast<String, dynamic>();
    final pid = (b['product_id'] as num?)?.toInt()
        ?? (card?['id'] as num?)?.toInt() ?? 0;
    final name = ((b['name'] as Map?)?[ar ? 'ar' : 'en'] ?? '').toString();
    final img = (card?['image'] ?? '').toString();
    final fullUrl = img.startsWith('http')
        ? img : '${UellowApi.instance.baseUrl}$img';
    // Clear pricing: bundle price (big) + struck components-total.
    final priceMap = (card?['price'] as Map?)?.cast<String, dynamic>();
    final price = priceMap != null
        ? UellowMoney.fromJson(priceMap)
        : UellowMoney(amount: (b['price'] as num?)?.toDouble() ?? 0,
            currency: 'KWD', symbol: 'KD', digits: 3);
    final total = (b['components_total'] as num?)?.toDouble() ?? 0;
    final savePct = (b['savings_pct'] as num?)?.toInt() ?? 0;
    final count = (b['component_count'] as num?)?.toInt() ?? 0;
    final unavailable = (b['listing_state'] ?? 'ok') == 'badge';

    return GestureDetector(
      onTap: () { if (pid > 0) UellowRouter.goProduct(context, pid); },
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [BoxShadow(color: Color(0x14000000),
              blurRadius: 8, offset: Offset(0, 3))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Stack(children: [
            AspectRatio(aspectRatio: 1, child: img.isNotEmpty
                ? CachedNetworkImage(imageUrl: fullUrl, fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                        color: const Color(0xFFF1ECFB)))
                : Container(color: const Color(0xFFF1ECFB),
                    child: const Icon(Icons.inventory_2_rounded,
                        color: Color(0xFF7C3AED), size: 34))),
            PositionedDirectional(top: 6, start: 6, child: _chip(
                const Color(0xFF7C3AED),
                count > 0 ? (ar ? '$count قطع' : '$count items')
                          : (ar ? 'باقة' : 'BUNDLE'),
                Icons.inventory_2_rounded)),
            if (savePct > 0) PositionedDirectional(top: 6, end: 6,
                child: _chip(const Color(0xFF16A34A),
                    ar ? 'وفّر $savePct%' : 'SAVE $savePct%', null)),
            if (unavailable) Positioned.fill(child: Container(
              color: Colors.white.withValues(alpha: .55),
              alignment: Alignment.center,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: const Color(0xCC111111),
                    borderRadius: BorderRadius.circular(6)),
                child: Text(ar ? 'غير متوفر' : 'UNAVAILABLE',
                    style: const TextStyle(color: Colors.white, fontSize: 9,
                        fontWeight: FontWeight.w900)),
              ),
            )),
          ]),
          Expanded(child: Padding(
            padding: const EdgeInsets.fromLTRB(9, 7, 9, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(name, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, height: 1.2,
                      fontWeight: FontWeight.w700, color: UellowColors.ink)),
              const Spacer(),
              // clear price line: amount + symbol, struck total under it
              Row(crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic, children: [
                Text(price.displayAmount(), style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w900,
                    color: Color(0xFF7C3AED))),
                const SizedBox(width: 3),
                Text(price.displaySymbol(lang), style: const TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w800,
                    color: Color(0xFF7C3AED))),
              ]),
              if (total > price.amount) Text(
                  ar ? 'بدل ${total.toStringAsFixed(price.digits)}'
                     : 'was ${total.toStringAsFixed(price.digits)}',
                  style: const TextStyle(fontSize: 10,
                      decoration: TextDecoration.lineThrough,
                      color: UellowColors.muted)),
            ]),
          )),
        ]),
      ),
    );
  }

  Widget _chip(Color bg, String text, IconData? icon) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(5)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      if (icon != null) ...[Icon(icon, size: 9, color: Colors.white),
        const SizedBox(width: 3)],
      Text(text, style: const TextStyle(color: Colors.white, fontSize: 8.5,
          fontWeight: FontWeight.w900)),
    ]),
  );
}
