// =============================================================================
// ProductCard — borderless tile used in home rails, category grids,
// wishlist, vendor store, related, search.
//
// Layout per latest spec:
//   • Image with discount badge (top-left) + heart/share (bottom-right)
//   • Name (2 lines)
//   • Current price + crossed-out original price INLINE (same row)
//   • Availability pill (right) — discount % NOT repeated here
//   • Bottom: save amount + (optional) rating
// =============================================================================
import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../api/uellow_api.dart';
import '../../api/uellow_models.dart';
import '../router/uellow_router.dart';
import '../theme/uellow_theme.dart';
import '../screens/product_screen.dart' show MidStrikePrice;

class ProductCard extends StatefulWidget {
  const ProductCard({
    super.key,
    required this.product,
    this.showStockLabel = true,
    this.inFlashSale = false,
    this.onTap,
    this.compact = false,
    this.hideSavePill = false,
    this.hideDiscount = false,
    this.rich = false,
  });

  final UellowProductCard product;
  final bool showStockLabel;
  final bool inFlashSale;
  final VoidCallback? onTap;
  // v2.0.79 — compact: smaller name + price + rating gap (shop screen
  // "All products" grid). hideSavePill: drop the bottom Save+Avail row.
  // v2.0.91 — hideDiscount: also drops the inline discount % pill, the
  // strikethrough compare price, AND the discount image badge for the
  // shop screen "Products" + "Recently arrived" rows per spec.
  final bool compact;
  final bool hideSavePill;
  final bool hideDiscount;
  // v2.1.26 — rich layout (category page): coins row, rating+price-trend
  // row, auto-rotating info ticker, availability/FREE/video bottom row.
  final bool rich;

