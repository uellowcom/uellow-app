// =============================================================================
// BrandsScreen (v2.1.59 full rewrite) — REAL brands directory:
// alphabetical grid of square brand tiles (logo + untranslated name +
// product count), search box, and root-category chips that re-filter
// the list from the backend. The old screen was demo data.
// =============================================================================
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../api/uellow_api.dart';
import '../../api/uellow_models.dart';
import '../theme/uellow_theme.dart';

class BrandsScreen extends StatefulWidget {
  const BrandsScreen({super.key, this.categoryId = 0});
  // v2.2.40 — when opened from a category's "More" brands tile, preselect
  // that category so it shows only the brands of the section the user is in.
  final int categoryId;
  @override
  State<BrandsScreen> createState() => _BrandsScreenState();
}

class _BrandsScreenState extends State<BrandsScreen> {
  List<Map<String, dynamic>>? _brands;
  List<UellowCategory> _roots = const [];
  late int _catId = widget.categoryId;   // 0 = all
  final _q = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    UellowApi.instance.categories.tree().then((v) {
      if (mounted) setState(() => _roots = v);
    }).catchError((_) {});
  }

  Future<void> _load() async {
    setState(() => _brands = null);
    try {
      final res = await UellowApi.instance.getRaw(
          '/api/mobile/v2/brands',
          query: {if (_catId > 0) 'category_id': _catId});
      final v = List<Map<String, dynamic>>.from(
          (res['data']?['brands'] as List?) ?? const []);
      // alphabetical per spec
      v.sort((a, b) => (a['name'] ?? '').toString().toLowerCase()
          .compareTo((b['name'] ?? '').toString().toLowerCase()));
      if (mounted) setState(() => _brands = v);
    } catch (_) {
      if (mounted) setState(() => _brands = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    final all = _brands;
    final q = _q.text.trim().toLowerCase();
    final brands = all == null
        ? null
        : (q.isEmpty
            ? all
            : all.where((b) => (b['name'] ?? '').toString()
                .toLowerCase().contains(q)).toList());
    return Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: UellowColors.bg,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: UellowColors.darkBrown,
          title: Text(ar ? '🏷️ الماركات' : '🏷️ Brands',
              style: const TextStyle(fontWeight: FontWeight.w900,
                  fontSize: 16)),
        ),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: TextField(
              controller: _q,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: ar ? 'ابحث عن ماركة…' : 'Search a brand…',
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true, filled: true, fillColor: Colors.white,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
            ),
          ),
          SizedBox(height: 40, child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 5),
            children: [
              _chip(ar ? 'الكل' : 'All', 0),
              for (final c in _roots.take(12))
                _chip(c.name.current(UellowApi.instance.lang), c.id),
            ],
          )),
          Expanded(child: brands == null
              ? const Center(child: CircularProgressIndicator(
                  color: UellowColors.darkBrown))
              : brands.isEmpty
                  ? Center(child: Text(
                      ar ? 'لا توجد ماركات هنا' : 'No brands here',
                      style: UT.body))
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3, mainAxisSpacing: 10,
                        crossAxisSpacing: 10, childAspectRatio: 0.86,
                      ),
                      itemCount: brands.length,
                      itemBuilder: (_, i) => _tile(brands[i], ar),
                    )),
        ]),
      ),
    );
  }

  Widget _chip(String label, int id) {
    final on = _catId == id;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: ChoiceChip(
        label: Text(label, style: TextStyle(fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: on ? UellowColors.yellowLight : UellowColors.ink)),
        selected: on,
        selectedColor: UellowColors.darkBrown,
        backgroundColor: Colors.white,
        showCheckmark: false,
        onSelected: (_) {
          setState(() => _catId = id);
          _load();
        },
      ),
    );
  }

  Widget _tile(Map<String, dynamic> b, bool ar) {
    final name = (b['name'] ?? '').toString();
    final img = (b['image'] as String?) ?? '';
    final count = (b['product_count'] as num?)?.toInt() ?? 0;
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, '/collection', arguments: {
        'brand_value_id': (b['value_id'] as num?)?.toInt(),
        'brand_name': name,
      }),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: UellowColors.border),
        ),
        padding: const EdgeInsets.all(8),
        child: Column(children: [
          Expanded(child: img.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: img.startsWith('http')
                      ? img : '${UellowApi.instance.baseUrl}$img',
                  fit: BoxFit.contain,
                  errorWidget: (_, __, ___) => _letter(name))
              : _letter(name)),
          const SizedBox(height: 4),
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10.5,
                  fontWeight: FontWeight.w800, color: UellowColors.ink)),
          Text(ar ? '$count منتج' : '$count items',
              style: const TextStyle(fontSize: 8.5,
                  color: UellowColors.muted,
                  fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }

  Widget _letter(String name) => Center(child: Container(
        width: 44, height: 44, alignment: Alignment.center,
        decoration: BoxDecoration(
          color: UellowColors.yellowSoft,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(name.isEmpty ? '🏷️' : name[0].toUpperCase(),
            style: const TextStyle(fontSize: 19,
                fontWeight: FontWeight.w900,
                color: UellowColors.darkBrown)),
      ));
}
