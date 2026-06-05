// =============================================================================
// SearchScreen — typing autocomplete + recent (from Odoo) + trending (from
// Odoo) + browse categories (real). Live suggestions via /api/mobile/v2/search.
// =============================================================================
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../api/uellow_api.dart';
import '../../api/uellow_models.dart';
import '../router/uellow_router.dart';
import '../theme/uellow_theme.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  Future<UellowSearchResult>? _results;
  late Future<_IdleData> _idle;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
    _ctrl.addListener(_onChanged);
    _idle = _loadIdle();
  }

  Future<_IdleData> _loadIdle() async {
    final api = UellowApi.instance;
    final results = await Future.wait([
      api.search.recent().catchError((_) => <Map<String, dynamic>>[]),
      api.search.trending().catchError((_) => <Map<String, dynamic>>[]),
      api.categories.tree().catchError((_) => <UellowCategory>[]),
    ]);
    return _IdleData(
      recent: (results[0] as List).cast<Map<String, dynamic>>(),
      trending: (results[1] as List).cast<Map<String, dynamic>>(),
      categories: (results[2] as List).cast<UellowCategory>(),
    );
  }

  void _onChanged() {
    final q = _ctrl.text.trim();
    if (q.length >= 2) {
      // v2.1.56 — log:false: typing pauses are suggestions, NOT searches.
      // The term is recorded only when the user finishes (submit / taps
      // a result) — see _goSeeAll and the result onTap.
      setState(() => _results =
          UellowApi.instance.search.search(q, perPage: 6, log: false));
    } else {
      setState(() => _results = null);
    }
  }

  void _fillAndSearch(String q) {
    _ctrl.text = q;
    _ctrl.selection = TextSelection.collapsed(offset: q.length);
    _focus.requestFocus();
  }

  void _goSeeAll(String q) {
    Navigator.pushReplacementNamed(context, '/collection',
        arguments: {'search': q.trim()});
  }

  Future<void> _clearRecent() async {
    try {
      await UellowApi.instance.search.clearRecent();
      setState(() => _idle = _loadIdle());
    } on UellowApiException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  void dispose() { _ctrl.dispose(); _focus.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: SafeArea(
        child: Column(children: [
          _topBar(),
          Expanded(child: _ctrl.text.length >= 2 ? _liveResults() : _idleState()),
        ]),
      ),
    );
  }

  Widget _topBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: UellowColors.border)),
      ),
      child: Row(children: [
        IconButton(
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_ios_new,
              color: UellowColors.darkBrown, size: 18),
          style: IconButton.styleFrom(
            backgroundColor: Colors.white,
            side: const BorderSide(color: UellowColors.border, width: 1),
            shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(10))),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: TextField(
          controller: _ctrl, focusNode: _focus, autofocus: true,
          textInputAction: TextInputAction.search,
          onSubmitted: (q) => q.trim().length >= 2 ? _goSeeAll(q) : null,
          decoration: InputDecoration(
            hintText: UellowApi.instance.lang == 'ar'
                ? 'ابحث عن منتج، ماركة، أو تاجر…'
                : 'Search products, brands, vendors…',
            prefixIcon: const Icon(Icons.search, size: 18, color: UellowColors.muted),
            suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: 'Scan barcode',
                onPressed: () => Navigator.pushNamed(context, '/scan'),
                icon: const Icon(Icons.qr_code_scanner_outlined,
                    size: 18, color: UellowColors.darkBrown),
              ),
              IconButton(
                tooltip: 'Search by image',
                onPressed: _imageSearch,
                icon: const Icon(Icons.camera_alt_outlined,
                    size: 18, color: UellowColors.darkBrown),
              ),
            ]),
            contentPadding: EdgeInsets.zero,
          ),
        )),
        const SizedBox(width: 4),
        TextButton(
          onPressed: () => Navigator.maybePop(context),
          child: Text(UellowApi.instance.lang == 'ar' ? 'إلغاء' : 'Cancel',
              style: const TextStyle(color: UellowColors.darkBrown,
                  fontWeight: FontWeight.w700, fontSize: 13)),
        ),
      ]),
    );
  }

  Future<void> _imageSearch() async {
    final picker = ImagePicker();
    final ar = UellowApi.instance.lang == 'ar';
    // Let the user pick gallery vs camera
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.photo_camera),
          title: Text(ar ? 'التقط صورة' : 'Take photo'),
          onTap: () => Navigator.pop(context, ImageSource.camera),
        ),
        ListTile(
          leading: const Icon(Icons.photo_library_outlined),
          title: Text(ar ? 'اختر من المعرض' : 'Pick from gallery'),
          onTap: () => Navigator.pop(context, ImageSource.gallery),
        ),
      ])),
    );
    if (src == null) return;
    // v2.0.71 — image-search reliability: tighter image size to keep uploads
    // small (was 1024/80 → now 768/70 = ~3× smaller body), explicit 20s
    // timeout, retry-on-timeout once, restore the input text on any failure
    // path (was leaving "Analysing…" stuck).
    final picked = await picker.pickImage(source: src,
        maxWidth: 768, imageQuality: 70);
    if (picked == null || !mounted) return;
    final bytes = await File(picked.path).readAsBytes();
    final b64 = base64Encode(bytes);
    final originalText = _ctrl.text;
    setState(() {
      _ctrl.text = ar ? 'جارٍ التحليل…' : 'Analysing…';
    });
    Future<http.Response> postOnce() => http.post(
        Uri.parse('${UellowApi.instance.baseUrl}/api/mobile/v2/search/image'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'image_base64': b64}),
      ).timeout(const Duration(seconds: 20));
    try {
      http.Response r;
      try { r = await postOnce(); }
      on TimeoutException { r = await postOnce(); } // single retry
      final body = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (body['success'] == true) {
        final q = (body['data']?['query'] as String?) ?? '';
        if (q.isNotEmpty && mounted) {
          _ctrl.text = q;
          _onChanged();
        } else if (mounted) {
          _ctrl.text = originalText;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(ar ? 'لم نتعرف على المنتج، جرب صورة أوضح'
                              : 'Could not identify product — try a clearer photo')));
        }
      } else if (mounted) {
        _ctrl.text = originalText;
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(body['error']?.toString() ?? 'Search failed')));
      }
    } catch (e) {
      if (mounted) {
        _ctrl.text = originalText;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(ar ? 'تعذّر البحث بالصورة، حاول مرة أخرى'
                            : 'Image search failed — try again')));
      }
    }
  }

  Widget _idleState() {
    return FutureBuilder<_IdleData>(
      future: _idle,
      builder: (_, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final d = snap.data ?? _IdleData.empty();
        final ar = UellowApi.instance.lang == 'ar';
        return ListView(children: [
          if (d.recent.isNotEmpty) _section(
            title: ar ? 'عمليات البحث الأخيرة' : 'RECENT SEARCHES',
            trailing: ar ? 'مسح الكل' : 'Clear all',
            onTrailing: _clearRecent,
            child: Wrap(spacing: 6, runSpacing: 6, children: d.recent.map((m) {
              final q = m['query'] as String? ?? '';
              return GestureDetector(
                onTap: () => _fillAndSearch(q),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
                  decoration: const BoxDecoration(
                    color: UellowColors.border,
                    borderRadius: BorderRadius.all(Radius.circular(999)),
                  ),
                  child: Text(q, style: const TextStyle(
                      fontSize: 12.5, color: UellowColors.text)),
                ),
              );
            }).toList()),
          ),
          if (d.trending.isNotEmpty) _section(
            title: ar ? 'الأكثر رواجاً اليوم  🔥' : 'TRENDING TODAY  🔥',
            child: GridView.builder(
              shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, crossAxisSpacing: 10,
                mainAxisSpacing: 10, childAspectRatio: 4.5,
              ),
              itemCount: d.trending.length.clamp(0, 8),
              itemBuilder: (_, i) {
                final t = d.trending[i];
                final q = (t['query'] as String?) ?? '';
                return GestureDetector(
                  onTap: () => _fillAndSearch(q),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: UellowColors.yellowFaint,
                      border: Border.all(color: UellowColors.warnBg),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(children: [
                      Container(
                        width: 22, height: 22, alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: i < 2 ? UellowColors.danger : UellowColors.yellowLight,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('${i + 1}', style: TextStyle(
                          color: i < 2 ? Colors.white : UellowColors.darkBrown,
                          fontWeight: FontWeight.w900, fontSize: 11,
                        )),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(q, maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: UellowColors.darkBrown),
                      )),
                    ]),
                  ),
                );
              },
            ),
          ),
          if (d.categories.isNotEmpty) _section(
            title: ar ? 'تصفّح الفئات' : 'BROWSE CATEGORIES', child: SizedBox(
              height: 100,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: d.categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final c = d.categories[i];
                  return GestureDetector(
                    onTap: () => UellowRouter.goCategory(context, c.id),
                    child: SizedBox(width: 88, child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: const BoxDecoration(
                        // v2.1.56 — gray background per spec (was yellow).
                        color: Color(0xFFEFEFEF),
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        (c.image != null && c.image!.isNotEmpty)
                          ? ClipRRect(borderRadius: BorderRadius.circular(8),
                              child: CachedNetworkImage(imageUrl: c.image!,
                                  width: 38, height: 38, fit: BoxFit.cover,
                                  errorWidget: (_,__,___) => const Text('🛒',
                                      style: TextStyle(fontSize: 22))))
                          : const Text('🛒', style: TextStyle(fontSize: 22)),
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(c.name.current(UellowApi.instance.lang),
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: UellowColors.darkBrown)),
                        ),
                      ]),
                    )),
                  );
                },
              ),
            ),
          ),
          if (d.recent.isEmpty && d.trending.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 80, 28, 30),
              child: Column(children: [
                const Icon(Icons.search, size: 64, color: UellowColors.muted),
                const SizedBox(height: 12),
                Text(ar ? 'ابدأ الكتابة للبحث في أكثر من ٣٠٠٠٠ منتج'
                        : 'Start typing to search 30,000+ products',
                    textAlign: TextAlign.center, style: UT.body),
              ]),
            ),
        ]);
      },
    );
  }

  Widget _section({
    required String title, String? trailing, VoidCallback? onTrailing,
    required Widget child,
  }) {
    return Container(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(title, style: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w800,
              color: UellowColors.muted, letterSpacing: 0.5))),
          if (trailing != null) GestureDetector(
            onTap: onTrailing,
            child: Text(trailing, style: const TextStyle(
                fontSize: 12, color: UellowColors.danger,
                fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 10),
        child,
      ]),
    );
  }

  Widget _liveResults() {
    return FutureBuilder<UellowSearchResult>(
      future: _results,
      builder: (_, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text(snap.error.toString(), style: UT.body));
        }
        final r = snap.data!;
        final lang = UellowApi.instance.lang;
        final ar = lang == 'ar';
        final nothing = r.products.isEmpty && r.brands.isEmpty &&
            r.categories.isEmpty && r.vendors.isEmpty;
        if (nothing) {
          return Padding(
            padding: const EdgeInsets.all(30),
            child: Column(children: [
              const Icon(Icons.search_off, size: 64, color: UellowColors.muted),
              const SizedBox(height: 12),
              Text(lang == 'ar'
                  ? 'لا توجد نتائج تطابق "${_ctrl.text}"'
                  : 'No results match "${_ctrl.text}"',
                  textAlign: TextAlign.center, style: UT.body),
            ]),
          );
        }
        // v2.1.56 — multi-section results: brands / categories / sellers
        // each in their own section above the product suggestions.
        return ListView(children: [
          if (r.brands.isNotEmpty) _resultSection(
            title: ar ? 'الماركات' : 'BRANDS',
            child: SizedBox(height: 86, child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: r.brands.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final b = r.brands[i];
                final img = (b['image'] as String?) ?? '';
                final name = (b['name'] ?? '').toString();
                final count = (b['product_count'] as num?)?.toInt() ?? 0;
                return GestureDetector(
                  onTap: () {
                    UellowApi.instance.search.record(_ctrl.text.trim());
                    Navigator.pushNamed(context, '/collection', arguments: {
                      'brand_value_id': (b['id'] as num?)?.toInt(),
                      'brand_name': name,
                    });
                  },
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 52, height: 52,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFEFEF), shape: BoxShape.circle,
                        border: Border.all(color: UellowColors.border),
                      ),
                      child: img.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: img.startsWith('http')
                                  ? img
                                  : '${UellowApi.instance.baseUrl}$img',
                              fit: BoxFit.contain,
                              errorWidget: (_, __, ___) => Center(child: Text(
                                  name.isEmpty ? '🏷️' : name[0].toUpperCase(),
                                  style: const TextStyle(fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                      color: UellowColors.darkBrown))))
                          : Center(child: Text(
                              name.isEmpty ? '🏷️' : name[0].toUpperCase(),
                              style: const TextStyle(fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: UellowColors.darkBrown))),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(width: 64, child: Text(
                        count > 0 ? '$name ($count)' : name,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: UellowColors.ink))),
                  ]),
                );
              },
            )),
          ),
          if (r.categories.isNotEmpty) _resultSection(
            title: ar ? 'الأقسام' : 'CATEGORIES',
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(spacing: 6, runSpacing: 6,
                  children: r.categories.take(8).map((c) => GestureDetector(
                onTap: () {
                  UellowApi.instance.search.record(_ctrl.text.trim());
                  Navigator.pushNamed(context, '/collection',
                      arguments: {'category_id': c.id});
                },
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFEFEF),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.category_outlined, size: 13,
                        color: UellowColors.darkBrown),
                    const SizedBox(width: 5),
                    Text(c.name.current(lang), style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700,
                        color: UellowColors.ink)),
                  ]),
                ),
              )).toList()),
            ),
          ),
          if (r.vendors.isNotEmpty) _resultSection(
            title: ar ? 'التجّار' : 'SELLERS',
            child: Column(children: r.vendors.take(4).map((v) {
              final name = ((v['name'] as Map?)?[ar ? 'ar' : 'en'] ??
                  (v['name'] as Map?)?['en'] ?? '').toString();
              final logo = (v['logo'] as String?) ?? '';
              final count = (v['product_count'] as num?)?.toInt() ?? 0;
              return InkWell(
                onTap: () {
                  UellowApi.instance.search.record(_ctrl.text.trim());
                  UellowRouter.goVendor(
                      context, (v['id'] as num?)?.toInt() ?? 0);
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                  child: Row(children: [
                    Container(
                      width: 40, height: 40,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFEFEF), shape: BoxShape.circle,
                      ),
                      child: logo.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: logo.startsWith('http')
                                  ? logo
                                  : '${UellowApi.instance.baseUrl}$logo',
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => const Icon(
                                  Icons.storefront_outlined, size: 18,
                                  color: UellowColors.darkBrown))
                          : const Icon(Icons.storefront_outlined, size: 18,
                              color: UellowColors.darkBrown),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: UellowColors.ink)),
                      Text(ar ? '$count منتج' : '$count products',
                          style: const TextStyle(fontSize: 10.5,
                              color: UellowColors.muted)),
                    ])),
                    const Icon(Icons.chevron_right, color: UellowColors.muted),
                  ]),
                ),
              );
            }).toList()),
          ),
          if (r.products.isNotEmpty) ...[
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Text(lang == 'ar' ? 'نتائج مقترحة' : 'SUGGESTED RESULTS',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                    color: UellowColors.muted, letterSpacing: 0.5)),
          ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(children: r.products.take(6).map((p) => GestureDetector(
              onTap: () {
                // v2.1.56 — tapping a result = a FINISHED search → record.
                UellowApi.instance.search.record(_ctrl.text.trim());
                UellowRouter.goProduct(context, p.id);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: UellowColors.border)),
                ),
                child: Row(children: [
                  ClipRRect(borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(imageUrl: p.image,
                        width: 50, height: 50, fit: BoxFit.cover),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p.name.current(lang), maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, color: UellowColors.ink)),
                    const SizedBox(height: 2),
                    Text(p.price.formatLocalized(lang), style: const TextStyle(
                        fontWeight: FontWeight.w800, color: UellowColors.darkBrown,
                        fontSize: 12)),
                  ])),
                  const Icon(Icons.chevron_right, color: UellowColors.muted),
                ]),
              ),
            )).toList()),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton(
              onPressed: () => _goSeeAll(_ctrl.text),
              child: Text(lang == 'ar'
                  ? 'عرض كل النتائج لـ "${_ctrl.text.trim()}"  ←'
                  : 'See all results for "${_ctrl.text.trim()}"  →'),
            ),
          ),
          ],
        ]);
      },
    );
  }

  // White section card with the same quiet caps title used elsewhere.
  Widget _resultSection({required String title, required Widget child}) {
    return Container(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Text(title, style: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w800,
              color: UellowColors.muted, letterSpacing: 0.5)),
        ),
        child,
      ]),
    );
  }
}

class _IdleData {
  _IdleData({required this.recent, required this.trending, required this.categories});
  _IdleData.empty(): recent = const [], trending = const [], categories = const [];
  final List<Map<String, dynamic>> recent;
  final List<Map<String, dynamic>> trending;
  final List<UellowCategory> categories;
}
