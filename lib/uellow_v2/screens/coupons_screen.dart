// =============================================================================
// CouponsScreen — real Odoo coupons (loyalty.card + active loyalty.program
// promotions) pulled from /api/mobile/v2/coupons. Tap a coupon row to open
// a details dialog with the full description + a single "Use" button that
// applies the code to the cart via /cart/apply-coupon.
// =============================================================================
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../api/uellow_api.dart';
import '../theme/uellow_theme.dart';

class CouponsScreen extends StatefulWidget {
  const CouponsScreen({super.key});
  @override
  State<CouponsScreen> createState() => _CouponsScreenState();
}

class _CouponsScreenState extends State<CouponsScreen> {
  Future<List<_Coupon>>? _future;
  int _tab = 0;       // 0=all available, 1=promotions, 2=cards

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<_Coupon>> _load() async {
    final token = await UellowApi.instance.tokenStore.readToken();
    final r = await http.get(
      Uri.parse('${UellowApi.instance.baseUrl}/api/mobile/v2/coupons'),
      headers: {
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );
    final body = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    if (body['success'] != true) {
      throw (body['error'] ?? 'Failed to load coupons').toString();
    }
    return (body['data'] as List)
        .map((e) => _Coupon.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return Scaffold(
      backgroundColor: UellowColors.bg,
      appBar: AppBar(
        leading: const BackButton(color: UellowColors.darkBrown),
        title: Text(ar ? 'كوبوناتي' : 'My Coupons', style: UT.h1),
      ),
      body: SafeArea(bottom: false, child: FutureBuilder<List<_Coupon>>(
        future: _future,
        builder: (_, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(
                color: UellowColors.darkBrown));
          }
          if (snap.hasError) {
            final err = snap.error.toString();
            // v2.1.68 — guests get the sign-in invite, not a raw
            // "Authentication required" screen.
            if (err.toLowerCase().contains('authentication')
                || err.contains('AUTH_REQUIRED')) {
              return _signInState(ar);
            }
            return _errorState(err, ar);
          }
          final all = snap.data ?? const <_Coupon>[];
          final filtered = _tab == 0
              ? all
              : _tab == 1
                  ? all.where((c) => c.kind == 'program' || c.category == 'promotion').toList()
                  : all.where((c) => c.kind == 'card').toList();
          return Column(children: [
            // Tabs
            Container(
              color: Colors.white,
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: UellowColors.border)),
              ),
              child: Row(children: [
                _tabBtn(ar ? 'الكل' : 'All', 0, all.length),
                _tabBtn(ar ? 'العروض' : 'Promotions', 1,
                    all.where((c) => c.kind == 'program' || c.category == 'promotion').length),
                _tabBtn(ar ? 'كوبوناتي' : 'My Codes', 2,
                    all.where((c) => c.kind == 'card').length),
              ]),
            ),
            Expanded(child: RefreshIndicator(
              onRefresh: _refresh,
              child: filtered.isEmpty
                ? ListView(children: [_emptyState(ar)])
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _CouponRow(
                        coupon: filtered[i],
                        onTap: () => _showCoupon(filtered[i])),
                  ),
            )),
          ]);
        },
      )),
    );
  }

  Widget _tabBtn(String label, int idx, int count) {
    final on = _tab == idx;
    return Expanded(child: GestureDetector(
      onTap: () => setState(() => _tab = idx),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(
            color: on ? UellowColors.yellow : Colors.transparent, width: 2,
          )),
        ),
        alignment: Alignment.center,
        child: Text('$label  ($count)', style: TextStyle(
          color: on ? UellowColors.darkBrown : UellowColors.muted,
          fontSize: 13, fontWeight: FontWeight.w700,
        )),
      ),
    ));
  }

  Widget _emptyState(bool ar) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(children: [
        const SizedBox(height: 60),
        const Icon(Icons.card_giftcard_outlined,
            size: 80, color: UellowColors.muted),
        const SizedBox(height: 16),
        Text(ar ? 'لا توجد كوبونات بعد' : 'No coupons yet',
            style: UT.h3),
        const SizedBox(height: 6),
        Text(ar
            ? 'العروض الترويجية وكوبونات الولاء ستظهر هنا.'
            : 'Promotions and loyalty rewards will appear here.',
            textAlign: TextAlign.center, style: UT.subtitle),
      ]),
    );
  }

  // v2.1.68 — friendly sign-in invite for guests (instead of the raw
  // "Authentication required" error). Returning from /auth reloads.
  Widget _signInState(bool ar) {
    return Center(child: Padding(
      padding: const EdgeInsets.all(30),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 84, height: 84,
          decoration: BoxDecoration(
            color: UellowColors.yellowFaint,
            shape: BoxShape.circle,
            border: Border.all(
                color: UellowColors.yellow.withValues(alpha: .5)),
          ),
          child: const Icon(Icons.card_giftcard, size: 42,
              color: UellowColors.darkBrown),
        ),
        const SizedBox(height: 16),
        Text(ar ? 'سجّل دخولك لمشاهدة كوبوناتك 🎟'
                : 'Sign in to see your coupons 🎟',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15,
                fontWeight: FontWeight.w900, color: UellowColors.ink)),
        const SizedBox(height: 6),
        Text(ar ? 'العروض والخصومات الخاصة بك تظهر هنا بعد تسجيل الدخول'
                : 'Your personal offers and discounts appear here after signing in',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, height: 1.5,
                color: UellowColors.muted)),
        const SizedBox(height: 18),
        ElevatedButton.icon(
          onPressed: () async {
            await Navigator.pushNamed(context, '/auth');
            if (mounted) _refresh();
          },
          icon: const Icon(Icons.login, size: 18),
          label: Text(ar ? 'تسجيل الدخول' : 'Sign in',
              style: const TextStyle(fontWeight: FontWeight.w900)),
          style: ElevatedButton.styleFrom(
            backgroundColor: UellowColors.yellow,
            foregroundColor: UellowColors.darkBrown,
            elevation: 0,
            padding: const EdgeInsets.symmetric(
                horizontal: 28, vertical: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ]),
    ));
  }

  Widget _errorState(String msg, bool ar) {
    return Center(child: Padding(
      padding: const EdgeInsets.all(30),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline, size: 56, color: UellowColors.muted),
        const SizedBox(height: 12),
        Text(msg, textAlign: TextAlign.center, style: UT.body),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _refresh,
          icon: const Icon(Icons.refresh, size: 18),
          label: Text(ar ? 'إعادة المحاولة' : 'Retry'),
        ),
      ]),
    ));
  }

  void _showCoupon(_Coupon c) {
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CouponDialog(coupon: c, onApplied: () {
        Navigator.pop(context);
        _refresh();
      }),
    );
  }
}

