// =============================================================================
// Beena rich cards (v2.1.78) — renders the AI's structured `extra.*` tool
// results as professional cards, mirroring the website chat. Each card is a
// compact summary with a CTA that deep-links into the app's existing rich
// screens (product, order tracking, Smart Fit, Try-On, loyalty, cart…).
//
// Backend already returns every block in `extra` (the mobile /beena/chat
// passthrough forwards it untouched); the app simply renders them here.
//
// Entry point: buildBeenaCards(context, extra, ar, onSend) → List<Widget>
// inserted under the AI text bubble.
// =============================================================================
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/uellow_api.dart';
import '../router/uellow_router.dart';
import '../theme/uellow_theme.dart';

// ── shared helpers ──────────────────────────────────────────────────────────
String _abs(String url) =>
    url.startsWith('/') ? '${UellowApi.instance.baseUrl}$url' : url;

String _locName(dynamic v, bool ar) {
  if (v is Map) {
    return (v[ar ? 'ar' : 'en'] ?? v['en_US'] ?? v['en'] ??
            (v.values.isNotEmpty ? v.values.first : '') ?? '')
        .toString();
  }
  return (v ?? '').toString();
}

String _kd(num? v, bool ar) =>
    '${(v ?? 0).toDouble().toStringAsFixed(3)} ${ar ? 'د.ك' : 'KD'}';

int _int(dynamic v) =>
    v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

double _dbl(dynamic v) =>
    v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

Future<void> _launch(String url) async {
  if (url.isEmpty) return;
  try {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {}
}

Color _fitColor(String c) {
  switch (c) {
    case 'green':  return const Color(0xFF2E9E6B);
    case 'yellow': return const Color(0xFFE6A817);
    case 'orange': return const Color(0xFFE08A17);
    case 'red':    return const Color(0xFFD2604E);
  }
  return UellowColors.muted;
}

/// Build the list of rich cards for one AI turn's `extra`.
List<Widget> buildBeenaCards(BuildContext context, Map<String, dynamic>? extra,
    bool ar, void Function(String) onSend) {
  if (extra == null || extra.isEmpty) return const [];
  final out = <Widget>[];
  void add(Widget? w) { if (w != null) out.add(w); }

  // products are rendered by the existing rail in beena_screen — skip here.
  if (extra['upsell'] is List && (extra['upsell'] as List).isNotEmpty) {
    add(_UpsellRail(items: (extra['upsell'] as List)
        .whereType<Map>().map((e) => e.cast<String, dynamic>()).toList(), ar: ar));
  }
  if (extra['order_status'] is Map) {
    add(_OrderStatusCard(d: (extra['order_status'] as Map).cast<String, dynamic>(), ar: ar));
  }
  if (extra['orders_list'] is List && (extra['orders_list'] as List).isNotEmpty) {
    add(_OrdersListCard(items: (extra['orders_list'] as List)
        .whereType<Map>().map((e) => e.cast<String, dynamic>()).toList(), ar: ar));
  }
  if (extra['tryon'] is Map) {
    add(_TryOnCard(d: (extra['tryon'] as Map).cast<String, dynamic>(), ar: ar));
  }
  if (extra['fit_check'] is Map) {
    add(_FitCheckCard(d: (extra['fit_check'] as Map).cast<String, dynamic>(), ar: ar));
  }
  if (extra['size_rec'] is Map) {
    add(_SizeRecCard(d: (extra['size_rec'] as Map).cast<String, dynamic>(), ar: ar));
  }
  if (extra['cart_view'] is Map) {
    add(_CartCard(d: (extra['cart_view'] as Map).cast<String, dynamic>(), ar: ar));
  } else if (extra['cart'] is Map) {
    add(_CartAddedCard(d: (extra['cart'] as Map).cast<String, dynamic>(), ar: ar));
  }
  if (extra['loyalty'] is Map) {
    add(_LoyaltyCard(d: (extra['loyalty'] as Map).cast<String, dynamic>(), ar: ar));
  }
  if (extra['reviewers'] is Map) {
    add(_ReviewersCard(d: (extra['reviewers'] as Map).cast<String, dynamic>(),
        ar: ar, onSend: onSend));
  }
  if (extra['company_location'] is Map) {
    add(_LocationCard(d: (extra['company_location'] as Map).cast<String, dynamic>(), ar: ar));
  }
  if (extra['location'] is Map) {
    add(_LocationCard(d: (extra['location'] as Map).cast<String, dynamic>(), ar: ar));
  }
  if (extra['locations'] is List) {
    for (final l in (extra['locations'] as List).whereType<Map>()) {
      add(_LocationCard(d: l.cast<String, dynamic>(), ar: ar));
    }
  }
  // Order created + payment (order / payment / payment_options / quote / checkout)
  if (extra['order'] is Map || extra['payment'] is Map) {
    add(_PaymentCard(
        order: (extra['order'] as Map?)?.cast<String, dynamic>(),
        payment: (extra['payment'] as Map?)?.cast<String, dynamic>(), ar: ar));
  }
  if (extra['payment_options'] is Map) {
    add(_PaymentOptionsCard(d: (extra['payment_options'] as Map).cast<String, dynamic>(), ar: ar));
  }
  if (extra['quote'] is Map) {
    add(_QuoteCard(d: (extra['quote'] as Map).cast<String, dynamic>(), ar: ar));
  }
  if (extra['checkout'] is Map) {
    add(_CheckoutCard(d: (extra['checkout'] as Map).cast<String, dynamic>(), ar: ar));
  }
  return out;
}

// ── reusable card shell ─────────────────────────────────────────────────────
class _Shell extends StatelessWidget {
  const _Shell({required this.accent, required this.icon, required this.title,
      required this.child, this.cta, this.onCta, this.ctaIcon});
  final Color accent;
  final IconData icon;
  final String title;
  final Widget child;
  final String? cta;
  final VoidCallback? onCta;
  final IconData? ctaIcon;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: UellowColors.border),
        boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 6, offset: Offset(0, 2))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: accent.withValues(alpha: 0.10),
          child: Row(children: [
            Icon(icon, size: 15, color: accent),
            const SizedBox(width: 6),
            Expanded(child: Text(title, style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w900, color: accent))),
          ]),
        ),
        Padding(padding: const EdgeInsets.fromLTRB(12, 10, 12, 12), child: child),
        if (cta != null) Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: SizedBox(width: double.infinity, child: ElevatedButton.icon(
            onPressed: onCta,
            icon: Icon(ctaIcon ?? Icons.arrow_forward, size: 15),
            label: Text(cta!, style: const TextStyle(
                fontWeight: FontWeight.w800, fontSize: 12.5)),
            style: ElevatedButton.styleFrom(
              backgroundColor: UellowColors.yellow,
              foregroundColor: UellowColors.darkBrown,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
          )),
        ),
      ]),
    );
  }
}

