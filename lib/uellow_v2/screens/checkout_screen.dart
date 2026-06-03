// =============================================================================
// CheckoutScreen — native (NOT a webview). Fetches:
//   • /orders/checkout/summary       — cart + saved addresses
//   • /orders/shipping-methods        — real delivery carriers + zone rates
//   • /orders/payment-methods         — enabled payment.providers from Odoo
//   • /orders/checkout/geoip          — IP + city + matched stored address
//
// Then renders 3 selectable sections (address, shipping, payment) plus a
// summary block and a GREEN "Place order" CTA.
// =============================================================================
import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../api/uellow_api.dart';
import '../../api/uellow_models.dart';
import '../router/uellow_router.dart';
import '../services/first_launch_service.dart';
import '../theme/uellow_l10n.dart';
import '../theme/uellow_theme.dart';
import 'address_picker_screen.dart';
import 'addresses_screen.dart';
import 'auth_screen.dart';
import 'order_confirmation_screen.dart';
import 'webview_screen.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});
  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  late Future<_CheckoutData> _data;
  int? _selectedAddressId;
  int? _selectedCarrierId;
  int? _selectedPaymentId;
  bool _placing = false;
  // v2.1.20 — guest checkout: opt-in after a lose-perks warning; only
  // offered when the per-website backend setting enables it.
  bool _guestMode = false;
  bool _guestAllowed = false;

  @override
  void initState() {
    super.initState();
    _data = _bootstrap();
    _loadGuestFlag();
  }

  void _loadGuestFlag() async {
    try {
      final s = await UellowApi.instance.settings.get();
      if (mounted) setState(() => _guestAllowed = s.guestCheckout);
    } catch (_) {}
  }

  Future<_CheckoutData> _bootstrap() async {
    // v2.0.81 — defensive bootstrap. Every HTTP call is wrapped with a
    // timeout + try/catch so a single dead endpoint never takes down the
    // whole checkout screen. IDs are coerced through `_asInt()` because
    // Odoo sometimes returns them as String/num and the bare `as int?`
    // throws on a TypeError that's invisible to the user (just shows
    // "Could not load checkout").
    final base = UellowApi.instance.baseUrl;
    final token = await UellowApi.instance.tokenStore.readToken();
    final cartToken = await UellowApi.instance.tokenStore.readCartToken();
    Map<String, String> hdrs(bool needAuth) => {
      'Accept': 'application/json',
      if (token != null && needAuth) 'Authorization': 'Bearer $token',
      if (cartToken != null) 'X-Cart-Token': cartToken,
    };

    String? country;
    try {
      final prefs = await SharedPreferences.getInstance();
      country = prefs.getString('uellow_country_code_v1');
    } catch (_) {}
    final pmUrl = country != null && country.isNotEmpty
        ? '$base/api/mobile/v2/orders/payment-methods?country=$country'
        : '$base/api/mobile/v2/orders/payment-methods';

    Future<Map<String, dynamic>> safeGet(String url, {required bool needAuth}) async {
      try {
        final r = await http.get(Uri.parse(url), headers: hdrs(needAuth))
            .timeout(const Duration(seconds: 15));
        final text = utf8.decode(r.bodyBytes);
        // Some proxies return HTML error pages on 5xx; jsonDecode would throw.
        if (text.isEmpty || !text.trimLeft().startsWith('{')) {
          return {'success': false, 'error': 'Bad response (${r.statusCode})'};
        }
        return jsonDecode(text) as Map<String, dynamic>;
      } on TimeoutException {
        return {'success': false, 'error': 'Request timed out'};
      } catch (e) {
        return {'success': false, 'error': '$e'};
      }
    }

    final guestQ = _guestMode ? '?guest=1' : '';
    final results = await Future.wait([
      safeGet('$base/api/mobile/v2/orders/checkout/summary$guestQ', needAuth: true),
      safeGet('$base/api/mobile/v2/orders/shipping-methods', needAuth: false),
      safeGet(pmUrl, needAuth: false),
      safeGet('$base/api/mobile/v2/orders/checkout/geoip', needAuth: true),
    ]);
    final summary = results[0];
    final shipping = results[1];
    final payment = results[2];
    final geoip = results[3];

    Map<String, dynamic>? asMap(dynamic d) =>
        d is Map ? d.cast<String, dynamic>() : null;
    List<Map<String, dynamic>> asList(dynamic d) => d is List
        ? d.map((e) => (e is Map ? e.cast<String, dynamic>() : <String, dynamic>{}))
            .toList()
        : <Map<String, dynamic>>[];

    final out = _CheckoutData(
      summary: summary['success'] == true ? asMap(summary['data']) : null,
      shippingMethods: shipping['success'] == true ? asList(shipping['data']) : [],
      paymentMethods: payment['success'] == true ? asList(payment['data']) : [],
      geoip: geoip['success'] == true ? asMap(geoip['data']) : null,
    );
    // The summary endpoint is the load-bearing one — surface its failure
    // as the screen-level error so the user sees a friendly message.
    if (out.summary == null) {
      // v2.1.2 — distinguish "not logged in" from a generic failure so the
      // screen can show a Sign-in CTA instead of a useless Retry on a raw
      // "Authentication required" string.
      final code = summary['code']?.toString() ?? '';
      final errStr = (summary['error']?.toString() ?? '').toLowerCase();
      if (code == 'AUTH_REQUIRED' || errStr.contains('authentication')
          || errStr.contains('logged in')) {
        throw Exception('AUTH_REQUIRED');
      }
      final reason = summary['error']?.toString() ?? 'Could not load checkout';
      throw Exception(reason);
    }

    // Initial selections — defensive ID coercion across the board.
    int? asInt(dynamic v) =>
        v is int ? v : (v is num ? v.toInt() : int.tryParse('$v'));

    final addrs = (out.summary?['addresses'] as List?) ?? [];
    if (addrs.isNotEmpty) {
      final stored = await UellowApi.instance.tokenStore.readAddressId();
      final hasStored = stored != null
          && addrs.any((a) => asInt((a as Map)['id']) == stored);
      final geoMatch = out.geoip?['matched_address'] as Map?;
      _selectedAddressId = hasStored
          ? stored
          : (asInt(geoMatch?['id']) ?? asInt((addrs.first as Map)['id']));
      // v2.1.18 — prefer a COMPLETE address over an incomplete default
      // (fresh signups have a name-only record).
      final selMap = addrs.cast<Map>().firstWhere(
          (a) => asInt(a['id']) == _selectedAddressId,
          orElse: () => addrs.first as Map);
      if (!addrComplete(selMap.cast<String, dynamic>())) {
        for (final a in addrs.cast<Map>()) {
          if (addrComplete(a.cast<String, dynamic>())) {
            _selectedAddressId = asInt(a['id']);
            break;
          }
        }
      }
    }
    if (out.shippingMethods.isNotEmpty) {
      _selectedCarrierId = asInt(out.shippingMethods.first['id']);
    }
    if (out.paymentMethods.isNotEmpty) {
      _selectedPaymentId = asInt(out.paymentMethods.first['id']);
    }
    return out;
  }

  Future<void> _confirmGuestCheckout() async {
    final ar = UellowApi.instance.lang == 'ar';
    await showDialog(context: context, builder: (dctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(ar ? 'المتابعة كزائر؟' : 'Continue as guest?',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900,
              color: UellowColors.darkBrown)),
      content: Text(ar
          ? 'بدون حساب ستفقد: متابعة حالة الطلب، نقاط الولاء والمكافآت، '
            'حفظ العناوين، وسجلّ مشترياتك. يمكنك إنشاء حساب في ثوانٍ.'
          : 'Without an account you lose: order tracking, loyalty points '
            'and rewards, saved addresses, and your purchase history. '
            'Creating an account takes seconds.',
          style: const TextStyle(fontSize: 13, height: 1.5)),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(dctx);
            setState(() {
              _guestMode = true;
              _data = _bootstrap();
            });
          },
          child: Text(ar ? 'الاستمرار كزائر' : 'Continue as guest',
              style: const TextStyle(color: UellowColors.muted,
                  fontSize: 12.5, fontWeight: FontWeight.w600)),
        ),
        ElevatedButton.icon(
          onPressed: () async {
            Navigator.pop(dctx);
            final ok = await showAuthSheet(context);
            if (ok && mounted) setState(() => _data = _bootstrap());
          },
          icon: const Icon(Icons.login, size: 15),
          label: Text(ar ? 'تسجيل الدخول' : 'Sign in',
              style: const TextStyle(fontWeight: FontWeight.w900)),
          style: ElevatedButton.styleFrom(
            backgroundColor: UellowColors.yellow,
            foregroundColor: UellowColors.darkBrown,
          ),
        ),
      ],
    ));
  }

  Future<void> _placeOrder(_CheckoutData d) async {
    if (_placing) return;
    // v2.1.18 — the order can only be placed with a COMPLETE address
    // (phone + street + city). Otherwise: red dialog with a button that
    // edits the SAME record (no new address row is created).
    final addrs = ((d.summary?['addresses'] as List?) ?? const [])
        .cast<Map>().map((a) => a.cast<String, dynamic>()).toList();
    Map<String, dynamic>? cur;
    for (final a in addrs) {
      if (a['id'] == _selectedAddressId) { cur = a; break; }
    }
    cur ??= addrs.isNotEmpty ? addrs.first : null;
    if (cur == null || !addrComplete(cur)) {
      final ar = UellowApi.instance.lang == 'ar';
      await showDialog(context: context, builder: (dctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const Icon(Icons.error_outline, color: UellowColors.danger),
          const SizedBox(width: 8),
          Expanded(child: Text(ar ? 'عبّئ عنوانك' : 'Complete your address',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900,
                  color: UellowColors.danger))),
        ]),
        content: Text(ar
            ? 'لا يمكن إتمام الطلب قبل تعبئة الهاتف والشارع والمدينة في عنوانك.'
            : 'Phone, street and city are required before placing the order.',
            style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx),
            child: Text(ar ? 'لاحقاً' : 'Later',
                style: const TextStyle(color: UellowColors.muted)),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(dctx);
              await Navigator.push(context, MaterialPageRoute(
                builder: (_) => AddressPickerScreen(
                  editing: cur == null ? null : UellowAddress.fromJson(cur),
                ),
              ));
              if (mounted) setState(() { _data = _bootstrap(); });
            },
            icon: const Icon(Icons.add_location_alt_outlined, size: 16),
            label: Text(ar ? 'أكمل العنوان' : 'Complete address',
                style: const TextStyle(fontWeight: FontWeight.w900)),
            style: ElevatedButton.styleFrom(
              backgroundColor: UellowColors.yellow,
              foregroundColor: UellowColors.darkBrown,
            ),
          ),
        ],
      ));
      return;
    }
    setState(() => _placing = true);
    try {
      final result = await UellowApi.instance.orders.checkoutConfirm(
        deliveryAddressId: _selectedAddressId,
        carrierId: _selectedCarrierId ?? 0,
        paymentMethod: _paymentCodeOf(d, _selectedPaymentId),
        guest: _guestMode,
      );
      if (!mounted) return;
      // v2.0.85 — honor paymentRequired + paymentUrl. For non-COD
      // (UPayments / KNET / Visa / Apple Pay / etc.), push the payment
      // page in a webview FIRST. The backend redirects to /payment/status
      // when the gateway returns; we listen for that URL and only then
      // route to the order-confirmation screen.
      final ar = UellowApi.instance.lang == 'ar';
      if (result.paymentRequired && (result.paymentUrl ?? '').isNotEmpty) {
        // v2.1.14 — payment opens as a DIALOG over the checkout (white-label
        // links land straight on the chosen gateway: KNET / Apple Pay / card)
        // instead of navigating away to a separate page.
        final paid = await showPaymentSheet(context,
            url: result.paymentUrl!,
            title: ar ? 'الدفع الآمن' : 'Secure payment');
        if (!mounted) return;
        // Cancelled / not completed / closed with back → cart is preserved
        // (online order stayed a draft until payment). Only an explicit `true`
        // (gateway redirected to the return/status URL) counts as paid.
        if (paid != true) {
          Navigator.pushReplacementNamed(context, Routes.orderConfirm,
            arguments: OrderConfirmationArgs(
              success: false,
              failureMessage: ar
                  ? 'لم يكتمل الدفع — سلتك محفوظة، يمكنك المحاولة مرة أخرى.'
                  : 'Payment was not completed — your cart is saved, you can try again.',
            ));
          return;
        }
      }
      // Guest receipt payload — the confirmation page is the guest's only
      // record of the order, so hand it everything we know.
      Map<String, dynamic>? gAddr;
      String? gShip, gShipPrice, gPay;
      if (_guestMode) {
        final addrs2 = ((d.summary?['addresses'] as List?) ?? const [])
            .cast<Map>().map((a) => a.cast<String, dynamic>()).toList();
        for (final a in addrs2) {
          if (a['id'] == _selectedAddressId) { gAddr = a; break; }
        }
        gAddr ??= addrs2.isNotEmpty ? addrs2.first : null;
        for (final m in d.shippingMethods) {
          if (m['id'] == _selectedCarrierId) {
            final lang2 = UellowApi.instance.lang;
            gShip = ((m['name'] as Map?)?[lang2]
                ?? (m['name'] as Map?)?['en'] ?? '').toString();
            final pm2 = m['price'] as Map?;
            if (pm2 != null) {
              gShipPrice = '${((pm2['amount'] as num?) ?? 0).toDouble().toStringAsFixed(3)} ${pm2['symbol'] ?? 'KD'}';
            }
            break;
          }
        }
        for (final m in d.paymentMethods) {
          if (m['id'] == _selectedPaymentId) {
            final lang2 = UellowApi.instance.lang;
            final nm = m['name'];
            gPay = nm is Map
                ? (nm[lang2] ?? nm['en'] ?? '').toString()
                : (nm ?? '').toString();
            break;
          }
        }
      }
      Navigator.pushReplacementNamed(context, Routes.orderConfirm,
        arguments: OrderConfirmationArgs(
          success: true,
          orderId: result.orderId,
          orderName: result.orderName,
          summary: d.summary,
          // Cashback only exists for ONLINE payments (backend sends it
          // only then; cash orders get nothing).
          cashbackAmount:
              result.cashbackAmount > 0 ? result.cashbackAmount : null,
          cashbackCurrency: result.cashbackCurrency,
          guest: _guestMode,
          guestAddress: gAddr,
          guestShipping: gShip,
          guestShippingPrice: gShipPrice,
          guestPayment: gPay,
        ));
    } on UellowApiException catch (e) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, Routes.orderConfirm,
        arguments: OrderConfirmationArgs(
          success: false,
          failureMessage: e.message,
        ));
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  String _paymentCodeOf(_CheckoutData d, int? id) {
    final pm = d.paymentMethods.firstWhere(
      (m) => m['id'] == id, orElse: () => const {});
    return (pm['code'] as String?) ?? 'card';
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return Scaffold(
      backgroundColor: UellowColors.bg,
      appBar: AppBar(
        leading: const BackButton(color: UellowColors.darkBrown),
        title: Text(ar ? 'إتمام الطلب' : 'Checkout', style: UT.h1),
        backgroundColor: Colors.white,
      ),
      body: FutureBuilder<_CheckoutData>(
        future: _data,
        builder: (_, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(
                color: UellowColors.darkBrown));
          }
          if (snap.hasError || snap.data?.summary == null) {
            // v2.0.81 — friendlier error state with a Retry button. The
            // bootstrap throws when the summary endpoint can't be fetched,
            // and previously the user just saw a stack trace and had to
            // close the screen to try again.
            final ar = UellowApi.instance.lang == 'ar';
            final rawMsg = snap.hasError ? snap.error.toString() : 'no_summary';
            // v2.1.2 — guests hit AUTH_REQUIRED on the summary endpoint; show
            // a Sign-in CTA (Retry would just fail again) instead of a raw
            // "Authentication required" line.
            final isAuth = rawMsg.contains('AUTH_REQUIRED');
            if (isAuth) {
              return Center(child: Padding(
                padding: const EdgeInsets.all(30),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.lock_outline, size: 56, color: UellowColors.muted),
                  const SizedBox(height: 14),
                  Text(ar ? 'سجّل الدخول لإتمام الطلب' : 'Sign in to complete checkout',
                      textAlign: TextAlign.center, style: UT.h3),
                  const SizedBox(height: 6),
                  Text(ar
                      ? 'تحتاج لحساب لإتمام الطلب وحفظ عناوينك وطلباتك.'
                      : 'You need an account to place the order and keep your addresses & orders.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12.5, color: UellowColors.muted)),
                  const SizedBox(height: 18),
                  ElevatedButton.icon(
                    onPressed: () async {
                      // Login as a DIALOG; stay on checkout and reload on success.
                      final ok = await showAuthSheet(context);
                      if (ok && mounted) setState(() => _data = _bootstrap());
                    },
                    icon: const Icon(Icons.login, size: 16),
                    label: Text(ar ? 'تسجيل الدخول' : 'Sign in'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: UellowColors.yellow,
                      foregroundColor: UellowColors.darkBrown,
                      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
                    ),
                  ),
                  // v2.1.20 — quiet, professional guest option (only when
                  // the backend setting allows it).
                  if (_guestAllowed) Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: TextButton(
                      onPressed: _confirmGuestCheckout,
                      style: TextButton.styleFrom(
                        foregroundColor: UellowColors.muted,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                      ),
                      child: Text(ar ? 'الاستكمال كزائر' : 'Continue as guest',
                          style: const TextStyle(fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              decoration: TextDecoration.underline,
                              decorationColor: UellowColors.muted)),
                    ),
                  ),
                ]),
              ));
            }
            final friendly = ar
                ? 'تعذّر تحميل صفحة الإتمام — تحقق من اتصالك وحاول مرة أخرى'
                : 'Could not load checkout — check your connection and try again';
            return Center(child: Padding(
              padding: const EdgeInsets.all(30),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.cloud_off_outlined, size: 56, color: UellowColors.muted),
                const SizedBox(height: 14),
                Text(friendly, textAlign: TextAlign.center, style: UT.body),
                const SizedBox(height: 6),
                // Show the raw error in a small dim line so we can debug
                // if the user reports the problem with a screenshot.
                Text(rawMsg, textAlign: TextAlign.center,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10.5,
                        color: UellowColors.muted)),
                const SizedBox(height: 18),
                ElevatedButton.icon(
                  onPressed: () => setState(() => _data = _bootstrap()),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text(ar ? 'إعادة المحاولة' : 'Retry'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: UellowColors.yellow,
                    foregroundColor: UellowColors.darkBrown,
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                  ),
                ),
              ]),
            ));
          }
          return _content(snap.data!);
        },
      ),
      bottomNavigationBar: FutureBuilder<_CheckoutData>(
        future: _data,
        builder: (_, snap) {
          UellowMoney? total;
          final tot = (snap.data?.summary?['cart']?['totals'] as Map?);
          if (tot != null) {
            double a(Map? m) => (m?['amount'] as num?)?.toDouble() ?? 0;
            final ship = snap.data != null ? _selectedShipping(snap.data!) : null;
            final pay = a(tot['subtotal'] as Map?) - a(tot['discount'] as Map?)
                + a(tot['tax'] as Map?) + a((ship ?? tot['shipping']) as Map?);
            final tmpl = (tot['subtotal'] ?? tot['total']) as Map?;
            if (tmpl != null) {
              final mm = Map<String, dynamic>.from(tmpl);
              mm['amount'] = pay;
              total = UellowMoney.fromJson(mm);
            }
          }
          return _PlaceOrderBar(
            busy: _placing,
            total: total,
            onPress: snap.hasData ? () => _placeOrder(snap.data!) : null,
          );
        },
      ),
    );
  }

  // The money map of the currently-selected shipping method (or null).
  Map<String, dynamic>? _selectedShipping(_CheckoutData d) {
    for (final m in d.shippingMethods) {
      if ((m['id'] as int?) == _selectedCarrierId) {
        final p = m['price'] ?? m['rate'];
        return p is Map ? p.cast<String, dynamic>() : null;
      }
    }
    return null;
  }

  Widget _content(_CheckoutData d) {
    final addrs = ((d.summary?['addresses'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    final geoCity = d.geoip?['city'] as String?;
    return ListView(children: [
      _section(num: 1, title: T.t('product.deliver_to'), child: _AddressList(
        addresses: addrs,
        selected: _selectedAddressId,
        geoCity: geoCity,
        guestMode: _guestMode,
        onSelect: (id) {
          setState(() => _selectedAddressId = id);
          UellowApi.instance.tokenStore.writeAddressId(id);
        },
      )),
      _section(num: 2, title: UellowApi.instance.lang == 'ar' ? 'طريقة الشحن' : 'SHIPPING METHOD',
          child: _ShippingMethodList(
            methods: d.shippingMethods,
            selected: _selectedCarrierId,
            onSelect: (id) => setState(() => _selectedCarrierId = id),
          )),
      _section(num: 3, title: UellowApi.instance.lang == 'ar' ? 'طريقة الدفع' : 'PAYMENT METHOD',
          child: _PaymentMethodGrid(
            methods: d.paymentMethods,
            selected: _selectedPaymentId,
            onSelect: (id) => setState(() => _selectedPaymentId = id),
          )),
      _section(num: null,
          title: UellowApi.instance.lang == 'ar' ? 'ملخص الطلب' : 'ORDER SUMMARY',
          child: _SumBlock(
            cart: (d.summary?['cart'] as Map?),
            shippingOverride: _selectedShipping(d),
          )),
      // No trailing gap — sticky Place Order bar hugs the last block.
    ]);
  }

  Widget _section({required int? num, required String title, required Widget child}) {
    return Container(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (num != null) Container(
            width: 22, height: 22, alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: UellowColors.yellowLight, shape: BoxShape.circle,
            ),
            child: Text('$num', style: const TextStyle(
                color: UellowColors.darkBrown,
                fontWeight: FontWeight.w900, fontSize: 12)),
          ),
          if (num != null) const SizedBox(width: 8),
          Text(title.toUpperCase(), style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w800, color: UellowColors.ink,
              letterSpacing: 0.5)),
        ]),
        const SizedBox(height: 12),
        child,
      ]),
    );
  }
}

