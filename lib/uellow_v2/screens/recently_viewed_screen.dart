// =============================================================================
// RecentlyViewedScreen — full grid of the customer's recently-viewed
// products (v2.1.23). Same layout language as the wishlist screen; opened
// from the account page's "Recently viewed › See more".
// =============================================================================
import 'package:flutter/material.dart';

import '../../api/uellow_api.dart';
import '../../api/uellow_models.dart';
import '../theme/uellow_theme.dart';
import '../widgets/product_card.dart';

class RecentlyViewedScreen extends StatefulWidget {
  const RecentlyViewedScreen({super.key});
  @override
  State<RecentlyViewedScreen> createState() => _RecentlyViewedScreenState();
}

class _RecentlyViewedScreenState extends State<RecentlyViewedScreen> {
  Future<List<UellowProductCard>>? _future;

  @override
  void initState() {
    super.initState();
    _future = UellowApi.instance.products.recentlyViewed();
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang.toLowerCase().startsWith('ar');
    return Scaffold(
      backgroundColor: UellowColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: const BackButton(color: UellowColors.darkBrown),
        title: Text(ar ? 'شاهدتها مؤخراً' : 'Recently viewed',
            style: const TextStyle(color: UellowColors.ink,
                fontWeight: FontWeight.w900, fontSize: 16)),
      ),
      body: FutureBuilder<List<UellowProductCard>>(
        future: _future,
        builder: (_, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(
                color: UellowColors.darkBrown));
          }
          final items = snap.data ?? const <UellowProductCard>[];
          if (items.isEmpty) {
            return Center(child: Column(
                mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.visibility_off_outlined,
                  size: 56, color: UellowColors.muted),
              const SizedBox(height: 12),
              Text(ar ? 'لم تشاهد أي منتجات بعد'
                      : 'You have not viewed any products yet',
                  style: UT.body),
            ]));
          }
          return RefreshIndicator(
            color: UellowColors.darkBrown,
            onRefresh: () async {
              setState(() =>
                  _future = UellowApi.instance.products.recentlyViewed());
              await _future;
            },
            child: GridView.builder(
              padding: const EdgeInsets.all(14),
              physics: const AlwaysScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, crossAxisSpacing: 10,
                mainAxisSpacing: 10, childAspectRatio: 0.62,
              ),
              itemCount: items.length,
              itemBuilder: (_, i) => ProductCard(product: items[i]),
            ),
          );
        },
      ),
    );
  }
}
