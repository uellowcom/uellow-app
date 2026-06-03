// =============================================================================
// OrderScreen — real Odoo order detail with multi-stage live tracking map.
//
// Map stages (from delivery_tracking.stage):
//   placed/at_warehouse   — single pin at Uellow warehouse
//   at_carrier            — two pins (warehouse → carrier) + parcel icon
//   in_transit/arriving   — three pins (carrier → live driver van → customer)
//   delivered             — fixed pin at customer location with checkmark
//
// AppBar has a Refresh button that re-fetches the order; pull-to-refresh too.
// Actions: Invoice (PDF download/share), Contact Seller (helpdesk form),
// Rate Items (inline dialog), Reorder, Return, Share.
// =============================================================================
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../api/uellow_api.dart';
import '../../api/uellow_models.dart';
import '../theme/uellow_theme.dart';
import 'helpdesk_screen.dart';

class OrderScreen extends StatefulWidget {
  const OrderScreen({super.key, required this.orderId});
  final int orderId;
  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  late Future<UellowOrderDetail> _future;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _future = UellowApi.instance.orders.detail(widget.orderId);
  }

  Future<void> _refresh() async {
    setState(() {
      _refreshing = true;
      _future = UellowApi.instance.orders.refresh(widget.orderId);
    });
    try { await _future; } catch (_) {}
    if (mounted) setState(() => _refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return Scaffold(
      backgroundColor: UellowColors.bg,
      body: SafeArea(bottom: false, child: FutureBuilder<UellowOrderDetail>(
        future: _future,
        builder: (_, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: UellowColors.darkBrown));
          }
          if (snap.hasError) {
            return _errorState(snap.error.toString(), ar);
          }
          final order = snap.data!;
          return RefreshIndicator(
            onRefresh: _refresh,
            color: UellowColors.darkBrown,
            child: ListView(padding: EdgeInsets.zero, children: [
              _Header(order: order, ar: ar, refreshing: _refreshing,
                  onRefresh: _refresh),
              if (order.deliveryTracking != null) _EtaCard(tracking: order.deliveryTracking!, ar: ar),
              _MapBox(tracking: order.deliveryTracking, ar: ar),
              if (order.timeline.isNotEmpty) _Timeline(timeline: order.timeline, ar: ar),
              _Items(order: order, ar: ar),
              _Summary(order: order, ar: ar),
              _Actions(order: order, ar: ar),
              const SizedBox(height: 24),
            ]),
          );
        },
      )),
    );
  }

  Widget _errorState(String msg, bool ar) {
    return Center(child: Padding(
      padding: const EdgeInsets.all(30),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline, size: 56, color: UellowColors.muted),
        const SizedBox(height: 12),
        Text(ar ? 'تعذّر تحميل الطلب' : 'Could not load order', style: UT.h3),
        const SizedBox(height: 4),
        Text(msg, textAlign: TextAlign.center, style: UT.subtitle),
        const SizedBox(height: 16),
        ElevatedButton.icon(onPressed: _refresh,
          icon: const Icon(Icons.refresh, size: 16),
          label: Text(ar ? 'إعادة المحاولة' : 'Retry')),
      ]),
    ));
  }
}

// ─── Header with Refresh button ──────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.order, required this.ar,
      required this.refreshing, required this.onRefresh});
  final UellowOrderDetail order;
  final bool ar;
  final bool refreshing;
  final VoidCallback onRefresh;
  Color _statusColor(String s) => switch (s) {
    'draft'     => UellowColors.muted,
    'confirmed' => const Color(0xFF0EA5E9),
    'preparing' => const Color(0xFF8B5CF6),
    'shipping'  => const Color(0xFFF59E0B),
    'delivered' => UellowColors.successDk,
    'cancelled' => UellowColors.muted,
    'returned'  => UellowColors.danger,
    _ => UellowColors.muted,
  };
  @override
  Widget build(BuildContext context) {
    final accent = _statusColor(order.uellowStatus);
    final placedDate = (order.date ?? '').split('T').first;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 18,
                  color: UellowColors.darkBrown),
              onPressed: () => Navigator.maybePop(context)),
          Expanded(child: Text(
            '${ar ? "طلب" : "Order"} ${order.name}',
            style: UT.h2,
          )),
          IconButton(
              tooltip: ar ? 'تحديث الحالة' : 'Refresh status',
              icon: refreshing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(
                    strokeWidth: 2, color: UellowColors.darkBrown))
                : const Icon(Icons.refresh, size: 20, color: UellowColors.darkBrown),
              onPressed: refreshing ? null : onRefresh),
          // Status pill on the right of the header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 6, height: 6,
                  decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(order.uellowStatusLabel.current(ar ? 'ar' : 'en').toUpperCase(),
                  style: TextStyle(color: accent, fontSize: 10.5,
                      fontWeight: FontWeight.w900, letterSpacing: 0.5)),
            ]),
          ),
          const SizedBox(width: 6),
        ]),
        Padding(padding: const EdgeInsets.only(left: 8, top: 2),
            child: Text(
                (ar ? 'تم في $placedDate · ${order.lineCount} عناصر · ${order.total.format()}'
                    : 'Placed on $placedDate · ${order.lineCount} items · ${order.total.format()}'),
                style: UT.small)),
      ]),
    );
  }
}