Widget _kv(String k, String v) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 2),
  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text('$k ', style: const TextStyle(fontSize: 11.5, color: UellowColors.muted)),
    Expanded(child: Text(v, style: const TextStyle(
        fontSize: 11.5, fontWeight: FontWeight.w700, color: UellowColors.ink))),
  ]),
);

// ── ORDER STATUS / DELIVERY TRACKING ────────────────────────────────────────
class _OrderStatusCard extends StatelessWidget {
  const _OrderStatusCard({required this.d, required this.ar});
  final Map<String, dynamic> d;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    final timeline = (d['timeline'] as List?)?.whereType<Map>().toList() ?? const [];
    final orderId = _int(d['order_id']);
    final failed = d['is_failed'] == true;
    final accent = failed ? UellowColors.danger : const Color(0xFF2F6E62);
    return _Shell(
      accent: accent,
      icon: Icons.local_shipping_outlined,
      title: '${ar ? 'حالة الطلب' : 'Order'} ${d['order_name'] ?? ''}',
      cta: ar ? 'تتبع الطلب' : 'Track order',
      ctaIcon: Icons.map_outlined,
      onCta: orderId > 0
          ? () => Navigator.pushNamed(context, Routes.order, arguments: {'id': orderId})
          : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // status pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text((d['delivery_status'] ?? d['state'] ?? '').toString(),
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: accent)),
        ),
        const SizedBox(height: 8),
        // mini timeline
        for (final t in timeline)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                  t['status'] == 'done' ? Icons.check_circle
                      : t['status'] == 'current' ? Icons.radio_button_checked
                      : t['status'] == 'failed' ? Icons.cancel
                      : Icons.radio_button_unchecked,
                  size: 14,
                  color: t['status'] == 'done' ? const Color(0xFF2E9E6B)
                      : t['status'] == 'current' ? accent
                      : t['status'] == 'failed' ? UellowColors.danger
                      : UellowColors.border),
            ),
            const SizedBox(width: 8),
            Expanded(child: Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text((t['label'] ?? '').toString(), style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: t['status'] == 'current' ? FontWeight.w800 : FontWeight.w500,
                  color: t['status'] == 'pending' ? UellowColors.muted : UellowColors.ink)),
            )),
          ]),
        const SizedBox(height: 4),
        if ((d['driver'] ?? '').toString().isNotEmpty)
          _kv(ar ? 'المندوب:' : 'Courier:', d['driver'].toString()),
        if ((d['driver_phone'] ?? '').toString().isNotEmpty)
          InkWell(
            onTap: () => _launch('tel:${d['driver_phone']}'),
            child: _kv(ar ? 'الهاتف:' : 'Phone:', d['driver_phone'].toString()),
          ),
        if ((d['eta'] ?? '').toString().isNotEmpty)
          _kv(ar ? 'الوصول المتوقع:' : 'ETA:', d['eta'].toString()),
        if ((d['tracking_number'] ?? '').toString().isNotEmpty)
          _kv(ar ? 'رقم التتبع:' : 'Tracking:', d['tracking_number'].toString()),
        _kv(ar ? 'الإجمالي:' : 'Total:', _kd(_dbl(d['amount']), ar)),
      ]),
    );
  }
}