class _CheckoutData {
  final Map<String, dynamic>? summary;
  final List<Map<String, dynamic>> shippingMethods;
  final List<Map<String, dynamic>> paymentMethods;
  final Map<String, dynamic>? geoip;
  _CheckoutData({
    required this.summary, required this.shippingMethods,
    required this.paymentMethods, required this.geoip,
  });
}

// ─── Addresses ─────────────────────────────────────────────────────


// v2.1.18 — an address is COMPLETE when its required fields are filled
// (fresh signups land in checkout with just a name). Incomplete addresses
// are flagged red and cannot be used to place an order.
bool addrComplete(Map<String, dynamic> a) {
  bool has(String k) => ((a[k] as String?) ?? '').trim().isNotEmpty;
  return has('phone') && has('street') && has('city');
}

class _AddressList extends StatelessWidget {
  const _AddressList({
    required this.addresses, required this.selected,
    required this.onSelect, required this.geoCity,
    this.guestMode = false,
  });
  final List<Map<String, dynamic>> addresses;
  final int? selected;
  final ValueChanged<int> onSelect;
  final String? geoCity;
  final bool guestMode;

  void _reloadCheckout(BuildContext context) {
    final state = context.findAncestorStateOfType<_CheckoutScreenState>();
    if (state != null && state.mounted) {
      state.setState(() { state._data = state._bootstrap(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    if (addresses.isEmpty) {
      return _EmptyAddressCta(geoCity: geoCity);
    }
    // v2.1.21 — guest checkout: add buttons stay on top (side by side)
    // and the written address shows below them with an Edit button.
    if (guestMode) {
      final cur = addresses.firstWhere(
        (a) => a['id'] == selected, orElse: () => addresses.first);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _EmptyAddressCta(geoCity: geoCity),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _addrCard(cur, selected: true)),
          const SizedBox(width: 8),
          // Edit pencil — reopens the form on the SAME guest record.
          Material(
            color: UellowColors.yellowSoft,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () async {
                await showModalBottomSheet(
                  context: context, isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => AddressFormSheet(
                    initial: UellowAddress.fromJson(cur),
                    onSaved: () {},
                  ),
                );
                _reloadCheckout(context);
              },
              child: const Padding(
                padding: EdgeInsets.all(11),
                child: Icon(Icons.edit_outlined, size: 18,
                    color: UellowColors.darkBrown),
              ),
            ),
          ),
        ]),
      ]);
    }
    // Only the selected address is shown; tap opens a picker.
    final current = addresses.firstWhere(
      (a) => a['id'] == selected, orElse: () => addresses.first);
    // v2.1.19 — an INCOMPLETE address (e.g. fresh OTP signup) opens the
    // completion form on the SAME record directly. This edit path only
    // exists while the address is incomplete — a one-time completion.
    if (!addrComplete(current)) {
      return GestureDetector(
        onTap: () async {
          // v2.1.20 — full add-address flow (map → detailed form) that
          // UPDATES this same record, not the small dialog.
          await Navigator.push(context, MaterialPageRoute(
            builder: (_) => AddressPickerScreen(
              editing: UellowAddress.fromJson(current),
            ),
          ));
          final state = context.findAncestorStateOfType<_CheckoutScreenState>();
          if (state != null && state.mounted) {
            state.setState(() { state._data = state._bootstrap(); });
          }
        },
        child: _addrCard(current, selected: true, showChevron: true),
      );
    }
    return GestureDetector(
      onTap: () => _openPicker(context),
      child: _addrCard(current, selected: true, showChevron: true),
    );
  }

  void _openPicker(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheet) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(sheet).size.height * 0.85),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AppBar(
            backgroundColor: Colors.white,
            elevation: 0.5,
            leading: IconButton(
              icon: const Icon(Icons.close, color: UellowColors.darkBrown),
              onPressed: () => Navigator.pop(sheet),
            ),
            title: Text(ar ? 'اختر عنواناً' : 'Select address', style: UT.h2),
          ),
          Flexible(child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: addresses.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final a = addresses[i];
              final on = a['id'] == selected;
              return GestureDetector(
                onTap: () { onSelect(a['id'] as int); Navigator.pop(sheet); },
                child: _addrCard(a, selected: on),
              );
            },
          )),
          // ── Sticky "+ Add new address" button at the bottom
          SafeArea(top: false, child: Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: UellowColors.border)),
            ),
            child: SizedBox(width: double.infinity, child: ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(sheet);
                final newId = await Navigator.push<int>(context, MaterialPageRoute(
                  builder: (_) => const AddressPickerScreen(),
                ));
                // Reload checkout + select the new address if one was created.
                final state = context.findAncestorStateOfType<_CheckoutScreenState>();
                if (state != null) {
                  state.setState(() { state._data = state._bootstrap(); });
                  if (newId != null) {
                    await state._data;
                    if (state.mounted) {
                      state.setState(() => state._selectedAddressId = newId);
                      UellowApi.instance.tokenStore.writeAddressId(newId);
                    }
                  }
                }
              },
              icon: const Icon(Icons.add_location_alt_outlined, size: 18),
              label: Text(ar ? 'إضافة عنوان جديد' : 'Add new address',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
              style: ElevatedButton.styleFrom(
                backgroundColor: UellowColors.darkBrown,
                foregroundColor: UellowColors.yellowLight,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12))),
              ),
            )),
          )),
        ]),
      ),
    );
  }

  Widget _addrCard(Map<String, dynamic> a,
      {required bool selected, bool showChevron = false}) {
    final ar = UellowApi.instance.lang == 'ar';
    final name = (a['name'] as String?) ?? '';
    final addr = [a['street'], a['street2'], a['city']]
        .where((s) => s != null && (s as String).isNotEmpty)
        .map((s) => s as String).join(', ');
    final phone = (a['phone'] as String?) ?? '';
    final complete = addrComplete(a);
    // Incomplete address is NEVER highlighted green — red outline instead.
    final on = selected && complete;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: on ? UellowColors.successBg
                  : (complete ? Colors.white : const Color(0xFFFFF5F5)),
        border: Border.all(
          color: on ? UellowColors.success
                    : (complete ? UellowColors.border : UellowColors.danger),
          width: (on || !complete) ? 2 : 1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 2),
            child: Icon(on ? Icons.location_on : Icons.location_on_outlined,
                color: on ? UellowColors.warn
                          : (complete ? UellowColors.muted : UellowColors.danger),
                size: 20)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: const TextStyle(
              fontWeight: FontWeight.w800, fontSize: 13, color: UellowColors.ink)),
          const SizedBox(height: 4),
          Text([addr, phone].where((s) => s.isNotEmpty).join(' · '),
              style: const TextStyle(fontSize: 12, color: UellowColors.text)),
          if (!complete) Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.error_outline, size: 13, color: UellowColors.danger),
              const SizedBox(width: 4),
              Text(ar ? 'أكمل عنوانك — الهاتف والشارع والمدينة مطلوبة'
                      : 'Complete your address — phone, street & city required',
                  style: const TextStyle(fontSize: 11,
                      color: UellowColors.danger, fontWeight: FontWeight.w800)),
            ]),
          ),
        ])),
        if (showChevron) const Icon(Icons.chevron_right, color: UellowColors.muted),
      ]),
    );
  }
}

