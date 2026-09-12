// =============================================================================
// AdminProductCreateScreen (v2.2.118) — create a new product from the app
// admin console with the FULL backend field set: names (EN/AR), image, price,
// cost, SKU, barcode (+scan), kind (storable/consumable/service), internal +
// eCommerce categories, customer taxes, unit of measure, sales/internal
// descriptions, weight/volume/HS-code, invoice policy, tracking, flags
// (sale/purchase/continue-selling/publish), an optional vendor and an optional
// initial on-hand quantity. Backed by POST /api/mobile/v2/admin/product/create
// (metadata from /admin/product/meta).
// =============================================================================
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../api/uellow_api.dart';
import '../../services/admin_mode.dart';

const _espresso = Color(0xFF412402);
const _gold = Color(0xFFF5C320);
const _fieldBg = Color(0xFFF7F8FA);

class AdminProductCreateScreen extends StatefulWidget {
  const AdminProductCreateScreen({super.key});
  @override
  State<AdminProductCreateScreen> createState() =>
      _AdminProductCreateScreenState();
}

class _AdminProductCreateScreenState extends State<AdminProductCreateScreen> {
  // text controllers
  final _nameEn = TextEditingController();
  final _nameAr = TextEditingController();
  final _price = TextEditingController();
  final _cost = TextEditingController();
  final _sku = TextEditingController();
  final _barcode = TextEditingController();
  final _descSale = TextEditingController();
  final _descNote = TextEditingController();
  final _weight = TextEditingController();
  final _volume = TextEditingController();
  final _hsCode = TextEditingController();
  final _initQty = TextEditingController();
  final _vendorPrice = TextEditingController();
  final _vendorMinQty = TextEditingController();

  // selections
  String _kind = 'storable'; // storable | consumable | service
  String _invoicePolicy = 'order'; // order | delivery
  String _tracking = 'none'; // none | lot | serial
  int? _categId;
  int? _uomId;
  final Set<int> _selEco = {};
  final Set<int> _selTaxes = {};
  bool _saleOk = true, _purchaseOk = true;
  bool _continueSelling = false, _isPublished = false;

  int? _vendorId;
  String? _vendorName;

  Uint8List? _imageBytes;
  String? _imageB64;

  // meta
  List<Map<String, dynamic>> _uoms = const [];
  List<Map<String, dynamic>> _taxes = const [];
  List<Map<String, dynamic>> _cats = const [];
  List<Map<String, dynamic>> _eco = const [];
  final Map<int, String> _ecoNames = {};
  final Map<int, String> _taxNames = {};
  String _sym = 'KD';

  bool _loading = true, _saving = false;
  String? _err;

  bool get _storable => _kind == 'storable';

  @override
  void initState() {
    super.initState();
    _loadMeta();
  }

