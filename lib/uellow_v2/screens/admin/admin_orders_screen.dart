// =============================================================================
// AdminOrdersScreen (v2.2.10) — every order across all sites, with
// search, state filter, infinite scroll, and a full detail page.
// =============================================================================
import 'dart:async';

import 'package:flutter/material.dart';
import '../../widgets/admin_console_nav.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../api/uellow_api.dart';
import '../../services/admin_mode.dart';
import '../../theme/uellow_theme.dart';
import 'admin_new_order_screen.dart';
import 'admin_helpdesk_screen.dart';

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
      bottomNavigationBar: const AdminConsoleNav(current: AdminTab.orders),
      backgroundColor: const Color(0xFFF2F3F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF412402),
        // v2.2.41 — yellow back arrow + title (was white, low-visibility).
        foregroundColor: UellowColors.yellow,
        iconTheme: const IconThemeData(color: UellowColors.yellow),
        title: Text('${ar ? '📦 الطلبات' : '📦 Orders'}'
            '${_total > 0 ? ' ($_total)' : ''}',
            style: const TextStyle(fontSize: 16,
                fontWeight: FontWeight.w900, color: UellowColors.yellow)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: UellowColors.yellow,
        foregroundColor: UellowColors.darkBrown,
        icon: const Icon(Icons.add_rounded),
        label: Text(ar ? 'طلب جديد' : 'New order',
            style: const TextStyle(fontWeight: FontWeight.w900)),
        onPressed: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => const AdminNewOrderScreen())).then((created) {
          if (created == true) _load(reset: true);
        }),
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
        // v2.2.41 — black font on a light chip so the filters are legible
        // (was washed-out white on the dark header).
        label: Text(label, style: const TextStyle(fontSize: 11,
            fontWeight: FontWeight.w800,
            color: UellowColors.darkBrown)),
        selected: sel,
        showCheckmark: false,
        selectedColor: UellowColors.yellow,
        backgroundColor: Colors.white,
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
  Map<String, dynamic>? _d; // v2.2.159 — للشريط السفلي الثابت
  void _fetch() {
    _future = AdminApi.instance.orderDetail(widget.orderId);
    _future.then((d) { if (mounted) setState(() => _d = d); });
  }
  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F5),
      bottomNavigationBar: _d == null ? null : _stickyBar(ar, _d!),
      appBar: AppBar(
        backgroundColor: const Color(0xFF412402),
        foregroundColor: UellowColors.yellow,
        iconTheme: const IconThemeData(color: UellowColors.yellow),
        title: Text(ar ? 'تفاصيل الطلب' : 'Order details',
            style: const TextStyle(fontSize: 16,
                fontWeight: FontWeight.w900, color: UellowColors.yellow)),
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
          final src = (d['source'] as Map?) ?? const {};
          final srcLabel = (src['label'] ?? '').toString();
          return ListView(padding: const EdgeInsets.all(14), children: [
            _card(children: [
              Row(children: [
                Text(d['name']?.toString() ?? '', style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w900,
                    color: UellowColors.darkBrown)),
                const Spacer(),
                if (srcLabel.isNotEmpty) _sourceChip(srcLabel),
              ]),
              const SizedBox(height: 4),
              Text(d['date']?.toString() ?? '', style: const TextStyle(
                  fontSize: 11, color: UellowColors.muted)),
              const SizedBox(height: 12),
              _stepper(ar, (d['stage'] as num?)?.toInt() ?? 1),
              const SizedBox(height: 12),
              Wrap(spacing: 6, runSpacing: 6, children: _statusBadges(ar, d)),
            ]),
            _card(title: ar ? '👤 العميل' : '👤 Customer', children: [
              _kv(ar ? 'الاسم' : 'Name', cust['name']?.toString() ?? ''),
              if ((cust['phone'] ?? '').toString().isNotEmpty)
                _phoneRow(context, ar, cust['phone'].toString())
              else
                _kv(ar ? 'الهاتف' : 'Phone', '—'),
              if ((cust['email'] ?? '').toString().isNotEmpty)
                _kv('Email', cust['email'].toString()),
              if ((d['shipping_address'] ?? '').toString().isNotEmpty)
                _kv(ar ? 'العنوان' : 'Address',
                    d['shipping_address'].toString()),
              if ((d['carrier'] ?? '').toString().isNotEmpty)
                _kv(ar ? 'شركة الشحن' : 'Carrier', d['carrier'].toString()),
              if ((cust['phone'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 11),
                Row(children: [
                  Expanded(child: _contactBtn(
                      Icons.phone_rounded, ar ? 'اتصال' : 'Call',
                      const Color(0xFF2563EB),
                      () => _call(context, ar, cust['phone'].toString()))),
                  const SizedBox(width: 8),
                  Expanded(child: _contactBtn(
                      Icons.chat_rounded, ar ? 'واتساب' : 'WhatsApp',
                      const Color(0xFF25D366),
                      () => _whatsapp(context, ar, cust['phone'].toString()))),
                  if ((cust['map_url'] ?? '').toString().isNotEmpty) ...[
                    const SizedBox(width: 8),
                    SizedBox(width: 48, child: _contactBtn(
                        Icons.map_rounded, '',
                        const Color(0xFF412402),
                        () => _launch(ar, Uri.parse(cust['map_url'].toString()),
                            cust['map_url'].toString()))),
                  ],
                ]),
              ],
            ]),
            _card(title: ar ? '🛒 المنتجات' : '🛒 Items', children: [
              for (final l in lines) InkWell(
                onTap: () => _showProductDialog(
                    context, ar, (l as Map).cast<String, dynamic>()),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    ClipRRect(borderRadius: BorderRadius.circular(8),
                        child: Image.network((l as Map)['image']?.toString()
                            ?? '', width: 42, height: 42, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                                width: 42, height: 42,
                                color: UellowColors.border,
                                child: const Icon(Icons.image_not_supported_rounded,
                                    size: 18, color: UellowColors.muted)))),
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
                    const SizedBox(width: 2),
                    const Icon(Icons.chevron_left_rounded, size: 18,
                        color: UellowColors.muted),
                  ]),
                ),
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
              if (amounts['cost'] != null) ...[
                const SizedBox(height: 6),
                _amtRow(ar ? 'التكلفة' : 'Cost', amounts['cost'] as Map?),
                _profitRow(ar, amounts['margin'] as Map?),
              ],
            ]),
            if (txs.isNotEmpty || (d['payment'] is Map))
              _card(children: [
                Row(children: [
                  Text(ar ? '💳 الدفع' : '💳 Payment', style: UT.h3),
                  const Spacer(),
                  if (d['payment'] is Map)
                    (d['payment'] as Map)['paid'] == true
                        ? _statusBadge(ar ? 'مدفوع' : 'Paid',
                            const Color(0xFFE3F3EA), const Color(0xFF1A7A46))
                        : _statusBadge(ar ? 'غير مدفوع' : 'Unpaid',
                            const Color(0xFFFBEFD6), const Color(0xFFA9680A)),
                ]),
                const SizedBox(height: 8),
                if (d['payment'] is Map) ...[
                  _kv(ar ? 'الطريقة' : 'Method',
                      ((d['payment'] as Map)['method'] ?? '').toString()),
                  if ((d['payment'] as Map)['collected'] is Map)
                    _kv(ar ? 'المحصّل' : 'Collected',
                        '${((d['payment'] as Map)['collected'] as Map)['amount'] ?? 0}'
                        ' ${((d['payment'] as Map)['collected'] as Map)['symbol'] ?? ''}'),
                ],
                for (final t in txs) _kv(
                    '${(t as Map)['provider'] ?? ''} (${t['state'] ?? ''})',
                    '${t['amount'] ?? 0}'),
              ]),
            _supportCard(context, d, ar),
            _fulfilCard(d, ar),
            _docsCard(d, ar),
            _actionCard(d, ar),
            const SizedBox(height: 24),
          ]);
        },
      ),
    );
  }

  bool _busy = false;

  void _reload() => setState(_fetch);

  Future<void> _run(Future<Map<String, dynamic>> Function() op,
      String okMsg) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await op();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(okMsg)));
        _reload();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: UellowColors.danger));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // Profit row — green when positive, red on a loss (free/gift lines etc).
  Widget _profitRow(bool ar, Map? m) {
    final v = (m?['amount'] as num?) ?? 0;
    final loss = v < 0;
    final col = loss ? UellowColors.danger : UellowColors.successDk;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Text(ar ? 'الربح' : 'Profit', style: TextStyle(
            fontSize: 12.5, fontWeight: FontWeight.w900, color: col)),
        const Spacer(),
        Text('${m?['amount'] ?? 0} ${m?['symbol'] ?? ''}',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900,
                color: col)),
      ]),
    );
  }

  // ── Contact (call / WhatsApp / copy) ──────────────────────────────────
  String _waNumber(String raw) {
    var p = raw.replaceAll(RegExp(r'[^0-9+]'), '');
    if (p.startsWith('+')) {
      p = p.substring(1);
    } else if (p.startsWith('00')) {
      p = p.substring(2);
    } else if (p.length == 8) {
      p = '965$p'; // رقم كويتي محلي
    }
    return p;
  }

  Future<void> _launch(bool ar, Uri uri, String copyText) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (ok) return;
    } catch (_) {}
    if (!mounted) return;
    await Clipboard.setData(ClipboardData(text: copyText));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ar ? 'تعذّر الفتح — تم نسخ الرقم'
                          : 'Could not open — number copied')));
  }

  Future<void> _call(BuildContext ctx, bool ar, String phone) =>
      _launch(ar, Uri(scheme: 'tel', path: phone.replaceAll(' ', '')), phone);

  Future<void> _whatsapp(BuildContext ctx, bool ar, String phone) => _launch(
      ar, Uri.parse('https://wa.me/${_waNumber(phone)}'), phone);

  Future<void> _copyPhone(BuildContext ctx, bool ar, String phone) async {
    await Clipboard.setData(ClipboardData(text: phone));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ar ? 'تم نسخ الرقم' : 'Number copied')));
  }

  Widget _phoneRow(BuildContext context, bool ar, String phone) => InkWell(
    onTap: () => _call(context, ar, phone),
    onLongPress: () => _copyPhone(context, ar, phone),
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 92, child: Text(ar ? 'الهاتف' : 'Phone',
            style: const TextStyle(fontSize: 11, color: UellowColors.muted,
                fontWeight: FontWeight.w700))),
        Expanded(child: Text(phone, textDirection: TextDirection.ltr,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800,
                color: Color(0xFF2563EB)))),
        const Icon(Icons.touch_app_rounded, size: 14,
            color: UellowColors.muted),
      ]),
    ),
  );

  Widget _contactBtn(IconData icon, String label, Color color,
      VoidCallback onTap) => ElevatedButton.icon(
    onPressed: onTap,
    icon: Icon(icon, size: 17),
    label: Text(label, style: const TextStyle(
        fontWeight: FontWeight.w900, fontSize: 12.5)),
    style: ElevatedButton.styleFrom(
      backgroundColor: color, foregroundColor: Colors.white, elevation: 0,
      padding: const EdgeInsets.symmetric(vertical: 11),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
    ),
  );

  // ── Professional product dialog (image + full line economics) ─────────
  void _showProductDialog(BuildContext context, bool ar,
      Map<String, dynamic> l) {
    final qty = (l['qty'] as num? ?? 0);
    final unit = (l['price_unit'] as num? ?? 0);
    final disc = (l['discount'] as num? ?? 0);
    final total = (l['total'] as num? ?? 0);
    final cost = (l['cost'] as num? ?? 0);
    final margin = (l['margin'] as num? ?? 0);
    final loss = margin < 0;
    String m(num v) => v.toStringAsFixed(3);
    showDialog(context: context, builder: (c) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          child: Image.network(l['image']?.toString() ?? '',
              height: 180, width: double.infinity, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(height: 180,
                  color: UellowColors.border,
                  child: const Icon(Icons.image_not_supported_rounded,
                      size: 40, color: UellowColors.muted))),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(l['name']?.toString() ?? '', style: const TextStyle(
                fontSize: 14.5, fontWeight: FontWeight.w900,
                color: UellowColors.darkBrown)),
            const SizedBox(height: 12),
            if ((l['sku'] ?? '').toString().isNotEmpty)
              _dlgRow(ar ? 'الكود (SKU)' : 'SKU', l['sku'].toString()),
            if ((l['variant'] ?? '').toString().isNotEmpty)
              _dlgRow(ar ? 'الخيار' : 'Variant', l['variant'].toString()),
            if (l['qty_available'] != null)
              _dlgRow(ar ? 'المخزون' : 'In stock',
                  ((l['qty_available'] as num? ?? 0) > 0)
                      ? '${(l['qty_available'] as num).toStringAsFixed(0)}'
                          ' ${ar ? '✓ متوفر' : '✓ available'}'
                      : (ar ? 'غير متوفر' : 'out of stock'),
                  color: ((l['qty_available'] as num? ?? 0) > 0)
                      ? UellowColors.successDk : UellowColors.danger),
            _dlgRow(ar ? 'الكمية' : 'Qty', qty.toStringAsFixed(0)),
            _dlgRow(ar ? 'سعر الوحدة' : 'Unit price', m(unit)),
            if (disc != 0) _dlgRow(ar ? 'الخصم' : 'Discount',
                '${disc.toStringAsFixed(2)}%'),
            const Divider(height: 18),
            _dlgRow(ar ? 'إجمالي السطر' : 'Line total', m(total), bold: true),
            _dlgRow(ar ? 'التكلفة' : 'Cost', m(cost)),
            _dlgRow(ar ? 'الربح' : 'Profit', m(margin),
                color: loss ? UellowColors.danger : UellowColors.successDk,
                bold: true),
            const SizedBox(height: 14),
            SizedBox(width: double.infinity, child: TextButton(
              onPressed: () => Navigator.pop(c),
              child: Text(ar ? 'إغلاق' : 'Close',
                  style: const TextStyle(fontWeight: FontWeight.w900)),
            )),
          ]),
        ),
      ]),
    ));
  }

  Widget _dlgRow(String k, String v, {bool bold = false, Color? color}) =>
      Padding(
    padding: const EdgeInsets.symmetric(vertical: 3.5),
    child: Row(children: [
      Text(k, style: TextStyle(fontSize: bold ? 12.5 : 11.5,
          fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
          color: color ?? UellowColors.text)),
      const Spacer(),
      Text(v, textDirection: TextDirection.ltr, style: TextStyle(
          fontSize: bold ? 13.5 : 12,
          fontWeight: FontWeight.w900,
          color: color ?? UellowColors.darkBrown)),
    ]),
  );

  // ── In-order support thread (badge of unread customer messages) ───────
  Widget _supportCard(BuildContext context, Map<String, dynamic> d, bool ar) {
    final tickets = ((d['tickets'] as List?) ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>()).toList();
    if (tickets.isEmpty) return const SizedBox.shrink();
    final pending = (d['support_pending'] as num? ?? 0).toInt();
    return _card(children: [
      Row(children: [
        Text(ar ? '🎧 الدعم الفني' : '🎧 Support', style: UT.h3),
        const SizedBox(width: 8),
        if (pending > 0) _badge(pending),
      ]),
      const SizedBox(height: 10),
      for (final t in tickets) _ticketRow(context, ar, t),
    ]);
  }

  Widget _badge(int n) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(color: UellowColors.danger,
        borderRadius: BorderRadius.circular(10)),
    child: Text('$n', style: const TextStyle(color: Colors.white,
        fontSize: 10.5, fontWeight: FontWeight.w900)),
  );

  Widget _ticketRow(BuildContext context, bool ar, Map<String, dynamic> t) {
    final pend = (t['pending'] as num? ?? 0).toInt();
    final closed = t['closed'] == true;
    final id = (t['id'] as num).toInt();
    return InkWell(
      onTap: () async {
        await Navigator.push(context, MaterialPageRoute(
            builder: (_) => AdminHelpdeskTicketScreen(ticketId: id)));
        _reload();
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 7),
        padding: const EdgeInsets.fromLTRB(11, 9, 9, 9),
        decoration: BoxDecoration(
            color: pend > 0 ? const Color(0xFFFFF4F4) : const Color(0xFFF7F8FA),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: pend > 0
                ? UellowColors.danger.withValues(alpha: .25)
                : const Color(0xFFECECEC))),
        child: Row(children: [
          Icon(closed ? Icons.check_circle_rounded
                      : Icons.support_agent_rounded,
              size: 20,
              color: closed ? UellowColors.successDk : UellowColors.darkBrown),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text('#${t['ref'] ?? ''} · ${t['subject'] ?? ''}',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: UellowColors.darkBrown)),
            const SizedBox(height: 2),
            Text('${t['stage'] ?? ''}'
                '${(t['last_at'] ?? '').toString().isNotEmpty ? ' · ${t['last_at']}' : ''}',
                style: const TextStyle(fontSize: 10,
                    color: UellowColors.muted)),
          ])),
          if (pend > 0) ...[const SizedBox(width: 6), _badge(pend)],
          const SizedBox(width: 4),
          const Icon(Icons.chevron_left_rounded, size: 18,
              color: UellowColors.muted),
        ]),
      ),
    );
  }

  // Delivery + fulfilment status (carrier company/driver, invoices, pickings).
  Widget _fulfilCard(Map<String, dynamic> d, bool ar) {
    final dv = (d['delivery'] as Map?) ?? const {};
    final invs = (d['invoices'] as List?) ?? const [];
    final picks = (d['pickings'] as List?) ?? const [];
    final hasAny = (dv['company'] ?? '').toString().isNotEmpty ||
        (dv['driver'] ?? '').toString().isNotEmpty ||
        (dv['status'] ?? '').toString().isNotEmpty ||
        invs.isNotEmpty || picks.isNotEmpty;
    if (!hasAny) return const SizedBox.shrink();
    return _card(title: ar ? '🚚 التوصيل والفوترة' : '🚚 Delivery & invoicing',
        children: [
      if ((dv['company'] ?? '').toString().isNotEmpty)
        _kv(ar ? 'شركة الشحن' : 'Carrier', dv['company'].toString()),
      if ((dv['driver'] ?? '').toString().isNotEmpty)
        _kv(ar ? 'السائق' : 'Driver', dv['driver'].toString()),
      if ((dv['status'] ?? '').toString().isNotEmpty)
        _kv(ar ? 'حالة التوصيل' : 'Delivery status', dv['status'].toString()),
      if ((dv['trip'] ?? '').toString().isNotEmpty)
        _kv(ar ? 'الرحلة' : 'Trip', dv['trip'].toString()),
      if (dv['cost'] is Map)
        _kv(ar ? 'تكلفة التوصيل' : 'Delivery cost',
            '${(dv['cost'] as Map)['amount'] ?? 0} ${(dv['cost'] as Map)['symbol'] ?? ''}'),
      if (dv['commission'] is Map)
        _kv(ar ? 'عمولة التحصيل' : 'Collection fee',
            '${(dv['commission'] as Map)['amount'] ?? 0} ${(dv['commission'] as Map)['symbol'] ?? ''}'),
      if (dv['net_cost'] is Map)
        _kv(ar ? 'صافي تكلفة الشركة' : 'Net company cost',
            '${(dv['net_cost'] as Map)['amount'] ?? 0} ${(dv['net_cost'] as Map)['symbol'] ?? ''}'),
      if ((d['invoice_status'] ?? '').toString().isNotEmpty)
        _kv(ar ? 'حالة الفوترة' : 'Invoice status',
            d['invoice_status'].toString()),
      for (final i in invs)
        _kv('🧾 ${(i as Map)['name'] ?? ''}',
            '${i['state'] ?? ''} · ${i['payment_state'] ?? ''}'),
      for (final pk in picks)
        _kv('📦 ${(pk as Map)['name'] ?? ''}', '${pk['state'] ?? ''}'),
    ]);
  }

  Widget _actionCard(Map<String, dynamic> d, bool ar) {
    final can = (d['can'] as Map?) ?? const {};
    final state = (d['state'] ?? '').toString();
    final isCancelled = state == 'cancel';
    final id = widget.orderId;
    bool flag(String k, bool fallback) =>
        can.containsKey(k) ? can[k] == true : fallback;
    final isConfirmed = state == 'sale' || state == 'done';
    final btns = <Widget>[];
    if (flag('confirm', !isCancelled && !isConfirmed)) {
      btns.add(_actBtn(ar ? '✅ اعتماد الطلب' : '✅ Approve order',
          UellowColors.successDk,
          () => _run(() => AdminApi.instance.orderApprove(id),
              ar ? 'تم اعتماد الطلب' : 'Order approved')));
    }
    if (flag('assign_delivery', isConfirmed)) {
      btns.add(_actBtn(ar ? '🚚 تعيين توصيل' : '🚚 Assign delivery',
          UellowColors.darkBrown, () => _openAssignDelivery(id, ar)));
    }
    if (flag('deliver', false)) {
      btns.add(_actBtn(ar ? '📦 تأكيد التسليم' : '📦 Validate delivery',
          const Color(0xFF0D9488),
          () => _run(() => AdminApi.instance.orderDeliver(id),
              ar ? 'تم تأكيد التسليم' : 'Delivery validated')));
    }
    if (flag('invoice', false)) {
      btns.add(_actBtn(ar ? '🧾 إنشاء فاتورة' : '🧾 Create invoice',
          const Color(0xFF7C3AED),
          () => _run(() => AdminApi.instance.orderInvoice(id),
              ar ? 'تم إنشاء الفاتورة' : 'Invoice created')));
    }
    if (flag('verify_payment', false)) {
      btns.add(_actBtn(ar ? '🔎 التحقق من الدفع' : '🔎 Verify payment',
          const Color(0xFF2563EB),
          () => _run(() => AdminApi.instance.orderVerifyPayment(id),
              ar ? 'تم التحقق من حالة الدفع' : 'Payment status checked')));
    }
    if (flag('register_payment', false)) {
      btns.add(_actBtn(ar ? '💵 تسجيل دفعة' : '💵 Register payment',
          const Color(0xFF059669),
          () => _run(() => AdminApi.instance.orderRegisterPayment(id),
              ar ? 'تم تسجيل الدفعة' : 'Payment registered')));
    }
    if (flag('lock', false)) {
      btns.add(_actBtn(ar ? '🔒 قفل الطلب' : '🔒 Lock order',
          const Color(0xFF64748B),
          () => _run(() => AdminApi.instance.orderLock(id),
              ar ? 'تم قفل الطلب' : 'Order locked')));
    }
    if (flag('unlock', false)) {
      btns.add(_actBtn(ar ? '🔓 فتح القفل' : '🔓 Unlock order',
          const Color(0xFF64748B),
          () => _run(() => AdminApi.instance.orderUnlock(id),
              ar ? 'تم فتح القفل' : 'Order unlocked')));
    }
    if (!isCancelled) {
      btns.add(_actBtn(ar ? '🔔 إشعار مخصّص للعميل' : '🔔 Custom notification',
          UellowColors.yellow, () => _openNotifyDialog(id, ar),
          fg: UellowColors.darkBrown));
      btns.add(_actBtn(ar ? '✏️ تعديل الأصناف' : '✏️ Edit items',
          const Color(0xFF475569), () => _openEditItems(d, id, ar)));
    }
    if (flag('cancel', !isCancelled)) {
      btns.add(_actBtn(ar ? '✖ إلغاء الطلب' : '✖ Cancel order',
          UellowColors.danger, () => _confirmCancel(id, ar)));
      btns.add(_actBtn(ar ? '🔕 إلغاء صامت (بدون إشعار)' : '🔕 Silent cancel',
          const Color(0xFF9A3412), () => _confirmCancelSilent(id, ar)));
    }
    if (btns.isEmpty) return const SizedBox.shrink();
    return _card(title: ar ? '⚙️ إجراءات' : '⚙️ Actions', children: [
      if (_busy) const Padding(padding: EdgeInsets.only(bottom: 8),
          child: LinearProgressIndicator(minHeight: 2)),
      ...btns,
    ]);
  }

  // v2.2.159 — شريط إجراءات سفلي ثابت (إلغاء + الإجراء الأساسي حسب الحالة).
  Widget? _stickyBar(bool ar, Map<String, dynamic> d) {
    final can = (d['can'] as Map?) ?? const {};
    final state = (d['state'] ?? '').toString();
    if (state == 'cancel') return null;
    final id = widget.orderId;
    Widget? primary;
    if (can['confirm'] == true) {
      primary = _barBtn(ar ? '✅ اعتماد الطلب' : '✅ Approve',
          UellowColors.successDk,
          () => _run(() => AdminApi.instance.orderApprove(id),
              ar ? 'تم الاعتماد' : 'Approved'));
    } else if (can['deliver'] == true) {
      primary = _barBtn(ar ? '📦 تأكيد التسليم' : '📦 Deliver',
          const Color(0xFF0D9488),
          () => _run(() => AdminApi.instance.orderDeliver(id),
              ar ? 'تم التسليم' : 'Delivered'));
    } else if (can['invoice'] == true) {
      primary = _barBtn(ar ? '🧾 إنشاء فاتورة' : '🧾 Invoice',
          const Color(0xFF7C3AED),
          () => _run(() => AdminApi.instance.orderInvoice(id),
              ar ? 'تم إنشاء الفاتورة' : 'Invoiced'));
    }
    final canCancel = can.containsKey('cancel') ? can['cancel'] == true : true;
    if (primary == null && !canCancel) return null;
    return SafeArea(top: false, child: Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: const BoxDecoration(color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFECECEC)))),
      child: Row(children: [
        if (canCancel)
          Expanded(flex: 2, child: _barBtn(ar ? 'إلغاء' : 'Cancel',
              UellowColors.danger, () => _confirmCancel(id, ar),
              outline: true)),
        if (canCancel && primary != null) const SizedBox(width: 8),
        if (primary != null) Expanded(flex: 3, child: primary),
      ]),
    ));
  }

  Widget _barBtn(String label, Color color, VoidCallback onTap,
          {bool outline = false}) =>
      outline
          ? OutlinedButton(onPressed: _busy ? null : onTap,
              style: OutlinedButton.styleFrom(foregroundColor: color,
                  side: BorderSide(color: color),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w900)))
          : ElevatedButton(onPressed: _busy ? null : onTap,
              style: ElevatedButton.styleFrom(backgroundColor: color,
                  foregroundColor: Colors.white, elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w900)));

  Widget _actBtn(String label, Color color, VoidCallback onTap,
      {Color fg = Colors.white}) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: SizedBox(width: double.infinity, child: ElevatedButton(
      onPressed: _busy ? null : onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color, foregroundColor: fg,
        elevation: 0, padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(label, style: TextStyle(
          fontWeight: FontWeight.w900, color: fg)),
    )),
  );

  Future<void> _confirmCancel(int id, bool ar) async {
    final ok = await showDialog<bool>(context: context, builder: (c) =>
        AlertDialog(
          title: Text(ar ? 'إلغاء الطلب؟' : 'Cancel order?'),
          content: Text(ar ? 'لا يمكن التراجع بسهولة.'
              : "This can't be easily undone."),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false),
                child: Text(ar ? 'تراجع' : 'Back')),
            TextButton(onPressed: () => Navigator.pop(c, true),
                child: Text(ar ? 'إلغاء الطلب' : 'Cancel order',
                    style: const TextStyle(color: UellowColors.danger))),
          ],
        ));
    if (ok == true) {
      _run(() => AdminApi.instance.orderCancel(id),
          ar ? 'تم إلغاء الطلب' : 'Order cancelled');
    }
  }

  Future<void> _openAssignDelivery(int id, bool ar) async {
    Map<String, dynamic> opts;
    try {
      opts = await AdminApi.instance.deliveryOptions();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ar ? 'تعذّر تحميل خيارات التوصيل'
              : 'Failed to load delivery options')));
      return;
    }
    final companies = ((opts['carrier_companies'] as List?) ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>()).toList();
    final drivers = ((opts['drivers'] as List?) ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>()).toList();
    if (companies.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ar ? 'لا توجد شركات شحن مُعدّة'
              : 'No carrier companies configured')));
      return;
    }
    int? companyId = (companies.first['id'] as num).toInt();
    int? driverId;
    String payType = 'cash';
    String setStatus = 'assigned';
    if (!mounted) return;
    final go = await showModalBottomSheet<bool>(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius:
          BorderRadius.vertical(top: Radius.circular(18))),
      builder: (c) => StatefulBuilder(builder: (c, setSt) {
        final dl = drivers.where((d) => d['carrier_company_id'] == null ||
            d['carrier_company_id'] == companyId).toList();
        return Padding(
          padding: EdgeInsets.fromLTRB(18, 16, 18,
              16 + MediaQuery.of(c).viewInsets.bottom +
                  MediaQuery.of(c).padding.bottom),
          child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(ar ? '🚚 تعيين توصيل' : '🚚 Assign delivery',
                style: UT.h3),
            const SizedBox(height: 12),
            _ddl<int?>(ar ? 'شركة الشحن' : 'Carrier company', companyId,
                [for (final c0 in companies)
                  DropdownMenuItem<int?>(value: (c0['id'] as num).toInt(),
                      child: Text(c0['name']?.toString() ?? ''))],
                (v) => setSt(() { companyId = v; driverId = null; })),
            const SizedBox(height: 10),
            _ddl<int?>(ar ? 'السائق (اختياري)' : 'Driver (optional)',
                driverId,
                [const DropdownMenuItem(value: null, child: Text('—')),
                  for (final d0 in dl)
                    DropdownMenuItem(value: (d0['id'] as num).toInt(),
                        child: Text(d0['name']?.toString() ?? ''))],
                (v) => setSt(() => driverId = v)),
            const SizedBox(height: 10),
            _ddl<String>(ar ? 'نوع الدفع' : 'Payment type', payType,
                [
                  DropdownMenuItem(value: 'cash',
                      child: Text(ar ? 'كاش عند الاستلام' : 'Cash on delivery')),
                  DropdownMenuItem(value: 'online',
                      child: Text(ar ? 'مدفوع أونلاين' : 'Paid online')),
                  DropdownMenuItem(value: 'free',
                      child: Text(ar ? 'مجاني' : 'Free')),
                ], (v) => setSt(() => payType = v ?? 'cash')),
            const SizedBox(height: 10),
            _ddl<String>(ar ? 'الحالة' : 'Status', setStatus, [
              DropdownMenuItem(value: 'assigned',
                  child: Text(ar ? 'مُسند' : 'Assigned')),
              DropdownMenuItem(value: 'out_for_delivery',
                  child: Text(ar ? 'خرج للتوصيل' : 'Out for delivery')),
            ], (v) => setSt(() => setStatus = v ?? 'assigned')),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: () => Navigator.pop(c, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: UellowColors.yellow,
                  foregroundColor: UellowColors.darkBrown,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              child: Text(ar ? 'تأكيد التعيين' : 'Confirm assignment',
                  style: const TextStyle(fontWeight: FontWeight.w900)),
            )),
          ]),
        );
      }),
    );
    if (go == true) {
      _run(() => AdminApi.instance.assignDelivery(id, {
            'carrier_company_id': companyId,
            if (driverId != null) 'driver_id': driverId,
            'payment_method_type': payType,
            'set_status': setStatus,
            'create_trip': true,
          }), ar ? 'تم تعيين التوصيل' : 'Delivery assigned');
    }
  }

  Widget _ddl<T>(String label, T value, List<DropdownMenuItem<T>> items,
      ValueChanged<T?> onChanged) => InputDecorator(
    decoration: InputDecoration(
      labelText: label, isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    ),
    child: DropdownButtonHideUnderline(child: DropdownButton<T>(
      value: value, isExpanded: true, items: items, onChanged: onChanged)),
  );

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

  // ── v2.2.151 — مكوّنات شاشة الطلب الإدارية (مطابقة للموكاب) ───────────
  Widget _sourceChip(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(color: const Color(0xFF412402),
        borderRadius: BorderRadius.circular(999)),
    child: Text('📱 $label', style: const TextStyle(fontSize: 10.5,
        fontWeight: FontWeight.w800, color: Color(0xFFFFE9A8))),
  );

  Widget _statusBadge(String t, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(color: bg,
        borderRadius: BorderRadius.circular(999)),
    child: Text(t, style: TextStyle(fontSize: 10.5,
        fontWeight: FontWeight.w800, color: fg)),
  );

  List<Widget> _statusBadges(bool ar, Map<String, dynamic> d) {
    final state = (d['state'] ?? '').toString();
    final paid = d['paid'] == true;
    final dstat = (d['delivery_status'] ?? '').toString();
    final isNew = ((d['customer'] as Map?)?['is_new']) == true;
    final out = <Widget>[];
    if (state == 'sale' || state == 'done') {
      out.add(_statusBadge(ar ? '✅ مؤكّد' : '✅ Confirmed',
          const Color(0xFFE3F3EA), const Color(0xFF1A7A46)));
    } else if (state == 'cancel') {
      out.add(_statusBadge(ar ? '✖ ملغي' : '✖ Cancelled',
          const Color(0xFFF8E0DC), const Color(0xFFC23B2B)));
    } else {
      out.add(_statusBadge(ar ? '📝 مسودة' : '📝 Draft',
          const Color(0xFFFBEFD6), const Color(0xFFA9680A)));
    }
    out.add(paid
        ? _statusBadge(ar ? '💳 مدفوع' : '💳 Paid',
            const Color(0xFFE3F3EA), const Color(0xFF1A7A46))
        : _statusBadge(ar ? '⏳ غير مدفوع' : '⏳ Unpaid',
            const Color(0xFFFBEFD6), const Color(0xFFA9680A)));
    if (dstat.isNotEmpty) {
      out.add(_statusBadge('🚚 $dstat',
          const Color(0xFFE5EEFB), const Color(0xFF1D5FB4)));
    }
    if (isNew) {
      out.add(_statusBadge(ar ? '⭐ عميل جديد' : '⭐ New customer',
          const Color(0xFFFDF3D6), const Color(0xFF6B4E00)));
    }
    return out;
  }

  Widget _stepper(bool ar, int stage) {
    final labels = ar
        ? const ['عرض سعر', 'مؤكّد', 'مُسند', 'قيد التوصيل', 'تم التسليم']
        : const ['Quote', 'Confirmed', 'Assigned', 'Delivering', 'Delivered'];
    return Row(children: [
      for (int i = 0; i < labels.length; i++)
        Expanded(child: Column(children: [
          Container(
            width: 22, height: 22,
            decoration: BoxDecoration(shape: BoxShape.circle,
                color: i < stage
                    ? const Color(0xFF1A7A46)
                    : (i == stage ? UellowColors.yellow
                        : const Color(0xFFF3EFE6)),
                border: Border.all(
                    color: i <= stage
                        ? (i == stage ? UellowColors.yellow
                            : const Color(0xFF1A7A46))
                        : const Color(0xFFE9E1D1), width: 2)),
            child: Icon(i < stage ? Icons.check : Icons.circle,
                size: i < stage ? 12 : 7,
                color: i < stage ? Colors.white
                    : (i == stage ? const Color(0xFF412402)
                        : UellowColors.muted)),
          ),
          const SizedBox(height: 3),
          Text(labels[i], textAlign: TextAlign.center,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 8,
                  fontWeight: i == stage ? FontWeight.w900 : FontWeight.w600,
                  color: i <= stage ? UellowColors.darkBrown
                      : UellowColors.muted)),
        ])),
    ]);
  }

  Widget _docsCard(Map<String, dynamic> d, bool ar) {
    final id = widget.orderId;
    Future<void> open(String kind) async {
      try {
        final url = await AdminApi.instance.orderDocumentUrl(id, kind);
        if (url == null || url.isEmpty) throw Exception('no url');
        if (!mounted) return;
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } catch (_) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(ar ? 'تعذّر فتح المستند' : 'Could not open document'),
            backgroundColor: UellowColors.danger));
      }
    }
    return _card(title: ar ? '🖨️ المستندات' : '🖨️ Documents', children: [
      Row(children: [
        Expanded(child: _docBtn(ar ? '🧾 فاتورة' : '🧾 Invoice',
            () => open('invoice'))),
        const SizedBox(width: 8),
        Expanded(child: _docBtn(ar ? '📜 ضمان' : '📜 Warranty',
            () => open('warranty'))),
        const SizedBox(width: 8),
        Expanded(child: _docBtn(ar ? '🧾 إيصال' : '🧾 Receipt',
            () => open('receipt'))),
      ]),
    ]);
  }

  Widget _docBtn(String label, VoidCallback onTap) => OutlinedButton(
    onPressed: onTap,
    style: OutlinedButton.styleFrom(
      foregroundColor: UellowColors.darkBrown,
      side: const BorderSide(color: Color(0xFFE9E1D1)),
      padding: const EdgeInsets.symmetric(vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
    ),
    child: Text(label, textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
  );

  Future<void> _openNotifyDialog(int id, bool ar) async {
    final titleC = TextEditingController();
    final bodyC = TextEditingController();
    final go = await showDialog<bool>(context: context, builder: (c) =>
        AlertDialog(
          title: Text(ar ? '🔔 إشعار مخصّص للعميل' : '🔔 Custom notification'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: titleC, decoration: InputDecoration(
                labelText: ar ? 'العنوان' : 'Title')),
            const SizedBox(height: 8),
            TextField(controller: bodyC, maxLines: 3,
                decoration: InputDecoration(
                    labelText: ar ? 'نص الرسالة' : 'Message')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false),
                child: Text(ar ? 'إلغاء' : 'Cancel')),
            TextButton(onPressed: () => Navigator.pop(c, true),
                child: Text(ar ? 'إرسال' : 'Send')),
          ],
        ));
    if (go == true) {
      final t = titleC.text.trim();
      final b = bodyC.text.trim();
      if (t.isEmpty || b.isEmpty) return;
      _run(() => AdminApi.instance.orderNotify(id, {
            'title': t, 'title_ar': t, 'body': b, 'body_ar': b,
          }), ar ? 'تم إرسال الإشعار' : 'Notification sent');
    }
  }

  Future<void> _confirmCancelSilent(int id, bool ar) async {
    final ok = await showDialog<bool>(context: context, builder: (c) =>
        AlertDialog(
          title: Text(ar ? 'إلغاء صامت؟' : 'Silent cancel?'),
          content: Text(ar ? 'سيُلغى الطلب دون إشعار العميل.'
              : 'Cancels without notifying the customer.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false),
                child: Text(ar ? 'تراجع' : 'Back')),
            TextButton(onPressed: () => Navigator.pop(c, true),
                child: Text(ar ? 'إلغاء صامت' : 'Silent cancel',
                    style: const TextStyle(color: UellowColors.danger))),
          ],
        ));
    if (ok == true) {
      _run(() => AdminApi.instance.orderCancel(id, silent: true),
          ar ? 'تم الإلغاء بدون إشعار' : 'Cancelled silently');
    }
  }

  Future<void> _openEditItems(Map<String, dynamic> d, int id, bool ar) async {
    final lines = ((d['lines'] as List?) ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>()).toList();
    if (lines.isEmpty) return;
    await showModalBottomSheet(context: context, isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius:
          BorderRadius.vertical(top: Radius.circular(18))),
      builder: (c) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16,
            16 + MediaQuery.of(c).padding.bottom),
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(ar ? '✏️ تعديل الأصناف' : '✏️ Edit items', style: UT.h3),
          const SizedBox(height: 10),
          for (final l in lines) Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              Expanded(child: Text(l['name']?.toString() ?? '',
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12,
                      fontWeight: FontWeight.w700))),
              const SizedBox(width: 8),
              Text('×${(l['qty'] as num? ?? 0).toStringAsFixed(0)}',
                  style: const TextStyle(fontSize: 12,
                      fontWeight: FontWeight.w900)),
              IconButton(icon: const Icon(Icons.edit_rounded, size: 18),
                  onPressed: () async {
                    Navigator.pop(c);
                    await _editLineQty(id, l, ar);
                  }),
              IconButton(icon: const Icon(Icons.delete_outline_rounded,
                  size: 18, color: UellowColors.danger),
                  onPressed: () {
                    Navigator.pop(c);
                    _run(() => AdminApi.instance.orderEditLine(id, {
                          'line_id': l['id'], 'remove': true,
                        }), ar ? 'تم حذف الصنف' : 'Item removed');
                  }),
            ]),
          ),
        ]),
      ),
    );
  }

  Future<void> _editLineQty(int id, Map<String, dynamic> l, bool ar) async {
    final c0 = TextEditingController(
        text: (l['qty'] as num? ?? 1).toStringAsFixed(0));
    final go = await showDialog<bool>(context: context, builder: (c) =>
        AlertDialog(
          title: Text(ar ? 'تعديل الكمية' : 'Edit quantity'),
          content: TextField(controller: c0,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: ar ? 'الكمية' : 'Qty')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false),
                child: Text(ar ? 'إلغاء' : 'Cancel')),
            TextButton(onPressed: () => Navigator.pop(c, true),
                child: Text(ar ? 'حفظ' : 'Save')),
          ],
        ));
    if (go == true) {
      final q = double.tryParse(c0.text.trim()) ?? 0;
      _run(() => AdminApi.instance.orderEditLine(id, {
            'line_id': l['id'], 'qty': q,
          }), ar ? 'تم تحديث الكمية' : 'Quantity updated');
    }
  }
}
