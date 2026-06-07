// =============================================================================
// AdminProductsScreen (v2.2.10) — product manager: search the whole
// catalog (name / SKU / barcode), see price·cost·stock at a glance,
// tap any row to open the admin edit sheet.
// =============================================================================
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../api/uellow_api.dart';
import '../../services/admin_mode.dart';
import '../../theme/uellow_theme.dart';
import 'admin_product_sheet.dart';

class AdminProductsScreen extends StatefulWidget {
  const AdminProductsScreen({super.key});
  @override
  State<AdminProductsScreen> createState() => _AdminProductsScreenState();
}

class _AdminProductsScreenState extends State<AdminProductsScreen> {
  final _scroll = ScrollController();
  final _searchCtl = TextEditingController();
  Timer? _debounce;

  final List<Map<String, dynamic>> _rows = [];
  int _page = 1, _pages = 1, _total = 0;
  bool _loading = false;
  String _q = '';

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
      final d = await AdminApi.instance.products(page: _page, q: _q);
      _pages = (d['pages'] as num?)?.toInt() ?? 1;
      _total = (d['total'] as num?)?.toInt() ?? 0;
      _rows.addAll(((d['products'] as List?) ?? const [])
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
        title: Text('${ar ? '📦 إدارة المنتجات' : '📦 Products'}'
            '${_total > 0 ? ' ($_total)' : ''}',
            style: const TextStyle(fontSize: 16,
                fontWeight: FontWeight.w900)),
      ),
      body: Column(children: [
        Container(
          color: const Color(0xFF412402),
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          child: TextField(
            controller: _searchCtl,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: ar ? '🔍 الاسم / SKU / الباركود'
                           : '🔍 Name / SKU / barcode',
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

  Widget _row(bool ar, Map<String, dynamic> p) {
    final qty = (p['qty'] as num?) ?? 0;
    final price = (p['price'] as num?) ?? 0;
    final cost = (p['cost'] as num?) ?? 0;
    final margin = (price > 0 && cost > 0)
        ? ((price - cost) / price * 100) : null;
    return InkWell(
      onTap: () async {
        await showAdminProductSheet(context, (p['id'] as num).toInt());
        _load(reset: true);   // refresh after possible edits
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
        decoration: BoxDecoration(color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFECECEC))),
        child: Row(children: [
          ClipRRect(borderRadius: BorderRadius.circular(10),
              child: Image.network(p['image']?.toString() ?? '',
                  width: 54, height: 54, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                      width: 54, height: 54,
                      color: UellowColors.border))),
          const SizedBox(width: 11),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((ar && (p['name_ar'] ?? '').toString().isNotEmpty
                    ? p['name_ar'] : p['name']).toString(),
                maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.5,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Row(children: [
              Text('${price.toStringAsFixed(3)} KD',
                  style: const TextStyle(fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                      color: UellowColors.darkBrown)),
              const SizedBox(width: 8),
              Text(ar ? 'تكلفة ${cost.toStringAsFixed(3)}'
                      : 'cost ${cost.toStringAsFixed(3)}',
                  style: const TextStyle(fontSize: 9.5,
                      color: UellowColors.muted)),
              if (margin != null) ...[
                const SizedBox(width: 6),
                Text('${margin.toStringAsFixed(0)}%',
                    style: TextStyle(fontSize: 9.5,
                        fontWeight: FontWeight.w900,
                        color: margin > 15
                            ? const Color(0xFF059669)
                            : UellowColors.warn)),
              ],
            ]),
          ])),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                  color: qty > 0
                      ? const Color(0xFF10B981).withValues(alpha: .1)
                      : (p['continue_selling'] == true
                          ? UellowColors.warn.withValues(alpha: .12)
                          : UellowColors.danger.withValues(alpha: .08)),
                  borderRadius: BorderRadius.circular(7)),
              child: Text(qty > 0 ? '$qty'
                  : (p['continue_selling'] == true ? '∞' : '0'),
                  style: TextStyle(fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: qty > 0 ? const Color(0xFF059669)
                          : (p['continue_selling'] == true
                              ? UellowColors.warn : UellowColors.danger))),
            ),
            const SizedBox(height: 3),
            if ((p['variants'] as num? ?? 0) > 1)
              Text('${p['variants']} ${ar ? 'متغير' : 'vars'}',
                  style: const TextStyle(fontSize: 8.5,
                      color: UellowColors.muted)),
          ]),
        ]),
      ),
    );
  }
}
