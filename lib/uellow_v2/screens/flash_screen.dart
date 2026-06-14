// =============================================================================
// FlashScreen — live flash sale page. Real banner + live countdown to end_date
// + real categories + real vendors (derived from product set) + 2-col grid.
// =============================================================================
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../api/uellow_api.dart';
import '../../api/uellow_models.dart';
import '../router/uellow_router.dart';
import '../theme/uellow_theme.dart';
import '../widgets/product_card.dart';

class FlashScreen extends StatefulWidget {
  const FlashScreen({super.key});
  @override
  State<FlashScreen> createState() => _FlashScreenState();
}

class _FlashScreenState extends State<FlashScreen> {
  late Future<List<_FlashSaleData>> _future;
  int _periodIdx = 0;            // 0=now, 1=upcoming, 2=ended
  int? _selectedCategoryId;       // null=all
  int? _selectedVendorId;         // null=all
  String _sort = 'discount';      // 'discount' | 'price' | 'sold'

  @override
  void initState() {
    super.initState();
    _future = _loadSales();
  }

  Future<List<_FlashSaleData>> _loadSales() async {
    final r = await http.get(
      Uri.parse('${UellowApi.instance.baseUrl}/api/mobile/v2/flash-sales'),
      headers: {'Accept': 'application/json'},
    );
    final body = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    if (body['success'] != true) return [];
    final list = (body['data'] as List).cast<Map<String, dynamic>>();
    return list.map(_FlashSaleData.fromJson).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UellowColors.bg,
      body: SafeArea(child: FutureBuilder<List<_FlashSaleData>>(
        future: _future,
        builder: (_, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: UellowColors.darkBrown));
          }
          final sales = snap.data ?? [];
          if (sales.isEmpty) return _EmptyFlash();
          final sale = sales.first;     // primary live sale
          final filtered = _applyFilters(sale);
          return CustomScrollView(slivers: [
            SliverToBoxAdapter(child: _Hero(sale: sale)),
            SliverToBoxAdapter(child: _PeriodButtons(
                idx: _periodIdx, onSelect: (i) => setState(() => _periodIdx = i))),
            SliverToBoxAdapter(child: _CategoryFilter(
              categories: sale.categories,
              selectedId: _selectedCategoryId,
              onSelect: (id) => setState(() => _selectedCategoryId = id),
            )),
            SliverToBoxAdapter(child: _VendorFilter(
              products: sale.products,
              selectedId: _selectedVendorId,
              onSelect: (id) => setState(() => _selectedVendorId = id),
            )),
            SliverToBoxAdapter(child: _SortBar(
              count: filtered.length, sort: _sort,
              onSort: (s) => setState(() => _sort = s),
            )),
            SliverPadding(padding: const EdgeInsets.all(12), sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, crossAxisSpacing: 8, mainAxisSpacing: 8,
                childAspectRatio: 0.58,
              ),
              delegate: SliverChildBuilderDelegate(
                (_, i) => ProductCard(product: filtered[i], inFlashSale: true),
                childCount: filtered.length,
              ),
            )),
            const SliverToBoxAdapter(child: SizedBox(height: 30)),
          ]);
        },
      )),
    );
  }

  List<UellowProductCard> _applyFilters(_FlashSaleData sale) {
    var list = sale.products.toList();
    // Period filter only narrows by stock state since the sales list is
    // already filtered to is_live=true on the server.
    if (_periodIdx == 2) list = list.where((p) => p.qtyAvailable != null && p.qtyAvailable! <= 0).toList();
    if (_selectedVendorId != null) list = list.where((p) => p.vendor?.id == _selectedVendorId).toList();
    if (_selectedCategoryId != null) {
      list = list.where((p) =>
          sale.productCategoryMap[p.id] == _selectedCategoryId).toList();
    }
    switch (_sort) {
      case 'price':
        list.sort((a, b) => a.price.amount.compareTo(b.price.amount));
        break;
      case 'sold':
        list.sort((a, b) => b.rating.count.compareTo(a.rating.count));
        break;
      case 'discount':
      default:
        list.sort((a, b) => b.discountPct.compareTo(a.discountPct));
    }
    return list;
  }
}

// ─── Data ─────────────────────────────────────────────────────────

