// =============================================================================
// Dynamic block extras — block envelope (bg + pattern + title + spacing) and
// the new block variants introduced in v2.0.34/v2.0.36 (Quick Pills, Themed
// Promo, Mini Category Cards, Welcome Deal, Discount Strip, Promo Pills,
// Explore More).
//
// Each new widget is keyed by a `kind` string the builder writes into
// blocks_json. The dispatcher in dynamic_page_screen.dart fans out here.
// =============================================================================
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;

import '../../api/uellow_api.dart';
import '../../api/uellow_models.dart';
import '../router/uellow_router.dart';
import '../theme/uellow_theme.dart';
import '../widgets/product_card.dart';
import 'dynamic_page_screen.dart' show DynTheme, renderDynamicBlock;

// ─── BLOCK ENVELOPE ─────────────────────────────────────────────────────────
// Wraps every block. Reads four optional props:
//   show_title  : bool (default true) — if false, omits titleEn/titleAr text
//   bg_color    : hex string — background fill behind the block
//   bg_pattern  : 'none'|'dots'|'lines'|'grid'|'mesh'|'waves'|'confetti'|'lanterns'
//   bg_image    : URL — image background (top of pattern, if both set)
//   title_gap   : px between title and content (default 8)
//   pad_y       : px vertical padding of the block (default 8)
// =============================================================================
class BlockEnvelope extends StatelessWidget {
  const BlockEnvelope({
    super.key,
    required this.props,
    required this.child,
    this.theme,
  });

  final Map<String, dynamic> props;
  final Widget child;
  final DynTheme? theme;

  @override
  Widget build(BuildContext context) {
    final padY = (props['pad_y'] as num?)?.toDouble() ?? 8.0;
    final bgColor = _hex(props['bg_color']);
    final pattern = (props['bg_pattern'] as String?) ?? 'none';
    final bgImage = (props['bg_image'] as String?) ?? '';
    final hasBg = bgColor != null || pattern != 'none' || bgImage.isNotEmpty;
    // v2.0.69 — when background is set, give the content breathing room and
    // round the colored panel so product rows don't sit flush against its
    // edges. Both knobs are admin-configurable.
    final innerRadius = ((props['bg_radius'] as num?)?.toDouble() ?? 14).clamp(0, 32).toDouble();
    final innerInsetX = ((props['bg_inset_x'] as num?)?.toDouble() ?? 10).clamp(0, 40).toDouble();
    final innerPadX  = ((props['bg_pad_x'] as num?)?.toDouble() ?? 6).clamp(0, 40).toDouble();
    final innerPadY  = ((props['bg_pad_y'] as num?)?.toDouble() ?? 8).clamp(0, 40).toDouble();

    Widget content = RepaintBoundary(child: child);

    if (hasBg) {
      content = Container(
        margin: EdgeInsets.symmetric(horizontal: innerInsetX),
        padding: EdgeInsets.symmetric(horizontal: innerPadX, vertical: innerPadY),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(innerRadius),
        ),
        child: Stack(children: [
          Positioned.fill(
            child: _BackgroundLayer(
              color: null, // already painted on the Container
              pattern: pattern,
              imageUrl: bgImage,
              patternColor: theme?.dark ?? const Color(0xFF412402),
            ),
          ),
          content,
        ]),
      );
    }

    // v2.1.56 — optional asymmetric bottom padding (`pad_bottom`); the
    // Explore More block uses 0 so nothing trails the Load-more button.
    final padBottom = (props['pad_bottom'] as num?)?.toDouble() ?? padY;
    // v2.1.61 — independent gap BEFORE the block too.
    final padTop = (props['pad_top'] as num?)?.toDouble() ?? padY;
    return Padding(
      padding: EdgeInsets.only(top: padTop, bottom: padBottom),
      child: content,
    );
  }

  static Color? _hex(dynamic v) {
    if (v == null) return null;
    final s = v.toString();
    if (s.isEmpty || s == 'none' || s == 'transparent') return null;
    final m = RegExp(r'#?([0-9A-Fa-f]{6})').firstMatch(s);
    if (m == null) return null;
    return Color(int.parse('FF${m.group(1)}', radix: 16));
  }
}

class _BackgroundLayer extends StatelessWidget {
  const _BackgroundLayer({
    required this.color,
    required this.pattern,
    required this.imageUrl,
    required this.patternColor,
  });
  final Color? color;
  final String pattern;
  final String imageUrl;
  final Color patternColor;

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      if (color != null) Positioned.fill(child: ColoredBox(color: color!)),
      if (imageUrl.isNotEmpty)
        Positioned.fill(
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      if (pattern != 'none')
        Positioned.fill(
          child: CustomPaint(
            painter: _PatternPainter(
              kind: pattern,
              // v2.0.71 — slightly more visible (was 0.08) so the pattern
              // reads on yellow/gold backgrounds without looking dirty.
              color: patternColor.withValues(alpha: 0.13),
            ),
          ),
        ),
    ]);
  }
}

class _PatternPainter extends CustomPainter {
  _PatternPainter({required this.kind, required this.color});
  final String kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // v2.0.71 — antialiased + slightly rounded strokes so the pattern looks
    // crisp on top of yellow/gold backgrounds (was hard-edged jaggy lines).
    final p = Paint()
      ..color = color
      ..isAntiAlias = true
      ..strokeCap = StrokeCap.round;
    switch (kind) {
      case 'dots':
        // Slightly bigger dots on a tighter grid for a premium polka feel.
        for (double y = 10; y < size.height; y += 16) {
          for (double x = 10; x < size.width; x += 16) {
            canvas.drawCircle(Offset(x, y), 1.6, p);
          }
        }
        break;
      case 'lines':
        p.strokeWidth = 0.9;
        for (double y = 0; y < size.height; y += 14) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
        }
        break;
      case 'grid':
        p.strokeWidth = 0.9;
        for (double y = 0; y < size.height; y += 20) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
        }
        for (double x = 0; x < size.width; x += 20) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
        }
        break;
      case 'mesh':
        p.strokeWidth = 0.9;
        for (double y = 0; y < size.height + size.width; y += 22) {
          canvas.drawLine(Offset(y, 0), Offset(0, y), p);
          canvas.drawLine(
              Offset(size.width - y, 0), Offset(size.width, y), p);
        }
        break;
      case 'waves':
        p.style = PaintingStyle.stroke;
        p.strokeWidth = 1.4;
        for (double y = 12; y < size.height; y += 18) {
          final path = Path()..moveTo(0, y);
          for (double x = 0; x < size.width; x += 6) {
            path.lineTo(x, y + math.sin(x / 14) * 3);
          }
          canvas.drawPath(path, p);
        }
        break;
      case 'confetti':
        final rnd = math.Random(7);
        for (int i = 0; i < (size.width * size.height / 1600).round(); i++) {
          final c = Paint()
            ..color = [
              const Color(0xFFF5C320),
              const Color(0xFFE63946),
              const Color(0xFF1F8A40),
              const Color(0xFF1D6FB7),
            ][i % 4]
                .withOpacity(0.55);
          final cx = rnd.nextDouble() * size.width;
          final cy = rnd.nextDouble() * size.height;
          canvas.save();
          canvas.translate(cx, cy);
          canvas.rotate(rnd.nextDouble() * 3.14);
          canvas.drawRect(const Rect.fromLTWH(-3, -1, 6, 2), c);
          canvas.restore();
        }
        break;
      case 'lanterns':
        final rnd = math.Random(11);
        for (int i = 0; i < 12; i++) {
          final x = rnd.nextDouble() * size.width;
          final y = rnd.nextDouble() * size.height;
          final c = Paint()..color = const Color(0xFFF5C320).withOpacity(0.30);
          canvas.drawOval(
              Rect.fromCenter(center: Offset(x, y), width: 14, height: 22), c);
        }
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _PatternPainter old) =>
      old.kind != kind || old.color != color;
}

// ─── SECTION HEADER (reusable, respects show_title + title_gap) ─────────────
class DynSectionHeader extends StatelessWidget {
  const DynSectionHeader({
    super.key,
    required this.props,
    required this.theme,
    required this.ar,
    required this.fallbackEn,
    this.trailing,
    this.showMore = false,
    this.moreSort = 'newest',
  });
  final Map<String, dynamic> props;
  final DynTheme theme;
  final bool ar;
  final String fallbackEn;
  final Widget? trailing;
  // v2.1.60 — carousel blocks opt in: renders a quiet «عرض المزيد»
  // beside the title (opens props.link, falls back to the shop).
  final bool showMore;
  // v2.1.93 — when no explicit link is set, "more" opens a FULL product
  // list matching the block's SOURCE (category / bestsellers / a sorted
  // feed). This is the block's natural feed key (e.g. 'discount').
  final String moreSort;

  // v2.1.61 — yellow pill button (Tajawal) per request.
  Widget _moreBtn(BuildContext context) => Material(
        color: UellowColors.yellow,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () {
            final link = (props['link'] as Map?)?.cast<String, dynamic>();
            if (link != null && (link['type'] ?? 'none') != 'none') {
              openBlockLink(context, link);
              return;
            }
            // v2.1.93 — used to dump the user on the categories page with
            // no products; now it resolves the block's source.
            final src = (props['source'] ?? '').toString();
            final cid = (props['category_id'] as num?)?.toInt() ?? 0;
            final title = (ar
                    ? (props['titleAr'] ?? props['titleEn'])
                    : (props['titleEn'] ?? props['titleAr']))
                ?.toString() ?? '';
            if (cid > 0) {
              Navigator.pushNamed(context, '/collection',
                  arguments: {'category_id': cid, 'title': title});
            } else if (src == 'bestsellers') {
              Navigator.pushNamed(context, '/bestsellers');
            } else {
              final sort = const {
                'discounted': 'discount', 'newest': 'newest',
                'popular': 'popular',
              }[src] ?? moreSort;
              Navigator.pushNamed(context, '/collection',
                  arguments: {'sort': sort, 'title': title});
            }
          },
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            child: Text(ar ? 'عرض المزيد ←' : 'View more →',
                style: const TextStyle(
                    fontFamily: 'Tajawal',
                    color: UellowColors.darkBrown,
                    fontSize: 9,
                    fontWeight: FontWeight.w900)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final show = props['show_title'] != false;
    if (!show) return SizedBox(height: ((props['title_gap'] as num?)?.toDouble() ?? 0));
    final t = ar
        ? (props['titleAr']?.toString() ?? props['titleEn']?.toString() ?? fallbackEn)
        : (props['titleEn']?.toString() ?? fallbackEn);
    final subtitle = ar
        ? (props['subtitleAr']?.toString() ?? '')
        : (props['subtitleEn']?.toString() ?? '');
    // v2.0.69/70 — optional header icon OR image next to/replacing the title.
    // Modes:
    //   'beside'  — small icon-sized thumb next to the title (default)
    //   'replace' — icon-sized thumb in place of the title
    //   'banner'  — full-width image banner above the content; treated as
    //               its own title (text title is hidden). The image keeps
    //               its natural aspect ratio inside a rounded card with a
    //               soft shadow.
    // v2.1.46 — bilingual header image: the AR variant (when set) is
    // used in Arabic mode, otherwise the EN/default one.
    final headerImgEn = (props['header_image_url'] as String?) ?? '';
    final headerImgAr = (props['header_image_url_ar'] as String?) ?? '';
    final headerImg = (ar && headerImgAr.isNotEmpty)
        ? headerImgAr : headerImgEn;
    final headerIcon = (props['header_icon'] as String?) ?? '';
    // v2.0.73 — when the admin uploads a header image, default to BANNER
    // (full-width). Was defaulting to a small beside-the-title icon, but
    // that hid the uploaded artwork. They can switch back via the builder.
    final headerMode = (props['header_image_mode'] as String?)
        ?? (headerImg.isNotEmpty ? 'banner' : 'beside');
    final iconSize = ((props['header_icon_size'] as num?)?.toDouble() ?? 22).clamp(12, 64).toDouble();
    // v2.1.36 — explicit image width/height from the builder; falls back
    // to the square icon size when not set.
    final imgW = ((props['header_image_w'] as num?)?.toDouble() ?? iconSize).clamp(12, 240).toDouble();
    final imgH = ((props['header_image_h'] as num?)?.toDouble() ?? iconSize).clamp(12, 160).toDouble();
    final bannerHeight = ((props['header_banner_height'] as num?)?.toDouble() ?? 84).clamp(40, 240).toDouble();
    final bannerRadius = ((props['header_banner_radius'] as num?)?.toDouble() ?? 12).clamp(0, 32).toDouble();
    final bannerFit = (props['header_banner_fit'] as String?) ?? 'cover'; // cover | contain

    // ── BANNER MODE — full-width header image as the section title ───────
    if (headerMode == 'banner' && headerImg.isNotEmpty) {
      final gap = (props['title_gap'] as num?)?.toDouble() ?? 6;
      final gapTop = (props['title_gap_top'] as num?)?.toDouble() ?? 4;
      return Padding(
        padding: EdgeInsets.fromLTRB(12, gapTop, 12, gap),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(bannerRadius),
          child: Container(
            width: double.infinity,
            height: bannerHeight,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(bannerRadius),
              boxShadow: [BoxShadow(
                color: theme.dark.withOpacity(0.08),
                blurRadius: 10, offset: const Offset(0, 3),
              )],
            ),
            child: Stack(fit: StackFit.expand, children: [
              CachedNetworkImage(
                imageUrl: headerImg,
                fit: bannerFit == 'contain' ? BoxFit.contain : BoxFit.cover,
                placeholder: (_, __) => Container(color: theme.primary.withOpacity(0.06)),
                errorWidget: (_, __, ___) => Container(
                    color: theme.primary.withOpacity(0.06),
                    child: Icon(Icons.image_outlined,
                        color: theme.dark.withOpacity(0.3))),
              ),
              // Subtle gradient veil + optional overlay text/trailing.
              if (subtitle.isNotEmpty || trailing != null)
                Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.black.withOpacity(0.35), Colors.transparent],
                    begin: Alignment.bottomLeft, end: Alignment.topRight,
                  ),
                ))),
              if (subtitle.isNotEmpty)
                Positioned(
                  left: 14, right: 14, bottom: 10,
                  child: Text(subtitle,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white, fontSize: 12,
                        fontWeight: FontWeight.w700,
                        shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                      )),
                ),
              if (trailing != null || showMore)
                Positioned(
                  top: 8, right: ar ? null : 8, left: ar ? 8 : null,
                  child: trailing ?? Builder(builder: _moreBtn),
                ),
            ]),
          ),
        ),
      );
    }

    // ── ICON / SMALL-IMAGE MODES ─────────────────────────────────────────
    Widget? leading;
    if (headerImg.isNotEmpty) {
      leading = ClipRRect(
        borderRadius: BorderRadius.circular(imgH / 5),
        child: CachedNetworkImage(
          imageUrl: headerImg, width: imgW, height: imgH, fit: BoxFit.cover,
          errorWidget: (_, __, ___) => SizedBox(width: imgW, height: imgH),
        ),
      );
    } else if (headerIcon.isNotEmpty) {
      leading = SizedBox(
        width: iconSize, height: iconSize,
        child: Center(child: Text(headerIcon, style: TextStyle(fontSize: iconSize * 0.85))),
      );
    }

    // Replace title with image when mode = 'replace' and a header image exists.
    final showTextTitle = !(headerMode == 'replace' && headerImg.isNotEmpty);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        14,
        // v2.1.61 — admin-tunable gap before the title.
        (props['title_gap_top'] as num?)?.toDouble() ?? 6,
        14,
        (props['title_gap'] as num?)?.toDouble() ?? 6,
      ),
      child: Row(children: [
        if (leading != null && headerMode == 'replace' && headerImg.isNotEmpty)
          Expanded(child: Align(alignment: ar ? Alignment.centerRight : Alignment.centerLeft, child: leading))
        else ...[
          if (leading != null) Padding(padding: EdgeInsets.only(right: ar ? 0 : 10, left: ar ? 10 : 0), child: leading),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showTextTitle)
                Text(t,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: theme.dark,
                    )),
              if (subtitle.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(subtitle,
                      style: TextStyle(
                        color: theme.dark.withOpacity(0.55),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                      )),
                ),
            ],
          )),
        ],
        if (trailing != null) trailing!
        else if (showMore) Builder(builder: _moreBtn),
      ]),
    );
  }
}

// ─── QUICK PILLS — Banggood-style top action icons ──────────────────────────
class QuickPillsBlock extends StatelessWidget {
  const QuickPillsBlock({super.key, required this.p, required this.data, required this.t, required this.ar});
  final Map<String, dynamic> p;
  final Map<String, dynamic> data;
  final DynTheme t;
  final bool ar;

  @override
  Widget build(BuildContext context) {
    final items = (p['items'] as List? ?? const []).cast<dynamic>();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DynSectionHeader(props: p, theme: t, ar: ar, fallbackEn: 'Quick links'),
      SizedBox(
        height: 92,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (_, i) {
            final it = (items[i] as Map).cast<String, dynamic>();
            final icon = (it['icon'] as String?) ?? '⭐';
            final label = ar
                ? (it['labelAr']?.toString() ?? it['labelEn']?.toString() ?? '')
                : (it['labelEn']?.toString() ?? '');
            final bg = BlockEnvelope._hex(it['color']) ??
                [
                  const Color(0xFFFFE5E5),
                  const Color(0xFFFFEFC2),
                  const Color(0xFFE5F0FF),
                  const Color(0xFFE7F8E7),
                  const Color(0xFFF5E7FF),
                ][i % 5];
            final fg = BlockEnvelope._hex(it['fg']) ?? t.dark;
            return GestureDetector(
              onTap: () => _openLink(context, (it['link'] as Map?)?.cast<String, dynamic>()),
              child: SizedBox(
                width: 64,
                child: Column(children: [
                  Container(
                    width: 52, height: 52,
                    decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: Text(icon, style: const TextStyle(fontSize: 24)),
                  ),
                  const SizedBox(height: 6),
                  Text(label,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11, color: fg, fontWeight: FontWeight.w700,
                      )),
                ]),
              ),
            );
          },
        ),
      ),
    ]);
  }
}

// ─── PROMO PILLS — two-up colored pills (Free Shipping / Flash Sale) ─────────
class PromoPillsBlock extends StatelessWidget {
  const PromoPillsBlock({super.key, required this.p, required this.t, required this.ar});
  final Map<String, dynamic> p;
  final DynTheme t;
  final bool ar;

  @override
  Widget build(BuildContext context) {
    final items = ((p['pills'] as List?) ?? const []).cast<dynamic>()
        .map((e) => (e as Map).cast<String, dynamic>()).toList();
    if (items.isEmpty) return const SizedBox.shrink();

    final layout = (p['layout'] as String?) ?? 'row';
    final gap = ((p['gap'] as num?)?.toDouble() ?? 8).clamp(2, 20).toDouble();
    final pad = const EdgeInsets.fromLTRB(12, 4, 12, 4);

    Widget pill(Map<String, dynamic> it, int i) =>
        _PromoPill(it: it, t: t, ar: ar, layout: layout, parentP: p, index: i);

    switch (layout) {
      case 'grid_2x2':
      case 'grid_2x3':
      case 'grid_3x2':
        final cols = layout == 'grid_3x2' ? 3 : 2;
        final ratio = layout == 'grid_3x2' ? 1.6 : 2.4;
        return Padding(padding: pad,
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                crossAxisSpacing: gap, mainAxisSpacing: gap,
                childAspectRatio: ratio),
            itemCount: items.length,
            itemBuilder: (_, i) => pill(items[i], i),
          ));
      case 'vertical':
        return Padding(padding: pad, child: Column(children: [
          for (int i = 0; i < items.length; i++) ...[
            pill(items[i], i),
            if (i < items.length - 1) SizedBox(height: gap),
          ],
        ]));
      case 'ticker':
        return _PromoTicker(items: items, t: t, ar: ar, p: p);
      case 'compact_row':
        return Padding(padding: pad,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            child: Row(children: [
              for (int i = 0; i < items.length; i++) ...[
                _PromoCompact(it: items[i], t: t, ar: ar, parentP: p, index: i),
                if (i < items.length - 1) SizedBox(width: gap),
              ],
            ]),
          ));
      case 'featured':
        // First pill renders large, rest fit in a 2-col grid below.
        if (items.isEmpty) return const SizedBox.shrink();
        final first = items.first;
        final rest = items.skip(1).toList();
        return Padding(padding: pad, child: Column(children: [
          SizedBox(height: 80, child: pill(first, 0)),
          if (rest.isNotEmpty) SizedBox(height: gap),
          if (rest.isNotEmpty) GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2, crossAxisSpacing: gap, mainAxisSpacing: gap,
                  childAspectRatio: 2.2),
              itemCount: rest.length,
              itemBuilder: (_, i) => pill(rest[i], i + 1)),
        ]));
      case 'iconic_row':
        return Padding(padding: pad,
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (int i = 0; i < items.length; i++)
                _PromoIconic(it: items[i], t: t, ar: ar, parentP: p, index: i),
            ]),
        );

      // ── v2.0.64: slim single-line variants ──────────────────────────
      case 'chip':
        // Very slim 28px pills, icon + tiny text — horizontal scroll.
        return SizedBox(height: 30, child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: items.length,
          separatorBuilder: (_, __) => SizedBox(width: gap.clamp(4, 10)),
          itemBuilder: (_, i) => _PromoChip(
              it: items[i], t: t, ar: ar, parentP: p, index: i),
        ));

      case 'trust_bar':
        // Inline "icon · text" entries separated by dots — looks like
        // Amazon's "FREE delivery · Returns · Help" header bar.
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Wrap(
            spacing: 8, runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (int i = 0; i < items.length; i++) ...[
                _PromoInlineEntry(it: items[i], t: t, ar: ar,
                    parentP: p, index: i),
                if (i < items.length - 1)
                  Text('·', style: TextStyle(
                      color: t.dark.withValues(alpha: 0.4),
                      fontSize: 14, fontWeight: FontWeight.w900)),
              ],
            ],
          ),
        );

      case 'mini_bar':
        // Full-width 24px pills stacked vertically — extreme compact.
        return Padding(padding: pad, child: Column(
          children: [
            for (int i = 0; i < items.length; i++) ...[
              _PromoMiniBar(it: items[i], t: t, ar: ar, parentP: p, index: i),
              if (i < items.length - 1) SizedBox(height: gap.clamp(2, 6)),
            ],
          ],
        ));

      case 'inline_dots':
        // No background, no border — icon + text inline with dot dividers.
        return Padding(padding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 6),
          child: Wrap(
            spacing: 10, runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (int i = 0; i < items.length; i++) ...[
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Text((items[i]['icon'] as String?) ?? '🎁',
                      style: const TextStyle(fontSize: 13)),
                  const SizedBox(width: 4),
                  Text(ar
                      ? (items[i]['titleAr']?.toString()
                          ?? items[i]['titleEn']?.toString() ?? '')
                      : (items[i]['titleEn']?.toString() ?? ''),
                      style: TextStyle(fontSize: 11.5,
                          fontWeight: FontWeight.w700, color: t.dark)),
                ]),
                if (i < items.length - 1)
                  Container(width: 3, height: 3,
                      decoration: BoxDecoration(
                          color: t.dark.withValues(alpha: 0.35),
                          shape: BoxShape.circle)),
              ],
            ],
          ),
        );

      case 'ticker_slim':
        return SizedBox(height: 28, child: _PromoTickerSlim(
            items: items, t: t, ar: ar, p: p));

      case 'cols_3':
        // v2.0.66 — 3 equal columns spanning full screen width.
        // Each cell shows an icon above a single tiny line of text so
        // 3 items fit comfortably even on narrow phones.
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              for (int i = 0; i < items.length && i < 3; i++) ...[
                Expanded(child: _PromoCol3(
                    it: items[i], t: t, ar: ar, parentP: p, index: i)),
                if (i < items.length - 1 && i < 2) SizedBox(width: gap),
              ],
            ],
          ),
        );

      default: // row
        return Padding(padding: pad, child: Row(children: [
          for (int i = 0; i < items.length; i++) ...[
            Expanded(child: pill(items[i], i)),
            if (i < items.length - 1) SizedBox(width: gap),
          ],
        ]));
    }
  }
}