  @override
  State<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<ProductCard> {
  bool _faved = false;

  @override
  void initState() {
    super.initState();
    // v2.1.29 — heart survives navigation: read the session cache.
    _faved = UellowApi.instance.wishlist.isCached(widget.product.id);
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final lang = UellowApi.instance.lang;
    final hasDiscount = product.comparePrice != null &&
        product.comparePrice!.amount > product.price.amount;
    final discountPct = product.discountPct;
    final saveAmount = hasDiscount
        ? product.comparePrice!.amount - product.price.amount : 0.0;

    return GestureDetector(
      onTap: widget.onTap ?? () => UellowRouter.goProduct(context, product.id),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: UellowRadius.all_lg,
          boxShadow: [
            BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: widget.rich
          ? _RichLayout(product: product, lang: lang,
              hasDiscount: hasDiscount, discountPct: discountPct,
              saveAmount: saveAmount, faved: _faved, onFav: _toggleFav)
          : widget.inFlashSale
          ? _FlashLayout(product: product, lang: lang,
              hasDiscount: hasDiscount, discountPct: discountPct,
              saveAmount: saveAmount, faved: _faved, onFav: _toggleFav)
          : _StdLayout(product: product, lang: lang,
              // v2.0.91 — when hideDiscount is set, pretend there is no
              // discount AT ALL so the image badge + inline pill + struck
              // compare price all vanish.
              hasDiscount: widget.hideDiscount ? false : hasDiscount,
              discountPct: widget.hideDiscount ? 0 : discountPct,
              saveAmount: saveAmount,
              showStockLabel: widget.hideSavePill ? false : widget.showStockLabel,
              hideSavePill: widget.hideSavePill,
              compact: widget.compact,
              faved: _faved, onFav: _toggleFav),
      ),
    );
  }

  Future<void> _toggleFav() async {
    final next = !_faved;
    setState(() => _faved = next);
    try {
      if (next) {
        await UellowApi.instance.wishlist.add(widget.product.id);
      } else {
        await UellowApi.instance.wishlist.remove(widget.product.id);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(next ? 'Added to wishlist' : 'Removed from wishlist'),
        duration: const Duration(seconds: 1),
      ));
    } on UellowApiException catch (e) {
      if (!mounted) return;
      setState(() => _faved = !next);   // revert
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

// ─── Standard card layout ──────────────────────────────────────────

class _StdLayout extends StatelessWidget {
  const _StdLayout({
    required this.product, required this.lang,
    required this.hasDiscount, required this.discountPct,
    required this.saveAmount, required this.showStockLabel,
    required this.faved, required this.onFav,
    this.compact = false, this.hideSavePill = false,
  });
  final UellowProductCard product;
  final String lang;
  final bool hasDiscount;
  final int discountPct;
  final double saveAmount;
  final bool showStockLabel;
  final bool faved;
  final VoidCallback onFav;
  // v2.0.79 — compact: smaller name + price + tighter gap. hideSavePill
  // drops the Save+Avail bottom row entirely (shop "All products" grid).
  // v2.0.79 — discount % now sits next to the STRUCK-THROUGH compare
  // price (not the current price) so "what you save" reads as a unit.
  final bool compact;
  final bool hideSavePill;

  @override
  Widget build(BuildContext context) {
    final nameFs   = compact ? 10.5 : 11.0;
    final nameH    = compact ? 26.0 : 30.0;
    final priceFs  = compact ? 12.0 : 13.5;
    final symFs    = compact ? 8.5  : 9.0;
    final cmpFs    = compact ? 8.5  : 9.0;
    final discFs   = compact ? 8.0  : 8.5;
    final padBetweenPriceAndStats = compact ? 2.0 : 4.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Image(product: product, hasDiscount: hasDiscount,
            discountPct: discountPct, faved: faved, onFav: onFav),
        Padding(
          padding: EdgeInsets.fromLTRB(8, compact ? 4 : 6, 8, compact ? 6 : 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: nameH,
                child: Text(product.name.current(lang),
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: nameFs, height: 1.25,
                      color: UellowColors.ink, fontWeight: FontWeight.w700,
                    )),
              ),
              SizedBox(height: compact ? 2 : 4),
              // Current price + currency, then (if discounted) compare price
              // with the -X% pill IMMEDIATELY adjacent — the user reads
              // "old price ̶7̶ -28%" together.
              Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                Text(product.price.amount.toStringAsFixed(3),
                    style: TextStyle(
                      fontSize: priceFs, fontWeight: FontWeight.w900,
                      color: UellowColors.ink, letterSpacing: -0.3,
                    )),
                const SizedBox(width: 3),
                Text(product.price.displaySymbol(lang),
                    style: TextStyle(
                      fontSize: symFs, fontWeight: FontWeight.w700,
                      color: UellowColors.muted,
                    )),
                if (hasDiscount) ...[
                  const SizedBox(width: 5),
                  Flexible(child: MidStrikePrice(
                      text: product.comparePrice!.amount.toStringAsFixed(3),
                      fontSize: cmpFs, color: Colors.black87)),
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: UellowColors.danger,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text('-$discountPct%',
                        style: TextStyle(
                          color: Colors.white, fontSize: discFs,
                          fontWeight: FontWeight.w900, height: 1.0,
                        )),
                  ),
                ],
              ]),
              // v2.1.25 — price-intelligence indicator (drop / lowest-90d).
              if (product.priceTrend != null) Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Builder(builder: (_) {
                  final t = product.priceTrend!;
                  final ar2 = lang.toLowerCase().startsWith('ar');
                  final lowest = t['is_lowest'] == true;
                  final down = t['direction'] == 'down';
                  final color = lowest
                      ? const Color(0xFFB8860B)
                      : (down ? UellowColors.successDk : UellowColors.danger);
                  final icon = lowest
                      ? Icons.workspace_premium_outlined
                      : (down ? Icons.trending_down : Icons.trending_up);
                  return Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(icon, size: 11, color: color),
                    const SizedBox(width: 3),
                    Flexible(child: Text(
                        (((t['label'] as Map?)?[ar2 ? 'ar' : 'en']) ?? '')
                            .toString(),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 9,
                            fontWeight: FontWeight.w800, color: color))),
                  ]);
                }),
              ),
              SizedBox(height: padBetweenPriceAndStats),
              _StatsRow(product: product, lang: lang),
              if (!hideSavePill) ...[
                const SizedBox(height: 6),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  if (hasDiscount)
                    Flexible(child: _SavePill(amount: saveAmount,
                        currency: product.price.displaySymbol(lang)))
                  else
                    const SizedBox.shrink(),
                  if (showStockLabel) _AvailPill(product: product),
                ]),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// v2.0.73 — compact stats line (rating · sales · views). All three are