// ─── Model ────────────────────────────────────────────────────────────

class _Coupon {
  final int id;
  final String kind;              // 'card' | 'program'
  final Map<String, String> name; // {en, ar}
  final String discountText;
  final double minAmount;
  final String currency;
  final String? expiry;            // ISO date
  final String code;
  final Map<String, String> terms; // {en, ar}
  final String category;
  final bool usableNow;
  final bool isAuto;              // v2.1.56 — true ⇔ auto-applied program
  final String color;             // hex like '#F5C320'

  const _Coupon({
    required this.id, required this.kind,
    required this.name, required this.discountText,
    required this.minAmount, required this.currency,
    this.expiry, required this.code, required this.terms,
    required this.category, required this.usableNow,
    this.isAuto = false, required this.color,
  });

  factory _Coupon.fromJson(Map<String, dynamic> j) {
    Map<String, String> _bi(dynamic v) {
      if (v is Map) {
        return {
          'en': (v['en'] ?? '').toString(),
          'ar': (v['ar'] ?? v['en'] ?? '').toString(),
        };
      }
      return {'en': (v ?? '').toString(), 'ar': (v ?? '').toString()};
    }
    return _Coupon(
      id: (j['id'] ?? 0) as int,
      kind: (j['kind'] ?? 'card').toString(),
      name: _bi(j['name']),
      discountText: (j['discount_text'] ?? '—').toString(),
      minAmount: ((j['min_amount'] ?? 0) as num).toDouble(),
      currency: (j['currency'] ?? 'KD').toString(),
      expiry: j['expiry'] as String?,
      code: (j['code'] ?? '').toString(),
      terms: _bi(j['terms']),
      category: (j['category'] ?? 'general').toString(),
      usableNow: (j['usable_now'] ?? true) as bool,
      isAuto: (j['is_auto'] ?? false) as bool,
      color: (j['color'] ?? '#F5C320').toString(),
    );
  }

  String label(String lang) => name[lang] ?? name['en'] ?? '';
  String termsLabel(String lang) => terms[lang] ?? terms['en'] ?? '';
}

// ─── Coupon row ───────────────────────────────────────────────────────
// Per-type visual treatment:
//   gift_card  → teal gradient + ribbon, holographic shine
//   ewallet    → sky-blue with wallet imagery
//   coupons    → brand yellow with stamp
//   promotion  → warm orange with diagonal stripes
//   promo_code → purple with code chip
//   default    → brand yellow

