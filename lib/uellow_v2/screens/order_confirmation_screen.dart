// =============================================================================
// OrderConfirmationScreen — shown after Place Order. Success or failure
// state with celebration animation, full order details, and a row of
// CTAs (Contact us / WhatsApp / Continue shopping).
// =============================================================================
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/uellow_api.dart';
import '../theme/uellow_theme.dart';
import 'auth_screen.dart';

class OrderConfirmationArgs {
  final bool success;
  final String? orderName;
  final int? orderId;
  final String? failureMessage;
  final Map<String, dynamic>? summary;
  // v2.1.21 — wallet cashback granted for paying online (null = none).
  final double? cashbackAmount;
  final String? cashbackCurrency;
  // v2.1.21 — guest checkout: render the full receipt + sign-up CTA
  // (guests can't open the order later, this page is their receipt).
  final bool guest;
  final Map<String, dynamic>? guestAddress;
  final String? guestShipping;
  final String? guestShippingPrice;
  final String? guestPayment;
  const OrderConfirmationArgs({
    required this.success, this.orderName, this.orderId,
    this.failureMessage, this.summary,
    this.cashbackAmount, this.cashbackCurrency,
    this.guest = false, this.guestAddress,
    this.guestShipping, this.guestShippingPrice, this.guestPayment,
  });
}

class OrderConfirmationScreen extends StatefulWidget {
  const OrderConfirmationScreen({super.key, required this.args});
  final OrderConfirmationArgs args;
  @override
  State<OrderConfirmationScreen> createState() => _OrderConfirmationScreenState();
}

