// =============================================================================
// showAdminProductSheet (v2.2.10) — the admin-only product dialog.
//
// Opened from the 🛡️ chip over any product card, or from the admin
// Products manager. Shows & edits:
//   sale price · cost (per-variant when variations exist) · on-hand qty
//   continue-selling toggle · barcode (typed OR camera-scanned)
// =============================================================================
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../api/uellow_api.dart';
import '../../services/admin_mode.dart';
import '../../theme/uellow_theme.dart';
import 'admin_stock_screen.dart';

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
  // v2.2.141 — توجل «منشور» + «إظهار في البوس» + سعر لكل لون
  bool _published = true;
  bool _availableInPos = true;
  final Map<int, TextEditingController> _vCost = {};
  final Map<int, TextEditingController> _vBarcode = {};
  final Map<int, TextEditingController> _vPrice = {};
  // v2.2.148 — إدارة الصور (رئيسية + كتالوج)
  String? _mainImg;
  List<Map<String, dynamic>> _catalog = [];
  bool _imgBusy = false;
  // v2.2.41 — eCommerce category (section) editing
  List<Map<String, dynamic>> _cats = [];
  final Set<int> _selCats = {};
  final Map<int, String> _catNames = {};

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
    for (final c in _vPrice.values) c.dispose();
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
      _published = d['published'] != false;
      _availableInPos = d['available_in_pos'] != false;
      _mainImg = (d['image'] as String?);
      _catalog = ((d['catalog_images'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
      for (final v in (d['variants'] as List? ?? const [])) {
        final id = ((v as Map)['id'] as num).toInt();
        _vCost[id] = TextEditingController(text: '${v['cost'] ?? ''}');
        _vBarcode[id] = TextEditingController(text: '${v['barcode'] ?? ''}');
        _vPrice[id] = TextEditingController(text: '${v['price'] ?? ''}');
      }
      for (final c in (d['eco_categories'] as List? ?? const [])) {
        final id = ((c as Map)['id'] as num).toInt();
        _selCats.add(id);
        _catNames[id] = (c['name'] ?? '').toString();
      }
      try {
        _cats = await AdminApi.instance.categories();
        for (final c in _cats) {
          _catNames[(c['id'] as num).toInt()] = (c['name'] ?? '').toString();
        }
      } catch (_) {}
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
        // v2.2.141 — توجل منشور + إظهار في البوس
        'is_published': _published,
        'available_in_pos': _availableInPos,
        if (!hasVariants) 'cost': double.tryParse(_cost.text.trim()),
        if (!hasVariants) 'barcode': _barcode.text.trim(),
        'public_categ_ids': _selCats.toList(),
        if (hasVariants) 'variants': [
          for (final v in (d['variants'] as List? ?? const []))
            {
              'id': ((v as Map)['id'] as num).toInt(),
              'cost': double.tryParse(
                  _vCost[(v['id'] as num).toInt()]?.text.trim() ?? ''),
              // v2.2.141 — سعر لكل لون (يُكتب عبر price_extra بالباك-اند)
              'price': double.tryParse(
                  _vPrice[(v['id'] as num).toInt()]?.text.trim() ?? ''),
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
          // v2.2.148 — إدارة الصور (رئيسية + كتالوج)
          _imageSection(ar),
          const SizedBox(height: 14),
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
          const SizedBox(height: 10),
          // v2.2.141 — توجل منشور على الموقع/التطبيق
          _toggleRow(Icons.public_rounded,
              ar ? 'منشور على الموقع/التطبيق' : 'Published on web/app',
              _published, (v) => setState(() => _published = v)),
          const SizedBox(height: 10),
          // v2.2.141 — توجل الإظهار في نقاط البيع (POS)
          _toggleRow(Icons.point_of_sale_rounded,
              ar ? 'إظهاره في نقاط البيع (POS)' : 'Available in POS',
              _availableInPos, (v) => setState(() => _availableInPos = v)),
          const SizedBox(height: 12),
          _stockButton(ar),
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
          const SizedBox(height: 16),
          _categorySection(ar),
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

  // v2.2.60 — open the full inventory ledger + adjustment screen.
  Widget _stockButton(bool ar) {
    final qty = _d?['qty'] as num? ?? 0;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final name = (ar ? _d!['name_ar'] : _d!['name'])?.toString();
        await Navigator.push(context, MaterialPageRoute(
            builder: (_) => AdminStockScreen(
                tmplId: widget.tmplId, title: name)));
        // refresh the sheet's on-hand chip in case it changed
        if (mounted) _load();
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(13, 12, 10, 12),
        decoration: BoxDecoration(
            color: const Color(0xFFF7F8FA),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFECECEC))),
        child: Row(children: [
          const Icon(Icons.inventory_2_outlined, size: 18,
              color: UellowColors.darkBrown),
          const SizedBox(width: 8),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(ar ? 'المخزون والحركة' : 'Stock & ledger',
                style: const TextStyle(fontSize: 12.5,
                    fontWeight: FontWeight.w800)),
            Text(
                ar ? 'تعديل الكمية • مشتريات • مبيعات • سجل'
                   : 'Adjust qty • purchases • sales • history',
                style: const TextStyle(fontSize: 10,
                    color: UellowColors.muted)),
          ])),
          Text('$qty',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900,
                  color: qty > 0
                      ? const Color(0xFF059669) : UellowColors.danger)),
          const Icon(Icons.chevron_right_rounded,
              color: UellowColors.muted),
        ]),
      ),
    );
  }

  Widget _categorySection(bool ar) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(ar ? '🗂️ قسم المتجر (eCommerce)' : '🗂️ Store section (eCommerce)',
            style: UT.h3),
        const Spacer(),
        TextButton.icon(
          onPressed: _cats.isEmpty ? null : () => _openCatPicker(ar),
          icon: const Icon(Icons.edit_outlined, size: 16),
          label: Text(ar ? 'تعديل' : 'Edit'),
          style: TextButton.styleFrom(
              foregroundColor: UellowColors.darkBrown),
        ),
      ]),
      const SizedBox(height: 4),
      if (_selCats.isEmpty)
        Text(ar ? 'لا يوجد قسم محدد' : 'No section selected',
            style: UT.subtitle)
      else
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final id in _selCats)
            Chip(
              label: Text(_catNames[id] ?? '#$id',
                  style: const TextStyle(fontSize: 11,
                      fontWeight: FontWeight.w700)),
              backgroundColor: UellowColors.yellow.withValues(alpha: .2),
              side: BorderSide.none,
              visualDensity: VisualDensity.compact,
              onDeleted: () => setState(() => _selCats.remove(id)),
            ),
        ]),
    ]);
  }

  Future<void> _openCatPicker(bool ar) async {
    final q = TextEditingController();
    await showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius:
          BorderRadius.vertical(top: Radius.circular(18))),
      builder: (c) => StatefulBuilder(builder: (c, setSt) {
        final term = q.text.trim().toLowerCase();
        final list = term.isEmpty ? _cats : _cats.where((e) =>
            (e['name'] ?? '').toString().toLowerCase().contains(term)).toList();
        return Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(c).viewInsets.bottom),
          child: SizedBox(
            height: MediaQuery.of(c).size.height * .7,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: TextField(
                  controller: q,
                  onChanged: (_) => setSt(() {}),
                  decoration: InputDecoration(
                    hintText: ar ? '🔍 ابحث عن قسم' : '🔍 Search section',
                    isDense: true, filled: true,
                    fillColor: const Color(0xFFF7F8FA),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                  ),
                ),
              ),
              Expanded(child: ListView.builder(
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final id = (list[i]['id'] as num).toInt();
                  final on = _selCats.contains(id);
                  return CheckboxListTile(
                    dense: true,
                    value: on,
                    activeColor: UellowColors.darkBrown,
                    title: Text(list[i]['name']?.toString() ?? '',
                        style: const TextStyle(fontSize: 12.5)),
                    onChanged: (v) => setSt(() {
                      if (v == true) {
                        _selCats.add(id);
                      } else {
                        _selCats.remove(id);
                      }
                      setState(() {});
                    }),
                  );
                },
              )),
              SafeArea(child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                child: SizedBox(width: double.infinity, child: ElevatedButton(
                  onPressed: () => Navigator.pop(c),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: UellowColors.yellow,
                      foregroundColor: UellowColors.darkBrown,
                      padding: const EdgeInsets.symmetric(vertical: 12)),
                  child: Text(ar ? 'تم' : 'Done',
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                )),
              )),
            ]),
          ),
        );
      }),
    );
  }

  // ── v2.2.148 — إدارة الصور ──────────────────────────────────────────
  String _imgUrl(String raw) =>
      raw.startsWith('http') ? raw : '${UellowApi.instance.baseUrl}$raw';

  Future<ImageSource?> _chooseSource(bool ar) {
    return showModalBottomSheet<ImageSource>(
      context: context,
      builder: (c) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min,
          children: [
        ListTile(
          leading: const Icon(Icons.photo_library_outlined),
          title: Text(ar ? 'من المعرض' : 'From gallery'),
          onTap: () => Navigator.pop(c, ImageSource.gallery),
        ),
        ListTile(
          leading: const Icon(Icons.photo_camera_outlined),
          title: Text(ar ? 'التقاط بالكاميرا' : 'Take a photo'),
          onTap: () => Navigator.pop(c, ImageSource.camera),
        ),
      ])),
    );
  }

  Future<void> _pickImage(String kind, bool ar) async {
    if (_imgBusy) return;
    final src = await _chooseSource(ar);
    if (src == null) return;
    final x = await ImagePicker()
        .pickImage(source: src, imageQuality: 85, maxWidth: 1920);
    if (x == null) return;
    setState(() => _imgBusy = true);
    try {
      final bytes = await File(x.path).readAsBytes();
      final b64 = base64Encode(bytes);
      final r = await AdminApi.instance
          .productSetImage(widget.tmplId, b64, kind);
      final data = (r['data'] as Map?)?.cast<String, dynamic>() ?? {};
      if (kind == 'main') {
        setState(() => _mainImg = (data['image'] as String?) ?? _mainImg);
      } else {
        final id = (data['id'] as num?)?.toInt();
        if (id != null) {
          setState(() => _catalog.add({'id': id, 'image': data['image']}));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: UellowColors.danger));
      }
    } finally {
      if (mounted) setState(() => _imgBusy = false);
    }
  }

  Future<void> _delCatalog(int id, bool ar) async {
    if (_imgBusy) return;
    setState(() => _imgBusy = true);
    try {
      await AdminApi.instance.productDeleteImage(widget.tmplId, id);
      setState(() => _catalog
          .removeWhere((c) => (c['id'] as num?)?.toInt() == id));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: UellowColors.danger));
      }
    } finally {
      if (mounted) setState(() => _imgBusy = false);
    }
  }

  Widget _imageSection(bool ar) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          width: 72, height: 72,
          decoration: BoxDecoration(
            color: const Color(0xFFF1EEE7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE9E1D1)),
          ),
          clipBehavior: Clip.antiAlias,
          child: (_mainImg != null && _mainImg!.isNotEmpty)
              ? CachedNetworkImage(imageUrl: _imgUrl(_mainImg!),
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => const Icon(
                      Icons.image_outlined, color: UellowColors.muted))
              : const Icon(Icons.image_outlined, color: UellowColors.muted),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          OutlinedButton.icon(
            onPressed: _imgBusy ? null : () => _pickImage('main', ar),
            icon: const Icon(Icons.photo_camera_outlined, size: 18),
            label: Text(ar ? 'تغيير الصورة الرئيسية' : 'Change main image'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF412402),
              side: const BorderSide(color: Color(0xFFE8A800)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11)),
            ),
          ),
          Text(ar ? 'من المعرض أو الكاميرا' : 'From gallery or camera',
              style: const TextStyle(fontSize: 10.5, color: UellowColors.muted)),
        ])),
      ]),
      const SizedBox(height: 12),
      Text(ar ? '🗂️ صور الكتالوج (${_catalog.length})'
              : '🗂️ Catalog images (${_catalog.length})',
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900,
              color: UellowColors.darkBrown)),
      const SizedBox(height: 8),
      // v2.2.154 — سحب لإعادة ترتيب الصور (مع زر الإضافة بآخر الصف).
      if (_catalog.length > 1)
        Padding(padding: const EdgeInsets.only(bottom: 4),
          child: Text(ar ? '↔ اسحب لإعادة الترتيب' : '↔ Drag to reorder',
              style: const TextStyle(fontSize: 10,
                  color: UellowColors.muted, fontWeight: FontWeight.w700))),
      SizedBox(height: 66, child: Row(children: [
        Expanded(child: ReorderableListView.builder(
          scrollDirection: Axis.horizontal,
          buildDefaultDragHandles: true,
          itemCount: _catalog.length,
          onReorder: (oldI, newI) {
            setState(() {
              if (newI > oldI) newI -= 1;
              final it = _catalog.removeAt(oldI);
              _catalog.insert(newI, it);
            });
            AdminApi.instance.reorderProductImages(widget.tmplId,
                [for (final c in _catalog) (c['id'] as num).toInt()]);
          },
          itemBuilder: (ctx, i) {
            final c = _catalog[i];
            return Padding(
              key: ValueKey(c['id']),
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: Stack(clipBehavior: Clip.none, children: [
                Container(
                  width: 62, height: 62,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1EEE7),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE9E1D1)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: CachedNetworkImage(
                      imageUrl: _imgUrl((c['image'] ?? '').toString()),
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => const Icon(
                          Icons.image_outlined, size: 18,
                          color: UellowColors.muted)),
                ),
                PositionedDirectional(
                  top: -6, start: -6,
                  child: GestureDetector(
                    onTap: _imgBusy
                        ? null
                        : () => _delCatalog((c['id'] as num).toInt(), ar),
                    child: Container(
                      width: 20, height: 20,
                      decoration: BoxDecoration(
                        color: UellowColors.danger, shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: const Icon(Icons.close, size: 12,
                          color: Colors.white),
                    ),
                  ),
                ),
              ]),
            );
          },
        )),
        GestureDetector(
          onTap: _imgBusy ? null : () => _pickImage('catalog', ar),
          child: Container(
            width: 62, height: 62,
            decoration: BoxDecoration(
              color: const Color(0xFFFDF3D6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE8A800)),
            ),
            child: const Icon(Icons.add, size: 26, color: Color(0xFFB58A00)),
          ),
        ),
      ])),
      if (_imgBusy) const Padding(
        padding: EdgeInsets.only(top: 8),
        child: LinearProgressIndicator(minHeight: 2),
      ),
    ]);
  }

  // v2.2.141 — صفّ توجل عام (أيقونة + عنوان + Switch) بنفس ستايل البطاقة.
  Widget _toggleRow(IconData icon, String label, bool value,
      ValueChanged<bool> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
          color: const Color(0xFFF7F8FA),
          borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Icon(icon, size: 17, color: UellowColors.darkBrown),
        const SizedBox(width: 8),
        Expanded(child: Text(label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
        Switch(value: value,
            activeColor: UellowColors.yellow,
            activeTrackColor: const Color(0xFF412402),
            onChanged: onChanged),
      ]),
    );
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
          // v2.2.141 — تكلفة وسعر لكل لون
          SizedBox(width: 92, child: _numField(
              ar ? 'التكلفة ($sym)' : 'Cost ($sym)',
              _vCost[id] ?? TextEditingController())),
          const SizedBox(width: 8),
          SizedBox(width: 92, child: _numField(
              ar ? 'البيع ($sym)' : 'Sell ($sym)',
              _vPrice[id] ?? TextEditingController())),
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
