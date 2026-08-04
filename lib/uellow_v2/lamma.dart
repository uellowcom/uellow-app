// لمّة يلو (Uellow Lamma) — smart bundle for the app.
// Self-contained: state + API (config/quote) + button/bar/sheet widgets.
// Renders from the server /quote response, so it stays decoupled from the app's
// product model — it only needs a productId (int) to add/remove.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../api/uellow_api.dart';

/// Singleton holding the current Lamma and talking to the server engine.
class LammaService {
  LammaService._();
  static final LammaService instance = LammaService._();

  final Set<int> _ids = <int>{};                 // product (template) ids
  final Map<int, int> _variants = <int, int>{};  // templateId -> chosen variantId
  String type = 'normal';

  /// Latest server quote (margin-protected price). Widgets listen to rebuild.
  final ValueNotifier<Map<String, dynamic>?> quote =
      ValueNotifier<Map<String, dynamic>?>(null);
  final ValueNotifier<Map<String, dynamic>?> config =
      ValueNotifier<Map<String, dynamic>?>(null);

  /// The floating mini-bar is dismissed (X) — session only; a new add re-shows
  /// it, and product pages always show their own inline bar regardless.
  final ValueNotifier<bool> hidden = ValueNotifier<bool>(false);
  /// True while any product screen is on the stack — the global bar yields to
  /// the product page's own inline bar. Depth-counted so nested product→product
  /// navigation stays correct.
  final ValueNotifier<bool> onProductPage = ValueNotifier<bool>(false);
  int _productDepth = 0;
  void enterProduct() { _productDepth++; onProductPage.value = true; }
  void leaveProduct() {
    if (_productDepth > 0) _productDepth--;
    onProductPage.value = _productDepth > 0;
  }

  /// True while the splash screen is up — the floating bar must never paint
  /// over the splash.
  final ValueNotifier<bool> onSplash = ValueNotifier<bool>(false);

  /// Navigator key (set from main) so the floating bar — which lives ABOVE the
  /// Navigator in MaterialApp.builder — can still open the sheet after a cold
  /// start. Without it, tapping the bar found no Navigator and did nothing.
  GlobalKey<NavigatorState>? navKey;
  BuildContext? get _navCtx => navKey?.currentContext;

  bool has(int id) => _ids.contains(id);
  int get count => _ids.length;
  bool _restored = false;

