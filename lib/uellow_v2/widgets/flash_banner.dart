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
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../api/uellow_api.dart';

class FlashBanner extends StatelessWidget {
  const FlashBanner({super.key,
      this.endsAt, this.compact = false, this.edgeToEdge = false,
      this.discountPct, this.productCount,
      this.title, this.subtitle, this.onTap,
      this.colors, this.emoji, this.pattern = true,
      this.patternStyle, this.iconUrl, this.iconBg});
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
  /// v2.1.39 — named pattern style (one of [BannerPattern.styles]);
  /// overrides the default stripes when set. 'none' disables.
  final String? patternStyle;
  /// v2.1.39 — campaign icon IMAGE (replaces the discount circle / emoji
  /// in the leading slot when provided).
  final String? iconUrl;
  /// v2.1.43 — background color of the round icon holder.
  final Color? iconBg;
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
        // Pattern overlay — named style when set, legacy stripes else.
        if (pattern && (patternStyle ?? 'stripes') != 'none')
          Positioned.fill(child: IgnorePointer(
              child: CustomPaint(painter: BannerPattern(
                  style: patternStyle ?? 'stripes')))),
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
      // Leading slot — v2.1.39: 56→46 (it crowded the text) and priority:
      // campaign icon IMAGE > discount % > emoji.
      Container(
        width: 46, height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: iconBg ?? Colors.white,
          boxShadow: const [BoxShadow(
              color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2))],
        ),
        clipBehavior: Clip.antiAlias,
        alignment: Alignment.center,
        child: (iconUrl != null && iconUrl!.isNotEmpty)
            // v2.1.43 — contain + inset: the icon always sits CENTERED
            // and fully visible inside the circle (cover used to crop it).
            ? Padding(
                padding: const EdgeInsets.all(5),
                child: CachedNetworkImage(
                  imageUrl: iconUrl!, width: 36, height: 36,
                  fit: BoxFit.contain,
                  errorWidget: (_, __, ___) =>
                      Text(emoji ?? '⚡', style: const TextStyle(fontSize: 22)),
                ))
            : discountPct != null
            ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('-${discountPct}%', style: const TextStyle(
                    color: Color(0xFFEA580C), fontSize: 13.5,
                    fontWeight: FontWeight.w900, height: 1)),
                Text(UellowApi.instance.lang == 'ar' ? 'خصم' : 'OFF',
                    style: const TextStyle(color: Color(0xFFB91C1C),
                    fontSize: 7.5, fontWeight: FontWeight.w900,
                    letterSpacing: 0.6, height: 1)),
              ])
            : Text(emoji ?? '⚡', style: const TextStyle(fontSize: 22)),
      ),
      const SizedBox(width: 10),
      // Middle: title + subtitle
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center, children: [
        Row(children: [
          // v2.1.38 — Flexible + ellipsis: a long title can never run
          // under the countdown anymore.
          Flexible(child: Text(t, maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white,
                  fontSize: 15, fontWeight: FontWeight.w900,
                  letterSpacing: 0.3, height: 1.1))),
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
      // Right: D/H/M/S countdown — v2.1.38: smaller cells + a safe gap
      // from the text, and FittedBox auto-shrinks it on narrow screens.
      const SizedBox(width: 8),
      FittedBox(fit: BoxFit.scaleDown,
          child: _DhmsCounter(endsAt: endsAt, compact: false)),
    ]);
  }
}

// ─── Banner pattern engine (v2.1.39) ─────────────────────────────────
// 22 professional white-overlay patterns, selectable per promotion from
// the backend / per block from the builder. All deterministic.
class BannerPattern extends CustomPainter {
  BannerPattern({this.style = 'stripes'});
  final String style;

  static const styles = [
    'stripes', 'stripes_bold', 'crosshatch', 'mesh', 'grid',
    'dots', 'polka', 'bubbles', 'circles', 'rings', 'scales',
    'waves', 'zigzag', 'chevrons', 'diamonds', 'triangles', 'hexagons',
    'plus', 'sparkles', 'stars', 'confetti', 'moons',
  ];