class _FlashSaleData {
  final int id;
  final String titleEn, titleAr, subtitleEn, subtitleAr;
  final DateTime? endDate;
  final bool showCountdown;
  final int soldCount, productCount;
  final List<UellowProductCard> products;
  final List<Map<String, dynamic>> categories;
  final Map<int, int> productCategoryMap;   // product_id → category_id
  const _FlashSaleData({
    required this.id, required this.titleEn, required this.titleAr,
    required this.subtitleEn, required this.subtitleAr,
    required this.endDate, required this.showCountdown,
    required this.soldCount, required this.productCount, required this.products,
    required this.categories, required this.productCategoryMap,
  });
  factory _FlashSaleData.fromJson(Map<String, dynamic> j) {
    final pcRaw = (j['product_categories'] as Map?) ?? const {};
    final pcm = <int, int>{};
    pcRaw.forEach((k, v) {
      final pid = int.tryParse('$k');
      final cid = int.tryParse('$v');
      if (pid != null && cid != null) pcm[pid] = cid;
    });
    return _FlashSaleData(
      id: (j['id'] ?? 0) as int,
      titleEn: ((j['title'] as Map?)?['en'] ?? '').toString(),
      titleAr: ((j['title'] as Map?)?['ar'] ?? '').toString(),
      subtitleEn: ((j['subtitle'] as Map?)?['en'] ?? '').toString(),
      subtitleAr: ((j['subtitle'] as Map?)?['ar'] ?? '').toString(),
      endDate: j['end_date'] != null
          ? DateTime.tryParse(j['end_date'] as String)?.toLocal()
          : null,
      showCountdown: (j['show_countdown'] ?? true) as bool,
      soldCount: (j['sold_count'] ?? 0) as int,
      productCount: (j['product_count'] ?? 0) as int,
      products: ((j['products'] as List?) ?? const [])
          .map((e) => UellowProductCard.fromJson(e as Map<String, dynamic>))
          .toList(),
      categories: ((j['categories'] as List?) ?? const [])
          .cast<Map<String, dynamic>>(),
      productCategoryMap: pcm,
    );
  }
}

// ─── Hero with live boxed countdown ───────────────────────────────

class _Hero extends StatelessWidget {
  const _Hero({required this.sale});
  final _FlashSaleData sale;
  @override
  Widget build(BuildContext context) {
    final lang = UellowApi.instance.lang;
    final title = (lang == 'ar' ? sale.titleAr : sale.titleEn).isNotEmpty
        ? (lang == 'ar' ? sale.titleAr : sale.titleEn)
        : 'Mega Flash Sale';
    final sub = (lang == 'ar' ? sale.subtitleAr : sale.subtitleEn).isNotEmpty
        ? (lang == 'ar' ? sale.subtitleAr : sale.subtitleEn)
        : 'Limited time deals';
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
      decoration: const BoxDecoration(gradient: UellowColors.heroFlash),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          IconButton(
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            padding: EdgeInsets.zero, constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 8),
          const Text('⚡', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 4),
          Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white,
                  fontSize: 22, fontWeight: FontWeight.w900))),
        ]),
        Padding(padding: const EdgeInsets.only(left: 48),
            child: Text(sub, style: const TextStyle(
                color: Color(0xD9FFFFFF), fontSize: 13))),
        const SizedBox(height: 14),
        if (sale.showCountdown && sale.endDate != null)
          _LiveCountdown(endsAt: sale.endDate!),
        const SizedBox(height: 10),
        Padding(padding: const EdgeInsets.only(left: 4),
            child: Text('${sale.productCount} products  ·  ${sale.soldCount} sold',
                style: const TextStyle(color: Colors.white, fontSize: 12))),
      ]),
    );
  }
}

class _LiveCountdown extends StatefulWidget {
  const _LiveCountdown({required this.endsAt});
  final DateTime endsAt;
  @override
  State<_LiveCountdown> createState() => _LiveCountdownState();
}

class _LiveCountdownState extends State<_LiveCountdown> {
  Timer? _t;
  Duration _left = Duration.zero;
  @override
  void initState() {
    super.initState();
    _tick();
    _t = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }
  void _tick() {
    final d = widget.endsAt.difference(DateTime.now());
    setState(() => _left = d.isNegative ? Duration.zero : d);
  }
  @override
  void dispose() { _t?.cancel(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final days = _left.inDays;
    final h = _left.inHours.remainder(24);
    final m = _left.inMinutes.remainder(60);
    final s = _left.inSeconds.remainder(60);
    return Row(children: [
      if (days > 0) ...[
        Expanded(child: _Box(num: days.toString().padLeft(2, '0'), lbl: 'DAYS')),
        const SizedBox(width: 8),
      ],
      Expanded(child: _Box(num: h.toString().padLeft(2, '0'), lbl: 'HOURS')),
      const SizedBox(width: 8),
      Expanded(child: _Box(num: m.toString().padLeft(2, '0'), lbl: 'MINUTES')),
      const SizedBox(width: 8),
      Expanded(child: _Box(num: s.toString().padLeft(2, '0'), lbl: 'SECONDS')),
    ]);
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.num, required this.lbl});
  final String num, lbl;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: Column(children: [
        Text(num, style: const TextStyle(
            color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900,
            letterSpacing: -1)),
        const SizedBox(height: 2),
        Text(lbl, style: const TextStyle(
            color: Color(0xCCFFFFFF), fontSize: 9.5,
            letterSpacing: 0.8, fontWeight: FontWeight.w800)),
      ]),
    );
  }
}

