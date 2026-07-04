// =============================================================================
// Uellow World (Dropship) — customer-facing entry + browsing screens.
//
// WorldScreen        : entry page — country grid + China Hub (mirrors the app's
//                      design; brand colors) → opens WorldShopScreen.
// WorldShopScreen    : product grid over GET /api/mobile/v2/dropship/feed
//                      (same JSON contract as every other listing, so the cards
//                      look identical). Tapping a card calls /dropship/open which
//                      materializes a real product and returns its id, then we
//                      push the STANDARD product screen — no difference.
//
// Wiring (add during the release):
//   • reach it from a header icon / menu:
//       Navigator.push(context,
//         MaterialPageRoute(builder: (_) => const WorldScreen()));
// =============================================================================
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../api/uellow_api.dart';
import '../router/uellow_router.dart';
import '../theme/uellow_theme.dart';

const _brandDark = Color(0xFF412402);
const _brandYellow = UellowColors.yellow;

// ── country tiles (China featured; China also present as a normal country) ──
const List<Map<String, String>> _kCountries = [
  {'flag': '🇨🇳', 'en': 'China', 'ar': 'الصين', 'code': 'CN', 'feat': '1'},
  {'flag': '🇦🇪', 'en': 'UAE', 'ar': 'الإمارات', 'code': 'AE', 'feat': '0'},
  {'flag': '🇸🇦', 'en': 'Saudi Arabia', 'ar': 'السعودية', 'code': 'SA', 'feat': '0'},
  {'flag': '🇰🇼', 'en': 'Kuwait', 'ar': 'الكويت', 'code': 'KW', 'feat': '0'},
  {'flag': '🇶🇦', 'en': 'Qatar', 'ar': 'قطر', 'code': 'QA', 'feat': '0'},
  {'flag': '🇴🇲', 'en': 'Oman', 'ar': 'عُمان', 'code': 'OM', 'feat': '0'},
  {'flag': '🇹🇷', 'en': 'Türkiye', 'ar': 'تركيا', 'code': 'TR', 'feat': '0'},
  {'flag': '🇺🇸', 'en': 'USA', 'ar': 'أمريكا', 'code': 'US', 'feat': '0'},
];

// =============================================================================
// Entry: country grid + China Hub
// =============================================================================
class WorldScreen extends StatelessWidget {
  const WorldScreen({super.key});

  void _openShop(BuildContext context, {String? country}) {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => WorldShopScreen(country: country)));
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: UellowColors.bg,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: _brandDark,
          elevation: 0,
          title: Text(ar ? '🌍 يلو وورلد' : '🌍 Uellow World',
              style: const TextStyle(
                  color: Color(0xFF1A1A1A),
                  fontWeight: FontWeight.w800, fontSize: 17)),
        ),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 30),
          children: [
            // hero
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 26, 16, 26),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [_brandDark, Color(0xFF63410C)]),
              ),
              child: Column(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
                  decoration: BoxDecoration(
                      color: _brandYellow,
                      borderRadius: BorderRadius.circular(999)),
                  child: Text(ar ? '🌍 يلو وورلد' : '🌍 Uellow World',
                      style: const TextStyle(
                          color: _brandDark, fontWeight: FontWeight.w900, fontSize: 13)),
                ),
                const SizedBox(height: 10),
                Text(ar ? 'العالم كله في جيبك' : 'The whole world in your pocket',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22)),
              ]),
            ),
            // countries
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
              child: Text(ar ? 'الدول' : 'Countries',
                  style: const TextStyle(
                      color: _brandDark, fontWeight: FontWeight.w800, fontSize: 15)),
            ),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.92,
              children: _kCountries.map((c) {
                final feat = c['feat'] == '1';
                return GestureDetector(
                  onTap: () => _openShop(context, country: c['code']),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: feat ? _brandYellow : Colors.transparent, width: 2),
                      boxShadow: const [BoxShadow(
                          color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2))],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(c['flag']!, style: const TextStyle(fontSize: 38)),
                        const SizedBox(height: 6),
                        Text(ar ? c['ar']! : c['en']!,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, color: _brandDark, fontSize: 13)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            // China Hub
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Text(ar ? 'مميّز' : 'Featured',
                  style: const TextStyle(
                      color: _brandDark, fontWeight: FontWeight.w800, fontSize: 15)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GestureDetector(
                onTap: () => _openShop(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [_brandDark, Color(0xFF7A4E12)]),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(children: [
                    const Text('🏪', style: TextStyle(fontSize: 34)),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('China Hub',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900, fontSize: 18)),
                          const SizedBox(height: 2),
                          Text(
                              ar ? 'وجهة الصين الكبرى — أفضل المنتجات والعروض'
                                 : 'The great China destination — top picks & deals',
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12.5)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                          color: _brandYellow,
                          borderRadius: BorderRadius.circular(999)),
                      child: Text(ar ? 'مميّز' : 'Featured',
                          style: const TextStyle(
                              color: _brandDark, fontWeight: FontWeight.w900, fontSize: 12)),
                    ),
                  ]),
                ),
              ),
            ),
            // Shop by category — real, functional filters (unlike countries).
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 22, 16, 8),
              child: Text(ar ? 'تسوّق حسب القسم' : 'Shop by Category',
                  style: const TextStyle(
                      color: _brandDark, fontWeight: FontWeight.w800, fontSize: 15)),
            ),
            const _WorldCategoryGrid(),
          ],
        ),
      ),
    );
  }
}

