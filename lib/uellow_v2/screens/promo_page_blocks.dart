// =============================================================================
// v2.2.06 — PROMOTION PAGE blocks (10 designs) for builder-designed
// campaign landing pages. The hero header pulls the live promotion record
// (name/logo/colors/end date) and offers 7 selectable ANIMATIONS; every
// block is fully colour-customisable from the builder.
// =============================================================================
import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/uellow_api.dart';
import '../../api/uellow_models.dart';
import '../router/uellow_router.dart';
import 'dynamic_block_extras.dart'
    show blockMargin, blockRadius, blockOverlay, blockOverlayCustom,
         pickLocalizedImage;
import 'product_screen.dart' show MidStrikePrice;
import '../theme/uellow_theme.dart';
import '../widgets/flash_banner.dart' show BannerPattern;
import '../widgets/product_card.dart';

Color? promoParseColor(dynamic v) {
  if (v == null) return null;
  var s = v.toString().replaceAll('#', '').trim();
  if (s.isEmpty) return null;
  if (s.length == 6) s = 'FF$s';
  final n = int.tryParse(s, radix: 16);
  return n == null ? null : Color(n);
}

List<UellowProductCard> promoItems(Map<String, dynamic> data) =>
    ((data['items'] as List?) ?? const [])
        .map((e) {
          try {
            return UellowProductCard.fromJson((e as Map).cast<String, dynamic>());
          } catch (_) {
            return null;
          }
        })
        .whereType<UellowProductCard>()
        .toList();

String _abs(String u) =>
    u.startsWith('http') ? u : '${UellowApi.instance.baseUrl}$u';

// ─── live countdown helper ──────────────────────────────────────────────
class PromoCountdown extends StatefulWidget {
  const PromoCountdown({super.key, required this.endsAt, this.color,
      this.boxColor, this.compact = false, this.labelColor, this.scale = 1.0});
  final DateTime? endsAt;
  final Color? color;
  final Color? boxColor;
  final bool compact;
  // v2.2.11 — separate label colour + a size multiplier (sm/md/lg in hero).
  final Color? labelColor;
  final double scale;
  @override
  State<PromoCountdown> createState() => _PromoCountdownState();
}

class _PromoCountdownState extends State<PromoCountdown> {
  Timer? _t;
  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1),
        (_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() { _t?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    final end = widget.endsAt;
    if (end == null) return const SizedBox.shrink();
    var d = end.difference(DateTime.now());
    if (d.isNegative) d = Duration.zero;
    final parts = [
      (d.inDays, ar ? 'يوم' : 'D'),
      (d.inHours % 24, ar ? 'ساعة' : 'H'),
      (d.inMinutes % 60, ar ? 'دقيقة' : 'M'),
      (d.inSeconds % 60, ar ? 'ثانية' : 'S'),
    ];
    final fg = widget.color ?? Colors.white;
    final lc = widget.labelColor ?? fg.withValues(alpha: .8);
    final bg = widget.boxColor ?? Colors.white.withValues(alpha: .18);
    final sc = widget.scale;
    final sz = (widget.compact ? 13.0 : 19.0) * sc;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < parts.length; i++) ...[
        Container(
          padding: EdgeInsets.symmetric(
              horizontal: (widget.compact ? 7 : 10) * sc,
              vertical: (widget.compact ? 4 : 7) * sc),
          decoration: BoxDecoration(color: bg,
              borderRadius: BorderRadius.circular(10)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${parts[i].$1}'.padLeft(2, '0'),
                style: TextStyle(color: fg, fontSize: sz,
                    fontWeight: FontWeight.w900,
                    fontFeatures: const [FontFeature.tabularFigures()])),
            if (!widget.compact)
              Text(parts[i].$2, style: TextStyle(
                  color: lc, fontSize: 8.5 * sc,
                  fontWeight: FontWeight.w700)),
          ]),
        ),
        if (i < parts.length - 1)
          Padding(padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Text(':', style: TextStyle(color: fg,
                  fontWeight: FontWeight.w900, fontSize: sz))),
      ],
    ]);
  }
}

// ─── animated backgrounds (7 styles) ────────────────────────────────────
class _AnimatedPromoBg extends StatefulWidget {
  const _AnimatedPromoBg({required this.style, required this.c1,
      required this.c2, required this.c3});
  final String style;
  final Color c1, c2, c3;
  @override
  State<_AnimatedPromoBg> createState() => _AnimatedPromoBgState();
}

class _AnimatedPromoBgState extends State<_AnimatedPromoBg>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(seconds: 6))..repeat();

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = _c.value;
        switch (widget.style) {
          case 'aurora':
            return Container(decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(-1 + 2 * t, -1),
                end: Alignment(1 - 2 * t, 1),
                colors: [widget.c1, widget.c2, widget.c3, widget.c1],
              ),
            ));
          case 'pulse':
            final s = 0.85 + 0.3 * (0.5 + 0.5 * math.sin(t * 2 * math.pi));
            return Container(
              decoration: BoxDecoration(color: widget.c2),
              child: Center(child: Container(
                width: 600 * s, height: 600 * s,
                decoration: BoxDecoration(shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [
                      widget.c1.withValues(alpha: .8),
                      widget.c2.withValues(alpha: 0)
                    ])),
              )),
            );
          case 'wave':
            return CustomPaint(
              painter: _WavePainter(t, widget.c1, widget.c2, widget.c3),
              child: const SizedBox.expand(),
            );
          case 'particles':
            return CustomPaint(
              painter: _ParticlesPainter(t, widget.c1, widget.c2, widget.c3),
              child: const SizedBox.expand(),
            );
          case 'confetti':
            return CustomPaint(
              painter: _ConfettiPainter(t, widget.c1, widget.c2, widget.c3),
              child: const SizedBox.expand(),
            );
          case 'shimmer':
            return Container(
              decoration: BoxDecoration(gradient: LinearGradient(
                  colors: [widget.c1, widget.c2])),
              foregroundDecoration: BoxDecoration(gradient: LinearGradient(
                begin: Alignment(-1.5 + 3 * t, 0),
                end: Alignment(-0.5 + 3 * t, 0),
                colors: [Colors.white.withValues(alpha: 0),
                         Colors.white.withValues(alpha: .35),
                         Colors.white.withValues(alpha: 0)],
              )),
            );
          default: // none → static gradient
            return Container(decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [widget.c1, widget.c2])));
        }
      },
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.t, this.c1, this.c2, this.c3);
  final double t;
  final Color c1, c2, c3;
  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawRect(Offset.zero & s,
        Paint()..shader = LinearGradient(colors: [c1, c2])
            .createShader(Offset.zero & s));
    for (final (amp, speed, color, base) in [
      (14.0, 1.0, c3.withValues(alpha: .35), .62),
      (20.0, -0.7, Colors.white.withValues(alpha: .15), .72),
      (10.0, 1.4, c3.withValues(alpha: .22), .82),
    ]) {
      final p = Path()..moveTo(0, s.height);
      for (double x = 0; x <= s.width; x += 6) {
        p.lineTo(x, s.height * base +
            amp * math.sin((x / s.width * 2 * math.pi) +
                t * 2 * math.pi * speed));
      }
      p..lineTo(s.width, s.height)..close();
      canvas.drawPath(p, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) => old.t != t;
}

class _ParticlesPainter extends CustomPainter {
  _ParticlesPainter(this.t, this.c1, this.c2, this.c3);
  final double t;
  final Color c1, c2, c3;
  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawRect(Offset.zero & s,
        Paint()..shader = LinearGradient(begin: Alignment.topLeft,
            end: Alignment.bottomRight, colors: [c1, c2])
            .createShader(Offset.zero & s));
    final rnd = math.Random(7);
    for (var i = 0; i < 26; i++) {
      final bx = rnd.nextDouble(), by = rnd.nextDouble();
      final r = 2.0 + rnd.nextDouble() * 5;
      final y = (by - t * (0.15 + rnd.nextDouble() * .2)) % 1.0;
      canvas.drawCircle(Offset(bx * s.width, y * s.height), r,
          Paint()..color = (i.isEven ? Colors.white : c3)
              .withValues(alpha: .25 + rnd.nextDouble() * .3));
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlesPainter old) => old.t != t;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.t, this.c1, this.c2, this.c3);
  final double t;
  final Color c1, c2, c3;
  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawRect(Offset.zero & s,
        Paint()..shader = LinearGradient(colors: [c1, c2])
            .createShader(Offset.zero & s));
    final rnd = math.Random(11);
    final colors = [c3, Colors.white, const Color(0xFFFF6B6B),
        const Color(0xFF4ECDC4), const Color(0xFFFFE66D)];
    for (var i = 0; i < 30; i++) {
      final bx = rnd.nextDouble();
      final speed = .25 + rnd.nextDouble() * .4;
      final y = (rnd.nextDouble() + t * speed) % 1.0;
      final rot = (t * 4 + i) * math.pi;
      canvas.save();
      canvas.translate(bx * s.width, y * s.height);
      canvas.rotate(rot);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset.zero,
                  width: 7, height: 4 + rnd.nextDouble() * 5),
              const Radius.circular(1.5)),
          Paint()..color = colors[i % colors.length]
              .withValues(alpha: .85));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => old.t != t;
}