// ─── ETA card — stage label + driver info ────────────────────────────

class _EtaCard extends StatelessWidget {
  const _EtaCard({required this.tracking, required this.ar});
  final Map<String, dynamic> tracking;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    final stageLabel = (tracking['stage_label'] as Map?) ?? const {};
    final stageText = (ar ? stageLabel['ar'] : stageLabel['en']) as String?
        ?? ((tracking['eta_text'] as Map?)?[ar ? 'ar' : 'en'] as String?)
        ?? (ar ? 'قيد المعالجة' : 'In progress');
    final driverMap = tracking['driver'] is Map ? Map<String, dynamic>.from(tracking['driver'] as Map) : const <String, dynamic>{};
    final driver = (driverMap['name'] as String?) ?? (tracking['driver_name'] as String?) ?? '';
    final phone  = (driverMap['phone'] as String?) ?? (tracking['driver_phone'] as String?) ?? '';
    final distance = tracking['distance_km'];
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      padding: const EdgeInsets.all(14),
      decoration: const BoxDecoration(
        gradient: UellowColors.heroWallet,
        borderRadius: BorderRadius.all(Radius.circular(16)),
        boxShadow: [BoxShadow(color: Color(0x66412402),
            blurRadius: 18, offset: Offset(0, 8))],
      ),
      child: Row(children: [
        Container(
          width: 52, height: 52,
          decoration: BoxDecoration(
            color: UellowColors.yellowLight.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.local_shipping_outlined,
              size: 26, color: UellowColors.yellowLight),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min, children: [
          Text(ar ? 'الحالة' : 'Status',
              style: const TextStyle(fontSize: 11,
                  color: UellowColors.yellowLight, fontWeight: FontWeight.w600)),
          Text(stageText, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900,
                  color: UellowColors.yellowLight, height: 1.2)),
          if (driver.isNotEmpty || distance != null) Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text([
              if (driver.isNotEmpty) (ar ? 'السائق: $driver' : 'Driver: $driver'),
              if (distance != null) (ar
                  ? 'تبعد ${distance.toStringAsFixed(1)} كم'
                  : '${distance.toStringAsFixed(1)} km away'),
            ].join(' · '),
                style: const TextStyle(fontSize: 11,
                    color: UellowColors.yellowLight)),
          ),
        ])),
        if (phone.isNotEmpty) ElevatedButton(
          onPressed: () => launchUrl(Uri.parse('tel:$phone')),
          style: ElevatedButton.styleFrom(
            backgroundColor: UellowColors.yellowLight,
            foregroundColor: UellowColors.darkBrown,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          child: Text(ar ? 'اتصال' : 'Call'),
        ),
      ]),
    );
  }
}

// ─── Map box — multi-stage Leaflet map. Pins:
//     warehouse 📦 → carrier 🏬 → driver 🚚 → customer 📍
// Polyline connects them in the order that exists. Live driver pin
// animates between heartbeats by reloading the URL via setState.

class _MapBox extends StatefulWidget {
  const _MapBox({this.tracking, required this.ar});
  final Map<String, dynamic>? tracking;
  final bool ar;
  @override
  State<_MapBox> createState() => _MapBoxState();
}

class _MapBoxState extends State<_MapBox> {
  WebViewController? _wv;
  String _lastSig = '';

  @override
  void initState() { super.initState(); _maybeLoad(); }

  @override
  void didUpdateWidget(covariant _MapBox old) {
    super.didUpdateWidget(old);
    _maybeLoad();
  }