// ─── Period buttons ────────────────────────────────────────────────

class _PeriodButtons extends StatelessWidget {
  const _PeriodButtons({required this.idx, required this.onSelect});
  final int idx;
  final ValueChanged<int> onSelect;
  @override
  Widget build(BuildContext context) {
    // v2.0.91 — localized period labels (was English-only)
    final ar = UellowApi.instance.lang.toLowerCase().startsWith('ar');
    final labels = ar
        ? const ['🔥 الآن', '⏰ قريباً', '🏁 منتهية']
        : const ['🔥 LIVE', '⏰ UPCOMING', '🏁 ENDED'];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Row(children: List.generate(labels.length, (i) => Expanded(
        child: GestureDetector(
          onTap: () => onSelect(i),
          child: Container(
            margin: EdgeInsets.only(right: i < labels.length - 1 ? 6 : 0),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: i == idx ? UellowColors.darkBrown : UellowColors.border,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(labels[i], style: TextStyle(
              color: i == idx ? UellowColors.yellowLight : UellowColors.text,
              fontWeight: FontWeight.w800, fontSize: 11.5,
            )),
          ),
        ),
      ))),
    );
  }
}

// ─── Category + vendor filters (derived from product set) ──────────

class _CategoryFilter extends StatelessWidget {
  const _CategoryFilter({required this.categories, required this.selectedId,
      required this.onSelect});
  final List<Map<String, dynamic>> categories;
  final int? selectedId;
  final ValueChanged<int?> onSelect;
  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) return const SizedBox.shrink();
    final lang = UellowApi.instance.lang;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 14),
      child: SizedBox(height: 96, child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: categories.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          if (i == 0) {
            final on = selectedId == null;
            return _chip(
              null, label: lang == 'ar' ? 'الكل' : 'All',
              icon: const Icon(Icons.flash_on, size: 26,
                  color: UellowColors.danger),
              selected: on, onTap: () => onSelect(null),
            );
          }
          final c = categories[i - 1];
          final id = c['id'] as int;
          final name = ((c['name'] as Map?)?[lang] as String?)
              ?? ((c['name'] as Map?)?['en'] as String?) ?? '';
          final image = c['image'] as String?;
          final on = selectedId == id;
          return _chip(
            image, label: name, selected: on, onTap: () => onSelect(id),
          );
        },
      )),
    );
  }

  Widget _chip(String? image, {
    required String label, required bool selected,
    required VoidCallback onTap, Widget? icon,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(width: 72, child: Column(children: [
        Container(
          width: 60, height: 60,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(
                color: selected ? UellowColors.yellow : UellowColors.border,
                width: selected ? 3 : 1.5),
            boxShadow: selected ? const [BoxShadow(
                color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 3))]
              : null,
          ),
          child: ClipOval(child: image != null && image.isNotEmpty
            ? Image.network(image, fit: BoxFit.cover,
                errorBuilder: (_,__,___) => Container(
                    color: UellowColors.yellowSoft,
                    alignment: Alignment.center,
                    child: const Text('🛒', style: TextStyle(fontSize: 22))))
            : Container(
                color: UellowColors.yellowSoft,
                alignment: Alignment.center,
                child: icon ?? const Text('🛒', style: TextStyle(fontSize: 22)))),
        ),
        const SizedBox(height: 4),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10.5,
                fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                color: selected ? UellowColors.darkBrown : UellowColors.text)),
      ])),
    );
  }
}