class _OrdersListCard extends StatelessWidget {
  const _OrdersListCard({required this.items, required this.ar});
  final List<Map<String, dynamic>> items;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    return _Shell(
      accent: const Color(0xFF2F6E62),
      icon: Icons.receipt_long_outlined,
      title: ar ? 'طلباتي' : 'My orders',
      cta: ar ? 'كل الطلبات' : 'All orders',
      onCta: () => Navigator.pushNamed(context, Routes.orders),
      child: Column(children: [
        for (final o in items.take(5))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Expanded(child: Text((o['name'] ?? '').toString(),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                      color: UellowColors.ink))),
              if ((o['state'] ?? '').toString().isNotEmpty)
                Padding(padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text((o['state']).toString(),
                      style: const TextStyle(fontSize: 10.5, color: UellowColors.muted))),
              Text(_kd(_dbl(o['amount']), ar), style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w900, color: UellowColors.darkBrown)),
            ]),
          ),
      ]),
    );
  }
}

// ── VIRTUAL TRY-ON ──────────────────────────────────────────────────────────
class _TryOnCard extends StatelessWidget {
  const _TryOnCard({required this.d, required this.ar});
  final Map<String, dynamic> d;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    final state = (d['state'] ?? '').toString();
    final pid = _int(d['product_id']);
    final img = _abs((d['product_image_url'] ?? '').toString());
    final ctaReady = state == 'ready' || state == 'needs_photo';
    return _Shell(
      accent: const Color(0xFF7A4FE0),
      icon: Icons.checkroom_outlined,
      title: ar ? 'التجربة الافتراضية' : 'Virtual Try-On',
      cta: state == 'needs_login'
          ? (ar ? 'تسجيل الدخول' : 'Sign in')
          : ctaReady ? (ar ? 'ابدأ التجربة' : 'Start try-on') : null,
      ctaIcon: Icons.auto_awesome,
      onCta: state == 'needs_login'
          ? () => Navigator.pushNamed(context, Routes.auth)
          : ctaReady && pid > 0
              ? () => Navigator.pushNamed(context, Routes.tryOn, arguments: {'id': pid})
              : null,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (img.isNotEmpty) Padding(
          padding: const EdgeInsets.only(right: 10),
          child: ClipRRect(borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(imageUrl: img, width: 56, height: 56,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => const SizedBox(width: 56, height: 56))),
        ),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if ((d['product_name'] ?? '').toString().isNotEmpty)
            Text(_locName(d['product_name'], ar), maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800,
                    color: UellowColors.ink)),
          if ((d['message'] ?? '').toString().isNotEmpty) Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(d['message'].toString(), style: const TextStyle(
                fontSize: 11.5, height: 1.4, color: UellowColors.muted)),
          ),
        ])),
      ]),
    );
  }
}

