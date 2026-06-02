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
    // Resolver returns `items` (matches resolve_products). Older alias
    // `products` kept for forward compatibility with any seed data.
    final products = (data['items'] as List? ?? data['products'] as List? ?? const []).cast<dynamic>();
    if (products.isEmpty) return const SizedBox.shrink();
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
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // ─── Header row ────────────────────────────────────────────────────
          if ((widget.p['show_title'] != false) && title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
              child: Row(children: [
                Icon(Icons.explore_outlined, size: 18, color: t.dark),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(title, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: t.dark, fontSize: 16, fontWeight: FontWeight.w900)),
                ),
                if (sub.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(sub, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: t.dark.withOpacity(0.55), fontSize: 12)),
                  ),
                ],
                if (_showShuffle) ...[
                  const Spacer(),
                  InkWell(
                    onTap: _shuffle, borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: UellowColors.yellowSoft,
                        border: Border.all(color: UellowColors.yellow),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.shuffle, size: 13, color: UellowColors.darkBrown),
                        SizedBox(width: 4),
                        Text('Shuffle', style: TextStyle(
                            color: UellowColors.darkBrown, fontSize: 11, fontWeight: FontWeight.w800)),
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
              padding: const EdgeInsets.fromLTRB(40, 12, 40, 6),
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
          childAspectRatio: _columns == 2 ? 0.58 : 0.52,
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
      ProductCard(product: product),
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
            child: const Text('AD',
                style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900)),
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
    final img = (slide['image_url'] as String?) ?? '';
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
    return Container(
      decoration: widget.p['sticky'] == true
          ? BoxDecoration(color: Colors.white,
              boxShadow: [BoxShadow(color: t.dark.withValues(alpha: 0.06), blurRadius: 6, offset: const Offset(0,2))])
          : null,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        physics: const ClampingScrollPhysics(),
        child: Row(children: [
          for (int i = 0; i < tabs.length; i++) _tab(tabs[i] as Map, i, style, t),
        ]),
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
        margin: EdgeInsets.only(right: style == 'underline' ? 18 : 6),
        padding: style == 'underline'
            ? const EdgeInsets.symmetric(vertical: 6)
            : const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
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
            final img = (b['image_url'] as String?) ?? '';
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
    final url = (m['image_url'] as String?) ?? '';
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
