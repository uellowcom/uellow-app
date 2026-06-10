// =============================================================================
// AdminNewOrderScreen (v2.2.41) — create a sale order from the admin console:
// pick/enter a customer, search & add products, then save as a quotation or
// create & confirm. Backed by POST /api/mobile/v2/admin/order/create.
// =============================================================================
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../api/uellow_api.dart';
import '../../services/admin_mode.dart';
import '../../theme/uellow_theme.dart';

class AdminNewOrderScreen extends StatefulWidget {
  const AdminNewOrderScreen({super.key});
  @override
  State<AdminNewOrderScreen> createState() => _AdminNewOrderScreenState();
}

class _AdminNewOrderScreenState extends State<AdminNewOrderScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _search = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _results = [];
  bool _searching = false, _saving = false;

  // line = {product_id, name, price, qty, image}
  final List<Map<String, dynamic>> _lines = [];

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _search.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _doSearch(String q) async {
    if (q.trim().length < 2) {
      setState(() => _results = []);
      return;
    }
    setState(() => _searching = true);
    try {
      final d = await AdminApi.instance.products(q: q.trim());
      _results = ((d['products'] as List?) ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>()).toList();
    } catch (_) {
      _results = [];
    }
    if (mounted) setState(() => _searching = false);
  }

  void _addProduct(Map<String, dynamic> p) {
    final pid = (p['id'] as num).toInt();
    final existing = _lines.indexWhere((l) => l['product_id'] == pid);
    setState(() {
      if (existing >= 0) {
        _lines[existing]['qty'] = (_lines[existing]['qty'] as num) + 1;
      } else {
        _lines.add({
          'product_id': pid,
          'name': p['name'] ?? p['name_ar'] ?? '',
          'price': p['price'] ?? 0,
          'qty': 1,
          'image': p['image'] ?? '',
        });
      }
      _search.clear();
      _results = [];
    });
  }

  double get _total => _lines.fold(0.0, (s, l) =>
      s + ((l['price'] as num? ?? 0) * (l['qty'] as num? ?? 0)));

  Future<void> _save({required bool confirm}) async {
    final ar = UellowApi.instance.lang == 'ar';
    if (_lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ar ? 'أضف منتجاً واحداً على الأقل'
              : 'Add at least one product')));
      return;
    }
    if (_name.text.trim().isEmpty && _phone.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ar ? 'أدخل اسم أو هاتف العميل'
              : 'Enter a customer name or phone')));
      return;
    }
    setState(() => _saving = true);
    try {
      await AdminApi.instance.orderCreate({
        'customer_name': _name.text.trim(),
        'customer_phone': _phone.text.trim(),
        'confirm': confirm,
        'lines': [for (final l in _lines)
          {'product_id': l['product_id'], 'qty': l['qty']}],
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(ar ? 'تم إنشاء الطلب' : 'Order created')));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: UellowColors.danger));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF412402),
        foregroundColor: UellowColors.yellow,
        iconTheme: const IconThemeData(color: UellowColors.yellow),
        title: Text(ar ? 'طلب جديد' : 'New order',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900,
                color: UellowColors.yellow)),
      ),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        _card(ar ? '👤 العميل' : '👤 Customer', [
          TextField(controller: _name, decoration: _dec(
              ar ? 'اسم العميل' : 'Customer name')),
          const SizedBox(height: 10),
          TextField(controller: _phone, keyboardType: TextInputType.phone,
              decoration: _dec(ar ? 'الهاتف' : 'Phone')),
        ]),
        _card(ar ? '🛒 المنتجات' : '🛒 Products', [
          TextField(
            controller: _search,
            decoration: _dec(ar ? '🔍 ابحث لإضافة منتج' : '🔍 Search to add',
                suffix: _searching
                    ? const SizedBox(width: 18, height: 18, child:
                        Padding(padding: EdgeInsets.all(2),
                            child: CircularProgressIndicator(strokeWidth: 2)))
                    : null),
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 400),
                  () => _doSearch(v));
            },
          ),
          for (final p in _results)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: ClipRRect(borderRadius: BorderRadius.circular(6),
                  child: Image.network(p['image']?.toString() ?? '',
                      width: 38, height: 38, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(width: 38,
                          height: 38, color: UellowColors.border))),
              title: Text((p['name'] ?? p['name_ar'] ?? '').toString(),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5,
                      fontWeight: FontWeight.w600)),
              subtitle: Text('${p['price'] ?? 0}',
                  style: const TextStyle(fontSize: 11)),
              trailing: const Icon(Icons.add_circle,
                  color: UellowColors.darkBrown),
              onTap: () => _addProduct(p),
            ),
          if (_lines.isNotEmpty) const Divider(height: 20),
          for (int i = 0; i < _lines.length; i++) _lineRow(i, ar),
          if (_lines.isNotEmpty) ...[
            const Divider(height: 20),
            Row(children: [
              Text(ar ? 'الإجمالي' : 'Total', style: const TextStyle(
                  fontWeight: FontWeight.w900, fontSize: 14)),
              const Spacer(),
              Text(_total.toStringAsFixed(3), style: const TextStyle(
                  fontWeight: FontWeight.w900, fontSize: 15,
                  color: UellowColors.darkBrown)),
            ]),
          ],
        ]),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(child: OutlinedButton(
            onPressed: _saving ? null : () => _save(confirm: false),
            style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 13),
                side: const BorderSide(color: UellowColors.darkBrown)),
            child: Text(ar ? 'حفظ كمسودة' : 'Save quotation',
                style: const TextStyle(fontWeight: FontWeight.w900,
                    color: UellowColors.darkBrown)),
          )),
          const SizedBox(width: 10),
          Expanded(child: ElevatedButton(
            onPressed: _saving ? null : () => _save(confirm: true),
            style: ElevatedButton.styleFrom(
                backgroundColor: UellowColors.yellow,
                foregroundColor: UellowColors.darkBrown,
                padding: const EdgeInsets.symmetric(vertical: 13)),
            child: _saving
                ? const SizedBox(width: 18, height: 18, child:
                    CircularProgressIndicator(strokeWidth: 2,
                        color: UellowColors.darkBrown))
                : Text(ar ? 'إنشاء واعتماد' : 'Create & confirm',
                    style: const TextStyle(fontWeight: FontWeight.w900)),
          )),
        ]),
        const SizedBox(height: 24),
      ]),
    );
  }

  Widget _lineRow(int i, bool ar) {
    final l = _lines[i];
    final qty = (l['qty'] as num).toInt();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(l['name'].toString(), maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
        IconButton(visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.remove_circle_outline, size: 20),
            onPressed: () => setState(() {
              if (qty <= 1) {
                _lines.removeAt(i);
              } else {
                l['qty'] = qty - 1;
              }
            })),
        Text('$qty', style: const TextStyle(fontWeight: FontWeight.w900)),
        IconButton(visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add_circle_outline, size: 20),
            onPressed: () => setState(() => l['qty'] = qty + 1)),
        SizedBox(width: 64, child: Text(
            ((l['price'] as num? ?? 0) * qty).toStringAsFixed(3),
            textAlign: TextAlign.end,
            style: const TextStyle(fontSize: 11.5,
                fontWeight: FontWeight.w800))),
      ]),
    );
  }

  InputDecoration _dec(String hint, {Widget? suffix}) => InputDecoration(
    hintText: hint, isDense: true, suffixIcon: suffix,
    filled: true, fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
  );

  Widget _card(String title, List<Widget> children) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
    decoration: BoxDecoration(color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFECECEC))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: UT.h3),
      const SizedBox(height: 10),
      ...children,
    ]),
  );
}
