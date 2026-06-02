// =============================================================================
// Dynamic block extras — block envelope (bg + pattern + title + spacing) and
// the new block variants introduced in v2.0.34 (Quick Pills, Themed Promo,
// Mini Category Cards, Welcome Deal, Discount Strip, Promo Pills).
//
// Each new widget is keyed by a `kind` string the builder writes into
// blocks_json. The dispatcher in dynamic_page_screen.dart fans out here.
// =============================================================================
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../router/uellow_router.dart';
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

    // Wrap child in a RepaintBoundary so its repaints don't bleed into
    // siblings (a Timer-driven block won't force the whole list to repaint).
    Widget content = RepaintBoundary(child: child);

    if (hasBg) {
      content = Stack(children: [
        Positioned.fill(
          child: _BackgroundLayer(
            color: bgColor,
            pattern: pattern,
            imageUrl: bgImage,
            patternColor: theme?.dark ?? const Color(0xFF412402),
          ),
        ),
        content,
      ]);
    }

    return Padding(
      padding: EdgeInsets.symmetric(vertical: padY),
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
              color: patternColor.withOpacity(0.08),
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
    final p = Paint()..color = color;
    switch (kind) {
      case 'dots':
        for (double y = 8; y < size.height; y += 18) {
          for (double x = 8; x < size.width; x += 18) {
            canvas.drawCircle(Offset(x, y), 1.4, p);
          }
        }
        break;
      case 'lines':
        p.strokeWidth = 1;
        for (double y = 0; y < size.height; y += 14) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
        }
        break;
      case 'grid':
        p.strokeWidth = 1;
        for (double y = 0; y < size.height; y += 20) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
        }
        for (double x = 0; x < size.width; x += 20) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
        }
        break;
      case 'mesh':
        p.strokeWidth = 1;
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
  });
  final Map<String, dynamic> props;
  final DynTheme theme;
  final bool ar;
  final String fallbackEn;
  final Widget? trailing;

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
    return Padding(
      padding: EdgeInsets.fromLTRB(
        14, 6, 14, (props['title_gap'] as num?)?.toDouble() ?? 6,
      ),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
          ),
        ),
        if (trailing != null) trailing!,
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
    final items = (p['pills'] as List? ?? const []).cast<dynamic>();
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Row(
        children: List.generate(items.length, (i) {
          final it = (items[i] as Map).cast<String, dynamic>();
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(left: i == 0 ? 0 : 5, right: i == items.length - 1 ? 0 : 5),
              child: _PromoPill(it: it, t: t, ar: ar),
            ),
          );
        }),
      ),
    );
  }
}

class _PromoPill extends StatelessWidget {
  const _PromoPill({required this.it, required this.t, required this.ar});
  final Map<String, dynamic> it;
  final DynTheme t;
  final bool ar;

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
    return GestureDetector(
      onTap: () => _openLink(context, (it['link'] as Map?)?.cast<String, dynamic>()),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w900,
                      color: t.dark,
                    )),
                if (sub.isNotEmpty)
                  Text(sub,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: t.dark.withOpacity(0.65),
                        fontWeight: FontWeight.w600,
                      )),
              ],
            ),
          ),
        ]),
      ),
    );
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
    final img = (c['image_url'] as String?) ?? '';
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
class DiscountStripBlock extends StatelessWidget {
  const DiscountStripBlock({super.key, required this.p, required this.data, required this.t, required this.ar});
  final Map<String, dynamic> p;
  final Map<String, dynamic> data;
  final DynTheme t;
  final bool ar;

  @override
  Widget build(BuildContext context) {
    final products = (data['products'] as List? ?? const []).cast<dynamic>();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DynSectionHeader(props: p, theme: t, ar: ar, fallbackEn: 'Hot deals'),
      SizedBox(
        height: 180,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          itemCount: products.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final pp = (products[i] as Map).cast<String, dynamic>();
            return _DiscountCard(p: pp, t: t, ar: ar);
          },
        ),
      ),
    ]);
  }
}

class _DiscountCard extends StatelessWidget {
  const _DiscountCard({required this.p, required this.t, required this.ar});
  final Map<String, dynamic> p;
  final DynTheme t;
  final bool ar;

  @override
  Widget build(BuildContext context) {
    final img = (p['image'] as String?) ?? '';
    final price = ((p['price'] as Map?)?.cast<String, dynamic>())?['display']?.toString() ?? '';
    final compare = ((p['compare_price'] as Map?)?.cast<String, dynamic>())?['display']?.toString();
    int discount = 0;
    final priceVal = ((p['price'] as Map?)?.cast<String, dynamic>())?['amount'];
    final compareVal = ((p['compare_price'] as Map?)?.cast<String, dynamic>())?['amount'];
    if (priceVal is num && compareVal is num && compareVal > 0 && compareVal > priceVal) {
      discount = ((1 - priceVal / compareVal) * 100).round();
    }
    return GestureDetector(
      onTap: () {
        final id = (p['id'] as num?)?.toInt();
        if (id != null && id > 0) UellowRouter.goProduct(context, id);
      },
      child: Container(
        width: 134,
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(10),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AspectRatio(
            aspectRatio: 1,
            child: img.isNotEmpty
                ? CachedNetworkImage(imageUrl: img, fit: BoxFit.cover)
                : Container(color: const Color(0xFFF1EBDF)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(price,
                  style: TextStyle(
                    color: t.dark, fontWeight: FontWeight.w900, fontSize: 13,
                  )),
              const SizedBox(height: 3),
              Row(children: [
                if (discount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE63946),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('-$discount%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 10.5,
                        )),
                  ),
                if (compare != null && compare.isNotEmpty) ...[
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(compare,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: t.dark.withOpacity(0.45),
                          fontSize: 10.5,
                          decoration: TextDecoration.lineThrough,
                          fontWeight: FontWeight.w600,
                        )),
                  ),
                ],
              ]),
            ]),
          ),
        ]),
      ),
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
    final img = (c['image_url'] as String?) ?? '';
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
