// =============================================================================
// Compare (v2.1.58) — قارن المنتجات. Entry: the ⚖ button on the PRODUCT
// PAGE only (deliberately NOT on product cards per spec). Up to 4
// products, persisted locally. Columns scroll horizontally; smart rows:
// price (cheapest highlighted), rating, availability, brand, attributes
// union — with a "differences only" toggle and per-column add-to-cart.
// =============================================================================
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../api/uellow_api.dart';
import '../../api/uellow_models.dart';
import '../router/uellow_router.dart';
import '../theme/uellow_theme.dart';

/// Local compare basket — max 4 product ids, persisted.
class CompareService {
  static const _key = 'compare_ids_v1';
  static const maxItems = 4;

  static Future<List<int>> ids() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_key) ?? const [])
        .map((e) => int.tryParse(e) ?? 0)
        .where((e) => e > 0)
        .toList();
  }

  /// Returns: 'added' | 'exists' | 'full'
  static Future<String> add(int id) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? <String>[];
    if (list.contains('$id')) return 'exists';
    if (list.length >= maxItems) return 'full';
    list.add('$id');
    await prefs.setStringList(_key, list);
    return 'added';
  }

  static Future<void> remove(int id) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? <String>[];
    list.remove('$id');
    await prefs.setStringList(_key, list);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

class CompareScreen extends StatefulWidget {
  const CompareScreen({super.key});
  @override
  State<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends State<CompareScreen> {
  List<UellowProductFull>? _items;
  bool _diffOnly = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final ids = await CompareService.ids();
    final out = <UellowProductFull>[];
    for (final id in ids) {
      try {
        out.add(await UellowApi.instance.products.detail(id));
      } catch (_) {/* skip dead products */}
    }
    if (mounted) setState(() => _items = out);
  }