class _OrderConfirmationScreenState extends State<OrderConfirmationScreen>
    with SingleTickerProviderStateMixin {
  // v2.1.18 — contact numbers come from Mobile App Settings (backend:
  // Mobile App Manager → Settings → WhatsApp Number / Support Phone),
  // falling back to the legacy hardcoded line.
  String _whatsapp = '+96522227777';
  String _phone = '+96522227777';

  String _digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  void _loadContacts() async {
    try {
      final s = await UellowApi.instance.settings.get();
      if (!mounted) return;
      setState(() {
        if (s.whatsapp.isNotEmpty) _whatsapp = s.whatsapp;
        if (s.supportPhone.isNotEmpty) _phone = s.supportPhone;
        if (s.whatsapp.isEmpty && s.supportPhone.isNotEmpty) _whatsapp = s.supportPhone;
        if (s.supportPhone.isEmpty && s.whatsapp.isNotEmpty) _phone = s.whatsapp;
      });
    } catch (_) {}
  }

  AnimationController? _ctrl;

  @override
  void initState() {
    super.initState();
    _loadContacts();
    if (widget.args.success) {
      _ctrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 3));
      _ctrl!.forward();
    }
  }

  @override
  void dispose() { _ctrl?.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UellowColors.bg,
      body: SafeArea(child: Stack(children: [
        if (widget.args.success && _ctrl != null)
          Positioned.fill(child: IgnorePointer(
              child: _Confetti(controller: _ctrl!))),
        widget.args.success
            ? (widget.args.guest ? _guestReceipt(context) : _success(context))
            : _failure(context),
      ])),
    );
  }

  Widget _success(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    final order = widget.args.orderName ?? '';
    return ListView(padding: const EdgeInsets.fromLTRB(20, 40, 20, 30), children: [
      Center(child: Container(
        width: 110, height: 110,
        decoration: BoxDecoration(
          color: UellowColors.successBg, shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: UellowColors.success.withValues(alpha: 0.3),
              blurRadius: 24, offset: const Offset(0, 8))],
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.check_circle, size: 72, color: UellowColors.success),
      )),
      const SizedBox(height: 20),
      Center(child: Text(ar ? 'تم استلام طلبك! 🎉' : 'Order received! 🎉',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900,
              color: UellowColors.ink))),
      const SizedBox(height: 6),
      Center(child: Text(ar
          ? 'سنرسل لك تحديثاً فور شحن الطلب'
          : "We'll text you the moment it ships",
          textAlign: TextAlign.center, style: UT.body)),
      const SizedBox(height: 22),
      // v2.1.21 — online-payment cashback congratulation (green banner).
      if ((widget.args.cashbackAmount ?? 0) > 0) Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: UellowColors.successBg,
          border: Border.all(color: UellowColors.success, width: 1.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          const Text('🎁', style: TextStyle(fontSize: 26)),
          const SizedBox(width: 12),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(ar ? 'مبروك! 🎉' : 'Congratulations! 🎉',
                style: const TextStyle(fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: UellowColors.successDk)),
            const SizedBox(height: 2),
            Text(ar
                ? 'تم وضع مبلغ ${widget.args.cashbackAmount!.toStringAsFixed(3)} '
                  '${widget.args.cashbackCurrency ?? "KWD"} في محفظتك '
                  'لأنك دفعت أونلاين'
                : '${widget.args.cashbackAmount!.toStringAsFixed(3)} '
                  '${widget.args.cashbackCurrency ?? "KWD"} was added to '
                  'your wallet for paying online',
                style: const TextStyle(fontSize: 12.5,
                    color: UellowColors.successDk, height: 1.4,
                    fontWeight: FontWeight.w600)),
          ])),
        ]),
      ),
      if (order.isNotEmpty) Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white, border: Border.all(color: UellowColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          const Icon(Icons.receipt_long_outlined, color: UellowColors.darkBrown),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(ar ? 'رقم الطلب' : 'Order number',
                style: const TextStyle(fontSize: 11, color: UellowColors.muted,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(order, style: const TextStyle(fontWeight: FontWeight.w900,
                fontSize: 15, color: UellowColors.ink)),
          ])),
          if (widget.args.orderId != null) TextButton.icon(
            onPressed: () => Navigator.pushReplacementNamed(context,
                '/order', arguments: {'id': widget.args.orderId}),
            icon: const Icon(Icons.arrow_forward, size: 14,
                color: UellowColors.darkBrown),
            label: Text(ar ? 'تفاصيل' : 'Details',
                style: const TextStyle(color: UellowColors.darkBrown,
                    fontWeight: FontWeight.w800)),
          ),
        ]),
      ),
      const SizedBox(height: 30),
      _ctaRow(context),
    ]);
  }

  // ── Guest receipt: full order details + sign-up CTA ────────────────
  Widget _guestReceipt(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    final cart = (widget.args.summary?['cart'] as Map?)?.cast<String, dynamic>();
    final lines = ((cart?['lines'] as List?) ?? const [])
        .cast<Map>().map((l) => l.cast<String, dynamic>()).toList();
    final totals = (cart?['totals'] as Map?)?.cast<String, dynamic>();
    String money(Map? m) {
      if (m == null) return '—';
      final a = (m['amount'] as num?)?.toDouble() ?? 0;
      return '${a.toStringAsFixed(3)} ${(m['symbol'] ?? 'KD')}';
    }
    final a = widget.args.guestAddress;
    Widget row(String k, String v, {bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(k, style: TextStyle(fontSize: bold ? 14 : 12.5,
            color: bold ? UellowColors.ink : UellowColors.muted,
            fontWeight: bold ? FontWeight.w900 : FontWeight.w600)),
        Text(v, style: TextStyle(fontSize: bold ? 15 : 12.5,
            color: UellowColors.ink,
            fontWeight: bold ? FontWeight.w900 : FontWeight.w700)),
      ]),
    );
    Widget card(String title, IconData icon, List<Widget> children) => Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: UellowColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 15, color: UellowColors.darkBrown),
          const SizedBox(width: 6),
          Text(title, style: const TextStyle(fontSize: 12.5,
              fontWeight: FontWeight.w900, color: UellowColors.darkBrown)),
        ]),
        const SizedBox(height: 8),
        ...children,
      ]),
    );
    return ListView(padding: const EdgeInsets.fromLTRB(20, 30, 20, 30), children: [
      Center(child: Container(
        width: 88, height: 88,
        decoration: BoxDecoration(
          color: UellowColors.successBg, shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: UellowColors.success.withValues(alpha: 0.3),
              blurRadius: 20, offset: const Offset(0, 6))],
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.check_circle, size: 58, color: UellowColors.success),
      )),
      const SizedBox(height: 14),
      Center(child: Text(ar ? 'تم استلام طلبك! 🎉' : 'Order received! 🎉',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900,
              color: UellowColors.ink))),
      const SizedBox(height: 4),
      Center(child: Text(
          ar ? 'احتفظ بهذه الصفحة — هذا إيصال طلبك كزائر'
             : 'Keep this page — this is your guest order receipt',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: UellowColors.muted))),
      const SizedBox(height: 18),
      // Order number
      card(ar ? 'رقم الطلب' : 'Order number', Icons.receipt_long_outlined, [
        Text(widget.args.orderName ?? '—', style: const TextStyle(
            fontSize: 18, fontWeight: FontWeight.w900,
            color: UellowColors.darkBrown, letterSpacing: 0.5)),
      ]),
      // Items
      if (lines.isNotEmpty) card(ar ? 'المنتجات' : 'Items',
          Icons.shopping_bag_outlined, [
        for (final l in lines) Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Expanded(child: Text(
                ((l['name'] as Map?)?[ar ? 'ar' : 'en']
                    ?? (l['name'] as Map?)?['en'] ?? '').toString(),
                maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5,
                    fontWeight: FontWeight.w700, color: UellowColors.ink))),
            const SizedBox(width: 8),
            Text('×${((l['qty'] as num?) ?? 1).toInt()}',
                style: const TextStyle(fontSize: 12,
                    color: UellowColors.muted, fontWeight: FontWeight.w800)),
            const SizedBox(width: 10),
            Text(money((l['total'] as Map?)?.cast<String, dynamic>()),
                style: const TextStyle(fontSize: 12.5,
                    fontWeight: FontWeight.w900, color: UellowColors.ink)),
          ]),
        ),
        const Divider(height: 16, color: UellowColors.border),
        row(ar ? 'المجموع الفرعي' : 'Subtotal',
            money((totals?['subtotal'] as Map?)?.cast<String, dynamic>())),
        if (widget.args.guestShippingPrice != null)
          row(ar ? 'التوصيل' : 'Delivery', widget.args.guestShippingPrice!),
        row(ar ? 'الإجمالي' : 'Total',
            money((totals?['total'] as Map?)?.cast<String, dynamic>()),
            bold: true),
      ]),
      // Address
      if (a != null) card(ar ? 'عنوان التوصيل' : 'Delivery address',
          Icons.location_on_outlined, [
        Text((a['name'] ?? '').toString(), style: const TextStyle(
            fontSize: 13, fontWeight: FontWeight.w800, color: UellowColors.ink)),
        const SizedBox(height: 2),
        Text([a['street'], a['street2'], a['city'], a['country']]
                .where((s) => s != null && '$s'.isNotEmpty).join(', '),
            style: const TextStyle(fontSize: 12, color: UellowColors.text)),
        if ((a['phone'] ?? '').toString().isNotEmpty) Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text((a['phone'] ?? '').toString(),
              style: const TextStyle(fontSize: 11.5, color: UellowColors.muted)),
        ),
      ]),
      // Shipping + payment
      card(ar ? 'الشحن والدفع' : 'Shipping & payment',
          Icons.local_shipping_outlined, [
        if (widget.args.guestShipping != null)
          row(ar ? 'وسيلة التوصيل' : 'Delivery method', widget.args.guestShipping!),
        if (widget.args.guestPayment != null)
          row(ar ? 'طريقة الدفع' : 'Payment', widget.args.guestPayment!),
      ]),
      const SizedBox(height: 8),
      // Sign-up CTA — convert the guest
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: UellowColors.yellowSoft,
          border: Border.all(color: UellowColors.yellow, width: 1.5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(children: [
          Text(ar ? '✨ أنشئ حساباً لمتابعة طلبك'
                  : '✨ Create an account to track this order',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900,
                  color: UellowColors.darkBrown)),
          const SizedBox(height: 4),
          Text(ar
              ? 'تابع حالة التوصيل، اجمع نقاط الولاء، واحفظ عنوانك للمرات القادمة'
              : 'Track delivery, earn loyalty points, and save your address',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11.5, color: UellowColors.text)),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: ElevatedButton.icon(
            onPressed: () async { await showAuthSheet(context); },
            icon: const Icon(Icons.login, size: 16),
            label: Text(ar ? 'تسجيل الدخول / حساب جديد' : 'Sign in / Register',
                style: const TextStyle(fontWeight: FontWeight.w900)),
            style: ElevatedButton.styleFrom(
              backgroundColor: UellowColors.yellow,
              foregroundColor: UellowColors.darkBrown,
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
          )),
        ]),
      ),
      const SizedBox(height: 12),
      SizedBox(width: double.infinity, child: OutlinedButton.icon(
        onPressed: () => Navigator.of(context)
            .pushNamedAndRemoveUntil('/home', (_) => false),
        icon: const Icon(Icons.storefront_outlined, size: 16,
            color: UellowColors.darkBrown),
        label: Text(ar ? 'متابعة التسوق' : 'Continue shopping',
            style: const TextStyle(color: UellowColors.ink,
                fontWeight: FontWeight.w800)),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 13),
          side: const BorderSide(color: UellowColors.border, width: 1.5),
        ),
      )),
    ]);
  }

  Widget _failure(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return ListView(padding: const EdgeInsets.fromLTRB(20, 40, 20, 30), children: [
      Center(child: Container(
        width: 110, height: 110,
        decoration: BoxDecoration(
          color: UellowColors.dangerBg, shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.error_outline, size: 64, color: UellowColors.danger),
      )),
      const SizedBox(height: 20),
      Center(child: Text(ar ? 'فشل تأكيد الطلب' : 'Order failed',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900,
              color: UellowColors.ink))),
      const SizedBox(height: 8),
      Center(child: Text(widget.args.failureMessage
          ?? (ar ? 'حدث خطأ غير متوقع. حاول مرة أخرى أو تواصل معنا.'
                 : 'Something went wrong. Please try again or contact us.'),
          textAlign: TextAlign.center, style: UT.body)),
      const SizedBox(height: 24),
      _ctaRow(context),
    ]);
  }

  Widget _ctaRow(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return Column(children: [
      // Cart is preserved on a failed/cancelled payment — let the user retry.
      SizedBox(width: double.infinity, child: ElevatedButton.icon(
        onPressed: () =>
            Navigator.of(context).pushReplacementNamed('/checkout'),
        icon: const Icon(Icons.lock_outline, size: 16),
        label: Text(ar ? 'العودة إلى الدفع' : 'Back to checkout',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
        style: ElevatedButton.styleFrom(
          backgroundColor: UellowColors.yellow,
          foregroundColor: UellowColors.darkBrown,
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      )),
      const SizedBox(height: 10),
      SizedBox(width: double.infinity, child: OutlinedButton.icon(
        onPressed: () => Navigator.of(context).pushReplacementNamed('/cart'),
        icon: const Icon(Icons.shopping_cart_outlined, size: 16,
            color: UellowColors.darkBrown),
        label: Text(ar ? 'العودة إلى السلة' : 'Back to cart',
            style: const TextStyle(color: UellowColors.ink,
                fontWeight: FontWeight.w800)),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: const BorderSide(color: UellowColors.border, width: 1.5),
        ),
      )),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: OutlinedButton.icon(
          onPressed: () => _open('https://wa.me/${_digits(_whatsapp)}'),
          icon: const Icon(Icons.chat_bubble_outline, size: 16,
              color: Color(0xFF25D366)),
          label: Text(ar ? 'واتساب' : 'WhatsApp',
              style: const TextStyle(color: UellowColors.ink,
                  fontWeight: FontWeight.w800)),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            side: const BorderSide(color: UellowColors.border, width: 1.5),
          ),
        )),
        const SizedBox(width: 10),
        Expanded(child: OutlinedButton.icon(
          onPressed: () => _open('tel:+${_digits(_phone)}'),
          icon: const Icon(Icons.phone, size: 16, color: UellowColors.darkBrown),
          label: Text(ar ? 'اتصل بنا' : 'Contact us',
              style: const TextStyle(color: UellowColors.ink,
                  fontWeight: FontWeight.w800)),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            side: const BorderSide(color: UellowColors.border, width: 1.5),
          ),
        )),
      ]),
    ]);
  }

  Future<void> _open(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {/* swallow — device just can't handle the URL */}
  }
}

