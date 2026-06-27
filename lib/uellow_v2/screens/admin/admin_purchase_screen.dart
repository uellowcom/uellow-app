// =============================================================================
// AdminPurchaseScreen (v2.2.57) — procurement manager: browse RFQs &
// purchase orders, filter by state (RFQ / to-approve / to-receive / to-bill),
// open any one to confirm, receive the goods, create the vendor bill or
// cancel — all from the in-app admin console.
// =============================================================================
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../api/uellow_api.dart';
import '../../theme/uellow_theme.dart';
import '../../services/admin_mode.dart';

const _brown = Color(0xFF412402);

// State → (color, EN, AR) for the status pill.
({Color c, String en, String ar}) _stateStyle(String s) {
  switch (s) {
    case 'draft':
      return (c: const Color(0xFF64748B), en: 'RFQ', ar: 'طلب عرض سعر');
    case 'sent':
      return (c: const Color(0xFF0EA5E9), en: 'RFQ Sent', ar: 'تم الإرسال');
    case 'to approve':
      return (c: const Color(0xFFF59E0B), en: 'To Approve', ar: 'بانتظار الموافقة');
    case 'purchase':
      return (c: const Color(0xFF059669), en: 'Purchase Order', ar: 'أمر شراء');
    case 'done':
      return (c: const Color(0xFF475569), en: 'Locked', ar: 'مغلق');
    case 'cancel':
      return (c: const Color(0xFFDC2626), en: 'Cancelled', ar: 'ملغي');
  }
  return (c: const Color(0xFF64748B), en: s, ar: s);
}

class AdminPurchaseScreen extends StatefulWidget {
  const AdminPurchaseScreen({super.key});
  @override
  State<AdminPurchaseScreen> createState() => _AdminPurchaseScreenState();
}

class _AdminPurchaseScreenState extends State<AdminPurchaseScreen> {
  final _scroll = ScrollController();
  final _searchCtl = TextEditingController();
  Timer? _debounce;

  final List<Map<String, dynamic>> _rows = [];
  Map<String, dynamic> _counts = {};
  int _page = 1, _pages = 1, _total = 0;
  bool _loading = false;
  String _q = '';
  String _state = ''; // '' = all

  // (key, EN, AR, counts-key)
  static const _filters = <(String, String, String, String)>[
    ('', 'All', 'الكل', 'all'),
    ('rfq', 'RFQs', 'طلبات عرض سعر', 'rfq'),
    ('to_approve', 'To Approve', 'للموافقة', 'to approve'),
    ('purchase', 'Orders', 'أوامر الشراء', 'purchase'),
    ('to_receive', 'To Receive', 'للاستلام', ''),
    ('to_bill', 'To Bill', 'للفوترة', ''),
    ('cancel', 'Cancelled', 'ملغاة', 'cancel'),
  ];

