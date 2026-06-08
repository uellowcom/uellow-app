// =============================================================================
// OrdersListScreen — current user's NON-cancelled orders. Status filter chips
// each carry a COUNT label; every order shows an animated coloured progress
// bar of its journey + a Track button → /order detail.
// =============================================================================
import 'package:flutter/material.dart';

import '../../api/uellow_api.dart';
import '../../api/uellow_models.dart';
import '../theme/uellow_theme.dart';

const _kStages = ['confirmed', 'preparing', 'shipping', 'delivered'];

class OrdersListScreen extends StatefulWidget {
  const OrdersListScreen({super.key, this.filterState});
  final String? filterState;
  @override
  State<OrdersListScreen> createState() => _OrdersListScreenState();
}

class _OrdersListScreenState extends State<OrdersListScreen> {
  late Future<UellowPage<UellowOrderSummary>> _future;
  String? _filter;

  @override
  void initState() {
    super.initState();
    _filter = widget.filterState;
    // fetch a wide page once; filter + count client-side so chips show counts.
    _future = UellowApi.instance.orders.list(perPage: 50);
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
      body: SafeArea(child: FutureBuilder<UellowPage<UellowOrderSummary>>(
        future: _future,
        builder: (_, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(
                color: UellowColors.darkBrown));
          }
          if (snap.hasError) {
            return Center(child: Padding(padding: const EdgeInsets.all(20),
                child: Text(snap.error.toString(),
                    textAlign: TextAlign.center, style: UT.body)));
          }
          // drop cancelled entirely (the user wants non-cancelled only)
          final all = (snap.data?.items ?? const <UellowOrderSummary>[])
              .where((o) => o.uellowStatus != 'cancelled').toList();
          final counts = <String, int>{};
          for (final o in all) {
            counts[o.uellowStatus] = (counts[o.uellowStatus] ?? 0) + 1;
          }
          final shown = _filter == null
              ? all
              : all.where((o) => o.uellowStatus == _filter).toList();
          return Column(children: [
            _FilterStrip(active: _filter, ar: ar, total: all.length,
                counts: counts,
                onSelect: (s) => setState(() => _filter = s)),
            Expanded(child: shown.isEmpty
                ? Center(child: Padding(padding: const EdgeInsets.all(40),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.inbox_outlined, size: 64,
                          color: UellowColors.muted),
                      const SizedBox(height: 12),
                      Text(ar ? 'لا توجد طلبات' : 'No orders', style: UT.body),
                    ])))
                : ListView.separated(
                    padding: const EdgeInsets.all(14),
                    itemCount: shown.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _OrderCard(order: shown[i], ar: ar))),
          ]);
        },
      )),
    );
  }
}