// ── FIT CHECK (Smart Fit gauge) ─────────────────────────────────────────────
class _FitCheckCard extends StatelessWidget {
  const _FitCheckCard({required this.d, required this.ar});
  final Map<String, dynamic> d;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    final state = (d['state'] ?? '').toString();
    final pid = _int(d['product_id']);
    if (state != 'ready') {
      return _Shell(
        accent: const Color(0xFF2E9E6B),
        icon: Icons.straighten,
        title: ar ? 'مقاسي الذكي' : 'Smart Fit',
        cta: state == 'needs_login'
            ? (ar ? 'تسجيل الدخول' : 'Sign in')
            : (ar ? 'أدخل قياساتك' : 'Enter measurements'),
        onCta: state == 'needs_login'
            ? () => Navigator.pushNamed(context, Routes.auth)
            : () => Navigator.pushNamed(context, Routes.smartFit,
                arguments: pid > 0 ? {'id': pid} : null),
        child: Text((d['message'] ?? '').toString(), style: const TextStyle(
            fontSize: 11.5, height: 1.4, color: UellowColors.muted)),
      );
    }
    final pct = _int(d['overall_pct']);
    final col = _fitColor((d['fit_color'] ?? '').toString());
    final areas = (d['areas'] as List?)?.whereType<Map>().toList() ?? const [];
    return _Shell(
      accent: col,
      icon: Icons.straighten,
      title: '${ar ? 'المقاس الموصى' : 'Recommended'}: ${d['size'] ?? ''}',
      cta: ar ? 'تفاصيل المقاس' : 'Fit details',
      onCta: () => Navigator.pushNamed(context, Routes.smartFit,
          arguments: pid > 0 ? {'id': pid} : null),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          SizedBox(width: 44, height: 44, child: Stack(alignment: Alignment.center, children: [
            CircularProgressIndicator(value: pct / 100, strokeWidth: 5,
                backgroundColor: const Color(0xFFEDEDED),
                valueColor: AlwaysStoppedAnimation(col)),
            Text('$pct%', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: col)),
          ])),
          const SizedBox(width: 12),
          Expanded(child: Text((d['fit_label'] ?? '').toString(), style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w900, color: col))),
        ]),
        if (areas.isNotEmpty) const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final a in areas)
            _chip('${a['name'] ?? a['label'] ?? ''}: ${_verdict(a['verdict'], ar)}',
                _verdictColor((a['verdict'] ?? '').toString())),
        ]),
      ]),
    );
  }
  static String _verdict(dynamic v, bool ar) {
    switch ((v ?? '').toString()) {
      case 'tight':       return ar ? 'ضيّق' : 'tight';
      case 'loose':       return ar ? 'واسع' : 'loose';
      case 'comfortable': return ar ? 'مناسب' : 'good';
    }
    return (v ?? '').toString();
  }
  static Color _verdictColor(String v) {
    if (v == 'tight') return const Color(0xFFD2604E);
    if (v == 'loose') return const Color(0xFFE6A817);
    return const Color(0xFF2E9E6B);
  }
}

Widget _chip(String t, Color c) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
  decoration: BoxDecoration(color: c.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999)),
  child: Text(t, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: c)),
);

class _SizeRecCard extends StatelessWidget {
  const _SizeRecCard({required this.d, required this.ar});
  final Map<String, dynamic> d;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    final results = (d['results'] as List?)?.whereType<Map>().toList() ?? const [];
    if (results.isEmpty) {
      final msg = (d['message'] ?? '').toString();
      if (msg.isEmpty) return const SizedBox.shrink();
      return _Shell(
        accent: const Color(0xFF2E9E6B), icon: Icons.straighten,
        title: ar ? 'توصية المقاس' : 'Size recommendation',
        cta: d['logged_in'] == false ? (ar ? 'تسجيل الدخول' : 'Sign in') : null,
        onCta: d['logged_in'] == false ? () => Navigator.pushNamed(context, Routes.auth) : null,
        child: Text(msg, style: const TextStyle(fontSize: 11.5, height: 1.4, color: UellowColors.muted)),
      );
    }
    return _Shell(
      accent: const Color(0xFF2E9E6B), icon: Icons.straighten,
      title: ar ? 'توصية المقاس' : 'Size recommendation',
      child: Wrap(spacing: 6, runSpacing: 6, children: [
        for (final r in results)
          _chip('${r['size']} · ${r['fit_label'] ?? ''}'
              '${r['recommended'] == true ? ' ✓' : ''}',
              _fitColor((r['fit_color'] ?? '').toString())),
      ]),
    );
  }
}