// v2.0.72 (#416) — empty-state CTA that lets the user fill in their address
// from device GPS instead of typing. Uses FirstLaunchService's cached fix
// when possible, otherwise requests a fresh location reading.
class _EmptyAddressCta extends StatefulWidget {
  const _EmptyAddressCta({required this.geoCity});
  final String? geoCity;
  @override
  State<_EmptyAddressCta> createState() => _EmptyAddressCtaState();
}

class _EmptyAddressCtaState extends State<_EmptyAddressCta> {
  bool _busy = false;

  Future<void> _detect() async {
    setState(() => _busy = true);
    final ar = UellowApi.instance.lang == 'ar';
    // Ensure we either have a cached fix from first-launch or a fresh one
    // before opening the picker, so its map opens at the right spot.
    var fix = await FirstLaunchService.lastFix();
    fix ??= await FirstLaunchService.refreshNow();
    if (!mounted) return;
    setState(() => _busy = false);
    if (fix == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          ar ? 'تعذّر تحديد موقعك — فعّل صلاحية الموقع وحاول مرة أخرى'
             : 'Could not detect your location — enable Location and retry')));
      return;
    }
    // AddressPickerScreen calls Geolocator on its own; with the perm + GPS
    // cache primed it lands on the user's location instantly.
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(
        builder: (_) => const AddressPickerScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: UellowColors.yellowSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (widget.geoCity != null) Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            const Icon(Icons.public, size: 16, color: UellowColors.darkBrown),
            const SizedBox(width: 6),
            Flexible(child: Text(
                ar ? 'موقعك المكتشف: ${widget.geoCity}'
                   : 'Detected location: ${widget.geoCity}',
                style: const TextStyle(fontWeight: FontWeight.w800,
                    color: UellowColors.darkBrown))),
          ]),
        ),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ElevatedButton.icon(
            onPressed: _busy ? null : _detect,
            icon: _busy
                ? const SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2,
                        color: UellowColors.darkBrown))
                : const Icon(Icons.my_location, size: 16),
            label: Text(ar ? 'استخدم موقعي الحالي' : 'Use my current location'),
            style: ElevatedButton.styleFrom(
              backgroundColor: UellowColors.yellow,
              foregroundColor: UellowColors.darkBrown,
              elevation: 0,
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.pushNamed(context, '/addresses'),
            icon: const Icon(Icons.add_location_alt_outlined, size: 16),
            label: Text(ar ? 'إدخال يدوي' : 'Enter manually'),
            style: OutlinedButton.styleFrom(
              foregroundColor: UellowColors.darkBrown,
              side: const BorderSide(color: UellowColors.darkBrown, width: 1),
            ),
          ),
        ]),
      ]),
    );
  }
}