  Map<String, dynamic>? get _t => widget.tracking;
  Map<String, dynamic>? _pt(String key) {
    final raw = _t?[key];
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  void _maybeLoad() {
    final w = _pt('warehouse');
    final c = _pt('carrier');
    final d = _pt('driver');
    final u = _pt('customer');
    final stage = (_t?['stage'] as String?) ?? 'placed';
    final pins = <String>[];
    if (w != null) pins.add('w:${w['lat']},${w['lng']}');
    if (c != null) pins.add('c:${c['lat']},${c['lng']}');
    if (d != null && d['is_live'] == true) pins.add('d:${d['lat']},${d['lng']}');
    if (u != null) pins.add('u:${u['lat']},${u['lng']}');
    final sig = '$stage|${pins.join('|')}';
    if (sig == _lastSig && _wv != null) return;
    if (pins.isEmpty) return;
    _lastSig = sig;
    try {
      final wv = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xFFEFEAE0))
        ..loadHtmlString(_html(stage));
      setState(() => _wv = wv);
    } catch (_) {
      setState(() => _wv = null);
    }
  }

  String _esc(String s) => s.replaceAll("'", "\\'").replaceAll('"', '\\"');

  String _html(String stage) {
    final ar = widget.ar;
    final w = _pt('warehouse');
    final c = _pt('carrier');
    final d = _pt('driver');
    final u = _pt('customer');
    final markers = <String>[];
    final coords = <String>[];
    if (w != null) {
      final name = _esc(((w['name'] is Map ? (w['name'][ar?'ar':'en']) : '').toString()).isNotEmpty
          ? (w['name'][ar?'ar':'en']).toString()
          : (ar ? 'مخزن يلو' : 'Uellow Warehouse'));
      markers.add(_pin(w['lat'], w['lng'], '#412402', '#F5C320', '📦', name));
      coords.add('[${w['lat']},${w['lng']}]');
    }
    if (c != null) {
      final name = _esc((c['name'] ?? '').toString().isNotEmpty
          ? c['name'].toString() : (ar ? 'مركز التوصيل' : 'Delivery Hub'));
      markers.add(_pin(c['lat'], c['lng'], '#0EA5E9', '#FFFFFF', '🏬', name));
      coords.add('[${c['lat']},${c['lng']}]');
    }
    if (d != null && d['is_live'] == true) {
      final name = _esc(ar ? 'السائق' : 'Driver');
      markers.add(_pin(d['lat'], d['lng'], '#F59E0B', '#412402', '🚚', name));
      coords.add('[${d['lat']},${d['lng']}]');
    }
    if (u != null) {
      final name = _esc(ar ? 'عنوانك' : 'You');
      final isDelivered = stage == 'delivered';
      markers.add(_pin(u['lat'], u['lng'],
          isDelivered ? '#10B981' : '#EF4444', '#FFFFFF',
          isDelivered ? '✓' : '🏠', name));   // v2.1.23 — house icon
      coords.add('[${u['lat']},${u['lng']}]');
    }
    final markersJs = markers.join('\n');
    final polyJs = coords.length >= 2
        ? "L.polyline([${coords.join(',')}],{color:'#412402',weight:3,opacity:0.6,dashArray:'8,6'}).addTo(map);"
        : "";
    return '''
<!doctype html><html><head><meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no"/>
<link rel="stylesheet" href="https://unpkg.com/leaflet\@1.9.4/dist/leaflet.css"/>
<style>html,body,#m{margin:0;padding:0;height:100%;width:100%;background:#efeae0}
.leaflet-control-attribution{font-size:9px}</style>
</head><body><div id="m"></div>
<script src="https://unpkg.com/leaflet\@1.9.4/dist/leaflet.js"></script>
<script>
var map=L.map('m',{zoomControl:true,attributionControl:true,scrollWheelZoom:false});
L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
  {maxZoom:19,attribution:'© OSM'}).addTo(map);
$markersJs
$polyJs
var pts=[${coords.join(',')}];
if(pts.length>=2){map.fitBounds(L.latLngBounds(pts).pad(0.25));}
else if(pts.length==1){map.setView(pts[0],14);}
</script></body></html>''';
  }

  String _pin(dynamic lat, dynamic lng, String bg, String fg, String emoji, String label) {
    return "L.marker([$lat,$lng],{icon:L.divIcon({className:'',iconSize:[38,38],iconAnchor:[19,19],"
        "html:'<div style=\"width:38px;height:38px;border-radius:50%;background:$bg;border:3px solid $fg;"
        "display:flex;align-items:center;justify-content:center;color:$fg;font-size:18px;"
        "box-shadow:0 2px 6px rgba(0,0,0,.4)\">$emoji</div>'})}).addTo(map).bindPopup('$label');";
  }

  @override
  Widget build(BuildContext context) {
    final ar = widget.ar;
    final hasAny = _pt('warehouse') != null || _pt('carrier') != null ||
        _pt('customer') != null ||
        (_pt('driver')?['is_live'] == true);
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      height: 220,
      decoration: BoxDecoration(
        color: UellowColors.yellowFaint,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: UellowColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(children: [
          if (hasAny && _wv != null)
            Positioned.fill(child: WebViewWidget(controller: _wv!))
          else
            Center(child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.location_searching,
                    size: 28, color: UellowColors.darkBrown),
                const SizedBox(height: 8),
                Text(ar
                    ? 'سيظهر تتبع الطلب هنا فور تأكيده'
                    : 'Tracking will appear here once the order is confirmed',
                    textAlign: TextAlign.center, style: UT.subtitle),
              ]),
            )),
          if (hasAny) Positioned(top: 8, right: 8, child: _buildOpenInMaps()),
        ]),
      ),
    );
  }

  Widget _buildOpenInMaps() {
    final c = _pt('customer');
    final d = _pt('driver');
    final target = (d?['is_live'] == true) ? d : c;
    if (target == null) return const SizedBox.shrink();
    final lat = target['lat']; final lng = target['lng'];
    return GestureDetector(
      onTap: () => launchUrl(
        Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng'),
        mode: LaunchMode.externalApplication,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            boxShadow: const [BoxShadow(color: Color(0x33000000),
                blurRadius: 4, offset: Offset(0, 2))]),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.open_in_new, size: 12, color: UellowColors.darkBrown),
          const SizedBox(width: 4),
          Text(widget.ar ? 'افتح الخريطة' : 'Open in Maps',
              style: const TextStyle(fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                  color: UellowColors.darkBrown)),
        ]),
      ),
    );
  }
}