class _CouponStyle {
  final List<Color> gradient;
  final Color accent;
  final IconData icon;
  final String emoji;
  final String ribbonEn, ribbonAr;
  final bool useStripes, useShine;
  const _CouponStyle({
    required this.gradient, required this.accent,
    required this.icon, required this.emoji,
    required this.ribbonEn, required this.ribbonAr,
    this.useStripes = false, this.useShine = false,
  });
}

_CouponStyle _styleFor(String kindOrCategory) {
  switch (kindOrCategory) {
    case 'gift_card':
      return const _CouponStyle(
        gradient: [Color(0xFF14B789), Color(0xFF0E8867)],
        accent: Color(0xFF0A6B52),
        icon: Icons.card_giftcard, emoji: '🎁',
        ribbonEn: 'GIFT CARD', ribbonAr: 'بطاقة هدية',
        useShine: true);
    case 'ewallet':
      return const _CouponStyle(
        gradient: [Color(0xFF2BA3E0), Color(0xFF1473B3)],
        accent: Color(0xFF0E5C8E),
        icon: Icons.account_balance_wallet, emoji: '💳',
        ribbonEn: 'E-WALLET', ribbonAr: 'محفظة',
        useShine: true);
    case 'coupons':
      return const _CouponStyle(
        gradient: [Color(0xFFFFD340), Color(0xFFF5C320)],
        accent: Color(0xFFB78A00),
        icon: Icons.confirmation_number, emoji: '🎟️',
        ribbonEn: 'COUPON', ribbonAr: 'كوبون');
    case 'promotion':
      return const _CouponStyle(
        gradient: [Color(0xFFFF8A3D), Color(0xFFE56811)],
        accent: Color(0xFFB54A00),
        icon: Icons.local_offer, emoji: '🔥',
        ribbonEn: 'PROMO', ribbonAr: 'عرض',
        useStripes: true);
    case 'promo_code':
      return const _CouponStyle(
        gradient: [Color(0xFF8B5CF6), Color(0xFF6D3FD8)],
        accent: Color(0xFF512EA8),
        icon: Icons.qr_code_2, emoji: '✨',
        ribbonEn: 'CODE', ribbonAr: 'كود');
    default:
      return const _CouponStyle(
        gradient: [Color(0xFFFFD340), Color(0xFFF5C320)],
        accent: Color(0xFFB78A00),
        icon: Icons.confirmation_number, emoji: '🎟️',
        ribbonEn: 'COUPON', ribbonAr: 'كوبون');
  }
}