// ── LOYALTY ─────────────────────────────────────────────────────────────────
class _LoyaltyCard extends StatelessWidget {
  const _LoyaltyCard({required this.d, required this.ar});
  final Map<String, dynamic> d;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    if (d['logged_in'] == false) {
      return _Shell(
        accent: UellowColors.darkBrown, icon: Icons.card_giftcard,
        title: ar ? 'نقاط الولاء' : 'Loyalty points',
        cta: ar ? 'تسجيل الدخول' : 'Sign in',
        onCta: () => Navigator.pushNamed(context, Routes.auth),
        child: Text((d['message'] ?? '').toString(),
            style: const TextStyle(fontSize: 11.5, height: 1.4, color: UellowColors.muted)),
      );
    }
    final progress = (_int(d['progress']) / 100).clamp(0.0, 1.0);
    return _Shell(
      accent: UellowColors.darkBrown, icon: Icons.card_giftcard,
      title: ar ? 'نقاط الولاء' : 'Loyalty points',
      cta: ar ? 'محفظة نقاطي' : 'My points',
      onCta: () => Navigator.pushNamed(context, Routes.loyalty),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${_int(d['points'])}', style: const TextStyle(
              fontSize: 24, fontWeight: FontWeight.w900, color: UellowColors.darkBrown)),
          const SizedBox(width: 4),
          Padding(padding: const EdgeInsets.only(bottom: 4),
            child: Text(ar ? 'نقطة' : 'pts', style: const TextStyle(
                fontSize: 11, color: UellowColors.muted))),
          const Spacer(),
          if ((d['level_label'] ?? d['level'] ?? '').toString().isNotEmpty)
            _chip((d['level_label'] ?? d['level']).toString(), const Color(0xFFC99000)),
        ]),
        if ((d['kd_value_text'] ?? '').toString().isNotEmpty ||
            d['kd_value'] != null)
          Padding(padding: const EdgeInsets.only(top: 2),
            child: Text(
                '${ar ? 'القيمة:' : 'Worth:'} '
                '${(d['kd_value_text'] ?? _kd(_dbl(d['kd_value']), ar))}',
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700,
                    color: UellowColors.ink))),
        if (_int(d['to_next']) > 0) ...[
          const SizedBox(height: 8),
          ClipRRect(borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(value: progress, minHeight: 6,
                backgroundColor: const Color(0xFFEDEDED),
                valueColor: const AlwaysStoppedAnimation(UellowColors.yellow))),
          const SizedBox(height: 4),
          Text('${ar ? 'باقي' : 'Need'} ${_int(d['to_next'])} '
              '${ar ? 'للمستوى التالي' : 'to next tier'}',
              style: const TextStyle(fontSize: 10.5, color: UellowColors.muted)),
        ],
      ]),
    );
  }
}

