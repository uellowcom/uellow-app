// =============================================================================
// AdminPurchaseCreateScreen (v2.2.58) — build a new RFQ (or edit an existing
// draft RFQ's lines) from the admin console: pick a vendor, search & add
// products, tweak qty / price per line, then submit.
// =============================================================================
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../api/uellow_api.dart';
import '../../theme/uellow_theme.dart';
import '../../services/admin_mode.dart';

const _brown = Color(0xFF412402);

class _Line {
  _Line({this.id, required this.productId, required this.name,
      required this.qty, required this.price, this.image = ''});
  final int? id;          // existing PO line id (edit mode), null = new
  final int productId;
  final String name;
  double qty;
  double price;
  final String image;
}

class AdminPurchaseCreateScreen extends StatefulWidget {
  const AdminPurchaseCreateScreen({super.key, this.editPoId,
      this.initVendorId, this.initVendorName, this.initLines});
  // Edit mode: pass the PO id + its vendor + existing lines.
  final int? editPoId;
  final int? initVendorId;
  final String? initVendorName;
  final List<Map<String, dynamic>>? initLines;

  @override
  State<AdminPurchaseCreateScreen> createState() =>
      _AdminPurchaseCreateScreenState();
}

class _AdminPurchaseCreateScreenState
    extends State<AdminPurchaseCreateScreen> {
  int? _vendorId;
  String _vendorName = '';
  final List<_Line> _lines = [];
  final List<int> _removed = []; // ids removed in edit mode
  bool _busy = false;

  bool get _isEdit => widget.editPoId != null;

  @override
  void initState() {
    super.initState();
    _vendorId = widget.initVendorId;
    _vendorName = widget.initVendorName ?? '';
    for (final l in widget.initLines ?? const []) {
      _lines.add(_Line(
        id: (l['id'] as num?)?.toInt(),
        productId: (l['product_id'] as num?)?.toInt() ?? 0,
        name: (l['name'] ?? '').toString(),
        qty: (l['qty'] as num?)?.toDouble() ?? 1,
        price: (l['price_unit'] as num?)?.toDouble() ?? 0,
        image: (l['image'] ?? '').toString(),
      ));
    }
  }

  double get _total =>
      _lines.fold(0.0, (s, l) => s + l.qty * l.price);

  Future<void> _pickVendor(bool ar) async {
    final v = await showModalBottomSheet<Map<String, dynamic>>(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _SearchSheet(kind: 'vendor'),
    );
    if (v != null) {
      setState(() {
        _vendorId = (v['id'] as num).toInt();
        _vendorName = (v['name'] ?? '').toString();
      });
    }
  }

  Future<void> _addProduct(bool ar) async {
    final p = await showModalBottomSheet<Map<String, dynamic>>(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _SearchSheet(kind: 'product'),
    );
    if (p != null) {
      final pid = (p['id'] as num).toInt();
      final existing = _lines.indexWhere((l) => l.productId == pid);
      setState(() {
        if (existing >= 0) {
          _lines[existing].qty += 1;
        } else {
          _lines.add(_Line(
            productId: pid,
            name: (p['name'] ?? '').toString(),
            qty: 1,
            price: (p['cost'] as num?)?.toDouble() ?? 0,
            image: (p['image'] ?? '').toString(),
          ));
        }
      });
    }
  }

  Future<void> _submit(bool ar) async {
    if (_vendorId == null) {
      _snack(ar ? 'اختر المورد أولًا' : 'Pick a vendor first', true);
      return;
    }
    if (_lines.isEmpty) {
      _snack(ar ? 'أضف منتجًا واحدًا على الأقل' : 'Add at least one product',
          true);
      return;
    }
    setState(() => _busy = true);
    try {
      final lineMaps = _lines.map((l) => {
            if (l.id != null) 'id': l.id,
            if (l.id == null) 'product_id': l.productId,
            'qty': l.qty,
            'price_unit': l.price,
          }).toList();
      if (_isEdit) {
        await AdminApi.instance.purchaseUpdateLines(widget.editPoId!, {
          'lines': lineMaps,
          'remove': _removed,
        });
      } else {
        await AdminApi.instance.purchaseCreate({
          'vendor_id': _vendorId,
          'lines': lineMaps,
        });
      }
      if (mounted) {
        _snack(_isEdit
            ? (ar ? 'تم حفظ التعديلات' : 'Changes saved')
            : (ar ? 'تم إنشاء طلب الشراء' : 'RFQ created'), false);
        Navigator.pop(context, true);
      }
    } catch (e) {
      _snack(e.toString().replaceAll('Exception: ', ''), true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String m, bool err) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m),
          backgroundColor: err ? UellowColors.danger : null));

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F5),
      appBar: AppBar(
        backgroundColor: _brown,
        foregroundColor: UellowColors.yellow,
        iconTheme: const IconThemeData(color: UellowColors.yellow),
        title: Text(
            _isEdit ? (ar ? '✏️ تعديل البنود' : '✏️ Edit lines')
                    : (ar ? '🛒 طلب شراء جديد' : '🛒 New RFQ'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900,
                color: UellowColors.yellow)),
      ),
      body: Stack(children: [
        ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 120),
            children: [
          // vendor
          Text(ar ? 'المورد' : 'Vendor', style: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w900,
              color: UellowColors.darkBrown)),
          const SizedBox(height: 6),
          InkWell(
            onTap: _isEdit ? null : () => _pickVendor(ar),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14,
                  vertical: 14),
              decoration: BoxDecoration(color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E5E9))),
              child: Row(children: [
                const Icon(Icons.store_rounded, size: 20, color: _brown),
                const SizedBox(width: 10),
                Expanded(child: Text(
                    _vendorName.isEmpty
                        ? (ar ? 'اختر المورد' : 'Select vendor')
                        : _vendorName,
                    style: TextStyle(fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _vendorName.isEmpty
                            ? UellowColors.muted : UellowColors.darkBrown))),
                if (!_isEdit)
                  const Icon(Icons.chevron_right_rounded,
                      color: UellowColors.muted),
              ]),
            ),
          ),
          const SizedBox(height: 18),
          // lines header
          Row(children: [
            Text(ar ? 'الأصناف' : 'Items', style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w900,
                color: UellowColors.darkBrown)),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _addProduct(ar),
              icon: const Icon(Icons.add_circle_rounded, size: 18),
              label: Text(ar ? 'إضافة منتج' : 'Add product'),
              style: TextButton.styleFrom(foregroundColor: _brown),
            ),
          ]),
          const SizedBox(height: 4),
          if (_lines.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 28),
              alignment: Alignment.center,
              child: Text(ar ? 'لا توجد أصناف بعد' : 'No items yet',
                  style: const TextStyle(color: UellowColors.muted)),
            ),
          for (int i = 0; i < _lines.length; i++) _lineCard(ar, i),
        ]),
        // bottom bar
        Positioned(left: 0, right: 0, bottom: 0, child: Container(
          padding: EdgeInsets.fromLTRB(14, 12, 14,
              12 + MediaQuery.of(context).padding.bottom),
          decoration: const BoxDecoration(color: Colors.white,
              boxShadow: [BoxShadow(color: Color(0x18000000),
                  blurRadius: 12, offset: Offset(0, -3))]),
          child: Row(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(ar ? 'الإجمالي' : 'Total', style: const TextStyle(
                  fontSize: 10.5, color: UellowColors.muted)),
              Text('${_total.toStringAsFixed(3)} KD',
                  style: const TextStyle(fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: UellowColors.darkBrown)),
            ]),
            const Spacer(),
            ElevatedButton(
              onPressed: _busy ? null : () => _submit(ar),
              style: ElevatedButton.styleFrom(
                backgroundColor: _brown, foregroundColor: UellowColors.yellow,
                padding: const EdgeInsets.symmetric(
                    horizontal: 30, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                  _isEdit ? (ar ? 'حفظ' : 'Save')
                          : (ar ? 'إنشاء الطلب' : 'Create RFQ'),
                  style: const TextStyle(fontSize: 14,
                      fontWeight: FontWeight.w900)),
            ),
          ]),
        )),
        if (_busy)
          Positioned.fill(child: Container(
              color: Colors.black.withValues(alpha: .08),
              child: const Center(child: CircularProgressIndicator(
                  color: UellowColors.darkBrown)))),
      ]),
    );
  }

  Widget _lineCard(bool ar, int i) {
    final l = _lines[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.fromLTRB(11, 10, 6, 10),
      decoration: BoxDecoration(color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFECECEC))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(borderRadius: BorderRadius.circular(9),
            child: Image.network(l.image, width: 46, height: 46,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(width: 46,
                    height: 46, color: UellowColors.border))),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Text(l.name, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Row(children: [
            _numField(ar ? 'كمية' : 'Qty', l.qty, (v) {
              setState(() => l.qty = v);
            }),
            const SizedBox(width: 8),
            _numField(ar ? 'سعر' : 'Price', l.price, (v) {
              setState(() => l.price = v);
            }),
            const Spacer(),
            Text((l.qty * l.price).toStringAsFixed(3),
                style: const TextStyle(fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: UellowColors.darkBrown)),
          ]),
        ])),
        IconButton(
          onPressed: () => setState(() {
            if (l.id != null) _removed.add(l.id!);
            _lines.removeAt(i);
          }),
          icon: const Icon(Icons.delete_outline_rounded,
              color: UellowColors.danger, size: 20),
          visualDensity: VisualDensity.compact,
        ),
      ]),
    );
  }

  Widget _numField(String label, double value, ValueChanged<double> onCh) =>
      SizedBox(
        width: 70,
        child: TextFormField(
          initialValue: value == value.roundToDouble()
              ? value.toStringAsFixed(value >= 100 ? 0 : 0)
              : value.toString(),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(fontSize: 10),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
          onChanged: (s) {
            final v = double.tryParse(s.trim());
            if (v != null && v >= 0) onCh(v);
          },
        ),
      );
}