// ═══ 1. PROMO HERO — premium animated campaign header ══════════════════
// v2.2.09 — designer rework: layered glow blobs, gradient display title,
// heroic discount line ("UP TO 70%"), glass countdown with unit labels,
// kicker chip, sparkle accents, optional CTA and a curved bottom edge.
class PromoHeroBlock extends StatelessWidget {
  const PromoHeroBlock({super.key, required this.p, required this.data,
      required this.ar, this.onCta});
  final Map<String, dynamic> p;
  final Map<String, dynamic> data;
  final bool ar;
  final VoidCallback? onCta;

  @override
  Widget build(BuildContext context) {
    final promo = (data['promo'] as Map?)?.cast<String, dynamic>();
    final c1 = promoParseColor(p['c1'])
        ?? promoParseColor(promo?['c1']) ?? UellowColors.yellow;
    final c2 = promoParseColor(p['c2'])
        ?? promoParseColor(promo?['c2']) ?? const Color(0xFFC99000);
    final c3 = promoParseColor(p['c3']) ?? Colors.white;
    final txt = promoParseColor(p['text_color']) ?? Colors.white;
    final anim = (p['animation'] ?? 'aurora').toString();
    final h = ((p['height'] as num?)?.toDouble() ?? 210).clamp(140, 460)
        .toDouble();
    final title = _tx(p, 'titleEn', 'titleAr', ar).isNotEmpty
        ? _tx(p, 'titleEn', 'titleAr', ar)
        : ((promo?['name'] as Map?)?[ar ? 'ar' : 'en'] ?? '').toString();
    final sub = _tx(p, 'subEn', 'subAr', ar).isNotEmpty
        ? _tx(p, 'subEn', 'subAr', ar)
        : ((promo?['subtitle'] as Map?)?[ar ? 'ar' : 'en'] ?? '').toString();
    final kicker = _tx(p, 'kickerEn', 'kickerAr', ar);
    final discount = (p['discount_text'] ?? '').toString().trim();
    final cta = _tx(p, 'ctaEn', 'ctaAr', ar);
    final logo = (p['logo_image'] ?? promo?['logo'] ?? '').toString();
    final emoji = (p['emoji'] ?? promo?['emoji'] ?? '🎉').toString();
    final endsRaw = (p['ends_at'] ?? promo?['ends_at'] ?? '').toString();
    final ends = DateTime.tryParse(endsRaw);
    final showCd = p['show_countdown'] != false && ends != null;
    final pattern = (p['pattern'] ?? promo?['pattern'] ?? 'none').toString();
    final curved = p['bottom_curve'] != false;
    // v2.2.11 — background image slider + configurable countdown.
    final bgImages = ((p['bg_images'] as List?) ?? const [])
        .map((e) => _abs(e.toString()))
        .where((s) => s.isNotEmpty && s != _abs('')).toList();
    final slideInterval =
        ((p['slide_interval'] as num?)?.toInt() ?? 4).clamp(2, 12);
    final cdPos = (p['countdown_position'] ?? 'bottom-center').toString();
    final cdSize = (p['countdown_size'] ?? 'sm').toString();
    final cdBox = promoParseColor(p['countdown_box_color'])
        ?? Colors.black.withValues(alpha: .45);
    final cdText = promoParseColor(p['countdown_text_color']) ?? Colors.white;
    final cdLabel = promoParseColor(p['countdown_label_color']) ?? Colors.white;

    final core = SizedBox(
      height: h,
      child: Stack(fit: StackFit.expand, children: [
        _AnimatedPromoBg(style: anim, c1: c1, c2: c2, c3: c3),
        if (bgImages.isNotEmpty) Positioned.fill(
            child: _HeroBgSlider(images: bgImages, interval: slideInterval)),
        if (pattern != 'none')
          CustomPaint(painter: BannerPattern(style: pattern),
              child: const SizedBox.expand()),
        // depth: two oversized glow blobs
        Positioned(top: -70, left: -50, child: _glow(c3, 190)),
        Positioned(bottom: -90, right: -60, child: _glow(Colors.white, 230)),
        // legibility veil — v2.2.17: admin override via overlay_color/
        // overlay_opacity (solid); default stays the soft gradient.
        if (blockOverlayCustom(p))
          Container(color: blockOverlay(p) ?? Colors.transparent)
        else
          Container(decoration: BoxDecoration(gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Colors.black.withValues(alpha: .05),
                       Colors.black.withValues(alpha: .28)]))),
        // sparkle accents
        const Positioned(top: 18, right: 26,
            child: Text('✦', style: TextStyle(
                color: Colors.white70, fontSize: 17))),
        const Positioned(top: 52, left: 22,
            child: Text('✧', style: TextStyle(
                color: Colors.white38, fontSize: 12))),
        Positioned(bottom: curved ? 48 : 26, right: 38,
            child: const Text('✦', style: TextStyle(
                color: Colors.white38, fontSize: 11))),
        SafeArea(bottom: false, child: Padding(
          padding: EdgeInsets.fromLTRB(18, 12, 18, curved ? 30 : 16),
          child: Column(mainAxisAlignment: MainAxisAlignment.center,
              children: [
            // ── logo + kicker row ──
            Row(mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center, children: [
              _logoRing(logo, emoji, 44),
              if (kicker.isNotEmpty) ...[
                const SizedBox(width: 9),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 11, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .16),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: .4)),
                  ),
                  child: Text(kicker.toUpperCase(), style: TextStyle(
                      color: txt, fontSize: 10.5, letterSpacing: 1.4,
                      fontWeight: FontWeight.w900)),
                ),
              ],
            ]),
            const SizedBox(height: 8),
            // ── display title with gradient sheen ──
            ShaderMask(
              shaderCallback: (r) => LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [txt, txt.withValues(alpha: .82)]).createShader(r),
              child: Text(title, textAlign: TextAlign.center, maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: txt, height: 1.08,
                      fontSize: discount.isNotEmpty ? 21 : 26,
                      fontWeight: FontWeight.w900, letterSpacing: -.3,
                      shadows: const [Shadow(color: Color(0x66000000),
                          blurRadius: 10, offset: Offset(0, 3))])),
            ),
            // ── heroic discount line ──
            if (discount.isNotEmpty) Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center, children: [
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(ar ? 'خصم' : 'UP', style: TextStyle(color: txt,
                      fontSize: 13, height: 1.05,
                      fontWeight: FontWeight.w900)),
                  Text(ar ? 'حتى' : 'TO', style: TextStyle(
                      color: txt.withValues(alpha: .85), fontSize: 13,
                      height: 1.05, fontWeight: FontWeight.w900)),
                ]),
                const SizedBox(width: 7),
                ShaderMask(
                  shaderCallback: (r) => LinearGradient(
                      colors: [c3, Colors.white]).createShader(r),
                  child: Text(discount, style: const TextStyle(
                      color: Colors.white, fontSize: 42, height: 1.0,
                      fontWeight: FontWeight.w900, fontStyle: FontStyle.italic,
                      letterSpacing: -1,
                      shadows: [Shadow(color: Color(0x73000000),
                          blurRadius: 14, offset: Offset(0, 4))])),
                ),
              ]),
            ),
            if (sub.isNotEmpty) Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(sub, textAlign: TextAlign.center, maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: txt.withValues(alpha: .9),
                      fontSize: 12, fontWeight: FontWeight.w600)),
            ),
            if (cta.isNotEmpty) Padding(
              padding: const EdgeInsets.only(top: 10),
              child: GestureDetector(
                onTap: onCta,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 22, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: const [BoxShadow(color: Color(0x59000000),
                        blurRadius: 12, offset: Offset(0, 4))],
                  ),
                  child: Text(cta, style: TextStyle(color: c2,
                      fontSize: 13.5, fontWeight: FontWeight.w900)),
                ),
              ),
            ),
          ]),
        )),
        // v2.2.11 — countdown rendered as a positioned overlay so it keeps
        // its anchor (and rises automatically) when the height is reduced.
        if (showCd) _heroCountdown(
            cdPos, cdSize, ends, cdBox, cdText, cdLabel, ar, curved),
      ]),
    );

    if (!curved) {
      return Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(24)),
          boxShadow: [BoxShadow(color: c2.withValues(alpha: .35),
              blurRadius: 18, offset: const Offset(0, 8))],
        ),
        child: core,
      );
    }
    return ClipPath(clipper: _HeroWaveClipper(), child: core);
  }

  Widget _glow(Color c, double size) => Container(
        width: size, height: size,
        decoration: BoxDecoration(shape: BoxShape.circle,
            gradient: RadialGradient(colors: [
              c.withValues(alpha: .35), c.withValues(alpha: 0)])),
      );

  Widget _logoRing(String logo, String emoji, double d) => Container(
        width: d, height: d,
        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white,
            border: Border.all(
                color: Colors.white.withValues(alpha: .6), width: 2.5),
            boxShadow: const [BoxShadow(color: Color(0x4D000000),
                blurRadius: 12, offset: Offset(0, 4))]),
        clipBehavior: Clip.antiAlias,
        alignment: Alignment.center,
        child: logo.isNotEmpty
            ? CachedNetworkImage(imageUrl: _abs(logo), width: d, height: d,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Text(emoji,
                    style: TextStyle(fontSize: d * .48)))
            : Text(emoji, style: TextStyle(fontSize: d * .48)),
      );

  // v2.2.11 — countdown overlay anchored by the builder's position setting.
  Widget _heroCountdown(String pos, String size, DateTime ends, Color box,
      Color text, Color label, bool ar, bool curved) {
    const aligns = {
      'top-left': Alignment.topLeft, 'top-center': Alignment.topCenter,
      'top-right': Alignment.topRight, 'center': Alignment.center,
      'bottom-left': Alignment.bottomLeft, 'bottom-center': Alignment.bottomCenter,
      'bottom-right': Alignment.bottomRight,
    };
    final align = aligns[pos] ?? Alignment.bottomCenter;
    final compact = size == 'sm';
    final scale = size == 'lg' ? 1.25 : (size == 'md' ? 1.0 : 0.9);
    return Positioned.fill(child: Padding(
      padding: EdgeInsets.fromLTRB(14, 14, 14, curved ? 30 : 14),
      child: Align(alignment: align, child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center, children: [
        Text(ar ? '⏰ ينتهي خلال' : '⏰ ENDS IN',
            style: TextStyle(color: label, fontSize: 9.5 * scale,
                letterSpacing: 1.1, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        PromoCountdown(endsAt: ends, color: text, boxColor: box,
            labelColor: label, compact: compact, scale: scale),
      ]))));
  }
}