  @override
  void initState() {
    super.initState();
    _loadMeta();
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

  Future<void> _loadMeta() async {
    try {
      final d = await AdminApi.instance.purchaseMeta();
      if (mounted) {
        setState(() => _counts = (d['counts'] as Map?)?.cast<String,
            dynamic>() ?? {});
      }
    } catch (_) {}
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      _page = 1;
      _rows.clear();
    }
    setState(() => _loading = true);
    try {
      final d = await AdminApi.instance
          .purchases(page: _page, q: _q, state: _state);
      _pages = (d['pages'] as num?)?.toInt() ?? 1;
      _total = (d['total'] as num?)?.toInt() ?? 0;
      _rows.addAll(((d['purchases'] as List?) ?? const [])
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
        backgroundColor: _brown,
        foregroundColor: UellowColors.yellow,
        iconTheme: const IconThemeData(color: UellowColors.yellow),
        title: Text('${ar ? '🛒 المشتريات' : '🛒 Purchases'}'
            '${_total > 0 ? ' ($_total)' : ''}',
            style: const TextStyle(fontSize: 16,
                fontWeight: FontWeight.w900, color: UellowColors.yellow)),
      ),
      body: Column(children: [
        Container(
          color: _brown,
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          child: TextField(
            controller: _searchCtl,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: ar ? '🔍 الرقم / المورد / المرجع'
                           : '🔍 Number / vendor / reference',
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
        ),
        // filter chips
        Container(
          color: _brown,
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _filters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 7),
              itemBuilder: (_, i) {
                final f = _filters[i];
                final sel = _state == f.$1;
                final cnt = f.$4.isNotEmpty
                    ? (_counts[f.$4] as num?)?.toInt() : null;
                return GestureDetector(
                  onTap: () {
                    setState(() => _state = f.$1);
                    _load(reset: true);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 13, vertical: 6),
                    decoration: BoxDecoration(
                      color: sel ? UellowColors.yellow
                          : Colors.white.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Center(child: Text(
                        '${ar ? f.$3 : f.$2}'
                        '${cnt != null && cnt > 0 ? ' $cnt' : ''}',
                        style: TextStyle(fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: sel ? _brown : Colors.white))),
                  ),
                );
              },
            ),
          ),
        ),
        Expanded(child: _rows.isEmpty && _loading
            ? const Center(child: CircularProgressIndicator(
                color: UellowColors.darkBrown))
            : _rows.isEmpty
                ? Center(child: Text(ar ? 'لا توجد طلبات شراء'
                    : 'No purchase orders',
                    style: const TextStyle(color: UellowColors.muted)))
                : RefreshIndicator(
                    onRefresh: () async {
                      await _loadMeta();
                      await _load(reset: true);
                    },
                    child: ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
                      itemCount: _rows.length + (_loading ? 1 : 0),
                      itemBuilder: (_, i) {
                        if (i >= _rows.length) {
                          return const Padding(padding: EdgeInsets.all(14),
                              child: Center(child: SizedBox(
                                  width: 20, height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))));
                        }
                        return _row(ar, _rows[i]);
                      },
                    ),
                  )),
      ]),
    );
  }

  Widget _row(bool ar, Map<String, dynamic> po) {
    final st = _stateStyle((po['state'] ?? '').toString());
    final total = (po['total'] as Map?) ?? const {};
    final recv = (po['receipt_status'] ?? '').toString();
    final inv = (po['invoice_status'] ?? '').toString();
    return InkWell(
      onTap: () async {
        await _openDetail(context, (po['id'] as num).toInt(), ar);
        _loadMeta();
        _load(reset: true);
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
        decoration: BoxDecoration(color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFECECEC))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text((po['name'] ?? '').toString(),
                style: const TextStyle(fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    color: UellowColors.darkBrown)),
            const Spacer(),
            _pill(ar ? st.ar : st.en, st.c),
          ]),
          const SizedBox(height: 5),
          Text((po['vendor'] ?? '').toString(),
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Row(children: [
            Text((po['date'] ?? '').toString(),
                style: const TextStyle(fontSize: 10.5,
                    color: UellowColors.muted)),
            const SizedBox(width: 8),
            Text('${po['items'] ?? 0} ${ar ? 'صنف' : 'items'}',
                style: const TextStyle(fontSize: 10.5,
                    color: UellowColors.muted)),
            const Spacer(),
            Text('${total['amount'] ?? 0} ${total['symbol'] ?? ''}',
                style: const TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: UellowColors.darkBrown)),
          ]),
          if (recv == 'pending' || recv == 'partial' || inv == 'to invoice')
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Wrap(spacing: 6, runSpacing: 4, children: [
                if (recv == 'pending')
                  _tag(ar ? '📦 بانتظار الاستلام' : '📦 To receive',
                      const Color(0xFFF59E0B)),
                if (recv == 'partial')
                  _tag(ar ? '📦 استلام جزئي' : '📦 Partial receipt',
                      const Color(0xFFF59E0B)),
                if (inv == 'to invoice')
                  _tag(ar ? '🧾 بانتظار الفاتورة' : '🧾 To bill',
                      const Color(0xFF7C3AED)),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _pill(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: c.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(7)),
        child: Text(t, style: TextStyle(fontSize: 10,
            fontWeight: FontWeight.w900, color: c)),
      );

  Widget _tag(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(color: c.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(6)),
        child: Text(t, style: TextStyle(fontSize: 9.5,
            fontWeight: FontWeight.w800, color: c)),
      );

  Future<void> _openDetail(BuildContext ctx, int id, bool ar) =>
      showModalBottomSheet<void>(
        context: ctx,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _PurchaseDetailSheet(poId: id, ar: ar),
      );
}

// ─── detail bottom sheet ─────────────────────────────────────────────────
class _PurchaseDetailSheet extends StatefulWidget {
  const _PurchaseDetailSheet({required this.poId, required this.ar});
  final int poId;
  final bool ar;
  @override
  State<_PurchaseDetailSheet> createState() => _PurchaseDetailSheetState();
}