// ─── Category grid on the World entry (fetched, tap → filtered shop) ──
class _WorldCategoryGrid extends StatefulWidget {
  const _WorldCategoryGrid();
  @override
  State<_WorldCategoryGrid> createState() => _WorldCategoryGridState();
}

class _WorldCategoryGridState extends State<_WorldCategoryGrid> {
  List<Map<String, dynamic>> _cats = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await UellowApi.instance.getRaw(
          '/api/mobile/v2/dropship/categories', query: {'limit': 18});
      final data = (res['data'] as Map?)?.cast<String, dynamic>() ?? res;
      final list = (data['items'] as List?) ?? const [];
      _cats = list.map((e) => (e as Map).cast<String, dynamic>()).toList();
    } catch (_) {
      _cats = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator(color: _brandYellow)));
    }
    if (_cats.isEmpty) return const SizedBox.shrink();
    final ar = UellowApi.instance.lang == 'ar';
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.92,
      children: _cats.map((c) {
        final label = (c['label'] as Map?)?.cast<String, dynamic>() ?? const {};
        final title = (ar ? (label['ar'] ?? label['en']) : (label['en'] ?? label['ar']) ?? '').toString();
        return GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => WorldShopScreen(
                  category: (c['code'] ?? '').toString(),
                  categoryLabel: title))),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [BoxShadow(
                  color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2))],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text((c['icon'] ?? '🏷️').toString(),
                    style: const TextStyle(fontSize: 30)),
                const SizedBox(height: 6),
                Text(title,
                    maxLines: 2, textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, color: _brandDark, fontSize: 11.5)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// =============================================================================
// Product grid (same card look as the rest of the app)
// =============================================================================
class WorldShopScreen extends StatefulWidget {
  final String? country;
  final String? category;        // dropship.category code (filter key)
  final String? categoryLabel;   // display label for the app bar
  const WorldShopScreen({super.key, this.country, this.category, this.categoryLabel});
  @override
  State<WorldShopScreen> createState() => _WorldShopScreenState();
}