// v2.2.11 — auto-advancing background image slider for the Promo Hero.
class _HeroBgSlider extends StatefulWidget {
  const _HeroBgSlider({required this.images, required this.interval});
  final List<String> images;
  final int interval;
  @override
  State<_HeroBgSlider> createState() => _HeroBgSliderState();
}

class _HeroBgSliderState extends State<_HeroBgSlider> {
  final _ctrl = PageController();
  int _i = 0;
  Timer? _t;
  @override
  void initState() {
    super.initState();
    if (widget.images.length > 1) {
      _t = Timer.periodic(Duration(seconds: widget.interval), (_) {
        if (!mounted || !_ctrl.hasClients) return;
        _i = (_i + 1) % widget.images.length;
        _ctrl.animateToPage(_i,
            duration: const Duration(milliseconds: 600), curve: Curves.easeInOut);
      });
    }
  }
  @override
  void dispose() { _t?.cancel(); _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    if (widget.images.length == 1) {
      return Image.network(widget.images.first, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const SizedBox.shrink());
    }
    return PageView.builder(
      controller: _ctrl,
      itemCount: widget.images.length,
      itemBuilder: (_, i) => Image.network(widget.images[i], fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const SizedBox.shrink()),
    );
  }
}

/// Concave wave cut along the hero's bottom edge.
class _HeroWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final p = Path()
      ..lineTo(0, size.height - 26)
      ..quadraticBezierTo(size.width * .25, size.height,
          size.width * .5, size.height - 14)
      ..quadraticBezierTo(size.width * .75, size.height - 28,
          size.width, size.height - 6)
      ..lineTo(size.width, 0)
      ..close();
    return p;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> old) => false;
}

String _tx(Map p, String en, String arK, bool ar) =>
    ((ar ? p[arK] : p[en]) ?? p[en] ?? '').toString();

// ═══ 2. COUNTDOWN STRIP ═════════════════════════════════════════════════
class PromoCountdownBlock extends StatelessWidget {
  const PromoCountdownBlock({super.key, required this.p, required this.data,
      required this.ar});
  final Map<String, dynamic> p;
  final Map<String, dynamic> data;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    final promo = (data['promo'] as Map?)?.cast<String, dynamic>();
    final c1 = promoParseColor(p['c1'])
        ?? promoParseColor(promo?['c1']) ?? const Color(0xFFE63946);
    final txt = promoParseColor(p['text_color']) ?? Colors.white;
    final ends = DateTime.tryParse(
        (p['ends_at'] ?? promo?['ends_at'] ?? '').toString());
    if (ends == null) return const SizedBox.shrink();
    final label = _tx(p, 'titleEn', 'titleAr', ar);
    return Container(
      margin: blockMargin(p, 10, 0, 10, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: c1,
          borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Text('⏰', style: TextStyle(fontSize: 18, color: txt)),
        const SizedBox(width: 8),
        Expanded(child: Text(
            label.isNotEmpty ? label : (ar ? 'ينتهي العرض خلال' : 'Offer ends in'),
            maxLines: 2,
            style: TextStyle(color: txt, fontSize: 12.5,
                fontWeight: FontWeight.w900))),
        PromoCountdown(endsAt: ends, color: txt, compact: true),
      ]),
    );
  }
}

// ═══ 3. AUTO-PLAY CAROUSEL ══════════════════════════════════════════════
class PromoCarouselBlock extends StatefulWidget {
  const PromoCarouselBlock({super.key, required this.p, required this.data,
      required this.ar});
  final Map<String, dynamic> p;
  final Map<String, dynamic> data;
  final bool ar;
  @override
  State<PromoCarouselBlock> createState() => _PromoCarouselBlockState();
}

class _PromoCarouselBlockState extends State<PromoCarouselBlock> {
  // v2.2.08 — narrower card (was .82 → unreadably wide) with taller
  // proportions so the product data reads clearly.
  final _ctrl = PageController(viewportFraction: .60);
  Timer? _auto;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    final secs = ((widget.p['interval'] as num?)?.toInt() ?? 3).clamp(2, 10);
    _auto = Timer.periodic(Duration(seconds: secs), (_) {
      if (!mounted || !_ctrl.hasClients) return;
      final n = promoItems(widget.data).length;
      if (n < 2) return;
      _page = (_page + 1) % n;
      _ctrl.animateToPage(_page,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutCubic);
    });
  }

  @override
  void dispose() { _auto?.cancel(); _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final items = promoItems(widget.data);
    if (items.isEmpty) return const SizedBox.shrink();
    final c1 = promoParseColor(widget.p['c1']) ?? UellowColors.yellow;
    return Column(children: [
      SizedBox(height: 312, child: PageView.builder(
        controller: _ctrl,
        onPageChanged: (i) => _page = i,
        itemCount: items.length,
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: ProductCard(rich: true, product: items[i], hideAvail: true,
              display: CardDisplay.fromMap(widget.p['card'] as Map?)),
        ),
      )),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (var i = 0; i < items.length.clamp(0, 8); i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: i == _page % items.length ? 18 : 6, height: 6,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
                color: i == _page % items.length
                    ? c1 : UellowColors.border,
                borderRadius: BorderRadius.circular(3)),
          ),
      ]),
    ]);
  }
}

// ═══ 4. MEGA GRID — custom sale cards (v2.2.09 redesign) ═══════════════
// Bespoke card (not the standard ProductCard): badge INSIDE the image
// corner, tinted price, save-chip, optional header with accent bar.
class PromoMegaGridBlock extends StatelessWidget {
  const PromoMegaGridBlock({super.key, required this.p, required this.data,
      required this.ar});
  final Map<String, dynamic> p;
  final Map<String, dynamic> data;
  final bool ar;
  // v2.2.11 — per-element card display map from the builder (b.props.card).
  CardDisplay get _d => CardDisplay.fromMap(p['card'] as Map?);