// ─── Shipping methods (real, zone-aware) ───────────────────────────

class _ShippingMethodList extends StatelessWidget {
  const _ShippingMethodList({
    required this.methods, required this.selected, required this.onSelect,
  });
  final List<Map<String, dynamic>> methods;
  final int? selected;
  final ValueChanged<int> onSelect;
  @override
  Widget build(BuildContext context) {
    final lang = UellowApi.instance.lang;
    if (methods.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(lang == 'ar'
            ? 'لا توجد طرق شحن متاحة لعنوانك.'
            : 'No shipping methods available for your address.',
            style: UT.body),
      );
    }
    return Column(children: methods.map((m) {
      final id = m['id'] as int;
      final on = selected == id;
      final name = ((m['name'] as Map?)?[lang] as String?)
          ?? ((m['name'] as Map?)?['en'] as String?) ?? 'Delivery';
      final priceMap = m['price'] as Map?;
      final price = priceMap == null
          ? null
          : UellowMoney.fromJson(Map<String, dynamic>.from(priceMap));
      // v2.1.18 — small public description under the method name.
      final descMap = m['description'] as Map?;
      final desc = (descMap?[lang] as String?)
          ?? (descMap?['en'] as String?) ?? '';
      final zone = m['zone'] as Map?;
      final cutoff = zone?['cutoff_time'] as String? ?? '';
      // v2.0.97 — informational per-zone delivery window (no pricing impact).
      final winMap = zone?['delivery_window'] as Map?;
      final window = (winMap?[lang] as String?)
          ?? (winMap?['en'] as String?) ?? '';
      return GestureDetector(
        onTap: () => onSelect(id),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: EdgeInsets.all(on ? 11 : 12),
          decoration: BoxDecoration(
            color: on ? UellowColors.successBg : Colors.white,
            border: Border.all(
              color: on ? UellowColors.success : UellowColors.border,
              width: on ? 2 : 1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            Icon(on ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: on ? UellowColors.success : UellowColors.muted, size: 18),
            const SizedBox(width: 10),
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: on ? UellowColors.successBg : UellowColors.border,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.local_shipping_outlined, size: 18,
                  color: on ? UellowColors.darkBrown : UellowColors.muted),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // v2.1.15 — smaller label per request (long names were loud).
              Text(name, style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w800, color: UellowColors.ink)),
              if (desc.isNotEmpty) Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(desc, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10.5,
                        color: UellowColors.muted)),
              ),
              if (cutoff.isNotEmpty) Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(lang == 'ar' ? 'اطلب قبل $cutoff' : 'Order before $cutoff',
                    style: const TextStyle(fontSize: 11, color: UellowColors.muted)),
              ),
              if (window.isNotEmpty) Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.schedule, size: 11, color: UellowColors.muted),
                  const SizedBox(width: 3),
                  Flexible(child: Text(
                      lang == 'ar' ? 'نافذة التوصيل: $window' : 'Delivery window: $window',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: UellowColors.muted))),
                ]),
              ),
            ])),
            Text(price?.format() ?? '—', style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w900,
                color: UellowColors.darkBrown)),
          ]),
        ),
      );
    }).toList());
  }
}