// ─── Timeline (uses backend timeline list) ───────────────────────────

class _Timeline extends StatelessWidget {
  const _Timeline({required this.timeline, required this.ar});
  final List<Map<String, dynamic>> timeline;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(ar ? 'التتبع' : 'Tracking', style: UT.h3),
        const SizedBox(height: 14),
        ...List.generate(timeline.length, (i) =>
            _step(timeline[i], i == timeline.length - 1)),
      ]),
    );
  }

  Widget _step(Map<String, dynamic> s, bool last) {
    final state = (s['state'] as String?) ?? 'upcoming';
    final code = (s['code'] as String?) ?? '';
    final label = (s['label'] as Map?)?[ar ? 'ar' : 'en'] as String? ?? code;
    final icon = {
      'draft':     Icons.edit_note,
      'confirmed': Icons.check_circle_outline,
      'preparing': Icons.inventory_2_outlined,
      'shipping':  Icons.local_shipping_outlined,
      'delivered': Icons.home_outlined,
    }[code] ?? Icons.circle_outlined;
    final isDone = state == 'done';
    final isNow = state == 'current';
    final iconBg = isDone ? UellowColors.success
        : (isNow ? UellowColors.yellowLight : UellowColors.border);
    final iconFg = isDone ? Colors.white
        : (isNow ? UellowColors.darkBrown : UellowColors.muted);
    final titleCol = (isDone || isNow) ? UellowColors.ink : UellowColors.muted;
    return IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Column(children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
          child: Icon(isDone ? Icons.check : icon, size: 14, color: iconFg),
        ),
        if (!last) Expanded(child: Container(
          width: 2, margin: const EdgeInsets.symmetric(vertical: 2),
          color: isDone ? UellowColors.success : UellowColors.border,
        )),
      ]),
      const SizedBox(width: 12),
      Expanded(child: Padding(
        padding: const EdgeInsets.only(bottom: 14, top: 3),
        child: Text(label, style: TextStyle(
          fontWeight: FontWeight.w800, fontSize: 13, color: titleCol)),
      )),
    ]));
  }
}

// ─── Items + Summary ─────────────────────────────────────────────────