  @override
  Widget build(BuildContext context) {
    final items = promoItems(data);
    if (items.isEmpty) return const SizedBox.shrink();
    final rib = promoParseColor(p['c1']) ?? const Color(0xFFE63946);
    final cols = (int.tryParse('${p['columns'] ?? 2}') ?? 2).clamp(2, 3);
    final style = (p['card_style'] ?? 'light').toString();
    final title = _tx(p, 'titleEn', 'titleAr', ar);
    final sub = _tx(p, 'subEn', 'subAr', ar);
    final showSave = p['show_save'] != false;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (title.isNotEmpty) Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Container(width: 4, height: 30, decoration: BoxDecoration(
                color: rib, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 16,
                  fontWeight: FontWeight.w900, color: UellowColors.ink)),
              if (sub.isNotEmpty)
                Text(sub, style: const TextStyle(fontSize: 11,
                    color: UellowColors.muted)),
            ]),
          ]),
        ),
        GridView.builder(
          shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols, mainAxisSpacing: 10, crossAxisSpacing: 10,
              childAspectRatio: cols == 3 ? 0.62 : 0.70),
          itemCount: items.length,
          itemBuilder: (_, i) =>
              _saleCard(context, items[i], rib, style, showSave, cols),
        ),
      ]),
    );
  }

  Widget _saleCard(BuildContext ctx, UellowProductCard prod, Color rib,
      String style, bool showSave, int cols) {
    final d = prod.discountPct;
    final tinted = style == 'tinted';
    final lang = ar ? 'ar' : 'en';
    double? saved;
    if (prod.comparePrice != null) {
      saved = prod.comparePrice!.amount - prod.price.amount;
      if (saved <= 0) saved = null;
    }
    return GestureDetector(
      onTap: () => UellowRouter.goProduct(ctx, prod.id),
      child: Container(
        decoration: BoxDecoration(
          // v2.2.14 — solid white card (tinted = opaque wash over white, never
          // see-through against the page background).
          color: tinted
              ? (Color.alphaBlend(rib.withValues(alpha: .06), Colors.white))
              : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: tinted
              ? rib.withValues(alpha: .25) : const Color(0xFFEDEDED)),
          boxShadow: const [BoxShadow(color: Color(0x0A000000),
              blurRadius: 6, offset: Offset(0, 2))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // image with the badge pinned INSIDE its corner
          Expanded(child: Stack(fit: StackFit.expand, children: [
            CachedNetworkImage(imageUrl: _abs(prod.image), fit: BoxFit.cover,
                errorWidget: (_, __, ___) =>
                    const ColoredBox(color: Color(0xFFF4F4F4))),
            if (d > 0 && _d.discount) PositionedDirectional(top: 6, start: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 7, vertical: 3),
                decoration: BoxDecoration(color: rib,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: const [BoxShadow(color: Color(0x40000000),
                        blurRadius: 6, offset: Offset(0, 2))]),
                child: Text('-$d%', style: TextStyle(
                    color: Colors.white, fontSize: cols == 3 ? 10 : 11.5,
                    fontWeight: FontWeight.w900)),
              )),
          ])),
          Padding(
            padding: const EdgeInsets.fromLTRB(9, 8, 9, 9),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              if (_d.name) Text(prod.name.current(lang), maxLines: cols == 3 ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: cols == 3 ? 10.5 : 12,
                      fontWeight: FontWeight.w700,
                      color: UellowColors.ink, height: 1.3)),
              const SizedBox(height: 5),
              if (_d.price) FittedBox(fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Row(mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(prod.price.formatLocalized(lang), style: TextStyle(
                    fontSize: cols == 3 ? 12.5 : 14.5,
                    fontWeight: FontWeight.w900, color: rib)),
                if (prod.comparePrice != null && _d.compare) ...[
                  const SizedBox(width: 5),
                  Text(prod.comparePrice!.formatLocalized(lang),
                      style: const TextStyle(fontSize: 10,
                          color: UellowColors.muted,
                          decoration: TextDecoration.lineThrough)),
                ],
              ])),
              if (showSave && _d.save && saved != null) Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: rib.withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(6)),
                  child: Text(
                      ar ? 'وفّرت ${saved.toStringAsFixed(saved % 1 == 0 ? 0 : 2)}'
                         : 'Save ${saved.toStringAsFixed(saved % 1 == 0 ? 0 : 2)}',
                      style: TextStyle(fontSize: 9.5, color: rib,
                          fontWeight: FontWeight.w800)),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ═══ 5. FLASH RAIL (countdown chip per card) ════════════════════════════
class PromoFlashRailBlock extends StatelessWidget {
  const PromoFlashRailBlock({super.key, required this.p, required this.data,
      required this.ar});
  final Map<String, dynamic> p;
  final Map<String, dynamic> data;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    final items = promoItems(data);
    if (items.isEmpty) return const SizedBox.shrink();
    final c1 = promoParseColor(p['c1']) ?? const Color(0xFFE63946);
    final ends = DateTime.tryParse((p['ends_at']
        ?? (data['flash_end_datetime'] ?? '')).toString());
    return SizedBox(height: 296, child: ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      scrollDirection: Axis.horizontal,
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(width: 8),
      itemBuilder: (_, i) => SizedBox(width: 165, child: Column(children: [
        if (ends != null)
          Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: c1.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(8)),
            child: PromoCountdown(endsAt: ends, color: c1,
                boxColor: Colors.transparent, compact: true),
          ),
        Expanded(child: ProductCard(
            rich: true, product: items[i], hideAvail: true,
            display: CardDisplay.fromMap(p['card'] as Map?))),
      ])),
    ));
  }
}

// ═══ 6. COUPON CARD (dashed + copy) ═════════════════════════════════════
// v2.2.11 — professional coupon wall. Manual single code OR real coupons
// from the loyalty engine (resolved into data['coupons']). Layouts:
// grid / slider / carousel / list. Fully colour-customisable + claim btn.
class PromoCouponBlock extends StatelessWidget {
  const PromoCouponBlock({super.key, required this.p, this.data, required this.ar});
  final Map<String, dynamic> p;
  final Map<String, dynamic>? data;
  final bool ar;

  List<Map<String, dynamic>> _coupons() {
    final mode = (p['coupon_mode'] ?? 'manual').toString();
    if (mode == 'manual') {
      final code = (p['code'] ?? '').toString();
      if (code.isEmpty) return const [];
      return [{
        'name': {'en': _tx(p, 'titleEn', 'titleAr', false),
                 'ar': _tx(p, 'titleEn', 'titleAr', true)},
        'code': code, 'discount_text': '', 'expiry': null, 'min_amount': 0,
      }];
    }
    final raw = ((data?['coupons'] as List?) ?? const []).cast<dynamic>();
    return raw.map((e) => (e as Map).cast<String, dynamic>()).toList();
  }

  @override
  Widget build(BuildContext context) {
    final coupons = _coupons();
    if (coupons.isEmpty) return const SizedBox.shrink();
    final layout = (p['layout'] ?? 'grid').toString();
    final title = _tx(p, 'titleEn', 'titleAr', ar);
    final sub = _tx(p, 'subEn', 'subAr', ar);
    final showHeader = (p['coupon_mode'] ?? 'manual') != 'manual' &&
        (title.isNotEmpty || sub.isNotEmpty);

    Widget card(Map<String, dynamic> c, {double? width}) =>
        _CouponCard(c: c, p: p, ar: ar, width: width);

    Widget body;
    switch (layout) {
      case 'slider':
        body = SizedBox(height: 84, child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          itemCount: coupons.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) => Align(alignment: Alignment.topCenter,
              child: card(coupons[i], width: 270)),
        ));
        break;
      case 'carousel':
        body = SizedBox(height: 84, child: PageView.builder(
          controller: PageController(viewportFraction: 0.86),
          itemCount: coupons.length,
          itemBuilder: (_, i) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Align(alignment: Alignment.topCenter,
                child: card(coupons[i])),
          ),
        ));
        break;
      case 'list':
        body = Column(children: [
          for (final c in coupons) Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            child: card(c),
          ),
        ]);
        break;
      default: // grid
        body = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in coupons)
              card(c, width: (MediaQuery.of(context).size.width - 28) / 2),
          ]),
        );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (showHeader) Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (title.isNotEmpty) Text(title, style: TextStyle(
              fontWeight: FontWeight.w900, fontSize: 15,
              color: promoParseColor(p['font_color']) ?? UellowColors.ink)),
          if (sub.isNotEmpty) Text(sub, style: const TextStyle(
              fontSize: 11.5, color: UellowColors.muted)),
        ]),
      ),
      body,
    ]);
  }
}