  /// Persist the bundle so it survives app restarts.
  Future<void> _persist() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('lamma_ids_v1', jsonEncode(_ids.toList()));
      await p.setString('lamma_variants_v1',
          jsonEncode(_variants.map((k, v) => MapEntry(k.toString(), v))));
      await p.setString('lamma_type_v1', type);
    } catch (_) {}
  }

  Future<void> restore() async {
    if (_restored) return;
    _restored = true;
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString('lamma_ids_v1');
      // only load the saved bundle when nothing was added this session yet —
      // never overwrite items the user just added.
      if (s != null && s.isNotEmpty && _ids.isEmpty) {
        _ids.addAll((jsonDecode(s) as List).map((e) => (e as num).toInt()));
        final v = p.getString('lamma_variants_v1');
        if (v != null && v.isNotEmpty) {
          (jsonDecode(v) as Map).forEach((k, val) =>
              _variants[int.parse(k.toString())] = (val as num).toInt());
        }
      }
      type = p.getString('lamma_type_v1') ?? 'normal';
    } catch (_) {}
    if (_ids.isNotEmpty) await refresh();
  }

  /// {templateId: variantId} for the products where a colour/variant was picked.
  Map<String, int> _variantPayload() =>
      _variants.map((k, v) => MapEntry(k.toString(), v));

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

  Future<void> toggle(int id, {int? variantId}) async {
    if (_ids.contains(id)) {
      _ids.remove(id);
      _variants.remove(id);
    } else {
      _ids.add(id);
      if (variantId != null) _variants[id] = variantId;
      hidden.value = false; // a fresh add always re-shows the mini-bar
    }
    _persist();
    await refresh();
  }

  Future<void> remove(int id) async {
    _ids.remove(id);
    _variants.remove(id);
    _persist();
    await refresh();
  }

  Future<void> setType(String t) async {
    type = (t == 'installment') ? 'installment' : 'normal';
    _persist();
    await refresh();
  }

  void clear() {
    _ids.clear();
    _variants.clear();
    quote.value = null;
    _persist();
  }

  /// Fetch the selectable colours/variants for a product (for the picker).
  Future<Map<String, dynamic>?> fetchVariants(int productId) async {
    try {
      final r = await http.get(
        Uri.parse('$_base/api/mobile/v2/lamma/variants?product_id=$productId'),
        headers: _headers,
      );
      if (r.statusCode == 200) return jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) {}
    return null;
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
        body: jsonEncode({
          'product_ids': _ids.toList(),
          'variants': _variantPayload(),
          'type': type,
        }),
      );
      if (r.statusCode == 200) {
        quote.value = jsonDecode(r.body) as Map<String, dynamic>;
      }
    } catch (_) {/* keep last quote */}
  }

  /// Push the Lamma into the app cart WITH the margin-protected discount, via
  /// the server checkout endpoint (auth-aware — it resolves the partner/guest
  /// cart from the Bearer + cart tokens). Returns true on success.
  /// Product ids actually shown in the sheet (the quote) — the source of truth
  /// the customer sees; falls back to the in-memory set.
  List<int> shownIds() {
    final items = (quote.value?['items'] as List?) ?? [];
    if (items.isNotEmpty) {
      return items.map((it) => (it['id'] as num).toInt()).toList();
    }
    return _ids.toList();
  }

  /// Runs checkout. Returns null on success, or a clear Arabic/English message
  /// explaining exactly why it did not go through.
  Future<String?> checkout() async {
    final ids = shownIds();
    if (ids.length < 2) {
      return _ar ? 'أضف منتجين على الأقل لإتمام اللمّة'
                 : 'Add at least 2 products to check out';
    }
    try {
      final headers = Map<String, String>.from(_headers);
      final token = await UellowApi.instance.tokenStore.readToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
      final cartToken = await UellowApi.instance.tokenStore.readCartToken();
      if (cartToken != null && cartToken.isNotEmpty) {
        headers['X-Cart-Token'] = cartToken;
      }
      final r = await http.post(
        Uri.parse('$_base/api/mobile/v2/lamma/checkout'),
        headers: headers,
        body: jsonEncode({
          'product_ids': ids,
          'variants': _variantPayload(),
          'type': type,
        }),
      );
      Map<String, dynamic> body = {};
      try { body = jsonDecode(r.body) as Map<String, dynamic>; } catch (_) {}
      if (r.statusCode == 200 && body['ok'] == true) {
        // Adopt the server cart token so the cart screen reads the SAME order we
        // just filled — otherwise it opens empty right after checkout.
        final ct = (body['cart_token'] ?? '').toString();
        if (ct.isNotEmpty) {
          try { await UellowApi.instance.tokenStore.writeCartToken(ct); } catch (_) {}
        }
        clear();
        return null;
      }
      // map server error codes to a clear message
      final err = (body['error'] ?? '').toString();
      switch (err) {
        case 'need_more':
          return _ar ? 'أضف منتجين على الأقل لإتمام اللمّة'
                     : 'Add at least 2 products to check out';
        case 'disabled':
          return _ar ? 'خدمة اللمّة غير متاحة في بلدك حالياً'
                     : 'Lamma is not available in your country yet';
        case 'no_order':
          return _ar ? 'تعذّر إنشاء سلة الطلب، حدّث الصفحة وحاول مجدداً'
                     : 'Could not create your cart, please retry';
        default:
          return _ar
              ? 'حدث خطأ أثناء إتمام اللمّة — تواصل معنا إذا استمرت المشكلة'
              : 'Something went wrong finishing your Lamma — contact us if it persists';
      }
    } catch (_) {
      return _ar ? 'لا يوجد اتصال بالإنترنت، تحقّق من الشبكة وحاول مجدداً'
                 : 'No internet connection, please check your network';
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
          if (_s.has(widget.productId)) {
            await _s.toggle(widget.productId); // already in bundle → remove
          } else {
            final data = await _s.fetchVariants(widget.productId);
            if (!mounted) return;
            if (data != null && data['multi'] == true) {
              final chosen = await showVariantPicker(context, data);
              if (chosen == null) return; // user cancelled the colour picker
              await _s.toggle(widget.productId, variantId: chosen);
            } else {
              final vs = (data?['variants'] as List?) ?? const [];
              final vid = vs.isNotEmpty ? (vs.first['variant_id'] as num).toInt() : null;
              await _s.toggle(widget.productId, variantId: vid);
            }
          }
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
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                inBundle
                    ? (_ar ? '✓ في لمّتك' : '✓ in Lamma')
                    : (_ar ? '🧺 أضف للّمّة' : '🧺 Add to Lamma'),
                maxLines: 1,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: inBundle ? const Color(0xFF4ADE80) : _ink,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows the "add to Lamma" button in place of the Buy-Now button when Lamma is
/// enabled for this country; otherwise falls back to the original Buy-Now widget.
class LammaBuyNowSlot extends StatelessWidget {
  const LammaBuyNowSlot({super.key, required this.productId, required this.fallback});
  final int productId;
  final Widget fallback;
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, dynamic>?>(
      valueListenable: LammaService.instance.config,
      builder: (context, cfg, _) {
        final enabled = cfg != null && cfg['enabled'] == true;
        return enabled ? LammaButton(productId: productId) : fallback;
      },
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
  final msg = ValueNotifier<String?>(null); // in-sheet message (shows ON TOP of the sheet)
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
          final excluded = ((q['excluded'] ?? 0) as num).toInt();
          final savedAmt = (q['saved'] ?? 0).toDouble();
          final nItems = ((q['n'] ?? 0) as num).toInt();
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
                  _seg(ctx, s, 'installment', _ar ? 'أقساط' : 'Installment'),
                ]),
              ),
              if (inst) Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(color: const Color(0xFFF4F0FF), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE6DCFF))),
                child: Text(
                  _ar
                      ? '💳 الأقساط: قسّم طلبك على دفعات مريحة عبر Taly / CINET — موافقة سريعة وبدون تعقيد. أضف منتجاتك واختر «الأقساط»، وأكمل الدفع بالتقسيط عند الدفع.'
                      : '💳 Installments: split your order into easy payments via Taly / CINET — quick approval, no hassle. Add items, pick Installments, and pay in instalments at checkout.',
                  style: const TextStyle(color: Color(0xFF6B4EC7), fontSize: 12, fontWeight: FontWeight.w600, height: 1.5),
                ),
              ),
              const SizedBox(height: 12),
              ...items.map((it) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: Image.network('$base${it['image']}', width: 38, height: 38, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(width: 38, height: 38, color: const Color(0xFFF0F2F5))),
                      ),
                      const SizedBox(width: 9),
                      Expanded(child: Text('${it['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF344054), height: 1.3))),
                      const SizedBox(width: 6),
                      Text('${(it['price'] as num).toStringAsFixed(3)}', style: const TextStyle(fontWeight: FontWeight.w800, color: _orange, fontSize: 12)),
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: () => s.remove(it['id'] as int),
                        child: Container(width: 24, height: 24, alignment: Alignment.center,
                          decoration: BoxDecoration(color: const Color(0xFFFFF0F0), borderRadius: BorderRadius.circular(7)),
                          child: const Text('✕', style: TextStyle(color: Color(0xFFF04438), fontWeight: FontWeight.w800, fontSize: 12))),
                      ),
                    ]),
                  )),
              if (excluded > 0 && savedAmt > 0)
                _noteBox(
                  _ar
                      ? '✔️ طُبّق خصم اللمّة على المنتجات المؤهّلة، و$excluded ${excluded == 1 ? 'منتج' : 'منتجات'} عند حد الربح فبقيت بسعرها.'
                      : '✔️ Discount applied to eligible items; $excluded item(s) are at the margin floor and kept full price.',
                  amber: false)
              else if (savedAmt <= 0 && nItems >= 2)
                _noteBox(
                  _ar
                      ? 'ℹ️ منتجات هذه الباقة عند حد الربح حالياً، فلا يمكن تطبيق خصم اللمّة عليها.'
                      : 'ℹ️ These items are at the margin floor, so no Lamma discount can apply right now.',
                  amber: true)
              else if (capped)
                _noteBox(
                  _ar
                      ? '✔️ خصم اللمّة وصل حده الأقصى لهذه الباقة.'
                      : '✔️ Lamma discount reached its maximum for this bundle.',
                  amber: false),
              const SizedBox(height: 10),
              // professional price breakdown: subtotal / discount / net
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFFF7F8FA), borderRadius: BorderRadius.circular(12)),
                child: Column(children: [
                  _brk(_ar ? 'الإجمالي قبل الخصم' : 'Subtotal',
                      '${(q['subtotal'] ?? 0).toStringAsFixed(3)} $cur', const Color(0xFF667085), false),
                  const SizedBox(height: 7),
                  _brk((_ar ? 'الخصم' : 'Discount') +
                          (((q['discount_pct'] ?? 0) as num) > 0 ? ' (-${(q['discount_pct'] ?? 0).toStringAsFixed(0)}%)' : ''),
                      '− ${(q['saved'] ?? 0).toStringAsFixed(3)} $cur', const Color(0xFF12B76A), false),
                  if (inst) ...[
                    const SizedBox(height: 7),
                    _brk(_ar ? 'التقسيط' : 'Installment',
                        '${(q['monthly'] ?? 0).toStringAsFixed(3)} $cur/${_ar ? 'شهر' : 'mo'}', const Color(0xFF7A5AF8), false),
                  ],
                  const Padding(padding: EdgeInsets.symmetric(vertical: 9), child: Divider(height: 1)),
                  _brk(_ar ? 'الصافي' : 'Net',
                      '${(q['pays'] ?? 0).toStringAsFixed(3)} $cur', _ink, true),
                ]),
              ),
              const SizedBox(height: 12),
              // in-sheet message banner — renders ON TOP of the sheet (not behind it)
              ValueListenableBuilder<String?>(
                valueListenable: msg,
                builder: (ctx, m, _) {
                  if (m == null) return const SizedBox.shrink();
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF4E5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFFD9A8)),
                    ),
                    child: Row(children: [
                      const Text('⚠️', style: TextStyle(fontSize: 15)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(m, style: const TextStyle(color: Color(0xFF8A5A12), fontWeight: FontWeight.w700, fontSize: 12.5))),
                    ]),
                  );
                },
              ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _orange, foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    final shown = ((q['items'] as List?) ?? []).length;
                    if (shown < 2) {
                      msg.value = _ar ? 'أضف منتجين على الأقل للّمّة' : 'Add at least 2 products';
                      return;
                    }
                    msg.value = null;
                    final err = await s.checkout();
                    if (!ctx.mounted) return;
                    if (err == null) {
                      Navigator.pop(ctx);
                      Navigator.pushNamed(context, '/cart');
                    } else {
                      msg.value = err; // clear, specific reason
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

Widget _noteBox(String text, {required bool amber}) {
  return Container(
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: amber ? const Color(0xFFFFF4E5) : const Color(0xFF12241B),
      borderRadius: BorderRadius.circular(10),
      border: amber ? Border.all(color: const Color(0xFFFFD9A8)) : null,
    ),
    child: Text(text,
        style: TextStyle(
          color: amber ? const Color(0xFF8A5A12) : const Color(0xFF4ADE80),
          fontWeight: FontWeight.w700,
          fontSize: 12.5,
          height: 1.45,
        )),
  );
}