// optional; the row collapses when nothing relevant is set.
class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.product, required this.lang});
  final UellowProductCard product;
  final String lang;

  String _fmtCount(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}k';
    return n.toString();
  }

  @override
  Widget build(BuildContext context) {
    final hasRating = product.rating.count > 0 || product.rating.avg > 0;
    final hasSold = product.soldCount > 0;
    final hasViews = product.viewCount > 0;
    if (!hasRating && !hasSold && !hasViews) return const SizedBox.shrink();
    final children = <Widget>[];
    if (hasRating) {
      children.addAll([
        const Icon(Icons.star_rounded, size: 11, color: Color(0xFFFFC107)),
        const SizedBox(width: 2),
        Text(product.rating.avg.toStringAsFixed(1),
            style: const TextStyle(fontSize: 9.5,
                fontWeight: FontWeight.w800, color: UellowColors.ink)),
        if (product.rating.count > 0) ...[
          const SizedBox(width: 2),
          Text('(${_fmtCount(product.rating.count)})',
              style: const TextStyle(fontSize: 9,
                  color: UellowColors.muted, fontWeight: FontWeight.w600)),
        ],
      ]);
    }
    if (hasSold) {
      if (children.isNotEmpty) children.add(const _Dot());
      children.addAll([
        const Icon(Icons.shopping_bag_outlined, size: 10,
            color: UellowColors.muted),
        const SizedBox(width: 2),
        Text(_fmtCount(product.soldCount),
            style: const TextStyle(fontSize: 9.5,
                fontWeight: FontWeight.w700, color: UellowColors.ink)),
      ]);
    }
    if (hasViews) {
      if (children.isNotEmpty) children.add(const _Dot());
      children.addAll([
        const Icon(Icons.visibility_outlined, size: 10,
            color: UellowColors.muted),
        const SizedBox(width: 2),
        Text(_fmtCount(product.viewCount),
            style: const TextStyle(fontSize: 9.5,
                fontWeight: FontWeight.w700, color: UellowColors.ink)),
      ]);
    }
    return Row(children: children);
  }
}

class _Dot extends StatelessWidget {
  const _Dot();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 5),
    child: Container(width: 2.5, height: 2.5,
        decoration: const BoxDecoration(
            color: UellowColors.muted, shape: BoxShape.circle)),
  );
}

// ─── Flash-sale layout — name hidden, big price row + save block ───

class _FlashLayout extends StatelessWidget {
  const _FlashLayout({
    required this.product, required this.lang,
    required this.hasDiscount, required this.discountPct, required this.saveAmount,
    required this.faved, required this.onFav,
  });
  final UellowProductCard product;
  final String lang;
  final bool hasDiscount;
  final int discountPct;
  final double saveAmount;
  final bool faved;
  final VoidCallback onFav;