class _CouponCard extends StatelessWidget {
  const _CouponCard({required this.c, required this.p, required this.ar, this.width});
  final Map<String, dynamic> c;
  final Map<String, dynamic> p;
  final bool ar;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final accent = promoParseColor(p['c1']) ?? UellowColors.yellow;
    final cardColor = promoParseColor(p['card_color']) ?? Colors.white;
    final fontColor = promoParseColor(p['font_color']) ?? UellowColors.ink;
    final codeColor = promoParseColor(p['code_color']) ?? UellowColors.darkBrown;
    final claimColor = promoParseColor(p['claim_color']) ?? UellowColors.darkBrown;
    final claimText = promoParseColor(p['claim_text_color']) ?? Colors.white;
    final code = (c['code'] ?? '').toString();
    final name = ((c['name'] as Map?)?[ar ? 'ar' : 'en'] ?? '').toString();
    final disc = (c['discount_text'] ?? '').toString();
    final minAmt = (c['min_amount'] as num?)?.toDouble() ?? 0;
    final claimLabel = _tx(p, 'claimEn', 'claimAr', ar);

    // v2.2.18 — compact HORIZONTAL ticket like the big marketplaces:
    // accent value-stub | punched notches + dashed perforation | name,
    // min-spend and a small code + copy pill. Low height (76), small type.
    final tight = (width ?? 600) < 200; // grid half-width cards
    final stubW = tight ? 56.0 : 72.0;

    void copy() {
      if (code.isNotEmpty) Clipboard.setData(ClipboardData(text: code));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(code.isNotEmpty
              ? (ar ? 'نُسخ الكود ✓' : 'Code copied ✓')
              : (ar ? 'تم ✓' : 'Done ✓')),
          duration: const Duration(seconds: 1)));
    }

    final rtl = Directionality.of(context) == TextDirection.rtl;
    return SizedBox(
      width: width,
      height: 76,
      child: PhysicalShape(
        clipper: _CouponTicketClipper(stub: stubW, rtl: rtl),
        color: cardColor,
        elevation: 1.5,
        shadowColor: const Color(0x26000000),
        child: GestureDetector(
          onTap: copy,
          child: Stack(children: [
            Row(children: [
              // ── value stub ──
              Container(
                width: stubW, color: accent, alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                  FittedBox(child: Text(disc.isNotEmpty ? disc : '🎟',
                      style: TextStyle(
                          color: _onAccent(accent), fontSize: 16,
                          fontWeight: FontWeight.w900, height: 1.0))),
                  if (disc.isNotEmpty) Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(ar ? 'خصم' : 'OFF',
                        style: TextStyle(
                            color: _onAccent(accent).withValues(alpha: .85),
                            fontSize: 7.5, letterSpacing: 1.6,
                            fontWeight: FontWeight.w800))),
                ]),
              ),
              // ── details ──
              Expanded(child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(12, 9, 10, 9),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name.isNotEmpty ? name
                          : (ar ? 'كوبون خصم' : 'Discount coupon'),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w800,
                          fontSize: 11, color: fontColor, height: 1.1)),
                  if (minAmt > 0) Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(ar
                              ? 'بحد أدنى ${minAmt.toStringAsFixed(0)}'
                              : 'Min spend ${minAmt.toStringAsFixed(0)}',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 8.5,
                              color: fontColor.withValues(alpha: .55),
                              fontWeight: FontWeight.w600))),
                  const Spacer(),
                  Row(children: [
                    if (code.isNotEmpty) Expanded(child: Text(code,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontFamily: 'monospace',
                            letterSpacing: 1.2, fontWeight: FontWeight.w900,
                            fontSize: 10.5, color: codeColor)))
                    else const Spacer(),
                    const SizedBox(width: 6),
                    // small claim pill (icon-only when the card is narrow)
                    GestureDetector(onTap: copy, child: Container(
                      height: 24,
                      padding: EdgeInsets.symmetric(
                          horizontal: tight ? 7 : 10),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: claimColor,
                          borderRadius: BorderRadius.circular(999)),
                      child: tight
                          ? Icon(Icons.copy_rounded, size: 11,
                              color: claimText)
                          : Text(claimLabel.isNotEmpty ? claimLabel
                                  : (ar ? 'نسخ' : 'Copy'),
                              style: TextStyle(fontWeight: FontWeight.w900,
                                  fontSize: 9.5, color: claimText)),
                    )),
                  ]),
                ]),
              )),
            ]),
            // dashed perforation on the stub boundary
            PositionedDirectional(start: stubW - 0.5, top: 9, bottom: 9,
                child: SizedBox(width: 1, child: CustomPaint(
                    painter: _CouponDashPainter(
                        color: fontColor.withValues(alpha: .18))))),
          ]),
        ),
      ),
    );
  }

  /// White on dark accents, dark-brown on light accents (e.g. yellow).
  Color _onAccent(Color a) =>
      a.computeLuminance() > 0.6 ? UellowColors.darkBrown : Colors.white;
}

/// Ticket silhouette: rounded card with two punched semicircle notches on
/// the stub boundary — transparent cutouts, so any page/showcase
/// background shows through naturally.
class _CouponTicketClipper extends CustomClipper<Path> {
  const _CouponTicketClipper({required this.stub, required this.rtl});
  final double stub;
  final bool rtl;
  static const _r = 12.0;   // card corner radius
  static const _notch = 5.0;
  @override
  Path getClip(Size s) {
    final x = rtl ? s.width - stub : stub;
    final card = Path()
      ..addRRect(RRect.fromRectAndRadius(Offset.zero & s,
          const Radius.circular(_r)));
    final holes = Path()
      ..addOval(Rect.fromCircle(center: Offset(x, 0), radius: _notch))
      ..addOval(Rect.fromCircle(center: Offset(x, s.height), radius: _notch));
    return Path.combine(PathOperation.difference, card, holes);
  }

  @override
  bool shouldReclip(_CouponTicketClipper old) =>
      old.stub != stub || old.rtl != rtl;
}

/// Tiny vertical dashed line (the "tear here" perforation).
class _CouponDashPainter extends CustomPainter {
  const _CouponDashPainter({required this.color});
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..strokeWidth = 1;
    for (double y = 0; y < size.height; y += 7) {
      canvas.drawLine(Offset(0, y), Offset(0, y + 3.5), paint);
    }
  }

  @override
  bool shouldRepaint(_CouponDashPainter old) => old.color != color;
}

// ═══ 7. BANNER + CTA ════════════════════════════════════════════════════
class PromoBannerCtaBlock extends StatelessWidget {
  const PromoBannerCtaBlock({super.key, required this.p, this.data,
      required this.ar, required this.onTap});
  final Map<String, dynamic> p;
  final Map<String, dynamic>? data;
  final bool ar;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c1 = promoParseColor(p['c1']) ?? UellowColors.darkBrown;
    final c2 = promoParseColor(p['c2']) ?? const Color(0xFF1F1100);
    final txt = promoParseColor(p['text_color']) ?? Colors.white;
    // v2.2.17 — builder picker now sets image_url(+_ar): honour the
    // Arabic override when the app runs in Arabic.
    final img = pickLocalizedImage(p, ar);
    final title = _tx(p, 'titleEn', 'titleAr', ar);
    final cta = _tx(p, 'ctaEn', 'ctaAr', ar);
    // v2.2.14 — fullscreen option + countdown from the linked promotion.
    final fullscreen = p['fullscreen'] == true;
    final promo = (data?['promo'] as Map?)?.cast<String, dynamic>();
    final endsRaw = (p['ends_at'] ?? promo?['ends_at'] ?? '').toString();
    final ends = DateTime.tryParse(endsRaw);
    final showCd = p['show_countdown'] == true && ends != null;
    final cdBox = promoParseColor(p['cd_box_color'])
        ?? Colors.black.withValues(alpha: .45);
    final cdText = promoParseColor(p['cd_text_color']) ?? Colors.white;
    final cdLabel = promoParseColor(p['cd_label_color']) ?? Colors.white;
    final height = fullscreen
        ? MediaQuery.of(context).size.height -
            MediaQuery.of(context).padding.vertical - 80
        : ((p['height'] as num?)?.toDouble() ?? 130).clamp(90.0, 320.0);