Widget _brk(String label, String value, Color color, bool big) {
  return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
    Text(label, style: TextStyle(
        color: big ? _ink : const Color(0xFF667085),
        fontWeight: big ? FontWeight.w800 : FontWeight.w600,
        fontSize: big ? 15 : 13)),
    Text(value, style: TextStyle(
        color: color,
        fontWeight: big ? FontWeight.w900 : FontWeight.w700,
        fontSize: big ? 20 : 13.5)),
  ]);
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

Color? _parseHtmlColor(String s) {
  var h = s.trim();
  if (h.isEmpty) return null;
  if (h.startsWith('#')) h = h.substring(1);
  if (h.length == 6) {
    final v = int.tryParse(h, radix: 16);
    if (v != null) return Color(0xFF000000 | v);
  }
  return null;
}

/// Colour / variant picker shown when a product has more than one variant.
/// Returns the chosen variant id, or null if the customer backed out.
Future<int?> showVariantPicker(BuildContext context, Map<String, dynamic> data) {
  final variants = (data['variants'] as List?) ?? const [];
  final cur = (data['currency'] ?? 'KD').toString();
  final base = UellowApi.instance.baseUrl;
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (ctx) => Directionality(
      textDirection: _ar ? TextDirection.rtl : TextDirection.ltr,
      child: Padding(
        padding: EdgeInsets.only(left: 16, right: 16, top: 14, bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFFE2E6EC), borderRadius: BorderRadius.circular(9))),
          const SizedBox(height: 12),
          Text(_ar ? 'اختر اللون / النوع 🎨' : 'Choose colour / variant 🎨',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: _ink)),
          const SizedBox(height: 4),
          Text(_ar ? 'حدّد الخيار الذي تريد إضافته للّمّة' : 'Pick the option to add to your Lamma',
              style: const TextStyle(fontSize: 12, color: Color(0xFF98A2B3))),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.55),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: variants.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final v = variants[i] as Map;
                final sw = _parseHtmlColor((v['color'] ?? '').toString());
                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.pop(ctx, (v['variant_id'] as num).toInt()),
                  child: Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F8FA),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFECEFF3)),
                    ),
                    child: Row(children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: Image.network('$base${v['image']}', width: 44, height: 44, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(width: 44, height: 44, color: const Color(0xFFF0F2F5))),
                      ),
                      const SizedBox(width: 10),
                      if (sw != null) ...[
                        Container(width: 16, height: 16, decoration: BoxDecoration(
                            color: sw, shape: BoxShape.circle, border: Border.all(color: const Color(0xFFD0D5DD)))),
                        const SizedBox(width: 8),
                      ],
                      Expanded(child: Text('${v['label']}', maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF344054)))),
                      const SizedBox(width: 6),
                      Text('${(v['price'] as num).toStringAsFixed(3)} $cur',
                          style: const TextStyle(fontWeight: FontWeight.w800, color: _orange, fontSize: 12.5)),
                      const SizedBox(width: 4),
                      Icon(_ar ? Icons.chevron_left : Icons.chevron_right, size: 18, color: const Color(0xFF98A2B3)),
                    ]),
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    ),
  );
}