class _Items extends StatelessWidget {
  const _Items({required this.order, required this.ar});
  final UellowOrderDetail order;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    final lines = order.lines;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      padding: const EdgeInsets.all(14),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(ar ? 'العناصر' : 'Items', style: UT.h3)),
          TextButton.icon(onPressed: () => _RateDialog.show(context, order),
              icon: const Icon(Icons.star_outline, size: 16,
                  color: UellowColors.darkBrown),
              label: Text(ar ? 'قيّم' : 'Rate',
                  style: const TextStyle(color: UellowColors.darkBrown,
                      fontWeight: FontWeight.w800, fontSize: 12.5))),
        ]),
        const SizedBox(height: 6),
        if (lines.isEmpty) Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(ar ? 'لا توجد عناصر في هذا الطلب.'
                          : 'No items in this order.', style: UT.subtitle),
        ) else
          for (final l in lines) _line(l, context),
      ]),
    );
  }

  Widget _line(UellowCartLine l, BuildContext context) {
    return InkWell(
      onTap: () => _RateDialog.showFor(context, l),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          ClipRRect(borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(imageUrl: l.image,
                width: 60, height: 60, fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  width: 60, height: 60, color: UellowColors.yellowSoft),
                errorWidget: (_, __, ___) => Container(
                  width: 60, height: 60, color: UellowColors.yellowSoft,
                  alignment: Alignment.center,
                  child: const Icon(Icons.image_outlined, color: UellowColors.muted)))),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.name.current(UellowApi.instance.lang),
                maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, color: UellowColors.ink)),
            const SizedBox(height: 4),
            Row(children: [
              Text('${ar ? "الكمية" : "Qty"} ${l.qty.toInt()}', style: UT.small),
              const Spacer(),
              Text(l.total.format(), style: const TextStyle(
                  color: UellowColors.darkBrown, fontWeight: FontWeight.w800, fontSize: 12)),
            ]),
          ])),
          const Icon(Icons.star_outline, size: 16, color: UellowColors.warn),
        ]),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.order, required this.ar});
  final UellowOrderDetail order;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      padding: const EdgeInsets.all(14),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(ar ? 'ملخص الدفع' : 'Payment summary', style: UT.h3),
        const SizedBox(height: 8),
        _r(ar ? 'الإجمالي قبل الخصم' : 'Subtotal', order.subtotal.format()),
        if (order.tax.amount > 0)
          _r(ar ? 'الضريبة' : 'Tax', order.tax.format()),
        _r(ar ? 'التوصيل' : 'Delivery', order.shipping.format()),
        const Divider(height: 18),
        Row(children: [
          Expanded(child: Text(ar ? 'المدفوع' : 'Paid', style: const TextStyle(
              fontWeight: FontWeight.w900, fontSize: 16, color: UellowColors.darkBrown))),
          Text(order.total.format(), style: const TextStyle(
              fontWeight: FontWeight.w900, fontSize: 18, color: UellowColors.darkBrown)),
        ]),
      ]),
    );
  }
  Widget _r(String l, String v, {bool good = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Expanded(child: Text(l, style: const TextStyle(fontSize: 12.5, color: UellowColors.text))),
      Text(v, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700,
          color: good ? UellowColors.successDk : UellowColors.text)),
    ]),
  );
}

// ─── Action buttons ──────────────────────────────────────────────────