    final banner = GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        margin: fullscreen ? EdgeInsets.zero : blockMargin(p, 10, 0, 10, 0),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(fullscreen ? 0 : 16),
          gradient: LinearGradient(colors: [c1, c2]),
        ),
        child: Stack(fit: StackFit.expand, children: [
          if (img.isNotEmpty)
            CachedNetworkImage(imageUrl: _abs(img), fit: BoxFit.cover,
                errorWidget: (_, __, ___) => const SizedBox.shrink()),
          // v2.2.17 — overlay configurable from the builder Style tab
          // (overlay_color / overlay_opacity; 0 = no veil).
          if (img.isNotEmpty && blockOverlay(p, defOpacity: .30) != null)
            Container(color: blockOverlay(p, defOpacity: .30)),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Expanded(child: Text(title, maxLines: fullscreen ? 5 : 3,
                  style: TextStyle(color: txt,
                      fontSize: fullscreen ? 26 : 18, height: 1.25,
                      fontWeight: FontWeight.w900))),
              if (cta.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(color: Colors.white,
                      borderRadius: BorderRadius.circular(999)),
                  child: Text(cta, style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 12,
                      color: UellowColors.darkBrown)),
                ),
            ]),
          ),
          // ── small countdown, bottom-center ──
          if (showCd) Positioned(
            left: 0, right: 0, bottom: 12,
            child: Center(child: Column(mainAxisSize: MainAxisSize.min,
                children: [
              Text(ar ? '⏰ ينتهي خلال' : '⏰ ENDS IN',
                  style: TextStyle(color: cdLabel, fontSize: 9,
                      letterSpacing: 1, fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              PromoCountdown(endsAt: ends, color: cdText, boxColor: cdBox,
                  labelColor: cdLabel, compact: true, scale: 0.9),
            ])),
          ),
        ]),
      ),
    );
    return banner;
  }
}

// ═══ 8. TIERS — buy-more-save-more product wall (v2.2.14) ════════════════
// Each product shows its single-unit price AND a bulk price (e.g. ×10),
// using the product's real bulk-pricing ladder (data.items[].bulk_pricing).
class PromoTiersBlock extends StatelessWidget {
  const PromoTiersBlock({super.key, required this.p, this.data, required this.ar});
  final Map<String, dynamic> p;
  final Map<String, dynamic>? data;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    final raw = ((data?['items'] as List?) ?? const []).cast<dynamic>()
        .map((e) => (e as Map).cast<String, dynamic>()).toList();
    if (raw.isEmpty) return const SizedBox.shrink();
    final bulkQty = (p['bulk_qty'] as num?)?.toInt() ?? 10;
    final accent = promoParseColor(p['c1']) ?? UellowColors.yellow;
    final cardColor = promoParseColor(p['card_color']) ?? Colors.white;
    final fontColor = promoParseColor(p['font_color']) ?? UellowColors.ink;
    final title = _tx(p, 'titleEn', 'titleAr', ar);
    final sub = _tx(p, 'subEn', 'subAr', ar);
    final grid = (p['layout'] ?? 'list').toString() == 'grid';
    final lang = ar ? 'ar' : 'en';

    final cards = <Widget>[];
    for (final m in raw) {
      UellowProductCard prod;
      try { prod = UellowProductCard.fromJson(m); } catch (_) { continue; }
      final tiers = ((m['bulk_pricing'] as List?) ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>()).toList();
      cards.add(_TierCard(prod: prod, tiers: tiers, bulkQty: bulkQty,
          accent: accent, cardColor: cardColor, fontColor: fontColor,
          ar: ar, lang: lang, grid: grid));
    }
    if (cards.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (title.isNotEmpty || sub.isNotEmpty) Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
          child: Row(children: [
            Container(width: 4, height: 30, decoration: BoxDecoration(
                color: accent, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              if (title.isNotEmpty) Text(title, style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w900, color: fontColor)),
              if (sub.isNotEmpty) Text(sub, style: const TextStyle(
                  fontSize: 11.5, color: UellowColors.muted)),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: accent.withValues(alpha: .15),
                  borderRadius: BorderRadius.circular(999)),
              child: Text(ar ? 'وفّر بالجملة' : 'Bulk deals',
                  style: TextStyle(fontSize: 10,
                      color: Color.lerp(accent, Colors.black, .35),
                      fontWeight: FontWeight.w900)),
            ),
          ]),
        ),
        if (grid)
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in cards)
              SizedBox(width: (MediaQuery.of(context).size.width - 28) / 2,
                  child: c),
          ])
        else
          Column(children: [
            for (final c in cards) Padding(
              padding: const EdgeInsets.only(bottom: 8), child: c),
          ]),
      ]),
    );
  }
}

class _TierCard extends StatelessWidget {
  const _TierCard({required this.prod, required this.tiers, required this.bulkQty,
      required this.accent, required this.cardColor, required this.fontColor,
      required this.ar, required this.lang, required this.grid});
  final UellowProductCard prod;
  final List<Map<String, dynamic>> tiers;
  final int bulkQty;
  final Color accent, cardColor, fontColor;
  final bool ar;
  final String lang;
  final bool grid;

  String _money(double v) {
    final s = v.toStringAsFixed(v % 1 == 0 ? 0 : 2);
    return ar ? '$s ${prod.price.displaySymbol("ar")}'
        : '$s ${prod.price.displaySymbol("en")}';
  }

  @override
  Widget build(BuildContext context) {
    final unit = prod.price.amount;
    // best per-unit price when buying bulkQty (lowest tier whose min_qty ≤ qty)
    var bulkUnit = unit;
    var savePct = 0;
    for (final t in tiers) {
      final mq = (t['min_qty'] as num?)?.toInt() ?? 0;
      final pr = (t['price'] as num?)?.toDouble() ?? unit;
      if (mq <= bulkQty && pr <= bulkUnit) {
        bulkUnit = pr;
        savePct = (t['save_pct'] as num?)?.toInt() ?? 0;
      }
    }
    final bulkTotal = bulkUnit * bulkQty;

    Widget priceRow(String qtyLabel, String total, {String? perUnit,
        bool highlight = false}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: highlight ? accent.withValues(alpha: .12) : const Color(0xFFF6F6F6),
        borderRadius: BorderRadius.circular(9),
        border: highlight ? Border.all(color: accent.withValues(alpha: .5)) : null,
      ),
      child: Row(children: [
        Text(qtyLabel, style: TextStyle(fontSize: 11,
            fontWeight: FontWeight.w800,
            color: highlight ? Color.lerp(accent, Colors.black, .4) : fontColor)),
        const Spacer(),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(total, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900,
              color: highlight ? Color.lerp(accent, Colors.black, .4) : fontColor)),
          if (perUnit != null) Text(perUnit, style: const TextStyle(fontSize: 9,
              color: UellowColors.muted, fontWeight: FontWeight.w600)),
        ]),
      ]),
    );

    return GestureDetector(
      onTap: () => UellowRouter.goProduct(context, prod.id),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFEDEDED)),
          boxShadow: const [BoxShadow(color: Color(0x0A000000),
              blurRadius: 6, offset: Offset(0, 2))],
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(borderRadius: BorderRadius.circular(10),
            child: CachedNetworkImage(imageUrl: _abs(prod.image),
                width: grid ? 56 : 66, height: grid ? 56 : 66, fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(
                    width: grid ? 56 : 66, height: grid ? 56 : 66,
                    color: const Color(0xFFF4F4F4)))),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min, children: [
            Text(prod.name.current(lang), maxLines: grid ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                    color: fontColor, height: 1.25)),
            const SizedBox(height: 7),
            priceRow(ar ? 'حبة واحدة' : '1 unit', _money(unit)),
            const SizedBox(height: 5),
            Row(children: [
              Expanded(child: priceRow(
                  ar ? '$bulkQty حبة' : '$bulkQty units', _money(bulkTotal),
                  perUnit: savePct > 0
                      ? (ar ? '${_money(bulkUnit)} للحبة' : '${_money(bulkUnit)}/ea')
                      : null,
                  highlight: true)),
              if (savePct > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                  decoration: BoxDecoration(color: UellowColors.successDk,
                      borderRadius: BorderRadius.circular(8)),
                  child: Text('-$savePct%', style: const TextStyle(
                      color: Colors.white, fontSize: 11,
                      fontWeight: FontWeight.w900)),
                ),
              ],
            ]),
          ])),
        ]),
      ),
    );
  }
}

// ═══ 8b. CAMPAIGN SHOWCASE (v2.2.14) ════════════════════════════════════
// A themed gradient hero holding EITHER coupons OR a product feed, with an
// optional promotion countdown. Every part's colour is configurable.
class PromoShowcaseBlock extends StatelessWidget {
  const PromoShowcaseBlock({super.key, required this.p, required this.data,
      required this.ar});
  final Map<String, dynamic> p;
  final Map<String, dynamic> data;
  final bool ar;