  @override
  Widget build(BuildContext context) {
    // v2.0.62 — Compact pro design: smaller card, lighter typography,
    // styled "Save" pill, no bottom % badge.
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Image(product: product, hasDiscount: hasDiscount,
          discountPct: discountPct, faved: faved, onFav: onFav),
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Price row — smaller, refined
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(product.price.amount.toStringAsFixed(3),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900,
                    color: UellowColors.danger, letterSpacing: -0.2)),
            const SizedBox(width: 2),
            Padding(padding: const EdgeInsets.only(bottom: 1),
                child: Text(product.price.symbol,
                    style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800,
                        color: UellowColors.danger))),
            if (hasDiscount) ...[
              const SizedBox(width: 6),
              Padding(padding: const EdgeInsets.only(bottom: 2),
                  child: MidStrikePrice(
                      text: product.comparePrice!.amount.toStringAsFixed(3),
                      fontSize: 9, color: UellowColors.muted)),
            ],
          ]),
          if (hasDiscount) ...[
            const SizedBox(height: 5),
            // v2.0.65 — centered "Save X.XXX KD" pill in the flash card.
            Align(alignment: Alignment.center, child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.centerLeft, end: Alignment.centerRight,
                  colors: [Color(0xFFE6F7EF), Color(0xFFD4F0DD)]),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                    color: UellowColors.successDk.withValues(alpha: 0.18),
                    width: 0.6),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.discount_outlined, size: 9,
                    color: UellowColors.successDk),
                const SizedBox(width: 3),
                Text(lang == 'ar' ? 'وفّر' : 'Save',
                    style: const TextStyle(fontSize: 8.5,
                        fontWeight: FontWeight.w700,
                        color: UellowColors.successDk,
                        letterSpacing: 0.3)),
                const SizedBox(width: 3),
                Text(saveAmount.toStringAsFixed(3),
                    style: const TextStyle(fontSize: 9.5,
                        fontWeight: FontWeight.w900,
                        color: UellowColors.successDk)),
                const SizedBox(width: 2),
                Text(product.price.displaySymbol(lang),
                    style: const TextStyle(fontSize: 7.5,
                        fontWeight: FontWeight.w700,
                        color: UellowColors.successDk)),
              ]),
            )),
          ],
        ]),
      ),
    ]);
  }
}

// ─── Image + badges (shared) ───────────────────────────────────────

class _Image extends StatelessWidget {
  const _Image({
    required this.product, required this.hasDiscount,
    required this.discountPct, required this.faved, required this.onFav,
    this.clean = false,
  });
  final UellowProductCard product;
  final bool hasDiscount;
  final int discountPct;
  final bool faved;
  final VoidCallback onFav;
  // v2.1.28 — clean image for the rich card: discount %, free-shipping
  // and rank badges all moved off the photo per design.
  final bool clean;
  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: const Color(0xFFFAFAFA),
            child: CachedNetworkImage(
              imageUrl: product.image,
              fit: BoxFit.cover,
              placeholder: (_, __) => const ColoredBox(color: UellowColors.border),
              errorWidget: (_, __, ___) => const ColoredBox(color: UellowColors.border),
            ),
          ),
          if (discountPct > 0 && !clean) Positioned(
            top: 8, left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: UellowColors.danger,
                borderRadius: BorderRadius.circular(6),
                boxShadow: [BoxShadow(
                  color: UellowColors.danger.withValues(alpha: 0.5),
                  blurRadius: 8, offset: const Offset(0, 3),
                )],
              ),
              child: Text('-$discountPct%',
                  style: const TextStyle(
                    color: Colors.white, fontSize: 10,
                    fontWeight: FontWeight.w800, letterSpacing: 0.3,
                  )),
            ),
          ),
          if (product.hasVideo && !clean) Positioned(
            top: 8, right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(6),
                boxShadow: const [BoxShadow(
                  color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 2),
                )],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 12),
                const SizedBox(width: 2),
                Text(UellowApi.instance.lang.toLowerCase().startsWith('ar')
                    ? 'فيديو' : 'VIDEO',
                    style: const TextStyle(color: Colors.white, fontSize: 9,
                        fontWeight: FontWeight.w900, letterSpacing: 0.4)),
              ]),
            ),
          ),
          // v2.1.24 — Best Seller rank badge (gold, Amazon-style).
          if (product.rank != null && !clean) Positioned(
            top: 8, left: 8, right: 8,
            child: Align(
              alignment: AlignmentDirectional.topStart,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFFFFD700), Color(0xFFE8A800)]),
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: const [BoxShadow(
                    color: Color(0x44000000), blurRadius: 4, offset: Offset(0, 2),
                  )],
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Text('🏆', style: TextStyle(fontSize: 9)),
                  const SizedBox(width: 3),
                  Flexible(child: Text(
                      (((product.rank!['label'] as Map?)?[
                          UellowApi.instance.lang.toLowerCase().startsWith('ar')
                              ? 'ar' : 'en']) ?? '').toString(),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF412402), fontSize: 8.5,
                        fontWeight: FontWeight.w900, letterSpacing: 0.2,
                      ))),
                ]),
              ),
            ),
          ),
          // v2.0.82 — Free shipping badge (when the product is tagged)
          if (product.badges.contains('free_shipping') && !clean) Positioned(
            bottom: 8, left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: UellowColors.yellow,
                borderRadius: BorderRadius.circular(6),
                boxShadow: const [BoxShadow(
                  color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 2),
                )],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.local_shipping_outlined, size: 11,
                    color: UellowColors.darkBrown),
                const SizedBox(width: 3),
                Text(UellowApi.instance.lang.toLowerCase().startsWith('ar')
                    ? 'شحن مجاني' : 'FREE SHIP',
                    style: const TextStyle(
                      color: UellowColors.darkBrown, fontSize: 9,
                      fontWeight: FontWeight.w900, letterSpacing: 0.3,
                    )),
              ]),
            ),
          ),
          Positioned(bottom: 8, right: 8,
            child: _HeartBtn(filled: faved, onTap: onFav)),
        ],
      ),
    );
  }
}