class _Actions extends StatelessWidget {
  const _Actions({required this.order, required this.ar});
  final UellowOrderDetail order;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    final items = <_Action>[
      _Action(icon: Icons.replay,
          label: ar ? 'إعادة الطلب' : 'Reorder',
          onTap: () => _reorder(context)),
      _Action(icon: Icons.receipt_long_outlined,
          label: ar ? 'الفاتورة' : 'Invoice',
          onTap: () => _openInvoice(context)),
      _Action(icon: Icons.chat_bubble_outline,
          label: ar ? 'تواصل مع البائع' : 'Contact seller',
          onTap: () => _contactSeller(context)),
      _Action(icon: Icons.star_outline,
          label: ar ? 'قيّم المنتجات' : 'Rate items',
          onTap: () => _RateDialog.show(context, order)),
      _Action(icon: Icons.assignment_return_outlined,
          label: ar ? 'طلب إرجاع' : 'Request return', danger: true,
          onTap: () => _requestReturn(context)),
      _Action(icon: Icons.share_outlined,
          label: ar ? 'مشاركة الطلب' : 'Share order',
          onTap: () => _share(context)),
      _Action(icon: Icons.support_agent,
          label: ar ? 'الدعم الفني' : 'Support',
          primary: true,
          onTap: () => Navigator.pushNamed(context, '/helpdesk',
              arguments: {'order_ref': order.name, 'category': 'order'})),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 2.6,
        ),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final a = items[i];
          Color bg = Colors.white, fg = UellowColors.darkBrown;
          BorderSide side = const BorderSide(color: UellowColors.border, width: 1.5);
          if (a.primary) {
            bg = UellowColors.darkBrown; fg = UellowColors.yellowLight; side = BorderSide.none;
          }
          if (a.danger) {
            fg = UellowColors.dangerDk;
            side = const BorderSide(color: UellowColors.dangerBg, width: 1.5);
          }
          return Material(
            color: bg, borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: a.onTap,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.fromBorderSide(side),
                ),
                alignment: Alignment.center,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(a.icon, size: 14, color: fg),
                  const SizedBox(width: 6),
                  Flexible(child: Text(a.label, maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w800,
                          fontSize: 12.5, color: fg))),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _reorder(BuildContext context) async {
    final api = UellowApi.instance;
    try {
      for (final l in order.lines) {
        await api.cart.add(productId: l.productId, qty: l.qty.toInt());
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ar ? 'تمت إضافة عناصر الطلب إلى السلة'
                            : 'Items added to your cart')));
      Navigator.pushNamed(context, '/cart');
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _openInvoice(BuildContext context) async {
    // Download PDF to a temp file, then open or share.
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(
        content: Text(ar ? 'جاري تحضير الفاتورة...' : 'Preparing invoice...'),
        duration: const Duration(seconds: 1)));
    try {
      final bytes = await UellowApi.instance.orders.invoiceBytes(order.id);
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/${order.name.replaceAll('/', '-')}.pdf');
      await f.writeAsBytes(bytes, flush: true);
      if (!context.mounted) return;
      // Try url_launcher first; fall back to share sheet.
      final uri = Uri.file(f.path);
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) {
        await Share.shareXFiles([XFile(f.path)],
            subject: ar ? 'فاتورة ${order.name}' : 'Invoice ${order.name}');
      }
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(
          ar ? 'تعذّر تحميل الفاتورة' : 'Could not load invoice — ${e.toString()}')));
    }
  }

  Future<void> _contactSeller(BuildContext context) async {
    await showDialog(context: context, builder: (_) => _ContactSellerDialog(order: order));
  }

  void _requestReturn(BuildContext context) {
    Navigator.pushNamed(context, '/helpdesk', arguments: {
      'order_ref': order.name, 'category': 'return',
      'subject': ar ? 'طلب إرجاع للطلب ${order.name}' : 'Return request for ${order.name}',
    });
  }

  Future<void> _share(BuildContext context) async {
    final url = '${UellowApi.instance.baseUrl}/my/orders/${order.id}';
    await Share.share(url, subject: order.name);
  }
}

class _Action {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary, danger;
  _Action({required this.icon, required this.label, required this.onTap,
      this.primary = false, this.danger = false});
}

// ─── Contact seller dialog (with up to 5 photo attachments) ──────────

class _ContactSellerDialog extends StatefulWidget {
  const _ContactSellerDialog({required this.order});
  final UellowOrderDetail order;
  @override
  State<_ContactSellerDialog> createState() => _ContactSellerDialogState();
}

class _ContactSellerDialogState extends State<_ContactSellerDialog> {
  late final TextEditingController _subjectC;
  final _bodyC = TextEditingController();
  final List<Uint8List> _photos = [];
  bool _busy = false;
  static const int _maxPhotos = 5;

  @override
  void initState() {
    super.initState();
    final ar = UellowApi.instance.lang == 'ar';
    _subjectC = TextEditingController(
        text: ar ? 'استفسار حول الطلب ${widget.order.name}'
                  : 'Question about order ${widget.order.name}');
  }