  Color _c(String k, Color fb) => promoParseColor(p[k]) ?? fb;

  List<Map<String, dynamic>> _coupons() {
    if ((p['coupon_mode'] ?? '') == 'manual') {
      final code = (p['code'] ?? '').toString();
      if (code.isEmpty) return const [];
      return [{'name': {'en': _tx(p, 'titleEn', 'titleAr', false),
                        'ar': _tx(p, 'titleEn', 'titleAr', true)},
               'code': code, 'discount_text': '', 'expiry': null, 'min_amount': 0}];
    }
    return ((data['coupons'] as List?) ?? const []).cast<dynamic>()
        .map((e) => (e as Map).cast<String, dynamic>()).toList();
  }

  @override
  Widget build(BuildContext context) {
    final c1 = _c('c1', const Color(0xFF2563EB));
    final c2 = _c('c2', const Color(0xFF1E3A8A));
    final tc = _c('text_color', Colors.white);
    final sc = _c('sub_color', const Color(0xFFDBEAFE));
    final title = _tx(p, 'titleEn', 'titleAr', ar);
    final sub = _tx(p, 'subEn', 'subAr', ar);
    final emoji = (p['emoji'] ?? '🎁').toString();
    final ctype = (p['content_type'] ?? 'coupons').toString();
    final grid = (p['layout'] ?? 'rail').toString() == 'grid';
    final promo = (data['promo'] as Map?)?.cast<String, dynamic>();
    final ends = DateTime.tryParse(
        (p['ends_at'] ?? promo?['ends_at'] ?? '').toString());
    final showCd = p['show_countdown'] == true && ends != null;
    final cdPos = (p['countdown_position'] ?? 'top-right').toString();
    final cdBox = _c('cd_box_color', c2);
    final cdText = _c('cd_text_color', Colors.white);
    final cdLabel = _c('cd_label_color', sc);

    Widget? countdown = showCd ? Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center, children: [
      Text(ar ? '⏰ ينتهي خلال' : '⏰ ENDS IN', style: TextStyle(
          color: cdLabel, fontSize: 8.5, letterSpacing: .8,
          fontWeight: FontWeight.w800)),
      const SizedBox(height: 3),
      PromoCountdown(endsAt: ends, color: cdText, boxColor: cdBox,
          labelColor: cdLabel, compact: true, scale: .82),
    ]) : null;

    // ── content ──
    Widget content;
    if (ctype == 'coupons') {
      final coupons = _coupons();
      if (coupons.isEmpty) {
        content = const SizedBox.shrink();
      } else if (grid) {
        content = Wrap(spacing: 8, runSpacing: 8, children: [
          for (final c in coupons)
            _CouponCard(c: c, p: p, ar: ar,
                width: (MediaQuery.of(context).size.width - 44) / 2),
        ]);
      } else {
        content = SizedBox(height: 84, child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.zero,
          itemCount: coupons.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) => Align(alignment: Alignment.topCenter,
              child: _CouponCard(c: coupons[i], p: p, ar: ar, width: 270)),
        ));
      }
    } else {
      final items = ((data['items'] as List?) ?? const []).cast<dynamic>()
          .map((e) {
            try { return UellowProductCard.fromJson((e as Map).cast<String, dynamic>()); }
            catch (_) { return null; }
          }).whereType<UellowProductCard>().toList();
      final display = CardDisplay.fromMap(p['card'] as Map?);
      // v2.2.17 — the card slot used to be FIXED (286 rail / 0.585 grid),
      // sized for every row visible, so hiding name/price/rating left a
      // white strip at the card bottom. The info height now follows the
      // visible rows (rich layout: pad 10 + ticker 17 + badges 17 always;
      // name 32 / price 20 / rating 16 when shown), or the explicit
      // builder override.
      double infoH = 10 + 17 + 17;
      if (display.name) infoH += 32;
      if (display.price) infoH += 20;
      if (display.rating) infoH += 16;
      if (display.infoHeight != null) infoH = display.infoHeight!;
      const buffer = 14.0; // shadow / rounding breathing room
      if (items.isEmpty) {
        content = const SizedBox.shrink();
      } else if (grid) {
        content = LayoutBuilder(builder: (_, cons) {
          final cellW = (cons.maxWidth - 8) / 2;
          final cellH = cellW + infoH + buffer; // square image + info rows
          return GridView.builder(
            shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, crossAxisSpacing: 8, mainAxisSpacing: 8,
                childAspectRatio: cellW / cellH),
            itemCount: items.length,
            itemBuilder: (_, i) => ProductCard(rich: true, product: items[i],
                hideAvail: true, display: display),
          );
        });
      } else {
        content = SizedBox(height: 160 + infoH + buffer,
            child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.zero,
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) => SizedBox(width: 160,
              child: ProductCard(rich: true, product: items[i],
                  hideAvail: true, display: display)),
        ));
      }
    }

    final header = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(emoji, style: const TextStyle(fontSize: 26)),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min, children: [
        if (title.isNotEmpty) Text(title, maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: tc, fontSize: 18,
                fontWeight: FontWeight.w900, height: 1.15)),
        if (sub.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2),
          child: Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: sc, fontSize: 12))),
      ])),
      if (countdown != null && cdPos != 'below-title') Padding(
        padding: const EdgeInsetsDirectional.only(start: 8), child: countdown),
    ]);

    return Container(
      margin: blockMargin(p, 10, 4, 10, 8),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft,
            end: Alignment.bottomRight, colors: [c1, c2]),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: c1.withValues(alpha: .3),
            blurRadius: 14, offset: const Offset(0, 6))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        header,
        if (countdown != null && cdPos == 'below-title') Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Align(alignment: Alignment.center, child: countdown)),
        const SizedBox(height: 14),
        content,
      ]),
    );
  }
}

// ═══ 8b. BUNDLE SHOWCASE — published bundles as save-as-a-set cards ══════
class BundleShowcaseBlock extends StatelessWidget {
  const BundleShowcaseBlock({super.key, required this.p, required this.data,
      required this.ar});
  final Map<String, dynamic> p;
  final Map<String, dynamic> data;
  final bool ar;

  Color _c(String k, Color fb) => promoParseColor(p[k]) ?? fb;

  @override
  Widget build(BuildContext context) {
    final items = ((data['items'] as List?) ?? const []).cast<dynamic>()
        .map((e) => (e as Map).cast<String, dynamic>()).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    final c1 = _c('c1', const Color(0xFF7C3AED));
    final c2 = _c('c2', const Color(0xFF4C1D95));
    final tc = _c('text_color', Colors.white);
    final sc = _c('sub_color', const Color(0xFFEDE9FE));
    final saveColor = _c('savings_color', const Color(0xFF16A34A));
    final showSavings = p['show_savings'] != false;
    final title = _tx(p, 'titleEn', 'titleAr', ar);
    final sub = _tx(p, 'subEn', 'subAr', ar);
    final emoji = (p['emoji'] ?? '📦').toString();
    final grid = (p['layout'] ?? 'rail').toString() == 'grid';
    final display = CardDisplay.fromMap(p['card'] as Map?);

    Widget card(Map<String, dynamic> it, double width) => _BundleCard(
        it: it, ar: ar, width: width, saveColor: saveColor,
        showSavings: showSavings, display: display);

    Widget content;
    if (grid) {
      content = Wrap(spacing: 8, runSpacing: 8, children: [
        for (final it in items)
          card(it, (MediaQuery.of(context).size.width - 44) / 2),
      ]);
    } else {
      content = SizedBox(height: 250, child: ListView.separated(
        scrollDirection: Axis.horizontal, padding: EdgeInsets.zero,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => card(items[i], 164),
      ));
    }

    return Container(
      margin: blockMargin(p, 10, 4, 10, 8),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [c1, c2],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: blockRadius(p, 20),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(emoji, style: const TextStyle(fontSize: 26)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            if (title.isNotEmpty) Text(title, style: TextStyle(color: tc,
                fontSize: 17, fontWeight: FontWeight.w900, height: 1.15)),
            if (sub.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2),
                child: Text(sub, style: TextStyle(color: sc, fontSize: 12))),
          ])),
        ]),
        const SizedBox(height: 14),
        content,
        // v2.2.21 — yellow "View more" → full bundles screen.
        if (p['show_more'] != false) Padding(
          padding: const EdgeInsets.only(top: 12),
          child: SizedBox(width: double.infinity, height: 40,
            child: ElevatedButton(
              onPressed: () => Navigator.pushNamed(context, '/bundles'),
              style: ElevatedButton.styleFrom(
                backgroundColor: UellowColors.yellow,
                foregroundColor: UellowColors.darkBrown,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(ar ? 'عرض المزيد' : 'View more',
                  style: const TextStyle(fontWeight: FontWeight.w900,
                      fontSize: 13)),
            )),
        ),
      ]),
    );
  }
}

