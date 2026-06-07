// =============================================================================
// showAdminProductSheet (v2.2.10) — the admin-only product dialog.
//
// Opened from the 🛡️ chip over any product card, or from the admin
// Products manager. Shows & edits:
//   sale price · cost (per-variant when variations exist) · on-hand qty
//   continue-selling toggle · barcode (typed OR camera-scanned)
// =============================================================================
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../api/uellow_api.dart';
import '../../services/admin_mode.dart';
import '../../theme/uellow_theme.dart';

Future<void> showAdminProductSheet(BuildContext context, int tmplId) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (_) => _AdminProductSheet(tmplId: tmplId),
  );
}

class _AdminProductSheet extends StatefulWidget {
  const _AdminProductSheet({required this.tmplId});
  final int tmplId;
  @override
  State<_AdminProductSheet> createState() => _AdminProductSheetState();
}

class _AdminProductSheetState extends State<_AdminProductSheet> {
  Map<String, dynamic>? _d;
  bool _loading = true, _saving = false;
  String? _error;

  // edit state
  late final TextEditingController _price = TextEditingController();
  late final TextEditingController _cost = TextEditingController();
  late final TextEditingController _barcode = TextEditingController();
  bool _continueSelling = false;
  final Map<int, TextEditingController> _vCost = {};
  final Map<int, TextEditingController> _vBarcode = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _price.dispose();
    _cost.dispose();
    _barcode.dispose();
    for (final c in _vCost.values) c.dispose();
    for (final c in _vBarcode.values) c.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await AdminApi.instance.productDetail(widget.tmplId);
      _d = d;
      _price.text = '${d['price'] ?? ''}';
      _cost.text = '${d['cost'] ?? ''}';
      _barcode.text = '${d['barcode'] ?? ''}';
      _continueSelling = d['continue_selling'] == true;
      for (final v in (d['variants'] as List? ?? const [])) {
        final id = ((v as Map)['id'] as num).toInt();
        _vCost[id] = TextEditingController(text: '${v['cost'] ?? ''}');
        _vBarcode[id] = TextEditingController(text: '${v['barcode'] ?? ''}');
      }
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final ar = UellowApi.instance.lang == 'ar';
    setState(() => _saving = true);
    try {
      final d = _d!;
      final hasVariants = d['has_variants'] == true;
      final body = <String, dynamic>{
        'id': widget.tmplId,
        'price': double.tryParse(_price.text.trim()),
        'continue_selling': _continueSelling,
        if (!hasVariants) 'cost': double.tryParse(_cost.text.trim()),
        if (!hasVariants) 'barcode': _barcode.text.trim(),
        if (hasVariants) 'variants': [
          for (final v in (d['variants'] as List? ?? const []))
            {
              'id': ((v as Map)['id'] as num).toInt(),
              'cost': double.tryParse(
                  _vCost[(v['id'] as num).toInt()]?.text.trim() ?? ''),
              'barcode':
                  _vBarcode[(v['id'] as num).toInt()]?.text.trim() ?? '',
            }
        ],
      }..removeWhere((_, v) => v == null);
      await AdminApi.instance.productUpdate(body);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: const Color(0xFF10B981),
          content: Text(ar ? '✓ تم حفظ التعديلات' : '✓ Changes saved',
              style: const TextStyle(fontWeight: FontWeight.w800))));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      final msg = e.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: UellowColors.danger,
          content: Text(msg, maxLines: 3,
              style: const TextStyle(fontSize: 12))));
    }
  }

  Future<void> _scan(TextEditingController into) async {
    final code = await Navigator.push<String>(context,
        MaterialPageRoute(builder: (_) => const _BarcodeScanPage()));
    if (code != null && code.isNotEmpty) {
      setState(() => into.text = code);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * .86),
        child: _loading
            ? const SizedBox(height: 220, child: Center(
                child: CircularProgressIndicator(
                    color: UellowColors.darkBrown)))
            : _error != null
                ? SizedBox(height: 200, child: Center(child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(_error!, style: UT.subtitle))))
                : _body(ar),
      )),
    );
  }

  Widget _body(bool ar) {
    final d = _d!;
    final hasVariants = d['has_variants'] == true;
    final variants = (d['variants'] as List?) ?? const [];
    final sym = ((d['currency'] as Map?)?['symbol'] ?? 'KD').toString();
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 40, height: 4,
          margin: const EdgeInsets.only(top: 10, bottom: 8),
          decoration: BoxDecoration(color: UellowColors.border,
              borderRadius: BorderRadius.circular(2))),
      // header
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
        child: Row(children: [
          ClipRRect(borderRadius: BorderRadius.circular(10),
              child: Image.network(d['image']?.toString() ?? '',
                  width: 52, height: 52, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                      width: 52, height: 52,
                      color: UellowColors.border))),
          const SizedBox(width: 11),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.shield_rounded, size: 13,
                  color: Color(0xFFB58A00)),
              const SizedBox(width: 4),
              Text(ar ? 'وضع الإدارة' : 'ADMIN MODE',
                  style: const TextStyle(fontSize: 9,
                      fontWeight: FontWeight.w900, letterSpacing: .8,
                      color: Color(0xFFB58A00))),
            ]),
            const SizedBox(height: 2),
            Text((ar ? d['name_ar'] : d['name'])?.toString().isNotEmpty
                    == true
                    ? (ar ? d['name_ar'] : d['name']).toString()
                    : d['name'].toString(),
                maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w800)),
          ])),
          // on-hand chip
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: ((d['qty'] as num? ?? 0) > 0)
                  ? const Color(0xFF10B981).withValues(alpha: .1)
                  : UellowColors.danger.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(9)),
            child: Column(children: [
              Text('${d['qty'] ?? 0}', style: TextStyle(fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: ((d['qty'] as num? ?? 0) > 0)
                      ? const Color(0xFF059669) : UellowColors.danger)),
              Text(ar ? 'بالمخزون' : 'on hand', style: const TextStyle(
                  fontSize: 8.5, color: UellowColors.muted)),
            ]),
          ),
        ]),
      ),
      const Divider(height: 1),
      // scrollable form
      Flexible(child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Row(children: [
            Expanded(child: _numField(
                ar ? 'سعر البيع ($sym)' : 'Sale price ($sym)', _price,
                icon: Icons.sell_outlined)),
            if (!hasVariants) ...[
              const SizedBox(width: 10),
              Expanded(child: _numField(
                  ar ? 'التكلفة ($sym)' : 'Cost ($sym)', _cost,
                  icon: Icons.payments_outlined)),
            ],
          ]),
          const SizedBox(height: 12),
          // continue selling
          Container(
            padding: const EdgeInsets.fromLTRB(13, 4, 8, 4),
            decoration: BoxDecoration(
                color: const Color(0xFFF7F8FA),
                borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              const Icon(Icons.all_inclusive_rounded, size: 17,
                  color: UellowColors.darkBrown),
              const SizedBox(width: 8),
              Expanded(child: Text(
                  ar ? 'استمر في البيع عند نفاد الكمية'
                     : 'Continue selling when out of stock',
                  style: const TextStyle(fontSize: 12,
                      fontWeight: FontWeight.w700))),
              Switch(value: _continueSelling,
                  activeColor: UellowColors.yellow,
                  activeTrackColor: const Color(0xFF412402),
                  onChanged: (v) =>
                      setState(() => _continueSelling = v)),
            ]),
          ),
          if (!hasVariants) ...[
            const SizedBox(height: 12),
            _barcodeField(ar, _barcode),
          ],
          if (hasVariants) ...[
            const SizedBox(height: 16),
            Text(ar ? '🎨 المتغيرات (${variants.length})'
                    : '🎨 Variants (${variants.length})',
                style: UT.h3),
            const SizedBox(height: 6),
            for (final v in variants) _variantCard(ar, v as Map, sym),
          ],
          const SizedBox(height: 8),
        ]),
      )),
      // save bar
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: SizedBox(width: double.infinity, height: 46,
          child: ElevatedButton.icon(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF412402),
              foregroundColor: UellowColors.yellow,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13)),
            ),
            icon: _saving
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2,
                        color: UellowColors.yellow))
                : const Icon(Icons.save_rounded, size: 18),
            label: Text(ar ? 'حفظ التعديلات' : 'Save changes',
                style: const TextStyle(fontSize: 14,
                    fontWeight: FontWeight.w900)),
          ),
        ),
      ),
    ]);
  }

  Widget _numField(String label, TextEditingController ctl,
      {IconData? icon}) {
    return TextField(
      controller: ctl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 11.5),
        prefixIcon: icon != null ? Icon(icon, size: 17) : null,
        isDense: true,
        filled: true,
        fillColor: const Color(0xFFF7F8FA),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
      ),
    );
  }

  Widget _barcodeField(bool ar, TextEditingController ctl) {
    return Row(children: [
      Expanded(child: TextField(
        controller: ctl,
        style: const TextStyle(fontSize: 13,
            fontWeight: FontWeight.w700, letterSpacing: .5),
        decoration: InputDecoration(
          labelText: ar ? 'الباركود' : 'Barcode',
          labelStyle: const TextStyle(fontSize: 11.5),
          prefixIcon: const Icon(Icons.qr_code_2_rounded, size: 18),
          isDense: true,
          filled: true,
          fillColor: const Color(0xFFF7F8FA),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
        ),
      )),
      const SizedBox(width: 8),
      InkWell(
        onTap: () => _scan(ctl),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 46, height: 46,
          decoration: BoxDecoration(
              color: const Color(0xFF412402),
              borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.qr_code_scanner_rounded,
              color: UellowColors.yellow, size: 21),
        ),
      ),
    ]);
  }

  Widget _variantCard(bool ar, Map v, String sym) {
    final id = (v['id'] as num).toInt();
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.fromLTRB(11, 10, 11, 11),
      decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: const Color(0xFFEDEDED))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        Row(children: [
          ClipRRect(borderRadius: BorderRadius.circular(7),
              child: Image.network(v['image']?.toString() ?? '',
                  width: 30, height: 30, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                      width: 30, height: 30,
                      color: UellowColors.border))),
          const SizedBox(width: 8),
          Expanded(child: Text(
              (v['attrs'] ?? '').toString().isNotEmpty
                  ? v['attrs'].toString()
                  : (v['sku'] ?? '#$id').toString(),
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5,
                  fontWeight: FontWeight.w800))),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
                color: ((v['qty'] as num? ?? 0) > 0)
                    ? const Color(0xFF10B981).withValues(alpha: .1)
                    : UellowColors.danger.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(7)),
            child: Text('${v['qty'] ?? 0} ${ar ? 'قطعة' : 'pcs'}',
                style: TextStyle(fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    color: ((v['qty'] as num? ?? 0) > 0)
                        ? const Color(0xFF059669)
                        : UellowColors.danger)),
          ),
        ]),
        const SizedBox(height: 9),
        Row(children: [
          SizedBox(width: 110, child: _numField(
              ar ? 'التكلفة ($sym)' : 'Cost ($sym)',
              _vCost[id] ?? TextEditingController())),
          const SizedBox(width: 8),
          Expanded(child: TextField(
            controller: _vBarcode[id],
            style: const TextStyle(fontSize: 12,
                fontWeight: FontWeight.w700, letterSpacing: .4),
            decoration: InputDecoration(
              labelText: ar ? 'الباركود' : 'Barcode',
              labelStyle: const TextStyle(fontSize: 10.5),
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              suffixIcon: IconButton(
                icon: const Icon(Icons.qr_code_scanner_rounded, size: 17,
                    color: UellowColors.darkBrown),
                onPressed: () => _scan(
                    _vBarcode[id] ?? TextEditingController()),
              ),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(11),
                  borderSide: BorderSide.none),
            ),
          )),
        ]),
      ]),
    );
  }
}