// ── CART ────────────────────────────────────────────────────────────────────
class _CartCard extends StatelessWidget {
  const _CartCard({required this.d, required this.ar});
  final Map<String, dynamic> d;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    if (d['empty'] == true) {
      return _Shell(accent: UellowColors.darkBrown, icon: Icons.shopping_cart_outlined,
        title: ar ? 'سلتك' : 'Your cart',
        child: Text(ar ? 'سلتك فارغة.' : 'Your cart is empty.',
            style: const TextStyle(fontSize: 11.5, color: UellowColors.muted)));
    }
    final lines = (d['lines'] as List?)?.whereType<Map>().toList() ?? const [];
    return _Shell(
      accent: UellowColors.darkBrown, icon: Icons.shopping_cart_outlined,
      title: '${ar ? 'سلتك' : 'Your cart'} (${_int(d['item_count'])})',
      cta: ar ? 'إتمام الشراء' : 'Checkout',
      ctaIcon: Icons.lock_outline,
      onCta: () => Navigator.pushNamed(context, Routes.cart),
      child: Column(children: [
        for (final l in lines.take(4))
          Padding(padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              if ((l['image_url'] ?? '').toString().isNotEmpty) Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ClipRRect(borderRadius: BorderRadius.circular(6),
                  child: CachedNetworkImage(imageUrl: _abs(l['image_url'].toString()),
                      width: 34, height: 34, fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => const SizedBox(width: 34, height: 34))),
              ),
              Expanded(child: Text(_locName(l['name'], ar), maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600,
                      color: UellowColors.ink))),
              Text(' ×${_int(l['qty'])}', style: const TextStyle(
                  fontSize: 11, color: UellowColors.muted)),
              const SizedBox(width: 6),
              Text(_kd(_dbl(l['subtotal']), ar), style: const TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w800, color: UellowColors.darkBrown)),
            ])),
        const Divider(height: 14),
        Row(children: [
          Text(ar ? 'الإجمالي' : 'Total', style: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, color: UellowColors.ink)),
          const Spacer(),
          Text(_kd(_dbl(d['amount_total']), ar), style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w900, color: UellowColors.darkBrown)),
        ]),
      ]),
    );
  }
}

class _CartAddedCard extends StatelessWidget {
  const _CartAddedCard({required this.d, required this.ar});
  final Map<String, dynamic> d;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    if (d['success'] != true) return const SizedBox.shrink();
    return _Shell(
      accent: const Color(0xFF2E9E6B), icon: Icons.check_circle_outline,
      title: ar ? 'تمت الإضافة للسلة' : 'Added to cart',
      cta: ar ? 'عرض السلة' : 'View cart',
      onCta: () => Navigator.pushNamed(context, Routes.cart),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_locName(d['product'], ar), style: const TextStyle(
            fontSize: 12, fontWeight: FontWeight.w800, color: UellowColors.ink)),
        const SizedBox(height: 4),
        _kv(ar ? 'القطع:' : 'Items:', '${_int(d['cart_count'])}'),
        _kv(ar ? 'الإجمالي:' : 'Total:', _kd(_dbl(d['cart_total']), ar)),
      ]),
    );
  }
}

// ── REVIEWERS ───────────────────────────────────────────────────────────────
class _ReviewersCard extends StatelessWidget {
  const _ReviewersCard({required this.d, required this.ar, required this.onSend});
  final Map<String, dynamic> d;
  final bool ar;
  final void Function(String) onSend;
  @override
  Widget build(BuildContext context) {
    final revs = (d['reviewers'] as List?)?.whereType<Map>().toList() ?? const [];
    if (revs.isEmpty) return const SizedBox.shrink();
    return _Shell(
      accent: const Color(0xFF2F6E62), icon: Icons.reviews_outlined,
      title: '${ar ? 'المراجعون' : 'Reviewers'} '
          '(${_int(d['online_count'])} ${ar ? 'متصل' : 'online'})',
      child: SizedBox(height: 92, child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: revs.length.clamp(0, 12),
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final r = revs[i];
          final av = _abs((r['avatar_url'] ?? '').toString());
          return SizedBox(width: 64, child: Column(children: [
            Stack(children: [
              CircleAvatar(radius: 24, backgroundColor: const Color(0xFFEDEDED),
                  backgroundImage: av.isNotEmpty ? CachedNetworkImageProvider(av) : null,
                  child: av.isEmpty ? const Icon(Icons.person, size: 22,
                      color: UellowColors.muted) : null),
              if (r['is_online'] == true) Positioned(right: 0, bottom: 0,
                child: Container(width: 12, height: 12, decoration: BoxDecoration(
                    color: const Color(0xFF2E9E6B), shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2)))),
            ]),
            const SizedBox(height: 4),
            Text((r['name'] ?? '').toString(), maxLines: 1,
                overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                    color: UellowColors.ink)),
            if (r['rating'] != null)
              Text('⭐ ${_dbl(r['rating']).toStringAsFixed(1)}',
                  style: const TextStyle(fontSize: 9.5, color: UellowColors.muted)),
          ]));
        },
      )),
    );
  }
}