class _PromoTicker extends StatefulWidget {
  const _PromoTicker({required this.items, required this.t, required this.ar,
      required this.p});
  final List<Map<String, dynamic>> items;
  final DynTheme t;
  final bool ar;
  final Map<String, dynamic> p;
  @override State<_PromoTicker> createState() => _PromoTickerState();
}
class _PromoTickerState extends State<_PromoTicker> {
  final _ctrl = ScrollController();
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!_ctrl.hasClients) return;
      final max = _ctrl.position.maxScrollExtent;
      final off = _ctrl.offset + 1.0;
      _ctrl.jumpTo(off >= max ? 0 : off);
    });
  }
  @override void dispose() { _timer?.cancel(); _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final doubled = [...widget.items, ...widget.items];
    return SizedBox(height: 56, child: ListView.separated(
      controller: _ctrl,
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: doubled.length,
      separatorBuilder: (_, __) => const SizedBox(width: 8),
      itemBuilder: (_, i) => _PromoPill(
          it: doubled[i], t: widget.t, ar: widget.ar,
          layout: 'ticker', parentP: widget.p, index: i),
    ));
  }
}

class _PromoCompact extends StatelessWidget {
  const _PromoCompact({required this.it, required this.t, required this.ar,
      required this.parentP, required this.index});
  final Map<String, dynamic> it;
  final DynTheme t;
  final bool ar;
  final Map<String, dynamic> parentP;
  final int index;
  @override
  Widget build(BuildContext context) {
    final icon = (it['icon'] as String?) ?? '🎁';
    final title = ar
        ? (it['titleAr']?.toString() ?? it['titleEn']?.toString() ?? '')
        : (it['titleEn']?.toString() ?? '');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
          color: BlockEnvelope._hex(it['color']) ?? const Color(0xFFFFF6E0),
          borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(icon, style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 6),
        Text(title, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700,
            color: BlockEnvelope._hex(it['text_color']) ?? t.dark)),
      ]),
    );
  }
}

// ── v2.0.64 slim single-line widgets ──────────────────────────────────

class _PromoChip extends StatelessWidget {
  const _PromoChip({required this.it, required this.t, required this.ar,
      required this.parentP, required this.index});
  final Map<String, dynamic> it;
  final DynTheme t;
  final bool ar;
  final Map<String, dynamic> parentP;
  final int index;
  @override
  Widget build(BuildContext context) {
    final icon = (it['icon'] as String?) ?? '🎁';
    final title = ar
        ? (it['titleAr']?.toString() ?? it['titleEn']?.toString() ?? '')
        : (it['titleEn']?.toString() ?? '');
    final bg = BlockEnvelope._hex(it['color']) ?? const Color(0xFFFFF6E0);
    final fg = BlockEnvelope._hex(it['text_color']) ?? t.dark;
    return GestureDetector(
      onTap: () => _openLink(context, (it['link'] as Map?)?.cast<String, dynamic>()),
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(color: bg,
            borderRadius: BorderRadius.circular(14)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(icon, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 5),
          Text(title, style: TextStyle(fontSize: 11,
              fontWeight: FontWeight.w800, color: fg, letterSpacing: 0.1)),
        ]),
      ),
    );
  }
}

class _PromoInlineEntry extends StatelessWidget {
  const _PromoInlineEntry({required this.it, required this.t,
      required this.ar, required this.parentP, required this.index});
  final Map<String, dynamic> it;
  final DynTheme t;
  final bool ar;
  final Map<String, dynamic> parentP;
  final int index;
  @override
  Widget build(BuildContext context) {
    final icon = (it['icon'] as String?) ?? '🎁';
    final title = ar
        ? (it['titleAr']?.toString() ?? it['titleEn']?.toString() ?? '')
        : (it['titleEn']?.toString() ?? '');
    final iconColor = BlockEnvelope._hex(it['icon_color'])
        ?? t.dark.withValues(alpha: 0.85);
    return GestureDetector(
      onTap: () => _openLink(context, (it['link'] as Map?)?.cast<String, dynamic>()),
      child: Row(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center, children: [
        Container(width: 18, height: 18, alignment: Alignment.center,
            child: Text(icon,
                style: TextStyle(fontSize: 13, color: iconColor))),
        const SizedBox(width: 5),
        Text(title, style: TextStyle(fontSize: 11.5,
            fontWeight: FontWeight.w700, color: t.dark, height: 1.0)),
      ]),
    );
  }
}

class _PromoMiniBar extends StatelessWidget {
  const _PromoMiniBar({required this.it, required this.t, required this.ar,
      required this.parentP, required this.index});
  final Map<String, dynamic> it;
  final DynTheme t;
  final bool ar;
  final Map<String, dynamic> parentP;
  final int index;
  @override
  Widget build(BuildContext context) {
    final icon = (it['icon'] as String?) ?? '🎁';
    final title = ar
        ? (it['titleAr']?.toString() ?? it['titleEn']?.toString() ?? '')
        : (it['titleEn']?.toString() ?? '');
    final sub = ar
        ? (it['subtitleAr']?.toString() ?? it['subtitleEn']?.toString() ?? '')
        : (it['subtitleEn']?.toString() ?? '');
    final bg = BlockEnvelope._hex(it['color']) ?? const Color(0xFFFFF6E0);
    final iconColor = BlockEnvelope._hex(it['icon_color']) ?? t.dark;
    final fg = BlockEnvelope._hex(it['text_color']) ?? t.dark;
    return GestureDetector(
      onTap: () => _openLink(context, (it['link'] as Map?)?.cast<String, dynamic>()),
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(color: bg,
            borderRadius: BorderRadius.circular(6)),
        child: Row(children: [
          Text(icon, style: TextStyle(fontSize: 13, color: iconColor)),
          const SizedBox(width: 8),
          Expanded(child: Text(title,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11,
                  fontWeight: FontWeight.w800, color: fg))),
          if (sub.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(sub, style: TextStyle(fontSize: 10,
                fontWeight: FontWeight.w600,
                color: fg.withValues(alpha: 0.65))),
          ],
        ]),
      ),
    );
  }
}

class _PromoCol3 extends StatelessWidget {
  const _PromoCol3({required this.it, required this.t, required this.ar,
      required this.parentP, required this.index});
  final Map<String, dynamic> it;
  final DynTheme t;
  final bool ar;
  final Map<String, dynamic> parentP;
  final int index;
  @override
  Widget build(BuildContext context) {
    final icon = (it['icon'] as String?) ?? '🎁';
    final title = ar
        ? (it['titleAr']?.toString() ?? it['titleEn']?.toString() ?? '')
        : (it['titleEn']?.toString() ?? '');
    final bg = BlockEnvelope._hex(it['color']) ?? const Color(0xFFFFF6E0);
    final iconColor = BlockEnvelope._hex(it['icon_color']) ?? t.dark;
    final fg = BlockEnvelope._hex(it['text_color']) ?? t.dark;
    return GestureDetector(
      onTap: () => _openLink(context, (it['link'] as Map?)?.cast<String, dynamic>()),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(color: bg,
            borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center,
            children: [
          Text(icon, style: TextStyle(fontSize: 12, color: iconColor)),
          const SizedBox(width: 4),
          Flexible(child: Text(title,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 9.5,
                  fontWeight: FontWeight.w700, color: fg, height: 1.1))),
        ]),
      ),
    );
  }
}

class _PromoTickerSlim extends StatefulWidget {
  const _PromoTickerSlim({required this.items, required this.t,
      required this.ar, required this.p});
  final List<Map<String, dynamic>> items;
  final DynTheme t;
  final bool ar;
  final Map<String, dynamic> p;
  @override State<_PromoTickerSlim> createState() => _PromoTickerSlimState();
}
class _PromoTickerSlimState extends State<_PromoTickerSlim> {
  final _ctrl = ScrollController();
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!_ctrl.hasClients) return;
      final max = _ctrl.position.maxScrollExtent;
      final off = _ctrl.offset + 0.6;
      _ctrl.jumpTo(off >= max ? 0 : off);
    });
  }
  @override void dispose() { _timer?.cancel(); _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final doubled = [...widget.items, ...widget.items];
    return ListView.separated(
      controller: _ctrl,
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: doubled.length,
      separatorBuilder: (_, __) => Container(width: 1, height: 12,
          margin: const EdgeInsets.symmetric(horizontal: 10),
          color: widget.t.dark.withValues(alpha: 0.2)),
      itemBuilder: (_, i) => _PromoInlineEntry(
          it: doubled[i], t: widget.t, ar: widget.ar,
          parentP: widget.p, index: i),
    );
  }
}

class _PromoIconic extends StatelessWidget {
  const _PromoIconic({required this.it, required this.t, required this.ar,
      required this.parentP, required this.index});
  final Map<String, dynamic> it;
  final DynTheme t;
  final bool ar;
  final Map<String, dynamic> parentP;
  final int index;
  @override
  Widget build(BuildContext context) {
    final icon = (it['icon'] as String?) ?? '🎁';
    final title = ar
        ? (it['titleAr']?.toString() ?? it['titleEn']?.toString() ?? '')
        : (it['titleEn']?.toString() ?? '');
    final bg = BlockEnvelope._hex(it['color']) ?? const Color(0xFFFFF6E0);
    return GestureDetector(
      onTap: () => _openLink(context, (it['link'] as Map?)?.cast<String, dynamic>()),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 44, height: 44,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          child: Center(child: Text(icon, style: const TextStyle(fontSize: 22))),
        ),
        const SizedBox(height: 4),
        Text(title, textAlign: TextAlign.center, maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700,
                color: t.dark, height: 1.1)),
      ]),
    );
  }
}

class _PromoPill extends StatelessWidget {
  const _PromoPill({required this.it, required this.t, required this.ar,
      this.layout = 'row', this.parentP = const {}, this.index = 0});
  final Map<String, dynamic> it;
  final DynTheme t;
  final bool ar;
  final String layout;
  final Map<String, dynamic> parentP;
  final int index;

  @override
  Widget build(BuildContext context) {
    final kind = (it['kind'] as String?) ?? 'pill';
    final icon = (it['icon'] as String?) ?? '🎁';
    final title = ar
        ? (it['titleAr']?.toString() ?? it['titleEn']?.toString() ?? '')
        : (it['titleEn']?.toString() ?? '');
    final sub = ar
        ? (it['subtitleAr']?.toString() ?? it['subtitleEn']?.toString() ?? '')
        : (it['subtitleEn']?.toString() ?? '');
    final style = (parentP['style'] as String?) ?? 'filled';
    final iconPos = (parentP['icon_position'] as String?) ?? 'left';
    final iconSize = {'sm': 14.0, 'md': 18.0, 'lg': 24.0, 'xl': 32.0}
        [parentP['icon_size'] as String? ?? 'md'] ?? 18.0;
    final animation = (parentP['animation'] as String?) ?? 'fade_in';
    final countUp = parentP['count_up'] != false;
    final badge = (it['badge_text'] as String?) ?? '';

    final bg = BlockEnvelope._hex(it['color']) ?? const Color(0xFFFFF6E0);
    final iconColor = BlockEnvelope._hex(it['icon_color']) ?? t.dark;
    final textColor = BlockEnvelope._hex(it['text_color']) ?? t.dark;

    // Decoration based on style
    BoxDecoration deco;
    switch (style) {
      case 'outlined':
        deco = BoxDecoration(color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: iconColor.withValues(alpha: 0.35), width: 1));
        break;
      case 'gradient':
        deco = BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [bg, Color.lerp(bg, Colors.white, 0.35)!]));
        break;
      case 'glass':
        deco = BoxDecoration(
            color: bg.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.45)));
        break;
      case 'minimal':
        deco = const BoxDecoration();
        break;
      case 'iconic':
        deco = const BoxDecoration();
        break;
      case 'neumorphic':
        deco = BoxDecoration(color: bg,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(color: Colors.white.withValues(alpha: 0.6),
                  blurRadius: 6, offset: const Offset(-3, -3)),
              BoxShadow(color: t.dark.withValues(alpha: 0.12),
                  blurRadius: 8, offset: const Offset(3, 3)),
            ]);
        break;
      default: // filled
        deco = BoxDecoration(color: bg,
            borderRadius: BorderRadius.circular(10));
    }

    // Stat counter
    Widget statValue() {
      final raw = (it['value'] as num?) ?? 0;
      final suffix = (it['value_suffix'] as String?) ?? '';
      if (!countUp) {
        return Text(_fmt(raw) + suffix, style: TextStyle(
            fontSize: 18, fontWeight: FontWeight.w900, color: textColor,
            letterSpacing: -0.3));
      }
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: raw.toDouble()),
        duration: Duration(milliseconds: 1500 + (index * 100).clamp(0, 600)),
        curve: Curves.easeOutCubic,
        builder: (_, v, __) => Text(_fmt(v) + suffix, style: TextStyle(
            fontSize: 18, fontWeight: FontWeight.w900, color: textColor,
            letterSpacing: -0.3)),
      );
    }

    // Icon widget — different sizes per style
    Widget iconWidget() {
      if (style == 'iconic') {
        return Container(
          width: 48, height: 48,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          child: Center(child: Text(icon, style: TextStyle(fontSize: iconSize + 6))),
        );
      }
      return Text(icon, style: TextStyle(fontSize: iconSize));
    }

    Widget textCol() {
      if (kind == 'stat') {
        return Column(crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min, children: [
          statValue(),
          if (title.isNotEmpty) Text(title, maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                  color: textColor.withValues(alpha: 0.75))),
        ]);
      }
      if (kind == 'icon_only') return const SizedBox.shrink();
      if (kind == 'badge') {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: iconColor,
              borderRadius: BorderRadius.circular(4)),
          child: Text(title, style: const TextStyle(
              color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900,
              letterSpacing: 0.6)),
        );
      }
      // pill kind (default)
      return Column(crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min, children: [
        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900,
                color: textColor)),
        if (sub.isNotEmpty)
          Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5,
                  color: textColor.withValues(alpha: 0.65),
                  fontWeight: FontWeight.w600)),
      ]);
    }

    // Build inner content based on icon position
    Widget inner;
    if (iconPos == 'top') {
      inner = Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        IconTheme(data: IconThemeData(color: iconColor), child: iconWidget()),
        const SizedBox(height: 6),
        textCol(),
      ]);
    } else if (iconPos == 'right') {
      inner = Row(children: [
        Expanded(child: textCol()),
        const SizedBox(width: 8),
        IconTheme(data: IconThemeData(color: iconColor), child: iconWidget()),
      ]);
    } else {
      inner = Row(children: [
        IconTheme(data: IconThemeData(color: iconColor), child: iconWidget()),
        if (kind != 'icon_only') const SizedBox(width: 8),
        if (kind != 'icon_only') Expanded(child: textCol()),
      ]);
    }

    final card = Stack(clipBehavior: Clip.none, children: [
      GestureDetector(
        onTap: () => _openLink(context, (it['link'] as Map?)?.cast<String, dynamic>()),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: deco,
          child: inner,
        ),
      ),
      if (badge.isNotEmpty) Positioned(top: -4, right: -4, child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
        decoration: BoxDecoration(color: const Color(0xFFE63946),
            borderRadius: BorderRadius.circular(4),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 3)]),
        child: Text(badge, style: const TextStyle(color: Colors.white,
            fontSize: 8.5, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
      )),
    ]);

    // Entry animation
    if (animation == 'fade_in') {
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 300 + (index * 80).clamp(0, 800)),
        curve: Curves.easeOut,
        builder: (_, v, child) => Opacity(opacity: v, child: child),
        child: card,
      );
    }
    if (animation == 'slide_up') {
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 300 + (index * 80).clamp(0, 800)),
        curve: Curves.easeOutCubic,
        builder: (_, v, child) => Transform.translate(
            offset: Offset(0, (1 - v) * 12),
            child: Opacity(opacity: v, child: child)),
        child: card,
      );
    }
    return card;
  }

  static String _fmt(num v) {
    if (v == v.toInt()) return v.toInt().toString();
    return v.toStringAsFixed(1);
  }
}

// ─── THEMED PROMO — Temu-style colored cards (Fashion trends / Tech life) ───
class ThemedPromoBlock extends StatelessWidget {
  const ThemedPromoBlock({super.key, required this.p, required this.t, required this.ar});
  final Map<String, dynamic> p;
  final DynTheme t;
  final bool ar;

  @override
  Widget build(BuildContext context) {
    final cards = (p['cards'] as List? ?? const []).cast<dynamic>();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DynSectionHeader(props: p, theme: t, ar: ar, fallbackEn: 'Featured'),
      SizedBox(
        height: 158,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          itemCount: cards.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final c = (cards[i] as Map).cast<String, dynamic>();
            return _ThemedPromoCard(c: c, t: t, ar: ar);
          },
        ),
      ),
    ]);
  }
}

class _ThemedPromoCard extends StatelessWidget {
  const _ThemedPromoCard({required this.c, required this.t, required this.ar});
  final Map<String, dynamic> c;
  final DynTheme t;
  final bool ar;

  @override
  Widget build(BuildContext context) {
    final title = ar
        ? (c['titleAr']?.toString() ?? c['titleEn']?.toString() ?? '')
        : (c['titleEn']?.toString() ?? '');
    final sub = ar
        ? (c['subtitleAr']?.toString() ?? c['subtitleEn']?.toString() ?? '')
        : (c['subtitleEn']?.toString() ?? '');
    final bg = BlockEnvelope._hex(c['color']) ?? const Color(0xFFEAF7C9);
    final img = pickLocalizedImage(c, ar);
    return GestureDetector(
      onTap: () => _openLink(context, (c['link'] as Map?)?.cast<String, dynamic>()),
      child: Container(
        width: 175,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: TextStyle(
                fontWeight: FontWeight.w900, fontSize: 13.5, color: t.dark,
              )),
          if (sub.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(sub,
                  style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600,
                    color: t.dark.withOpacity(0.65),
                  )),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: img.isNotEmpty
                  ? CachedNetworkImage(imageUrl: img, fit: BoxFit.cover)
                  : Container(color: Colors.white.withOpacity(0.5)),
            ),
          ),
        ]),
      ),
    );
  }
}

// ─── WELCOME DEAL — large card with 2×2 product images + sticker ────────────
class WelcomeDealBlock extends StatelessWidget {
  const WelcomeDealBlock({super.key, required this.p, required this.data, required this.t, required this.ar});
  final Map<String, dynamic> p;
  final Map<String, dynamic> data;
  final DynTheme t;
  final bool ar;

  @override
  Widget build(BuildContext context) {
    final products = (data['products'] as List? ?? const []).cast<dynamic>();
    final visible = products.take(4).toList();
    final stickerText = ar
        ? (p['stickerAr']?.toString() ?? p['stickerEn']?.toString() ?? 'WELCOME DEAL')
        : (p['stickerEn']?.toString() ?? 'WELCOME DEAL');
    final stickerSub = ar
        ? (p['stickerSubAr']?.toString() ?? p['stickerSubEn']?.toString() ?? 'Free shipping')
        : (p['stickerSubEn']?.toString() ?? 'Free shipping');
    final bgColor = BlockEnvelope._hex(p['accent']) ?? const Color(0xFFE63946);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(.05), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 6, crossAxisSpacing: 6,
              children: List.generate(4, (i) {
                final url = i < visible.length
                    ? ((visible[i] as Map)['image'] as String?) ?? ''
                    : '';
                return ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: url.isNotEmpty
                      ? CachedNetworkImage(imageUrl: url, fit: BoxFit.cover)
                      : Container(color: const Color(0xFFF1EBDF)),
                );
              }),
            ),
          ),
          Container(
            color: bgColor,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(stickerText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 14, letterSpacing: 0.5,
                      )),
                  Text(stickerSub,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.92),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      )),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ─── DISCOUNT STRIP — horizontal of products with bold % badges ─────────────
// ─── DISCOUNT STRIP — v2.0.67 PRO: 6 variants ────────────────────────────────
//   compact   horizontal scroll of small cards (default)
//   hero      one big featured deal + 2 stacked side cards
//   mega      vertical list with image|name|price|save badge
//   grid_2col 2-column non-scrolling grid
//   ticker    auto-scrolling circular thumbnails
//   countdown each card has its own mini timer (uses flash_end_datetime if any)
class DiscountStripBlock extends StatelessWidget {
  const DiscountStripBlock({super.key, required this.p, required this.data, required this.t, required this.ar});
  final Map<String, dynamic> p;
  final Map<String, dynamic> data;
  final DynTheme t;
  final bool ar;

