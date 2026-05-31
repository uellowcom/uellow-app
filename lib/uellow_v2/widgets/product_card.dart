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
  });

  final UellowProductCard product;
  final bool showStockLabel;
  final bool inFlashSale;
  final VoidCallback? onTap;

  @override
  State<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<ProductCard> {
  bool _faved = false;

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
        child: widget.inFlashSale
          ? _FlashLayout(product: product, lang: lang,
              hasDiscount: hasDiscount, discountPct: discountPct,
              saveAmount: saveAmount, faved: _faved, onFav: _toggleFav)
          : _StdLayout(product: product, lang: lang,
              hasDiscount: hasDiscount, discountPct: discountPct,
              saveAmount: saveAmount, showStockLabel: widget.showStockLabel,
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
  });
  final UellowProductCard product;
  final String lang;
  final bool hasDiscount;
  final int discountPct;
  final double saveAmount;
  final bool showStockLabel;
  final bool faved;
  final VoidCallback onFav;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Image(product: product, hasDiscount: hasDiscount,
            discountPct: discountPct, faved: faved, onFav: onFav),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Single-line name — more room for the price + meta below.
              Text(product.name.current(lang),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11, height: 1.25, color: UellowColors.ink,
                    fontWeight: FontWeight.w700,
                  )),
              const SizedBox(height: 4),
              // Price row — current + crossed-out original, INLINE
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(product.price.amount.toStringAsFixed(3),
                    style: const TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.w900,
                      color: UellowColors.ink, letterSpacing: -0.3,
                    )),
                const SizedBox(width: 3),
                Padding(padding: const EdgeInsets.only(bottom: 1),
                    child: Text(product.price.displaySymbol(lang),
                        style: const TextStyle(
                          fontSize: 9.5, fontWeight: FontWeight.w700,
                          color: UellowColors.muted,
                        ))),
                if (hasDiscount) ...[
                  const SizedBox(width: 5),
                  Padding(padding: const EdgeInsets.only(bottom: 1),
                      child: MidStrikePrice(
                          text: product.comparePrice!.amount.toStringAsFixed(3),
                          fontSize: 10, color: UellowColors.muted)),
                ],
              ]),
              const SizedBox(height: 4),
              _RatingRow(rating: product.rating),
              const SizedBox(height: 4),
              // Bottom row — save amount + availability
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                if (hasDiscount)
                  _SavePill(amount: saveAmount, currency: product.price.displaySymbol(lang))
                else
                  const SizedBox.shrink(),
                if (showStockLabel) _AvailPill(product: product),
              ]),
            ],
          ),
        ),
      ],
    );
  }
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
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Image(product: product, hasDiscount: hasDiscount,
          discountPct: discountPct, faved: faved, onFav: onFav),
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Price row — current + crossed-out original next to each other
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(product.price.amount.toStringAsFixed(3),
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900,
                    color: UellowColors.danger, letterSpacing: -0.3)),
            const SizedBox(width: 3),
            Padding(padding: const EdgeInsets.only(bottom: 2),
                child: Text(product.price.symbol,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
                        color: UellowColors.danger))),
            if (hasDiscount) ...[
              const SizedBox(width: 8),
              Padding(padding: const EdgeInsets.only(bottom: 3),
                  child: MidStrikePrice(
                      text: product.comparePrice!.amount.toStringAsFixed(3),
                      fontSize: 12, color: UellowColors.muted)),
            ],
          ]),
          if (hasDiscount) ...[
            const SizedBox(height: 6),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: UellowColors.danger,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text('-$discountPct%',
                    style: const TextStyle(color: Colors.white,
                        fontSize: 10, fontWeight: FontWeight.w900)),
              ),
              const SizedBox(width: 6),
              Text(lang == 'ar'
                  ? 'وفّر ${saveAmount.toStringAsFixed(3)} ${product.price.displaySymbol(lang)}'
                  : 'Save ${saveAmount.toStringAsFixed(3)} ${product.price.displaySymbol(lang)}',
                  style: const TextStyle(fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: UellowColors.successDk)),
            ]),
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
  });
  final UellowProductCard product;
  final bool hasDiscount;
  final int discountPct;
  final bool faved;
  final VoidCallback onFav;
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
          if (discountPct > 0) Positioned(
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
          if (product.hasVideo) Positioned(
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
              child: Row(mainAxisSize: MainAxisSize.min, children: const [
                Icon(Icons.play_arrow_rounded, color: Colors.white, size: 12),
                SizedBox(width: 2),
                Text('VIDEO',
                    style: TextStyle(color: Colors.white, fontSize: 9,
                        fontWeight: FontWeight.w900, letterSpacing: 0.4)),
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
    Color bg, fg; String text;
    // Continue-sale → always show GREEN "Available" even at 0 qty.
    if (allowOos) {
      bg = UellowColors.successBg; fg = UellowColors.successDk; text = 'Available';
    } else if (qty != null && qty <= 0) {
      bg = UellowColors.dangerBg; fg = UellowColors.dangerDk; text = 'OUT';
    } else if (qty != null && qty <= 5) {
      bg = UellowColors.warnBg; fg = UellowColors.warn; text = 'Only $qty';
    } else {
      bg = UellowColors.successBg; fg = UellowColors.successDk; text = 'Available';
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