// ─── reusable search sheet (vendor | product) ────────────────────────────
class _SearchSheet extends StatefulWidget {
  const _SearchSheet({required this.kind});
  final String kind; // 'vendor' | 'product'
  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  final _ctl = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _rows = [];
  bool _loading = false;

  bool get _isVendor => widget.kind == 'vendor';

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _ctl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _search(String q) async {
    setState(() => _loading = true);
    try {
      _rows = _isVendor
          ? await AdminApi.instance.purchaseVendors(q: q)
          : await AdminApi.instance.purchaseProducts(q: q);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return DraggableScrollableSheet(
      initialChildSize: .8, minChildSize: .5, maxChildSize: .92,
      expand: false,
      builder: (_, sc) => Container(
        decoration: const BoxDecoration(color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
        child: Column(children: [
          const SizedBox(height: 10),
          Container(width: 42, height: 4,
              decoration: BoxDecoration(color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(3))),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: TextField(
              controller: _ctl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: _isVendor
                    ? (ar ? '🔍 ابحث عن مورد' : '🔍 Search vendor')
                    : (ar ? '🔍 ابحث عن منتج' : '🔍 Search product'),
                isDense: true,
                filled: true, fillColor: const Color(0xFFF2F3F5),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
              onChanged: (v) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 400),
                    () => _search(v.trim()));
              },
            ),
          ),
          Expanded(child: _loading
              ? const Center(child: CircularProgressIndicator(
                  color: UellowColors.darkBrown))
              : ListView.builder(
                  controller: sc,
                  itemCount: _rows.length,
                  itemBuilder: (_, i) {
                    final r = _rows[i];
                    return ListTile(
                      leading: _isVendor
                          ? const Icon(Icons.store_rounded, color: _brown)
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(7),
                              child: Image.network(
                                  (r['image'] ?? '').toString(),
                                  width: 40, height: 40, fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                      width: 40, height: 40,
                                      color: UellowColors.border))),
                      title: Text((r['name'] ?? '').toString(),
                          maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5,
                              fontWeight: FontWeight.w700)),
                      subtitle: _isVendor
                          ? Text([r['phone'], r['city']]
                              .where((e) => (e ?? '').toString().isNotEmpty)
                              .join(' · '),
                              style: const TextStyle(fontSize: 10.5))
                          : Text(ar
                              ? 'تكلفة ${r['cost']} · ${r['code'] ?? ''}'
                              : 'cost ${r['cost']} · ${r['code'] ?? ''}',
                              style: const TextStyle(fontSize: 10.5)),
                      onTap: () => Navigator.pop(context, r),
                    );
                  },
                )),
        ]),
      ),
    );
  }
}