class _HeartBtn extends StatelessWidget {
  const _HeartBtn({required this.filled, required this.onTap});
  final bool filled;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 32, height: 32,
        decoration: BoxDecoration(
          color: filled ? UellowColors.danger : const Color(0xF2FFFFFF),
          shape: BoxShape.circle,
          boxShadow: const [BoxShadow(color: Color(0x14000000),
              blurRadius: 6, offset: Offset(0, 2))],
        ),
        child: Icon(filled ? Icons.favorite : Icons.favorite_border,
            size: 16,
            color: filled ? Colors.white : UellowColors.muted),
      ),
    );
  }
}

class _RatingRow extends StatelessWidget {
  const _RatingRow({required this.rating});
  final UellowRating rating;
  @override
  Widget build(BuildContext context) {
    final avgRounded = rating.avg.round();
    return Row(children: [
      for (var i = 0; i < 5; i++) Padding(
        padding: const EdgeInsets.only(right: 1),
        child: Icon(
          i < avgRounded ? Icons.star : Icons.star_border,
          size: 11,
          color: i < avgRounded ? UellowColors.yellow
                                : const Color(0xFFCFCFCF),
        ),
      ),
      const SizedBox(width: 3),
      Text(rating.count > 0 ? rating.avg.toStringAsFixed(1) : '0.0',
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
              color: UellowColors.ink)),
      const SizedBox(width: 3),
      Text('(${rating.count})',
          style: const TextStyle(fontSize: 10.5, color: UellowColors.muted)),
    ]);
  }
}

class _SavePill extends StatelessWidget {
  const _SavePill({required this.amount, required this.currency});
  final double amount;
  final String currency;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: UellowColors.successBg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.local_offer_outlined, size: 10,
            color: UellowColors.successDk),
        const SizedBox(width: 3),
        Text('${amount.toStringAsFixed(3)} $currency',
            style: const TextStyle(fontSize: 10,
                fontWeight: FontWeight.w900, color: UellowColors.successDk)),
      ]),
    );
  }
}

