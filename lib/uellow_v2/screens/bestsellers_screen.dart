// =============================================================================
// BestsellersScreen (v2.1.61) — the full ranked bestsellers ladder.
// Opened from the Champions-Arena block's «عرض المزيد»: a gold hero header
// + ordered list rows (🥇🥈🥉 then #N) with image, name, price, sold count
// and rating. Infinite scroll over /api/mobile/v2/products/bestsellers
// (same daily-rank ladder the home block uses, so the order matches).
// =============================================================================
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../api/uellow_api.dart';
import '../../api/uellow_models.dart';
import '../router/uellow_router.dart';
import '../theme/uellow_theme.dart';

class BestsellersScreen extends StatefulWidget {
  const BestsellersScreen({super.key});
  @override
  State<BestsellersScreen> createState() => _BestsellersScreenState();
}

class _BestsellersScreenState extends State<BestsellersScreen> {
  final List<UellowProductCard> _items = [];
  final List<int> _ranks = [];
  final _scroll = ScrollController();
  bool _loading = false;
  bool _hasMore = true;
  int _page = 1;
  int _catId = 0;                          // 0 = all
  List<UellowCategory> _cats = const [];

  @override
  void initState() {
    super.initState();
    _load();
    UellowApi.instance.categories.tree().then((c) {
      if (mounted) setState(() => _cats = c.take(14).toList());
    }).catchError((_) {});
    _scroll.addListener(() {
      if (_scroll.position.pixels >
              _scroll.position.maxScrollExtent - 400 &&
          !_loading && _hasMore) {
        _load();
      }
    });
  }

