// لمّة يلو (Uellow Lamma) — smart bundle for the app.
// Self-contained: state + API (config/quote) + button/bar/sheet widgets.
// Renders from the server /quote response, so it stays decoupled from the app's
// product model — it only needs a productId (int) to add/remove.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../api/uellow_api.dart';
import 'lamma_group.dart';

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

  /// Current top route name (fed by LammaRouteObserver). The global bar
  /// only paints on the allowed pages; any modal/dialog (name == null)
  /// hides it automatically.
  final ValueNotifier<String?> currentRoute = ValueNotifier<String?>(null);

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
    await maybeAutoStartFromCart();
  }

  /// Auto-start: when settings enable it and the Lamma is still empty, seed it
  /// from whatever is already in the cart (2+ products) so it activates on its
  /// own — mirrors the web behaviour. Safe/no-op otherwise. Called after both
  /// config load and restore, so whichever finishes last triggers it.
  Future<void> maybeAutoStartFromCart() async {
    try {
      if (!_restored || _ids.isNotEmpty) return;
      if (config.value?['auto_start'] != true) return;
      final headers = Map<String, String>.from(_headers);
      final token = await UellowApi.instance.tokenStore.readToken();
      if (token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';
      final ct = await UellowApi.instance.tokenStore.readCartToken();
      if (ct != null && ct.isNotEmpty) headers['X-Cart-Token'] = ct;
      final r = await http.get(
          Uri.parse('$_base/api/mobile/v2/lamma/cart-items'), headers: headers);
      if (r.statusCode != 200) return;
      final items = ((jsonDecode(r.body) as Map)['items'] as List?) ?? const [];
      if (items.length < 2 || _ids.isNotEmpty) return;
      for (final it in items) {
        final pid = (it['product_id'] as num).toInt();
        final vid = (it['variant_id'] as num?)?.toInt();
        _ids.add(pid);
        if (vid != null) _variants[pid] = vid;
      }
      _persist();
      await refresh();
    } catch (_) {}
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
    await maybeAutoStartFromCart(); // auto-activate from cart once config is known
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
  bool _checkingOut = false;
  Future<String?> checkout() async {
    // Re-entrancy guard: a double-tap must never fire two checkouts (which
    // used to add the bundle + a discount twice).
    if (_checkingOut) {
      return _ar ? 'جارٍ إتمام اللمّة، انتظر لحظة…' : 'Finishing your Lamma, please wait…';
    }
    _checkingOut = true;
    try {
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
    } finally {
      _checkingOut = false;
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
  bool _busy = false; // guards against a double-tap racing add-then-remove
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
          if (_busy) return;
          _busy = true;
          try {
            if (_s.has(widget.productId)) {
              await _s.toggle(widget.productId); // already in bundle → remove
            } else {
              final data = await _s.fetchVariants(widget.productId);
              if (!mounted) return;
              // A null response = the options fetch FAILED — never silently add a
              // multi-variant product with no colour chosen; ask to retry.
              if (data == null) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(_ar ? 'تعذّر تحميل الخيارات، حاول مجدداً'
                                      : 'Could not load options, please try again')));
                return;
              }
              if (data['multi'] == true) {
                final chosen = await showVariantPicker(context, data);
                if (chosen == null) return; // user cancelled the colour picker
                await _s.toggle(widget.productId, variantId: chosen);
              } else {
                final vs = (data['variants'] as List?) ?? const [];
                final vid = vs.isNotEmpty ? (vs.first['variant_id'] as num).toInt() : null;
                await _s.toggle(widget.productId, variantId: vid);
              }
            }
            if (mounted) setState(() {});
          } finally {
            _busy = false;
          }
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
// Uellow "Temu-style" orange for the checkout CTA + count chip.
const _temuA = Color(0xFFFF8A00);
const _temuB = Color(0xFFFB4E00);

/// The shared لمّة يلو bar card — clean white, product thumbnails, the net price
/// with a red "كان (was)" pill emphasising the pre-discount price, and a bold
/// orange checkout CTA. Used by both the floating global bar and the inline bar.
Widget lammaBarCard(BuildContext context, Map<String, dynamic> q,
    {required VoidCallback onTap, VoidCallback? onClose}) {
  final cur = (q['currency'] ?? 'KD').toString();
  final n = ((q['n'] ?? 0) as num).toInt();
  final pays = (q['pays'] ?? 0).toDouble();
  final subtotal = (q['subtotal'] ?? 0).toDouble();
  final pct = (q['discount_pct'] ?? 0).toDouble();
  final items = (q['items'] as List?) ?? const [];
  final hasDiscount = pct > 0 && subtotal > pays + 0.0005;
  return Material(
    color: Colors.white,
    elevation: 10,
    shadowColor: Colors.black.withOpacity(0.26),
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(13, 10, 13, 10),
        child: Row(children: [
          _ThumbsLite(items: items, count: n),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                RichText(
                  textDirection: _ar ? TextDirection.rtl : TextDirection.ltr,
                  text: TextSpan(children: [
                    TextSpan(
                      text: pays.toStringAsFixed(3),
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 16, color: _ink, height: 1),
                    ),
                    TextSpan(
                      text: ' $cur',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 11, color: Color(0xFF98A2B3)),
                    ),
                  ]),
                ),
                const SizedBox(height: 4),
                if (hasDiscount)
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: _ar ? Alignment.centerRight : Alignment.centerLeft,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      // red "كان" pill — the pre-discount price
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFECEC),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: const Color(0xFFFFD4D4)),
                        ),
                        child: RichText(
                          textDirection: _ar ? TextDirection.rtl : TextDirection.ltr,
                          text: TextSpan(children: [
                            TextSpan(
                              text: _ar ? 'كان ' : 'was ',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 11.5, color: Color(0xFFC23434)),
                            ),
                            TextSpan(
                              text: subtotal.toStringAsFixed(3),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 11.5, color: Color(0xFFE05252),
                                  decoration: TextDecoration.lineThrough),
                            ),
                          ]),
                        ),
                      ),
                      const SizedBox(width: 5),
                      // green "وفّرت" pill — the saved amount
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE6F7EE),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: const Color(0xFFC4EBD6)),
                        ),
                        child: Text(
                          '${_ar ? 'وفّرت' : 'saved'} ${(subtotal - pays).toStringAsFixed(3)}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 11.5, color: Color(0xFF0E9F6E)),
                        ),
                      ),
                    ]),
                  )
                else
                  const SizedBox.shrink(),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [_temuA, _temuB]),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                    color: const Color(0xFFFB4E00).withOpacity(0.32),
                    blurRadius: 14, offset: const Offset(0, 6)),
              ],
            ),
            child: Text(_ar ? 'أكمل اللمّة' : 'Checkout',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Colors.white)),
          ),
          if (onClose != null) ...[
            const SizedBox(width: 2),
            InkWell(
              onTap: onClose,
              borderRadius: BorderRadius.circular(20),
              child: const Padding(
                padding: EdgeInsets.all(5),
                child: Icon(Icons.close, size: 16, color: Color(0xFF98A2B3)),
              ),
            ),
          ],
        ]),
      ),
    ),
  );
}