// ─── Tiny confetti painter (no extra dep) ──────────────────────────

class _Confetti extends StatelessWidget {
  const _Confetti({required this.controller});
  final AnimationController controller;
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) => CustomPaint(
        painter: _ConfettiPainter(controller.value),
        size: Size.infinite,
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.t);
  final double t;
  final _rng = math.Random(42);
  static const _colors = [
    UellowColors.yellow, UellowColors.success, UellowColors.danger,
    Color(0xFF1DA1F2), Color(0xFFFF6F00),
  ];
  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(42);
    for (var i = 0; i < 60; i++) {
      final x = rng.nextDouble() * size.width;
      final fallSpeed = 0.4 + rng.nextDouble() * 0.8;
      final yStart = -20 - rng.nextDouble() * 200;
      final y = yStart + t * size.height * 1.4 * fallSpeed;
      if (y < -20 || y > size.height + 20) continue;
      final color = _colors[i % _colors.length];
      final paint = Paint()..color = color;
      final w = 6 + rng.nextDouble() * 6;
      final h = 8 + rng.nextDouble() * 8;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(t * 6 + i.toDouble());
      canvas.drawRect(Rect.fromLTWH(-w/2, -h/2, w, h), paint);
      canvas.restore();
    }
  }
  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => old.t != t;
}