  void _selectCat(int id) {
    if (id == _catId) return;
    setState(() {
      _catId = id; _page = 1; _hasMore = true;
      _items.clear(); _ranks.clear();
    });
    _load();
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
          '/api/mobile/v2/products/bestsellers',
          query: {'page': _page, 'per_page': 20,
            if (_catId > 0) 'category_id': _catId});
      final data = (res['data'] as Map?)?.cast<String, dynamic>() ?? res;
      final list = (data['items'] as List?) ?? const [];
      for (final j in list) {
        final m = (j as Map).cast<String, dynamic>();
        _ranks.add((m['bs_rank'] ?? (_items.length + 1)) as int);
        _items.add(UellowProductCard.fromJson(m));
      }
      _hasMore = data['has_more'] == true && list.isNotEmpty;
      _page++;
    } catch (_) {
      _hasMore = false;
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: UellowColors.bg,
        appBar: AppBar(
          backgroundColor: const Color(0xFF1F1A10),
          foregroundColor: Colors.white,
          // v2.2.25 — yellow back arrow.
          iconTheme: const IconThemeData(color: UellowColors.yellow),
          title: Text(ar ? '👑 الأفضل مبيعاً' : '👑 Bestsellers',
              style: const TextStyle(
                  color: UellowColors.yellow,
                  fontWeight: FontWeight.w900, fontSize: 16)),
        ),
        body: _items.isEmpty && _loading
            ? const Center(child: CircularProgressIndicator(
                color: UellowColors.yellow))
            : CustomScrollView(controller: _scroll, slivers: [
                // gold strip under the appbar
                SliverToBoxAdapter(child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF1F1A10), Color(0xFF3A2E14)]),
                  ),
                  child: Row(children: [
                    const Text('🔥', style: TextStyle(fontSize: 18)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(
                        ar ? 'الترتيب محدّث يومياً حسب المبيعات الفعلية'
                           : 'Ranking updated daily from real sales',
                        style: const TextStyle(color: Color(0xFFFFD75E),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700))),
                  ]),
                )),
                // category filter chips (header)
                if (_cats.isNotEmpty) SliverToBoxAdapter(child: Container(
                  color: const Color(0xFF1F1A10),
                  // v2.2.25 — small breathing space above the category chips.
                  padding: const EdgeInsets.only(top: 8, bottom: 10),
                  child: SizedBox(height: 34, child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _cats.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (_, i) {
                      final id = i == 0 ? 0 : _cats[i - 1].id;
                      final label = i == 0
                          ? (ar ? 'الكل' : 'All')
                          : _cats[i - 1].name.current(ar ? 'ar' : 'en');
                      final on = id == _catId;
                      return GestureDetector(
                        onTap: () => _selectCat(id),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
                          decoration: BoxDecoration(
                            color: on ? UellowColors.yellow : Colors.white.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: on ? UellowColors.yellow
                                : Colors.white.withValues(alpha: 0.20)),
                          ),
                          alignment: Alignment.center,
                          child: Text(label, style: TextStyle(
                              color: on ? const Color(0xFF1F1A10) : Colors.white,
                              fontSize: 12, fontWeight: FontWeight.w800)),
                        ),
                      );
                    },
                  )),
                )),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 24),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) {
                        if (i >= _items.length) {
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: SizedBox(
                                width: 22, height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    color: UellowColors.yellow))),
                          );
                        }
                        return _row(context, _items[i], _ranks[i], ar);
                      },
                      childCount: _items.length + (_hasMore ? 1 : 0),
                    ),
                  ),
                ),
              ]),
      ),
    );
  }

  Widget _medal(int rank) {
    if (rank <= 3) {
      return Text(rank == 1 ? '🥇' : rank == 2 ? '🥈' : '🥉',
          style: const TextStyle(fontSize: 24));
    }
    return Container(
      width: 30, height: 30, alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFF3EDE0),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFE2D6BC)),
      ),
      child: Text('#$rank', style: const TextStyle(fontSize: 10.5,
          fontWeight: FontWeight.w900, color: Color(0xFF8A7140))),
    );
  }

  Widget _row(BuildContext context, UellowProductCard pr, int rank, bool ar) {
    final lang = UellowApi.instance.lang;
    final top3 = rank <= 3;
    return GestureDetector(
      onTap: () => UellowRouter.goProduct(context, pr.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: top3
              ? const Color(0xFFE9C463) : const Color(0xFFEFEAE0)),
          boxShadow: top3
              ? [BoxShadow(color: const Color(0xFFD4AF37)
                  .withValues(alpha: .18), blurRadius: 10)]
              : const [BoxShadow(color: Color(0x0A000000), blurRadius: 6)],
        ),
        child: Row(children: [
          _medal(rank),
          const SizedBox(width: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: CachedNetworkImage(
              imageUrl: pr.image, width: 64, height: 64,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => Container(
                  width: 64, height: 64, color: const Color(0xFFF5F2EA),
                  child: const Icon(Icons.image_outlined,
                      color: Color(0xFFCBBFa5))),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(pr.name.current(lang),
                maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: UellowColors.darkBrown, height: 1.25)),
            const SizedBox(height: 5),
            Row(children: [
              Text(pr.price.format(), style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w900,
                  color: UellowColors.darkBrown)),
              if (pr.comparePrice != null &&
                  pr.comparePrice!.amount > pr.price.amount) ...[
                const SizedBox(width: 6),
                Text(pr.comparePrice!.format(), style: const TextStyle(
                    fontSize: 10.5, color: UellowColors.muted,
                    decoration: TextDecoration.lineThrough)),
              ],
            ]),
            const SizedBox(height: 4),
            Row(children: [
              if (pr.soldCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3D6),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(ar ? '🔥 بيع ${pr.soldCount}'
                                 : '🔥 ${pr.soldCount} sold',
                      style: const TextStyle(fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF8A6500))),
                ),
              if (pr.rating.count > 0) ...[
                const SizedBox(width: 6),
                const Icon(Icons.star_rounded, size: 14,
                    color: Color(0xFFF5A623)),
                Text(' ${pr.rating.avg.toStringAsFixed(1)}',
                    style: const TextStyle(fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: UellowColors.muted)),
              ],
            ]),
          ])),
          Icon(ar ? Icons.chevron_left : Icons.chevron_right,
              color: const Color(0xFFCBBFa5)),
        ]),
      ),
    );
  }
}