  @override
  Widget build(BuildContext context) {
    final items = (data['items'] as List? ?? data['products'] as List? ?? const []).cast<dynamic>();
    if (items.isEmpty) return const SizedBox.shrink();
    final variant = (p['variant'] as String?) ?? 'compact';
    Widget body;
    switch (variant) {
      case 'hero':      body = _hero(items); break;
      case 'mega':      body = _mega(items); break;
      case 'grid_2col': body = _grid2(items); break;
      case 'ticker':    body = _ticker(items); break;
      case 'countdown': body = _countdownRow(items); break;
      default:          body = _compactRow(items);
    }
    // v2.0.69 — no outer Stack (was crashing the page when used 2+ times).
    // Background is applied via a single Container wrapper, with inner
    // padding so the inner card row doesn't touch the colored edges.
    final bgStrip = _parseColor(p['bg_strip']);
    final hasBg = bgStrip != null && bgStrip != Colors.transparent;
    final inner = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DynSectionHeader(props: p, theme: t, ar: ar,
            fallbackEn: 'Hot deals', showMore: true,
            // discount strip → "more" opens the full discounts feed
            moreSort: 'discount'),
        Padding(padding: EdgeInsets.only(bottom: hasBg ? 10 : 0), child: body),
      ],
    );
    if (!hasBg) return inner;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: bgStrip,
        borderRadius: BorderRadius.circular(14),
      ),
      child: inner,
    );
  }

  // ─── compact (default) ─────────────────────────────────────────────────────
  // v2.1.45 — uses the adopted RICH ProductCard (stars + PI + ticker +
  // badges) instead of the bespoke discount card.
  Widget _compactRow(List items) {
    return SizedBox(
      height: 268,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => _richCard(items[i], width: 150),
      ),
    );
  }

  // v2.1.45 — shared rich-card builder with a graceful fallback to the
  // legacy discount card when the payload can't be parsed.
  Widget _richCard(dynamic raw, {double width = 150}) {
    final pp = (raw as Map).cast<String, dynamic>();
    try {
      final prod = UellowProductCard.fromJson(pp);
      // v2.1.56 — availability pill hidden in this block only per spec.
      return SizedBox(width: width,
          child: ProductCard(rich: true, product: prod, hideAvail: true));
    } catch (_) {
      return _DiscountCard(p: pp, props: p, t: t, ar: ar, width: width);
    }
  }

  // ─── hero (1 big + 2 small) ────────────────────────────────────────────────
  Widget _hero(List items) {
    final big = (items.first as Map).cast<String, dynamic>();
    final side = items.skip(1).take(2).map((e) => (e as Map).cast<String, dynamic>()).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SizedBox(
        height: 200,
        child: Row(children: [
          Expanded(flex: 14, child: _DiscountCard(p: big, props: this.p, t: t, ar: ar, fillHeight: true, big: true)),
          const SizedBox(width: 8),
          Expanded(flex: 10, child: Column(children: [
            for (final s in side) ...[
              Expanded(child: _DiscountHorizontalRow(p: s, props: this.p, t: t, ar: ar, small: true)),
              if (s != side.last) const SizedBox(height: 6),
            ],
            if (side.isEmpty) const SizedBox.shrink(),
          ])),
        ]),
      ),
    );
  }

  // ─── mega list (vertical) ──────────────────────────────────────────────────
  Widget _mega(List items) {
    final list = items.take(8).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(children: [
        for (int i = 0; i < list.length; i++) ...[
          _DiscountHorizontalRow(
            p: (list[i] as Map).cast<String, dynamic>(),
            props: this.p, t: t, ar: ar,
          ),
          if (i != list.length - 1) const SizedBox(height: 6),
        ],
      ]),
    );
  }

  // ─── 2-col grid ────────────────────────────────────────────────────────────
  Widget _grid2(List items) {
    final list = items.take(8).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          // v2.1.45 — rich-card aspect (matches the adopted card).
          crossAxisCount: 2, mainAxisSpacing: 8, crossAxisSpacing: 8,
          childAspectRatio: 0.585,
        ),
        itemCount: list.length,
        itemBuilder: (_, i) => _richCard(list[i]),
      ),
    );
  }

  // ─── ticker (auto-scrolling circular thumbs) ───────────────────────────────
  Widget _ticker(List items) {
    final speed = ((p['ticker_speed'] as num?)?.toInt() ?? 30).clamp(8, 240);
    return SizedBox(
      height: 80,
      child: _MarqueeTicker(
        speedSeconds: speed,
        children: items.map((e) => _DiscountTickerThumb(
          p: (e as Map).cast<String, dynamic>(),
          props: this.p, t: t,
        )).toList(),
      ),
    );
  }

  // ─── countdown row ─────────────────────────────────────────────────────────
  // v2.0.70 — match compact card sizing (was width 128 / height 184)
  Widget _countdownRow(List items) {
    // v2.1.48 — same adopted RICH ProductCard as the other layouts, with
    // the per-item countdown chip overlaid on the photo (top-start).
    final accent = _parseColor(p['accent']) ?? const Color(0xFFE63946);
    return SizedBox(
      height: 268,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final pp = (items[i] as Map).cast<String, dynamic>();
          final endIso = pp['flash_end_datetime']?.toString();
          // v2.1.53 — Positioned.fill: the bare Stack gave the card LOOSE
          // constraints so its bottom badge row (⚡عرض…) fell below the
          // row's clip and never showed. Now the card gets the same tight
          // box as the other layouts.
          return SizedBox(width: 150, child: Stack(children: [
            Positioned.fill(child: _richCard(pp, width: 150)),
            if (endIso != null && endIso.isNotEmpty)
              PositionedDirectional(top: 6, start: 6,
                  child: _MiniCountdown(endIso: endIso, accent: accent)),
          ]));
        },
      ),
    );
  }
}

// ───── helpers ─────────────────────────────────────────────────────────────
// v2.0.75 — pick the localized image URL from any item/props map.
// Looks at `<key>_ar` first when the app is in Arabic mode AND the
// override is set; otherwise falls back to the default key.
String pickLocalizedImage(Map item, bool ar, {String key = 'image_url'}) {
  final base = (item[key] as String?) ?? '';
  if (!ar) return base;
  final loc = (item['${key}_ar'] as String?) ?? '';
  return loc.isNotEmpty ? loc : base;
}

Color? _parseColor(dynamic v) {
  if (v is! String) return null;
  final s = v.trim();
  if (s.isEmpty || s == 'transparent') return Colors.transparent;
  final hex = s.startsWith('#') ? s.substring(1) : s;
  if (RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)) {
    return Color(int.parse('FF$hex', radix: 16));
  }
  return null;
}

double _num(dynamic v) => v is num ? v.toDouble() : 0.0;

int _discountPct(Map<String, dynamic> p) {
  final v = p['discount_pct'];
  if (v is num) return v.toInt();
  final priceVal = ((p['price'] as Map?)?.cast<String, dynamic>())?['amount'];
  final compareVal = ((p['compare_price'] as Map?)?.cast<String, dynamic>())?['amount'];
  if (priceVal is num && compareVal is num && compareVal > 0 && compareVal > priceVal) {
    return ((1 - priceVal / compareVal) * 100).round();
  }
  return 0;
}

String _saveText(Map<String, dynamic> p) {
  final priceMap = (p['price'] as Map?)?.cast<String, dynamic>();
  final compareMap = (p['compare_price'] as Map?)?.cast<String, dynamic>();
  if (priceMap == null || compareMap == null) return '';
  final priceVal = _num(priceMap['amount']);
  final compareVal = _num(compareMap['amount']);
  if (compareVal <= priceVal) return '';
  final save = compareVal - priceVal;
  final digits = (priceMap['digits'] is num) ? (priceMap['digits'] as num).toInt() : 3;
  return save.toStringAsFixed(digits);
}

String _currency(Map<String, dynamic> p) {
  final priceMap = (p['price'] as Map?)?.cast<String, dynamic>();
  return priceMap?['currency']?.toString() ?? 'KWD';
}

// v2.0.71 — format a {amount, currency, symbol, digits} map into a readable
// string. v2.0.73 — localize the currency symbol (KD → د.ك for Arabic)
// and add `withSymbol:false` so the strikethrough-compare row can be just
// the bare number.
String _fmtPrice(dynamic raw, {bool ar = false, bool withSymbol = true}) {
  if (raw == null) return '';
  if (raw is num) return raw.toStringAsFixed(3);
  if (raw is String) return raw;
  if (raw is Map) {
    final m = raw.cast<String, dynamic>();
    final amt = m['amount'];
    if (amt is! num) {
      final disp = m['display']?.toString();
      return disp ?? '';
    }
    final digits = (m['digits'] is num) ? (m['digits'] as num).toInt() : 3;
    final numStr = amt.toStringAsFixed(digits);
    if (!withSymbol) return numStr;
    final rawSym = m['symbol']?.toString() ?? '';
    final code = m['currency']?.toString() ?? '';
    final sym = ar ? UellowMoney.localizedSymbol(code, rawSym, 'ar') : rawSym;
    return '$numStr $sym'.trim();
  }
  return raw.toString();
}

BoxDecoration _cardDecoration(Map<String, dynamic> props, {required double radius}) {
  final style = (props['card_style'] as String?) ?? 'flat';
  switch (style) {
    case 'outlined':
      return BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: const Color(0xFFE5DBC0), width: 1),
      );
    case 'gradient':
      return BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.white, Color(0xFFFFF6E0)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(radius),
      );
    case 'glass':
      return BoxDecoration(
        color: Colors.white.withOpacity(0.78),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Colors.white.withOpacity(0.6), width: 1),
      );
    case 'flat':
    default:
      return BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
      );
  }
}

// ───── card (compact / countdown / hero-big / grid-cell) ─────────────────────
class _DiscountCard extends StatelessWidget {
  const _DiscountCard({
    required this.p,
    required this.props,
    required this.t,
    required this.ar,
    this.width,
    this.fillHeight = false,
    this.fillWidth = false,
    this.showCountdown = false,
    this.big = false,
  });
  final Map<String, dynamic> p;
  final Map<String, dynamic> props;
  final DynTheme t;
  final bool ar;
  final double? width;
  final bool fillHeight, fillWidth, showCountdown, big;

  @override
  Widget build(BuildContext context) {
    final img = (p['image'] as String?) ?? '';
    // v2.0.71/73 — localized currency in Arabic; compare price renders as
    // a bare number to save space alongside an inline discount-% badge.
    final price = _fmtPrice(p['price'], ar: ar);
    final compare = _fmtPrice(p['compare_price'], ar: ar, withSymbol: false);
    final discount = _discountPct(p);
    final accent = _parseColor(props['accent']) ?? const Color(0xFFE63946);
    final radius = ((props['card_radius'] as num?)?.toDouble() ?? 10).clamp(0, 32).toDouble();
    final showBadge = props['show_discount_badge'] != false;
    final showSave = props['show_save_amount'] != false;
    final showCompare = props['show_compare_price'] != false;
    final showBrand = props['show_brand'] == true;
    final showUrg = props['show_urgency'] == true;
    final urgTh = (props['urgency_threshold'] as num?)?.toInt() ?? 30;
    final saveAmt = _saveText(p);
    final brand = ((p['vendor'] as Map?)?.cast<String, dynamic>())?['name']?.toString();
    final endIso = p['flash_end_datetime']?.toString();
    final nameMap = (p['name'] as Map?)?.cast<String, dynamic>();
    final productName = ar ? (nameMap?['ar']?.toString() ?? '') : (nameMap?['en']?.toString() ?? '');

    // v2.0.70 — full info-section redesign. Hierarchy:
    //   1. brand + rating chip row (small, secondary)
    //   2. product name (2 lines, bold, primary)
    //   3. BIG price + small strikethrough compare on the same row
    //   4. full-width "Save X KD" gradient pill
    final rating = (p['rating'] as Map?)?.cast<String, dynamic>();
    final ratingAvg = (rating?['avg'] as num?)?.toDouble() ?? 0.0;
    final ratingCount = (rating?['count'] as num?)?.toInt() ?? 0;
    final cardW = width ?? (big ? 200.0 : 140.0);

    return GestureDetector(
      onTap: () {
        final id = (p['id'] as num?)?.toInt();
        if (id != null && id > 0) UellowRouter.goProduct(context, id);
      },
      child: Container(
        width: fillWidth ? null : cardW,
        decoration: _cardDecoration(props, radius: radius),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          // ─── IMAGE ────────────────────────────────────────────────────────
          Stack(children: [
            AspectRatio(
              aspectRatio: 1,
              child: img.isNotEmpty
                  ? CachedNetworkImage(imageUrl: img, fit: BoxFit.cover)
                  : Container(color: const Color(0xFFF1EBDF)),
            ),
            // v2.0.73 — on-image -X% badge removed; the discount now lives
            // inline next to the price (per user request to reduce clutter).
            if (showUrg && discount >= urgTh)
              Positioned(top: 6, right: 6, child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.65),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(ar ? '🔥 تنفد بسرعة' : '🔥 Selling fast',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 9, height: 1.0)),
              )),
            if (showCountdown && endIso != null && endIso.isNotEmpty)
              Positioned(bottom: 6, right: 6, child: _MiniCountdown(endIso: endIso, accent: accent)),
          ]),

          // ─── INFO ─────────────────────────────────────────────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(9, big ? 9 : 8, 9, big ? 10 : 9),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              // Row 1: brand + rating
              if ((showBrand && brand != null && brand.isNotEmpty) || ratingAvg > 0)
                Padding(padding: const EdgeInsets.only(bottom: 4), child: Row(children: [
                  if (showBrand && brand != null && brand.isNotEmpty)
                    Flexible(child: Text(brand.toUpperCase(),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: t.dark.withOpacity(0.55),
                          fontWeight: FontWeight.w800, fontSize: 8.5,
                          letterSpacing: 0.5, height: 1.0,
                        ))),
                  if ((showBrand && brand != null && brand.isNotEmpty) && ratingAvg > 0)
                    Padding(padding: const EdgeInsets.symmetric(horizontal: 5), child: Container(
                      width: 2, height: 2,
                      decoration: BoxDecoration(
                        color: t.dark.withOpacity(0.3), shape: BoxShape.circle,
                      ),
                    )),
                  if (ratingAvg > 0) ...[
                    const Icon(Icons.star_rounded, size: 11, color: Color(0xFFFFC107)),
                    const SizedBox(width: 2),
                    Text(ratingAvg.toStringAsFixed(1),
                        style: TextStyle(
                          color: t.dark, fontWeight: FontWeight.w900,
                          fontSize: 9.5, height: 1.0,
                        )),
                    if (ratingCount > 0) Padding(
                      padding: const EdgeInsets.only(left: 2),
                      child: Text('($ratingCount)',
                          style: TextStyle(
                            color: t.dark.withOpacity(0.5), fontWeight: FontWeight.w600,
                            fontSize: 9, height: 1.0,
                          )),
                    ),
                  ],
                ])),

              // Row 2: product name (always 2 lines high so card heights match)
              if (productName.isNotEmpty)
                SizedBox(
                  height: big ? 34 : 30,
                  child: Text(
                    productName,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: t.dark, fontWeight: FontWeight.w700,
                      fontSize: big ? 13 : 11.5, height: 1.25,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
              SizedBox(height: big ? 6 : 5),

              // v2.0.73 — Price row: BIG price + inline -X% pill + bare-number
              // strikethrough compare with BLACK strike. Smaller fonts so all
              // three elements fit comfortably on the same line.
              Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                Flexible(child: Text(price,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: t.dark, fontWeight: FontWeight.w900,
                      fontSize: big ? 15 : 13, height: 1.0,
                      letterSpacing: -0.3,
                    ))),
                if (showBadge && discount > 0) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text('-$discount%',
                        style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w900,
                          fontSize: 9, height: 1.0,
                        )),
                  ),
                ],
                if (showCompare && compare.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Flexible(child: Text(compare,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.black87, fontSize: 9.5,
                        decoration: TextDecoration.lineThrough,
                        decorationColor: Colors.black87,
                        fontWeight: FontWeight.w600, height: 1.0,
                      ))),
                ],
              ]),

              // Row 4: Save badge (full-width pill)
              if (showSave && saveAmt.isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 6), child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFEAFBF1), Color(0xFFD0F0DD)],
                      begin: Alignment.centerLeft, end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: const Color(0xFF1F8A40).withOpacity(0.25), width: 0.7),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.discount_outlined, size: 11, color: Color(0xFF1F8A40)),
                    const SizedBox(width: 4),
                    Flexible(child: Text(
                      ar ? 'وفر $saveAmt ${_currency(p)}' : 'Save $saveAmt ${_currency(p)}',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF166534), fontWeight: FontWeight.w900,
                        fontSize: 10, height: 1.0, letterSpacing: -0.1,
                      ),
                    )),
                  ]),
                )),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ───── horizontal row card (mega list + hero side cards) ─────────────────────
class _DiscountHorizontalRow extends StatelessWidget {
  const _DiscountHorizontalRow({
    required this.p, required this.props, required this.t, required this.ar, this.small = false,
  });
  final Map<String, dynamic> p;
  final Map<String, dynamic> props;
  final DynTheme t;
  final bool ar;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final img = (p['image'] as String?) ?? '';
    // v2.0.71 — use _fmtPrice (resolver returns amount/symbol/digits, not display).
    final price = _fmtPrice(p['price']);
    final compare = _fmtPrice(p['compare_price']);
    final discount = _discountPct(p);
    final accent = _parseColor(props['accent']) ?? const Color(0xFFE63946);
    final radius = ((props['card_radius'] as num?)?.toDouble() ?? 10).clamp(0, 32).toDouble();
    final showBadge = props['show_discount_badge'] != false;
    final showSave = props['show_save_amount'] != false;
    final showCompare = props['show_compare_price'] != false;
    final saveAmt = _saveText(p);
    final nameMap = (p['name'] as Map?)?.cast<String, dynamic>();
    final name = ar ? (nameMap?['ar']?.toString() ?? '') : (nameMap?['en']?.toString() ?? '');
    final imgSize = small ? 56.0 : 72.0;

    return GestureDetector(
      onTap: () {
        final id = (p['id'] as num?)?.toInt();
        if (id != null && id > 0) UellowRouter.goProduct(context, id);
      },
      child: Container(
        decoration: _cardDecoration(props, radius: radius),
        clipBehavior: Clip.antiAlias,
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            width: imgSize, height: imgSize,
            child: img.isNotEmpty
                ? CachedNetworkImage(imageUrl: img, fit: BoxFit.cover)
                : Container(color: const Color(0xFFF1EBDF)),
          ),
          Expanded(child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: small ? 5 : 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              if (name.isNotEmpty)
                Text(name, maxLines: small ? 1 : 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.dark, fontWeight: FontWeight.w800, fontSize: small ? 10.5 : 11.5)),
              SizedBox(height: small ? 2 : 4),
              Row(children: [
                Text(price, style: TextStyle(color: t.dark, fontWeight: FontWeight.w900, fontSize: small ? 11 : 13)),
                if (showCompare && compare.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Flexible(child: Text(compare, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: t.dark.withOpacity(0.45),
                          fontSize: small ? 9 : 10.5,
                          decoration: TextDecoration.lineThrough,
                          fontWeight: FontWeight.w600))),
                ],
                if (showBadge && discount > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(4)),
                    child: Text('-$discount%',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 9.5)),
                  ),
                ],
              ]),
              if (showSave && saveAmt.isNotEmpty && !small)
                Padding(padding: const EdgeInsets.only(top: 3), child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFFE6F7EF), Color(0xFFD4F0DD)]),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFF1F8A40).withOpacity(0.18), width: 0.6),
                  ),
                  child: Text(
                    ar ? 'وفر $saveAmt ${_currency(p)}' : 'Save $saveAmt ${_currency(p)}',
                    style: const TextStyle(color: Color(0xFF1F8A40), fontWeight: FontWeight.w900, fontSize: 10),
                  ),
                )),
            ]),
          )),
        ]),
      ),
    );
  }
}

// ───── ticker thumbnail (circular) ───────────────────────────────────────────
class _DiscountTickerThumb extends StatelessWidget {
  const _DiscountTickerThumb({required this.p, required this.props, required this.t});
  final Map<String, dynamic> p;
  final Map<String, dynamic> props;
  final DynTheme t;

  @override
  Widget build(BuildContext context) {
    final img = (p['image'] as String?) ?? '';
    final discount = _discountPct(p);
    final accent = _parseColor(props['accent']) ?? const Color(0xFFE63946);
    final showBadge = props['show_discount_badge'] != false;
    return GestureDetector(
      onTap: () {
        final id = (p['id'] as num?)?.toInt();
        if (id != null && id > 0) UellowRouter.goProduct(context, id);
      },
      child: SizedBox(width: 64, child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 52, height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle, color: Colors.white,
            border: Border.all(color: accent, width: 2),
          ),
          clipBehavior: Clip.antiAlias,
          child: img.isNotEmpty
              ? CachedNetworkImage(imageUrl: img, fit: BoxFit.cover)
              : const ColoredBox(color: Color(0xFFF1EBDF)),
        ),
        const SizedBox(height: 3),
        if (showBadge && discount > 0)
          Text('-$discount%',
              style: TextStyle(color: accent, fontWeight: FontWeight.w900, fontSize: 10)),
      ])),
    );
  }
}

// ───── auto-scrolling ticker (loops smoothly) ───────────────────────────────
class _MarqueeTicker extends StatefulWidget {
  const _MarqueeTicker({required this.children, required this.speedSeconds});
  final List<Widget> children;
  final int speedSeconds;
  @override
  State<_MarqueeTicker> createState() => _MarqueeTickerState();
}

class _MarqueeTickerState extends State<_MarqueeTicker> with SingleTickerProviderStateMixin {
  late final ScrollController _ctrl;
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = ScrollController();
    _anim = AnimationController(vsync: this, duration: Duration(seconds: widget.speedSeconds))..repeat();
    _anim.addListener(_tick);
  }

  void _tick() {
    if (!_ctrl.hasClients) return;
    final max = _ctrl.position.maxScrollExtent;
    if (max <= 0) return;
    final pos = (_anim.value * max) % max;
    _ctrl.jumpTo(pos);
  }

  @override
  void dispose() {
    _anim.removeListener(_tick);
    _anim.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Duplicate the list so scrolling loops seamlessly.
    final loop = [...widget.children, ...widget.children];
    return ListView.separated(
      controller: _ctrl,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: loop.length,
      separatorBuilder: (_, __) => const SizedBox(width: 10),
      itemBuilder: (_, i) => loop[i],
    );
  }
}