class _VendorFilter extends StatelessWidget {
  const _VendorFilter({required this.products, required this.selectedId,
      required this.onSelect});
  final List<UellowProductCard> products;
  final int? selectedId;
  final ValueChanged<int?> onSelect;
  @override
  Widget build(BuildContext context) {
    final lang = UellowApi.instance.lang;
    // Derive unique vendors from the product set
    final byId = <int, UellowVendorRef>{};
    for (final p in products) {
      if (p.vendor != null && !p.vendor!.house) byId[p.vendor!.id] = p.vendor!;
    }
    final vendors = byId.values.toList();
    if (vendors.isEmpty) return const SizedBox.shrink();
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: UellowColors.border)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(lang == 'ar' ? 'تصفية حسب المتجر' : 'FILTER BY VENDOR',
            style: const TextStyle(
            fontSize: 10.5, color: UellowColors.muted,
            fontWeight: FontWeight.w800, letterSpacing: 0.5)),
        const SizedBox(height: 8),
        SizedBox(height: 36, child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: vendors.length + 1,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (_, i) {
            if (i == 0) {
              final on = selectedId == null;
              return GestureDetector(
                onTap: () => onSelect(null),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: on ? UellowColors.darkBrown : UellowColors.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  alignment: Alignment.center,
                  child: Text(lang == 'ar' ? 'كل المتاجر' : 'All vendors',
                    style: TextStyle(
                    color: on ? UellowColors.yellowLight : UellowColors.text,
                    fontWeight: FontWeight.w800, fontSize: 12,
                  )),
                ),
              );
            }
            final v = vendors[i - 1];
            final on = v.id == selectedId;
            final name = v.name.current(lang);
            return GestureDetector(
              onTap: () => onSelect(v.id),
              child: Container(
                padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
                decoration: BoxDecoration(
                  color: on ? UellowColors.yellowSoft : Colors.white,
                  border: Border.all(
                      color: on ? UellowColors.yellow : UellowColors.border),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(children: [
                  Container(
                    width: 28, height: 28,
                    decoration: const BoxDecoration(
                        color: UellowColors.darkBrown, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900, fontSize: 11)),
                  ),
                  const SizedBox(width: 6),
                  Text(name, style: const TextStyle(
                      fontSize: 12, color: UellowColors.darkBrown,
                      fontWeight: FontWeight.w700)),
                ]),
              ),
            );
          },
        )),
      ]),
    );
  }
}

class _SortBar extends StatelessWidget {
  const _SortBar({required this.count, required this.sort, required this.onSort});
  final int count;
  final String sort;
  final ValueChanged<String> onSort;
  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: UellowColors.border)),
      ),
      child: Row(children: [
        Text.rich(TextSpan(style: const TextStyle(fontSize: 12, color: UellowColors.muted), children: [
          TextSpan(text: '$count', style: const TextStyle(
              fontWeight: FontWeight.w900, color: UellowColors.darkBrown)),
          TextSpan(text: ar ? ' عرض · متوفّر' : ' deals · in stock'),
        ])),
        const Spacer(),
        GestureDetector(
          onTap: () async {
            final picked = await showModalBottomSheet<String>(
              context: context,
              builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
                _sortTile(context, 'discount', ar ? '🔥 الأكبر خصماً أولاً' : '🔥 Biggest discount first'),
                _sortTile(context, 'price', ar ? '↑ الأقل سعراً أولاً' : '↑ Lowest price first'),
                _sortTile(context, 'sold', ar ? '⭐ الأكثر تقييماً أولاً' : '⭐ Most reviewed first'),
              ]),
            );
            if (picked != null) onSort(picked);
          },
          child: Row(children: [
            const Icon(Icons.swap_vert, size: 14, color: UellowColors.darkBrown),
            const SizedBox(width: 3),
            Text(ar ? 'ترتيب' : 'Sort', style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: UellowColors.darkBrown)),
          ]),
        ),
      ]),
    );
  }
  Widget _sortTile(BuildContext context, String key, String label) {
    return ListTile(
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      selected: sort == key,
      onTap: () => Navigator.pop(context, key),
    );
  }
}

class _EmptyFlash extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(child: Padding(
      padding: const EdgeInsets.all(30),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.flash_off, size: 64, color: UellowColors.muted),
        const SizedBox(height: 14),
        Text(UellowApi.instance.lang == 'ar'
            ? 'لا يوجد عرض فلاش مباشر الآن' : 'No flash sale is live right now',
            textAlign: TextAlign.center, style: UT.body),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: () => UellowRouter.pushNamed(context, '/category'),
          child: Text(UellowApi.instance.lang == 'ar' ? 'تصفّح كل المنتجات' : 'Browse all products'),
        ),
      ]),
    ));
  }
}
