// =============================================================================
// FreeShippingScreen — dedicated /free-shipping page for products tagged as
// free-shipping (via product flag, category, or tag — backend handles the
// resolution). Mirrors the website's /free-shipping route.
// =============================================================================
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../api/uellow_api.dart';
import '../../api/uellow_models.dart';
import '../theme/uellow_theme.dart';
import '../widgets/product_card.dart';

class FreeShippingScreen extends StatefulWidget {
  const FreeShippingScreen({super.key});
  @override
  State<FreeShippingScreen> createState() => _FreeShippingScreenState();
}

class _FreeShippingScreenState extends State<FreeShippingScreen> {
  final _scroll = ScrollController();
  final List<UellowProductCard> _items = [];
  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadMore();
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final uri = Uri.parse('${UellowApi.instance.baseUrl}/api/mobile/v2/products')
          .replace(queryParameters: {
        'page': '$_page',
        'per_page': '20',
        'free_shipping': '1',
        'sort': 'newest',
      });
      final r = await http.get(uri).timeout(const Duration(seconds: 15));
      final body = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (body['success'] == true) {
        final items = ((body['data'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(UellowProductCard.fromJson)
            .toList();
        if (mounted) {
          setState(() {
            _items.addAll(items);
            _hasMore = items.length >= 20;
            _page++;
          });
        }
      }
    } catch (_) {/* ignore — keep what we have */}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang.toLowerCase().startsWith('ar');
    return Scaffold(
      backgroundColor: UellowColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          onPressed: () => Navigator.maybePop(context),
          icon: Icon(ar ? Icons.arrow_forward : Icons.arrow_back,
              color: UellowColors.darkBrown),
        ),
        title: Row(children: [
          const Icon(Icons.local_shipping_outlined,
              color: UellowColors.darkBrown, size: 18),
          const SizedBox(width: 6),
          Text(ar ? 'شحن مجاني' : 'Free Shipping', style: UT.h1),
        ]),
      ),
      body: _items.isEmpty && _loading
          ? const Center(child: CircularProgressIndicator(
              color: UellowColors.darkBrown))
          : _items.isEmpty
              ? Center(child: Padding(padding: const EdgeInsets.all(30),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.local_shipping_outlined,
                        size: 56, color: UellowColors.muted),
                    const SizedBox(height: 12),
                    Text(ar ? 'لا توجد منتجات بشحن مجاني حالياً'
                            : 'No free-shipping products configured',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: UellowColors.muted)),
                  ])))
              : GridView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(10),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2, crossAxisSpacing: 8, mainAxisSpacing: 8,
                    childAspectRatio: 0.62,
                  ),
                  itemCount: _items.length + (_loading ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i >= _items.length) {
                      return const Center(child: CircularProgressIndicator(
                          color: UellowColors.darkBrown, strokeWidth: 2));
                    }
                    return ProductCard(product: _items[i]);
                  },
                ),
    );
  }
}