// ───── mini countdown for per-card timer ────────────────────────────────────
class _MiniCountdown extends StatefulWidget {
  const _MiniCountdown({required this.endIso, required this.accent});
  final String endIso;
  final Color accent;
  @override
  State<_MiniCountdown> createState() => _MiniCountdownState();
}

class _MiniCountdownState extends State<_MiniCountdown> {
  DateTime? _end;
  Duration _left = Duration.zero;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    try { _end = DateTime.parse(widget.endIso); } catch (_) { _end = null; }
    _recalc();
    // v2.0.69 — Timer.periodic that we explicitly cancel in dispose.
    // (was Stream.periodic — leaked across rebuilds and contributed to
    // the multi-Discount-Strip page-render crash.)
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _recalc();
      setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _recalc() {
    if (_end == null) { _left = Duration.zero; return; }
    final diff = _end!.difference(DateTime.now());
    _left = diff.isNegative ? Duration.zero : diff;
  }

  @override
  Widget build(BuildContext context) {
    if (_left == Duration.zero) return const SizedBox.shrink();
    final h = _left.inHours.toString().padLeft(2, '0');
    final m = (_left.inMinutes % 60).toString().padLeft(2, '0');
    final s = (_left.inSeconds % 60).toString().padLeft(2, '0');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text('$h:$m:$s',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10)),
    );
  }
}

// ─── MINI CATEGORY CARDS — 2x2 grid of colored category cards ────────────────
class MiniCategoryCardsBlock extends StatelessWidget {
  const MiniCategoryCardsBlock({super.key, required this.p, required this.data, required this.t, required this.ar});
  final Map<String, dynamic> p;
  final Map<String, dynamic> data;
  final DynTheme t;
  final bool ar;

  @override
  Widget build(BuildContext context) {
    final cards = (p['cards'] as List? ?? const []).cast<dynamic>();
    if (cards.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (p['show_title'] != false)
          DynSectionHeader(props: p, theme: t, ar: ar, fallbackEn: 'Browse'),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 8, crossAxisSpacing: 8,
          childAspectRatio: 1.6,
          children: cards.map((c) {
            final cc = (c as Map).cast<String, dynamic>();
            return _MiniCatCard(c: cc, t: t, ar: ar);
          }).toList(),
        ),
      ]),
    );
  }
}

class _MiniCatCard extends StatelessWidget {
  const _MiniCatCard({required this.c, required this.t, required this.ar});
  final Map<String, dynamic> c;
  final DynTheme t;
  final bool ar;

  @override
  Widget build(BuildContext context) {
    final bg = BlockEnvelope._hex(c['color']) ?? const Color(0xFFFFE9D6);
    final title = ar
        ? (c['titleAr']?.toString() ?? c['titleEn']?.toString() ?? '')
        : (c['titleEn']?.toString() ?? '');
    final sub = ar
        ? (c['subtitleAr']?.toString() ?? c['subtitleEn']?.toString() ?? '')
        : (c['subtitleEn']?.toString() ?? '');
    final img = pickLocalizedImage(c, ar);
    return GestureDetector(
      onTap: () => _openLink(context, (c['link'] as Map?)?.cast<String, dynamic>()),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 9, 6, 6),
        decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w900, color: t.dark, fontSize: 13,
                )),
            if (sub.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(sub,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5, color: t.dark.withOpacity(0.65),
                    fontWeight: FontWeight.w600,
                  )),
            ],
          ]),
          if (img.isNotEmpty)
            Positioned(
              right: -6, bottom: -6,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 70, height: 56,
                  child: CachedNetworkImage(imageUrl: img, fit: BoxFit.cover),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

// ─── TAB FILTERS — pill row (For You / New In / Deals / Bestsellers) ────────
class PillFilterBlock extends StatelessWidget {
  const PillFilterBlock({super.key, required this.p, required this.t, required this.ar});
  final Map<String, dynamic> p;
  final DynTheme t;
  final bool ar;

  @override
  Widget build(BuildContext context) {
    final pills = (p['pills'] as List? ?? const []).cast<dynamic>();
    if (pills.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 38,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        itemCount: pills.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final pp = (pills[i] as Map).cast<String, dynamic>();
          final label = ar
              ? (pp['labelAr']?.toString() ?? pp['labelEn']?.toString() ?? '')
              : (pp['labelEn']?.toString() ?? '');
          final active = i == 0;
          return GestureDetector(
            onTap: () => _openLink(context, (pp['link'] as Map?)?.cast<String, dynamic>()),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: active ? t.dark : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: active ? t.dark : t.dark.withOpacity(0.12),
                  width: 1,
                ),
              ),
              child: Text(label,
                  style: TextStyle(
                    color: active ? Colors.white : t.dark,
                    fontWeight: FontWeight.w800, fontSize: 12,
                  )),
            ),
          );
        },
      ),
    );
  }
}

// ─── Helper duplicated here to avoid circular import of `_openLink` ─────────
// v2.1.40 — public wrapper: other screens (e.g. the flash block) route
// builder link maps {type, value} through the same logic.
void openBlockLink(BuildContext c, Map<String, dynamic>? link) =>
    _openLink(c, link);

void _openLink(BuildContext c, Map<String, dynamic>? link) {
  if (link == null) return;
  final type = link['type']?.toString();
  final value = link['value']?.toString();
  if (type == null || value == null) return;
  switch (type) {
    case 'product':
      final id = int.tryParse(value) ?? 0;
      if (id > 0) UellowRouter.goProduct(c, id);
      break;
    case 'category':
      final id = int.tryParse(value) ?? 0;
      if (id > 0) UellowRouter.goCollection(c, id);
      break;
    case 'screen':
      const map = {
        'shop': Routes.category, 'cart': Routes.cart, 'wishlist': Routes.wishlist,
        'account': Routes.account, 'orders': Routes.orders, 'beena': Routes.beena,
        'loyalty': Routes.loyalty, 'wallet': Routes.wallet, 'coupons': Routes.coupons,
        'notifications': Routes.notifications, 'search': Routes.search, 'home': Routes.home,
      };
      final r = map[value];
      if (r != null) Navigator.of(c).pushNamed(r);
      break;
    case 'page':
      UellowRouter.goDynPage(c, value);
      break;
  }
}

// ─── EXPLORE MORE v2.0.37 — full discovery suite ─────────────────────────────
//
// Top-tier e-commerce discovery block:
//   • Category chip filter strip (server-computed top 6 categories)
//   • Sort bar (Best / Newest / Price ↑↓ / Top rated)
//   • Skeleton shimmer while loading
//   • "Why you see this" + trending stat captions
//   • Smart badges per product (🔥 Hot · ✨ New · 🚚 Free ship · 💯 Best deal)
//   • Sponsored slots (designer's picks) every Nth item with "AD" tag
//   • Optional Deal-of-the-Hour pinned banner with countdown
//   • Optional live activity ticker (anonymized "Sara from Salmiya bought…")
//   • Variants: standard / compact / hero
//   • Bilingual (EN/AR)

class ExploreMoreBlock extends StatefulWidget {
  const ExploreMoreBlock({super.key, required this.p, required this.data, required this.t, required this.ar});
  final Map<String, dynamic> p;
  final Map<String, dynamic> data;
  final DynTheme t;
  final bool ar;
  @override
  State<ExploreMoreBlock> createState() => _ExploreMoreBlockState();
}

class _ExploreMoreBlockState extends State<ExploreMoreBlock> {
  final List<UellowProductCard> _items = [];
  final List<Map<String, dynamic>> _itemMeta = [];  // badges + sponsored flag per item
  List<UellowProductCard> _sponsored = [];
  List<Map<String, dynamic>> _sponsoredMeta = [];
  List<Map<String, dynamic>> _chips = [];
  int? _activeChipId;
  late int _seed;
  int _page = 2;
  int _autoRounds = 0;
  bool _loading = false;
  bool _hasMore = true;
  late String _sort;
  Timer? _activityTimer;
  int _activityIdx = 0;

  // Hard-coded plausible activity ticker entries (privacy-safe — no real names
  // exposed). Could fetch from server in v2.0.38.
  static const _activityFeed = [
    {'en':'Sara from Salmiya bought 2 minutes ago', 'ar':'سارة من السالمية اشترت قبل دقيقتين'},
    {'en':'Ahmed in Kuwait City just added to cart', 'ar':'أحمد في مدينة الكويت أضافه للسلة الآن'},
    {'en':'Layla from Hawalli is viewing this',     'ar':'ليلى من حولي تشاهد هذا المنتج'},
    {'en':'5 people bought this in the last hour',  'ar':'٥ أشخاص اشتروا هذا في الساعة الأخيرة'},
    {'en':'Trending #1 in Phones today',            'ar':'الأكثر رواجاً #1 في الهواتف اليوم'},
  ];

  int  get _perPage     => (widget.p['per_page']   as num?)?.toInt() ?? 12;
  int  get _autoLimit   => (widget.p['auto_pages'] as num?)?.toInt() ?? 3;
  int  get _sponsoredEvery => (widget.p['sponsored_every'] as num?)?.toInt() ?? 5;
  int  get _columns     {
    final c = widget.p['columns'];
    if (c is num) return c.toInt();
    return int.tryParse(c?.toString() ?? '2') ?? 2;
  }
  String get _variant   => (widget.p['variant'] as String?) ?? 'standard';
  bool get _showShuffle   => widget.p['show_shuffle']      != false;
  bool get _showEndMarker => widget.p['show_end_marker']   != false;
  bool get _showChips     => widget.p['show_chips']        != false;
  bool get _showSortBar   => widget.p['show_sort_bar']     != false;
  bool get _showBadges    => widget.p['show_badges']       != false;
  bool get _showSkeleton  => widget.p['show_skeleton']     != false;
  bool get _showWhy       => widget.p['show_why_caption']  != false;
  bool get _showTrending  => widget.p['show_trending_stat']!= false;
  bool get _showActivity  => widget.p['show_live_activity']== true;

  @override
  void initState() {
    super.initState();
    _seed = (widget.data['seed'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch & 0x7FFFFFFF;
    _sort = (widget.p['sort'] as String?) ?? 'best_match';
    _chips = ((widget.data['category_chips'] as List?) ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>()).toList();

    // Seed initial items from resolver
    final initial = (widget.data['items'] as List? ?? const []);
    for (final raw in initial) {
      try {
        final m = (raw as Map).cast<String, dynamic>();
        _items.add(UellowProductCard.fromJson(m));
        _itemMeta.add({'badges': m['badges'] ?? const []});
      } catch (_) {/* skip malformed */}
    }

    // Sponsored items
    final sp = (widget.data['sponsored'] as List? ?? const []);
    for (final raw in sp) {
      try {
        final m = (raw as Map).cast<String, dynamic>();
        _sponsored.add(UellowProductCard.fromJson(m));
        _sponsoredMeta.add({'badges': m['badges'] ?? const [], 'sponsored': true});
      } catch (_) {}
    }

    _hasMore = (widget.data['has_more'] as bool?) ?? _items.length >= _perPage;
    _page = (widget.data['next_page'] as num?)?.toInt() ?? 2;

    if (_showActivity) {
      _activityTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (!mounted) return;
        setState(() => _activityIdx = (_activityIdx + 1) % _activityFeed.length);
      });
    }
  }

  @override
  void dispose() {
    _activityTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final api = UellowApi.instance;
      final params = <String, String>{
        'seed': _seed.toString(),
        'page': _page.toString(),
        'per_page': _perPage.toString(),
        'sort': _sort,
        if (_activeChipId != null) 'category_id': _activeChipId.toString(),
      };
      final url = Uri.parse('${api.baseUrl}/api/mobile/v2/products/explore')
          .replace(queryParameters: params);
      final res = await http.get(url, headers: {'Accept': 'application/json', 'X-Lang': api.lang})
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) {
        setState(() { _loading = false; _hasMore = false; });
        return;
      }
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final items = (j['data'] as List? ?? const []);
      final meta = (j['meta'] as Map?)?.cast<String, dynamic>() ?? {};
      if (!mounted) return;
      setState(() {
        for (final raw in items) {
          try {
            final m = (raw as Map).cast<String, dynamic>();
            _items.add(UellowProductCard.fromJson(m));
            _itemMeta.add({'badges': m['badges'] ?? const []});
          } catch (_) {}
        }
        _page++;
        _autoRounds++;
        _hasMore = (meta['has_next'] as bool?) ?? items.isNotEmpty;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _hasMore = false; });
    }
  }

  void _shuffle() {
    setState(() {
      _items.clear(); _itemMeta.clear();
      _seed = DateTime.now().millisecondsSinceEpoch & 0x7FFFFFFF;
      _page = 1; _autoRounds = 0; _hasMore = true; _loading = false;
    });
    _loadMore();
  }

  void _changeChip(int? newId) {
    if (_activeChipId == newId) return;
    setState(() {
      _activeChipId = newId;
      _items.clear(); _itemMeta.clear();
      _page = 1; _autoRounds = 0; _hasMore = true; _loading = false;
    });
    _loadMore();
  }

  void _changeSort(String newSort) {
    if (_sort == newSort) return;
    setState(() {
      _sort = newSort;
      _items.clear(); _itemMeta.clear();
      _page = 1; _autoRounds = 0; _hasMore = true; _loading = false;
    });
    _loadMore();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final ar = widget.ar;
    final title = (ar
        ? (widget.p['titleAr'] ?? widget.p['titleEn'])
        : (widget.p['titleEn'] ?? widget.p['titleAr']))?.toString() ?? 'Explore More';
    final sub = (ar
        ? (widget.p['subAr'] ?? widget.p['subEn'])
        : (widget.p['subEn'] ?? widget.p['subAr']))?.toString() ?? '';
    final whyMap = (widget.data['why_caption'] as Map?)?.cast<String, dynamic>();
    final trendingMap = (widget.data['trending_stat'] as Map?)?.cast<String, dynamic>();
    final showLoadMoreBtn = _hasMore && !_loading && _autoRounds >= _autoLimit;

    return Stack(children: [
      Padding(
        // v2.1.36 — no bottom padding while the Load-more button shows;
        // the button is the natural end of the block.
        padding: EdgeInsets.fromLTRB(10, 4, 10, showLoadMoreBtn ? 0 : 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // ─── Header row ────────────────────────────────────────────────────
          if ((widget.p['show_title'] != false) && title.isNotEmpty)
            // v2.0.76 — Arabic titles were ellipsis'd because the row split
            // space between title + sub + Shuffle. Now the title gets
            // Expanded (max width), the subtitle drops in AR / sits as a
            // smaller line beside in EN, and the shuffle button is icon-only
            // when the language is Arabic so it doesn't eat horizontal room.
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
              child: Row(children: [
                Icon(Icons.explore_outlined, size: 17, color: t.dark),
                const SizedBox(width: 6),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: t.dark, fontSize: 14.5,
                            fontWeight: FontWeight.w900, letterSpacing: -0.2)),
                    if (sub.isNotEmpty)
                      Padding(padding: const EdgeInsets.only(top: 1),
                        child: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: t.dark.withOpacity(0.55), fontSize: 11,
                              fontWeight: FontWeight.w600)),
                      ),
                  ],
                )),
                if (_showShuffle) ...[
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: _shuffle, borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: widget.ar ? 8 : 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: UellowColors.yellowSoft,
                        border: Border.all(color: UellowColors.yellow),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.shuffle, size: 13, color: UellowColors.darkBrown),
                        const SizedBox(width: 4),
                        Text(widget.ar ? 'تبديل' : 'Shuffle',
                            style: const TextStyle(
                                color: UellowColors.darkBrown, fontSize: 10.5,
                                fontWeight: FontWeight.w800)),
                      ]),
                    ),
                  ),
                ],
              ]),
            ),
          // ─── Trending stat + Why caption ───────────────────────────────────
          if (_showTrending && trendingMap != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 4),
              child: Text((ar ? trendingMap['ar'] : trendingMap['en'])?.toString() ?? '',
                  style: const TextStyle(color: Color(0xFFE63946), fontSize: 11.5, fontWeight: FontWeight.w800)),
            ),
          if (_showWhy && whyMap != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
              child: Row(children: [
                const Text('💬 ', style: TextStyle(fontSize: 11)),
                Flexible(
                  child: Text((ar ? whyMap['ar'] : whyMap['en'])?.toString() ?? '',
                      style: TextStyle(color: t.dark.withOpacity(0.6), fontSize: 11.5, fontStyle: FontStyle.italic)),
                ),
              ]),
            ),
          // ─── Category chips ────────────────────────────────────────────────
          if (_showChips && _chips.isNotEmpty)
            _ChipsBar(
              chips: _chips, active: _activeChipId, dark: t.dark,
              ar: ar, onTap: _changeChip,
            ),
          // ─── Sort bar ──────────────────────────────────────────────────────
          if (_showSortBar)
            _SortBar(active: _sort, dark: t.dark, ar: ar, onTap: _changeSort),
          // ─── Skeleton OR grid ──────────────────────────────────────────────
          if (_items.isEmpty && _loading && _showSkeleton)
            _SkeletonGrid(columns: _columns)
          else if (_items.isEmpty && !_loading)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Center(child: Text(ar ? 'لا توجد منتجات' : 'No products yet',
                  style: TextStyle(color: t.dark.withOpacity(0.6)))),
            )
          else
            _renderGrid(),
          // ─── Load more / spinner / end marker ──────────────────────────────
          if (_loading && _items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(18),
              child: Center(child: SizedBox(
                width: 22, height: 22,
                child: CircularProgressIndicator(color: t.dark, strokeWidth: 2.5),
              )),
            ),
          if (showLoadMoreBtn)
            Padding(
              padding: const EdgeInsets.fromLTRB(40, 10, 40, 0),
              child: ElevatedButton.icon(
                onPressed: _loadMore,
                icon: const Icon(Icons.arrow_downward, size: 16),
                label: Text(ar ? 'تحميل المزيد' : 'Load more',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: UellowColors.yellowSoft,
                  foregroundColor: UellowColors.darkBrown,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          if (_showEndMarker && !_hasMore && _items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Center(child: Text(ar ? '— نهاية النتائج —' : '— end of feed —',
                  style: TextStyle(color: t.dark.withOpacity(0.5), fontSize: 11.5))),
            ),
        ]),
      ),
      // ─── Live activity ticker (overlay above content) ───────────────────────
      if (_showActivity && _activityFeed.isNotEmpty)
        Positioned(
          left: 12, right: 12, bottom: 10,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: Container(
              key: ValueKey(_activityIdx),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0E5E2E),
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2))],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Text('🎉', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    (ar ? _activityFeed[_activityIdx]['ar'] : _activityFeed[_activityIdx]['en'])!,
                    style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ]),
            ),
          ),
        ),
    ]);
  }

  Widget _renderGrid() {
    // Hero variant: first item is full-width, the rest in normal grid.
    final hero = _variant == 'hero';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (hero && _items.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: _ProductTile(
              product: _items[0],
              meta: _itemMeta.isNotEmpty ? _itemMeta[0] : const {},
              showBadges: _showBadges,
              isHero: true,
            ),
          ),
        ),
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _columns,
          crossAxisSpacing: 8, mainAxisSpacing: 8,
          childAspectRatio: _columns == 2 ? 0.585 : 0.52,   // v2.1.33 rich
        ),
        itemCount: _gridLength(),
        itemBuilder: (_, i) {
          // Auto-load trigger
          if (_autoRounds < _autoLimit && _hasMore && !_loading
              && i >= _gridLength() - (_columns * 2)) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _loadMore());
          }
          // Resolve which underlying item this slot represents (with sponsored insertions)
          final res = _resolveSlot(i);
          if (res == null) return const SizedBox.shrink();
          return _ProductTile(
            product: res.product, meta: res.meta,
            showBadges: _showBadges, isHero: false,
          );
        },
      ),
    ]);
  }

  // Returns the grid item count, factoring in sponsored insertions.
  int _gridLength() {
    final base = _variant == 'hero' && _items.isNotEmpty ? _items.length - 1 : _items.length;
    if (_sponsoredEvery <= 0 || _sponsored.isEmpty) return base;
    final inserts = base ~/ _sponsoredEvery;
    return base + inserts;
  }

  _SlotResult? _resolveSlot(int i) {
    // Hero offset: index 0 was the hero, so shift the rest by 1.
    final heroOffset = (_variant == 'hero' && _items.isNotEmpty) ? 1 : 0;
    if (_sponsoredEvery <= 0 || _sponsored.isEmpty) {
      final idx = i + heroOffset;
      if (idx < _items.length) {
        return _SlotResult(_items[idx], _itemMeta.length > idx ? _itemMeta[idx] : const {});
      }
      return null;
    }
    // Every `_sponsoredEvery`-th slot is sponsored
    int orgIdx = 0, slot = 0, spCursor = 0;
    while (slot <= i) {
      slot++;
      if (slot % _sponsoredEvery == 0 && spCursor < _sponsored.length) {
        if (slot - 1 == i) {
          return _SlotResult(_sponsored[spCursor], _sponsoredMeta[spCursor]);
        }
        spCursor++;
      } else {
        if (slot - 1 == i) {
          final realIdx = orgIdx + heroOffset;
          if (realIdx >= _items.length) return null;
          return _SlotResult(
              _items[realIdx],
              _itemMeta.length > realIdx ? _itemMeta[realIdx] : const {});
        }
        orgIdx++;
      }
    }
    return null;
  }
}

class _SlotResult {
  _SlotResult(this.product, this.meta);
  final UellowProductCard product;
  final Map<String, dynamic> meta;
}

// ─── Tile with badges + sponsored overlay ───────────────────────────────────
class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product, required this.meta,
      required this.showBadges, required this.isHero});
  final UellowProductCard product;
  final Map<String, dynamic> meta;
  final bool showBadges;
  final bool isHero;

  @override
  Widget build(BuildContext context) {
    final badges = ((meta['badges'] as List?) ?? const []).cast<dynamic>();
    final isSponsored = meta['sponsored'] == true;
    return Stack(children: [
      ProductCard(rich: true, product: product),
      if (showBadges && badges.isNotEmpty)
        Positioned(
          top: 4, right: 4,
          child: Wrap(spacing: 3, runSpacing: 3, children: [
            for (final raw in badges.take(2))
              if (raw is Map) Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0,1))],
                ),
                child: Text(
                  (raw['label_en']?.toString() ?? '').split(' ').first,  // emoji only for compactness
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
                ),
              ),
          ]),
        ),
      if (isSponsored)
        Positioned(
          top: 4, left: 4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF6E4AB0),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(UellowApi.instance.lang == 'ar' ? 'إعلان' : 'AD',
                style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900)),
          ),
        ),
    ]);
  }
}