class _PurchaseDetailSheetState extends State<_PurchaseDetailSheet> {
  late Future<Map<String, dynamic>> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = AdminApi.instance.purchaseDetail(widget.poId);
  }

  void _reload() => setState(() {
        _future = AdminApi.instance.purchaseDetail(widget.poId);
      });

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
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: UellowColors.danger));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmCancel(bool ar) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(ar ? 'إلغاء طلب الشراء؟' : 'Cancel purchase order?'),
        content: Text(ar
            ? 'سيتم إلغاء هذا الطلب. لا يمكن التراجع بسهولة.'
            : 'This will cancel the order. Not easily reversible.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false),
              child: Text(ar ? 'تراجع' : 'Back')),
          TextButton(onPressed: () => Navigator.pop(c, true),
              child: Text(ar ? 'إلغاء الطلب' : 'Cancel order',
                  style: const TextStyle(color: UellowColors.danger))),
        ],
      ),
    );
    if (go == true) {
      _run(() => AdminApi.instance.purchaseCancel(widget.poId),
          ar ? 'تم إلغاء الطلب' : 'Order cancelled');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ar = widget.ar;
    return DraggableScrollableSheet(
      initialChildSize: .9, minChildSize: .5, maxChildSize: .95,
      expand: false,
      builder: (_, sc) => Container(
        decoration: const BoxDecoration(color: Color(0xFFF2F3F5),
            borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
        child: FutureBuilder<Map<String, dynamic>>(
          future: _future,
          builder: (_, snap) {
            if (!snap.hasData) {
              return const SizedBox(height: 300, child: Center(
                  child: CircularProgressIndicator(
                      color: UellowColors.darkBrown)));
            }
            final d = snap.data!;
            return Stack(children: [
              ListView(controller: sc,
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
                  children: [
                Center(child: Container(width: 42, height: 4,
                    decoration: BoxDecoration(color: const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(3)))),
                const SizedBox(height: 12),
                _header(d, ar),
                const SizedBox(height: 12),
                _vendorCard(d, ar),
                const SizedBox(height: 12),
                _linesCard(d, ar),
                const SizedBox(height: 12),
                _fulfilCard(d, ar),
                const SizedBox(height: 12),
                _actionCard(d, ar),
              ]),
              if (_busy)
                Positioned.fill(child: Container(
                    color: Colors.black.withValues(alpha: .08),
                    child: const Center(child: CircularProgressIndicator(
                        color: UellowColors.darkBrown)))),
            ]);
          },
        ),
      ),
    );
  }

  Widget _header(Map<String, dynamic> d, bool ar) {
    final st = _stateStyle((d['state'] ?? '').toString());
    final amt = ((d['amounts'] as Map?)?['total'] as Map?) ?? const {};
    return Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        Text((d['name'] ?? '').toString(), style: const TextStyle(
            fontSize: 18, fontWeight: FontWeight.w900,
            color: UellowColors.darkBrown)),
        const SizedBox(height: 3),
        Text((d['date'] ?? '').toString(), style: const TextStyle(
            fontSize: 11, color: UellowColors.muted)),
      ])),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(color: st.c.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(8)),
          child: Text(ar ? st.ar : st.en, style: TextStyle(fontSize: 11,
              fontWeight: FontWeight.w900, color: st.c)),
        ),
        const SizedBox(height: 6),
        Text('${amt['amount'] ?? 0} ${amt['symbol'] ?? ''}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900,
                color: UellowColors.darkBrown)),
      ]),
    ]);
  }

  Widget _vendorCard(Map<String, dynamic> d, bool ar) {
    final v = (d['vendor'] as Map?) ?? const {};
    return _card(title: ar ? '🏭 المورد' : '🏭 Vendor', children: [
      _kv(ar ? 'الاسم' : 'Name', (v['name'] ?? '').toString()),
      if ((v['phone'] ?? '').toString().isNotEmpty)
        _kv(ar ? 'الهاتف' : 'Phone', v['phone'].toString()),
      if ((v['email'] ?? '').toString().isNotEmpty)
        _kv(ar ? 'البريد' : 'Email', v['email'].toString()),
      if ((v['ref'] ?? '').toString().isNotEmpty)
        _kv(ar ? 'مرجع المورد' : 'Vendor ref', v['ref'].toString()),
    ]);
  }

  Widget _linesCard(Map<String, dynamic> d, bool ar) {
    final lines = (d['lines'] as List?) ?? const [];
    final amt = (d['amounts'] as Map?) ?? const {};
    Map m(String k) => (amt[k] as Map?) ?? const {};
    return _card(title: ar ? '📦 الأصناف' : '📦 Items', children: [
      for (final l in lines) Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          ClipRRect(borderRadius: BorderRadius.circular(8),
              child: Image.network((l as Map)['image']?.toString() ?? '',
                  width: 40, height: 40, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(width: 40,
                      height: 40, color: UellowColors.border))),
          const SizedBox(width: 9),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text((l['name'] ?? '').toString(), maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.5,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text('${l['qty']} × ${l['price_unit']}'
                '   ${ar ? 'مستلم' : 'recv'} ${l['received']}',
                style: const TextStyle(fontSize: 9.5,
                    color: UellowColors.muted)),
          ])),
          const SizedBox(width: 6),
          Text('${l['total']}', style: const TextStyle(fontSize: 12,
              fontWeight: FontWeight.w900, color: UellowColors.darkBrown)),
        ]),
      ),
      const Divider(height: 18),
      _amtRow(ar ? 'الإجمالي قبل الضريبة' : 'Untaxed', m('untaxed')),
      _amtRow(ar ? 'الضريبة' : 'Tax', m('tax')),
      _amtRow(ar ? 'الإجمالي' : 'Total', m('total'), bold: true),
    ]);
  }

  Widget _fulfilCard(Map<String, dynamic> d, bool ar) {
    final picks = (d['pickings'] as List?) ?? const [];
    final bills = (d['bills'] as List?) ?? const [];
    if (picks.isEmpty && bills.isEmpty &&
        (d['invoice_status'] ?? '').toString().isEmpty) {
      return const SizedBox.shrink();
    }
    return _card(title: ar ? '🚚 الاستلام والفوترة' : '🚚 Receipt & billing',
        children: [
      if ((d['receipt_status'] ?? '').toString().isNotEmpty)
        _kv(ar ? 'حالة الاستلام' : 'Receipt status',
            (d['receipt_status']).toString()),
      if ((d['invoice_status'] ?? '').toString().isNotEmpty)
        _kv(ar ? 'حالة الفوترة' : 'Invoice status',
            (d['invoice_status']).toString()),
      for (final pk in picks)
        _kv('📦 ${(pk as Map)['name'] ?? ''}',
            '${pk['state'] ?? ''} (${pk['type'] ?? ''})'),
      for (final b in bills)
        _kv('🧾 ${(b as Map)['name'] ?? ''}',
            '${b['state'] ?? ''} · ${b['payment_state'] ?? ''}'),
    ]);
  }

  Widget _actionCard(Map<String, dynamic> d, bool ar) {
    final can = (d['can'] as Map?) ?? const {};
    final id = widget.poId;
    bool flag(String k) => can[k] == true;
    final btns = <Widget>[];
    if (flag('confirm')) {
      btns.add(_actBtn(ar ? '✅ تأكيد الطلب' : '✅ Confirm order',
          const Color(0xFF059669),
          () => _run(() => AdminApi.instance.purchaseConfirm(id),
              ar ? 'تم تأكيد الطلب' : 'Order confirmed')));
    }
    if (flag('receive')) {
      btns.add(_actBtn(ar ? '📦 استلام البضاعة' : '📦 Receive goods',
          const Color(0xFF0D9488),
          () => _run(() => AdminApi.instance.purchaseReceive(id),
              ar ? 'تم تأكيد الاستلام' : 'Goods received')));
    }
    if (flag('bill')) {
      btns.add(_actBtn(ar ? '🧾 إنشاء فاتورة المورد' : '🧾 Create vendor bill',
          const Color(0xFF7C3AED),
          () => _run(() => AdminApi.instance.purchaseBill(id),
              ar ? 'تم إنشاء الفاتورة' : 'Vendor bill created')));
    }
    if (flag('cancel')) {
      btns.add(_actBtn(ar ? '✖ إلغاء الطلب' : '✖ Cancel order',
          UellowColors.danger, () => _confirmCancel(ar)));
    }
    if (btns.isEmpty) {
      return _card(title: ar ? '⚙️ الإجراءات' : '⚙️ Actions', children: [
        Text(ar ? 'لا توجد إجراءات متاحة لهذه الحالة.'
            : 'No actions available for this state.',
            style: const TextStyle(fontSize: 12, color: UellowColors.muted)),
      ]);
    }
    return _card(title: ar ? '⚙️ الإجراءات' : '⚙️ Actions',
        children: [for (final b in btns) Padding(
            padding: const EdgeInsets.only(bottom: 8), child: b)]);
  }

  // ── small shared widgets ──
  Widget _card({required String title, required List<Widget> children}) =>
      Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [BoxShadow(color: Color(0x10000000),
                blurRadius: 8, offset: Offset(0, 3))]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 13,
              fontWeight: FontWeight.w900, color: UellowColors.darkBrown)),
          const SizedBox(height: 8),
          ...children,
        ]),
      );

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 120, child: Text(k, style: const TextStyle(
              fontSize: 11.5, color: UellowColors.muted))),
          Expanded(child: Text(v, style: const TextStyle(fontSize: 11.5,
              fontWeight: FontWeight.w700))),
        ]),
      );

  Widget _amtRow(String k, Map m, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Text(k, style: TextStyle(fontSize: bold ? 13 : 12,
              fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
              color: bold ? UellowColors.darkBrown : UellowColors.muted)),
          const Spacer(),
          Text('${m['amount'] ?? 0} ${m['symbol'] ?? ''}',
              style: TextStyle(fontSize: bold ? 14 : 12.5,
                  fontWeight: FontWeight.w900,
                  color: UellowColors.darkBrown)),
        ]),
      );

  Widget _actBtn(String label, Color c, VoidCallback onTap) => SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _busy ? null : onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: c, foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(label, style: const TextStyle(fontSize: 13.5,
              fontWeight: FontWeight.w900)),
        ),
      );
}
