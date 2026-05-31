// =============================================================================
// FlashBanner — unified flash-sale strip used across:
//   • Home flash block header
//   • Product page under the gallery (when product is in active sale)
//   • Flash screen hero (compact mode optional)
//
// Yellow → orange → red gradient, diagonal shimmer pattern, ⚡ icon,
// live D/H/M/S countdown, optional "% OFF" badge and right-side meta.
// =============================================================================
import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/uellow_api.dart';

class FlashBanner extends StatelessWidget {
  const FlashBanner({super.key,
      this.endsAt, this.compact = false, this.edgeToEdge = false,
      this.discountPct, this.productCount,
      this.title, this.subtitle, this.onTap});
  /// Sale end timestamp. If null, shows a placeholder D/H/M/S.
  final DateTime? endsAt;
  /// When true, renders the slim 36px-tall strip (for under product image).
  final bool compact;
  /// When true: no rounded corners, no horizontal margin — banner runs
  /// flush to both screen edges. Used on the product detail page.
  final bool edgeToEdge;
  /// Optional headline discount % to render as a circular badge.
  final int? discountPct;
  /// Optional product count to render as right-side meta.
  final int? productCount;
  /// Override title / subtitle copy (defaults to "FLASH SALE" / sub).
  final String? title, subtitle;
  /// Optional tap handler — wraps the whole banner in a Material InkWell.
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    final h = compact ? 36.0 : 88.0;
    final t = title ?? (ar ? 'فلاش سيل' : 'FLASH SALE');
    final sub = subtitle
        ?? (ar ? 'خصومات تصل إلى 70%' : 'Up to 70% OFF — hurry!');
    final radius = edgeToEdge ? 0.0 : (compact ? 10.0 : 14.0);
    final body = Container(
      height: h,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: edgeToEdge ? null : const [BoxShadow(
            color: Color(0x33EA580C), blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: Stack(children: [
        // Base gradient
        Positioned.fill(child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Color(0xFFFFD340), Color(0xFFF59E0B),
                  Color(0xFFEA580C), Color(0xFFB91C1C)],
              stops: [0.0, 0.45, 0.78, 1.0],
            ),
          ),
        )),
        // Diagonal shimmer
        Positioned.fill(child: IgnorePointer(
            child: CustomPaint(painter: _DiagonalStripes()))),
        // Subtle glossy top
        Positioned.fill(child: IgnorePointer(child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.center,
                colors: [Color(0x40FFFFFF), Colors.transparent],
              ),
            )))),
        Padding(
          padding: EdgeInsets.symmetric(
              horizontal: compact ? 10 : 14,
              vertical: compact ? 4 : 8),
          child: compact ? _compactRow(t) : _fullRow(t, sub, ar),
        ),
      ]),
    );
    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: body,
      ),
    );
  }

  Widget _compactRow(String t) {
    // Title on top-left, counter pinned to bottom-right corner — slim
    // strip that doesn't crowd the product gallery below it.
    return Stack(children: [
      Padding(padding: const EdgeInsets.only(top: 4, left: 2),
        child: Row(children: [
          const Icon(Icons.flash_on, color: Colors.white, size: 13),
          const SizedBox(width: 3),
          Text(t, style: const TextStyle(color: Colors.white,
              fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.3)),
        ]),
      ),
      Positioned(bottom: 1, right: 0,
          child: _DhmsCounter(endsAt: endsAt, compact: true)),
    ]);
  }

  Widget _fullRow(String t, String sub, bool ar) {
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      // Left: discount circular badge or lightning bolt
      Container(
        width: 56, height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          boxShadow: const [BoxShadow(
              color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2))],
        ),
        alignment: Alignment.center,
        child: discountPct != null
            ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('-${discountPct}%', style: const TextStyle(
                    color: Color(0xFFEA580C), fontSize: 16,
                    fontWeight: FontWeight.w900, height: 1)),
                const Text('OFF', style: TextStyle(color: Color(0xFFB91C1C),
                    fontSize: 8, fontWeight: FontWeight.w900,
                    letterSpacing: 0.6, height: 1)),
              ])
            : const Text('⚡', style: TextStyle(fontSize: 28)),
      ),
      const SizedBox(width: 12),
      // Middle: title + subtitle
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center, children: [
        Row(children: [
          Text(t, style: const TextStyle(color: Colors.white,
              fontSize: 16, fontWeight: FontWeight.w900,
              letterSpacing: 0.4, height: 1.1)),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4)),
            child: Text(ar ? 'الآن' : 'LIVE', style: const TextStyle(
                color: Color(0xFFB91C1C), fontSize: 8.5,
                fontWeight: FontWeight.w900, letterSpacing: 0.5)),
          ),
        ]),
        const SizedBox(height: 4),
        Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xE6FFFFFF),
                fontSize: 11, fontWeight: FontWeight.w600, height: 1.2)),
        if (productCount != null) Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(ar
              ? '$productCount منتج · جاهز'
              : '$productCount items · in stock',
              style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 10)),
        ),
      ])),
      // Right: D/H/M/S countdown
      _DhmsCounter(endsAt: endsAt, compact: false),
    ]);
  }
}