// ─── Chips bar (category filter) ────────────────────────────────────────────
class _ChipsBar extends StatelessWidget {
  const _ChipsBar({required this.chips, required this.active,
    required this.dark, required this.ar, required this.onTap});
  final List<Map<String, dynamic>> chips;
  final int? active;
  final Color dark;
  final bool ar;
  final void Function(int? id) onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
        physics: const ClampingScrollPhysics(),
        children: [
          _chip(label: ar ? 'الكل' : 'All', selected: active == null, onTap: () => onTap(null)),
          for (final c in chips)
            _chip(
              label: c['name']?.toString() ?? '',
              selected: active == (c['id'] as num?)?.toInt(),
              onTap: () => onTap((c['id'] as num?)?.toInt()),
            ),
        ],
      ),
    );
  }

  Widget _chip({required String label, required bool selected, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.only(right: 5),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? dark : Colors.white,
            border: Border.all(color: selected ? dark : const Color(0xFFE5DCC2)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(label, style: TextStyle(
              color: selected ? Colors.white : dark,
              fontSize: 11.5, fontWeight: FontWeight.w800)),
        ),
      ),
    );
  }
}

// ─── Sort bar ───────────────────────────────────────────────────────────────
class _SortBar extends StatelessWidget {
  const _SortBar({required this.active, required this.dark, required this.ar, required this.onTap});
  final String active;
  final Color dark;
  final bool ar;
  final void Function(String key) onTap;

  @override
  Widget build(BuildContext context) {
    final options = [
      ('best_match', ar ? '✨ الأنسب' : '✨ Best'),
      ('newest',     ar ? '🆕 الأحدث' : '🆕 New'),
      ('price_asc',  ar ? '💰 السعر ↑' : '💰 Price ↑'),
      ('price_desc', ar ? '💎 السعر ↓' : '💎 Price ↓'),
      ('top_rated',  ar ? '⭐ تقييم' : '⭐ Rated'),
    ];
    return SizedBox(
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(6, 2, 6, 6),
        physics: const ClampingScrollPhysics(),
        children: [
          for (final o in options)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: InkWell(
                onTap: () => onTap(o.$1),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: active == o.$1 ? UellowColors.yellowSoft : Colors.white,
                    border: Border.all(color: active == o.$1 ? UellowColors.yellow : const Color(0xFFE5DCC2)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(o.$2,
                    style: TextStyle(
                      color: active == o.$1 ? const Color(0xFF7A4A00) : dark,
                      fontSize: 10.5, fontWeight: FontWeight.w800)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Skeleton shimmer placeholder grid ──────────────────────────────────────
class _SkeletonGrid extends StatefulWidget {
  const _SkeletonGrid({required this.columns});
  final int columns;
  @override
  State<_SkeletonGrid> createState() => _SkeletonGridState();
}

class _SkeletonGridState extends State<_SkeletonGrid>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: widget.columns,
        crossAxisSpacing: 8, mainAxisSpacing: 8,
        childAspectRatio: widget.columns == 2 ? 0.58 : 0.52,
      ),
      itemCount: widget.columns * 3,
      itemBuilder: (_, __) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final t = (math.sin(_c.value * math.pi * 2) + 1) / 2;
          final c = Color.lerp(const Color(0xFFEEE6D6), const Color(0xFFF8F1E1), t)!;
          return Container(
            decoration: BoxDecoration(
              color: c,
              borderRadius: BorderRadius.circular(10),
            ),
          );
        },
      ),
    );
  }
}

// =============================================================================
// v2.0.38 — Slider + 5 pro design blocks
// =============================================================================

// ─── SLIDER — multi-slide hero with image/video/text + overlay ──────────────
class SliderBlock extends StatefulWidget {
  const SliderBlock({super.key, required this.p, required this.t, required this.ar});
  final Map<String, dynamic> p;
  final DynTheme t;
  final bool ar;
  @override
  State<SliderBlock> createState() => _SliderBlockState();
}

class _SliderBlockState extends State<SliderBlock> {
  // v2.0.61 — Pro slider state
  late PageController _ctrl;
  Timer? _autoTimer;
  int _index = 0;
  bool _paused = false;
  // Cached filtered slides — drops those outside their schedule / target lang
  // / country. Recomputed when widget.p changes.
  late List<Map<String, dynamic>> _visible;

  String get _layout => (widget.p['layout'] as String?) ?? 'full';
  String get _transition => (widget.p['transition'] as String?) ?? 'slide';
  double get _gap => ((widget.p['gap'] as num?)?.toDouble() ?? 10);

  @override
  void initState() {
    super.initState();
    _filterSlides();
    final viewport = (_layout == 'peek' || _layout == 'coverflow') ? 0.82
                    : (_layout == 'card') ? 0.92 : 1.0;
    _ctrl = PageController(viewportFraction: viewport);
    _maybeStartAuto();
  }

  @override
  void didUpdateWidget(SliderBlock old) {
    super.didUpdateWidget(old);
    _filterSlides();
  }

  void _filterSlides() {
    final raw = (widget.p['slides'] as List?) ?? const [];
    final now = DateTime.now();
    _visible = raw.where((s) {
      if (s is! Map) return false;
      final m = s.cast<String, dynamic>();
      // Schedule window
      final start = DateTime.tryParse((m['schedule_start'] as String?) ?? '');
      if (start != null && now.isBefore(start)) return false;
      final end = DateTime.tryParse((m['schedule_end'] as String?) ?? '');
      if (end != null && now.isAfter(end)) return false;
      // Lang targeting
      final langCsv = (m['target_langs'] as String?) ?? '';
      if (langCsv.trim().isNotEmpty) {
        final wanted = langCsv.toLowerCase().split(',').map((s) => s.trim());
        final cur = widget.ar ? 'ar' : 'en';
        if (!wanted.contains(cur)) return false;
      }
      return true;
    }).cast<Map<String, dynamic>>().toList();
    // A/B variant: stable random pick — keep first occurrence of each
    // variant key (simple impl; production would sticky-pick per user).
    // For now we just show all that survived the filters.
  }

  void _maybeStartAuto() {
    _autoTimer?.cancel();
    if (widget.p['autoplay'] == false || _visible.length < 2) return;
    final secs = ((widget.p['duration'] as num?)?.toInt() ?? 4).clamp(2, 20);
    _autoTimer = Timer.periodic(Duration(seconds: secs), (_) {
      if (!mounted || !_ctrl.hasClients || _paused) return;
      final next = (widget.p['loop'] == false && _index + 1 >= _visible.length)
          ? _index
          : (_index + 1) % _visible.length;
      _ctrl.animateToPage(next,
          duration: const Duration(milliseconds: 450), curve: Curves.easeInOut);
    });
  }

  @override
  void dispose() { _autoTimer?.cancel(); _ctrl.dispose(); super.dispose(); }

  double _ratio() {
    switch ((widget.p['aspect'] as String?) ?? '16_9') {
      case '2_1':  return 2;
      case '4_3':  return 4 / 3;
      case '1_1':  return 1;
      case '3_4':  return 3 / 4;
      case 'full': return 16 / 6;
      default:     return 16 / 9;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_visible.isEmpty) return const SizedBox.shrink();
    final radius = ((widget.p['radius'] as num?)?.toDouble() ?? 12);
    final fullBleed = widget.p['full_bleed'] == true;
    final ar = widget.ar;
    final accent = _hexColor(widget.p['accent_color'], const Color(0xFFF5C320));
    final pauseOnTouch = widget.p['pause_on_touch'] != false;
    final dotsPos = (widget.p['dots_position'] as String?) ?? 'bottom';
    final outerPadH = fullBleed ? 0.0 : 12.0;
    // Wrap in Listener to pause autoplay while user touches.
    return Listener(
      onPointerDown: pauseOnTouch ? (_) => _paused = true : null,
      onPointerUp:   pauseOnTouch ? (_) => _paused = false : null,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: outerPadH),
        child: AspectRatio(
          aspectRatio: _ratio(),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: Stack(children: [
              if (dotsPos == 'top' && widget.p['show_dots'] != false && _visible.length > 1)
                const SizedBox.shrink(),
              PageView.builder(
                controller: _ctrl,
                itemCount: _visible.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) {
                  final s = _visible[i];
                  final eager = i == 0 && widget.p['eager_first'] != false;
                  return _Slide(slide: s, ar: ar, eager: eager,
                      transition: _transition, current: i == _index,
                      kenBurnsGlobal: widget.p['kenburns_default'] == true,
                      onTap: () => _openLink(context, (s['link'] as Map?)?.cast<String, dynamic>()),
                      onTap2: () => _openLink(context, (s['cta2_link'] as Map?)?.cast<String, dynamic>()),
                      gap: (_layout == 'peek' || _layout == 'card') ? _gap : 0);
                },
              ),
              if (widget.p['show_arrows'] == true && _visible.length > 1) ...[
                Positioned(left: 8, top: 0, bottom: 0,
                    child: Align(alignment: Alignment.center, child: _arrow(false))),
                Positioned(right: 8, top: 0, bottom: 0,
                    child: Align(alignment: Alignment.center, child: _arrow(true))),
              ],
              if (widget.p['show_dots'] != false && _visible.length > 1)
                Positioned(
                  left: 0, right: 0,
                  bottom: dotsPos == 'top' ? null : 10,
                  top: dotsPos == 'top' ? 10 : null,
                  child: Center(child: _Indicator(
                    style: (widget.p['dots_style'] as String?) ?? 'dots',
                    count: _visible.length, index: _index, accent: accent,
                    duration: ((widget.p['duration'] as num?)?.toDouble() ?? 4),
                    autoplay: widget.p['autoplay'] != false,
                  )),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _arrow(bool next) {
    final style = (widget.p['arrows_style'] as String?) ?? 'round';
    final iconSize = style == 'minimal' ? 24.0 : 20.0;
    final boxSize = style == 'minimal' ? 28.0 : 32.0;
    final bg = style == 'minimal'
        ? Colors.transparent
        : Colors.black.withValues(alpha: 0.4);
    final shape = style == 'square' ? BoxShape.rectangle : BoxShape.circle;
    return InkWell(
      onTap: () {
        final target = next ? _index + 1 : _index - 1;
        if (target < 0 || target >= _visible.length) return;
        _ctrl.animateToPage(target,
            duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      },
      child: Container(
        width: boxSize, height: boxSize,
        decoration: BoxDecoration(
          color: bg, shape: shape,
          borderRadius: shape == BoxShape.rectangle ? BorderRadius.circular(8) : null,
        ),
        child: Icon(next ? Icons.chevron_right : Icons.chevron_left,
            color: style == 'minimal' ? Colors.white.withValues(alpha: 0.7) : Colors.white,
            size: iconSize),
      ),
    );
  }
}

// ─── Indicator (dots / bars / numbers / fraction / progress) ──────────
class _Indicator extends StatelessWidget {
  const _Indicator({required this.style, required this.count,
      required this.index, required this.accent, required this.duration,
      required this.autoplay});
  final String style;
  final int count;
  final int index;
  final Color accent;
  final double duration;
  final bool autoplay;

  @override
  Widget build(BuildContext context) {
    switch (style) {
      case 'numbers':
        return _pill(child: Text('${index + 1} / $count',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900,
              fontSize: 11)));
      case 'fraction':
        return _pill(child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('${index + 1}', style: TextStyle(
              color: accent, fontWeight: FontWeight.w900, fontSize: 14)),
          const Text('/', style: TextStyle(color: Colors.white70, fontSize: 11)),
          Text('$count', style: const TextStyle(
              color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 11)),
        ]));
      case 'progress':
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: autoplay ? 1.0 : (index + 1) / count),
              duration: Duration(seconds: autoplay ? duration.round() : 1),
              curve: Curves.linear,
              builder: (_, v, __) => LinearProgressIndicator(
                  value: v,
                  backgroundColor: Colors.white.withValues(alpha: 0.3),
                  valueColor: AlwaysStoppedAnimation(accent),
                  minHeight: 3),
            ),
          ),
        );
      case 'bars':
        return Row(mainAxisSize: MainAxisSize.min, children: [
          for (int i = 0; i < count; i++) AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: i == index ? 24 : 12, height: 4,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: i == index ? accent : Colors.white.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2)),
          ),
        ]);
      default: // dots
        return Row(mainAxisSize: MainAxisSize.min, children: [
          for (int i = 0; i < count; i++) AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: i == index ? 18 : 6, height: 6,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: i == index ? accent : Colors.white.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(3)),
          ),
        ]);
    }
  }

  Widget _pill({required Widget child}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12)),
    child: child,
  );
}

class _Slide extends StatelessWidget {
  const _Slide({required this.slide, required this.ar, required this.onTap,
      this.onTap2, this.eager = false, this.transition = 'slide',
      this.current = false, this.kenBurnsGlobal = false, this.gap = 0});
  final Map<String, dynamic> slide;
  final bool ar;
  final VoidCallback onTap;
  final VoidCallback? onTap2;
  final bool eager;
  final String transition;
  final bool current;
  final bool kenBurnsGlobal;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final kind = (slide['kind'] as String?) ?? 'image';
    final img = pickLocalizedImage(slide, ar);
    final overlayKind = (slide['overlay_kind'] as String?) ?? 'solid';
    final c1 = _hexColor(slide['overlay_color'], const Color(0xFF000000));
    final c2 = _hexColor(slide['overlay_color2'], c1);
    final overlayOpacity = ((slide['overlay_opacity'] as num?)?.toInt() ?? 30).clamp(0, 100) / 100.0;
    final textColor = _hexColor(slide['text_color'], Colors.white);
    final ctaColor = _hexColor(slide['cta_color'], textColor);
    final position = (slide['text_position'] as String?) ?? 'mc';
    final textAlignRaw = (slide['text_align'] as String?) ?? 'center';
    final align = (textAlignRaw == 'left' || textAlignRaw == 'start')
        ? CrossAxisAlignment.start
        : (textAlignRaw == 'right' || textAlignRaw == 'end')
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.center;
    final textAlign = (textAlignRaw == 'left' || textAlignRaw == 'start')
        ? TextAlign.start
        : (textAlignRaw == 'right' || textAlignRaw == 'end')
            ? TextAlign.end
            : TextAlign.center;
    final maxWidthPct = ((slide['text_max_width'] as num?)?.toDouble() ?? 80) / 100;
    final eyebrow = (ar ? slide['eyebrowAr'] : slide['eyebrowEn'])?.toString() ?? '';
    final title = (ar ? slide['titleAr'] : slide['titleEn'])?.toString() ?? '';
    final sub   = (ar ? slide['subtitleAr'] : slide['subtitleEn'])?.toString() ?? '';
    final cta   = (ar ? slide['ctaAr']      : slide['ctaEn'])?.toString() ?? '';
    final cta2  = (ar ? slide['cta2Ar']     : slide['cta2En'])?.toString() ?? '';
    final ctaShape = (slide['cta_shape'] as String?) ?? 'pill';
    final titleSize = (slide['title_size'] as String?) ?? 'md';
    final titleFontSize = {'sm': 16.0, 'md': 22.0, 'lg': 28.0, 'xl': 34.0}[titleSize] ?? 22.0;
    final badgeText = (ar ? slide['badge_textAr'] : slide['badge_textEn'])?.toString() ?? '';
    final badgeColor = _hexColor(slide['badge_color'], const Color(0xFFE63946));
    final badgePos = (slide['badge_position'] as String?) ?? 'tl';
    final kenBurnsSetting = (slide['kenburns'] as String?) ?? 'auto';
    final kenBurns = kenBurnsSetting == 'on'
        || (kenBurnsSetting == 'auto' && kenBurnsGlobal);

    // 9-anchor → Alignment
    final anchor = {
      'tl': Alignment.topLeft,     'tc': Alignment.topCenter,    'tr': Alignment.topRight,
      'ml': Alignment.centerLeft,  'mc': Alignment.center,       'mr': Alignment.centerRight,
      'bl': Alignment.bottomLeft,  'bc': Alignment.bottomCenter, 'br': Alignment.bottomRight,
    }[position] ?? Alignment.center;

    Widget media() {
      if (kind == 'product' || kind == 'countdown' || kind == 'text') {
        return Container(decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFF412402), Color(0xFFF5C320)],
                begin: Alignment.topLeft, end: Alignment.bottomRight)));
      }
      if (img.isEmpty) {
        return Container(decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFF412402), Color(0xFFF5C320)],
                begin: Alignment.topLeft, end: Alignment.bottomRight)));
      }
      return CachedNetworkImage(imageUrl: img, fit: BoxFit.cover,
          // eager-load first slide via no placeholder — LCP win
          placeholder: eager ? null : (_, __) => Container(color: const Color(0xFFEEE6D6)));
    }

    Widget overlay() {
      if (overlayOpacity == 0) return const SizedBox.shrink();
      switch (overlayKind) {
        case 'gradient_v':
          return Container(decoration: BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [c1.withValues(alpha: overlayOpacity),
                           c2.withValues(alpha: overlayOpacity)])));
        case 'gradient_h':
          return Container(decoration: BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.centerLeft, end: Alignment.centerRight,
                  colors: [c1.withValues(alpha: overlayOpacity),
                           c2.withValues(alpha: overlayOpacity)])));
        case 'gradient_diag':
          return Container(decoration: BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [c1.withValues(alpha: overlayOpacity),
                           c2.withValues(alpha: overlayOpacity)])));
        case 'vignette':
          return Container(decoration: BoxDecoration(
              gradient: RadialGradient(radius: 1.0,
                  colors: [Colors.transparent,
                           c1.withValues(alpha: overlayOpacity)])));
        default:
          return Container(color: c1.withValues(alpha: overlayOpacity));
      }
    }

    Widget ctaButton(String label, VoidCallback action, {bool secondary = false}) {
      if (label.isEmpty) return const SizedBox.shrink();
      final bg = secondary ? Colors.transparent : ctaColor;
      final fg = secondary ? ctaColor : const Color(0xFF412402);
      switch (ctaShape) {
        case 'rect':
          return GestureDetector(onTap: action, child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
              decoration: BoxDecoration(color: bg,
                  borderRadius: BorderRadius.circular(6),
                  border: secondary ? Border.all(color: ctaColor, width: 1.5) : null),
              child: Text(label, style: TextStyle(color: fg,
                  fontWeight: FontWeight.w900, fontSize: 13))));
        case 'ghost':
          return GestureDetector(onTap: action, child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: ctaColor, width: 1.5)),
              child: Text(label, style: TextStyle(color: ctaColor,
                  fontWeight: FontWeight.w900, fontSize: 13))));
        case 'underline':
          return GestureDetector(onTap: action, child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(label, style: TextStyle(
                  color: ctaColor, fontWeight: FontWeight.w900, fontSize: 13,
                  decoration: TextDecoration.underline,
                  decorationColor: ctaColor, decorationThickness: 2))));
        default: // pill
          return GestureDetector(onTap: action, child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
              decoration: BoxDecoration(color: bg,
                  borderRadius: BorderRadius.circular(20),
                  border: secondary ? Border.all(color: ctaColor, width: 1.5) : null),
              child: Text(label, style: TextStyle(color: fg,
                  fontWeight: FontWeight.w900, fontSize: 13))));
      }
    }

    Widget badge() {
      if (badgeText.isEmpty) return const SizedBox.shrink();
      final p = badgePos == 'tl' ? const EdgeInsets.only(top: 10, left: 10)
              : badgePos == 'tr' ? const EdgeInsets.only(top: 10, right: 10)
              : badgePos == 'bl' ? const EdgeInsets.only(bottom: 10, left: 10)
              : const EdgeInsets.only(bottom: 10, right: 10);
      return Align(
        alignment: badgePos == 'tl' ? Alignment.topLeft
                : badgePos == 'tr' ? Alignment.topRight
                : badgePos == 'bl' ? Alignment.bottomLeft
                : Alignment.bottomRight,
        child: Padding(padding: p, child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: badgeColor,
                borderRadius: BorderRadius.circular(4)),
            child: Text(badgeText, style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w900,
                fontSize: 10, letterSpacing: 0.6)))),
      );
    }

    // Countdown slide content
    Widget countdownContent() {
      if (kind != 'countdown') return const SizedBox.shrink();
      final iso = (slide['countdown_to'] as String?) ?? '';
      final end = DateTime.tryParse(iso);
      if (end == null) return const SizedBox.shrink();
      return TweenAnimationBuilder<int>(
        duration: const Duration(seconds: 1),
        tween: IntTween(begin: 0, end: 1),
        builder: (_, __, ___) {
          final diff = end.difference(DateTime.now());
          if (diff.isNegative) return Text(
              ar ? 'انتهى' : 'ENDED',
              style: TextStyle(color: textColor, fontSize: 24,
                  fontWeight: FontWeight.w900));
          final h = diff.inHours.toString().padLeft(2, '0');
          final m = (diff.inMinutes % 60).toString().padLeft(2, '0');
          final s = (diff.inSeconds % 60).toString().padLeft(2, '0');
          return Text('$h : $m : $s', style: TextStyle(
              color: textColor, fontSize: titleFontSize,
              fontWeight: FontWeight.w900, fontFeatures: const [
                FontFeature.tabularFigures()
              ]));
        },
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: gap / 2),
        child: Stack(fit: StackFit.expand, children: [
          // Media + optional Ken Burns slow zoom
          kenBurns
            ? _KenBurns(active: current, child: media())
            : media(),
          if (kind == 'video')
            const Center(child: Icon(Icons.play_circle_fill,
                color: Colors.white70, size: 56)),
          overlay(),
          // Anchored content
          Align(
            alignment: anchor,
            child: FractionallySizedBox(
              widthFactor: maxWidthPct,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: align,
                  children: [
                    if (eyebrow.isNotEmpty) Text(eyebrow,
                        textAlign: textAlign,
                        style: TextStyle(color: ctaColor,
                            fontWeight: FontWeight.w900, fontSize: 11,
                            letterSpacing: 1.2)),
                    if (eyebrow.isNotEmpty) const SizedBox(height: 6),
                    if (kind == 'countdown') countdownContent()
                    else if (title.isNotEmpty) Text(title,
                        textAlign: textAlign,
                        style: TextStyle(color: textColor,
                            fontSize: titleFontSize,
                            fontWeight: FontWeight.w900, height: 1.1)),
                    if (sub.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(sub, textAlign: textAlign,
                          style: TextStyle(
                              color: textColor.withValues(alpha: 0.92),
                              fontSize: 13, fontWeight: FontWeight.w500)),
                    ],
                    if (cta.isNotEmpty || cta2.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(spacing: 10, runSpacing: 6,
                        alignment: textAlignRaw == 'start'
                            ? WrapAlignment.start
                            : textAlignRaw == 'end'
                                ? WrapAlignment.end
                                : WrapAlignment.center,
                        children: [
                          if (cta.isNotEmpty) ctaButton(cta, onTap),
                          if (cta2.isNotEmpty)
                            ctaButton(cta2, onTap2 ?? onTap, secondary: true),
                        ]),
                    ],
                  ],
                ),
              ),
            ),
          ),
          badge(),
        ]),
      ),
    );
  }
}