/// Slim floating mini-bar shown on ALL screens (via MaterialApp.builder) when the
/// Lamma has items. Dismissible (✕); product pages show their own inline bar so
/// this one yields there. Returns a zero-size box (not Positioned) when hidden.
class LammaGlobalBar extends StatelessWidget {
  const LammaGlobalBar({super.key});
  @override
  Widget build(BuildContext context) {
    final s = LammaService.instance;
    return AnimatedBuilder(
      animation: Listenable.merge([s.quote, s.hidden, s.onProductPage, s.onSplash]),
      builder: (context, _) {
        final q = s.quote.value;
        if (q == null || (q['n'] ?? 0) == 0) return const SizedBox.shrink();
        if (s.hidden.value || s.onProductPage.value || s.onSplash.value) {
          return const SizedBox.shrink();
        }
        final cur = (q['currency'] ?? 'KD').toString();
        final pays = (q['pays'] ?? 0).toDouble();
        final pct = (q['discount_pct'] ?? 0).toDouble();
        final items = (q['items'] as List?) ?? const [];
        final n = (q['n'] ?? 0);
        return Positioned(
          left: 12,
          right: 12,
          bottom: MediaQuery.of(context).padding.bottom + 74,
          child: Directionality(
            textDirection: _ar ? TextDirection.rtl : TextDirection.ltr,
            child: Material(
              color: _ink,
              elevation: 12,
              shadowColor: Colors.black45,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => showLammaSheet(s._navCtx ?? context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF2A3444)),
                  ),
                  child: Row(children: [
                    _Thumbs(items: items),
                    const SizedBox(width: 8),
                    Expanded(
                      child: RichText(
                        textDirection: _ar ? TextDirection.rtl : TextDirection.ltr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        text: TextSpan(
                          style: const TextStyle(fontSize: 12, color: Color(0xFFC3CAD6)),
                          children: [
                            TextSpan(text: _ar ? 'لمّتك ($n) · ' : 'Lamma ($n) · '),
                            TextSpan(text: '${pays.toStringAsFixed(3)} $cur',
                                style: const TextStyle(color: _yellow, fontWeight: FontWeight.w800)),
                            if (pct > 0) TextSpan(text: '  -${pct.toStringAsFixed(0)}%'),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [_yellow, _orange]),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(_ar ? 'التفاصيل' : 'View',
                          style: const TextStyle(fontWeight: FontWeight.w800, color: _ink, fontSize: 12)),
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () => s.hidden.value = true,
                      borderRadius: BorderRadius.circular(20),
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(Icons.close, size: 16, color: Color(0xFF8B97A8)),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Compact entry-point block for the account screen: shows the current Lamma
/// contents (thumbs + total) and reopens the sheet. Hidden when empty.
class LammaAccountBlock extends StatelessWidget {
  const LammaAccountBlock({super.key});
  @override
  Widget build(BuildContext context) {
    final s = LammaService.instance;
    return ValueListenableBuilder<Map<String, dynamic>?>(
      valueListenable: s.quote,
      builder: (context, q, _) {
        if (q == null || (q['n'] ?? 0) == 0) return const SizedBox.shrink();
        final cur = (q['currency'] ?? 'KD').toString();
        final pays = (q['pays'] ?? 0).toDouble();
        final pct = (q['discount_pct'] ?? 0).toDouble();
        final items = (q['items'] as List?) ?? const [];
        final n = (q['n'] ?? 0);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => showLammaSheet(context),
              child: Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF12241B), _ink],
                    begin: Alignment.centerRight, end: Alignment.centerLeft),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF243244)),
                ),
                child: Row(children: [
                  _Thumbs(items: items),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_ar ? 'لمّتك 🧺' : 'Your Lamma 🧺',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: Colors.white)),
                        const SizedBox(height: 2),
                        Text(
                          _ar
                              ? '$n منتج · ${pays.toStringAsFixed(3)} $cur${pct > 0 ? ' · وفّرت ${pct.toStringAsFixed(0)}%' : ''}'
                              : '$n items · ${pays.toStringAsFixed(3)} $cur${pct > 0 ? ' · save ${pct.toStringAsFixed(0)}%' : ''}',
                          style: const TextStyle(fontSize: 11.5, color: Color(0xFFB9C2CF), fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [_yellow, _orange]),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(_ar ? 'متابعة' : 'Open',
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
