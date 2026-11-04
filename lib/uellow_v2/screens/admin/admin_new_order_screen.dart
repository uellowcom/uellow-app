// =============================================================================
// AdminNewOrderScreen (v2.2.171) — إنشاء طلب من الكونسول كالباك إند:
// • اختيار عميل حالي (بحث) أو عميل جديد بكل تفاصيله + عنوان منظّم
//   (المحافظة/المدينة/القطعة/الشارع/الجادة/المنزل).
// • بحث المنتجات وإضافتها، ثم حفظ كمسودة أو إنشاء واعتماد.
// Backed by POST /api/mobile/v2/admin/order/create.
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
  // customer
  bool _existing = false; // false = new customer, true = pick existing
  int? _partnerId;
  String _pickedLabel = '';
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  // structured address
  final _block = TextEditingController();
  final _street = TextEditingController();
  final _jadda = TextEditingController();
  final _house = TextEditingController();
  List<Map<String, dynamic>> _govs = [];
  int? _govId;
  int? _cityId;

  // customer search
  final _custSearch = TextEditingController();
  List<Map<String, dynamic>> _custResults = [];
  bool _custSearching = false;
  Timer? _custDebounce;

  // products
  final _search = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _results = [];
  bool _searching = false, _saving = false;
  final List<Map<String, dynamic>> _lines = [];

  @override
  void initState() {
    super.initState();
    _loadAreas();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _block.dispose();
    _street.dispose();
    _jadda.dispose();
    _house.dispose();
    _custSearch.dispose();
    _search.dispose();
    _debounce?.cancel();
    _custDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadAreas() async {
    try {
      final d = await AdminApi.instance.geoAreas();
      _govs = ((d['governorates'] as List?) ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>()).toList();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  List<Map<String, dynamic>> get _cities {
    final g = _govs.firstWhere((e) => e['id'] == _govId,
        orElse: () => const {});
    return ((g['cities'] as List?) ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>()).toList();
  }

  bool get _ar => UellowApi.instance.lang == 'ar';

  Future<void> _custDoSearch(String q) async {
    if (q.trim().length < 2) {
      setState(() => _custResults = []);
      return;
    }
    setState(() => _custSearching = true);
    try {
      _custResults = await AdminApi.instance.customersSearch(q.trim());
    } catch (_) {
      _custResults = [];
    }
    if (mounted) setState(() => _custSearching = false);
  }

  void _pickCustomer(Map<String, dynamic> c) {
    setState(() {
      _partnerId = (c['id'] as num).toInt();
      _pickedLabel = '${c['name'] ?? ''}'
          '${(c['phone'] ?? '').toString().isNotEmpty ? ' · ${c['phone']}' : ''}';
      _custResults = [];
      _custSearch.clear();
    });
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
    final ar = _ar;
    if (_lines.isEmpty) {
      _snack(ar ? 'أضف منتجاً واحداً على الأقل' : 'Add at least one product');
      return;
    }
    if (_existing && _partnerId == null) {
      _snack(ar ? 'اختر عميلاً حالياً' : 'Pick an existing customer');
      return;
    }
    if (!_existing &&
        _name.text.trim().isEmpty && _phone.text.trim().isEmpty) {
      _snack(ar ? 'أدخل اسم أو هاتف العميل'
                : 'Enter a customer name or phone');
      return;
    }
    setState(() => _saving = true);
    try {
      final body = <String, dynamic>{
        'confirm': confirm,
        'lines': [for (final l in _lines)
          {'product_id': l['product_id'], 'qty': l['qty']}],
      };
      if (_existing && _partnerId != null) {
        body['partner_id'] = _partnerId;
      } else {
        body['customer_name'] = _name.text.trim();
        body['customer_phone'] = _phone.text.trim();
        if (_email.text.trim().isNotEmpty) {
          body['customer_email'] = _email.text.trim();
        }
        if (_govId != null) body['gov_id'] = _govId;
        if (_cityId != null) body['city_id'] = _cityId;
        if (_block.text.trim().isNotEmpty) body['block'] = _block.text.trim();
        if (_street.text.trim().isNotEmpty) {
          body['street'] = _street.text.trim();
        }
        if (_jadda.text.trim().isNotEmpty) body['jadda'] = _jadda.text.trim();
        if (_house.text.trim().isNotEmpty) body['house'] = _house.text.trim();
      }
      await AdminApi.instance.orderCreate(body);
      if (mounted) {
        _snack(ar ? 'تم إنشاء الطلب' : 'Order created');
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

  void _snack(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final ar = _ar;
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
          // toggle existing / new
          Row(children: [
            Expanded(child: _segBtn(ar ? 'عميل جديد' : 'New', !_existing,
                () => setState(() => _existing = false))),
            const SizedBox(width: 8),
            Expanded(child: _segBtn(ar ? 'عميل حالي' : 'Existing', _existing,
                () => setState(() => _existing = true))),
          ]),
          const SizedBox(height: 12),
          if (_existing) ..._existingCustomer(ar) else ..._newCustomer(ar),
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

  List<Widget> _existingCustomer(bool ar) => [
        if (_partnerId != null)
          Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(color: const Color(0xFFF1FAF3),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFBBE7C6))),
            child: Row(children: [
              const Icon(Icons.check_circle, color: Color(0xFF16A34A),
                  size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(_pickedLabel, style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w800))),
              IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() {
                        _partnerId = null;
                        _pickedLabel = '';
                      })),
            ]),
          ),
        TextField(
          controller: _custSearch,
          decoration: _dec(ar ? '🔍 ابحث بالاسم/الهاتف/البريد'
                              : '🔍 Search name / phone / email',
              suffix: _custSearching
                  ? const SizedBox(width: 18, height: 18, child:
                      Padding(padding: EdgeInsets.all(2),
                          child: CircularProgressIndicator(strokeWidth: 2)))
                  : null),
          onChanged: (v) {
            _custDebounce?.cancel();
            _custDebounce = Timer(const Duration(milliseconds: 400),
                () => _custDoSearch(v));
          },
        ),
        for (final c in _custResults)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person_outline, size: 22,
                color: UellowColors.darkBrown),
            title: Text((c['name'] ?? '').toString(),
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5,
                    fontWeight: FontWeight.w700)),
            subtitle: Text([
              if ((c['phone'] ?? '').toString().isNotEmpty) c['phone'],
              if ((c['city'] ?? '').toString().isNotEmpty) c['city'],
            ].join(' · '), style: const TextStyle(fontSize: 11)),
            trailing: const Icon(Icons.add_circle_outline,
                color: UellowColors.darkBrown),
            onTap: () => _pickCustomer(c),
          ),
      ];

  List<Widget> _newCustomer(bool ar) => [
        TextField(controller: _name, decoration: _dec(
            ar ? 'اسم العميل' : 'Customer name')),
        const SizedBox(height: 10),
        TextField(controller: _phone, keyboardType: TextInputType.phone,
            decoration: _dec(ar ? 'الهاتف' : 'Phone')),
        const SizedBox(height: 10),
        TextField(controller: _email, keyboardType: TextInputType.emailAddress,
            decoration: _dec(ar ? 'البريد الإلكتروني (اختياري)'
                                : 'Email (optional)')),
        const SizedBox(height: 14),
        Text(ar ? '📍 العنوان' : '📍 Address', style: const TextStyle(
            fontSize: 12, fontWeight: FontWeight.w900,
            color: UellowColors.muted)),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          value: _govId,
          isExpanded: true,
          decoration: _dec(ar ? 'المحافظة' : 'Governorate'),
          items: [for (final g in _govs) DropdownMenuItem<int>(
              value: (g['id'] as num).toInt(),
              child: Text(ar ? (g['name_ar'] ?? g['name'] ?? '').toString()
                             : (g['name'] ?? '').toString(),
                  overflow: TextOverflow.ellipsis))],
          onChanged: (v) => setState(() { _govId = v; _cityId = null; }),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<int>(
          value: _cityId,
          isExpanded: true,
          decoration: _dec(ar ? 'المدينة / المنطقة' : 'City / Area'),
          items: [for (final c in _cities) DropdownMenuItem<int>(
              value: (c['id'] as num).toInt(),
              child: Text(ar ? (c['name_ar'] ?? c['name'] ?? '').toString()
                             : (c['name'] ?? '').toString(),
                  overflow: TextOverflow.ellipsis))],
          onChanged: (v) => setState(() => _cityId = v),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextField(controller: _block,
              decoration: _dec(ar ? 'قطعة' : 'Block'))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: _street,
              decoration: _dec(ar ? 'شارع' : 'Street'))),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextField(controller: _jadda,
              decoration: _dec(ar ? 'جادة' : 'Avenue'))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: _house,
              decoration: _dec(ar ? 'منزل / مبنى' : 'House / Bldg'))),
        ]),
      ];

  Widget _segBtn(String label, bool on, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? UellowColors.darkBrown : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: on
                ? UellowColors.darkBrown : const Color(0xFFE2E2E2)),
          ),
          child: Text(label, style: TextStyle(fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: on ? Colors.white : UellowColors.muted)),
        ),
      );

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
    hintText: hint, labelText: hint, isDense: true, suffixIcon: suffix,
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