// ─── Payment methods (from Odoo) ────────────────────────────────────

class _PaymentMethodGrid extends StatelessWidget {
  const _PaymentMethodGrid({
    required this.methods, required this.selected, required this.onSelect,
  });
  final List<Map<String, dynamic>> methods;
  final int? selected;
  final ValueChanged<int> onSelect;
  IconData _iconFor(String code) {
    switch (code) {
      case 'knet':         return Icons.account_balance_outlined;
      case 'mada':         return Icons.credit_card;
      case 'naps':         return Icons.account_balance_outlined;
      case 'omannet':      return Icons.account_balance_outlined;
      case 'benefit':      return Icons.account_balance_outlined;
      case 'fawry':        return Icons.payments_outlined;
      case 'vodafone_cash':return Icons.phone_android_outlined;
      case 'stc_pay':      return Icons.smartphone_outlined;
      case 'apple_pay':    return Icons.phone_iphone_outlined;
      case 'cod':          return Icons.local_shipping_outlined;
      case 'tabby':        return Icons.event_note;
      case 'tamara':       return Icons.calendar_month;
      case 'taly':         return Icons.access_time;
      case 'card':         return Icons.credit_card;
      case 'upayments':    return Icons.account_balance_outlined;
      case 'wallet':       return Icons.account_balance_wallet_outlined;
      default:             return Icons.credit_card;
    }
  }
  Color _accentFor(String code) {
    switch (code) {
      case 'knet':         return const Color(0xFFD32F2F);  // KNET red
      case 'mada':         return const Color(0xFF84BD00);  // Mada green
      case 'tabby':        return const Color(0xFF42E0A0);  // Tabby green
      case 'tamara':       return const Color(0xFF4B0082);  // Tamara purple
      case 'apple_pay':    return Colors.black;
      case 'stc_pay':      return const Color(0xFF4F008C);  // STC purple
      case 'fawry':        return const Color(0xFFE89316);  // Fawry orange
      case 'vodafone_cash':return const Color(0xFFE60000);  // Vodafone red
      case 'naps':         return const Color(0xFFAF0028);  // NaPS maroon
      case 'omannet':      return const Color(0xFF006B3F);  // Oman green
      case 'benefit':      return const Color(0xFF0066B3);  // Bahrain blue
      case 'taly':         return const Color(0xFFEDA300);  // Taly yellow
      case 'cod':          return UellowColors.successDk;
      default:             return UellowColors.darkBrown;
    }
  }
  // Branded payment marks — recognizable, brand-coloured representations
  // (no logo files needed). Returns null for codes without a custom mark.
  Widget? _brandMark(String code) {
    switch (code) {
      case 'cod':
        return Row(mainAxisSize: MainAxisSize.min, children: const [
          Icon(Icons.payments_rounded, size: 20, color: UellowColors.successDk),
          SizedBox(width: 4),
          Text('Cash', style: TextStyle(fontWeight: FontWeight.w900,
              color: UellowColors.successDk, fontSize: 13)),
        ]);
      case 'knet':
        // v2.1.16 — the real KNET logo (bundled asset).
        return Image.asset('assets/images/pay_knet.png',
            height: 22, fit: BoxFit.contain);
      case 'card':
        return Row(mainAxisSize: MainAxisSize.min, children: [
          const Text('VISA', style: TextStyle(color: Color(0xFF1A1F71),
              fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, fontSize: 14)),
          const SizedBox(width: 6),
          SizedBox(width: 26, height: 16, child: Stack(children: [
            const Positioned(left: 0, child: CircleAvatar(radius: 8,
                backgroundColor: Color(0xFFEB001B))),
            Positioned(left: 10, child: CircleAvatar(radius: 8,
                backgroundColor: const Color(0xFFF79E1B).withValues(alpha: 0.9))),
          ])),
        ]);
      case 'apple_pay':
        return Row(mainAxisSize: MainAxisSize.min, children: const [
          Icon(Icons.apple, size: 20, color: Colors.black),
          Text(' Pay', style: TextStyle(color: Colors.black,
              fontWeight: FontWeight.w800, fontSize: 14)),
        ]);
      case 'google_pay':
        return Row(mainAxisSize: MainAxisSize.min, children: const [
          Text('G', style: TextStyle(color: Color(0xFF4285F4),
              fontWeight: FontWeight.w900, fontSize: 16)),
          Text(' Pay', style: TextStyle(color: Color(0xFF5F6368),
              fontWeight: FontWeight.w800, fontSize: 14)),
        ]);
    }
    return null;
  }