class _BundleCard extends StatelessWidget {
  const _BundleCard({required this.it, required this.ar, required this.width,
      required this.saveColor, required this.showSavings,
      required this.display});
  final Map<String, dynamic> it;
  final bool ar;
  final double width;
  final Color saveColor;
  final bool showSavings;
  final CardDisplay display;

  @override
  Widget build(BuildContext context) {
    final meta = (it['bundle_meta'] as Map?)?.cast<String, dynamic>();
    final pid = (it['id'] as num?)?.toInt() ?? 0;
    final img = (it['image'] ?? '').toString();
    final name = ((it['name'] as Map?)?[ar ? 'ar' : 'en']
        ?? (it['name'] ?? '')).toString();
    // price + struck "components total" come from the card serializer as
    // {amount,currency,symbol,digits} — format via UellowMoney (the raw map
    // was being toString()'d → showed "{amount: ...}" gibberish on cards).
    final lang = UellowApi.instance.lang;
    final priceMap = (it['price'] as Map?)?.cast<String, dynamic>();
    final price = priceMap != null
        ? UellowMoney.fromJson(priceMap).formatLocalized(lang) : '';
    final cmpMap = (it['compare_price'] as Map?)?.cast<String, dynamic>();
    final compare = cmpMap != null
        ? UellowMoney.fromJson(cmpMap).displayAmount() : '';
    final savePct = (meta?['savings_pct'] as num?)?.toInt()
        ?? (it['discount_pct'] as num?)?.toInt() ?? 0;
    final count = (meta?['component_count'] as num?)?.toInt() ?? 0;
    final fullUrl = img.startsWith('http')
        ? img : '${UellowApi.instance.baseUrl}$img';

    return GestureDetector(
      onTap: () { if (pid > 0) UellowRouter.goProduct(context, pid); },
      child: Container(
        width: width,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [BoxShadow(color: Color(0x1A000000),
              blurRadius: 8, offset: Offset(0, 3))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min, children: [
          // cover + badges
          Stack(children: [
            AspectRatio(aspectRatio: 1, child: img.isNotEmpty
                ? CachedNetworkImage(imageUrl: fullUrl, fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                        color: const Color(0xFFF1ECFB)))
                : Container(color: const Color(0xFFF1ECFB),
                    child: const Icon(Icons.inventory_2_rounded,
                        color: Color(0xFF7C3AED), size: 34))),
            PositionedDirectional(top: 6, start: 6, child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
              decoration: BoxDecoration(color: const Color(0xFF7C3AED),
                  borderRadius: BorderRadius.circular(5)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.inventory_2_rounded, size: 9,
                    color: Colors.white),
                const SizedBox(width: 3),
                Text(count > 0
                        ? (ar ? '$count قطع' : '$count items')
                        : (ar ? 'باقة' : 'BUNDLE'),
                    style: const TextStyle(color: Colors.white, fontSize: 8,
                        fontWeight: FontWeight.w900)),
              ]),
            )),
            if (showSavings && savePct > 0)
              PositionedDirectional(top: 6, end: 6, child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2.5),
                decoration: BoxDecoration(color: saveColor,
                    borderRadius: BorderRadius.circular(5)),
                child: Text(ar ? 'وفّر $savePct%' : 'SAVE $savePct%',
                    style: const TextStyle(color: Colors.white, fontSize: 8.5,
                        fontWeight: FontWeight.w900)),
              )),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(9, 7, 9, 9),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              if (display.name) SizedBox(height: 32, child: Text(name,
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, height: 1.2,
                      fontWeight: FontWeight.w700,
                      color: UellowColors.ink))),
              const SizedBox(height: 4),
              if (display.price) Row(crossAxisAlignment:
                  CrossAxisAlignment.center, children: [
                Flexible(child: Text(price, maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF7C3AED)))),
                if (display.compare && compare.isNotEmpty) ...[
                  const SizedBox(width: 5),
                  Flexible(child: MidStrikePrice(text: compare,
                      fontSize: 9.5, color: Colors.black54)),
                ],
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ═══ 9. MARQUEE (looping strip) ═════════════════════════════════════════
class PromoMarqueeBlock extends StatefulWidget {
  const PromoMarqueeBlock({super.key, required this.p, required this.ar});
  final Map<String, dynamic> p;
  final bool ar;
  @override
  State<PromoMarqueeBlock> createState() => _PromoMarqueeBlockState();
}

class _PromoMarqueeBlockState extends State<PromoMarqueeBlock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this,
      duration: Duration(
          seconds: ((widget.p['speed'] as num?)?.toInt() ?? 14).clamp(6, 40)))
    ..repeat();

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final raw = _tx(widget.p, 'textsEn', 'textsAr', widget.ar);
    final texts = raw.split('|').map((e) => e.trim())
        .where((e) => e.isNotEmpty).toList();
    if (texts.isEmpty) return const SizedBox.shrink();
    final c1 = promoParseColor(widget.p['c1']) ?? UellowColors.darkBrown;
    final txt = promoParseColor(widget.p['text_color']) ?? Colors.white;
    final line = texts.map((t) => '  ✦  $t').join();
    return Container(
      height: 34, color: c1,
      child: ClipRect(child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => LayoutBuilder(builder: (_, box) {
          return Stack(children: [
            for (var k = 0; k < 2; k++)
              Positioned(
                left: (widget.ar ? 1 : -1) *
                        ((_c.value * box.maxWidth * 2) % (box.maxWidth * 2)) +
                    (k * box.maxWidth * 2) * (widget.ar ? -1 : 1) -
                    (widget.ar ? box.maxWidth * 2 : 0),
                top: 0, bottom: 0,
                child: SizedBox(width: box.maxWidth * 2, child: Center(
                  child: Text(line, maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: TextStyle(color: txt, fontSize: 12.5,
                          fontWeight: FontWeight.w800)),
                )),
              ),
          ]);
        }),
      )),
    );
  }
}

// ═══ 10. MASONRY (staggered 2-col) ══════════════════════════════════════
class PromoMasonryBlock extends StatelessWidget {
  const PromoMasonryBlock({super.key, required this.p, required this.data,
      required this.ar});
  final Map<String, dynamic> p;
  final Map<String, dynamic> data;
  final bool ar;
  // v2.2.11 — per-element card display map from the builder (b.props.card).
  CardDisplay get _d => CardDisplay.fromMap(p['card'] as Map?);
  @override
  Widget build(BuildContext context) {
    final items = promoItems(data);
    if (items.isEmpty) return const SizedBox.shrink();
    final left = <UellowProductCard>[], right = <UellowProductCard>[];
    for (var i = 0; i < items.length; i++) {
      (i.isEven ? left : right).add(items[i]);
    }
    Widget col(List<UellowProductCard> list, bool tallFirst) => Column(
      children: [
        for (var i = 0; i < list.length; i++) Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _tile(context, list[i],
              ((i.isEven) == tallFirst) ? 230.0 : 170.0),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: col(left, true)),
        const SizedBox(width: 10),
        Expanded(child: col(right, false)),
      ]),
    );
  }

  Widget _tile(BuildContext ctx, UellowProductCard prod, double imgH) {
    final c1 = promoParseColor(p['c1']) ?? UellowColors.yellow;
    return GestureDetector(
      onTap: () => UellowRouter.goProduct(ctx, prod.id),
      child: Container(
        decoration: BoxDecoration(color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFEDEDED))),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(height: imgH, width: double.infinity,
              child: CachedNetworkImage(imageUrl: _abs(prod.image),
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) =>
                      const ColoredBox(color: Color(0xFFF4F4F4)))),
          Padding(
            padding: const EdgeInsets.all(9),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              if (_d.name) Text(prod.name.current(ar ? 'ar' : 'en'), maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: UellowColors.ink, height: 1.3)),
              if (_d.name) const SizedBox(height: 4),
              if (_d.price) Text(prod.price.formatLocalized(ar ? 'ar' : 'en'),
                  style: TextStyle(fontSize: 14,
                      fontWeight: FontWeight.w900, color: c1)),
            ]),
          ),
        ]),
      ),
    );
  }
}