// ── LOCATION ────────────────────────────────────────────────────────────────
class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.d, required this.ar});
  final Map<String, dynamic> d;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    final lat = _dbl(d['lat']);
    final lng = _dbl(d['lng']);
    final mapUrl = (d['map_url'] ?? '').toString().isNotEmpty
        ? d['map_url'].toString()
        : (lat != 0 || lng != 0)
            ? 'https://www.google.com/maps/search/?api=1&query=$lat,$lng' : '';
    final phone = (d['phone'] ?? d['whatsapp'] ?? '').toString();
    return _Shell(
      accent: const Color(0xFF2F6E62), icon: Icons.location_on_outlined,
      title: _locName(d['name'], ar).isEmpty
          ? (ar ? 'الموقع' : 'Location') : _locName(d['name'], ar),
      cta: mapUrl.isNotEmpty ? (ar ? 'افتح الخريطة' : 'Open map') : null,
      ctaIcon: Icons.directions_outlined,
      onCta: mapUrl.isNotEmpty ? () => _launch(mapUrl) : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if ((d['address'] ?? '').toString().isNotEmpty)
          _kv(ar ? 'العنوان:' : 'Address:', d['address'].toString()),
        if ((d['hours'] ?? '').toString().isNotEmpty)
          _kv(ar ? 'الدوام:' : 'Hours:', d['hours'].toString()),
        if (phone.isNotEmpty) InkWell(
          onTap: () => _launch('tel:$phone'),
          child: _kv(ar ? 'الهاتف:' : 'Phone:', phone),
        ),
      ]),
    );
  }
}

// ── PAYMENT / ORDER CREATED ─────────────────────────────────────────────────
class _PaymentCard extends StatelessWidget {
  const _PaymentCard({this.order, this.payment, required this.ar});
  final Map<String, dynamic>? order;
  final Map<String, dynamic>? payment;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    final name = (order?['order_name'] ?? payment?['order_name'] ?? '').toString();
    final amount = _dbl(order?['amount'] ?? payment?['amount']);
    final upay = (order?['upay_url'] ?? payment?['upay_url'] ?? '').toString();
    final checkout = (order?['cart_url'] ?? payment?['checkout_url'] ?? '').toString();
    final pay = upay.isNotEmpty ? upay : checkout;
    return _Shell(
      accent: const Color(0xFF2F6E62), icon: Icons.payments_outlined,
      title: '${ar ? 'الطلب' : 'Order'} $name',
      cta: pay.isNotEmpty ? (ar ? 'ادفع الآن' : 'Pay now') : null,
      ctaIcon: Icons.lock_outline,
      onCta: pay.isNotEmpty
          ? () => Navigator.pushNamed(context, Routes.webview, arguments: {
              'url': _abs(pay), 'title': ar ? 'الدفع' : 'Payment'})
          : null,
      child: Row(children: [
        Text(ar ? 'الإجمالي' : 'Total', style: const TextStyle(
            fontSize: 12, color: UellowColors.muted)),
        const Spacer(),
        Text(_kd(amount, ar), style: const TextStyle(
            fontSize: 16, fontWeight: FontWeight.w900, color: UellowColors.darkBrown)),
      ]),
    );
  }
}

class _PaymentOptionsCard extends StatelessWidget {
  const _PaymentOptionsCard({required this.d, required this.ar});
  final Map<String, dynamic> d;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    final options = (d['options'] as List?)?.whereType<Map>().toList() ?? const [];
    if (options.isEmpty) return const SizedBox.shrink();
    return _Shell(
      accent: const Color(0xFF2F6E62), icon: Icons.account_balance_wallet_outlined,
      title: ar ? 'طرق الدفع' : 'Payment options',
      child: Column(children: [
        for (final o in options)
          Padding(padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              const Icon(Icons.check_circle, size: 14, color: Color(0xFF2E9E6B)),
              const SizedBox(width: 8),
              Text((o['name'] ?? '').toString(), style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w800, color: UellowColors.ink)),
              const SizedBox(width: 6),
              Expanded(child: Text((o['desc'] ?? '').toString(),
                  style: const TextStyle(fontSize: 11, color: UellowColors.muted))),
            ])),
      ]),
    );
  }
}