  Future<void> _remove(int id) async {
    await CompareService.remove(id);
    _load();
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
          foregroundColor: UellowColors.darkBrown,
          title: Text(ar ? '⚖️ مقارنة المنتجات' : '⚖️ Compare products',
              style: const TextStyle(fontWeight: FontWeight.w900,
                  fontSize: 15)),
          actions: [
            if ((_items ?? const []).isNotEmpty) TextButton(
              onPressed: () async {
                await CompareService.clear();
                _load();
              },
              child: Text(ar ? 'مسح الكل' : 'Clear all',
                  style: const TextStyle(color: UellowColors.danger,
                      fontWeight: FontWeight.w800, fontSize: 12)),
            ),
          ],
        ),
        body: _body(ar),
      ),
    );
  }

  Widget _body(bool ar) {
    final items = _items;
    if (items == null) {
      return const Center(child: CircularProgressIndicator(
          color: UellowColors.darkBrown));
    }
    if (items.isEmpty) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('⚖️', style: TextStyle(fontSize: 52)),
          const SizedBox(height: 12),
          Text(ar ? 'قائمة المقارنة فارغة' : 'Nothing to compare yet',
              style: UT.h2),
          const SizedBox(height: 6),
          Text(ar
              ? 'من صفحة أي منتج اضغط زر ⚖ لإضافته هنا (حتى 4 منتجات)'
              : 'Tap ⚖ on any product page to add it here (up to 4)',
              textAlign: TextAlign.center, style: UT.body),
        ]),
      ));
    }
    final lang = UellowApi.instance.lang;
    final colW = 168.0;

    // attribute union: attrName(current lang) → product idx → joined values
    final attrNames = <String>[];
    final attrMap = <String, Map<int, String>>{};
    for (var i = 0; i < items.length; i++) {
      for (final a in items[i].attributes) {
        final n = a.attributeName.current(lang);
        if (n.trim().isEmpty) continue;
        attrMap.putIfAbsent(n, () {
          attrNames.add(n);
          return {};
        })[i] = a.values.map((v) => v.name.current(lang)).join('، ');
      }
    }
    final prices = items.map((p) => p.price.amount).toList();
    final minPrice = prices.reduce((a, b) => a < b ? a : b);

    bool differs(List<String> vals) =>
        vals.toSet().length > 1;

    Widget rowLabel(String t) => Container(
        width: 86, padding: const EdgeInsets.all(8),
        alignment: AlignmentDirectional.centerStart,
        child: Text(t, style: const TextStyle(fontSize: 10.5,
            fontWeight: FontWeight.w800, color: UellowColors.muted)));

    Widget cell(Widget child, {Color? bg}) => Container(
        width: colW, padding: const EdgeInsets.all(8),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg,
            border: const BorderDirectional(
                start: BorderSide(color: Color(0xFFF0F0F0)))),
        child: child);

    List<Widget> dataRow(String label, List<Widget> cells,
        {List<String>? rawVals}) {
      if (_diffOnly && rawVals != null && !differs(rawVals)) return const [];
      return [Container(
        color: Colors.white,
        margin: const EdgeInsets.only(top: 1),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center,
            children: [rowLabel(label), ...cells]),
      )];
    }

    return Column(children: [
      // differences toggle
      Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
        child: Row(children: [
          Text(ar ? 'أظهر الاختلافات فقط' : 'Differences only',
              style: const TextStyle(fontSize: 12,
                  fontWeight: FontWeight.w700)),
          const Spacer(),
          Switch(value: _diffOnly, activeColor: UellowColors.yellow,
              onChanged: (v) => setState(() => _diffOnly = v)),
        ]),
      ),
      Expanded(child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: 86 + colW * items.length,
          child: ListView(padding: const EdgeInsets.only(bottom: 30),
              children: [
            // header: images + name + remove
            Container(color: Colors.white, child: Row(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              rowLabel(''),
              for (final p in items) cell(Column(children: [
                Stack(children: [
                  GestureDetector(
                    onTap: () => UellowRouter.goProduct(context, p.id),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: CachedNetworkImage(
                          imageUrl: p.images.isNotEmpty ? p.images.first : '',
                          width: 110, height: 110, fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => const ColoredBox(
                              color: Color(0xFFEFEFEF),
                              child: SizedBox(width: 110, height: 110))),
                    ),
                  ),
                  PositionedDirectional(top: 2, end: 2, child:
                    GestureDetector(
                      onTap: () => _remove(p.id),
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                            color: Colors.white, shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: Color(0x22000000),
                                blurRadius: 3)]),
                        child: const Icon(Icons.close, size: 13,
                            color: UellowColors.danger),
                      ),
                    )),
                ]),
                const SizedBox(height: 6),
                Text(p.name.current(lang), maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ])),
            ])),
            // price
            ...dataRow(ar ? 'السعر' : 'Price', [
              for (var i = 0; i < items.length; i++) cell(
                Column(children: [
                  Text(items[i].price.format(), style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w900,
                      color: prices[i] <= minPrice + 0.0001
                          ? const Color(0xFF1F8A40)
                          : UellowColors.darkBrown)),
                  if (prices[i] <= minPrice + 0.0001 && items.length > 1)
                    Text(ar ? 'الأرخص ✓' : 'Cheapest ✓',
                        style: const TextStyle(fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1F8A40))),
                ]),
                bg: prices[i] <= minPrice + 0.0001 && items.length > 1
                    ? const Color(0xFFF0FAF4) : null,
              ),
            ], rawVals: prices.map((p) => p.toStringAsFixed(3)).toList()),
            // rating
            ...dataRow(ar ? 'التقييم' : 'Rating', [
              for (final p in items) cell(Text(
                  p.rating.count > 0
                      ? '★ ${p.rating.avg.toStringAsFixed(1)} (${p.rating.count})'
                      : (ar ? 'لا تقييمات' : 'No reviews'),
                  style: const TextStyle(fontSize: 11.5,
                      fontWeight: FontWeight.w700))),
            ], rawVals: items
                .map((p) => p.rating.avg.toStringAsFixed(1))
                .toList()),
            // brand
            ...dataRow(ar ? 'الماركة' : 'Brand', [
              for (final p in items) cell(Text(
                  p.brand?.name.current(lang) ?? '—',
                  style: const TextStyle(fontSize: 11.5))),
            ], rawVals: items
                .map((p) => p.brand?.name.current(lang) ?? '—')
                .toList()),
            // attributes union
            for (final n in attrNames) ...dataRow(n, [
              for (var i = 0; i < items.length; i++) cell(Text(
                  attrMap[n]?[i] ?? '—',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 10.5))),
            ], rawVals: [
              for (var i = 0; i < items.length; i++) attrMap[n]?[i] ?? '—',
            ]),
            // add to cart row
            Container(color: Colors.white,
                margin: const EdgeInsets.only(top: 1),
                child: Row(children: [
              rowLabel(''),
              for (final p in items) cell(ElevatedButton(
                onPressed: () async {
                  try {
                    await UellowApi.instance.cart.add(productId: p.id);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          duration: const Duration(seconds: 1),
                          content: Text(ar ? 'أُضيف للسلة ✓'
                                           : 'Added to cart ✓')));
                    }
                  } on UellowApiException catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(e.message)));
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: UellowColors.yellow,
                  foregroundColor: UellowColors.darkBrown,
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  textStyle: const TextStyle(fontSize: 11,
                      fontWeight: FontWeight.w900),
                ),
                child: Text(ar ? '🛒 أضف' : '🛒 Add'),
              )),
            ])),
          ]),
        ),
      )),
    ]);
  }
}