  Future<void> _addPhoto() async {
    if (_photos.length >= _maxPhotos) return;
    final src = await showModalBottomSheet<ImageSource>(
      context: context, builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.photo_camera_outlined),
            title: Text(UellowApi.instance.lang == 'ar' ? 'التقاط صورة' : 'Take photo'),
            onTap: () => Navigator.pop(context, ImageSource.camera)),
        ListTile(leading: const Icon(Icons.photo_library_outlined),
            title: Text(UellowApi.instance.lang == 'ar' ? 'اختيار من المعرض' : 'Choose from gallery'),
            onTap: () => Navigator.pop(context, ImageSource.gallery)),
      ])));
    if (src == null) return;
    final picked = await ImagePicker().pickImage(source: src,
        maxWidth: 1400, maxHeight: 1400, imageQuality: 82);
    if (picked == null) return;
    final bytes = await File(picked.path).readAsBytes();
    if (mounted) setState(() => _photos.add(bytes));
  }

  Future<void> _send() async {
    if (_bodyC.text.trim().isEmpty) return;
    final ar = UellowApi.instance.lang == 'ar';
    setState(() => _busy = true);
    try {
      final photosB64 = _photos.map((b) => base64Encode(b)).toList();
      await UellowApi.instance.orders.contactSeller(
        orderId: widget.order.id,
        subject: _subjectC.text.trim(),
        body: _bodyC.text.trim(),
        photosBase64: photosB64.isEmpty ? null : photosB64);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          ar ? 'تم إرسال رسالتك للبائع' : 'Message sent to seller')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return AlertDialog(
      title: Text(ar ? 'تواصل مع البائع' : 'Contact seller'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: _subjectC,
          decoration: InputDecoration(labelText: ar ? 'الموضوع' : 'Subject',
            border: const OutlineInputBorder(), isDense: true)),
        const SizedBox(height: 10),
        TextField(controller: _bodyC, minLines: 3, maxLines: 6,
          decoration: InputDecoration(labelText: ar ? 'الرسالة' : 'Message',
            border: const OutlineInputBorder(), isDense: true)),
        const SizedBox(height: 10),
        SizedBox(height: 72, child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _photos.length + (_photos.length < _maxPhotos ? 1 : 0),
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            if (i == _photos.length) {
              return GestureDetector(onTap: _addPhoto, child: Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  color: UellowColors.yellowSoft,
                  border: Border.all(color: UellowColors.yellow, width: 1.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.add_a_photo_outlined, color: UellowColors.darkBrown, size: 22),
                  const SizedBox(height: 2),
                  Text(UellowApi.instance.lang == 'ar' ? 'إضافة' : 'Add',
                      style: const TextStyle(fontSize: 9.5,
                      color: UellowColors.darkBrown, fontWeight: FontWeight.w800)),
                ]),
              ));
            }
            return Stack(clipBehavior: Clip.none, children: [
              ClipRRect(borderRadius: BorderRadius.circular(10),
                  child: Image.memory(_photos[i], width: 64, height: 64, fit: BoxFit.cover)),
              Positioned(top: -6, right: -6, child: GestureDetector(
                onTap: () => setState(() => _photos.removeAt(i)),
                child: Container(
                  width: 22, height: 22, alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: UellowColors.danger, shape: BoxShape.circle),
                  child: const Icon(Icons.close, color: Colors.white, size: 14),
                ),
              )),
            ]);
          },
        )),
        if (_photos.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4),
            child: Text('${_photos.length}/$_maxPhotos ${ar ? "صور" : "photos"}',
                style: const TextStyle(fontSize: 11, color: UellowColors.muted))),
      ])),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context),
            child: Text(ar ? 'إلغاء' : 'Cancel')),
        ElevatedButton(onPressed: _busy ? null : _send,
            child: _busy
              ? const SizedBox(width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(ar ? 'إرسال' : 'Send')),
      ],
    );
  }
}

// ─── Rate dialog (inline, instead of pushing the product page) ───────

class _RateDialog extends StatefulWidget {
  const _RateDialog({required this.line});
  final UellowCartLine line;
  static Future<void> show(BuildContext context, UellowOrderDetail order) async {
    if (order.lines.isEmpty) return;
    if (order.lines.length == 1) {
      await showFor(context, order.lines.first);
      return;
    }
    // Multiple items — pick one via bottom sheet then open dialog.
    final ar = UellowApi.instance.lang == 'ar';
    final picked = await showModalBottomSheet<UellowCartLine>(
      context: context, isScrollControlled: true, backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(
          top: Radius.circular(18))),
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Row(children: [
            Expanded(child: Text(ar ? 'اختر منتجاً لتقييمه' : 'Pick an item to rate',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
            IconButton(onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close, size: 18)),
          ])),
        const Divider(height: 1),
        Flexible(child: ListView.builder(shrinkWrap: true, itemCount: order.lines.length,
          itemBuilder: (_, i) {
            final l = order.lines[i];
            return ListTile(
              leading: ClipRRect(borderRadius: BorderRadius.circular(6),
                child: CachedNetworkImage(imageUrl: l.image, width: 40, height: 40, fit: BoxFit.cover,
                  errorWidget: (_,__,___) => Container(width: 40, height: 40,
                    color: UellowColors.yellowSoft))),
              title: Text(l.name.current(UellowApi.instance.lang),
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              trailing: const Icon(Icons.chevron_right, color: UellowColors.darkBrown),
              onTap: () => Navigator.pop(context, l),
            );
          })),
      ])));
    if (picked != null && context.mounted) {
      await showFor(context, picked);
    }
  }

  static Future<void> showFor(BuildContext context, UellowCartLine line) async {
    await showDialog(context: context, builder: (_) => _RateDialog(line: line));
  }

  @override
  State<_RateDialog> createState() => _RateDialogState();
}

