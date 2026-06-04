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
      this.title, this.subtitle, this.onTap,
      this.colors, this.emoji, this.pattern = true});
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
  // v2.1.35 — promotion banners reuse this widget with their own look:
  /// Override gradient colors (1 color = solid, 2+ = gradient).
  final List<Color>? colors;
  /// Override the left icon (⚡ by default) with the campaign emoji.
  final String? emoji;
  /// Diagonal shimmer stripes on/off.
  final bool pattern;
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
        // Base gradient (overridable per campaign)
        Positioned.fill(child: Container(
          decoration: BoxDecoration(
            gradient: (colors != null && colors!.isNotEmpty)
                ? LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: colors!.length == 1
                        ? [colors!.first, colors!.first]
                        : colors!,
                  )
                : const LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [Color(0xFFFFD340), Color(0xFFF59E0B),
                        Color(0xFFEA580C), Color(0xFFB91C1C)],
                    stops: [0.0, 0.45, 0.78, 1.0],
                  ),
          ),
        )),
        // Diagonal shimmer
        if (pattern) Positioned.fill(child: IgnorePointer(
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
                Text(UellowApi.instance.lang == 'ar' ? 'خصم' : 'OFF',
                    style: const TextStyle(color: Color(0xFFB91C1C),
                    fontSize: 8, fontWeight: FontWeight.w900,
                    letterSpacing: 0.6, height: 1)),
              ])
            : Text(emoji ?? '⚡', style: const TextStyle(fontSize: 28)),
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
    final ar = UellowApi.instance.lang == 'ar';
    final d = _left.inDays;
    final h = _left.inHours.remainder(24);
    final m = _left.inMinutes.remainder(60);
    final s = _left.inSeconds.remainder(60);
    // v2.1.35 — full variant: localized unit label ABOVE the number
    // (يوم/ساعة/دقيقة/ثانية), per request. Compact keeps the tiny letter.
    final labels = ar
        ? const ['يوم', 'ساعة', 'دقيقة', 'ثانية']
        : const ['DAY', 'HR', 'MIN', 'SEC'];
    final sz = widget.compact ? 14.0 : 32.0;
    final fs = widget.compact ? 8.0 : 13.0;
    final vals = [_two(d), _two(h), _two(m), _two(s)];
    final letters = const ['D', 'H', 'M', 'S'];
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < 4; i++) ...[
        if (i > 0) const SizedBox(width: 3),
        widget.compact
            ? _cell(vals[i], letters[i], sz, fs)
            : _labeledCell(vals[i], labels[i], sz, fs),
      ],
    ]);
  }
  Widget _labeledCell(String v, String u, double sz, double fs) => Container(
    width: sz + 2, height: sz + 6,
    decoration: BoxDecoration(
      color: const Color(0xD9000000),
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: const Color(0x40FFFFFF), width: 0.5),
    ),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text(u, maxLines: 1,
          style: const TextStyle(color: Color(0xB3FFFFFF),
              fontSize: 6.5, fontWeight: FontWeight.w800, height: 1.1)),
      const SizedBox(height: 1),
      Text(v, style: TextStyle(color: Colors.white,
          fontSize: fs, fontWeight: FontWeight.w900,
          height: 1, fontFamily: 'monospace')),
    ]),
  );
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