class _DiagonalStripes extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x14FFFFFF)
      ..strokeWidth = 4;
    const spacing = 14.0;
    for (var x = -size.height.toDouble(); x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0),
          Offset(x + size.height, size.height), paint);
    }
  }
  @override
  bool shouldRepaint(covariant _) => false;
}

class _DhmsCounter extends StatefulWidget {
  const _DhmsCounter({required this.endsAt, required this.compact});
  final DateTime? endsAt;
  final bool compact;
  @override
  State<_DhmsCounter> createState() => _DhmsCounterState();
}

class _DhmsCounterState extends State<_DhmsCounter> {
  Timer? _t;
  Duration _left = const Duration(days: 1, hours: 4, minutes: 35);
  @override
  void initState() {
    super.initState();
    _tick();
    _t = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }
  void _tick() {
    if (!mounted) return;
    setState(() {
      if (widget.endsAt != null) {
        final d = widget.endsAt!.difference(DateTime.now());
        _left = d.isNegative ? Duration.zero : d;
      } else {
        _left = _left.inSeconds > 0
            ? _left - const Duration(seconds: 1)
            : const Duration(days: 1);
      }
    });
  }
  @override
  void dispose() { _t?.cancel(); super.dispose(); }
  String _two(int n) => n.toString().padLeft(2, '0');
  @override
  Widget build(BuildContext context) {
    final d = _left.inDays;
    final h = _left.inHours.remainder(24);
    final m = _left.inMinutes.remainder(60);
    final s = _left.inSeconds.remainder(60);
    final sz = widget.compact ? 14.0 : 30.0;
    final fs = widget.compact ? 8.0 : 14.0;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _cell(_two(d), 'D', sz, fs), const SizedBox(width: 3),
      _cell(_two(h), 'H', sz, fs), const SizedBox(width: 3),
      _cell(_two(m), 'M', sz, fs), const SizedBox(width: 3),
      _cell(_two(s), 'S', sz, fs),
    ]);
  }
  Widget _cell(String v, String u, double sz, double fs) => Container(
    width: sz, height: sz, alignment: Alignment.center,
    decoration: BoxDecoration(
      color: const Color(0xD9000000),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: const Color(0x40FFFFFF), width: 0.5),
    ),
    child: Stack(alignment: Alignment.center, children: [
      Text(v, style: TextStyle(color: Colors.white,
          fontSize: fs, fontWeight: FontWeight.w900,
          height: 1, fontFamily: 'monospace')),
      Positioned(bottom: 0.5, right: 1, child: Text(u,
          style: TextStyle(color: const Color(0x99FFFFFF),
              fontSize: widget.compact ? 6.5 : 7,
              fontWeight: FontWeight.w800))),
    ]),
  );
}
