// لمّة يلو (Uellow Lamma) — smart bundle for the app.
// Self-contained: state + API (config/quote) + button/bar/sheet widgets.
// Renders from the server /quote response, so it stays decoupled from the app's
// product model — it only needs a productId (int) to add/remove.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../api/uellow_api.dart';

/// Singleton holding the current Lamma and talking to the server engine.
class LammaService {
  LammaService._();
  static final LammaService instance = LammaService._();

  final Set<int> _ids = <int>{};
  String type = 'normal';

  /// Latest server quote (margin-protected price). Widgets listen to rebuild.
  final ValueNotifier<Map<String, dynamic>?> quote =
      ValueNotifier<Map<String, dynamic>?>(null);
  final ValueNotifier<Map<String, dynamic>?> config =
      ValueNotifier<Map<String, dynamic>?>(null);

  bool has(int id) => _ids.contains(id);
  int get count => _ids.length;

  String get _base => UellowApi.instance.baseUrl;
  Map<String, String> get _headers => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'X-Lang': UellowApi.instance.lang,
      };

  Future<void> loadConfig() async {
    try {
      final r = await http.get(
        Uri.parse('$_base/api/mobile/v2/lamma/config'),
        headers: _headers,
      );
      if (r.statusCode == 200) {
        config.value = jsonDecode(r.body) as Map<String, dynamic>;
      }
    } catch (_) {/* silent — feature just stays hidden */}
  }

  Future<void> toggle(int id) async {
    if (_ids.contains(id)) {
      _ids.remove(id);
    } else {
      _ids.add(id);
    }
    await refresh();
  }

  Future<void> remove(int id) async {
    _ids.remove(id);
    await refresh();
  }

  Future<void> setType(String t) async {
    type = (t == 'installment') ? 'installment' : 'normal';
    await refresh();
  }

  void clear() {
    _ids.clear();
    quote.value = null;
  }

  Future<void> refresh() async {
    if (_ids.isEmpty) {
      quote.value = null;
      return;
    }
    try {
      final r = await http.post(
        Uri.parse('$_base/api/mobile/v2/lamma/quote'),
        headers: _headers,
        body: jsonEncode({'product_ids': _ids.toList(), 'type': type}),
      );
      if (r.statusCode == 200) {
        quote.value = jsonDecode(r.body) as Map<String, dynamic>;
      }
    } catch (_) {/* keep last quote */}
  }

  /// Push the Lamma products into the app cart. Discount application on the app
  /// cart is a server follow-up; for now items are added and the deal is shown.
  Future<void> addAllToCart() async {
    for (final id in _ids.toList()) {
      try {
        await UellowApi.instance.cart.add(productId: id, qty: 1);
      } catch (_) {}
    }
  }
}

const _yellow = Color(0xFFFBBF00);
const _orange = Color(0xFFF26A2E);
const _ink = Color(0xFF101828);
bool get _ar => UellowApi.instance.lang == 'ar';

/// The "add to Lamma" button placed next to Add-to-cart on the product page.
class LammaButton extends StatefulWidget {
  const LammaButton({super.key, required this.productId});
  final int productId;
  @override
  State<LammaButton> createState() => _LammaButtonState();
}