class _RateDialogState extends State<_RateDialog> {
  double _rating = 5;
  final _comment = TextEditingController();
  final List<Uint8List> _photos = [];
  bool _busy = false;
  static const int _maxPhotos = 5;

  Future<void> _addPhoto() async {
    if (_photos.length >= _maxPhotos) return;
    final src = await showModalBottomSheet<ImageSource>(
      context: context, builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.photo_camera_outlined),
            title: Text(UellowApi.instance.lang == 'ar' ? 'التقاط صورة' : 'Take photo'),
            onTap: () => Navigator.pop(context, ImageSource.camera)),
        ListTile(leading: const Icon(Icons.photo_library_outlined),
            title: Text(UellowApi.instance.lang == 'ar' ? 'اختيار من المعرض' : 'Choose from gallery'),
            onTap: () => Navigator.pop(context, ImageSource.gallery)),
      ])));
    if (src == null) return;
    final picked = await ImagePicker().pickImage(source: src,
        maxWidth: 1400, maxHeight: 1400, imageQuality: 82);
    if (picked == null) return;
    final bytes = await File(picked.path).readAsBytes();
    if (mounted) setState(() => _photos.add(bytes));
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      final photosB64 = _photos.map((b) => base64Encode(b)).toList();
      await UellowApi.instance.reviews.create(
        productId: widget.line.productId, rating: _rating,
        body: _comment.text.trim().isEmpty ? null : _comment.text.trim(),
        photosBase64: photosB64.isEmpty ? null : photosB64);
      if (!mounted) return;
      Navigator.pop(context);
      final ar = UellowApi.instance.lang == 'ar';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ar ? 'شكراً على تقييمك!' : 'Thanks for your review!')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return AlertDialog(
      title: Text(widget.line.name.current(ar ? 'ar' : 'en'),
        maxLines: 2, overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(5, (i) {
          final v = i + 1;
          return IconButton(onPressed: () => setState(() => _rating = v.toDouble()),
            icon: Icon(_rating >= v ? Icons.star : Icons.star_border,
              color: UellowColors.warn, size: 28));
        })),
        const SizedBox(height: 8),
        TextField(controller: _comment, minLines: 2, maxLines: 5,
          decoration: InputDecoration(
            hintText: ar ? 'تعليقك (اختياري)' : 'Your comment (optional)',
            border: const OutlineInputBorder())),
        const SizedBox(height: 10),
        // ── Photo strip (max 5)
        SizedBox(height: 72, child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _photos.length + (_photos.length < _maxPhotos ? 1 : 0),
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            if (i == _photos.length) {
              return GestureDetector(
                onTap: _addPhoto,
                child: Container(
                  width: 64, height: 64,
                  decoration: BoxDecoration(
                    color: UellowColors.yellowSoft,
                    border: Border.all(color: UellowColors.yellow, width: 1.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.add_a_photo_outlined, color: UellowColors.darkBrown, size: 22),
                    const SizedBox(height: 2),
                    Text(UellowApi.instance.lang == 'ar' ? 'إضافة' : 'Add',
                        style: const TextStyle(fontSize: 9.5,
                        color: UellowColors.darkBrown, fontWeight: FontWeight.w800)),
                  ]),
                ),
              );
            }
            return Stack(clipBehavior: Clip.none, children: [
              ClipRRect(borderRadius: BorderRadius.circular(10),
                  child: Image.memory(_photos[i], width: 64, height: 64, fit: BoxFit.cover)),
              Positioned(top: -6, right: -6, child: GestureDetector(
                onTap: () => setState(() => _photos.removeAt(i)),
                child: Container(
                  width: 22, height: 22, alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: UellowColors.danger, shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 4)]),
                  child: const Icon(Icons.close, color: Colors.white, size: 14),
                ),
              )),
            ]);
          },
        )),
        if (_photos.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6),
            child: Text('${_photos.length}/$_maxPhotos ${ar ? "صور" : "photos"}',
                style: const TextStyle(fontSize: 11, color: UellowColors.muted))),
      ])),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(ar ? 'إلغاء' : 'Cancel')),
        ElevatedButton(onPressed: _busy ? null : _submit,
          child: _busy
            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
            : Text(ar ? 'إرسال' : 'Submit')),
      ],
    );
  }
}