  @override
  void paint(Canvas canvas, Size size) {
    const c = Color(0x16FFFFFF);
    final line = Paint()..color = c..strokeWidth = 3
        ..style = PaintingStyle.stroke;
    final fill = Paint()..color = c..style = PaintingStyle.fill;
    final w = size.width, h = size.height;
    final rnd = math.Random(7);   // fixed seed — stable artwork

    void diag(double spacing, double stroke) {
      final p = Paint()..color = c..strokeWidth = stroke;
      for (var x = -h; x < w; x += spacing) {
        canvas.drawLine(Offset(x, 0), Offset(x + h, h), p);
      }
    }

    switch (style) {
      case 'stripes_bold': diag(26, 10); break;
      case 'crosshatch':
        diag(18, 2);
        final p = Paint()..color = c..strokeWidth = 2;
        for (var x = 0.0; x < w + h; x += 18) {
          canvas.drawLine(Offset(x, 0), Offset(x - h, h), p);
        }
        break;
      case 'mesh':
        final p = Paint()..color = c..strokeWidth = 1.2;
        for (var x = 0.0; x < w; x += 16) {
          canvas.drawLine(Offset(x, 0), Offset(x, h), p);
        }
        for (var y = 0.0; y < h; y += 16) {
          canvas.drawLine(Offset(0, y), Offset(w, y), p);
        }
        break;
      case 'grid':
        final p = Paint()..color = c..strokeWidth = 2;
        for (var x = 0.0; x < w; x += 26) {
          canvas.drawLine(Offset(x, 0), Offset(x, h), p);
        }
        for (var y = 0.0; y < h; y += 26) {
          canvas.drawLine(Offset(0, y), Offset(w, y), p);
        }
        break;
      case 'dots':
        for (var x = 6.0; x < w; x += 16) {
          for (var y = 6.0; y < h; y += 16) {
            canvas.drawCircle(Offset(x, y), 1.6, fill);
          }
        }
        break;
      case 'polka':
        var row = 0;
        for (var y = 8.0; y < h; y += 20) {
          final off = (row.isOdd) ? 10.0 : 0.0;
          for (var x = 8.0 + off; x < w; x += 20) {
            canvas.drawCircle(Offset(x, y), 3.4, fill);
          }
          row++;
        }
        break;
      case 'bubbles':
        for (var i = 0; i < 26; i++) {
          canvas.drawCircle(
              Offset(rnd.nextDouble() * w, rnd.nextDouble() * h),
              3 + rnd.nextDouble() * 9, fill);
        }
        break;
      case 'circles':
        for (var x = 14.0; x < w; x += 34) {
          for (var y = 14.0; y < h; y += 34) {
            canvas.drawCircle(Offset(x, y), 9, line..strokeWidth = 1.6);
          }
        }
        break;
      case 'rings':
        for (var r = 12.0; r < math.max(w, h); r += 22) {
          canvas.drawCircle(Offset(w, 0), r, line..strokeWidth = 2);
        }
        break;
      case 'scales':
        var srow = 0;
        for (var y = 0.0; y <= h + 16; y += 13) {
          final off = srow.isOdd ? 13.0 : 0.0;
          for (var x = -13.0 + off; x < w + 13; x += 26) {
            canvas.drawArc(Rect.fromCircle(
                center: Offset(x, y), radius: 13),
                0, math.pi, false, line..strokeWidth = 1.6);
          }
          srow++;
        }
        break;
      case 'waves':
        final p = Paint()..color = c..strokeWidth = 2
            ..style = PaintingStyle.stroke;
        for (var y = 8.0; y < h; y += 16) {
          final path = Path()..moveTo(0, y);
          for (var x = 0.0; x < w; x += 24) {
            path.quadraticBezierTo(x + 6, y - 6, x + 12, y);
            path.quadraticBezierTo(x + 18, y + 6, x + 24, y);
          }
          canvas.drawPath(path, p);
        }
        break;
      case 'zigzag':
        final p = Paint()..color = c..strokeWidth = 2
            ..style = PaintingStyle.stroke;
        for (var y = 8.0; y < h; y += 18) {
          final path = Path()..moveTo(0, y);
          var up = true;
          for (var x = 0.0; x < w; x += 12) {
            path.lineTo(x + 12, up ? y - 6 : y + 6);
            up = !up;
          }
          canvas.drawPath(path, p);
        }
        break;
      case 'chevrons':
        final p = Paint()..color = c..strokeWidth = 3
            ..style = PaintingStyle.stroke;
        for (var x = 0.0; x < w + 20; x += 24) {
          final path = Path()
            ..moveTo(x, h)..lineTo(x + 12, h / 2)..lineTo(x, 0);
          canvas.drawPath(path, p);
        }
        break;
      case 'diamonds':
        for (var x = 14.0; x < w; x += 30) {
          for (var y = 12.0; y < h; y += 30) {
            final path = Path()
              ..moveTo(x, y - 7)..lineTo(x + 7, y)
              ..lineTo(x, y + 7)..lineTo(x - 7, y)..close();
            canvas.drawPath(path, fill);
          }
        }
        break;
      case 'triangles':
        for (var x = 12.0; x < w; x += 28) {
          for (var y = 14.0; y < h; y += 28) {
            final path = Path()
              ..moveTo(x, y - 7)..lineTo(x + 7, y + 6)
              ..lineTo(x - 7, y + 6)..close();
            canvas.drawPath(path, line..strokeWidth = 1.6);
          }
        }
        break;
      case 'hexagons':
        for (var x = 16.0; x < w; x += 34) {
          for (var y = 16.0; y < h; y += 32) {
            final path = Path();
            for (var i = 0; i < 6; i++) {
              final a = math.pi / 3 * i + math.pi / 6;
              final pt = Offset(x + 9 * math.cos(a), y + 9 * math.sin(a));
              i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
            }
            path.close();
            canvas.drawPath(path, line..strokeWidth = 1.6);
          }
        }
        break;
      case 'plus':
        final p = Paint()..color = c..strokeWidth = 2.4;
        for (var x = 12.0; x < w; x += 26) {
          for (var y = 12.0; y < h; y += 26) {
            canvas.drawLine(Offset(x - 4, y), Offset(x + 4, y), p);
            canvas.drawLine(Offset(x, y - 4), Offset(x, y + 4), p);
          }
        }
        break;
      case 'sparkles':
        for (var i = 0; i < 22; i++) {
          final x = rnd.nextDouble() * w, y = rnd.nextDouble() * h;
          final r = 2 + rnd.nextDouble() * 3;
          final p = Paint()..color = c..strokeWidth = 1.6;
          canvas.drawLine(Offset(x - r, y), Offset(x + r, y), p);
          canvas.drawLine(Offset(x, y - r), Offset(x, y + r), p);
        }
        break;
      case 'stars':
        for (var i = 0; i < 16; i++) {
          final cx = rnd.nextDouble() * w, cy = rnd.nextDouble() * h;
          final r = 3 + rnd.nextDouble() * 4;
          final path = Path();
          for (var k = 0; k < 8; k++) {
            final rr = k.isEven ? r : r / 2.6;
            final a = math.pi / 4 * k - math.pi / 2;
            final pt = Offset(cx + rr * math.cos(a), cy + rr * math.sin(a));
            k == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
          }
          path.close();
          canvas.drawPath(path, fill);
        }
        break;
      case 'confetti':
        for (var i = 0; i < 30; i++) {
          final x = rnd.nextDouble() * w, y = rnd.nextDouble() * h;
          canvas.save();
          canvas.translate(x, y);
          canvas.rotate(rnd.nextDouble() * math.pi);
          canvas.drawRect(
              const Rect.fromLTWH(-3, -1.4, 6, 2.8), fill);
          canvas.restore();
        }
        break;
      case 'moons':
        for (var x = 18.0; x < w; x += 40) {
          for (var y = 16.0; y < h; y += 36) {
            canvas.drawArc(Rect.fromCircle(
                center: Offset(x, y), radius: 8),
                math.pi * 0.25, math.pi * 1.1, false,
                line..strokeWidth = 2);
          }
        }
        break;
      case 'stripes':
      default:
        diag(14, 4);
    }
  }

  @override
  bool shouldRepaint(covariant BannerPattern old) => old.style != style;
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
    // v2.1.38 — full cells shrunk 32→26 (they crowded the banner title).
    final sz = widget.compact ? 14.0 : 26.0;
    final fs = widget.compact ? 8.0 : 11.0;
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
