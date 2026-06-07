// =============================================================================
// AdminOrdersScreen (v2.2.10) — every order across all sites, with
// search, state filter, infinite scroll, and a full detail page.
// =============================================================================
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../api/uellow_api.dart';
import '../../services/admin_mode.dart';
import '../../theme/uellow_theme.dart';

class AdminOrdersScreen extends StatefulWidget {
  const AdminOrdersScreen({super.key});
  @override
  State<AdminOrdersScreen> createState() => _AdminOrdersScreenState();
}

class _AdminOrdersScreenState extends State<AdminOrdersScreen> {
  final _scroll = ScrollController();
  final _searchCtl = TextEditingController();
  Timer? _debounce;

  final List<Map<String, dynamic>> _rows = [];
  int _page = 1, _pages = 1, _total = 0;
  bool _loading = false;
  String _q = '', _state = '';

  @override
  void initState() {
    super.initState();
    _load(reset: true);
    _scroll.addListener(() {
      if (_scroll.position.pixels >
              _scroll.position.maxScrollExtent - 300 &&
          !_loading && _page < _pages) {
        _page += 1;
        _load();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _searchCtl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      _page = 1;
      _rows.clear();
    }
    setState(() => _loading = true);
    try {
      final d = await AdminApi.instance
          .orders(page: _page, q: _q, state: _state);
      _pages = (d['pages'] as num?)?.toInt() ?? 1;
      _total = (d['total'] as num?)?.toInt() ?? 0;
      _rows.addAll(((d['orders'] as List?) ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>()));
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF412402),
        foregroundColor: Colors.white,
        title: Text('${ar ? '📦 الطلبات' : '📦 Orders'}'
            '${_total > 0 ? ' ($_total)' : ''}',
            style: const TextStyle(fontSize: 16,
                fontWeight: FontWeight.w900)),
      ),
      body: Column(children: [
        // search + filters
        Container(
          color: const Color(0xFF412402),
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          child: Column(children: [
            TextField(
              controller: _searchCtl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: ar ? '🔍 رقم الطلب / اسم العميل / الهاتف'
                             : '🔍 Order # / customer / phone',
                hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: .45), fontSize: 12),
                filled: true,
                fillColor: Colors.white.withValues(alpha: .1),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 11),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
              onChanged: (v) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 450), () {
                  _q = v.trim();
                  _load(reset: true);
                });
              },
            ),
            const SizedBox(height: 9),
            SizedBox(height: 30, child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _chip(ar ? 'الكل' : 'All', ''),
                _chip(ar ? 'مؤكدة' : 'Confirmed', 'sale'),
                _chip(ar ? 'عروض أسعار' : 'Quotations', 'quotation'),
                _chip(ar ? 'ملغاة' : 'Cancelled', 'cancel'),
              ],
            )),
          ]),
        ),
        Expanded(child: _rows.isEmpty && _loading
            ? const Center(child: CircularProgressIndicator(
                color: UellowColors.darkBrown))
            : RefreshIndicator(
                onRefresh: () => _load(reset: true),
                child: ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
                  itemCount: _rows.length + (_loading ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i >= _rows.length) {
                      return const Padding(
                        padding: EdgeInsets.all(14),
                        child: Center(child: SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))),
                      );
                    }
                    return _OrderTile(o: _rows[i], ar: ar);
                  },
                ),
              )),
      ]),
    );
  }

  Widget _chip(String label, String value) {
    final sel = _state == value;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: ChoiceChip(
        label: Text(label, style: TextStyle(fontSize: 11,
            fontWeight: FontWeight.w800,
            color: sel ? UellowColors.darkBrown : Colors.white)),
        selected: sel,
        showCheckmark: false,
        selectedColor: UellowColors.yellow,
        backgroundColor: Colors.white.withValues(alpha: .12),
        side: BorderSide.none,
        visualDensity: VisualDensity.compact,
        onSelected: (_) {
          _state = value;
          _load(reset: true);
        },
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.o, required this.ar});
  final Map<String, dynamic> o;
  final bool ar;

  static const _stateColors = {
    'sale': Color(0xFF10B981), 'done': Color(0xFF10B981),
    'draft': Color(0xFF6B7280), 'sent': Color(0xFF6B7280),
    'cancel': Color(0xFFEF4444),
  };

  String _stateLabel() {
    final ds = (o['delivery_status'] ?? '').toString();
    if (o['state'] == 'cancel') return ar ? 'ملغي' : 'Cancelled';
    switch (ds) {
      case 'delivered': return ar ? 'تم التوصيل' : 'Delivered';
      case 'out_for_delivery': return ar ? 'خرج للتوصيل' : 'Out for delivery';
      case 'arrived_sorting': return ar ? 'في مركز الفرز' : 'At sorting';
      case 'failed': return ar ? 'فشل التوصيل' : 'Failed';
    }
    if (o['state'] == 'sale' || o['state'] == 'done') {
      return ar ? 'مؤكد' : 'Confirmed';
    }
    return ar ? 'عرض سعر' : 'Quotation';
  }

  @override
  Widget build(BuildContext context) {
    final m = (o['total'] as Map?) ?? const {};
    final c = _stateColors[o['state']] ?? const Color(0xFF6B7280);
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => AdminOrderDetailScreen(
              orderId: (o['id'] as num).toInt()))),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
        decoration: BoxDecoration(color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFECECEC))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Row(children: [
            Text(o['name']?.toString() ?? '', style: const TextStyle(
                fontSize: 13.5, fontWeight: FontWeight.w900,
                color: UellowColors.darkBrown)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 7, vertical: 2.5),
              decoration: BoxDecoration(color: c.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(6)),
              child: Text(_stateLabel(), style: TextStyle(fontSize: 9.5,
                  fontWeight: FontWeight.w800, color: c)),
            ),
            const Spacer(),
            Text('${(m['amount'] as num? ?? 0).toStringAsFixed((m['digits'] as num?)?.toInt() ?? 3)} ${m['symbol'] ?? ''}',
                style: const TextStyle(fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: UellowColors.darkBrown)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.person_outline_rounded, size: 13,
                color: UellowColors.muted),
            const SizedBox(width: 4),
            Expanded(child: Text(
                '${o['customer'] ?? ''}'
                '${(o['phone'] ?? '').toString().isNotEmpty ? ' · ${o['phone']}' : ''}',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11,
                    color: UellowColors.text))),
            Text(o['date']?.toString() ?? '', style: const TextStyle(
                fontSize: 10, color: UellowColors.muted)),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  color: const Color(0xFFF5F6F8),
                  borderRadius: BorderRadius.circular(5)),
              child: Text(o['website']?.toString() ?? '',
                  style: const TextStyle(fontSize: 9,
                      color: UellowColors.muted,
                      fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 6),
            Text('${o['items'] ?? 0} ${ar ? 'منتج' : 'items'}',
                style: const TextStyle(fontSize: 10,
                    color: UellowColors.muted)),
            if ((o['payment'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(width: 6),
              Text('· ${o['payment']}', style: const TextStyle(fontSize: 10,
                  color: UellowColors.muted)),
            ],
          ]),
        ]),
      ),
    );
  }
}