// ─── Ken Burns: slow zoom + pan for the slide background ─────────────
class _KenBurns extends StatefulWidget {
  const _KenBurns({required this.child, required this.active});
  final Widget child;
  final bool active;
  @override
  State<_KenBurns> createState() => _KenBurnsState();
}

class _KenBurnsState extends State<_KenBurns>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this,
        duration: const Duration(seconds: 12));
    if (widget.active) _c.repeat(reverse: true);
  }
  @override
  void didUpdateWidget(_KenBurns old) {
    super.didUpdateWidget(old);
    if (widget.active && !_c.isAnimating) _c.repeat(reverse: true);
    if (!widget.active && _c.isAnimating) _c.stop();
  }
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (_, child) {
        final v = _c.value;
        return Transform.scale(
          scale: 1.0 + v * 0.12,
          child: Transform.translate(
            offset: Offset(-v * 8, -v * 6),
            child: child,
          ),
        );
      },
    );
  }
}


// ─── BESTSELLERS — premium podium + ranked list (v2.1.45) ───────────────────
// Theme-able (gold / dark / clean), #1 on a raised gold podium with a
// crown, #2 silver, #3 bronze, then a ranked list. All tappable.
class BestsellersBlock extends StatelessWidget {
  const BestsellersBlock({super.key, required this.p, required this.data,
      required this.t, required this.ar});
  final Map<String, dynamic> p;
  final Map<String, dynamic> data;
  final DynTheme t;
  final bool ar;

  ({Color bg1, Color bg2, Color ink, Color sub, Color card, Color border})
      _theme(String name) => switch (name) {
    'dark' => (bg1: const Color(0xFF131129), bg2: const Color(0xFF1E1B3C),
               ink: Colors.white, sub: const Color(0xB3FFFFFF),
               card: const Color(0x14FFFFFF), border: const Color(0x22FFFFFF)),
    'clean' => (bg1: Colors.white, bg2: Colors.white,
               ink: const Color(0xFF1F1206), sub: const Color(0xFF8A7B5E),
               card: const Color(0xFFFAFAFA), border: const Color(0xFFEFEAD9)),
    _ => (bg1: const Color(0xFFFFF9E8), bg2: const Color(0xFFFFFDF6),
               ink: const Color(0xFF4A2E04), sub: const Color(0xFF9A7B33),
               card: Colors.white, border: const Color(0xFFF0E2BB)),
  };

  static const _medal = ['🥇', '🥈', '🥉'];
  static const _ringColors = [
    [Color(0xFFFFE082), Color(0xFFD4AF37)],   // gold
    [Color(0xFFE0E0E0), Color(0xFF9E9E9E)],   // silver
    [Color(0xFFE0B187), Color(0xFFA0683A)],   // bronze
  ];

  @override
  Widget build(BuildContext context) {
    final raw = ((data['items'] as List?) ?? const [])
        .cast<dynamic>().map((e) => (e as Map).cast<String, dynamic>());
    final items = <UellowProductCard>[];
    for (final m in raw) {
      try { items.add(UellowProductCard.fromJson(m)); } catch (_) {}
    }
    if (items.isEmpty) return const SizedBox.shrink();
    final th = _theme((p['bs_theme'] as String?) ?? 'gold');
    final showPodium = p['show_podium'] != false && items.length >= 3;
    final showSold = p['show_sold'] != false;
    final listCount = ((p['bs_list_count'] as num?)?.toInt() ?? 7)
        .clamp(0, 20);
    final title = ar
        ? ((p['titleAr'] ?? p['titleEn'])?.toString() ?? 'الأكثر مبيعاً')
        : ((p['titleEn'] ?? p['titleAr'])?.toString() ?? 'Bestsellers');
    final podium = showPodium ? items.take(3).toList() : <UellowProductCard>[];
    final rest = items.skip(showPodium ? 3 : 0).take(listCount).toList();

    // v2.1.60 — NEW default look: «Champions Arena» — a premium panel in
    // the New-User-block spirit: the #1 champion as a big hero card with
    // a crown, the rest racing beside it with rank medals. Products are
    // front and center. The old podium stays as bs_style='podium'.
    final style = (p['bs_style'] as String?) ?? 'arena';
    if (style == 'arena') {
      return _arena(context, items, th, title, showSold, listCount);
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter,
            end: Alignment.bottomCenter, colors: [th.bg1, th.bg2]),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: th.border),
        boxShadow: const [BoxShadow(color: Color(0x14000000),
            blurRadius: 12, offset: Offset(0, 4))],
      ),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── header ──
        Row(children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFFFFE082), Color(0xFFD4AF37)]),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(
                  color: const Color(0xFFD4AF37).withValues(alpha: 0.45),
                  blurRadius: 8)],
            ),
            child: const Text('🏆', style: TextStyle(fontSize: 15)),
          ),
          const SizedBox(width: 8),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900,
                    color: th.ink, letterSpacing: 0.2)),
            Text(ar ? 'ترتيب حقيقي حسب المبيعات' : 'Real sales ranking',
                style: TextStyle(fontSize: 9.5, color: th.sub,
                    fontWeight: FontWeight.w600)),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF16A34A).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 6, height: 6, decoration: const BoxDecoration(
                  color: Color(0xFF16A34A), shape: BoxShape.circle)),
              const SizedBox(width: 4),
              Text(ar ? 'محدّث يومياً' : 'Updated daily',
                  style: const TextStyle(fontSize: 8.5,
                      fontWeight: FontWeight.w800, color: Color(0xFF15803D))),
            ]),
          ),
        ]),
        if (podium.isNotEmpty) ...[
          const SizedBox(height: 14),
          // ── podium: 2 · 1 · 3 ──
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(child: _podiumSpot(context, podium[1], 1, th,
                showSold, avatar: 64, stand: 26)),
            Expanded(child: _podiumSpot(context, podium[0], 0, th,
                showSold, avatar: 84, stand: 42, crowned: true)),
            Expanded(child: _podiumSpot(context, podium[2], 2, th,
                showSold, avatar: 64, stand: 16)),
          ]),
        ],
        if (rest.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (var i = 0; i < rest.length; i++)
            _rankRow(context, rest[i], (showPodium ? 4 : 1) + i, th, showSold),
        ],
      ]),
    );
  }

  Widget _podiumSpot(BuildContext c, UellowProductCard prod, int medalIdx,
      dynamic th, bool showSold,
      {required double avatar, required double stand, bool crowned = false}) {
    final lang = UellowApi.instance.lang;
    final ring = _ringColors[medalIdx];
    return GestureDetector(
      onTap: () => UellowRouter.goProduct(c, prod.id),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (crowned)
          const Padding(padding: EdgeInsets.only(bottom: 2),
              child: Text('👑', style: TextStyle(fontSize: 18))),
        Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
          Container(
            width: avatar + 8, height: avatar + 8,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: ring),
              boxShadow: [BoxShadow(
                  color: ring[1].withValues(alpha: 0.45),
                  blurRadius: crowned ? 14 : 8, offset: const Offset(0, 3))],
            ),
            child: ClipOval(child: CachedNetworkImage(
              imageUrl: prod.image, fit: BoxFit.cover,
              placeholder: (_, __) =>
                  const ColoredBox(color: Color(0xFFEFEFEF)),
              errorWidget: (_, __, ___) =>
                  const ColoredBox(color: Color(0xFFEFEFEF)),
            )),
          ),
          Positioned(bottom: -7,
              child: Text(_medal[medalIdx],
                  style: const TextStyle(fontSize: 17))),
        ]),
        const SizedBox(height: 10),
        Text(prod.name.current(lang),
            maxLines: 1, overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700,
                color: th.ink)),
        const SizedBox(height: 2),
        Text('${prod.price.amount.toStringAsFixed(3)} '
             '${prod.price.displaySymbol(lang)}',
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900,
                color: th.ink)),
        if (showSold && prod.soldCount > 0) Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
            decoration: BoxDecoration(
              color: const Color(0xFFD4AF37).withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
                UellowApi.instance.lang == 'ar'
                    ? '🔥 باع ${_fmtSold(prod.soldCount)}+'
                    : '🔥 ${_fmtSold(prod.soldCount)}+ sold',
                style: const TextStyle(fontSize: 8,
                    fontWeight: FontWeight.w800, color: Color(0xFF8B6508))),
          ),
        ),
        const SizedBox(height: 6),
        // podium stand
        Container(
          height: stand,
          margin: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [ring[0].withValues(alpha: 0.85),
                       ring[1].withValues(alpha: 0.55)],
            ),
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(6)),
          ),
          alignment: Alignment.center,
          child: Text('${medalIdx + 1}', style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w900,
              color: Colors.white)),
        ),
      ]),
    );
  }

  Widget _rankRow(BuildContext c, UellowProductCard prod, int rank,
      dynamic th, bool showSold) {
    final lang = UellowApi.instance.lang;
    return GestureDetector(
      onTap: () => UellowRouter.goProduct(c, prod.id),
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: th.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: th.border),
        ),
        child: Row(children: [
          SizedBox(width: 26, child: Text('#$rank',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900,
                  color: th.sub, fontStyle: FontStyle.italic))),
          const SizedBox(width: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: CachedNetworkImage(
              imageUrl: prod.image, width: 44, height: 44, fit: BoxFit.cover,
              placeholder: (_, __) => const SizedBox(width: 44, height: 44),
              errorWidget: (_, __, ___) =>
                  const SizedBox(width: 44, height: 44),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(prod.name.current(lang),
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700,
                    color: th.ink)),
            const SizedBox(height: 2),
            Row(children: [
              const Icon(Icons.star_rounded,
                  size: 11, color: Color(0xFFFFC107)),
              Text(' ${prod.rating.avg.toStringAsFixed(1)}',
                  style: TextStyle(fontSize: 9.5,
                      fontWeight: FontWeight.w800, color: th.ink)),
              if (showSold && prod.soldCount > 0)
                Text(UellowApi.instance.lang == 'ar'
                        ? '  ·  باع ${_fmtSold(prod.soldCount)}+'
                        : '  ·  ${_fmtSold(prod.soldCount)}+ sold',
                    style: TextStyle(fontSize: 9, color: th.sub,
                        fontWeight: FontWeight.w600)),
            ]),
          ])),
          Text('${prod.price.amount.toStringAsFixed(3)} '
               '${prod.price.displaySymbol(lang)}',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900,
                  color: th.ink)),
          Icon(UellowApi.instance.lang == 'ar'
                  ? Icons.chevron_left : Icons.chevron_right,
              size: 17, color: th.sub),
        ]),
      ),
    );
  }

  String _fmtSold(int n) => n >= 1000
      ? '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}K' : '$n';
  // ── Champions Arena (v2.1.60) ──────────────────────────────────────
  Widget _arena(BuildContext context, List<UellowProductCard> items,
      ({Color bg1, Color bg2, Color ink, Color sub, Color card,
        Color border}) th,
      String title, bool showSold, int listCount) {
    final champ = items.first;
    final rest = items.skip(1).take(listCount + 2).toList();
    final sym = ar ? 'د.ك' : 'KD';
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF2C1801), Color(0xFF5A3A0E), Color(0xFF2C1801)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x33FFD75E)),
        boxShadow: const [BoxShadow(color: Color(0x33000000),
            blurRadius: 12, offset: Offset(0, 5))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // header: crown title + live chip + view more
        Row(children: [
          const Text('👑', style: TextStyle(fontSize: 17)),
          const SizedBox(width: 6),
          Expanded(child: Text(title, maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFFFFD75E),
                  fontSize: 15, fontWeight: FontWeight.w900,
                  letterSpacing: -0.2))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0x26FFFFFF),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 6, height: 6, decoration: const BoxDecoration(
                  color: Color(0xFF7BE495), shape: BoxShape.circle)),
              const SizedBox(width: 4),
              Text(ar ? 'مبيعات حية' : 'LIVE sales',
                  style: const TextStyle(color: Colors.white70,
                      fontSize: 9, fontWeight: FontWeight.w800)),
            ]),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () {
              final link = (p['link'] as Map?)?.cast<String, dynamic>();
              if (link != null && (link['type'] ?? 'none') != 'none') {
                openBlockLink(context, link);
              } else {
                // v2.1.61 — opens the full RANKED bestsellers ladder.
                Navigator.pushNamed(context, '/bestsellers');
              }
            },
            child: Text(ar ? 'عرض المزيد ←' : 'View more →',
                style: const TextStyle(color: Color(0xFFFFD75E),
                    fontSize: 10.5, fontWeight: FontWeight.w800)),
          ),
        ]),
        const SizedBox(height: 10),
        SizedBox(height: 216, child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // ── #1 champion hero ──
          SizedBox(width: 158, child: GestureDetector(
            onTap: () => UellowRouter.goProduct(context, champ.id),
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFFD75E),
                    width: 2),
                boxShadow: const [BoxShadow(color: Color(0x59D4AF37),
                    blurRadius: 12)],
              ),
              child: Stack(fit: StackFit.expand, children: [
                CachedNetworkImage(imageUrl: champ.image,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) =>
                        const ColoredBox(color: Color(0xFF3A2A10))),
                // crown chip
                PositionedDirectional(top: 8, start: 8, child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [
                        Color(0xFFFFE082), Color(0xFFD4AF37)]),
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: const [BoxShadow(
                        color: Color(0x66000000), blurRadius: 4)],
                  ),
                  child: Text(ar ? '👑 الأول' : '👑 #1',
                      style: const TextStyle(fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF4A2E04))),
                )),
                // bottom veil: name + price + sold
                Positioned(left: 0, right: 0, bottom: 0, child: Container(
                  padding: const EdgeInsets.fromLTRB(9, 18, 9, 9),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xE6000000)],
                    ),
                  ),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(champ.name.current(UellowApi.instance.lang),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white,
                            fontSize: 11, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Row(children: [
                      Text('${champ.price.amount.toStringAsFixed(3)} $sym',
                          style: const TextStyle(
                              color: Color(0xFFFFD75E), fontSize: 13,
                              fontWeight: FontWeight.w900)),
                      const Spacer(),
                      if (showSold && champ.soldCount > 0)
                        Text(ar ? '🔥 ${champ.soldCount} بيعت'
                                : '🔥 ${champ.soldCount} sold',
                            style: const TextStyle(color: Colors.white70,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800)),
                    ]),
                  ]),
                )),
              ]),
            ),
          )),
          const SizedBox(width: 8),
          // ── the chasing pack ──
          Expanded(child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: rest.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => _arenaCard(context, rest[i], i + 2,
                showSold, sym),
          )),
        ])),
      ]),
    );
  }

  Widget _arenaCard(BuildContext context, UellowProductCard pr, int rank,
      bool showSold, String sym) {
    final medal = rank == 2 ? '🥈' : rank == 3 ? '🥉' : '#$rank';
    return GestureDetector(
      onTap: () => UellowRouter.goProduct(context, pr.id),
      child: Container(
        width: 122,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Expanded(child: Stack(fit: StackFit.expand, children: [
            CachedNetworkImage(imageUrl: pr.image, fit: BoxFit.cover,
                errorWidget: (_, __, ___) =>
                    const ColoredBox(color: Color(0xFFEFEFEF))),
            PositionedDirectional(top: 6, start: 6, child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: rank <= 3
                    ? const Color(0xE6FFFFFF) : const Color(0xB3412402),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(medal, style: TextStyle(fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: rank <= 3
                      ? const Color(0xFF4A2E04) : Colors.white)),
            )),
          ])),
          Padding(
            padding: const EdgeInsets.fromLTRB(7, 5, 7, 7),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(pr.name.current(UellowApi.instance.lang),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1F1206))),
              const SizedBox(height: 2),
              Row(children: [
                Text('${pr.price.amount.toStringAsFixed(3)}',
                    style: const TextStyle(fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF4A2E04))),
                const SizedBox(width: 2),
                Text(sym, style: const TextStyle(fontSize: 7.5,
                    color: Color(0xFF9A7B33),
                    fontWeight: FontWeight.w700)),
                const Spacer(),
                if (showSold && pr.soldCount > 0)
                  Text('🔥${pr.soldCount}', style: const TextStyle(
                      fontSize: 8.5, fontWeight: FontWeight.w800,
                      color: Color(0xFFBF360C))),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ─── TAB NAV — horizontal SHEIN-style tabs ──────────────────────────────────
class TabNavBlock extends StatefulWidget {
  const TabNavBlock({super.key, required this.p, required this.t, required this.ar});
  final Map<String, dynamic> p;
  final DynTheme t;
  final bool ar;
  @override
  State<TabNavBlock> createState() => _TabNavBlockState();
}
class _TabNavBlockState extends State<TabNavBlock> {
  int _active = 0;
  @override
  Widget build(BuildContext context) {
    final tabs = (widget.p['tabs'] as List? ?? const []);
    if (tabs.isEmpty) return const SizedBox.shrink();
    final style = (widget.p['style'] as String?) ?? 'underline';
    final t = widget.t;
    // v2.1.36 — builder-controlled alignment (start/center/end). Default
    // 'start' is direction-aware: it lines up with the slider's leading
    // edge in BOTH Arabic (right) and English (left).
    final align = (widget.p['align'] as String?) ?? 'start';
    final mainAlign = align == 'center'
        ? MainAxisAlignment.center
        : align == 'end' ? MainAxisAlignment.end : MainAxisAlignment.start;
    return Container(
      decoration: widget.p['sticky'] == true
          ? BoxDecoration(color: Colors.white,
              boxShadow: [BoxShadow(color: t.dark.withValues(alpha: 0.06), blurRadius: 6, offset: const Offset(0,2))])
          : null,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        // v2.0.67 — zero vertical padding so the tab strip sits flush
        // beneath the search bar; let block envelope's pad_y handle spacing.
        padding: const EdgeInsets.symmetric(horizontal: 10),
        physics: const ClampingScrollPhysics(),
        child: ConstrainedBox(
          // Let the alignment matter even when the tabs don't fill the
          // full width (otherwise the Row hugs its children).
          constraints: BoxConstraints(
              minWidth: MediaQuery.of(context).size.width - 20),
          child: Row(mainAxisAlignment: mainAlign, children: [
            for (int i = 0; i < tabs.length; i++) _tab(tabs[i] as Map, i, style, t),
          ]),
        ),
      ),
    );
  }
  Widget _tab(Map raw, int i, String style, DynTheme t) {
    final m = raw.cast<String, dynamic>();
    final label = (widget.ar ? m['labelAr'] : m['labelEn'])?.toString() ?? '';
    final active = i == _active;
    return GestureDetector(
      onTap: () {
        setState(() => _active = i);
        _openLink(context, (m['link'] as Map?)?.cast<String, dynamic>());
      },
      child: Container(
        // v2.1.36 — direction-aware gap (was EdgeInsets.only(right:),
        // which broke the start alignment in Arabic).
        margin: EdgeInsetsDirectional.only(end: style == 'underline' ? 18 : 6),
        padding: style == 'underline'
            ? const EdgeInsets.symmetric(vertical: 4)
            : const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: style == 'underline' ? null
              : active ? (style == 'pill' ? t.dark : UellowColors.yellowSoft)
                       : Colors.white,
          border: style == 'underline'
              ? Border(bottom: BorderSide(color: active ? t.primary : Colors.transparent, width: 2.5))
              : Border.all(color: active ? (style == 'pill' ? t.dark : UellowColors.yellow) : const Color(0xFFE5DCC2)),
          borderRadius: style == 'underline' ? null : BorderRadius.circular(16),
        ),
        child: Text(label, style: TextStyle(
            color: style == 'pill' && active ? Colors.white : t.dark,
            fontSize: 12.5, fontWeight: active ? FontWeight.w900 : FontWeight.w600)),
      ),
    );
  }
}

// ─── STORY BUBBLES — Instagram-style circular row with optional autoplay ────
class StoryBubblesBlock extends StatefulWidget {
  const StoryBubblesBlock({super.key, required this.p, required this.t, required this.ar});
  final Map<String, dynamic> p;
  final DynTheme t;
  final bool ar;
  @override
  State<StoryBubblesBlock> createState() => _StoryBubblesBlockState();
}
class _StoryBubblesBlockState extends State<StoryBubblesBlock> {
  final _ctrl = ScrollController();
  Timer? _autoTimer;