class _AvailPill extends StatelessWidget {
  const _AvailPill({required this.product});
  final UellowProductCard product;
  @override
  Widget build(BuildContext context) {
    final qty = product.qtyAvailable;
    final allowOos = product.allowOutOfStockOrder;
    final ar = UellowApi.instance.lang.toLowerCase().startsWith('ar');
    Color bg, fg; String text;
    if (allowOos) {
      bg = UellowColors.successBg; fg = UellowColors.successDk;
      text = ar ? 'متاح' : 'Available';
    } else if (qty != null && qty <= 0) {
      bg = UellowColors.dangerBg; fg = UellowColors.dangerDk;
      text = ar ? 'نفد' : 'OUT';
    } else if (qty != null && qty <= 5) {
      bg = UellowColors.warnBg; fg = UellowColors.warn;
      text = ar ? 'بقي $qty' : 'Only $qty';
    } else {
      bg = UellowColors.successBg; fg = UellowColors.successDk;
      text = ar ? 'متاح' : 'Available';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(text,
          style: TextStyle(color: fg, fontSize: 9.5,
              fontWeight: FontWeight.w900, letterSpacing: 0.5)),
    );
  }
}


// ─── Rich layout (v2.1.26 — category page) ──────────────────────────
// image → promo coins → name(2) → price row → rating + price-trend →
// rotating info ticker → availability / FREE / video bottom row.

class _RichLayout extends StatelessWidget {
  const _RichLayout({
    required this.product, required this.lang,
    required this.hasDiscount, required this.discountPct,
    required this.saveAmount, required this.faved, required this.onFav,
  });
  final UellowProductCard product;
  final String lang;
  final bool hasDiscount;
  final int discountPct;
  final double saveAmount;
  final bool faved;
  final VoidCallback onFav;