class _CouponRow extends StatelessWidget {
  const _CouponRow({required this.coupon, required this.onTap});
  final _Coupon coupon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    final style = _styleFor(coupon.category);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: SizedBox(height: 116, child: Stack(children: [
          // Left "punch" — branded gradient with emoji + discount
          Positioned(top: 0, bottom: 0, left: 0, child: Container(
            width: 116,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: style.gradient),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16), bottomLeft: Radius.circular(16)),
            ),
            child: Stack(children: [
              if (style.useStripes) Positioned.fill(child: CustomPaint(
                  painter: _StripePainter(color: Colors.white.withValues(alpha: 0.13)))),
              if (style.useShine) Positioned(top: -20, left: -20,
                child: Container(width: 70, height: 70,
                  decoration: const BoxDecoration(
                    gradient: RadialGradient(
                      colors: [Color(0x55FFFFFF), Colors.transparent]),
                    shape: BoxShape.circle))),
              Padding(padding: const EdgeInsets.all(8),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(style.emoji, style: const TextStyle(fontSize: 22)),
                  const SizedBox(height: 2),
                  FittedBox(fit: BoxFit.scaleDown,
                    child: Text(coupon.discountText, textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900,
                          color: Colors.white, height: 1.1, letterSpacing: -0.2))),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(4)),
                    child: Text(ar ? style.ribbonAr : style.ribbonEn,
                        style: TextStyle(color: style.accent,
                            fontSize: 8, fontWeight: FontWeight.w900,
                            letterSpacing: 0.5)),
                  ),
                ])),
            ]),
          )),
          // Right body — white card
          Positioned(top: 0, bottom: 0, left: 116, right: 0, child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topRight: Radius.circular(16), bottomRight: Radius.circular(16)),
              boxShadow: [BoxShadow(color: Color(0x0D000000),
                  blurRadius: 6, offset: Offset(0, 2))],
            ),
            child: Padding(padding: const EdgeInsets.fromLTRB(18, 12, 14, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center, children: [
                Row(children: [
                  Icon(style.icon, size: 14, color: style.accent),
                  const SizedBox(width: 4),
                  Expanded(child: Text(coupon.label(ar ? 'ar' : 'en'),
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900,
                          fontSize: 13, color: UellowColors.ink, height: 1.25))),
                ]),
                const SizedBox(height: 4),
                if (coupon.minAmount > 0) Text(ar
                    ? 'الحد الأدنى ${coupon.minAmount.toStringAsFixed(0)} ${coupon.currency}'
                    : 'Min ${coupon.minAmount.toStringAsFixed(0)} ${coupon.currency}',
                    style: UT.small),
                const SizedBox(height: 4),
                Row(children: [
                  if (coupon.code.isNotEmpty) Flexible(child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: style.accent.withValues(alpha: 0.10),
                      border: Border.all(color: style.accent.withValues(alpha: 0.4),
                          style: BorderStyle.solid, width: 1),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(coupon.code,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontFamily: 'monospace',
                            fontWeight: FontWeight.w900, fontSize: 11,
                            color: style.accent, letterSpacing: 1.2)),
                  )),
                  // v2.1.56 — badge only for genuinely AUTO programs
                  // (an empty code alone used to mislabel issued-card
                  // coupons as auto-applied).
                  if (coupon.code.isEmpty && coupon.isAuto) Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(color: UellowColors.successBg,
                        borderRadius: BorderRadius.circular(5)),
                    child: Text(ar ? 'تطبيق تلقائي' : 'Auto-applied',
                        style: const TextStyle(color: UellowColors.successDk,
                            fontSize: 9.5, fontWeight: FontWeight.w900)),
                  ),
                ]),
                if (coupon.expiry != null) Padding(padding: const EdgeInsets.only(top: 4),
                  child: Row(children: [
                    Icon(Icons.schedule, size: 11, color: _expiryColor(coupon.expiry!)),
                    const SizedBox(width: 3),
                    Flexible(child: Text(_expiryText(coupon.expiry!, ar),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: _expiryColor(coupon.expiry!),
                            fontSize: 10.5, fontWeight: FontWeight.w800))),
                  ]),
                ),
              ]),
            ),
          )),
          // Ticket notches (perforation between the two halves)
          _notch(top: true), _notch(top: false),
        ])),
      ),
    );
  }

  Widget _notch({required bool top}) => Positioned(
    left: 116 - 7,
    top: top ? -7 : null, bottom: top ? null : -7,
    child: Container(width: 14, height: 14,
      decoration: const BoxDecoration(
        color: UellowColors.bg, shape: BoxShape.circle)),
  );

  static Color _readableTextColor(Color bg) {
    // YIQ contrast check — dark bg → light text, light bg → dark text.
    final luminance = bg.computeLuminance();
    return luminance > 0.55 ? UellowColors.darkBrown : Colors.white;
  }

  static String _expiryText(String iso, bool ar) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    final days = d.difference(DateTime.now()).inDays;
    if (days < 0) return ar ? 'منتهي الصلاحية' : 'Expired';
    if (days == 0) return ar ? 'ينتهي اليوم' : 'Expires today';
    if (days <= 7) return ar ? 'باقي $days أيام' : '$days days left';
    return ar ? 'ينتهي ${d.toIso8601String().split("T").first}'
              : 'Expires ${d.toIso8601String().split("T").first}';
  }

  static Color _expiryColor(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return UellowColors.muted;
    final days = d.difference(DateTime.now()).inDays;
    if (days < 0) return UellowColors.danger;
    if (days <= 3) return UellowColors.danger;
    if (days <= 14) return UellowColors.warn;
    return UellowColors.muted;
  }
}

class _StripePainter extends CustomPainter {
  const _StripePainter({required this.color});
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color..strokeWidth = 6;
    for (double x = -size.height; x < size.width + size.height; x += 14) {
      canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), p);
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ─── Coupon details dialog ────────────────────────────────────────────

class _CouponDialog extends StatefulWidget {
  const _CouponDialog({required this.coupon, required this.onApplied});
  final _Coupon coupon;
  final VoidCallback onApplied;
  @override
  State<_CouponDialog> createState() => _CouponDialogState();
}

class _CouponDialogState extends State<_CouponDialog> {
  bool _busy = false;
  String? _message;

