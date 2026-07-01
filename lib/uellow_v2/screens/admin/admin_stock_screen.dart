// =============================================================================
// AdminStockScreen (v2.2.60) — per-product inventory control for the 🛡️ console.
//
// Answers "how many do I really have, and is the count right?":
//   • current on-hand + forecast
//   • total received (purchases / IN) vs total shipped (sales / OUT)
//   • an "unexplained" delta = on-hand − (in − out) that flags a suspicious
//     count (opening balances / manual edits)
//   • full stock-move history (in/out, ref, partner)
//   • every manual adjustment WITH its reason and who made it
// The admin can set a variant's on-hand quantity — a reason is REQUIRED and is
// stored in the audit log.
// =============================================================================
import 'package:flutter/material.dart';

import '../../services/admin_mode.dart';
import '../../../api/uellow_api.dart';
import '../../theme/uellow_theme.dart';

class AdminStockScreen extends StatefulWidget {
  const AdminStockScreen({super.key, required this.tmplId, this.title});
  final int tmplId;
  final String? title;

  @override
  State<AdminStockScreen> createState() => _AdminStockScreenState();
}

class _AdminStockScreenState extends State<AdminStockScreen> {
  Map<String, dynamic>? _d;
  bool _loading = true;
  String? _error;

  bool get _ar => UellowApi.instance.lang == 'ar';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _d = await AdminApi.instance.productStock(widget.tmplId);
      _error = null;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final ar = _ar;
    return Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F6F8),
        appBar: AppBar(
          backgroundColor: const Color(0xFF412402),
          foregroundColor: UellowColors.yellow,
          title: Text(ar ? 'المخزون والحركة' : 'Stock & Ledger',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(
                color: Color(0xFF412402)))
            : _error != null
                ? _errorView(ar)
                : RefreshIndicator(onRefresh: _load, child: _body(ar)),
      ),
    );
  }

  Widget _errorView(bool ar) => ListView(children: [
        const SizedBox(height: 120),
        Center(child: Icon(Icons.error_outline,
            size: 46, color: UellowColors.danger)),
        const SizedBox(height: 10),
        Center(child: Text(_error ?? '', textAlign: TextAlign.center)),
        const SizedBox(height: 16),
        Center(child: OutlinedButton(
            onPressed: _load,
            child: Text(ar ? 'إعادة المحاولة' : 'Retry'))),
      ]);

  Widget _body(bool ar) {
    final d = _d!;
    final storable = d['is_storable'] == true;
    final onHand = (d['on_hand'] as num? ?? 0);
    final totalIn = (d['total_in'] as num? ?? 0);
    final totalOut = (d['total_out'] as num? ?? 0);
    final unexplained = (d['unexplained'] as num? ?? 0);
    final uom = (d['uom'] ?? '').toString();
    final variants = (d['variants'] as List? ?? const []);
    final history = (d['history'] as List? ?? const []);
    final adjustments = (d['adjustments'] as List? ?? const []);
    final name = ar
        ? (d['product']?['name_ar'] ?? d['product']?['name'] ?? '')
        : (d['product']?['name'] ?? '');

    return ListView(padding: const EdgeInsets.all(14), children: [
      Text(name.toString(),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
      Text('${d['location'] ?? ''}',
          style: const TextStyle(fontSize: 11, color: UellowColors.muted)),
      const SizedBox(height: 12),

      if (!storable)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: const Color(0xFFFFF3CD),
              borderRadius: BorderRadius.circular(12)),
          child: Text(
              ar ? 'هذا المنتج غير مُخزّن — لا يُتابَع المخزون له.'
                 : 'This product is not storable — stock is not tracked.',
              style: const TextStyle(fontSize: 12)),
        ),

      // ── summary cards ────────────────────────────────────────────────
      Row(children: [
        _kpi(ar ? 'المتبقي' : 'On hand', '$onHand', uom,
            const Color(0xFF059669), Icons.inventory_2_outlined),
        const SizedBox(width: 8),
        _kpi(ar ? 'المشتريات' : 'Purchased', '$totalIn', uom,
            const Color(0xFF2563EB), Icons.south_west_rounded),
        const SizedBox(width: 8),
        _kpi(ar ? 'المبيعات' : 'Sold', '$totalOut', uom,
            const Color(0xFFDB2777), Icons.north_east_rounded),
      ]),
      const SizedBox(height: 8),
      // reconciliation hint
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: unexplained.abs() < 0.01
              ? const Color(0xFFE8F5EC)
              : const Color(0xFFFDECEC),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Icon(
              unexplained.abs() < 0.01
                  ? Icons.verified_rounded
                  : Icons.report_problem_rounded,
              size: 18,
              color: unexplained.abs() < 0.01
                  ? const Color(0xFF059669)
                  : UellowColors.danger),
          const SizedBox(width: 8),
          Expanded(child: Text(
              unexplained.abs() < 0.01
                  ? (ar
                      ? 'المخزون متطابق: المتبقي = المشتريات − المبيعات.'
                      : 'Reconciled: on-hand = purchased − sold.')
                  : (ar
                      ? 'فرق غير مُفسَّر بمقدار $unexplained (رصيد افتتاحي أو تعديل يدوي). راجع السجل.'
                      : 'Unexplained gap of $unexplained (opening balance / manual edit). Check the log.'),
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700))),
        ]),
      ),
      const SizedBox(height: 16),

      // ── adjust actions (per variant) ─────────────────────────────────
      if (storable) ...[
        Text(ar ? '⚙️ تعديل الكمية' : '⚙️ Adjust quantity', style: UT.h3),
        const SizedBox(height: 6),
        for (final v in variants) _variantRow(ar, v as Map, uom),
        const SizedBox(height: 16),
      ],

      // ── manual adjustment log ────────────────────────────────────────
      if (adjustments.isNotEmpty) ...[
        Text(ar ? '📝 سجل التعديلات اليدوية' : '📝 Manual adjustments',
            style: UT.h3),
        const SizedBox(height: 6),
        for (final a in adjustments) _adjustRow(ar, a as Map),
        const SizedBox(height: 16),
      ],

      // ── move history ─────────────────────────────────────────────────
      Text(ar ? '🔄 حركة المخزون' : '🔄 Stock movements', style: UT.h3),
      const SizedBox(height: 6),
      if (history.isEmpty)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(ar ? 'لا توجد حركات بعد.' : 'No movements yet.',
              style: const TextStyle(color: UellowColors.muted, fontSize: 12)),
        )
      else
        for (final h in history) _historyRow(ar, h as Map),
      const SizedBox(height: 24),
    ]);
  }

  Widget _kpi(String label, String value, String uom, Color c, IconData ic) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFECECEC))),
        child: Column(children: [
          Icon(ic, size: 18, color: c),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w900, color: c)),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: UellowColors.muted)),
        ]),
      ),
    );
  }

  Widget _variantRow(bool ar, Map v, String uom) {
    final attrs = (v['attrs'] ?? '').toString();
    final sku = (v['sku'] ?? '').toString();
    final onHand = (v['on_hand'] as num? ?? 0);
    final label = attrs.isNotEmpty ? attrs : (sku.isNotEmpty ? sku : (ar ? 'المنتج' : 'Item'));
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFECECEC))),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
            if (sku.isNotEmpty && attrs.isNotEmpty)
              Text(sku,
                  style: const TextStyle(fontSize: 10, color: UellowColors.muted)),
            Text('${ar ? 'المتبقي' : 'On hand'}: $onHand $uom',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: onHand > 0
                        ? const Color(0xFF059669)
                        : UellowColors.danger)),
          ]),
        ),
        OutlinedButton.icon(
          onPressed: () => _openAdjust(v),
          style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF412402),
              side: const BorderSide(color: Color(0xFF412402)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10))),
          icon: const Icon(Icons.edit_rounded, size: 15),
          label: Text(ar ? 'تعديل' : 'Set',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
        ),
      ]),
    );
  }

  Widget _adjustRow(bool ar, Map a) {
    final before = a['before'], after = a['after'], delta = a['delta'];
    final up = (delta as num? ?? 0) >= 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFECECEC))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(up ? Icons.trending_up_rounded : Icons.trending_down_rounded,
              size: 16,
              color: up ? const Color(0xFF059669) : UellowColors.danger),
          const SizedBox(width: 6),
          Text('$before → $after  (${up ? '+' : ''}$delta)',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
          const Spacer(),
          Text('${a['date'] ?? ''}',
              style: const TextStyle(fontSize: 9.5, color: UellowColors.muted)),
        ]),
        const SizedBox(height: 3),
        Text('${ar ? 'السبب' : 'Reason'}: ${a['reason'] ?? ''}',
            style: const TextStyle(fontSize: 11.5)),
        Text('${ar ? 'بواسطة' : 'By'}: ${a['by'] ?? ''}',
            style: const TextStyle(fontSize: 10, color: UellowColors.muted)),
      ]),
    );
  }

  Widget _historyRow(bool ar, Map h) {
    final dir = (h['direction'] ?? '').toString();
    final isIn = dir == 'in';
    final qty = (h['qty'] as num? ?? 0);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFECECEC))),
      child: Row(children: [
        Container(
          width: 30, height: 30,
          decoration: BoxDecoration(
              color: (isIn ? const Color(0xFF2563EB) : const Color(0xFFDB2777))
                  .withValues(alpha: .12),
              shape: BoxShape.circle),
          child: Icon(isIn ? Icons.south_west_rounded : Icons.north_east_rounded,
              size: 16,
              color: isIn ? const Color(0xFF2563EB) : const Color(0xFFDB2777)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${h['ref'] ?? ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            Text([
              if ((h['partner'] ?? '').toString().isNotEmpty) h['partner'],
              h['date'] ?? '',
            ].where((e) => (e ?? '').toString().isNotEmpty).join(' · '),
                style: const TextStyle(fontSize: 10, color: UellowColors.muted)),
          ]),
        ),
        Text('${qty > 0 ? '+' : ''}$qty',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: isIn ? const Color(0xFF2563EB) : const Color(0xFFDB2777))),
      ]),
    );
  }

  Future<void> _openAdjust(Map v) async {
    final ar = _ar;
    final qtyCtl = TextEditingController(text: '${v['on_hand'] ?? 0}');
    final reasonCtl = TextEditingController();
    final vid = (v['id'] as num).toInt();
    bool saving = false;
    String? err;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        return Padding(
          padding: EdgeInsets.only(
              left: 16, right: 16, top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(ar ? 'ضبط كمية المخزون' : 'Set stock quantity',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text((v['attrs'] ?? v['sku'] ?? '').toString(),
                style: const TextStyle(fontSize: 11, color: UellowColors.muted)),
            const SizedBox(height: 14),
            TextField(
              controller: qtyCtl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: ar ? 'الكمية الجديدة' : 'New quantity',
                prefixIcon: const Icon(Icons.inventory_2_outlined),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: reasonCtl,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: ar ? 'السبب (مطلوب)' : 'Reason (required)',
                hintText: ar
                    ? 'مثال: جرد فعلي، تالف، تسوية…'
                    : 'e.g. physical count, damaged, correction…',
                alignLabelWithHint: true,
                prefixIcon: const Icon(Icons.edit_note_rounded),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            if (err != null) ...[
              const SizedBox(height: 8),
              Text(err!,
                  style: TextStyle(color: UellowColors.danger, fontSize: 12)),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity, height: 46,
              child: ElevatedButton.icon(
                onPressed: saving
                    ? null
                    : () async {
                        final qty = double.tryParse(qtyCtl.text.trim());
                        final reason = reasonCtl.text.trim();
                        if (qty == null) {
                          setSheet(() => err = ar
                              ? 'أدخل كمية صحيحة'
                              : 'Enter a valid quantity');
                          return;
                        }
                        if (reason.isEmpty) {
                          setSheet(() => err = ar
                              ? 'السبب مطلوب'
                              : 'A reason is required');
                          return;
                        }
                        setSheet(() { saving = true; err = null; });
                        try {
                          await AdminApi.instance.stockAdjust(widget.tmplId,
                              qty: qty, reason: reason, variantId: vid);
                          if (ctx.mounted) Navigator.pop(ctx);
                        } catch (e) {
                          setSheet(() {
                            saving = false;
                            err = e.toString().replaceFirst('Exception: ', '');
                          });
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF412402),
                  foregroundColor: UellowColors.yellow,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: saving
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: UellowColors.yellow))
                    : const Icon(Icons.check_rounded, size: 18),
                label: Text(ar ? 'تطبيق الجرد' : 'Apply adjustment',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w900)),
              ),
            ),
          ]),
        );
      }),
    );
    qtyCtl.dispose();
    reasonCtl.dispose();
    await _load(); // refresh ledger after the sheet closes
  }
}