  @override
  Widget build(BuildContext context) {
    final ar = lang.toLowerCase().startsWith('ar');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // v2.1.28 — clean photo: no discount/free-ship/rank overlays.
        _Image(product: product, hasDiscount: hasDiscount,
            discountPct: discountPct, faved: faved, onFav: onFav,
            clean: true),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // ── name (2 lines) — promo coin inline BEFORE the name ──
            SizedBox(height: 30, child: Text.rich(TextSpan(children: [
              if (product.promo != null) WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Container(
                  margin: const EdgeInsetsDirectional.only(end: 4),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: _hex(product.promo!['bg'], const Color(0xFFFFF8E1)),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${product.promo!['emoji'] ?? ''} '
                    '${((product.promo!['label'] as Map?)?[lang.toLowerCase().startsWith('ar') ? 'ar' : 'en'] ?? '')}',
                    style: TextStyle(fontSize: 7.5,
                        fontWeight: FontWeight.w900,
                        color: _hex(product.promo!['fg'],
                            const Color(0xFF8B6508))),
                  ),
                ),
              ),
              TextSpan(text: product.name.current(lang)),
            ]),
                maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, height: 1.25,
                    color: UellowColors.ink, fontWeight: FontWeight.w700))),
            const SizedBox(height: 2),
            // ── price row ──
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Text(product.price.amount.toStringAsFixed(3),
                  style: const TextStyle(fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                      color: UellowColors.ink, letterSpacing: -0.3)),
              const SizedBox(width: 3),
              Text(product.price.displaySymbol(lang),
                  style: const TextStyle(fontSize: 9,
                      fontWeight: FontWeight.w700, color: UellowColors.muted)),
              if (hasDiscount) ...[
                const SizedBox(width: 5),
                Flexible(child: MidStrikePrice(
                    text: product.comparePrice!.amount.toStringAsFixed(3),
                    fontSize: 9, color: Colors.black87)),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                  decoration: BoxDecoration(color: UellowColors.danger,
                      borderRadius: BorderRadius.circular(3)),
                  child: Text('-$discountPct%', style: const TextStyle(
                      color: Colors.white, fontSize: 8.5,
                      fontWeight: FontWeight.w900, height: 1.0)),
                ),
              ],
            ]),
            const SizedBox(height: 2),
            // ── FULL 5 stars + (count) + price-intelligence indicator ──
            SizedBox(height: 14, child: Row(children: [
              for (var i = 0; i < 5; i++) Icon(
                i < product.rating.avg.round()
                    ? Icons.star_rounded : Icons.star_outline_rounded,
                size: 11,
                color: i < product.rating.avg.round()
                    ? const Color(0xFFFFC107) : const Color(0xFFCFCFCF),
              ),
              const SizedBox(width: 3),
              Text('(${product.rating.count})', style: const TextStyle(
                  fontSize: 9, color: UellowColors.muted,
                  fontWeight: FontWeight.w600)),
              if (product.priceTrend != null) ...[
                const SizedBox(width: 6),
                Builder(builder: (_) {
                  final t = product.priceTrend!;
                  final dir = (t['direction'] ?? 'stable').toString();
                  final lowest = t['is_lowest'] == true;
                  final down = dir == 'down' || lowest;
                  final stable = dir == 'stable' && !lowest;
                  // v2.1.28 — stable gets its OWN look (flat blue icon).
                  final color = stable
                      ? const Color(0xFF1565C0)
                      : (down ? UellowColors.successDk : UellowColors.danger);
                  final icon = stable
                      ? Icons.trending_flat
                      : (down ? Icons.arrow_downward : Icons.arrow_upward);
                  final pct = (t['change_pct'] as num?)?.toDouble() ?? 0;
                  return Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(icon, size: 11, color: color),
                    if (!stable && pct > 0) Text('${pct.toStringAsFixed(0)}%',
                        style: TextStyle(fontSize: 9,
                            fontWeight: FontWeight.w800, color: color)),
                  ]);
                }),
              ],
            ])),
            const SizedBox(height: 2),
            // ── rotating info ticker ──
            SizedBox(height: 14, child: _InfoTicker(
                product: product, ar: ar,
                saveAmount: hasDiscount ? saveAmount : 0)),
            const SizedBox(height: 3),
            // ── bottom: availability + promo coins + free ship + video ──
            SizedBox(height: 17, child: Row(children: [
              _AvailPill(product: product),
              const SizedBox(width: 4),
              Expanded(child: _CoinsRow(product: product, ar: ar)),
              if (product.badges.contains('free_shipping')) Container(
                margin: const EdgeInsetsDirectional.only(start: 4),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: UellowColors.yellow,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.local_shipping_outlined, size: 10,
                      color: UellowColors.darkBrown),
                  const SizedBox(width: 2),
                  Text(ar ? 'شحن مجاني' : 'FREE',
                      style: const TextStyle(fontSize: 7.5,
                          fontWeight: FontWeight.w900,
                          color: UellowColors.darkBrown, letterSpacing: 0.2)),
                ]),
              ),
              if (product.hasVideo) Container(
                margin: const EdgeInsetsDirectional.only(start: 4),
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.75),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.play_arrow_rounded,
                    size: 10, color: Colors.white),
              ),
            ])),
          ]),
        ),
      ],
    );
  }
}

Color _hex(Object? raw, Color fallback) {
  try {
    var s = (raw ?? '').toString().replaceAll('#', '');
    if (s.length == 6) s = 'FF$s';
    return Color(int.parse(s, radix: 16));
  } catch (_) {
    return fallback;
  }
}