  Future<void> _use() async {
    final ar = UellowApi.instance.lang == 'ar';
    final code = widget.coupon.code;
    if (code.isEmpty) {
      setState(() => _message = ar
          ? 'هذا العرض يُطبق تلقائياً على الطلبات المؤهلة.'
          : 'This promotion auto-applies to eligible orders.');
      return;
    }
    setState(() { _busy = true; _message = null; });
    try {
      final token = await UellowApi.instance.tokenStore.readToken();
      final r = await http.post(
        Uri.parse('${UellowApi.instance.baseUrl}/api/mobile/v2/cart/apply-coupon'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'code': code}),
      );
      final body = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (body['success'] == true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(ar ? 'تم تطبيق الكوبون على السلة' : 'Coupon applied to cart')));
        widget.onApplied();
        Navigator.pushNamed(context, '/cart');
      } else {
        setState(() => _message = (body['error'] ?? 'Failed').toString());
      }
    } catch (e) {
      setState(() => _message = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    final c = widget.coupon;
    final lang = ar ? 'ar' : 'en';
    final hex = c.color.replaceFirst('#', '');
    final accent = Color(0xFF000000 | (int.tryParse(hex, radix: 16) ?? 0xF5C320));
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20,
          MediaQuery.of(context).viewPadding.bottom + 16),
      child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(
          width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(color: UellowColors.border,
              borderRadius: BorderRadius.circular(2)))),
        // Discount headline + label
        Center(child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [accent, accent.withValues(alpha: 0.72)]),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.3),
                blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: Text(c.discountText, style: TextStyle(
              fontSize: 28, fontWeight: FontWeight.w900,
              color: _CouponRow._readableTextColor(accent), letterSpacing: -0.3)),
        )),
        const SizedBox(height: 16),
        Text(c.label(lang), style: UT.h2, textAlign: TextAlign.center),
        const SizedBox(height: 4),
        if (c.minAmount > 0) Center(child: Text(ar
            ? 'الحد الأدنى للطلب ${c.minAmount.toStringAsFixed(0)} ${c.currency}'
            : 'Minimum order ${c.minAmount.toStringAsFixed(0)} ${c.currency}',
            style: UT.subtitle)),
        const SizedBox(height: 14),
        // Code box
        if (c.code.isNotEmpty) Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: UellowColors.bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: UellowColors.border),
          ),
          child: Column(children: [
            Text(ar ? 'الكود' : 'CODE',
                style: const TextStyle(fontSize: 9.5, letterSpacing: 1,
                    fontWeight: FontWeight.w700, color: UellowColors.muted)),
            const SizedBox(height: 4),
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: c.code));
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    duration: const Duration(seconds: 1),
                    content: Text(ar ? 'تم نسخ الكود' : 'Code copied')));
              },
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(c.code, style: const TextStyle(fontFamily: 'monospace',
                    fontWeight: FontWeight.w900, fontSize: 22,
                    color: UellowColors.darkBrown, letterSpacing: 2)),
                const SizedBox(width: 8),
                const Icon(Icons.copy, size: 14, color: UellowColors.muted),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        if (c.termsLabel(lang).isNotEmpty) Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: UellowColors.yellowFaint,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: UellowColors.warnBg),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.info_outline, size: 16,
                color: UellowColors.darkBrown),
            const SizedBox(width: 8),
            Expanded(child: Text(c.termsLabel(lang), style: UT.small)),
          ]),
        ),
        if (c.expiry != null) Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(children: [
            const Icon(Icons.timer_outlined, size: 14,
                color: UellowColors.muted),
            const SizedBox(width: 6),
            Text(_CouponRow._expiryText(c.expiry!, ar),
                style: TextStyle(color: _CouponRow._expiryColor(c.expiry!),
                    fontSize: 12, fontWeight: FontWeight.w800)),
          ]),
        ),
        if (_message != null) Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(_message!, style: const TextStyle(
              color: UellowColors.danger, fontSize: 12,
              fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, child: ElevatedButton.icon(
          onPressed: _busy || !c.usableNow ? null : _use,
          icon: _busy
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2,
                      color: UellowColors.darkBrown))
              : const Icon(Icons.local_offer, size: 18),
          label: Text(_busy
              ? (ar ? 'جارٍ التطبيق…' : 'Applying…')
              : (ar ? 'استخدم الآن' : 'Use now'),
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          style: ElevatedButton.styleFrom(
            backgroundColor: UellowColors.yellow,
            foregroundColor: UellowColors.darkBrown,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(14))),
            elevation: 2,
          ),
        )),
      ]),
    );
  }
}
