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
      this.boxColor, this.compact = false});
  final DateTime? endsAt;
  final Color? color;
  final Color? boxColor;
  final bool compact;
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
    final bg = widget.boxColor ?? Colors.white.withValues(alpha: .18);
    final sz = widget.compact ? 13.0 : 19.0;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < parts.length; i++) ...[
        Container(
          padding: EdgeInsets.symmetric(
              horizontal: widget.compact ? 7 : 10,
              vertical: widget.compact ? 4 : 7),
          decoration: BoxDecoration(color: bg,
              borderRadius: BorderRadius.circular(10)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${parts[i].$1}'.padLeft(2, '0'),
                style: TextStyle(color: fg, fontSize: sz,
                    fontWeight: FontWeight.w900,
                    fontFeatures: const [FontFeature.tabularFigures()])),
            if (!widget.compact)
              Text(parts[i].$2, style: TextStyle(
                  color: fg.withValues(alpha: .8), fontSize: 8.5,
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

// ═══ 1. PROMO HERO — full-width animated campaign header ════════════════
class PromoHeroBlock extends StatelessWidget {
  const PromoHeroBlock({super.key, required this.p, required this.data,
      required this.ar});
  final Map<String, dynamic> p;
  final Map<String, dynamic> data;
  final bool ar;

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
    final h = ((p['height'] as num?)?.toDouble() ?? 170).clamp(120, 420)
        .toDouble();
    final title = _tx(p, 'titleEn', 'titleAr', ar).isNotEmpty
        ? _tx(p, 'titleEn', 'titleAr', ar)
        : ((promo?['name'] as Map?)?[ar ? 'ar' : 'en'] ?? '').toString();
    final sub = _tx(p, 'subEn', 'subAr', ar).isNotEmpty
        ? _tx(p, 'subEn', 'subAr', ar)
        : ((promo?['subtitle'] as Map?)?[ar ? 'ar' : 'en'] ?? '').toString();
    final logo = (p['logo_image'] ?? promo?['logo'] ?? '').toString();
    final emoji = (p['emoji'] ?? promo?['emoji'] ?? '🎉').toString();
    final endsRaw = (p['ends_at'] ?? promo?['ends_at'] ?? '').toString();
    final ends = DateTime.tryParse(endsRaw);
    final showCd = p['show_countdown'] != false && ends != null;
    // v2.2.08 — pattern overlay (same 22 artworks as the product-page
    // banner) + compact ADAPTIVE layout: short heroes lay logo+text side
    // by side; tall ones stay centred. Rounded bottom for a premium feel.
    final pattern = (p['pattern'] ?? promo?['pattern'] ?? 'none').toString();
    final compact = h < 200;

    final logoRing = Container(
      width: compact ? 46 : 60, height: compact ? 46 : 60,
      decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white,
          border: Border.all(color: Colors.white.withValues(alpha: .65),
              width: 2.5),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .25),
              blurRadius: 12, offset: const Offset(0, 4))]),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: logo.isNotEmpty
          ? CachedNetworkImage(imageUrl: _abs(logo),
              width: compact ? 46 : 60, height: compact ? 46 : 60,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => Text(emoji,
                  style: TextStyle(fontSize: compact ? 22 : 28)))
          : Text(emoji, style: TextStyle(fontSize: compact ? 22 : 28)),
    );
    final titleTxt = Text(title, maxLines: 2,
        textAlign: compact ? TextAlign.start : TextAlign.center,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: txt, fontSize: compact ? 18 : 23,
            height: 1.12, fontWeight: FontWeight.w900,
            shadows: const [Shadow(color: Color(0x59000000), blurRadius: 8)]));
    final subTxt = sub.isEmpty ? null : Text(sub, maxLines: 2,
        textAlign: compact ? TextAlign.start : TextAlign.center,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: txt.withValues(alpha: .92),
            fontSize: compact ? 11.5 : 13, fontWeight: FontWeight.w600));
    final cd = !showCd ? null : Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .18),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: .25))),
      child: PromoCountdown(endsAt: ends, color: txt, compact: compact),
    );

    return Container(
      height: h,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(24)),
        boxShadow: [BoxShadow(color: c2.withValues(alpha: .35),
            blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Stack(fit: StackFit.expand, children: [
        _AnimatedPromoBg(style: anim, c1: c1, c2: c2, c3: c3),
        if (pattern != 'none')
          CustomPaint(painter: BannerPattern(style: pattern),
              child: const SizedBox.expand()),
        // soft veil for legibility
        Container(decoration: BoxDecoration(gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Colors.black.withValues(alpha: .04),
                     Colors.black.withValues(alpha: .22)]))),
        SafeArea(bottom: false, child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
          child: compact
              ? Row(children: [
                  logoRing,
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    titleTxt,
                    if (subTxt != null) ...[
                      const SizedBox(height: 2), subTxt],
                    if (cd != null) ...[const SizedBox(height: 7), cd],
                  ])),
                ])
              : Column(mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                  logoRing,
                  const SizedBox(height: 8),
                  titleTxt,
                  if (subTxt != null) ...[const SizedBox(height: 3), subTxt],
                  if (cd != null) ...[const SizedBox(height: 10), cd],
                ]),
        )),
      ]),
    );
  }
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
      margin: const EdgeInsets.symmetric(horizontal: 10),
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
          child: ProductCard(rich: true, product: items[i], hideAvail: true),
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