class _LammaButtonState extends State<LammaButton> {
  final _s = LammaService.instance;
  @override
  Widget build(BuildContext context) {
    final cfg = _s.config.value;
    if (cfg != null && cfg['enabled'] == false) return const SizedBox.shrink();
    final inBundle = _s.has(widget.productId);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          await _s.toggle(widget.productId);
          if (mounted) setState(() {});
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: inBundle
                ? null
                : const LinearGradient(colors: [_yellow, _orange]),
            color: inBundle ? const Color(0xFF12241B) : null,
            border: inBundle
                ? Border.all(color: const Color(0xFF1C4D34))
                : null,
          ),
          child: Center(
            child: Text(
              inBundle
                  ? (_ar ? '✓ في لمّتك' : '✓ in your Lamma')
                  : (_ar ? '🧺 أضف للّمّة' : '🧺 Add to Lamma'),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: inBundle ? const Color(0xFF4ADE80) : _ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Inline bar shown just above the CTA when the Lamma has items; tap → sheet.
/// Returns an empty box when the Lamma is empty, so it takes no space.
class LammaBar extends StatelessWidget {
  const LammaBar({super.key});
  @override
  Widget build(BuildContext context) {
    final s = LammaService.instance;
    return ValueListenableBuilder<Map<String, dynamic>?>(
      valueListenable: s.quote,
      builder: (context, q, _) {
        if (q == null || (q['n'] ?? 0) == 0) return const SizedBox.shrink();
        final cur = (q['currency'] ?? 'KD').toString();
        final pct = (q['discount_pct'] ?? 0).toDouble();
        final pays = (q['pays'] ?? 0).toDouble();
        final items = (q['items'] as List?) ?? [];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => showLammaSheet(context),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _ink,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF2A3444)),
                ),
                child: Row(children: [
                  _Thumbs(items: items),
                  const SizedBox(width: 8),
                  Expanded(
                    child: RichText(
                      textDirection: _ar ? TextDirection.rtl : TextDirection.ltr,
                      text: TextSpan(
                        style: const TextStyle(fontSize: 12, color: Color(0xFFC3CAD6)),
                        children: [
                          TextSpan(text: _ar ? 'لمّتك · ' : 'Lamma · '),
                          if (pct > 0)
                            TextSpan(
                              text: '${(q['subtotal'] ?? 0).toStringAsFixed(3)} ',
                              style: const TextStyle(color: Color(0xFF8B97A8), decoration: TextDecoration.lineThrough),
                            ),
                          TextSpan(text: '${pays.toStringAsFixed(3)} $cur', style: const TextStyle(color: _yellow, fontWeight: FontWeight.w800)),
                          if (pct > 0) TextSpan(text: '  -${pct.toStringAsFixed(0)}%'),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [_yellow, _orange]),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(_ar ? 'التفاصيل' : 'View',
                        style: const TextStyle(fontWeight: FontWeight.w800, color: _ink, fontSize: 12)),
                  ),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Thumbs extends StatelessWidget {
  const _Thumbs({required this.items});
  final List items;
  @override
  Widget build(BuildContext context) {
    final base = UellowApi.instance.baseUrl;
    final shown = items.take(4).toList();
    return SizedBox(
      width: (shown.length * 19).toDouble() + 9,
      height: 28,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              right: (i * 19).toDouble(),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: Image.network(
                  '$base${shown[i]['image']}',
                  width: 28, height: 28, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(width: 28, height: 28, color: const Color(0xFF333333)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

void showLammaSheet(BuildContext context) {
  final s = LammaService.instance;
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (ctx) => Directionality(
      textDirection: _ar ? TextDirection.rtl : TextDirection.ltr,
      child: ValueListenableBuilder<Map<String, dynamic>?>(
        valueListenable: s.quote,
        builder: (ctx, q, _) {
          if (q == null) return const SizedBox(height: 120);
          final cur = (q['currency'] ?? 'KD').toString();
          final items = (q['items'] as List?) ?? [];
          final base = UellowApi.instance.baseUrl;
          final capped = q['capped'] == true;
          final inst = s.type == 'installment';
          return Padding(
            padding: EdgeInsets.only(left: 16, right: 16, top: 14, bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFFE2E6EC), borderRadius: BorderRadius.circular(9))),
              const SizedBox(height: 12),
              Text(_ar ? 'لمّتك 🧺' : 'Your Lamma 🧺', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: _ink)),
              const SizedBox(height: 10),
              // normal / installment toggle
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(color: const Color(0xFFF1F3F6), borderRadius: BorderRadius.circular(11)),
                child: Row(children: [
                  _seg(ctx, s, 'normal', _ar ? 'عادي' : 'Normal'),
                  _seg(ctx, s, 'installment', _ar ? 'أقساط · +٦.٥٪' : 'Installment · +6.5%'),
                ]),
              ),
              const SizedBox(height: 12),
              ...items.map((it) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network('$base${it['image']}', width: 46, height: 46, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(width: 46, height: 46, color: const Color(0xFFF0F2F5))),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text('${it['name']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _ink))),
                      Text('${(it['price'] as num).toStringAsFixed(3)}', style: const TextStyle(fontWeight: FontWeight.w800, color: _orange)),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () => s.remove(it['id'] as int),
                        child: Container(width: 26, height: 26, alignment: Alignment.center,
                          decoration: BoxDecoration(color: const Color(0xFFFFF0F0), borderRadius: BorderRadius.circular(8)),
                          child: const Text('✕', style: TextStyle(color: Color(0xFFF04438), fontWeight: FontWeight.w800))),
                      ),
                    ]),
                  )),
              if (capped)
                Container(
                  margin: const EdgeInsets.only(top: 8), padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(color: const Color(0xFF12241B), borderRadius: BorderRadius.circular(10)),
                  child: Text(
                    _ar
                        ? '🛡️ الخصم موقوف عند ${(q['discount_pct'] ?? 0).toStringAsFixed(1)}% لحماية هامش الربح (≥ ${q['floor_margin_pct']}%).'
                        : '🛡️ Discount capped at ${(q['discount_pct'] ?? 0).toStringAsFixed(1)}% to protect margin (≥ ${q['floor_margin_pct']}%).',
                    style: const TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.w700, fontSize: 12.5),
                  ),
                ),
              const SizedBox(height: 10),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(inst
                    ? (_ar ? 'على أقساط · ${(q['monthly'] ?? 0).toStringAsFixed(3)} $cur/شهر' : '${(q['monthly'] ?? 0).toStringAsFixed(3)} $cur/mo')
                    : (_ar ? 'وفّرت ${(q['saved'] ?? 0).toStringAsFixed(3)} $cur' : 'Saved ${(q['saved'] ?? 0).toStringAsFixed(3)} $cur'),
                    style: const TextStyle(color: Color(0xFF12B76A), fontWeight: FontWeight.w800)),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  if (((q['discount_pct'] ?? 0) as num) > 0) ...[
                    // price BEFORE discount (strikethrough)
                    Text('${(q['subtotal'] ?? 0).toStringAsFixed(3)}',
                        style: const TextStyle(color: Color(0xFF98A2B3), fontSize: 13, decoration: TextDecoration.lineThrough)),
                    const SizedBox(width: 6),
                  ],
                  // price AFTER discount
                  Text('${(q['pays'] ?? 0).toStringAsFixed(3)} $cur',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: _ink)),
                ]),
              ]),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _orange, foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    await s.addAllToCart();
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                      Navigator.pushNamed(context, '/cart');
                    }
                  },
                  child: Text(_ar ? 'إتمام اللمّة' : 'Checkout Lamma', style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ]),
          );
        },
      ),
    ),
  );
}

Widget _seg(BuildContext ctx, LammaService s, String t, String label) {
  final on = s.type == t;
  return Expanded(
    child: InkWell(
      onTap: () => s.setType(t),
      borderRadius: BorderRadius.circular(9),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: on ? const LinearGradient(colors: [_yellow, _orange]) : null,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: on ? _ink : const Color(0xFF9AA7B8))),
      ),
    ),
  );
}