  @override
  void initState() {
    super.initState();
    if (widget.p['autoplay'] == true) {
      final secs = ((widget.p['autoplay_speed'] as num?)?.toInt() ?? 3).clamp(2, 10);
      _autoTimer = Timer.periodic(Duration(seconds: secs), (_) {
        if (!_ctrl.hasClients || !mounted) return;
        final next = _ctrl.offset + 80;
        if (next > _ctrl.position.maxScrollExtent) {
          _ctrl.animateTo(0, duration: const Duration(milliseconds: 600), curve: Curves.easeInOut);
        } else {
          _ctrl.animateTo(next, duration: const Duration(milliseconds: 600), curve: Curves.easeInOut);
        }
      });
    }
  }
  @override
  void dispose() { _autoTimer?.cancel(); _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final bubbles = (widget.p['bubbles'] as List? ?? const []);
    if (bubbles.isEmpty) return const SizedBox.shrink();
    final t = widget.t;
    final sz = ((widget.p['size'] as num?)?.toDouble() ?? 60).clamp(40.0, 100.0);
    final showRings = widget.p['show_rings'] != false;
    final ringColor = _hexColor(widget.p['ring_color'], t.primary);
    final title = (widget.ar ? widget.p['titleAr'] : widget.p['titleEn'])?.toString() ?? '';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (title.isNotEmpty) Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
        child: Text(title, style: TextStyle(color: t.dark, fontSize: 14, fontWeight: FontWeight.w900)),
      ),
      SizedBox(
        height: sz + 26,
        child: ListView.separated(
          controller: _ctrl,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          itemCount: bubbles.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (_, i) {
            final b = (bubbles[i] as Map).cast<String, dynamic>();
            final label = (widget.ar ? b['labelAr'] : b['labelEn'])?.toString() ?? '';
            final img = pickLocalizedImage(b, widget.ar);
            final icon = (b['icon'] as String?) ?? '⭐';
            return GestureDetector(
              onTap: () => _openLink(context, (b['link'] as Map?)?.cast<String, dynamic>()),
              child: Column(children: [
                Container(
                  width: sz, height: sz,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFE5E5),
                    shape: BoxShape.circle,
                    image: img.isNotEmpty
                        ? DecorationImage(image: CachedNetworkImageProvider(img), fit: BoxFit.cover)
                        : null,
                    boxShadow: showRings ? [
                      BoxShadow(color: ringColor, blurRadius: 0, spreadRadius: 2.5),
                      const BoxShadow(color: Colors.white, blurRadius: 0, spreadRadius: 4.5),
                    ] : null,
                  ),
                  alignment: Alignment.center,
                  child: img.isEmpty ? Text(icon, style: TextStyle(fontSize: sz * 0.4)) : null,
                ),
                const SizedBox(height: 5),
                SizedBox(
                  width: sz + 6,
                  child: Text(label, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: t.dark, fontSize: 10.5, fontWeight: FontWeight.w700)),
                ),
              ]),
            );
          },
        ),
      ),
    ]);
  }
}

// ─── LOOKBOOK — asymmetric collage with CTA ─────────────────────────────────
class LookbookBlock extends StatelessWidget {
  const LookbookBlock({super.key, required this.p, required this.t, required this.ar});
  final Map<String, dynamic> p;
  final DynTheme t;
  final bool ar;

  @override
  Widget build(BuildContext context) {
    final images = (p['images'] as List? ?? const []);
    if (images.isEmpty) return const SizedBox.shrink();
    final title = (ar ? p['titleAr'] : p['titleEn'])?.toString() ?? '';
    final sub = (ar ? p['subAr'] : p['subEn'])?.toString() ?? '';
    final cta = (ar ? p['ctaAr'] : p['ctaEn'])?.toString() ?? '';
    final layout = (p['layout'] as String?) ?? 'mosaic';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (title.isNotEmpty)
          Text(title, style: TextStyle(color: t.dark, fontSize: 16, fontWeight: FontWeight.w900)),
        if (sub.isNotEmpty) Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 8),
          child: Text(sub, style: TextStyle(color: t.dark.withValues(alpha: 0.6), fontSize: 12)),
        ),
        if (title.isNotEmpty || sub.isNotEmpty) const SizedBox(height: 6),
        if (layout == 'mosaic') _mosaic(context, images) else _grid(context, images),
        if (cta.isNotEmpty) Padding(
          padding: const EdgeInsets.only(top: 10),
          child: GestureDetector(
            onTap: () => _openLink(context, (p['cta_link'] as Map?)?.cast<String, dynamic>()),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: t.dark, borderRadius: BorderRadius.circular(8)),
              child: Text('$cta →',
                  style: TextStyle(color: t.primary, fontWeight: FontWeight.w900, fontSize: 13)),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _mosaic(BuildContext c, List images) {
    return AspectRatio(
      aspectRatio: 1.4,
      child: Row(children: [
        Expanded(flex: 2, child: _img(c, images.isNotEmpty ? images[0] : null)),
        const SizedBox(width: 4),
        Expanded(child: Column(children: [
          Expanded(child: _img(c, images.length > 1 ? images[1] : null)),
          const SizedBox(height: 4),
          Expanded(child: _img(c, images.length > 2 ? images[2] : null)),
        ])),
      ]),
    );
  }
  Widget _grid(BuildContext c, List images) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 4, crossAxisSpacing: 4,
      childAspectRatio: 1,
      children: [for (final i in images.take(4)) _img(c, i)],
    );
  }
  Widget _img(BuildContext c, dynamic raw) {
    if (raw == null) return Container(color: const Color(0xFFEEE6D6));
    final m = (raw as Map).cast<String, dynamic>();
    final url = pickLocalizedImage(m, ar);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: GestureDetector(
        onTap: () => _openLink(c, (m['link'] as Map?)?.cast<String, dynamic>()),
        child: url.isEmpty
            ? Container(decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [Color(0xFFFFE9D6), Color(0xFFF5C320)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight)))
            : CachedNetworkImage(imageUrl: url, fit: BoxFit.cover,
                placeholder: (_, __) => Container(color: const Color(0xFFEEE6D6))),
      ),
    );
  }
}

// ─── IMAGE BANNER — pure image block (1/2/3 col) with per-lang images ───────
// v2.0.74 — every item carries `image_url` (default) and optional
// `image_url_ar` (Arabic override). Renderer picks the AR image only when
// `ar==true` and the field is non-empty; otherwise falls back to the EN one
// so admins don't have to upload twice for non-localized artwork.
class ImageBannerBlock extends StatelessWidget {
  const ImageBannerBlock({super.key, required this.p, required this.t, required this.ar});
  final Map<String, dynamic> p;
  final DynTheme t;
  final bool ar;

  static const _aspectMap = {
    '16_9': 16 / 9,
    '3_1':  3 / 1,
    '4_3':  4 / 3,
    '1_1':  1.0,
    '3_4':  3 / 4,
  };

  String _pickImage(Map<String, dynamic> item) {
    final base = (item['image_url'] as String?) ?? '';
    if (!ar) return base;
    final loc = (item['image_url_ar'] as String?) ?? '';
    return loc.isNotEmpty ? loc : base;
  }

  String _pickAlt(Map<String, dynamic> item) {
    final v = (ar ? item['altAr'] : item['altEn'])?.toString();
    return v ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final banners = ((p['banners'] as List?) ?? const []).cast<dynamic>()
        .map((e) => (e as Map).cast<String, dynamic>())
        .where((b) => _pickImage(b).isNotEmpty)
        .toList();
    if (banners.isEmpty) return const SizedBox.shrink();
    final variant = (p['variant'] as String?) ?? 'full';
    final aspect = _aspectMap[(p['aspect'] as String?) ?? '16_9'] ?? 16 / 9;
    final radius = ((p['radius'] as num?)?.toDouble() ?? 12).clamp(0, 32).toDouble();
    final gap = ((p['gap'] as num?)?.toDouble() ?? 8).clamp(0, 32).toDouble();

    Widget tile(Map<String, dynamic> b) {
      final img = _pickImage(b);
      final alt = _pickAlt(b);
      final link = (b['link'] as Map?)?.cast<String, dynamic>();
      return GestureDetector(
        onTap: () => _openBannerLink(context, link),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: AspectRatio(
            aspectRatio: aspect,
            child: Semantics(
              label: alt,
              image: true,
              child: CachedNetworkImage(
                imageUrl: img,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(color: t.primary.withOpacity(0.06)),
                errorWidget: (_, __, ___) => Container(
                  color: t.primary.withOpacity(0.06),
                  child: Icon(Icons.image_outlined, color: t.dark.withOpacity(0.3)),
                ),
              ),
            ),
          ),
        ),
      );
    }

    Widget body;
    if (variant == 'cols_2' && banners.length >= 1) {
      final pair = banners.take(2).toList();
      body = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (int i = 0; i < pair.length; i++) ...[
          Expanded(child: tile(pair[i])),
          if (i != pair.length - 1) SizedBox(width: gap),
        ],
      ]);
    } else if (variant == 'cols_3') {
      final trio = banners.take(3).toList();
      body = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (int i = 0; i < trio.length; i++) ...[
          Expanded(child: tile(trio[i])),
          if (i != trio.length - 1) SizedBox(width: gap),
        ],
      ]);
    } else {
      body = tile(banners.first);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: body,
    );
  }
}

// Local link opener for ImageBannerBlock — mirrors the global _openLink in
// dynamic_page_screen.dart. Named distinctly because another `_openLink`
// already lives in this file (used by Slider / Story Bubbles etc).
void _openBannerLink(BuildContext context, Map<String, dynamic>? link) {
  if (link == null) return;
  final type = link['type']?.toString();
  final value = link['value']?.toString();
  if (type == null || value == null || value.isEmpty) return;
  switch (type) {
    case 'product':
      final id = int.tryParse(value) ?? 0;
      if (id > 0) UellowRouter.goProduct(context, id);
      break;
    case 'category':
      final id = int.tryParse(value) ?? 0;
      if (id > 0) UellowRouter.goCollection(context, id);
      break;
    case 'url':
      launchUrl(Uri.parse(value), mode: LaunchMode.externalApplication);
      break;
    case 'screen':
      Navigator.of(context).pushNamed('/$value');
      break;
  }
}

// ─── OCCASION HEADER — themed full-width seasonal / event header ─────────────
// v2.0.96 — Builder block 'occasion-header'. All content lives in props; the
// builder ships preset themes (Ramadan, Eid al-Fitr / al-Adha, Black Friday,
// White Wednesday, Kuwait National Day, New Year, Summer/Winter, Back to
// School) that pre-fill gradient + emoji + pattern + bilingual copy. Props:
//   titleEn/Ar, subtitleEn/Ar, cta_textEn/Ar, cta_link {type,value},
//   variant (banner|compact|ribbon), accent, accent2, text_color,
//   icon (emoji), pattern (dots|lines|grid|mesh|waves|confetti|lanterns),
//   height, bg_image(/_ar), show_countdown + event_end (ISO).
class OccasionHeaderBlock extends StatelessWidget {
  const OccasionHeaderBlock({super.key, required this.p, required this.t, required this.ar});
  final Map<String, dynamic> p;
  final DynTheme t;
  final bool ar;

  String _txt(String key, [String fallback = '']) {
    final en = p['${key}En']?.toString() ?? fallback;
    if (!ar) return en;
    final a = p['${key}Ar']?.toString();
    return (a != null && a.isNotEmpty) ? a : en;
  }

  @override
  Widget build(BuildContext context) {
    final title = _txt('title', 'Special Occasion');
    final subtitle = _txt('subtitle');
    final ctaText = _txt('cta_text');
    final icon = p['icon']?.toString() ?? '';
    final variant = (p['variant'] as String?) ?? 'banner';
    final accent = _parseColor(p['accent']) ?? const Color(0xFFE63946);
    final accent2 = _parseColor(p['accent2']) ?? accent.withOpacity(0.65);
    final textColor = _parseColor(p['text_color']) ?? Colors.white;
    final pattern = (p['pattern'] as String?) ?? 'none';
    final bgImage = pickLocalizedImage(p, ar, key: 'bg_image');
    final showCountdown = p['show_countdown'] == true;
    final eventEnd = p['event_end']?.toString() ?? '';
    final link = (p['cta_link'] as Map?)?.cast<String, dynamic>();
    final height = ((p['height'] as num?)?.toDouble() ?? 130).clamp(70, 260).toDouble();

    // RIBBON — slim single-line accent ribbon
    if (variant == 'ribbon') {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: GestureDetector(
          onTap: link == null ? null : () => _openBannerLink(context, link),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [accent, accent2]),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              if (icon.isNotEmpty) ...[
                Text(icon, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
              ],
              Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: textColor, fontWeight: FontWeight.w900, fontSize: 14))),
              if (showCountdown && eventEnd.isNotEmpty)
                _MiniCountdown(endIso: eventEnd, accent: accent),
            ]),
          ),
        ),
      );
    }

    final isCompact = variant == 'compact';
    final h = isCompact ? (height * 0.72).clamp(64, 170).toDouble() : height;

    final content = Stack(fit: StackFit.expand, children: [
      // Background — gradient, or cover image with gradient fallback on error
      if (bgImage.isEmpty)
        DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [accent, accent2]))),
      if (bgImage.isNotEmpty)
        CachedNetworkImage(imageUrl: bgImage, fit: BoxFit.cover,
            placeholder: (_, __) => DecoratedBox(
                decoration: BoxDecoration(gradient: LinearGradient(colors: [accent, accent2]))),
            errorWidget: (_, __, ___) => DecoratedBox(
                decoration: BoxDecoration(gradient: LinearGradient(colors: [accent, accent2])))),
      // Decorative pattern overlay (lanterns/confetti/waves/…)
      if (pattern != 'none')
        _BackgroundLayer(color: null, pattern: pattern, imageUrl: '', patternColor: textColor),
      // Legibility veil when a photo is behind the text
      if (bgImage.isNotEmpty)
        DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
          begin: ar ? Alignment.centerRight : Alignment.centerLeft,
          end: ar ? Alignment.centerLeft : Alignment.centerRight,
          colors: [Colors.black.withOpacity(0.45), Colors.black.withOpacity(0.05)]))),
      Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          if (icon.isNotEmpty && !isCompact) ...[
            Text(icon, style: const TextStyle(fontSize: 38)),
            const SizedBox(width: 14),
          ],
          Expanded(child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon.isNotEmpty && isCompact) ...[
                Text(icon, style: const TextStyle(fontSize: 22)),
                const SizedBox(height: 2),
              ],
              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: textColor, fontSize: isCompact ? 16 : 22,
                      fontWeight: FontWeight.w900, height: 1.1,
                      shadows: const [Shadow(color: Colors.black26, blurRadius: 4)])),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: textColor.withValues(alpha: 0.92),
                        fontSize: isCompact ? 11.5 : 13, fontWeight: FontWeight.w600,
                        shadows: const [Shadow(color: Colors.black26, blurRadius: 3)])),
              ],
              if (showCountdown && eventEnd.isNotEmpty) ...[
                const SizedBox(height: 8),
                Align(alignment: ar ? Alignment.centerRight : Alignment.centerLeft,
                    child: _MiniCountdown(endIso: eventEnd, accent: accent)),
              ],
            ],
          )),
          if (ctaText.isNotEmpty) ...[
            const SizedBox(width: 12),
            _OccasionCta(text: ctaText, fg: accent, bg: textColor,
                onTap: () => _openBannerLink(context, link)),
          ],
        ]),
      ),
    ]);

    final card = ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(height: h, child: content),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: (link != null && ctaText.isEmpty)
          ? GestureDetector(onTap: () => _openBannerLink(context, link), child: card)
          : card,
    );
  }
}

class _OccasionCta extends StatelessWidget {
  const _OccasionCta({required this.text, required this.fg, required this.bg, required this.onTap});
  final String text;
  final Color fg, bg;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: fg, fontWeight: FontWeight.w900, fontSize: 12)),
        ),
      ),
    );
  }
}

// ─── REELS STRIP — circular video thumbs that open the Reels feed ───────────
// v2.0.90 — Data shape from resolver: { items: [{ product_id, product_name,
//                                                  thumbnail }, …] }
// Tap any bubble → push /reels. Visually mimics Instagram stories.
class ReelsStripBlock extends StatelessWidget {
  const ReelsStripBlock({super.key, required this.p, required this.data,
      required this.t, required this.ar});
  final Map<String, dynamic> p;
  final Map<String, dynamic> data;
  final DynTheme t;
  final bool ar;

  @override
  Widget build(BuildContext context) {
    final items = ((data['items'] as List?) ?? const [])
        .cast<dynamic>().map((e) => (e as Map).cast<String, dynamic>()).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    final bubbleSize = ((p['bubble_size'] as num?)?.toDouble() ?? 62).clamp(40, 120).toDouble();
    final ringColor = _parseColor(p['ring_color']) ?? UellowColors.yellow;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DynSectionHeader(props: p, theme: t, ar: ar,
          fallbackEn: '🔥 Trending videos'),
      SizedBox(
        height: bubbleSize + 22,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, i) {
            final it = items[i];
            final thumb = (it['thumbnail'] as String?) ?? '';
            final fullUrl = thumb.startsWith('http')
                ? thumb : '${UellowApi.instance.baseUrl}$thumb';
            return GestureDetector(
              onTap: () => Navigator.pushNamed(context, '/reels'),
              child: SizedBox(width: bubbleSize + 4, child: Column(children: [
                Container(
                  width: bubbleSize, height: bubbleSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle, color: Colors.white,
                    border: Border.all(color: ringColor, width: 2.5),
                    boxShadow: const [BoxShadow(color: Color(0x33000000),
                        blurRadius: 6, offset: Offset(0, 2))],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(fit: StackFit.expand, children: [
                    if (thumb.isNotEmpty)
                      CachedNetworkImage(imageUrl: fullUrl, fit: BoxFit.cover,
                          errorWidget: (_,__,___) => Container(
                              color: t.primary.withValues(alpha: 0.06)))
                    else
                      Container(color: t.primary.withValues(alpha: 0.06)),
                    // Play badge overlay
                    Center(child: Container(
                      width: 22, height: 22,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.85),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.play_arrow_rounded,
                          color: UellowColors.darkBrown, size: 16),
                    )),
                  ]),
                ),
                if (i == 0) const SizedBox(height: 2)
                else const SizedBox(height: 4),
              ])),
            );
          },
        ),
      ),
    ]);
  }
}