  // Always-on COD fallback — surface it even if backend didn't return any.
  static const _extras = [
    {'id': -1, 'code': 'cod', 'name': 'Cash on delivery'},
  ];
  @override
  Widget build(BuildContext context) {
    // Merge: server methods first, then COD (deduped by code)
    final codes = methods.map((m) => (m['code'] as String?) ?? '').toSet();
    final list = [
      ...methods,
      for (final e in _extras) if (!codes.contains(e['code'])) e,
    ];
    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(UellowApi.instance.lang == 'ar'
            ? 'لا توجد طرق دفع مُهيّأة.' : 'No payment methods configured.',
            style: UT.body),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2, crossAxisSpacing: 8,
        mainAxisSpacing: 8, childAspectRatio: 2.1,
      ),
      itemCount: list.length,
      itemBuilder: (_, i) {
        final m = list[i];
        final id = m['id'] as int;
        final on = selected == id;
        final code = (m['code'] as String?) ?? '';
        final ar = UellowApi.instance.lang == 'ar';
        final rawName = m['name'];
        final label = rawName is Map
            ? (rawName[ar ? 'ar' : 'en'] ?? rawName['en'] ?? code).toString()
            : (rawName as String?) ?? code;
        final logo = m['image'] as String?;
        final isTabby = code == 'tabby';
        return GestureDetector(
          onTap: () => onSelect(id),
          child: Container(
            decoration: BoxDecoration(
              color: on ? UellowColors.successBg : Colors.white,
              border: Border.all(
                color: on ? UellowColors.success : UellowColors.border,
                width: on ? 2 : 1),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            padding: const EdgeInsets.all(8),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (_brandMark(code) != null)
                SizedBox(height: 22, child: Center(child: _brandMark(code)))
              else if (isTabby) Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF42E0A0),  // Tabby green
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('tabby', style: TextStyle(
                    color: Color(0xFF1A1A1A), fontWeight: FontWeight.w900,
                    fontSize: 12, letterSpacing: -0.5)),
              )
              else if (logo != null) SizedBox(height: 22,
                  child: CachedNetworkImage(imageUrl: logo, fit: BoxFit.contain,
                      errorWidget: (_,__,___) => Icon(_iconFor(code),
                          size: 22, color: on ? UellowColors.darkBrown : UellowColors.muted)))
              else Icon(_iconFor(code), size: 22,
                  color: on ? UellowColors.darkBrown : UellowColors.muted),
              const SizedBox(height: 4),
              Text(label, textAlign: TextAlign.center, maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, height: 1.2,
                      fontWeight: FontWeight.w700,
                      color: on ? UellowColors.darkBrown : UellowColors.text)),
            ]),
          ),
        );
      },
    );
  }
}