  @override
  void dispose() {
    for (final c in [
      _nameEn, _nameAr, _price, _cost, _sku, _barcode, _descSale, _descNote,
      _weight, _volume, _hsCode, _initQty, _vendorPrice, _vendorMinQty,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadMeta() async {
    setState(() { _loading = true; _err = null; });
    try {
      final m = await AdminApi.instance.productMeta();
      _uoms = ((m['uoms'] as List?) ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>()).toList();
      _taxes = ((m['taxes'] as List?) ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>()).toList();
      _cats = ((m['categories'] as List?) ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>()).toList();
      _eco = ((m['eco_categories'] as List?) ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>()).toList();
      for (final c in _eco) {
        _ecoNames[(c['id'] as num).toInt()] = c['name']?.toString() ?? '';
      }
      for (final t in _taxes) {
        _taxNames[(t['id'] as num).toInt()] = t['name']?.toString() ?? '';
      }
      final defs = (m['defaults'] as Map?)?.cast<String, dynamic>() ?? const {};
      _uomId = (defs['uom_id'] as num?)?.toInt();
      _categId = (defs['categ_id'] as num?)?.toInt();
      _invoicePolicy = (defs['invoice_policy'] ?? 'order').toString();
      _tracking = (defs['tracking'] ?? 'none').toString();
      _kind = (defs['kind'] ?? 'storable').toString();
      _saleOk = defs['sale_ok'] != false;
      _purchaseOk = defs['purchase_ok'] != false;
      _continueSelling = defs['continue_selling'] == true;
      _isPublished = defs['is_published'] == true;
      _sym = ((m['currency'] as Map?)?['symbol'] ?? 'KD').toString();
    } catch (e) {
      _err = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pickImage(bool ar) async {
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(ar ? 'من المعرض' : 'Gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery)),
          ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(ar ? 'كاميرا' : 'Camera'),
              onTap: () => Navigator.pop(context, ImageSource.camera)),
        ]),
      ),
    );
    if (src == null) return;
    try {
      final x = await ImagePicker()
          .pickImage(source: src, maxWidth: 1600, imageQuality: 88);
      if (x == null) return;
      final b = await x.readAsBytes();
      setState(() {
        _imageBytes = b;
        _imageB64 = base64Encode(b);
      });
    } catch (e) {
      _toast('${ar ? 'تعذّر اختيار الصورة' : 'Could not pick image'}: $e');
    }
  }

  Future<void> _scanBarcode(bool ar) async {
    final code = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const _ScanPage()));
    if (code != null && code.isNotEmpty) {
      setState(() => _barcode.text = code);
    }
  }

  Future<void> _pickVendor(bool ar) async {
    final v = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _VendorPicker(ar: ar));
    if (v != null) {
      setState(() {
        _vendorId = (v['id'] as num).toInt();
        _vendorName = v['name']?.toString();
      });
    }
  }

  Future<void> _save(bool ar) async {
    if (_nameEn.text.trim().isEmpty) {
      _toast(ar ? 'الاسم (EN) مطلوب' : 'Name (EN) is required');
      return;
    }
    setState(() => _saving = true);
    try {
      final body = <String, dynamic>{
        'name': _nameEn.text.trim(),
        if (_nameAr.text.trim().isNotEmpty) 'name_ar': _nameAr.text.trim(),
        'kind': _kind,
        'sale_ok': _saleOk,
        'purchase_ok': _purchaseOk,
        'price': double.tryParse(_price.text.trim()) ?? 0,
        if (_cost.text.trim().isNotEmpty)
          'cost': double.tryParse(_cost.text.trim()),
        if (_sku.text.trim().isNotEmpty) 'default_code': _sku.text.trim(),
        if (_barcode.text.trim().isNotEmpty) 'barcode': _barcode.text.trim(),
        if (_categId != null) 'categ_id': _categId,
        if (_selEco.isNotEmpty) 'public_categ_ids': _selEco.toList(),
        'taxes_id': _selTaxes.toList(),
        if (_uomId != null) 'uom_id': _uomId,
        if (_descSale.text.trim().isNotEmpty)
          'description_sale': _descSale.text.trim(),
        if (_descNote.text.trim().isNotEmpty)
          'description': _descNote.text.trim(),
        if (_weight.text.trim().isNotEmpty)
          'weight': double.tryParse(_weight.text.trim()),
        if (_volume.text.trim().isNotEmpty)
          'volume': double.tryParse(_volume.text.trim()),
        if (_hsCode.text.trim().isNotEmpty) 'hs_code': _hsCode.text.trim(),
        'invoice_policy': _invoicePolicy,
        if (_storable) 'tracking': _tracking,
        'continue_selling': _continueSelling,
        'is_published': _isPublished,
        if (_imageB64 != null) 'image': _imageB64,
        if (_storable && _initQty.text.trim().isNotEmpty)
          'init_qty': double.tryParse(_initQty.text.trim()),
        if (_vendorId != null)
          'vendor': {
            'partner_id': _vendorId,
            if (_vendorPrice.text.trim().isNotEmpty)
              'price': double.tryParse(_vendorPrice.text.trim()),
            if (_vendorMinQty.text.trim().isNotEmpty)
              'min_qty': double.tryParse(_vendorMinQty.text.trim()),
          },
      };
      final r = await AdminApi.instance.productCreate(body);
      if (!mounted) return;
      _toast(ar
          ? '✅ تم إنشاء المنتج: ${r['name'] ?? ''}'
          : '✅ Product created: ${r['name'] ?? ''}');
      Navigator.of(context).pop(true);
    } catch (e) {
      _toast('${ar ? 'فشل الإنشاء' : 'Create failed'}: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F4F6),
        appBar: AppBar(
          backgroundColor: _espresso,
          foregroundColor: Colors.white,
          title: Text(ar ? '➕ منتج جديد' : '➕ New product',
              style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _err != null
                ? _errView(ar)
                : _form(ar),
        bottomNavigationBar: _loading || _err != null
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                  child: SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _saving ? null : () => _save(ar),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: _espresso,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14))),
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.check_circle_outline),
                      label: Text(ar ? 'حفظ المنتج' : 'Save product',
                          style: const TextStyle(
                              fontSize: 15.5, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _errView(bool ar) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, size: 40, color: Colors.redAccent),
            const SizedBox(height: 10),
            Text(_err ?? '', textAlign: TextAlign.center),
            const SizedBox(height: 14),
            OutlinedButton(
                onPressed: _loadMeta,
                child: Text(ar ? 'إعادة المحاولة' : 'Retry')),
          ]),
        ),
      );

  Widget _form(bool ar) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      children: [
        // ── image + names ──
        _section(ar ? 'الأساسيات' : 'Basics', [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _imagePickerBox(ar),
            const SizedBox(width: 12),
            Expanded(
              child: Column(children: [
                _text(_nameEn, ar ? 'الاسم (EN) *' : 'Name (EN) *'),
                const SizedBox(height: 10),
                _text(_nameAr, ar ? 'الاسم (AR)' : 'Name (AR)'),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          _kindSelector(ar),
        ]),

        // ── pricing ──
        _section(ar ? 'التسعير' : 'Pricing', [
          Row(children: [
            Expanded(
                child: _num(_price, ar ? 'سعر البيع ($_sym)' : 'Sale price ($_sym)')),
            const SizedBox(width: 10),
            Expanded(
                child: _num(_cost, ar ? 'التكلفة ($_sym)' : 'Cost ($_sym)')),
          ]),
        ]),

        // ── identifiers ──
        _section(ar ? 'المُعرّفات' : 'Identifiers', [
          _text(_sku, ar ? 'الرمز الداخلي (SKU)' : 'Internal Reference (SKU)'),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _text(_barcode, ar ? 'الباركود' : 'Barcode')),
            const SizedBox(width: 8),
            Material(
              color: _espresso,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _scanBarcode(ar),
                child: const Padding(
                    padding: EdgeInsets.all(13),
                    child: Icon(Icons.qr_code_scanner,
                        color: Colors.white, size: 22)),
              ),
            ),
          ]),
        ]),

        // ── categories ──
        _section(ar ? 'التصنيف' : 'Categories', [
          _dropdown<int>(
            label: ar ? 'القسم الداخلي' : 'Product Category',
            value: _categId,
            items: _cats
                .map((c) => DropdownMenuItem<int>(
                    value: (c['id'] as num).toInt(),
                    child: Text(c['name']?.toString() ?? '',
                        overflow: TextOverflow.ellipsis)))
                .toList(),
            onChanged: (v) => setState(() => _categId = v),
          ),
          const SizedBox(height: 10),
          _multiChips(
            ar ? 'أقسام المتجر (eCommerce)' : 'eCommerce sections',
            _selEco,
            _ecoNames,
            () => _openMultiPicker(ar,
                title: ar ? 'أقسام المتجر' : 'eCommerce sections',
                items: _eco,
                selected: _selEco),
          ),
        ]),

        // ── taxes + units ──
        _section(ar ? 'الضرائب والوحدات' : 'Taxes & Units', [
          _multiChips(
            ar ? 'ضرائب البيع' : 'Customer taxes',
            _selTaxes,
            _taxNames,
            () => _openMultiPicker(ar,
                title: ar ? 'ضرائب البيع' : 'Customer taxes',
                items: _taxes,
                selected: _selTaxes),
          ),
          const SizedBox(height: 10),
          _dropdown<int>(
            label: ar ? 'وحدة القياس' : 'Unit of Measure',
            value: _uomId,
            items: _uoms
                .map((u) => DropdownMenuItem<int>(
                    value: (u['id'] as num).toInt(),
                    child: Text(u['name']?.toString() ?? '',
                        overflow: TextOverflow.ellipsis)))
                .toList(),
            onChanged: (v) => setState(() => _uomId = v),
          ),
        ]),

        // ── descriptions ──
        _section(ar ? 'الأوصاف' : 'Descriptions', [
          _text(_descSale, ar ? 'وصف البيع' : 'Sales Description',
              maxLines: 3),
          const SizedBox(height: 10),
          _text(_descNote, ar ? 'ملاحظات داخلية' : 'Internal Notes',
              maxLines: 2),
        ]),

        // ── logistics ──
        _section(ar ? 'اللوجستيات' : 'Logistics', [
          Row(children: [
            Expanded(child: _num(_weight, ar ? 'الوزن (كجم)' : 'Weight (kg)')),
            const SizedBox(width: 10),
            Expanded(child: _num(_volume, ar ? 'الحجم (م³)' : 'Volume (m³)')),
          ]),
          const SizedBox(height: 10),
          _text(_hsCode, ar ? 'الرمز الجمركي (HS)' : 'HS Code'),
        ]),

        // ── policies ──
        _section(ar ? 'السياسات' : 'Policies', [
          _dropdown<String>(
            label: ar ? 'سياسة الفوترة' : 'Invoicing Policy',
            value: _invoicePolicy,
            items: [
              DropdownMenuItem(
                  value: 'order',
                  child: Text(ar ? 'الكميات المطلوبة' : 'Ordered quantities')),
              DropdownMenuItem(
                  value: 'delivery',
                  child:
                      Text(ar ? 'الكميات المُسلّمة' : 'Delivered quantities')),
            ],
            onChanged: (v) => setState(() => _invoicePolicy = v ?? 'order'),
          ),
          if (_storable) const SizedBox(height: 10),
          if (_storable)
            _dropdown<String>(
              label: ar ? 'التتبّع' : 'Tracking',
              value: _tracking,
              items: [
                DropdownMenuItem(
                    value: 'none', child: Text(ar ? 'بدون' : 'No tracking')),
                DropdownMenuItem(
                    value: 'lot',
                    child: Text(ar ? 'برقم الدفعة' : 'By lots')),
                DropdownMenuItem(
                    value: 'serial',
                    child: Text(ar ? 'برقم تسلسلي' : 'By serial number')),
              ],
              onChanged: (v) => setState(() => _tracking = v ?? 'none'),
            ),
        ]),

        // ── flags ──
        _section(ar ? 'الخيارات' : 'Options', [
          _switch(ar ? 'يمكن بيعه' : 'Can be Sold', _saleOk,
              (v) => setState(() => _saleOk = v)),
          _switch(ar ? 'يمكن شراؤه' : 'Can be Purchased', _purchaseOk,
              (v) => setState(() => _purchaseOk = v)),
          _switch(
              ar ? 'متابعة البيع عند نفاد المخزون' : 'Continue selling when OOS',
              _continueSelling,
              (v) => setState(() => _continueSelling = v)),
          _switch(ar ? 'نشر على الموقع' : 'Publish on website', _isPublished,
              (v) => setState(() => _isPublished = v)),
        ]),

        // ── initial stock (storable only) ──
        if (_storable)
          _section(ar ? 'المخزون الابتدائي' : 'Initial stock', [
            _num(_initQty,
                ar ? 'الكمية المتوفرة الآن' : 'On-hand quantity now'),
          ]),

        // ── vendor (optional) ──
        _section(ar ? 'المورّد (اختياري)' : 'Vendor (optional)', [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _pickVendor(ar),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                  color: _fieldBg, borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                const Icon(Icons.store_outlined, size: 19),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(
                        _vendorName ??
                            (ar ? 'اختر مورّدًا' : 'Choose a vendor'),
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: _vendorName == null
                                ? Colors.black45
                                : Colors.black87))),
                if (_vendorId != null)
                  IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() {
                            _vendorId = null;
                            _vendorName = null;
                          })),
                const Icon(Icons.chevron_right, color: Colors.black38),
              ]),
            ),
          ),
          if (_vendorId != null) ...[
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                  child: _num(_vendorPrice,
                      ar ? 'سعر الشراء ($_sym)' : 'Vendor price ($_sym)')),
              const SizedBox(width: 10),
              Expanded(
                  child: _num(_vendorMinQty,
                      ar ? 'أقل كمية' : 'Min qty')),
            ]),
          ],
        ]),
      ],
    );
  }

  // ── reusable bits ──────────────────────────────────────────────────
  Widget _section(String title, List<Widget> children) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFEDEDED))),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .3,
                      color: _espresso)),
              const SizedBox(height: 12),
              ...children,
            ]),
      );

  Widget _text(TextEditingController c, String label, {int maxLines = 1}) =>
      TextField(
        controller: c,
        maxLines: maxLines,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        decoration: _dec(label),
      );

  Widget _num(TextEditingController c, String label) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
        ],
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        decoration: _dec(label),
      );

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 12),
        isDense: true,
        filled: true,
        fillColor: _fieldBg,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
      );

  Widget _dropdown<T>({
    required String label,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) =>
      DropdownButtonFormField<T>(
        value: value,
        isExpanded: true,
        items: items,
        onChanged: onChanged,
        style: const TextStyle(
            fontSize: 14, fontWeight: FontWeight.w700, color: Colors.black87),
        decoration: _dec(label),
      );

  Widget _switch(String label, bool value, ValueChanged<bool> onChanged) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(children: [
          Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w700))),
          Switch(
              value: value,
              activeColor: _espresso,
              onChanged: onChanged),
        ]),
      );

  Widget _kindSelector(bool ar) {
    final opts = [
      ('storable', ar ? 'سلعة مخزنية' : 'Storable'),
      ('consumable', ar ? 'سلعة' : 'Consumable'),
      ('service', ar ? 'خدمة' : 'Service'),
    ];
    return Row(
      children: [
        for (final o in opts)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => setState(() => _kind = o.$1),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: _kind == o.$1 ? _espresso : _fieldBg,
                      borderRadius: BorderRadius.circular(10)),
                  child: Text(o.$2,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color:
                              _kind == o.$1 ? Colors.white : Colors.black54)),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _imagePickerBox(bool ar) => InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _pickImage(ar),
        child: Container(
          width: 92,
          height: 92,
          decoration: BoxDecoration(
              color: _fieldBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE3E3E3))),
          clipBehavior: Clip.antiAlias,
          child: _imageBytes != null
              ? Image.memory(_imageBytes!, fit: BoxFit.cover)
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.add_a_photo_outlined,
                        color: Colors.black38, size: 26),
                    const SizedBox(height: 4),
                    Text(ar ? 'صورة' : 'Photo',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.black45)),
                  ],
                ),
        ),
      );

  Widget _multiChips(String label, Set<int> selected,
      Map<int, String> names, VoidCallback onEdit) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700))),
        TextButton.icon(
            onPressed: onEdit,
            icon: const Icon(Icons.edit, size: 15),
            label: Text(selected.isEmpty ? '+' : '',
                style: const TextStyle(fontSize: 12))),
      ]),
      if (selected.isEmpty)
        Text(UellowApi.instance.lang == 'ar' ? 'لا شيء' : 'None',
            style: const TextStyle(color: Colors.black38, fontSize: 12))
      else
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final id in selected)
              Chip(
                label: Text(names[id] ?? '#$id',
                    style: const TextStyle(fontSize: 11.5)),
                backgroundColor: _gold.withValues(alpha: .22),
                onDeleted: () => setState(() => selected.remove(id)),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
    ]);
  }

  Future<void> _openMultiPicker(bool ar,
      {required String title,
      required List<Map<String, dynamic>> items,
      required Set<int> selected}) async {
    final q = TextEditingController();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(builder: (ctx, setSt) {
        final term = q.text.trim().toLowerCase();
        final list = term.isEmpty
            ? items
            : items
                .where((e) =>
                    (e['name']?.toString().toLowerCase() ?? '').contains(term))
                .toList();
        return Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * .7,
            child: Column(children: [
              const SizedBox(height: 10),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 15)),
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: q,
                  onChanged: (_) => setSt(() {}),
                  decoration: InputDecoration(
                    hintText: ar ? '🔍 بحث' : '🔍 Search',
                    isDense: true,
                    filled: true,
                    fillColor: _fieldBg,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final id = (list[i]['id'] as num).toInt();
                    final on = selected.contains(id);
                    return CheckboxListTile(
                      value: on,
                      dense: true,
                      activeColor: _espresso,
                      title: Text(list[i]['name']?.toString() ?? '',
                          style: const TextStyle(fontSize: 13.5)),
                      onChanged: (v) => setSt(() {
                        if (v == true) {
                          selected.add(id);
                        } else {
                          selected.remove(id);
                        }
                      }),
                    );
                  },
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
                  child: SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: _espresso,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12))),
                      child: Text(ar ? 'تم' : 'Done',
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        );
      }),
    );
    if (mounted) setState(() {});
  }
}

