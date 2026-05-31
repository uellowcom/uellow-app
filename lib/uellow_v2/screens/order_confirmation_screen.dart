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

class OrderConfirmationArgs {
  final bool success;
  final String? orderName;
  final int? orderId;
  final String? failureMessage;
  final Map<String, dynamic>? summary;
  const OrderConfirmationArgs({
    required this.success, this.orderName, this.orderId,
    this.failureMessage, this.summary,
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
  AnimationController? _ctrl;

  @override
  void initState() {
    super.initState();
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
        widget.args.success ? _success(context) : _failure(context),
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
      SizedBox(width: double.infinity, child: ElevatedButton.icon(
        onPressed: () =>
            Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false),
        icon: const Icon(Icons.shopping_bag_outlined, size: 16),
        label: Text(ar ? 'متابعة التسوق' : 'Continue shopping',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
        style: ElevatedButton.styleFrom(
          backgroundColor: UellowColors.yellow,
          foregroundColor: UellowColors.darkBrown,
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      )),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: OutlinedButton.icon(
          onPressed: () => _open('https://wa.me/96522227777'),
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
          onPressed: () => _open('tel:+96522227777'),
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