// ─── detail ──────────────────────────────────────────────────────────────
class AdminOrderDetailScreen extends StatefulWidget {
  const AdminOrderDetailScreen({super.key, required this.orderId});
  final int orderId;
  @override
  State<AdminOrderDetailScreen> createState() =>
      _AdminOrderDetailScreenState();
}

class _AdminOrderDetailScreenState extends State<AdminOrderDetailScreen> {
  late Future<Map<String, dynamic>> _future;
  @override
  void initState() {
    super.initState();
    _future = AdminApi.instance.orderDetail(widget.orderId);
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF412402),
        foregroundColor: Colors.white,
        title: Text(ar ? 'تفاصيل الطلب' : 'Order details',
            style: const TextStyle(fontSize: 16,
                fontWeight: FontWeight.w900)),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (_, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(
                color: UellowColors.darkBrown));
          }
          final d = snap.data;
          if (d == null) {
            return Center(child: Text(ar ? 'تعذر التحميل' : 'Failed to load'));
          }
          final amounts = (d['amounts'] as Map?) ?? const {};
          final cust = (d['customer'] as Map?) ?? const {};
          final lines = (d['lines'] as List?) ?? const [];
          final txs = (d['transactions'] as List?) ?? const [];
          return ListView(padding: const EdgeInsets.all(14), children: [
            _card(children: [
              Row(children: [
                Text(d['name']?.toString() ?? '', style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w900,
                    color: UellowColors.darkBrown)),
                const Spacer(),
                Text(d['date']?.toString() ?? '', style: const TextStyle(
                    fontSize: 11, color: UellowColors.muted)),
              ]),
              const SizedBox(height: 4),
              Text('${d['website'] ?? ''}'
                  '${(d['delivery_status'] ?? '').toString().isNotEmpty ? ' · ${d['delivery_status']}' : ''}',
                  style: const TextStyle(fontSize: 11,
                      color: UellowColors.muted)),
            ]),
            _card(title: ar ? '👤 العميل' : '👤 Customer', children: [
              _kv(ar ? 'الاسم' : 'Name', cust['name']?.toString() ?? ''),
              _kv(ar ? 'الهاتف' : 'Phone', cust['phone']?.toString() ?? ''),
              if ((cust['email'] ?? '').toString().isNotEmpty)
                _kv('Email', cust['email'].toString()),
              if ((d['shipping_address'] ?? '').toString().isNotEmpty)
                _kv(ar ? 'العنوان' : 'Address',
                    d['shipping_address'].toString()),
              if ((d['carrier'] ?? '').toString().isNotEmpty)
                _kv(ar ? 'شركة الشحن' : 'Carrier', d['carrier'].toString()),
            ]),
            _card(title: ar ? '🛒 المنتجات' : '🛒 Items', children: [
              for (final l in lines) Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  ClipRRect(borderRadius: BorderRadius.circular(8),
                      child: Image.network((l as Map)['image']?.toString()
                          ?? '', width: 40, height: 40, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                              width: 40, height: 40,
                              color: UellowColors.border))),
                  const SizedBox(width: 10),
                  Expanded(child: Text(l['name']?.toString() ?? '',
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5,
                          fontWeight: FontWeight.w600))),
                  const SizedBox(width: 8),
                  Column(crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                    Text('×${(l['qty'] as num? ?? 0).toStringAsFixed(0)}',
                        style: const TextStyle(fontSize: 10.5,
                            color: UellowColors.muted)),
                    Text('${l['total'] ?? 0}', style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w900,
                        color: UellowColors.darkBrown)),
                  ]),
                ]),
              ),
            ]),
            _card(title: ar ? '💰 المبالغ' : '💰 Amounts', children: [
              _amtRow(ar ? 'المنتجات' : 'Subtotal',
                  amounts['untaxed'] as Map?),
              _amtRow(ar ? 'التوصيل' : 'Delivery',
                  amounts['delivery'] as Map?),
              if (((amounts['tax'] as Map?)?['amount'] as num? ?? 0) != 0)
                _amtRow(ar ? 'الضريبة' : 'Tax', amounts['tax'] as Map?),
              const Divider(height: 16),
              _amtRow(ar ? 'الإجمالي' : 'Total', amounts['total'] as Map?,
                  bold: true),
            ]),
            if (txs.isNotEmpty)
              _card(title: ar ? '💳 الدفع' : '💳 Payments', children: [
                for (final t in txs) _kv(
                    '${(t as Map)['provider'] ?? ''} (${t['state'] ?? ''})',
                    '${t['amount'] ?? 0}'),
              ]),
            const SizedBox(height: 24),
          ]);
        },
      ),
    );
  }

  Widget _card({String? title, required List<Widget> children}) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
    decoration: BoxDecoration(color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFECECEC))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (title != null) ...[
        Text(title, style: UT.h3),
        const SizedBox(height: 8),
      ],
      ...children,
    ]),
  );

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 92, child: Text(k, style: const TextStyle(
          fontSize: 11, color: UellowColors.muted,
          fontWeight: FontWeight.w700))),
      Expanded(child: Text(v, style: const TextStyle(fontSize: 11.5,
          fontWeight: FontWeight.w600))),
    ]),
  );

  Widget _amtRow(String label, Map? m, {bool bold = false}) {
    final a = (m?['amount'] as num? ?? 0)
        .toStringAsFixed((m?['digits'] as num?)?.toInt() ?? 3);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(children: [
        Text(label, style: TextStyle(fontSize: bold ? 13 : 11.5,
            fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
            color: bold ? UellowColors.darkBrown : UellowColors.text)),
        const Spacer(),
        Text('$a ${m?['symbol'] ?? ''}', style: TextStyle(
            fontSize: bold ? 14 : 12,
            fontWeight: FontWeight.w900,
            color: bold ? UellowColors.darkBrown : UellowColors.text)),
      ]),
    );
  }
}