// ═══ 4. MEGA GRID (٪ ribbons) ═══════════════════════════════════════════
class PromoMegaGridBlock extends StatelessWidget {
  const PromoMegaGridBlock({super.key, required this.p, required this.data,
      required this.ar});
  final Map<String, dynamic> p;
  final Map<String, dynamic> data;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    final items = promoItems(data);
    if (items.isEmpty) return const SizedBox.shrink();
    final rib = promoParseColor(p['c1']) ?? const Color(0xFFE63946);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: GridView.builder(
        shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10,
            childAspectRatio: 0.584),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final d = items[i].discountPct;
          return Stack(clipBehavior: Clip.none, children: [
            ProductCard(rich: true, product: items[i], hideAvail: true),
            if (d > 0) PositionedDirectional(top: 8, start: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: rib,
                    borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(2),
                        bottomRight: Radius.circular(9),
                        bottomLeft: Radius.circular(9))),
                child: Text('-$d%', style: const TextStyle(
                    color: Colors.white, fontSize: 13,
                    fontWeight: FontWeight.w900)),
              )),
          ]);
        },
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
            rich: true, product: items[i], hideAvail: true)),
      ])),
    ));
  }
}

// ═══ 6. COUPON CARD (dashed + copy) ═════════════════════════════════════
class PromoCouponBlock extends StatelessWidget {
  const PromoCouponBlock({super.key, required this.p, required this.ar});
  final Map<String, dynamic> p;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    final code = (p['code'] ?? '').toString();
    if (code.isEmpty) return const SizedBox.shrink();
    final c1 = promoParseColor(p['c1']) ?? UellowColors.yellow;
    final title = _tx(p, 'titleEn', 'titleAr', ar);
    final sub = _tx(p, 'subEn', 'subAr', ar);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c1.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c1, width: 1.6),
      ),
      child: Row(children: [
        Text('🎟', style: const TextStyle(fontSize: 30)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Text(title.isNotEmpty ? title
              : (ar ? 'كوبون خصم' : 'Discount coupon'),
              style: const TextStyle(fontWeight: FontWeight.w900,
                  fontSize: 14, color: UellowColors.ink)),
          if (sub.isNotEmpty)
            Text(sub, style: const TextStyle(fontSize: 11,
                color: UellowColors.muted)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: c1, width: 1.2,
                  strokeAlign: BorderSide.strokeAlignOutside),
            ),
            child: Text(code, style: TextStyle(
                fontFamily: 'monospace', letterSpacing: 2,
                fontWeight: FontWeight.w900, fontSize: 16,
                color: promoParseColor(p['code_color'])
                    ?? UellowColors.darkBrown)),
          ),
        ])),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: code));
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(ar ? 'نُسخ الكود ✓' : 'Code copied ✓'),
                duration: const Duration(seconds: 1)));
          },
          style: ElevatedButton.styleFrom(backgroundColor: c1,
              foregroundColor: UellowColors.darkBrown,
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10)),
          child: Text(ar ? 'انسخ' : 'Copy',
              style: const TextStyle(fontWeight: FontWeight.w900)),
        ),
      ]),
    );
  }
}