// ─── camera barcode scanner page ─────────────────────────────────────────
class _BarcodeScanPage extends StatefulWidget {
  const _BarcodeScanPage();
  @override
  State<_BarcodeScanPage> createState() => _BarcodeScanPageState();
}

class _BarcodeScanPageState extends State<_BarcodeScanPage> {
  bool _done = false;
  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(ar ? 'امسح الباركود' : 'Scan barcode',
            style: const TextStyle(fontSize: 15,
                fontWeight: FontWeight.w800)),
      ),
      body: Stack(children: [
        MobileScanner(
          onDetect: (capture) {
            if (_done) return;
            final code = capture.barcodes.isNotEmpty
                ? (capture.barcodes.first.rawValue ?? '') : '';
            if (code.isNotEmpty) {
              _done = true;
              Navigator.pop(context, code);
            }
          },
        ),
        // viewfinder frame
        Center(child: Container(
          width: 250, height: 160,
          decoration: BoxDecoration(
            border: Border.all(color: UellowColors.yellow, width: 2.5),
            borderRadius: BorderRadius.circular(16),
          ),
        )),
        Positioned(left: 0, right: 0, bottom: 40,
            child: Center(child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: .6),
              borderRadius: BorderRadius.circular(999)),
          child: Text(ar ? 'وجّه الكاميرا نحو الباركود'
                        : 'Point the camera at the barcode',
              style: const TextStyle(color: Colors.white, fontSize: 12,
                  fontWeight: FontWeight.w700)),
        ))),
      ]),
    );
  }
}
