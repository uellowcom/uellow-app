// =============================================================================
// OrdersListScreen — lists current user's orders. Optionally filtered by
// state (draft / sale / confirmed / shipping / delivered). Tap a row →
// /order detail.
// =============================================================================
import 'package:flutter/material.dart';

import '../../api/uellow_api.dart';
import '../../api/uellow_models.dart';
import '../theme/uellow_theme.dart';

class OrdersListScreen extends StatefulWidget {
  const OrdersListScreen({super.key, this.filterState});
  final String? filterState;
  @override
  State<OrdersListScreen> createState() => _OrdersListScreenState();
}

class _OrdersListScreenState extends State<OrdersListScreen> {
  late Future<UellowPage<UellowOrderSummary>> _future;
  late String? _filter;

  @override
  void initState() {
    super.initState();
    _filter = widget.filterState;
    _future = UellowApi.instance.orders.list(state: _filter);
  }

  void _setFilter(String? s) {
    setState(() {
      _filter = s;
      _future = UellowApi.instance.orders.list(state: s);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return Scaffold(
      backgroundColor: UellowColors.bg,
      appBar: AppBar(
        title: Text(ar ? 'طلباتي' : 'My Orders', style: UT.h1),
        backgroundColor: Colors.white,
      ),
      body: SafeArea(child: Column(children: [
        _FilterStrip(active: _filter, onSelect: _setFilter, ar: ar),
        Expanded(child: FutureBuilder<UellowPage<UellowOrderSummary>>(
          future: _future,
          builder: (_, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator(
                  color: UellowColors.darkBrown));
            }
            if (snap.hasError) {
              return Center(child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(snap.error.toString(),
                    textAlign: TextAlign.center, style: UT.body),
              ));
            }
            final orders = snap.data?.items ?? const <UellowOrderSummary>[];
            if (orders.isEmpty) {
              return Center(child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.inbox_outlined, size: 64,
                      color: UellowColors.muted),
                  const SizedBox(height: 12),
                  Text(ar ? 'لا توجد طلبات بعد' : 'No orders yet',
                      style: UT.body),
                ]),
              ));
            }
            return ListView.separated(
              padding: const EdgeInsets.all(14),
              itemCount: orders.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _OrderTile(order: orders[i], ar: ar),
            );
          },
        )),
      ])),
    );
  }
}

class _FilterStrip extends StatelessWidget {
  const _FilterStrip({required this.active, required this.onSelect, required this.ar});
  final String? active;
  final ValueChanged<String?> onSelect;
  final bool ar;
  static const _en = ['All','Draft','Confirmed','Preparing','Shipping','Delivered'];
  static const _ar = ['الكل','مسودة','مؤكد','قيد التجهيز','قيد الشحن','تم التوصيل'];
  static const _vals = [null, 'draft','confirmed','preparing','shipping','delivered'];
  @override
  Widget build(BuildContext context) {
    final labels = ar ? _ar : _en;
    return Container(
      color: Colors.white,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: UellowColors.border)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: SizedBox(height: 30, child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _vals.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final on = active == _vals[i];
          return GestureDetector(
            onTap: () => onSelect(_vals[i]),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: on ? UellowColors.darkBrown : UellowColors.border,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(labels[i], style: TextStyle(
                color: on ? UellowColors.yellowLight : UellowColors.text,
                fontWeight: FontWeight.w800, fontSize: 12,
              )),
            ),
          );
        },
      )),
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.order, required this.ar});
  final UellowOrderSummary order;
  final bool ar;
  // Color and label come straight from the backend uellow_status enum
  // (api_v2/orders.py:_UELLOW_STATUS_DICT) — keeps app + portal aligned.
  Color _statusColor(String s) => switch (s) {
    'draft'     => UellowColors.muted,
    'confirmed' => const Color(0xFF0EA5E9),
    'preparing' => const Color(0xFF8B5CF6),
    'shipping'  => const Color(0xFFF59E0B),
    'delivered' => UellowColors.successDk,
    'cancelled' => UellowColors.muted,
    'returned'  => UellowColors.danger,
    _ => UellowColors.muted,
  };
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.pushNamed(context, '/order',
          arguments: {'id': order.id}),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: UellowColors.border),
        ),
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: const BoxDecoration(
              color: UellowColors.yellowSoft,
              borderRadius: BorderRadius.all(Radius.circular(10)),
            ),
            child: const Icon(Icons.shopping_bag_outlined,
                color: UellowColors.darkBrown),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(order.name, style: const TextStyle(
                fontWeight: FontWeight.w900, color: UellowColors.ink)),
            const SizedBox(height: 4),
            Text(order.date?.split('T').first ?? '',
                style: const TextStyle(fontSize: 11, color: UellowColors.muted)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(order.total.format(), style: const TextStyle(
                fontWeight: FontWeight.w900, color: UellowColors.ink)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _statusColor(order.uellowStatus).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(order.uellowStatusLabel.current(ar ? 'ar' : 'en'),
                  style: TextStyle(color: _statusColor(order.uellowStatus),
                      fontSize: 10, fontWeight: FontWeight.w900)),
            ),
          ]),
        ]),
      ),
    );
  }
}