// ─── Summary block ────────────────────────────────────────────────

class _SumBlock extends StatelessWidget {
  const _SumBlock({this.cart, this.shippingOverride});
  final Map? cart;
  // The selected shipping method's price (the order's amount_delivery is 0
  // until a carrier is applied at confirm, so the preview must use this).
  final Map<String, dynamic>? shippingOverride;
  @override
  Widget build(BuildContext context) {
    final totals = cart?['totals'] as Map?;
    final coupons = ((cart?['coupons'] as List?) ?? const []).cast<String>();
    double amt(Map? m) => (m?['amount'] as num?)?.toDouble() ?? 0;
    String moneyOf(Map? m) => m == null
        ? '—'
        : UellowMoney.fromJson(Map<String, dynamic>.from(m)).format();
    // Build a money string for a computed amount, reusing a currency template.
    String moneyAmt(double a) {
      final tmpl = (totals?['subtotal'] ?? totals?['total'] ?? shippingOverride) as Map?;
      if (tmpl == null) return a.toStringAsFixed(3);
      final mm = Map<String, dynamic>.from(tmpl);
      mm['amount'] = a;
      return UellowMoney.fromJson(mm).format();
    }
    final ar = UellowApi.instance.lang == 'ar';
    final subAmt = amt(totals?['subtotal'] as Map?);
    final taxAmt = amt(totals?['tax'] as Map?);
    final discAmt = amt(totals?['discount'] as Map?);
    final shipMap = shippingOverride ?? (totals?['shipping'] as Map?);
    final shipAmt = amt(shipMap);
    final payAmt = subAmt - discAmt + taxAmt + shipAmt;
    return Column(children: [
      _r(ar ? 'الإجمالي قبل الخصم' : 'Subtotal', moneyOf(totals?['subtotal'] as Map?)),
      _r(ar ? 'الشحن' : 'Delivery',
          shipAmt <= 0 ? (ar ? 'مجاني' : 'Free') : moneyOf(shipMap)),
      if (discAmt > 0) ...[
        if (coupons.isNotEmpty)
          for (final code in coupons)
            _r(ar ? 'كوبون $code' : 'Coupon $code',
                '− ${moneyOf(totals?['discount'] as Map?)}', success: true)
        else
          _r(ar ? 'الخصم' : 'Discount',
              '− ${moneyOf(totals?['discount'] as Map?)}', success: true),
      ],
      const Divider(height: 24),
      Row(children: [
        Expanded(child: Text(ar ? 'الإجمالي' : 'You pay', style: const TextStyle(
            fontWeight: FontWeight.w900, fontSize: 16, color: UellowColors.ink))),
        Text(moneyAmt(payAmt), style: const TextStyle(
            fontWeight: FontWeight.w900, fontSize: 18, color: UellowColors.ink)),
      ]),
    ]);
  }