class _QuoteCard extends StatelessWidget {
  const _QuoteCard({required this.d, required this.ar});
  final Map<String, dynamic> d;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    final addr = (d['address'] as Map?)?.cast<String, dynamic>() ?? const {};
    final checkout = (d['checkout_url'] ?? '').toString();
    return _Shell(
      accent: const Color(0xFF2F6E62), icon: Icons.receipt_outlined,
      title: '${ar ? 'ملخص الطلب' : 'Order summary'} ${d['order_name'] ?? ''}',
      cta: checkout.isNotEmpty ? (ar ? 'إتمام الدفع' : 'Complete payment') : null,
      onCta: checkout.isNotEmpty
          ? () => Navigator.pushNamed(context, Routes.webview, arguments: {
              'url': _abs(checkout), 'title': ar ? 'الدفع' : 'Payment'})
          : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _kv(ar ? 'القطع:' : 'Items:', '${_int(d['item_count'])}'),
        _kv(ar ? 'الإجمالي:' : 'Total:', _kd(_dbl(d['amount_total']), ar)),
        if ((addr['city'] ?? '').toString().isNotEmpty)
          _kv(ar ? 'العنوان:' : 'Address:',
              [addr['governorate'], addr['city'], addr['street']]
                  .where((e) => (e ?? '').toString().isNotEmpty).join('، ')),
      ]),
    );
  }
}

class _CheckoutCard extends StatelessWidget {
  const _CheckoutCard({required this.d, required this.ar});
  final Map<String, dynamic> d;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    final state = (d['state'] ?? '').toString();
    final missing = (d['missing'] as List?)?.map((e) => e.toString()).toList() ?? const [];
    final labels = {
      'phone': ar ? 'الهاتف' : 'phone',
      'governorate': ar ? 'المحافظة' : 'governorate',
      'city': ar ? 'المدينة' : 'city',
      'street': ar ? 'الشارع' : 'street',
    };
    return _Shell(
      accent: const Color(0xFF2F6E62), icon: Icons.local_mall_outlined,
      title: ar ? 'إتمام الطلب' : 'Checkout',
      cta: state == 'needs_login'
          ? (ar ? 'تسجيل الدخول' : 'Sign in')
          : (ar ? 'افتح السلة' : 'Open cart'),
      onCta: state == 'needs_login'
          ? () => Navigator.pushNamed(context, Routes.auth)
          : () => Navigator.pushNamed(context, Routes.cart),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if ((d['message'] ?? '').toString().isNotEmpty)
          Text(d['message'].toString(), style: const TextStyle(
              fontSize: 11.5, height: 1.4, color: UellowColors.muted)),
        if (missing.isNotEmpty) Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final m in missing)
              _chip(labels[m] ?? m, UellowColors.danger),
          ]),
        ),
      ]),
    );
  }
}

// ── UPSELL (mini product rail) ──────────────────────────────────────────────
class _UpsellRail extends StatelessWidget {
  const _UpsellRail({required this.items, required this.ar});
  final List<Map<String, dynamic>> items;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    return _Shell(
      accent: const Color(0xFFC99000), icon: Icons.auto_awesome_outlined,
      title: ar ? 'قد يعجبك أيضاً' : 'You may also like',
      child: SizedBox(height: 150, child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final p = items[i];
          final id = _int(p['id']);
          final img = _abs((p['image_url'] ?? p['image'] ?? '').toString());
          return GestureDetector(
            onTap: id > 0 ? () => UellowRouter.goProduct(context, id) : null,
            child: SizedBox(width: 108, child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              ClipRRect(borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(imageUrl: img, width: 108, height: 90,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => const ColoredBox(color: Color(0xFFF4F4F4)),
                    errorWidget: (_, __, ___) => const ColoredBox(color: Color(0xFFF4F4F4),
                        child: Icon(Icons.image_outlined, color: UellowColors.muted)))),
              const SizedBox(height: 4),
              Text(_locName(p['name'], ar), maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10.5, height: 1.3,
                      fontWeight: FontWeight.w700, color: UellowColors.ink)),
              Text(_kd(_dbl(p['price']), ar), style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w900, color: UellowColors.darkBrown)),
            ])),
          );
        },
      )),
    );
  }
}