// ─── STICKY CTA — promo bar (inline placement) ──────────────────────────────
class StickyCtaBlock extends StatefulWidget {
  const StickyCtaBlock({super.key, required this.p, required this.t, required this.ar});
  final Map<String, dynamic> p;
  final DynTheme t;
  final bool ar;
  @override
  State<StickyCtaBlock> createState() => _StickyCtaBlockState();
}
class _StickyCtaBlockState extends State<StickyCtaBlock> {
  bool _closed = false;
  @override
  Widget build(BuildContext context) {
    if (_closed) return const SizedBox.shrink();
    final p = widget.p;
    final ar = widget.ar;
    final bg = _hexColor(p['bg_color'], const Color(0xFF412402));
    final fg = _hexColor(p['text_color'], Colors.white);
    final label = (ar ? p['labelAr'] : p['labelEn'])?.toString() ?? '';
    final cta = (ar ? p['ctaAr'] : p['ctaEn'])?.toString() ?? '';
    final icon = (p['icon'] as String?) ?? '🎁';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _openLink(context, (p['cta_link'] as Map?)?.cast<String, dynamic>()),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Text(icon, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Expanded(child: Text(label,
                  style: TextStyle(color: fg, fontSize: 12.5, fontWeight: FontWeight.w700))),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: fg.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(cta,
                    style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w900)),
              ),
              if (p['show_close'] != false) ...[
                const SizedBox(width: 6),
                InkWell(
                  onTap: () => setState(() => _closed = true),
                  child: Icon(Icons.close, size: 18, color: fg.withValues(alpha: 0.7)),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

Color _hexColor(dynamic v, Color fb) {
  if (v == null) return fb;
  final s = v.toString();
  final m = RegExp(r'#?([0-9A-Fa-f]{3,6})').firstMatch(s);
  if (m == null) return fb;
  var h = m.group(1)!;
  if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
  return Color(int.parse('FF$h', radix: 16));
}

// ═══ New User Discount block (v2.1.57 — Banggood-style) ═══════════════
// Gradient exclusive panel: coupon-pack card + mini deal rows on the
// start side, "New User Bonus" product cards scrolling after it.
// Audience prop: all | guests | new (guests OR signed-in with 0 orders).

// =====================================================================
// PromoSectionBlock (v2.1.75) — ONE powerful, settings-rich promo
// section that powers 5 builder presets via a `variant` prop:
//   spotlight  — featured first product + rail (great for "on offer")
//   category   — clean category showcase rail
//   rank       — best-sellers with #1/#2/#3 rank medals
//   arrivals   — "NEW" ribbon on fresh products
//   mega       — bold sale band with big % OFF chips
// Every preset shares the same engine: gradient header band (2 colors),
// a logo (emoji OR image url), bilingual title/subtitle/badge, optional
// CTA, rail-or-grid layout, and the standard product card.
// =====================================================================
class PromoSectionBlock extends StatelessWidget {
  const PromoSectionBlock({super.key, required this.variant, required this.p,
      required this.data, required this.t, required this.ar});
  final String variant;          // spotlight | category | rank | arrivals | mega
  final Map<String, dynamic> p;
  final Map<String, dynamic> data;
  final DynTheme t;
  final bool ar;

  String _tx(String en, String arr) {
    final v = ((ar ? p[arr] : p[en]) ?? p[en] ?? '').toString();
    return v;
  }

  @override
  Widget build(BuildContext context) {
    final items = ((data['items'] as List?) ?? const [])
        .map((e) {
          try { return UellowProductCard.fromJson((e as Map).cast<String, dynamic>()); }
          catch (_) { return null; }
        }).whereType<UellowProductCard>().toList();
    if (items.isEmpty) return const SizedBox.shrink();

    // per-variant defaults (overridable from the builder)
    final defaults = <String, List<dynamic>>{
      // [c1, c2, logo, badgeEn, badgeAr]
      'spotlight': ['#7B2FF7', '#B86CFF', '✨', 'Featured', 'مميّز'],
      'category':  ['#2F6E62', '#3E9C88', '🛍', 'Shop', 'تسوّق'],
      'rank':      ['#C19A2E', '#E8C45A', '🏆', 'Best Seller', 'الأكثر مبيعاً'],
      'arrivals':  ['#1E88A8', '#43C0D6', '🆕', 'New', 'جديد'],
      'mega':      ['#E63946', '#FF7A85', '🔥', 'SALE', 'تخفيض'],
    }[variant] ?? ['#2F6E62', '#3E9C88', '⭐', 'Offer', 'عرض'];

    final c1 = _parseColor(p['c1']) ?? _parseColor(defaults[0] as String)!;
    final c2 = _parseColor(p['c2']) ?? _parseColor(defaults[1] as String)!;
    final logo = (p['logo'] ?? defaults[2]).toString();
    final logoImg = (p['logo_image'] ?? '').toString();
    final title = _tx('titleEn', 'titleAr');
    final sub = _tx('subEn', 'subAr');
    final badge = (() {
      final b = _tx('badgeEn', 'badgeAr');
      return b.isNotEmpty ? b : (ar ? defaults[4] : defaults[3]).toString();
    })();
    final cta = _tx('ctaEn', 'ctaAr');
    // v2.1.91 — SHAPE: 6 selectable layouts per block (builder `shape`).
    // Falls back to the variant's natural shape when unset.
    const _shapeForVariant = {
      'spotlight': 'hero', 'category': 'grid', 'rank': 'leaderboard',
      'arrivals': 'arrivals', 'mega': 'mega',
    };
    final shape = (p['shape'] ?? _shapeForVariant[variant] ?? 'rail').toString();
    // CTA / "All" button colour (builder `cta_color`, else brand yellow).
    final ctaColor = _parseColor(p['cta_color']) ?? UellowColors.yellow;
    // header background style: 'gradient' (default) | 'flat' | 'none'.
    final headerStyle = (p['header_style'] ?? 'gradient').toString();
    final layout = (p['layout'] ?? (variant == 'category' ? 'grid' : 'rail'))
        .toString();
    // v2.1.92 — "All" button ALWAYS lands on a full product list. With a
    // category → that category; otherwise a feed keyed to the block variant
    // (mega→discounts, arrivals→newest, rank→bestsellers, else→newest).
    final onHeaderTap = () {
      final cid = (p['category_id'] as num?)?.toInt() ?? 0;
      if (cid > 0) {
        Navigator.pushNamed(context, '/collection',
            arguments: {'category_id': cid, 'title': title});
        return;
      }
      if (variant == 'rank') {
        Navigator.pushNamed(context, '/bestsellers');
        return;
      }
      final feed = {'mega': 'discount', 'arrivals': 'newest'}[variant] ?? 'newest';
      final ft = title.isNotEmpty
          ? title
          : (variant == 'mega'
              ? (ar ? 'عروض وتخفيضات' : 'Offers & deals')
              : variant == 'arrivals'
                  ? (ar ? 'وصل حديثاً' : 'New arrivals')
                  : (ar ? 'منتجات مختارة' : 'Featured'));
      Navigator.pushNamed(context, '/collection',
          arguments: {'sort': feed, 'title': ft});
    };

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10),
      // v2.1.92 — NO shadow around the block (per ali@uellow): clean flat
      // card with a hairline border only.
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEDEDED)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── minimal header (v2.1.91) — small icon, description UNDER the
        // title, tiny coloured "All" pill; background gradient / flat / none.
        _header(context, c1, c2, logo, logoImg, title, sub, cta, ctaColor,
            headerStyle, onHeaderTap),
        // ── products — layout chosen by SHAPE (6 selectable) ──
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
          child: _bodyForShape(context, shape, items, c1, c2, badge),
        ),
      ]),
    );
  }

  Widget _header(BuildContext ctx, Color c1, Color c2, String logo,
      String logoImg, String title, String sub, String cta, Color ctaColor,
      String style, VoidCallback onTap) {
    final ar = UellowApi.instance.lang.toLowerCase().startsWith('ar');
    final grad = style == 'gradient';
    final onColor = grad ? Colors.white : UellowColors.ink;
    final iconTileBg = grad ? Colors.white.withValues(alpha: 0.20)
        : c1.withValues(alpha: 0.12);
    BoxDecoration deco;
    if (grad) {
      deco = BoxDecoration(gradient: LinearGradient(
          begin: Alignment.centerLeft, end: Alignment.centerRight, colors: [c1, c2]));
    } else if (style == 'flat') {
      deco = BoxDecoration(color: c1.withValues(alpha: 0.08));
    } else {
      deco = const BoxDecoration(color: Colors.white);   // none
    }
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(11, 9, 9, 7),
        decoration: deco,
        child: Row(children: [
          // small icon
          Container(width: 26, height: 26, alignment: Alignment.center,
            decoration: BoxDecoration(color: iconTileBg,
                borderRadius: BorderRadius.circular(8)),
            clipBehavior: Clip.antiAlias,
            child: logoImg.isNotEmpty
                ? CachedNetworkImage(imageUrl: logoImg, width: 26, height: 26,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Text(logo,
                        style: const TextStyle(fontSize: 14)))
                : Text(logo, style: const TextStyle(fontSize: 14))),
          const SizedBox(width: 8),
          // title + description UNDERNEATH
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min, children: [
            Text(title.isNotEmpty ? title : (ar ? 'عرض مميّز' : 'Featured offer'),
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: onColor, fontSize: 13.5,
                    fontWeight: FontWeight.w900)),
            if (sub.isNotEmpty) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: grad ? Colors.white.withValues(alpha: .85)
                        : UellowColors.muted,
                    fontSize: 10.5, height: 1.2)),
          ])),
          const SizedBox(width: 8),
          // tiny coloured "All" pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: ctaColor,
                borderRadius: BorderRadius.circular(999)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(cta.isNotEmpty ? cta : (ar ? 'الكل' : 'All'),
                  style: const TextStyle(color: UellowColors.darkBrown,
                      fontSize: 10.5, fontWeight: FontWeight.w900)),
              Icon(ar ? Icons.chevron_left : Icons.chevron_right,
                  color: UellowColors.darkBrown, size: 14),
            ]),
          ),
        ]),
      ),
    );
  }

  // 6 selectable shapes (builder `shape`): hero · grid · rail · leaderboard
  // · mega · arrivals. Block colour (c1/c2) + icon (logo) are customisable.
  Widget _bodyForShape(BuildContext ctx, String shape,
      List<UellowProductCard> items, Color c1, Color c2, String badge) {
    switch (shape) {
      case 'hero':        return _spotlightHero(ctx, items, c1, badge);
      case 'leaderboard': return _leaderboard(ctx, items, c1, c2);
      case 'mega':        return _megaGrid(items, c1);
      case 'arrivals':    return _arrivalsRail(items, c1, badge);
      case 'grid':        return _grid(items, c1, badge);
      case 'rail':
      default:            return _rail(items, c1, badge);
    }
  }

  // SPOTLIGHT — one big hero (image left / details right) + a small rail.
  Widget _spotlightHero(BuildContext ctx, List<UellowProductCard> items,
      Color c1, String badge) {
    final hero = items.first;
    final rest = items.skip(1).toList();
    return Column(children: [
      GestureDetector(
        onTap: () => UellowRouter.goProduct(ctx, hero.id),
        child: Container(
          decoration: BoxDecoration(
            color: c1.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c1.withValues(alpha: 0.18)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(children: [
            Expanded(flex: 5, child: AspectRatio(aspectRatio: 1,
              child: CachedNetworkImage(imageUrl: hero.image, fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => const ColoredBox(color: Color(0xFFF4F4F4))))),
            Expanded(flex: 6, child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min, children: [
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: c1, borderRadius: BorderRadius.circular(999)),
                  child: Text(badge, style: const TextStyle(color: Colors.white,
                      fontSize: 9.5, fontWeight: FontWeight.w900))),
                const SizedBox(height: 8),
                Text(hero.name.current(ar ? 'ar' : 'en'), maxLines: 2,
                    overflow: TextOverflow.ellipsis, style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w800,
                        color: UellowColors.ink, height: 1.3)),
                const SizedBox(height: 6),
                Text(hero.price.formatLocalized(ar ? 'ar' : 'en'),
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: c1)),
              ]),
            )),
          ]),
        ),
      ),
      if (rest.isNotEmpty) ...[
        const SizedBox(height: 10),
        SizedBox(height: 276, child: ListView.separated(   // spotlight rail: −1px (v2.1.97)
          scrollDirection: Axis.horizontal, itemCount: rest.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) => SizedBox(width: 150,
              child: ProductCard(rich: true, product: rest[i], hideAvail: true)),
        )),
      ],
    ]);
  }

  // RANK — a vertical leaderboard: medal #n + thumb + name + price.
  Widget _leaderboard(BuildContext ctx, List<UellowProductCard> items,
      Color c1, Color c2) {
    const medals = ['🥇', '🥈', '🥉'];
    return Column(children: [
      for (var i = 0; i < items.length && i < 6; i++)
        GestureDetector(
          onTap: () => UellowRouter.goProduct(ctx, items[i].id),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: i < 3 ? c2.withValues(alpha: 0.10) : const Color(0xFFF8F8F8),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: i < 3 ? c2.withValues(alpha: 0.30)
                  : UellowColors.border),
            ),
            child: Row(children: [
              SizedBox(width: 30, child: Text(
                  i < 3 ? medals[i] : '#${i + 1}',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: i < 3 ? 20 : 13,
                      fontWeight: FontWeight.w900, color: c1))),
              ClipRRect(borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(imageUrl: items[i].image,
                    width: 52, height: 52, fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => const ColoredBox(color: Color(0xFFF4F4F4),
                        child: SizedBox(width: 52, height: 52)))),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min, children: [
                Text(items[i].name.current(ar ? 'ar' : 'en'), maxLines: 2,
                    overflow: TextOverflow.ellipsis, style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w700, color: UellowColors.ink)),
                const SizedBox(height: 3),
                Text(items[i].price.formatLocalized(ar ? 'ar' : 'en'),
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: c1)),
              ])),
              Icon(ar ? Icons.chevron_left : Icons.chevron_right,
                  color: UellowColors.muted, size: 20),
            ]),
          ),
        ),
    ]);
  }

  // MEGA — bold 2-col grid with a big diagonal -% OFF ribbon.
  Widget _megaGrid(List<UellowProductCard> items, Color c1) {
    return GridView.builder(
      shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10,
        childAspectRatio: 0.586),  // mega: +1px more (v2.1.97)
      itemCount: items.length,
      itemBuilder: (_, i) {
        final d = items[i].discountPct;
        return Stack(clipBehavior: Clip.none, children: [
          ProductCard(rich: true, product: items[i], hideAvail: true),
          if (d > 0) PositionedDirectional(top: 8, start: -2, child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: const BoxDecoration(color: Color(0xFFE63946),
              borderRadius: BorderRadius.only(topRight: Radius.circular(2),
                  bottomRight: Radius.circular(9), bottomLeft: Radius.circular(9))),
            child: Text('-$d%', style: const TextStyle(color: Colors.white,
                fontSize: 13, fontWeight: FontWeight.w900)))),
        ]);
      },
    );
  }

  // ARRIVALS — taller horizontal rail with a corner NEW ribbon.
  Widget _arrivalsRail(List<UellowProductCard> items, Color c1, String badge) {
    return SizedBox(height: 284, child: ListView.separated(   // arrivals: slightly shorter (v2.1.92)
      scrollDirection: Axis.horizontal, itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(width: 8),
      itemBuilder: (_, i) => SizedBox(width: 170, child: Stack(
          clipBehavior: Clip.none, children: [
        ProductCard(rich: true, product: items[i], hideAvail: true),
        PositionedDirectional(top: 0, end: 0, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(color: c1, borderRadius:
              const BorderRadius.only(topRight: Radius.circular(10),
                  bottomLeft: Radius.circular(10))),
          child: Text(ar ? 'جديد' : 'NEW', style: const TextStyle(color: Colors.white,
              fontSize: 9.5, fontWeight: FontWeight.w900)))),
      ])),
    ));
  }

  Widget _rail(List<UellowProductCard> items, Color c1, String badge) =>
      SizedBox(height: 286, child: ListView.separated(
        scrollDirection: Axis.horizontal, itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => SizedBox(width: 160,
            child: ProductCard(rich: true, product: items[i], hideAvail: true)),
      ));

  Widget _grid(List<UellowProductCard> items, Color c1, String badge) =>
      GridView.builder(
        shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, mainAxisSpacing: 8, crossAxisSpacing: 8,
          childAspectRatio: 0.59),   // category: +3px taller (v2.1.92)
        itemCount: items.length,
        itemBuilder: (_, i) => ProductCard(rich: true, product: items[i], hideAvail: true),
      );

  Widget _card(UellowProductCard prod, int i, Color accent, String badge) {
    Widget card = ProductCard(rich: true, product: prod, hideAvail: true);
    // variant-specific overlay badge
    String? overlay;
    if (variant == 'rank') {
      overlay = '#${i + 1}';
    } else if (variant == 'arrivals') {
      overlay = ar ? 'جديد' : 'NEW';
    } else if (variant == 'mega') {
      final d = prod.discountPct;
      if (d > 0) overlay = '-$d%';
    } else if (variant == 'spotlight' && i == 0) {
      overlay = badge;
    }
    if (overlay == null) return card;
    final isMedal = variant == 'rank';
    return Stack(clipBehavior: Clip.none, children: [
      card,
      PositionedDirectional(
        top: 6, start: 6,
        child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: isMedal ? 8 : 7, vertical: isMedal ? 5 : 3),
          decoration: BoxDecoration(
            color: variant == 'mega' ? const Color(0xFFE63946)
                : (isMedal ? const Color(0xFFC19A2E) : accent),
            borderRadius: BorderRadius.circular(isMedal ? 999 : 7),
            boxShadow: const [BoxShadow(color: Color(0x33000000),
                blurRadius: 4, offset: Offset(0, 2))],
          ),
          child: Text(overlay,
              style: const TextStyle(color: Colors.white,
                  fontSize: 10.5, fontWeight: FontWeight.w900)),
        ),
      ),
    ]);
  }
}

class NewUserBlock extends StatefulWidget {
  const NewUserBlock({super.key, required this.p, required this.data,
      required this.t, required this.ar});
  final Map<String, dynamic> p;
  final Map<String, dynamic> data;
  final DynTheme t;
  final bool ar;

  @override
  State<NewUserBlock> createState() => _NewUserBlockState();
}

class _NewUserBlockState extends State<NewUserBlock> {
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    _checkAudience();
  }

  Future<void> _checkAudience() async {
    final aud = (widget.p['audience'] ?? 'all').toString();
    if (aud == 'all') return;
    try {
      final token = await UellowApi.instance.tokenStore.readToken();
      final signedIn = token != null && token.isNotEmpty;
      if (aud == 'guests') {
        if (signedIn && mounted) setState(() => _visible = false);
        return;
      }
      // aud == 'new' → guests count as new; signed-in must have 0 orders.
      if (!signedIn) return;
      final page = await UellowApi.instance.orders.list(page: 1, perPage: 1);
      if (page.total > 0 && mounted) setState(() => _visible = false);
    } catch (_) {/* default to visible */}
  }

  void _collect() {
    UellowApi.instance.tokenStore.readToken().then((tok) {
      if (!mounted) return;
      Navigator.pushNamed(context,
          (tok == null || tok.isEmpty) ? '/auth' : '/coupons');
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    final p = widget.p;
    final ar = widget.ar;
    final items = ((widget.data['items'] as List?) ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>()).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    final c1 = _parseColor(p['c1']) ?? const Color(0xFFFF7A00);
    final c2 = _parseColor(p['c2']) ?? const Color(0xFFFFB347);
    final title = ((ar ? p['titleAr'] : p['titleEn'])
        ?? p['titleEn'] ?? '').toString();
    final sub = ((ar ? p['subAr'] : p['subEn'])
        ?? p['subEn'] ?? '').toString();
    final cta = ((ar ? p['ctaAr'] : p['ctaEn'])
        ?? p['ctaEn'] ?? (ar ? 'اجمعها' : 'Collect')).toString();
    final badge = ((ar ? p['badgeAr'] : p['badgeEn'])
        ?? p['badgeEn'] ?? (ar ? 'مكافأة العميل الجديد' : 'New User Bonus'))
        .toString();
    final packValue = (p['pack_value'] ?? '9.5').toString();
    final packCur = (p['pack_currency'] ?? 'KD').toString();
    final miniRows = items.take(2).toList();
    final cards = items.skip(2).toList();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [c1, c2]),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: c1.withValues(alpha: 0.35),
            blurRadius: 12, offset: const Offset(0, 5))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // header
        Row(children: [
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 15.5,
                    fontWeight: FontWeight.w900)),
            if (sub.isNotEmpty) Text(sub,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.92),
                    fontSize: 11)),
          ])),
          GestureDetector(
            onTap: _collect,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
                boxShadow: const [BoxShadow(color: Color(0x33000000),
                    blurRadius: 6, offset: Offset(0, 2))],
              ),
              child: Text(cta, style: TextStyle(color: c1,
                  fontSize: 12, fontWeight: FontWeight.w900)),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        SizedBox(height: 168, child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // coupon-pack card + 2 mini deal rows
          SizedBox(width: 132, child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end, children: [
                Flexible(child: Text(packValue,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c1, fontSize: 22,
                        fontWeight: FontWeight.w900, height: 1.0))),
                const SizedBox(width: 3),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(packCur, style: TextStyle(color: c1,
                      fontSize: 10, fontWeight: FontWeight.w800)),
                ),
              ]),
              Text(ar ? 'باقة كوبونات' : 'Coupon pack',
                  style: const TextStyle(fontSize: 9,
                      color: Color(0xFF8A8A8A),
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              for (final m in miniRows) Expanded(child: _miniRow(m, c1)),
            ]),
          )),
          const SizedBox(width: 8),
          // product cards rail
          Expanded(child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: cards.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => _bonusCard(cards[i], badge, c1),
          )),
        ])),
      ]),
    );
  }

  Widget _miniRow(Map<String, dynamic> m, Color accent) {
    final img = ((m['image'] ?? m['image_url']) ?? '').toString();
    final price = ((m['price'] as Map?)?['amount'] as num?)?.toDouble()
        ?? (m['price'] as num?)?.toDouble() ?? 0;
    return GestureDetector(
      onTap: () {
        final id = (m['id'] as num?)?.toInt() ?? 0;
        if (id > 0) UellowRouter.goProduct(context, id);
      },
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: CachedNetworkImage(
                imageUrl: img.startsWith('http')
                    ? img : '${UellowApi.instance.baseUrl}$img',
                width: 38, height: 38, fit: BoxFit.cover,
                errorWidget: (_, __, ___) =>
                    const ColoredBox(color: Color(0xFFEFEFEF))),
          ),
          const SizedBox(width: 6),
          Expanded(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${price.toStringAsFixed(2)} ${widget.ar ? "د.ك" : "KD"}',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: accent, fontSize: 11,
                    fontWeight: FontWeight.w900)),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(widget.ar ? '⚡ بكوبون' : '⚡ w/ coupon',
                  style: TextStyle(color: accent, fontSize: 7.5,
                      fontWeight: FontWeight.w800)),
            ),
          ])),
        ]),
      ),
    );
  }

  Widget _bonusCard(Map<String, dynamic> m, String badge, Color accent) {
    final img = ((m['image'] ?? m['image_url']) ?? '').toString();
    final price = ((m['price'] as Map?)?['amount'] as num?)?.toDouble()
        ?? (m['price'] as num?)?.toDouble() ?? 0;
    final cmp = ((m['compare_price'] as Map?)?['amount'] as num?)?.toDouble()
        ?? (m['compare_price'] as num?)?.toDouble() ?? 0;
    return GestureDetector(
      onTap: () {
        final id = (m['id'] as num?)?.toInt() ?? 0;
        if (id > 0) UellowRouter.goProduct(context, id);
      },
      child: Container(
        width: 110,
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Stack(fit: StackFit.expand, children: [
            CachedNetworkImage(
                imageUrl: img.startsWith('http')
                    ? img : '${UellowApi.instance.baseUrl}$img',
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) =>
                    const ColoredBox(color: Color(0xFFEFEFEF))),
            PositionedDirectional(bottom: 0, start: 0, end: 0,
              child: Container(
                color: const Color(0xFFFFE9A8),
                padding: const EdgeInsets.symmetric(vertical: 2),
                alignment: Alignment.center,
                child: Text(badge, maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 7.5,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF7A4A00))),
              ),
            ),
          ])),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.center,
                children: [
              Text('${price.toStringAsFixed(2)}',
                  style: TextStyle(color: accent, fontSize: 12,
                      fontWeight: FontWeight.w900, height: 1.0)),
              const SizedBox(width: 3),
              if (cmp > price) Flexible(child: Text(cmp.toStringAsFixed(2),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 8.5,
                      color: Color(0xFF9A9A9A),
                      decoration: TextDecoration.lineThrough))),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ═══ Trust / Services strip (v2.1.57) ═════════════════════════════════
// "After-sales assurance | Secure payment | Logistics support" — items
// fully editable from the builder (icon + bilingual text + optional link).

class TrustStripBlock extends StatelessWidget {
  const TrustStripBlock({super.key, required this.p, required this.t,
      required this.ar});
  final Map<String, dynamic> p;
  final DynTheme t;
  final bool ar;

  @override
  Widget build(BuildContext context) {
    final items = ((p['items'] as List?) ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>()).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    final style = (p['style'] ?? 'plain').toString();
    // v2.1.60 — admin-chosen background: hex color, or 'none' for a
    // fully transparent strip.
    final rawBg = (p['strip_bg'] ?? '').toString().trim();
    final noBg = rawBg == 'none';
    final stripBg = (!noBg && rawBg.isNotEmpty)
        ? (_parseColor(rawBg) ?? Colors.white)
        : Colors.white;

    Widget cell(Map<String, dynamic> it, {bool card = false}) {
      final label = ((ar ? it['labelAr'] : it['labelEn'])
          ?? it['labelEn'] ?? '').toString();
      final w = Row(mainAxisSize: MainAxisSize.min, children: [
        Text((it['icon'] ?? '🛡️').toString(),
            style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 4),
        Flexible(child: Text(label, maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                color: t.dark.withValues(alpha: 0.85)))),
      ]);
      final inner = card
          ? Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F7F7),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFFEAEAEA)),
              ),
              child: w)
          : w;
      final link = (it['link'] as Map?)?.cast<String, dynamic>();
      if (link == null || (link['type'] ?? 'none') == 'none') return inner;
      return GestureDetector(
          onTap: () => openBlockLink(context, link), child: inner);
    }

    if (style == 'cards') {
      return SizedBox(height: 34, child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) => Center(child: cell(items[i], card: true)),
      ));
    }
    // plain / divided — evenly spread single row
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: noBg
          ? null
          : BoxDecoration(
              color: stripBg, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        for (var i = 0; i < items.length; i++) ...[
          Expanded(child: Center(child: cell(items[i]))),
          if (style == 'divided' && i != items.length - 1)
            Container(width: 1, height: 14, color: const Color(0xFFE5E5E5)),
        ],
      ]),
    );
  }
}