/// Overlapping product thumbnails (white) + a count chip, for the light bar.
class _ThumbsLite extends StatelessWidget {
  const _ThumbsLite({required this.items, required this.count});
  final List items;
  final int count;
  @override
  Widget build(BuildContext context) {
    final base = UellowApi.instance.baseUrl;
    final shown = items.take(3).toList();
    const sz = 36.0, step = 25.0;
    final slots = shown.length + 1; // + count chip
    return SizedBox(
      width: step * (slots - 1) + sz,
      height: sz,
      child: Stack(children: [
        for (var i = 0; i < shown.length; i++)
          Positioned(
            top: 0,
            right: i * step,
            child: Container(
              width: sz, height: sz,
              decoration: BoxDecoration(
                color: const Color(0xFFEEF1F6),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 5, offset: const Offset(0, 2)),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network('$base${shown[i]['image']}',
                    width: sz, height: sz, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox()),
              ),
            ),
          ),
        Positioned(
          top: 0,
          right: shown.length * step,
          child: Container(
            width: sz, height: sz,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [_temuA, _temuB]),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Text('$count',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
          ),
        ),
      ]),
    );
  }
}

/// Inline bar shown just above the CTA on product pages when the Lamma has items.
class LammaBar extends StatelessWidget {
  const LammaBar({super.key});
  @override
  Widget build(BuildContext context) {
    final s = LammaService.instance;
    return ValueListenableBuilder<Map<String, dynamic>?>(
      valueListenable: s.quote,
      builder: (context, q, _) {
        if (q == null || (q['n'] ?? 0) == 0) return const SizedBox.shrink();
        if (s.config.value?['enabled'] == false) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: lammaBarCard(context, q, onTap: () => showLammaSheet(context)),
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
              if (savedAmt <= 0 && nItems >= 2)
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
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFF7A1A),
                    side: const BorderSide(color: Color(0xFFFFD0A8), width: 1.4),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () { Navigator.pop(ctx); startGroupLamma(context); },
                  icon: const Text('🧺', style: TextStyle(fontSize: 16)),
                  label: Text(_ar ? 'ابدأ لمّة جماعية — شارك التوفير' : 'Start a group Lamma',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5)),
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
/// Tracks the visible route so the global Lamma bar restricts itself to a
/// few pages and disappears while any modal/dialog is open.
class LammaRouteObserver extends NavigatorObserver {
  void _set(String? n) => LammaService.instance.currentRoute.value = n;
  @override
  void didPush(Route route, Route? prev) { super.didPush(route, prev); _set(route.settings.name); }
  @override
  void didPop(Route route, Route? prev) { super.didPop(route, prev); _set(prev?.settings.name); }
  @override
  void didReplace({Route? newRoute, Route? oldRoute}) { super.didReplace(newRoute: newRoute, oldRoute: oldRoute); _set(newRoute?.settings.name); }
  @override
  void didRemove(Route route, Route? prev) { super.didRemove(route, prev); _set(prev?.settings.name); }
}

class LammaGlobalBar extends StatelessWidget {
  const LammaGlobalBar({super.key});
  @override
  Widget build(BuildContext context) {
    final s = LammaService.instance;
    return AnimatedBuilder(
      animation: Listenable.merge([s.quote, s.hidden, s.currentRoute]),
      builder: (context, _) {
        // Only these three surfaces show the Lamma bar; product pages use
        // their own inline bar, and any open modal (route name == null)
        // drops out of this set so the bar hides while a dialog is up.
        const allowed = {'/home', '/category', '/collection'};
        if (!allowed.contains(s.currentRoute.value)) return const SizedBox.shrink();
        final q = s.quote.value;
        if (q == null || (q['n'] ?? 0) == 0) return const SizedBox.shrink();
        if (s.config.value?['enabled'] == false) return const SizedBox.shrink();
        if (s.hidden.value) return const SizedBox.shrink();
        return Positioned(
          left: 12,
          right: 12,
          bottom: MediaQuery.of(context).padding.bottom + 74,
          child: Directionality(
            textDirection: _ar ? TextDirection.rtl : TextDirection.ltr,
            child: lammaBarCard(
              context, q,
              onTap: () => showLammaSheet(s._navCtx ?? context),
              onClose: () => s.hidden.value = true,
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
