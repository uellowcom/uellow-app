// =============================================================================
// NewCustomerScreen (v2.2.11) — 🌟 exclusive first-order zone.
// A premium gradient hero (configured in the backend 🌟 New Customers menu)
// + a paginated product grid. Eligibility:
//   guest    → "register to unlock" CTA
//   eligible → full offer + welcome coupon
//   existing → may browse (per setting) but no coupon
// Backed by /api/mobile/v2/newcustomer/offer + /newcustomer/products.
// =============================================================================
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/uellow_api.dart';
import '../../api/uellow_models.dart';
import '../router/uellow_router.dart';
import '../theme/uellow_theme.dart';
import '../widgets/product_card.dart';

class NewCustomerScreen extends StatefulWidget {
  const NewCustomerScreen({super.key});
  @override
  State<NewCustomerScreen> createState() => _NewCustomerScreenState();
}

class _NewCustomerScreenState extends State<NewCustomerScreen> {
  final _scroll = ScrollController();
  Map<String, dynamic>? _offer;
  final List<UellowProductCard> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 1;
  String? _error;

  bool get _ar => UellowApi.instance.lang.toLowerCase().startsWith('ar');

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels >
          _scroll.position.maxScrollExtent - 600) {
        _loadMore();
      }
    });
    _load();
  }

  @override
  void dispose() { _scroll.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final off = await UellowApi.instance.getRaw(
          '/api/mobile/v2/newcustomer/offer', auth: false);
      _offer = (off['data'] as Map?)?.cast<String, dynamic>();
      _items.clear();
      _page = 1;
      _hasMore = true;
      await _loadMore(reset: true);
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadMore({bool reset = false}) async {
    if (_loadingMore || (!_hasMore && !reset)) return;
    _loadingMore = true;
    try {
      final r = await UellowApi.instance.getRaw(
          '/api/mobile/v2/newcustomer/products',
          query: {'page': '$_page', 'per_page': '12'}, auth: false);
      final data = (r['data'] as Map?)?.cast<String, dynamic>() ?? {};
      final list = ((data['products'] as List?) ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>());
      for (final m in list) {
        try { _items.add(UellowProductCard.fromJson(m)); } catch (_) {}
      }
      _hasMore = data['has_more'] == true;
      _page += 1;
    } catch (_) {
      _hasMore = false;
    }
    _loadingMore = false;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ar = _ar;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F5FB),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_offer == null || _offer!['enabled'] != true)
              ? _empty(ar)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: CustomScrollView(
                    controller: _scroll,
                    slivers: [
                      SliverToBoxAdapter(child: _hero(ar)),
                      if (_eligibility == 'guest')
                        SliverToBoxAdapter(child: _unlockCta(ar)),
                      _grid(),
                      if (_loadingMore)
                        const SliverToBoxAdapter(child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Center(child: CircularProgressIndicator()))),
                      const SliverToBoxAdapter(child: SizedBox(height: 24)),
                    ],
                  ),
                ),
    );
  }

  String get _eligibility => (_offer?['eligibility'] ?? 'guest').toString();

  Color _c(String key, Color fb) {
    try {
      var s = (_offer?[key] ?? '').toString().replaceAll('#', '');
      if (s.length == 6) s = 'FF$s';
      return Color(int.parse(s, radix: 16));
    } catch (_) { return fb; }
  }

  Widget _hero(bool ar) {
    final c1 = _c('c1', const Color(0xFF7C3AED));
    final c2 = _c('c2', const Color(0xFF2563EB));
    final tc = _c('text_color', Colors.white);
    final title = ((_offer?['title'] as Map?)?[ar ? 'ar' : 'en'] ?? '').toString();
    final sub = ((_offer?['subtitle'] as Map?)?[ar ? 'ar' : 'en'] ?? '').toString();
    final emoji = (_offer?['emoji'] ?? '🎁').toString();
    final pct = (_offer?['discount_pct'] as num?)?.toInt() ?? 0;
    final code = (_offer?['coupon_code'] ?? '').toString();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 56, 20, 26),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [c1, c2]),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
        boxShadow: [BoxShadow(color: c1.withValues(alpha: .35),
            blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          IconButton(
            onPressed: () => Navigator.maybePop(context),
            icon: Icon(ar ? Icons.arrow_forward_ios : Icons.arrow_back_ios_new,
                color: tc, size: 18),
          ),
          const Spacer(),
          Text(emoji, style: const TextStyle(fontSize: 30)),
        ]),
        const SizedBox(height: 6),
        Text(title.isNotEmpty ? title
            : (ar ? 'حصري للعملاء الجدد' : 'Exclusive for New Customers'),
            style: TextStyle(color: tc, fontSize: 24,
                fontWeight: FontWeight.w900, height: 1.15)),
        if (sub.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(sub, style: TextStyle(color: tc.withValues(alpha: .9),
              fontSize: 13, height: 1.4)),
        ],
        const SizedBox(height: 16),
        Row(children: [
          if (pct > 0) Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: .22),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: tc.withValues(alpha: .5))),
            child: Text(ar ? 'خصم حتى $pct%' : 'Up to $pct% OFF',
                style: TextStyle(color: tc, fontWeight: FontWeight.w900,
                    fontSize: 13)),
          ),
          if (code.isNotEmpty) ...[
            const SizedBox(width: 8),
            Expanded(child: GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: code));
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(ar ? 'نُسخ الكود ✓' : 'Code copied ✓'),
                    duration: const Duration(seconds: 1)));
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(color: Colors.white,
                    borderRadius: BorderRadius.circular(999)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.local_offer, size: 14, color: Color(0xFF7C3AED)),
                  const SizedBox(width: 6),
                  Flexible(child: Text(code, maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: 'monospace',
                          fontWeight: FontWeight.w900, letterSpacing: 1.5,
                          color: Color(0xFF412402)))),
                  const SizedBox(width: 4),
                  const Icon(Icons.copy, size: 13, color: UellowColors.muted),
                ]),
              ),
            )),
          ],
        ]),
      ]),
    );
  }

  Widget _unlockCta(bool ar) => Container(
    margin: const EdgeInsets.fromLTRB(14, 14, 14, 0),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0x22000000)),
    ),
    child: Column(children: [
      Text(ar ? '🔓 سجّل لفتح العرض الحصري'
              : '🔓 Register to unlock your exclusive offer',
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
      const SizedBox(height: 10),
      SizedBox(width: double.infinity, child: ElevatedButton(
        onPressed: () => Navigator.pushNamed(context, Routes.auth),
        style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF7C3AED),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 13)),
        child: Text(ar ? 'إنشاء حساب' : 'Create account',
            style: const TextStyle(fontWeight: FontWeight.w900)),
      )),
    ]),
  );

  Widget _grid() {
    if (_items.isEmpty && !_loadingMore) {
      return SliverToBoxAdapter(child: Padding(
        padding: const EdgeInsets.all(40),
        child: Center(child: Text(_ar ? 'لا توجد منتجات بعد' : 'No products yet',
            style: const TextStyle(color: UellowColors.muted))),
      ));
    }
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, mainAxisSpacing: 8, crossAxisSpacing: 8,
          childAspectRatio: 0.585),
        delegate: SliverChildBuilderDelegate(
          (_, i) => ProductCard(product: _items[i]),
          childCount: _items.length,
        ),
      ),
    );
  }

  Widget _empty(bool ar) => Center(child: Padding(
    padding: const EdgeInsets.all(30),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('🌟', style: TextStyle(fontSize: 48)),
      const SizedBox(height: 12),
      Text(ar ? 'لا يوجد عرض للعملاء الجدد حالياً'
              : 'No new-customer offer right now',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      if (_error != null) ...[
        const SizedBox(height: 8),
        TextButton(onPressed: _load,
            child: Text(ar ? 'إعادة المحاولة' : 'Retry')),
      ],
    ]),
  ));
}