class _CoinsRow extends StatelessWidget {
  const _CoinsRow({required this.product, required this.ar});
  final UellowProductCard product;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    final coins = <Widget>[];
    void coin(String emoji, String label, Color bg, Color fg) {
      coins.add(Container(
        margin: const EdgeInsetsDirectional.only(end: 4),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
        decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(emoji, style: const TextStyle(fontSize: 8)),
          const SizedBox(width: 2),
          Text(label, style: TextStyle(fontSize: 7.5,
              fontWeight: FontWeight.w900, color: fg, letterSpacing: 0.2)),
        ]),
      ));
    }
    if (product.priceTrend?['is_lowest'] == true) {
      coin('🔥', ar ? 'أقل سعر' : 'LOWEST', const Color(0xFFFFF3E0),
          const Color(0xFFBF360C));
    }
    if (product.badges.contains('sale')) {
      coin('⚡', ar ? 'عرض' : 'SALE', const Color(0xFFFFEBEE),
          const Color(0xFFC62828));
    }
    if ((product.rank?['rank'] ?? 99) == 1) {
      coin('🏆', ar ? 'الأفضل' : 'BEST', const Color(0xFFFFF8E1),
          const Color(0xFF8B6508));
    }
    if (product.badges.contains('new')) {
      coin('✨', ar ? 'جديد' : 'NEW', const Color(0xFFE3F2FD),
          const Color(0xFF1565C0));
    }
    if (coins.isEmpty) return const SizedBox.shrink();
    return ListView(scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(), children: coins);
  }
}

/// Vertically rotating one-line ticker (slides up every ~2.4 s) with the
/// card's soft facts: save amount, fast delivery, views, sales, rank.
class _InfoTicker extends StatefulWidget {
  const _InfoTicker({required this.product, required this.ar,
      required this.saveAmount});
  final UellowProductCard product;
  final bool ar;
  final double saveAmount;
  @override
  State<_InfoTicker> createState() => _InfoTickerState();
}

class _InfoTickerState extends State<_InfoTicker> {
  late final List<String> _items;
  int _i = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    final ar = widget.ar;
    // v2.1.30 — views + cart-adds added; trimmed phrases; ENDLESS loop.
    _items = [
      if (widget.saveAmount > 0)
        (ar ? '💰 وفّر ${widget.saveAmount.toStringAsFixed(3)} ${p.price.displaySymbol("ar")} الآن'
            : '💰 Save ${widget.saveAmount.toStringAsFixed(3)} ${p.price.displaySymbol("en")} now'),
      ar ? '🚚 توصيل سريع خلال ساعات' : '🚚 Fast delivery in hours',
      if (p.viewCount > 0)
        (ar ? '👁 شاهده ${_fmt(p.viewCount)} شخص'
            : '👁 Viewed by ${_fmt(p.viewCount)} people'),
      if (p.cartAdds > 0)
        (ar ? '🛒 أضافه ${_fmt(p.cartAdds)} شخص للسلة'
            : '🛒 ${_fmt(p.cartAdds)} people added to cart'),
      if (p.soldCount > 0)
        (ar ? '✅ أكثر من ${_fmt(p.soldCount)} عملية شراء'
            : '✅ Over ${_fmt(p.soldCount)} purchases'),
      if (p.rank != null)
        (ar ? '🏆 الأفضل مبيعاً في ${_short((p.rank!['category'] as Map?)?['ar'] ?? '')}'
            : '🏆 Best seller in ${_short((p.rank!['category'] as Map?)?['en'] ?? '')}'),
    ];
    _scheduleNext();
  }

  // Self-rescheduling chain — survives anything Timer.periodic might
  // silently drop; the rotation NEVER stops.
  void _scheduleNext() {
    if (_items.length <= 1) return;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 2400), () {
      if (!mounted) return;
      setState(() => _i = (_i + 1) % _items.length);
      _scheduleNext();
    });
  }

  String _fmt(int n) => n >= 1000
      ? '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}K' : '$n';
  String _short(Object s) {
    final t = s.toString();
    return t.length > 16 ? '${t.substring(0, 15)}…' : t;
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    return ClipRect(child: AnimatedSwitcher(
      duration: const Duration(milliseconds: 380),
      transitionBuilder: (child, anim) => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1), end: Offset.zero).animate(anim),
        child: FadeTransition(opacity: anim, child: child),
      ),
      child: Align(
        key: ValueKey(_i),
        alignment: AlignmentDirectional.centerStart,
        child: Text(_items[_i],
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 9.5,
                fontWeight: FontWeight.w500,   // deliberately NOT bold
                color: UellowColors.text)),
      ),
    ));
  }
}