class _FilterStrip extends StatelessWidget {
  const _FilterStrip({required this.active, required this.onSelect,
      required this.ar, required this.counts, required this.total});
  final String? active;
  final ValueChanged<String?> onSelect;
  final bool ar;
  final Map<String, int> counts;
  final int total;
  static const _en = {'confirmed': 'Confirmed', 'preparing': 'Preparing',
      'shipping': 'Shipping', 'delivered': 'Delivered', 'returned': 'Returned'};
  static const _ar = {'confirmed': 'مؤكد', 'preparing': 'قيد التجهيز',
      'shipping': 'قيد الشحن', 'delivered': 'تم التوصيل', 'returned': 'مُرتجع'};
  @override
  Widget build(BuildContext context) {
    final order = ['confirmed', 'preparing', 'shipping', 'delivered', 'returned'];
    final chips = <(String?, String, int)>[
      (null, ar ? 'الكل' : 'All', total),
      for (final s in order)
        if ((counts[s] ?? 0) > 0) (s, (ar ? _ar : _en)[s]!, counts[s]!),
    ];
    return Container(
      color: Colors.white,
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: UellowColors.border))),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: SizedBox(height: 32, child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final (val, label, count) = chips[i];
          final on = active == val;
          return GestureDetector(
            onTap: () => onSelect(val),
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
              decoration: BoxDecoration(
                color: on ? UellowColors.darkBrown : UellowColors.border,
                borderRadius: BorderRadius.circular(999)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(label, style: TextStyle(
                    color: on ? UellowColors.yellowLight : UellowColors.text,
                    fontWeight: FontWeight.w800, fontSize: 12)),
                const SizedBox(width: 5),
                // count label for this status
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: on ? UellowColors.yellow : Colors.white,
                    borderRadius: BorderRadius.circular(999)),
                  child: Text('$count', style: TextStyle(
                      color: UellowColors.darkBrown,
                      fontWeight: FontWeight.w900, fontSize: 10.5)),
                ),
              ]),
            ),
          );
        },
      )),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.ar});
  final UellowOrderSummary order;
  final bool ar;

  Color _color(String s) => switch (s) {
    'confirmed' => const Color(0xFF0EA5E9),
    'preparing' => const Color(0xFF8B5CF6),
    'shipping'  => const Color(0xFFF59E0B),
    'delivered' => UellowColors.successDk,
    'returned'  => UellowColors.danger,
    _ => UellowColors.muted,
  };

  double _progress(String s) {
    final i = _kStages.indexOf(s);
    if (s == 'delivered') return 1.0;
    if (i < 0) return 0.12;                 // draft/confirmed start
    return (i + 1) / _kStages.length;
  }

  @override
  Widget build(BuildContext context) {
    final c = _color(order.uellowStatus);
    final prog = _progress(order.uellowStatus);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: UellowColors.border),
        boxShadow: const [BoxShadow(color: Color(0x0A000000),
            blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 42, height: 42,
            decoration: BoxDecoration(color: c.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(Icons.shopping_bag_outlined, color: c)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(order.name, style: const TextStyle(
                fontWeight: FontWeight.w900, color: UellowColors.ink)),
            const SizedBox(height: 2),
            Text(order.date?.split('T').first ?? '', style: const TextStyle(
                fontSize: 11, color: UellowColors.muted)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(order.total.format(), style: const TextStyle(
                fontWeight: FontWeight.w900, color: UellowColors.ink)),
            const SizedBox(height: 3),
            Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: c.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999)),
              child: Text(order.uellowStatusLabel.current(ar ? 'ar' : 'en'),
                  style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.w900))),
          ]),
        ]),
        const SizedBox(height: 12),
        // animated progress bar
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: prog),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => LinearProgressIndicator(
              value: v, minHeight: 7,
              backgroundColor: const Color(0xFFEFEFEF),
              valueColor: AlwaysStoppedAnimation(c)),
          ),
        ),
        const SizedBox(height: 6),
        Row(children: [
          // stage dots
          for (var i = 0; i < _kStages.length; i++) ...[
            Icon(prog >= (i + 1) / _kStages.length
                    ? Icons.check_circle : Icons.circle_outlined,
                size: 13,
                color: prog >= (i + 1) / _kStages.length ? c : UellowColors.border),
            if (i < _kStages.length - 1) Expanded(child: Container(
                height: 2, color: prog > (i + 1) / _kStages.length
                    ? c : UellowColors.border)),
          ],
        ]),
        const SizedBox(height: 10),
        // v2.2.34 — compact track button aligned to the end (was full-width).
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton.icon(
            onPressed: () => Navigator.pushNamed(context, '/order',
                arguments: {'id': order.id}),
            icon: const Icon(Icons.local_shipping_outlined, size: 15),
            label: Text(ar ? 'تتبع الطلب' : 'Track order',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
            style: TextButton.styleFrom(
              backgroundColor: UellowColors.yellowFaint,
              foregroundColor: UellowColors.darkBrown,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999)),
            ),
          ),
        ),
      ]),
    );
  }
}