// ═══ 7. BANNER + CTA ════════════════════════════════════════════════════
class PromoBannerCtaBlock extends StatelessWidget {
  const PromoBannerCtaBlock({super.key, required this.p, required this.ar,
      required this.onTap});
  final Map<String, dynamic> p;
  final bool ar;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c1 = promoParseColor(p['c1']) ?? UellowColors.darkBrown;
    final c2 = promoParseColor(p['c2']) ?? const Color(0xFF1F1100);
    final txt = promoParseColor(p['text_color']) ?? Colors.white;
    final img = (p['image_url'] ?? '').toString();
    final title = _tx(p, 'titleEn', 'titleAr', ar);
    final cta = _tx(p, 'ctaEn', 'ctaAr', ar);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: ((p['height'] as num?)?.toDouble() ?? 130).clamp(90, 260),
        margin: const EdgeInsets.symmetric(horizontal: 10),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(colors: [c1, c2]),
        ),
        child: Stack(fit: StackFit.expand, children: [
          if (img.isNotEmpty)
            CachedNetworkImage(imageUrl: _abs(img), fit: BoxFit.cover,
                errorWidget: (_, __, ___) => const SizedBox.shrink()),
          if (img.isNotEmpty)
            Container(color: Colors.black.withValues(alpha: .30)),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Expanded(child: Text(title, maxLines: 3,
                  style: TextStyle(color: txt, fontSize: 18, height: 1.25,
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
        ]),
      ),
    );
  }
}

// ═══ 8. TIERS (buy more save more) ══════════════════════════════════════
class PromoTiersBlock extends StatelessWidget {
  const PromoTiersBlock({super.key, required this.p, required this.ar});
  final Map<String, dynamic> p;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    final c1 = promoParseColor(p['c1']) ?? UellowColors.yellow;
    final tiers = <(String, String)>[];
    for (var i = 1; i <= 4; i++) {
      final t = _tx(p, 'tier${i}En', 'tier${i}Ar', ar);
      if (t.isNotEmpty) tiers.add(('${i == 1 ? '🥉' : i == 2 ? '🥈' : i == 3 ? '🥇' : '🏆'}', t));
    }
    if (tiers.isEmpty) return const SizedBox.shrink();
    final title = _tx(p, 'titleEn', 'titleAr', ar);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFEDEDED))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title.isNotEmpty ? title
            : (ar ? 'اشترِ أكثر، وفّر أكثر' : 'Buy more, save more'),
            style: const TextStyle(fontWeight: FontWeight.w900,
                fontSize: 15, color: UellowColors.ink)),
        const SizedBox(height: 10),
        for (var i = 0; i < tiers.length; i++) ...[
          Row(children: [
            Container(width: 34, height: 34, alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: c1.withValues(alpha: .12 + i * .1),
                    shape: BoxShape.circle),
                child: Text(tiers[i].$1,
                    style: const TextStyle(fontSize: 16))),
            const SizedBox(width: 10),
            Expanded(child: Text(tiers[i].$2,
                style: const TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: UellowColors.ink))),
          ]),
          if (i < tiers.length - 1) Padding(
            padding: const EdgeInsetsDirectional.only(start: 16),
            child: Container(width: 2, height: 12,
                color: c1.withValues(alpha: .35)),
          ),
        ],
      ]),
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
              Text(prod.name.current(ar ? 'ar' : 'en'), maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: UellowColors.ink, height: 1.3)),
              const SizedBox(height: 4),
              Text(prod.price.formatLocalized(ar ? 'ar' : 'en'),
                  style: TextStyle(fontSize: 14,
                      fontWeight: FontWeight.w900, color: c1)),
            ]),
          ),
        ]),
      ),
    );
  }
}