class _WorldShopScreenState extends State<WorldShopScreen> {
  final List<Map<String, dynamic>> _items = [];
  final _scroll = ScrollController();
  bool _loading = false;
  bool _hasMore = true;
  bool _deals = false;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _load();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400 &&
          !_loading && _hasMore) {
        _load();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final res = await UellowApi.instance.getRaw(
          '/api/mobile/v2/dropship/feed',
          query: {
            'page': _page,
            'per_page': 20,
            if (_deals) 'deals_only': 1,
            if (widget.country != null) 'country': widget.country,
            if (widget.category != null) 'category': widget.category,
          });
      final data = (res['data'] as Map?)?.cast<String, dynamic>() ?? res;
      final list = (data['items'] as List?) ?? const [];
      for (final j in list) {
        _items.add((j as Map).cast<String, dynamic>());
      }
      _hasMore = data['has_more'] == true && list.isNotEmpty;
      _page++;
    } catch (_) {
      _hasMore = false;
    }
    if (mounted) setState(() => _loading = false);
  }

  void _toggleDeals() {
    setState(() {
      _deals = !_deals;
      _page = 1; _hasMore = true; _items.clear();
    });
    _load();
  }

  Future<void> _open(int dsId) async {
    try {
      final res = await UellowApi.instance.getRaw(
          '/api/mobile/v2/dropship/open', query: {'id': dsId});
      final data = (res['data'] as Map?)?.cast<String, dynamic>() ?? res;
      final pid = (data['product_id'] ?? 0) as int;
      if (pid > 0 && mounted) UellowRouter.goProduct(context, pid);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: UellowColors.bg,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: _brandDark,
          elevation: 0,
          title: Text(
              widget.categoryLabel ?? (ar ? '🌍 يلو وورلد' : '🌍 Uellow World'),
              style: const TextStyle(
                  color: Color(0xFF1A1A1A), fontWeight: FontWeight.w800, fontSize: 17)),
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: GestureDetector(
                onTap: _toggleDeals,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _deals ? _brandDark : const Color(0xFFF2F2F2),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(ar ? '🔥 عروض' : '🔥 Deals',
                      style: TextStyle(
                          color: _deals ? Colors.white : _brandDark,
                          fontWeight: FontWeight.w800, fontSize: 12.5)),
                ),
              ),
            ),
          ],
        ),
        body: _items.isEmpty && _loading
            ? const Center(child: CircularProgressIndicator(color: _brandYellow))
            : GridView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 200,
                  mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.62),
                itemCount: _items.length + (_hasMore ? 1 : 0),
                itemBuilder: (_, i) {
                  if (i >= _items.length) {
                    return const Center(child: SizedBox(
                        width: 22, height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.4, color: _brandYellow)));
                  }
                  return _card(_items[i], ar);
                },
              ),
      ),
    );
  }

  Widget _card(Map<String, dynamic> p, bool ar) {
    final name = (p['name'] as Map?)?.cast<String, dynamic>() ?? const {};
    final price = (p['price'] as Map?)?.cast<String, dynamic>() ?? const {};
    final cmp = (p['compare_price'] as Map?)?.cast<String, dynamic>();
    final disc = (p['discount_pct'] ?? 0) as int;
    final title = (ar ? (name['ar'] ?? name['en']) : (name['en'] ?? name['ar']) ?? '').toString();
    final sym = (price['symbol'] ?? 'KD').toString();
    return GestureDetector(
      onTap: () => _open((p['id'] ?? 0) as int),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [BoxShadow(
              color: Color(0x0D000000), blurRadius: 8, offset: Offset(0, 2))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(children: [
                Positioned.fill(
                  child: CachedNetworkImage(
                    imageUrl: (p['image'] ?? '').toString(),
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(color: const Color(0xFFF2F2F2)),
                    errorWidget: (_, __, ___) =>
                        Container(color: const Color(0xFFF2F2F2)),
                  ),
                ),
                if (disc > 0)
                  Positioned(
                    top: 8, left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                          color: const Color(0xFFFF4D4D),
                          borderRadius: BorderRadius.circular(8)),
                      child: Text('-$disc%',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800, fontSize: 12)),
                    ),
                  ),
                if (p['has_video'] == true)
                  const Positioned(
                    top: 8, right: 8,
                    child: CircleAvatar(
                        radius: 13, backgroundColor: Colors.black54,
                        child: Text('▶', style: TextStyle(
                            color: Colors.white, fontSize: 11))),
                  ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12.5, height: 1.3,
                          color: Color(0xFF1A1A1A), fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Row(crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                    Text('${price['amount'] ?? 0}',
                        style: const TextStyle(
                            color: _brandDark, fontWeight: FontWeight.w900, fontSize: 15)),
                    const SizedBox(width: 3),
                    Text(sym, style: const TextStyle(
                        color: _brandDark, fontWeight: FontWeight.w700, fontSize: 11)),
                    if (cmp != null) ...[
                      const SizedBox(width: 6),
                      Text('${cmp['amount']}',
                          style: const TextStyle(
                              color: Color(0xFF9A9A9A), fontSize: 11,
                              decoration: TextDecoration.lineThrough)),
                    ],
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