// ─── vendor picker (reuses /admin/purchase/vendors) ────────────────────
class _VendorPicker extends StatefulWidget {
  const _VendorPicker({required this.ar});
  final bool ar;
  @override
  State<_VendorPicker> createState() => _VendorPickerState();
}

class _VendorPickerState extends State<_VendorPicker> {
  final _q = TextEditingController();
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _rows = await AdminApi.instance.purchaseVendors(q: _q.text.trim());
    } catch (_) {
      _rows = const [];
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final ar = widget.ar;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * .7,
        child: Column(children: [
          const SizedBox(height: 10),
          Text(ar ? 'اختر مورّدًا' : 'Choose a vendor',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _q,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _load(),
              onChanged: (_) => _load(),
              decoration: InputDecoration(
                hintText: ar ? '🔍 اسم / هاتف' : '🔍 name / phone',
                isDense: true,
                filled: true,
                fillColor: _fieldBg,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _rows.length,
                    itemBuilder: (_, i) {
                      final v = _rows[i];
                      return ListTile(
                        leading: const Icon(Icons.store_outlined),
                        title: Text(v['name']?.toString() ?? '',
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text([
                          v['phone']?.toString() ?? '',
                          v['city']?.toString() ?? ''
                        ].where((s) => s.isNotEmpty).join(' · ')),
                        onTap: () => Navigator.pop(context, v),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}

// ─── camera barcode scanner ────────────────────────────────────────────
class _ScanPage extends StatefulWidget {
  const _ScanPage();
  @override
  State<_ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<_ScanPage> {
  bool _done = false;
  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return Scaffold(
      appBar: AppBar(
          backgroundColor: _espresso,
          foregroundColor: Colors.white,
          title: Text(ar ? 'امسح الباركود' : 'Scan barcode')),
      body: MobileScanner(
        onDetect: (capture) {
          if (_done) return;
          final codes = capture.barcodes;
          if (codes.isNotEmpty && (codes.first.rawValue ?? '').isNotEmpty) {
            _done = true;
            Navigator.of(context).pop(codes.first.rawValue);
          }
        },
      ),
    );
  }
}