  Widget _r(String l, String v, {bool success = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(l, style: const TextStyle(
            fontSize: 13, color: UellowColors.text))),
        Text(v, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
            color: success ? UellowColors.successDk : UellowColors.text)),
      ]),
    );
  }
}

// ─── Place order CTA (GREEN) ──────────────────────────────────────

class _PlaceOrderBar extends StatelessWidget {
  const _PlaceOrderBar({required this.onPress, required this.total, required this.busy});
  final VoidCallback? onPress;
  final UellowMoney? total;
  final bool busy;
  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: UellowColors.border)),
        boxShadow: [BoxShadow(
            color: Color(0x14000000), blurRadius: 10, offset: Offset(0, -2))],
      ),
      child: SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: busy ? null : onPress,
          style: ElevatedButton.styleFrom(
            backgroundColor: UellowColors.yellow,
            foregroundColor: UellowColors.darkBrown,
            padding: const EdgeInsets.symmetric(vertical: 16),
            elevation: 4,
            shadowColor: UellowColors.yellow.withValues(alpha: 0.4),
            shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(14))),
          ),
          child: busy
            ? const SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: UellowColors.darkBrown))
            : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.check_circle_outline, size: 18, color: UellowColors.darkBrown),
                const SizedBox(width: 8),
                Text(ar
                    ? 'تأكيد الطلب${total != null ? " · ${total!.format()}" : ""}'
                    : 'Place order${total != null ? " · ${total!.format()}" : ""}',
                    style: const TextStyle(fontSize: 15,
                        fontWeight: FontWeight.w900, color: UellowColors.darkBrown)),
              ]),
        )),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.lock_outline, size: 12, color: UellowColors.successDk),
          const SizedBox(width: 4),
          Text(ar
              ? 'دفع آمن · بياناتك محميه بالتشفير'
              : 'Secure checkout · Your data is encrypted',
              style: const TextStyle(fontSize: 11.5,
                  fontWeight: FontWeight.w700, color: UellowColors.successDk)),
        ]),
      ])),
    );
  }
}
