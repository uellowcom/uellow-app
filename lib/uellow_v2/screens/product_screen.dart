// =============================================================================
// ProductScreen — fully wired to v2 API. Real sold/views, brand block,
// bulk pricing, real description, real specs, paginated reviews, infinite
// load related, working share + wishlist + delivery sheet.
// =============================================================================
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../api/uellow_api.dart';
import '../../api/uellow_models.dart';
import '../router/uellow_router.dart';
import '../theme/uellow_l10n.dart';
import '../theme/uellow_theme.dart';
import '../widgets/flash_banner.dart';
import '../widgets/product_card.dart';

class ProductScreen extends StatefulWidget {
  const ProductScreen({super.key, required this.productId});
  final int productId;
  @override
  State<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends State<ProductScreen> {
  late Future<UellowProductFull> _future;
  int _galleryPage = 0;
  int _selectedColor = 0;
  String _selectedSize = '';
  int _qty = 1;
  bool _inWishlist = false;

  @override
  void initState() {
    super.initState();
    _future = UellowApi.instance.products.detail(widget.productId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UellowColors.bg,
      body: SafeArea(bottom: false, child: FutureBuilder<UellowProductFull>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(
                child: CircularProgressIndicator(color: UellowColors.darkBrown));
          }
          if (snap.hasError) {
            return Center(child: Padding(
              padding: const EdgeInsets.all(30),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.error_outline, size: 56, color: UellowColors.muted),
                const SizedBox(height: 14),
                Text(snap.error.toString(), textAlign: TextAlign.center, style: UT.body),
              ]),
            ));
          }
          return _buildScroll(snap.data!);
        },
      )),
      // Beena now lives in the bottom CTA bar — no floating button needed
      bottomSheet: FutureBuilder<UellowProductFull>(
        future: _future,
        builder: (_, snap) {
          if (!snap.hasData) return const SizedBox.shrink();
          return _CtaBar(
            product: snap.data!, qty: _qty,
            onQty: (q) => setState(() => _qty = q),
          );
        },
      ),
    );
  }

  Widget _buildScroll(UellowProductFull p) {
    // Build a gallery that respects the selected color: if there's a
    // color attribute, swap the first image to the selected swatch's
    // variant image.
    final colorLine = p.attributes.where(
      (a) {
        final n = a.attributeName.current(UellowApi.instance.lang).toLowerCase();
        return n.contains('color') || n.contains('لون');
      },
    ).firstOrNull;
    final selectedColorVal = (colorLine != null
        && colorLine.values.isNotEmpty
        && _selectedColor < colorLine.values.length)
        ? colorLine.values[_selectedColor] : null;
    var gallery = List<String>.from(p.images);
    if (selectedColorVal?.image != null && selectedColorVal!.image!.isNotEmpty) {
      // Hoist the color image to the front of the gallery
      gallery = [selectedColorVal.image!, ...gallery.where((u) => u != selectedColorVal.image)];
    }

    return CustomScrollView(slivers: [
      SliverToBoxAdapter(child: _Gallery(
        images: gallery, videos: p.videos, page: _galleryPage,
        onChanged: (i) => setState(() => _galleryPage = i),
        onShare: () => Share.share(
          'Check out ${p.name.current(UellowApi.instance.lang)} on Uellow\n'
          'https://www.uellow.com/shop/${p.slug}',
          subject: p.name.current(UellowApi.instance.lang),
        ),
        inWishlist: _inWishlist,
        onWishlist: () async {
          try {
            if (_inWishlist) {
              await UellowApi.instance.wishlist.remove(p.id);
            } else {
              await UellowApi.instance.wishlist.add(p.id);
            }
            if (mounted) setState(() => _inWishlist = !_inWishlist);
          } on UellowApiException catch (e) {
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(e.message)));
          }
        },
      )),
      if (p.flashEndsAt != null) SliverToBoxAdapter(
        // Full-width, edge-to-edge — no horizontal padding, no rounded
        // corners, no internal margins so the timer can never overlap
        // the headline text. Uses the wide flash banner variant.
        child: FlashBanner(endsAt: p.flashEndsAt, compact: false, edgeToEdge: true),
      ),
      SliverToBoxAdapter(child: _Title(p: p)),
      SliverToBoxAdapter(child: _PriceRow(p: p)),
      if (p.vendor != null) SliverToBoxAdapter(child: _VendorCard(vendor: p.vendor!)),
      SliverToBoxAdapter(child: _Attributes(
        productId: p.id,
        attributes: p.attributes,
        selectedColor: _selectedColor,
        selectedSize: _selectedSize,
        onColor: (i) => setState(() {
          _selectedColor = i;
          _galleryPage = 0;   // jump gallery back to the new color image
        }),
        onSize: (s) => setState(() => _selectedSize = s),
      )),
      SliverToBoxAdapter(child: _CompactDelivery(
          onTap: () => _showDeliverySheet(context))),
      // Brand block sits below shipping info per latest spec
      if (p.brand != null) SliverToBoxAdapter(child: _BrandBlock(brand: p.brand!)),
      // Show whenever there's at least one bulk tier — even a single
      // "buy 5+ → save 5%" hint is useful.
      if (p.bulkPricing.isNotEmpty)
        SliverToBoxAdapter(child: _BulkPricing(tiers: p.bulkPricing)),
      SliverToBoxAdapter(child: _DescriptionBlock(product: p)),
      SliverToBoxAdapter(child: _SpecsBlock(product: p,
          onOpen: () => _showSpecsDialog(context, p))),
      SliverToBoxAdapter(child: _ReviewsBlock(productId: p.id)),
      SliverToBoxAdapter(child: _RelatedInfinite(
          productId: p.id,
          categoryId: p.categories.isNotEmpty ? p.categories.first.id : null)),
      const SliverToBoxAdapter(child: SizedBox(height: 80)),
    ]);
  }

  void _showDeliverySheet(BuildContext context) {
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DeliveryDialog(),
    );
  }

  void _showSpecsDialog(BuildContext context, UellowProductFull p) {
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SpecsDialog(p: p),
    );
  }
}

// ─── Gallery ───────────────────────────────────────────────────────

class _Gallery extends StatelessWidget {
  const _Gallery({
    required this.images, required this.videos,
    required this.page, required this.onChanged,
    required this.onShare, required this.onWishlist, required this.inWishlist,
  });
  final List<String> images;
  final List<UellowProductVideo> videos;
  final int page;
  final ValueChanged<int> onChanged;
  final VoidCallback onShare, onWishlist;   // onShare currently unused
  final bool inWishlist;
  // Unified gallery: videos first, then images. Each entry is
  // {type: 'video'|'image', video: UellowProductVideo?, url: String?}
  List<Map<String, dynamic>> get _items {
    final out = <Map<String, dynamic>>[];
    for (final v in videos) {
      out.add({'type': 'video', 'video': v});
    }
    for (final url in images) {
      out.add({'type': 'image', 'url': url});
    }
    return out;
  }
  @override
  Widget build(BuildContext context) {
    final items = _items;
    final hasItems = items.isNotEmpty;
    return SizedBox(
      height: 380,
      child: Stack(children: [
        ColoredBox(color: Colors.white, child: PageView.builder(
          itemCount: hasItems ? items.length : 1, onPageChanged: onChanged,
          itemBuilder: (_, i) {
            if (!hasItems) {
              return const Icon(Icons.image_outlined, size: 80, color: UellowColors.muted);
            }
            final it = items[i];
            if (it['type'] == 'video') {
              return _VideoTile(video: it['video'] as UellowProductVideo);
            }
            return CachedNetworkImage(imageUrl: it['url'] as String, fit: BoxFit.contain);
          },
        )),
        // Video pill in top-center to flag the gallery has a clip
        if (videos.isNotEmpty) Positioned(top: 14, left: 0, right: 0,
          child: Center(child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.play_circle_fill, color: Colors.white, size: 14),
              const SizedBox(width: 5),
              Text(videos.length == 1
                  ? '${UellowApi.instance.lang == "ar" ? "فيديو" : "Video"}'
                  : '${videos.length} ${UellowApi.instance.lang == "ar" ? "فيديوهات" : "videos"}',
                  style: const TextStyle(color: Colors.white, fontSize: 10.5,
                      fontWeight: FontWeight.w900, letterSpacing: 0.3)),
            ]),
          ))),
        Positioned(top: 14, left: 14, child: _btn(
            icon: Icons.arrow_back_ios_new, color: UellowColors.darkBrown,
            onTap: () => Navigator.maybePop(context))),
        Positioned(top: 14, right: 14, child: Row(children: [
          _btn(icon: inWishlist ? Icons.favorite : Icons.favorite_border,
              color: inWishlist ? UellowColors.danger : UellowColors.darkBrown,
              onTap: onWishlist),
          const SizedBox(width: 8),
          // Cart button with live count badge
          _CartBadgeBtn(onTap: () => Navigator.pushNamed(context, '/cart')),
        ])),
        Positioned(bottom: 14, left: 0, right: 0, child: _Dots(
          count: hasItems ? items.length : 1, active: page)),
      ]),
    );
  }
  Widget _btn({required IconData icon, required Color color, required VoidCallback onTap}) {
    return GestureDetector(onTap: onTap, child: Container(
      width: 38, height: 38,
      decoration: const BoxDecoration(
        color: Color(0xF2FFFFFF),
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      child: Icon(icon, size: 18, color: color),
    ));
  }
}

/// Single video tile in the product gallery — shows the thumbnail with
/// a big play button overlay; tap opens the full-screen player.
class _VideoTile extends StatelessWidget {
  const _VideoTile({required this.video});
  final UellowProductVideo video;
  String get _thumb {
    if (video.thumbnail.isNotEmpty) {
      return '${UellowApi.instance.baseUrl}${video.thumbnail}';
    }
    // YouTube auto-thumbnail from the embed URL.
    final m = RegExp(r'embed/([a-zA-Z0-9_-]{11})').firstMatch(video.embedUrl);
    if (m != null) return 'https://i.ytimg.com/vi/${m.group(1)}/hqdefault.jpg';
    return '';
  }
  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return GestureDetector(
      onTap: () => _openPlayer(context),
      child: Stack(fit: StackFit.expand, children: [
        if (_thumb.isNotEmpty)
          CachedNetworkImage(imageUrl: _thumb, fit: BoxFit.cover,
              errorWidget: (_,__,___) => Container(color: const Color(0xFF1A1A1A)))
        else
          Container(color: const Color(0xFF1A1A1A)),
        Container(color: Colors.black.withValues(alpha: 0.35)),
        Center(child: Container(
          width: 72, height: 72,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.95),
            shape: BoxShape.circle,
            boxShadow: const [BoxShadow(color: Color(0x66000000),
                blurRadius: 12, offset: Offset(0, 4))],
          ),
          child: const Icon(Icons.play_arrow_rounded,
              color: UellowColors.darkBrown, size: 44),
        )),
        Positioned(bottom: 14, left: 14, right: 14, child: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(_typeLabel(video.type, ar),
                style: const TextStyle(color: Colors.white, fontSize: 10,
                    fontWeight: FontWeight.w900, letterSpacing: 0.4)),
          ),
          if (video.title.isNotEmpty) ...[
            const SizedBox(width: 8),
            Expanded(child: Text(video.title,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    shadows: [Shadow(color: Color(0xAA000000), blurRadius: 4)]))),
          ],
        ])),
      ]),
    );
  }

  String _typeLabel(String t, bool ar) {
    switch (t) {
      case 'tiktok_url':    return ar ? 'تيك توك' : 'TIKTOK';
      case 'youtube':       return 'YOUTUBE';
      case 'vimeo':         return 'VIMEO';
      case 'direct_upload': return ar ? 'فيديو' : 'VIDEO';
    }
    return ar ? 'فيديو' : 'VIDEO';
  }

  void _openPlayer(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _VideoPlayerScreen(video: video),
      fullscreenDialog: true,
    ));
  }
}

/// Full-screen video player — uses webview_flutter so a single
/// implementation handles YouTube / TikTok / Vimeo embeds AND direct
/// MP4 uploads (wrapped in a small <video> HTML).
class _VideoPlayerScreen extends StatefulWidget {
  const _VideoPlayerScreen({required this.video});
  final UellowProductVideo video;
  @override
  State<_VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<_VideoPlayerScreen> {
  WebViewController? _wv;
  @override
  void initState() { super.initState(); _load(); }
  void _load() {
    try {
      final wv = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.black);
      final v = widget.video;
      if (v.type == 'direct_upload' && v.fileUrl.isNotEmpty) {
        final url = '${UellowApi.instance.baseUrl}${v.fileUrl}';
        wv.loadHtmlString('''
<!doctype html><html><head><meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no"/>
<style>html,body{margin:0;padding:0;background:#000;height:100%;width:100%}
video{width:100%;height:100%;object-fit:contain}</style>
</head><body>
<video src="$url" controls autoplay playsinline></video>
</body></html>''');
      } else if (v.embedUrl.isNotEmpty) {
        wv.loadRequest(Uri.parse(v.embedUrl));
      } else if (v.tiktokVideoId.isNotEmpty && !v.tiktokVideoId.startsWith('short:')) {
        wv.loadHtmlString('''
<!doctype html><html><head><meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no"/>
<style>html,body{margin:0;padding:0;background:#000;height:100%;width:100%;display:flex;align-items:center;justify-content:center}</style>
</head><body>
<blockquote class="tiktok-embed" cite="${v.embedUrl}" data-video-id="${v.tiktokVideoId}" style="max-width:605px;min-width:325px;"></blockquote>
<script async src="https://www.tiktok.com/embed.js"></script>
</body></html>''');
      } else if (v.videoUrl.isNotEmpty) {
        wv.loadRequest(Uri.parse(v.videoUrl));
      }
      setState(() => _wv = wv);
    } catch (_) {
      setState(() => _wv = null);
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(child: Stack(children: [
        if (_wv != null) Positioned.fill(child: WebViewWidget(controller: _wv!))
        else const Center(child: CircularProgressIndicator(color: Colors.white)),
        Positioned(top: 8, right: 8, child: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close, color: Colors.white, size: 28),
          style: IconButton.styleFrom(
            backgroundColor: Colors.black.withValues(alpha: 0.4),
            shape: const CircleBorder(),
          ),
        )),
      ])),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.active});
  final int count, active;
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(
      count, (i) => AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: i == active ? 18 : 6, height: 6,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: i == active ? UellowColors.darkBrown : const Color(0x40000000),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    ));
  }
}

class _CartBadgeBtn extends StatefulWidget {
  const _CartBadgeBtn({required this.onTap});
  final VoidCallback onTap;
  @override
  State<_CartBadgeBtn> createState() => _CartBadgeBtnState();
}

class _CartBadgeBtnState extends State<_CartBadgeBtn> {
  int _count = 0;
  @override
  void initState() {
    super.initState();
    _count = UellowApi.instance.cart.count.value;
    UellowApi.instance.cart.count.addListener(_sync);
    UellowApi.instance.cart.get().then((_) {}).catchError((_) {});
  }
  @override
  void dispose() {
    UellowApi.instance.cart.count.removeListener(_sync);
    super.dispose();
  }
  void _sync() {
    if (!mounted) return;
    setState(() => _count = UellowApi.instance.cart.count.value);
  }
  @override
  Widget build(BuildContext context) {
    return GestureDetector(onTap: widget.onTap, child: Stack(clipBehavior: Clip.none, children: [
      Container(
        width: 38, height: 38,
        decoration: const BoxDecoration(
          color: Color(0xF2FFFFFF),
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        child: const Icon(Icons.shopping_cart_outlined, size: 18,
            color: UellowColors.darkBrown),
      ),
      if (_count > 0) Positioned(top: -4, right: -4, child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
        decoration: BoxDecoration(color: UellowColors.danger,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: Colors.white, width: 1.5)),
        alignment: Alignment.center,
        child: Text('$_count', style: const TextStyle(
            color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900)),
      )),
    ]));
  }
}

// ─── Title — real sold + view + ID ─────────────────────────────────

class _Title extends StatelessWidget {
  const _Title({required this.p});
  final UellowProductFull p;
  @override
  Widget build(BuildContext context) {
    final lang = UellowApi.instance.lang;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(p.name.current(lang), style: UT.h1),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 4, children: [
          _MetaChip(icon: Icons.inventory_2_outlined, label: 'ID ${p.id}'),
          if (p.soldCount > 0)
            _MetaChip(icon: Icons.shopping_cart_outlined,
                label: lang == 'ar'
                    ? 'تم بيع ${p.soldCount}'
                    : '${p.soldCount} sold'),
          if (p.viewCount > 0)
            _MetaChip(icon: Icons.visibility_outlined,
                label: lang == 'ar'
                    ? '${p.viewCount} مشاهدة'
                    : '${p.viewCount} views'),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          for (var i = 0; i < 5; i++) Icon(
            i < p.rating.avg.round() ? Icons.star : Icons.star_border,
            size: 14, color: UellowColors.yellow,
          ),
          const SizedBox(width: 6),
          Text(p.rating.avg.toStringAsFixed(1),
              style: const TextStyle(fontWeight: FontWeight.w800,
                  color: UellowColors.darkBrown)),
          const SizedBox(width: 4),
          Text('(${p.rating.count})',
              style: const TextStyle(color: UellowColors.muted)),
        ]),
      ]),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});
  final IconData icon; final String label;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F0F0),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: UellowColors.muted),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(
          fontSize: 11, fontWeight: FontWeight.w700, color: UellowColors.text,
        )),
      ]),
    );
  }
}

// ─── Price row ─────────────────────────────────────────────────────

class _PriceRow extends StatelessWidget {
  const _PriceRow({required this.p});
  final UellowProductFull p;
  @override
  Widget build(BuildContext context) {
    final hasDisc = p.comparePrice != null && p.comparePrice!.amount > p.price.amount;
    final save = hasDisc ? p.comparePrice!.amount - p.price.amount : 0.0;
    final lang = UellowApi.instance.lang;
    final sym = p.price.displaySymbol(lang);
    final saveLabel = lang == 'ar' ? 'وفّر' : 'Save';
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
      child: Wrap(spacing: 10, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text('${p.price.amount.toStringAsFixed(3)} $sym',
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900,
                color: UellowColors.darkBrown, letterSpacing: -0.3)),
        if (hasDisc) MidStrikePrice(
          text: p.comparePrice!.amount.toStringAsFixed(3),
          fontSize: 14, color: UellowColors.muted,
          lineColor: UellowColors.danger),
        if (hasDisc) Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: UellowColors.successBg,
              borderRadius: BorderRadius.circular(6)),
          child: Text('-${p.discountPct}%',
              style: const TextStyle(color: UellowColors.successDk,
                  fontSize: 11, fontWeight: FontWeight.w800)),
        ),
        if (hasDisc) Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: UellowColors.danger,
              borderRadius: BorderRadius.circular(6)),
          child: Text('$saveLabel ${save.toStringAsFixed(3)} $sym',
              style: const TextStyle(color: Colors.white,
                  fontSize: 11, fontWeight: FontWeight.w800)),
        ),
      ]),
    );
  }
}

/// Strikethrough text where the line is centered vertically through the
/// glyph body (not floating at the baseline as the default
/// TextDecoration.lineThrough does). Used on pre-discount prices so the
/// line clearly cancels the digits.
class MidStrikePrice extends StatelessWidget {
  const MidStrikePrice({super.key,
      required this.text, required this.fontSize,
      required this.color, this.lineColor = UellowColors.danger,
      this.thickness = 1.6});
  final String text;
  final double fontSize;
  final Color color, lineColor;
  final double thickness;
  @override
  Widget build(BuildContext context) {
    return Stack(alignment: Alignment.center, children: [
      Text(text, style: TextStyle(
          fontSize: fontSize, color: color, fontWeight: FontWeight.w700)),
      Positioned.fill(child: Center(child: Container(
        height: thickness,
        margin: const EdgeInsets.symmetric(horizontal: -2),
        color: lineColor,
      ))),
    ]);
  }
}

// ─── Brand block ───────────────────────────────────────────────────

class _BrandBlock extends StatelessWidget {
  const _BrandBlock({required this.brand});
  final UellowBrand brand;
  @override
  Widget build(BuildContext context) {
    final lang = UellowApi.instance.lang;
    final name = brand.name.current(lang);
    return Container(
      color: Colors.white, margin: const EdgeInsets.only(top: 8),
      child: InkWell(
        onTap: () => UellowRouter.goBrand(context, brand.id, name),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
          child: Row(children: [
            // Brand logo
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: UellowColors.bg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: UellowColors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: (brand.image != null && brand.image!.isNotEmpty)
                ? CachedNetworkImage(imageUrl: brand.image!, fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => _initial(name))
                : _initial(name),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(T.t('brand.official'), style: const TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w800,
                  color: UellowColors.muted, letterSpacing: 0.8)),
              const SizedBox(height: 4),
              Row(children: [
                Flexible(child: Text(name,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15,
                        fontWeight: FontWeight.w900, color: UellowColors.ink))),
                const SizedBox(width: 6),
                // Blue scalloped verified badge — Twitter/Instagram style
                const _VerifiedBadge(),
              ]),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: UellowColors.yellowSoft,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: UellowColors.yellow),
              ),
              child: Text(T.t('brand.visit_store'), style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w800,
                  color: UellowColors.darkBrown)),
            ),
          ]),
        ),
      ),
    );
  }
  Widget _initial(String name) => Container(
    color: UellowColors.darkBrown,
    alignment: Alignment.center,
    child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'B',
        style: const TextStyle(color: UellowColors.yellowLight,
            fontWeight: FontWeight.w900, fontSize: 18)),
  );
}


// ─── Vendor card ───────────────────────────────────────────────────

/// Sold-By vendor card — taps through to the vendor's storefront.
class _VendorCard extends StatelessWidget {
  const _VendorCard({required this.vendor});
  final UellowVendorRef vendor;
  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    final lang = UellowApi.instance.lang;
    final name = vendor.name.current(lang);
    final tier = vendor.tier.toLowerCase();
    final tierColors = {
      'platinum': const Color(0xFFA7C7E7),
      'gold':     const Color(0xFFE6C04A),
      'silver':   const Color(0xFFBCBCBC),
      'bronze':   const Color(0xFFCD7F32),
    };
    final tierColor = tierColors[tier] ?? UellowColors.muted;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      child: InkWell(
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        onTap: () => UellowRouter.goVendor(context, vendor.id),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: UellowColors.border, width: 1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            // ── Vendor logo / initial
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: UellowColors.yellowSoft,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: UellowColors.yellow, width: 1.5),
              ),
              clipBehavior: Clip.antiAlias,
              child: vendor.logo != null && vendor.logo!.isNotEmpty
                  ? CachedNetworkImage(imageUrl: vendor.logo!, fit: BoxFit.cover,
                      errorWidget: (_,__,___) => _initial(name))
                  : _initial(name),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // "Sold by" caption
              Row(children: [
                const Icon(Icons.verified_outlined, size: 11,
                    color: UellowColors.muted),
                const SizedBox(width: 3),
                Text(ar ? 'البائع' : 'SOLD BY',
                    style: const TextStyle(fontSize: 9.5,
                        fontWeight: FontWeight.w900, color: UellowColors.muted,
                        letterSpacing: 0.6)),
              ]),
              const SizedBox(height: 2),
              Row(children: [
                Flexible(child: Text(name, maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900,
                        fontSize: 14.5, color: UellowColors.ink))),
                if (tier.isNotEmpty && tier != 'standard') ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [tierColor.withValues(alpha: 0.85), tierColor]),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(tier.toUpperCase(),
                        style: const TextStyle(color: Colors.white,
                            fontSize: 8.5, fontWeight: FontWeight.w900,
                            letterSpacing: 0.5)),
                  ),
                ],
              ]),
            ])),
            // ── Visit button
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: UellowColors.yellow,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(ar ? 'زيارة' : 'Visit',
                    style: const TextStyle(color: UellowColors.darkBrown,
                        fontSize: 11.5, fontWeight: FontWeight.w900)),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_forward, size: 11,
                    color: UellowColors.darkBrown),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
  Widget _initial(String name) => Container(
    alignment: Alignment.center,
    child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'U',
        style: const TextStyle(color: UellowColors.darkBrown,
            fontWeight: FontWeight.w900, fontSize: 18)),
  );
}

// ─── Attributes ────────────────────────────────────────────────────

class _Attributes extends StatelessWidget {
  const _Attributes({
    required this.productId,
    required this.attributes, required this.selectedColor, required this.selectedSize,
    required this.onColor, required this.onSize,
  });
  final int productId;
  final List<UellowAttributeLine> attributes;
  final int selectedColor;
  final String selectedSize;
  final ValueChanged<int> onColor;
  final ValueChanged<String> onSize;

  @override
  Widget build(BuildContext context) {
    final relevant = attributes.where((line) {
      final n = line.attributeName.current(UellowApi.instance.lang).toLowerCase();
      return !(n.contains('brand') || n.contains('ماركة')
          || n.contains('علامة') || n.contains('trademark'));
    }).toList();
    if (relevant.isEmpty) return const SizedBox.shrink();
    // Variations live in their own dedicated card — no gap with the
    // delivery card directly below.
    return Container(
      color: Colors.white,
      margin: const EdgeInsets.only(top: 6),
      child: Column(children: relevant.map((line) {
        final name = line.attributeName.current(UellowApi.instance.lang).toLowerCase();
        if (name.contains('color') || name.contains('لون')) return _colorBlock(line);
        if (name.contains('size') || name.contains('مقاس')) return _sizeBlock(line, withSmartFit: true);
        return _generic(line);
      }).toList()),
    );
  }

  Widget _colorBlock(UellowAttributeLine line) {
    return _wrap(title: line.attributeName.current(UellowApi.instance.lang),
        child: SizedBox(height: 86, child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: line.values.length,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (_, i) => _imageSwatch(line.values[i], selectedColor == i,
              () => onColor(i)),
        )));
  }

  Widget _imageSwatch(UellowAttributeValue v, bool on, VoidCallback onTap) {
    final hasImage = v.image != null && v.image!.isNotEmpty;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 64, padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          border: Border.all(
              color: on ? UellowColors.yellow : Colors.transparent, width: 2),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: hasImage
              ? CachedNetworkImage(imageUrl: v.image!,
                  width: 54, height: 54, fit: BoxFit.cover,
                  errorWidget: (_,__,___) => _swatchColor(v))
              : _swatchColor(v),
          ),
          const SizedBox(height: 4),
          Text(v.name.current(UellowApi.instance.lang),
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                  color: UellowColors.text)),
        ]),
      ),
    );
  }

  Widget _swatchColor(UellowAttributeValue v) {
    Color c = UellowColors.darkBrown;
    final hex = v.htmlColor.replaceAll('#', '');
    if (hex.length == 6) {
      try { c = Color(int.parse('ff$hex', radix: 16)); } catch (_) {}
    }
    return Container(width: 54, height: 54, color: c);
  }

  Widget _sizeBlock(UellowAttributeLine line, {bool withSmartFit = false}) {
    return _wrap(title: line.attributeName.current(UellowApi.instance.lang),
        smartFit: withSmartFit, child: Wrap(spacing: 6, runSpacing: 6, children: [
          for (var v in line.values)
            _sizeChip(v.name.current(UellowApi.instance.lang),
                v.name.current(UellowApi.instance.lang) == selectedSize),
        ]));
  }

  Widget _generic(UellowAttributeLine line) {
    return _wrap(title: line.attributeName.current(UellowApi.instance.lang),
        child: Wrap(spacing: 6, children: [
          for (var v in line.values) _sizeChip(v.name.current(UellowApi.instance.lang), false),
        ]));
  }

  Widget _wrap({required String title, required Widget child, bool smartFit = false}) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(title, style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w800, color: UellowColors.darkBrown)),
          if (smartFit) const Spacer(),
          if (smartFit) Builder(builder: (ctx) {
            final ar = UellowApi.instance.lang == 'ar';
            return GestureDetector(
              onTap: () => Navigator.pushNamed(ctx, '/tryon',
                  arguments: {'id': productId}),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [UellowColors.yellowLight, UellowColors.yellow]),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: const [BoxShadow(color: Color(0x33F5C320),
                      blurRadius: 6, offset: Offset(0, 2))],
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.straighten, size: 13,
                      color: UellowColors.darkBrown),
                  const SizedBox(width: 4),
                  Text(ar ? 'مقاسي الذكي' : 'Smart Fit',
                      style: const TextStyle(fontWeight: FontWeight.w800,
                          color: UellowColors.darkBrown, fontSize: 11)),
                ]),
              ),
            );
          }),
        ]),
        const SizedBox(height: 10),
        child,
      ]),
    );
  }

  Widget _sizeChip(String size, bool on) {
    return GestureDetector(
      onTap: () => onSize(size),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: on ? UellowColors.darkBrown : Colors.white,
          border: Border.all(color: on ? UellowColors.darkBrown : UellowColors.border, width: 1.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(size, style: TextStyle(
          color: on ? UellowColors.yellowLight : UellowColors.text,
          fontWeight: FontWeight.w800, fontSize: 13,
        )),
      ),
    );
  }
}

// ─── Compact delivery (clickable) ─────────────────────────────────

class _CompactDelivery extends StatefulWidget {
  const _CompactDelivery({required this.onTap});
  final VoidCallback onTap;
  @override
  State<_CompactDelivery> createState() => _CompactDeliveryState();
}

class _CompactDeliveryState extends State<_CompactDelivery> {
  String _summary = '';
  @override
  void initState() { super.initState(); _loadAddress(); }
  Future<void> _loadAddress() async {
    try {
      final addrs = await UellowApi.instance.addresses.list();
      if (addrs.isEmpty) return;
      // Prefer the saved-default; else first (newest)
      final savedId = await UellowApi.instance.tokenStore.readAddressId();
      final pick = addrs.firstWhere((a) => a.id == savedId,
          orElse: () => addrs.first);
      final parts = [
        pick.country, pick.state, pick.city,
      ].where((s) => s.isNotEmpty).toList();
      if (mounted) setState(() => _summary = parts.join(' · '));
    } catch (_) {}
  }
  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    final has = _summary.isNotEmpty;
    return InkWell(onTap: widget.onTap, child: Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      child: Row(children: [
        Container(
          width: 32, height: 32,
          decoration: const BoxDecoration(
            color: UellowColors.yellowSoft,
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
          child: const Icon(Icons.location_on_outlined, size: 16, color: UellowColors.warn),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(ar ? 'التوصيل إلى' : 'Deliver to',
                style: const TextStyle(fontSize: 11,
                    color: UellowColors.muted, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(has
                ? _summary
                : (ar ? 'اختر عنوانك' : 'Choose your address'),
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: has ? UellowColors.darkBrown : UellowColors.ink)),
          ],
        )),
        const Icon(Icons.chevron_right, color: Color(0xFFCBB78A)),
      ]),
    ));
  }
}

class _DeliveryDialog extends StatefulWidget {
  @override
  State<_DeliveryDialog> createState() => _DeliveryDialogState();
}

class _DeliveryDialogState extends State<_DeliveryDialog> {
  late Future<List<UellowAddress>> _future;
  @override
  void initState() {
    super.initState();
    _future = UellowApi.instance.addresses.list().catchError((_) => <UellowAddress>[]);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.78),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 10),
        Center(child: Container(width: 36, height: 4,
            decoration: BoxDecoration(color: UellowColors.border,
                borderRadius: BorderRadius.circular(2)))),
        const Padding(padding: EdgeInsets.fromLTRB(20, 14, 20, 6),
            child: Row(children: [
              Text('Deliver to', style: UT.h2),
            ])),
        Flexible(child: FutureBuilder<List<UellowAddress>>(
          future: _future,
          builder: (_, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: Padding(
                padding: EdgeInsets.all(20), child: CircularProgressIndicator()));
            }
            final list = snap.data ?? [];
            if (list.isEmpty) return _empty();
            return ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final a = list[i];
                final isDef = a.isDefault;
                return GestureDetector(
                  onTap: () async {
                    await UellowApi.instance.tokenStore.writeAddressId(a.id);
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDef ? UellowColors.yellowSoft : Colors.white,
                    border: Border.all(
                        color: isDef ? UellowColors.yellow : UellowColors.border,
                        width: isDef ? 2 : 1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(children: [
                    Icon(isDef ? Icons.location_on : Icons.location_on_outlined,
                        color: isDef ? UellowColors.warn : UellowColors.muted),
                    const SizedBox(width: 10),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(a.name.isNotEmpty ? a.name : (a.city.isNotEmpty ? a.city : 'Address'),
                          style: const TextStyle(fontWeight: FontWeight.w800,
                              fontSize: 14, color: UellowColors.ink)),
                      const SizedBox(height: 2),
                      Text([a.street, a.street2, a.city].where((s) => s.isNotEmpty).join(', '),
                          style: const TextStyle(fontSize: 12, color: UellowColors.muted)),
                    ])),
                    if (isDef) Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: UellowColors.yellow,
                        borderRadius: BorderRadius.circular(6)),
                      child: const Text('DEFAULT', style: TextStyle(
                          fontSize: 9, fontWeight: FontWeight.w900,
                          color: UellowColors.darkBrown, letterSpacing: 0.5)),
                    ),
                  ]),
                ));
              },
            );
          },
        )),
        Padding(padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
            child: Column(children: [
              SizedBox(width: double.infinity, child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, '/addresses');
                },
                icon: const Icon(Icons.add_location_alt_outlined, size: 16),
                label: Text(UellowApi.instance.lang == 'ar'
                    ? 'إدارة العناوين' : 'Manage addresses'),
                style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14)),
              )),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close', style: TextStyle(color: UellowColors.text)),
              ),
            ])),
      ]),
    );
  }

  Widget _empty() {
    return Padding(padding: const EdgeInsets.all(20), child: Column(children: [
      const Icon(Icons.location_off_outlined, size: 48, color: UellowColors.muted),
      const SizedBox(height: 10),
      const Text('No saved addresses yet.', style: UT.body),
      const SizedBox(height: 14),
      SizedBox(width: double.infinity, child: ElevatedButton.icon(
        onPressed: () {
          Navigator.pop(context);
          Navigator.pushNamed(context, '/auth');
        },
        icon: const Icon(Icons.login, size: 16),
        label: const Text('Sign in to add address'),
        style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14)),
      )),
    ]));
  }
}

// ─── Bulk pricing ─────────────────────────────────────────────────

class _BulkPricing extends StatelessWidget {
  const _BulkPricing({required this.tiers});
  final List<UellowBulkTier> tiers;
  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    final bestIdx = tiers.indexWhere((t) => t.savePct >= tiers.map((x) => x.savePct).reduce((a,b)=>a>b?a:b));
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFFFFFAEC), Color(0xFFFFF4D2)]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: UellowColors.yellow.withValues(alpha: 0.5), width: 1.5),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 32, height: 32, alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: UellowColors.darkBrown, shape: BoxShape.circle),
            child: const Icon(Icons.local_offer_outlined, size: 16,
                color: UellowColors.yellowLight),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(ar ? 'سعر الجملة' : 'Bulk pricing',
                style: const TextStyle(fontWeight: FontWeight.w900,
                    fontSize: 14, color: UellowColors.darkBrown)),
            Text(ar ? 'اشترِ أكثر · ادفع أقل' : 'Buy more · save more',
                style: const TextStyle(fontSize: 11.5,
                    color: UellowColors.muted, fontWeight: FontWeight.w600)),
          ])),
          if (tiers.isNotEmpty && tiers.last.savePct > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: UellowColors.success,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(ar
                  ? 'وفّر حتى ${tiers.last.savePct}%'
                  : 'Save up to ${tiers.last.savePct}%',
                  style: const TextStyle(color: Colors.white,
                      fontSize: 10.5, fontWeight: FontWeight.w900)),
            ),
        ]),
        const SizedBox(height: 14),
        // Render up to 4 tiers in a tight row. Spacing is 6px so 4 columns
        // still breathe on small phones.
        Row(children: List.generate(tiers.length, (i) {
          final t = tiers[i];
          final nextMin = i < tiers.length - 1 ? tiers[i + 1].minQty - 1 : null;
          final qtyLabel = nextMin != null
              ? '${t.minQty}–$nextMin'
              : '${t.minQty}+';
          return Expanded(child: Padding(
            padding: EdgeInsets.only(right: i < tiers.length - 1 ? 6 : 0),
            child: _tier(qtyLabel: qtyLabel, price: t.price, sym: t.currency,
                save: t.savePct, best: i == bestIdx && tiers.length > 1,
                capped: t.capped, ar: ar),
          ));
        })),
        // Tier-floor protection legend (only shows if ANY tier was capped)
        if (tiers.any((t) => t.capped)) ...[
          const SizedBox(height: 10),
          Row(children: [
            Icon(Icons.shield_outlined, size: 13,
                color: UellowColors.darkBrown.withValues(alpha: 0.55)),
            const SizedBox(width: 4),
            Expanded(child: Text(
              ar
                ? 'بعض الخصومات مُحسَّنة لضمان جودة المنتج'
                : 'Some discounts adjusted to protect product quality',
              style: TextStyle(fontSize: 10.5,
                  color: UellowColors.darkBrown.withValues(alpha: 0.55),
                  fontWeight: FontWeight.w600))),
          ]),
        ],
      ]),
    );
  }
  Widget _tier({required String qtyLabel, required double price, required String sym,
      required int save, bool best = false, bool capped = false, required bool ar}) {
    return Stack(clipBehavior: Clip.none, children: [
      Container(
        padding: EdgeInsets.fromLTRB(6, best ? 18 : 12, 6, 12),
        decoration: BoxDecoration(
          color: best ? UellowColors.darkBrown : Colors.white,
          border: Border.all(
              color: best ? UellowColors.darkBrown : UellowColors.border,
              width: best ? 2 : 1),
          borderRadius: BorderRadius.circular(12),
          boxShadow: best ? [BoxShadow(
              color: UellowColors.darkBrown.withValues(alpha: 0.18),
              blurRadius: 10, offset: const Offset(0, 4))] : null,
        ),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: best ? UellowColors.yellow : UellowColors.yellowSoft,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text('$qtyLabel ${ar ? "قطعة" : "pcs"}',
                style: const TextStyle(fontSize: 10,
                    fontWeight: FontWeight.w900, color: UellowColors.darkBrown)),
          ),
          const SizedBox(height: 8),
          Text(price.toStringAsFixed(3), style: TextStyle(
              fontSize: 17, fontWeight: FontWeight.w900,
              color: best ? UellowColors.yellowLight : UellowColors.darkBrown)),
          Text('$sym ${ar ? "/ قطعة" : "/ pc"}',
              style: TextStyle(fontSize: 10,
                  color: best ? UellowColors.yellowLight.withValues(alpha: 0.7) : UellowColors.muted)),
          if (save > 0) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: UellowColors.success,
                borderRadius: BorderRadius.circular(4)),
              child: Text(ar ? 'وفّر $save%' : 'Save $save%',
                  style: const TextStyle(fontSize: 9.5,
                      color: Colors.white, fontWeight: FontWeight.w900)),
            ),
          ],
        ]),
      ),
      if (best) Positioned(top: -8, left: 0, right: 0, child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: UellowColors.yellow,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white, width: 1.5),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.star, color: UellowColors.darkBrown, size: 10),
            const SizedBox(width: 3),
            Text(ar ? 'الأفضل' : 'BEST',
                style: const TextStyle(fontSize: 9,
                    fontWeight: FontWeight.w900, color: UellowColors.darkBrown,
                    letterSpacing: 0.4)),
          ]),
        ),
      )),
    ]);
  }
}

// ─── Description ──────────────────────────────────────────────────

class _DescriptionBlock extends StatelessWidget {
  const _DescriptionBlock({required this.product});
  final UellowProductFull product;
  @override
  Widget build(BuildContext context) {
    final lang = UellowApi.instance.lang;
    final raw = product.descriptionHtml.current(lang).isNotEmpty
        ? _stripHtml(product.descriptionHtml.current(lang))
        : _stripHtml(product.descriptionShort.current(lang));
    final body = raw.isEmpty ? 'No description provided for this product.' : raw;
    final long = body.length > 240;
    return Container(
      color: Colors.white, margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Description', style: UT.h3),
        const SizedBox(height: 10),
        Stack(children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Text(body, style: UT.body),
            ),
          ),
          if (long) Positioned(bottom: 0, left: 0, right: 0, height: 70,
            child: IgnorePointer(child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.white], stops: [0, 0.9],
                ),
              ),
            )),
          ),
        ]),
        if (long) ...[
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () => showModalBottomSheet(
              context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
              builder: (_) => _DescriptionDialog(text: body),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: UellowColors.yellowSoft,
              foregroundColor: UellowColors.darkBrown, elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12))),
            ),
            child: const Text('See full description  ›',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          )),
        ],
      ]),
    );
  }
}

String _stripHtml(String s) {
  var t = s.replaceAll(RegExp(r'<\s*br\s*/?\s*>'), '\n');
  t = t.replaceAll(RegExp(r'</\s*(p|div|li|h\d)\s*>'), '\n');
  t = t.replaceAll(RegExp(r'<[^>]+>'), '');
  t = t.replaceAll('&nbsp;', ' ').replaceAll('&amp;', '&')
       .replaceAll('&lt;', '<').replaceAll('&gt;', '>')
       .replaceAll('&quot;', '"').replaceAll('&#39;', "'");
  return t.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}

class _DescriptionDialog extends StatelessWidget {
  const _DescriptionDialog({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _SheetHeader(title: 'Description'),
        Flexible(child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 30),
          child: Text(text, style: UT.body),
        )),
      ]),
    );
  }
}

// ─── Specs ────────────────────────────────────────────────────────

class _SpecsBlock extends StatelessWidget {
  const _SpecsBlock({required this.product, required this.onOpen});
  final UellowProductFull product;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white, margin: const EdgeInsets.only(top: 8),
      child: InkWell(onTap: onOpen, child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Container(
            width: 38, height: 38,
            decoration: const BoxDecoration(
              color: UellowColors.yellowSoft,
              borderRadius: BorderRadius.all(Radius.circular(10)),
            ),
            child: const Icon(Icons.grid_view, size: 18, color: UellowColors.warn),
          ),
          const SizedBox(width: 12),
          const Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Specifications', style: UT.h3),
              SizedBox(height: 2),
              Text('Brand, materials, warranty & more', style: UT.small),
            ],
          )),
          const Icon(Icons.chevron_right, color: Color(0xFFCBB78A), size: 22),
        ]),
      )),
    );
  }
}

class _SpecsDialog extends StatelessWidget {
  const _SpecsDialog({required this.p});
  final UellowProductFull p;
  @override
  Widget build(BuildContext context) {
    final lang = UellowApi.instance.lang;
    final rows = <(String, String)>[];
    if (p.brand != null) rows.add(('Brand', p.brand!.name.current(lang)));
    for (final line in p.attributes) {
      final attr = line.attributeName.current(lang);
      final lo = attr.toLowerCase();
      if (lo.contains('brand') || attr.contains('ماركة')
          || attr.contains('علامة') || lo.contains('trademark')) continue;
      if (line.values.isNotEmpty) {
        rows.add((attr, line.values.map((v) => v.name.current(lang)).join(' · ')));
      }
    }
    if (p.sku.isNotEmpty) rows.add(('SKU', p.sku));
    if (p.barcode.isNotEmpty) rows.add(('Barcode', p.barcode));
    rows.add(('Warranty', '${p.warrantyMonths} months'));
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _SheetHeader(title: 'Specifications'),
        Flexible(child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 30),
          child: Column(children: rows.map((r) => Container(
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: UellowColors.border)),
            ),
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(children: [
              SizedBox(width: 140, child: Text(r.$1,
                  style: const TextStyle(color: UellowColors.muted, fontWeight: FontWeight.w600))),
              Expanded(child: Text(r.$2,
                  style: const TextStyle(color: UellowColors.ink, fontWeight: FontWeight.w700))),
            ]),
          )).toList()),
        )),
      ]),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: UellowColors.border)),
      ),
      child: Row(children: [
        Expanded(child: Text(title, style: UT.h2)),
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            width: 32, height: 32,
            decoration: const BoxDecoration(
              color: UellowColors.border, shape: BoxShape.circle,
            ),
            child: const Icon(Icons.close, size: 18, color: UellowColors.darkBrown),
          ),
        ),
      ]),
    );
  }
}

// ─── Reviews block (live from /products/<id>/reviews) ──────────────

class _ReviewsBlock extends StatefulWidget {
  const _ReviewsBlock({required this.productId});
  final int productId;
  @override
  State<_ReviewsBlock> createState() => _ReviewsBlockState();
}

class _ReviewsBlockState extends State<_ReviewsBlock> {
  Future<Map<String, dynamic>?>? _future;
  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }
  Future<Map<String, dynamic>?> _fetch() async {
    try {
      final r = await http.get(
        Uri.parse('${UellowApi.instance.baseUrl}/api/mobile/v2/products/${widget.productId}/reviews'),
        headers: {'Accept': 'application/json'},
      );
      final body = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (body['success'] == true) return body['data'] as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white, margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(T.t('product.reviews'), style: UT.h3)),
          OutlinedButton.icon(
            onPressed: () => _openWriteReview(context),
            icon: const Icon(Icons.edit_outlined, size: 14, color: UellowColors.darkBrown),
            label: Text(T.t('product.write_review'),
                style: const TextStyle(fontSize: 11.5,
                    fontWeight: FontWeight.w800, color: UellowColors.darkBrown)),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              side: const BorderSide(color: UellowColors.yellow, width: 1.5),
              shape: const StadiumBorder(),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        FutureBuilder<Map<String, dynamic>?>(
          future: _future,
          builder: (_, snap) {
            final data = snap.data ?? {};
            final summary = (data['summary'] as Map?) ?? {};
            final reviews = (data['reviews'] as List?) ?? [];
            final avg = (summary['avg'] as num?)?.toDouble() ?? 0;
            final total = (summary['total'] as int?) ?? reviews.length;
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(avg.toStringAsFixed(1), style: const TextStyle(
                    fontSize: 42, fontWeight: FontWeight.w900,
                    color: UellowColors.ink, height: 1)),
                const SizedBox(width: 14),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [for (var i = 0; i < 5; i++) Icon(
                    i < avg.round() ? Icons.star : Icons.star_border,
                    size: 16, color: UellowColors.yellow)]),
                  const SizedBox(height: 2),
                  Text('Based on $total ${total == 1 ? "review" : "reviews"}',
                      style: const TextStyle(color: UellowColors.muted, fontSize: 11)),
                ]),
              ]),
              const SizedBox(height: 14),
              if (reviews.isEmpty) Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: UellowColors.yellowSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(child: Text(T.t('reviews.no_reviews'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: UellowColors.text),
                )),
              ) else for (final r in reviews.take(3)) _reviewCard(r as Map<String, dynamic>),
              if (reviews.length > 3) Padding(
                padding: const EdgeInsets.only(top: 10),
                child: SizedBox(width: double.infinity, child: ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: UellowColors.yellowSoft,
                    foregroundColor: UellowColors.darkBrown, elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text('${T.t('reviews.see_all')} ($total)',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                )),
              ),
            ]);
          },
        ),
      ]),
    );
  }

  void _openWriteReview(BuildContext context) {
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _WriteReviewSheet(
        productId: widget.productId,
        onSubmitted: () => setState(() => _future = _fetch()),
      ),
    );
  }

  Widget _reviewCard(Map<String, dynamic> r) {
    final author = (r['author'] as String?) ?? 'Anonymous';
    final rating = (r['rating'] as num?)?.toDouble() ?? 0;
    final body = (r['body'] as String?) ?? '';
    final verified = r['verified_purchase'] == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 32, height: 32,
            decoration: const BoxDecoration(
                color: UellowColors.yellowLight, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(author.isNotEmpty ? author[0].toUpperCase() : '?',
                style: const TextStyle(fontWeight: FontWeight.w800,
                    color: UellowColors.darkBrown)),
          ),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(author, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              if (verified) Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: UellowColors.success,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('VERIFIED', style: TextStyle(
                      color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
                ),
              ),
            ]),
            Row(children: [for (var i = 0; i < 5; i++) Icon(
              i < rating.round() ? Icons.star : Icons.star_border,
              size: 12, color: UellowColors.yellow)]),
          ])),
        ]),
        if (body.isNotEmpty) Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(body, style: const TextStyle(
              fontSize: 13, color: UellowColors.ink, height: 1.5)),
        ),
      ]),
    );
  }
}

// ─── Related products with infinite-load (3 auto rounds, then button) ─

class _RelatedInfinite extends StatefulWidget {
  const _RelatedInfinite({required this.productId, required this.categoryId});
  final int productId;
  final int? categoryId;
  @override
  State<_RelatedInfinite> createState() => _RelatedInfiniteState();
}

class _RelatedInfiniteState extends State<_RelatedInfinite> {
  final List<UellowProductCard> _items = [];
  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;
  int _autoRounds = 0;
  // Unlimited infinite scroll — keep fetching while the backend reports
  // hasNext. We don't surface a manual "Load more" button anymore.
  static const int _kAutoLimit = 1 << 31;
  @override
  void initState() { super.initState(); _loadMore(); }
  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      // Same-category only — that's what makes them "related". If the
      // product has no public category, fall back to the global list.
      final page = await UellowApi.instance.products.list(
          categoryId: widget.categoryId,
          page: _page, perPage: 10);
      if (mounted) setState(() {
        _items.addAll(page.items.where((p) => p.id != widget.productId));
        _hasMore = page.hasNext;
        _page++;
        _autoRounds++;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _hasMore = false; });
    }
  }
  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return NotificationListener<ScrollEndNotification>(
      onNotification: (n) {
        // Auto-load first 5 rounds, then user must tap View more.
        if (_autoRounds < _kAutoLimit && _hasMore && !_loading
            && n.metrics.pixels >= n.metrics.maxScrollExtent - 400) {
          _loadMore();
        }
        return false;
      },
      child: Container(
        color: Colors.white, margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(T.t('product.related'), style: UT.h3),
          const SizedBox(height: 4),
          Text(T.t('sec.related_sub'), style: UT.subtitle),
          const SizedBox(height: 12),
          if (_items.isEmpty && _loading)
            const SizedBox(height: 180,
                child: Center(child: CircularProgressIndicator(
                    color: UellowColors.darkBrown))),
          if (_items.isNotEmpty) GridView.builder(
            shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, mainAxisSpacing: 8, crossAxisSpacing: 8,
              childAspectRatio: 0.55,
            ),
            itemCount: _items.length,
            itemBuilder: (_, i) => ProductCard(product: _items[i]),
          ),
          if (_loading && _items.isNotEmpty) const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Center(child: CircularProgressIndicator(
                strokeWidth: 2, color: UellowColors.darkBrown)),
          ),
          if (_hasMore && !_loading && _autoRounds >= _kAutoLimit) Padding(
            padding: const EdgeInsets.fromLTRB(40, 16, 40, 8),
            child: SizedBox(width: double.infinity, child: ElevatedButton.icon(
              onPressed: _loadMore,
              icon: const Icon(Icons.expand_more, size: 18,
                  color: UellowColors.darkBrown),
              label: Text(ar ? 'تحميل المزيد' : 'Load more',
                  style: const TextStyle(fontWeight: FontWeight.w900,
                      color: UellowColors.darkBrown)),
              style: ElevatedButton.styleFrom(
                backgroundColor: UellowColors.yellowSoft,
                foregroundColor: UellowColors.darkBrown, elevation: 0,
                side: const BorderSide(color: UellowColors.yellow, width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            )),
          ),
        ]),
      ),
    );
  }
}

// ─── Sticky CTA bar ───────────────────────────────────────────────

class _CtaBar extends StatelessWidget {
  const _CtaBar({required this.product, required this.qty, required this.onQty});
  final UellowProductFull product;
  final int qty;
  final ValueChanged<int> onQty;
  @override
  Widget build(BuildContext context) {
    final qa = product.qtyAvailable;
    // Truly out of stock = qty<=0 AND product does NOT allow backorders.
    // If the vendor enabled "continue selling when out of stock", treat
    // as normally available (Add to cart).
    final isOut = qa != null && qa <= 0 && !product.allowOutOfStockOrder;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: UellowColors.border)),
        boxShadow: [BoxShadow(
            color: Color(0x14000000), blurRadius: 8, offset: Offset(0, -2))],
      ),
      child: SafeArea(top: false,
          child: isOut ? _notify(context, product) : _normal(context, product)),
    );
  }

  Widget _notify(BuildContext context, UellowProductFull p) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [UellowColors.darkBrown, UellowColors.darkSoft],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(
            color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Material(
        color: Colors.transparent, borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            // Best-effort wishlist add — it makes the user a "subscriber"
            // to this product so we can email them when it's restocked.
            try {
              await UellowApi.instance.wishlist.add(p.id);
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text(
                      "We'll notify you the moment it's back in stock."),
                      duration: Duration(seconds: 2)));
            } on UellowApiException catch (e) {
              if (e.isAuthError) {
                if (context.mounted) Navigator.pushNamed(context, '/auth');
              } else if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.message)));
              }
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
            child: Row(children: const [
              Icon(Icons.notifications_active_outlined, size: 18,
                  color: UellowColors.yellowLight),
              SizedBox(width: 10),
              Text('Notify me when back in stock', style: TextStyle(
                  color: UellowColors.yellowLight, fontSize: 14,
                  fontWeight: FontWeight.w900, letterSpacing: 0.2)),
              Spacer(),
              Icon(Icons.arrow_forward, size: 16,
                  color: UellowColors.yellowLight),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _normal(BuildContext context, UellowProductFull p) {
    final ar = UellowApi.instance.lang == 'ar';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        // ── Beena bee with floating red "Any help?" pill ──────────
        _BeenaHelpButton(onTap: () => Navigator.pushNamed(context, '/beena'),
            label: ar ? 'مساعدة؟' : 'Any help?'),
        const SizedBox(width: 8),
        // ── Yellow Add to cart — 2/3 of the row (wider than Buy now) ─
        Expanded(flex: 2, child: _CtaButton(
          label: T.t('product.add_cart'),
          icon: Icons.add_shopping_cart,
          gradient: const LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFFFFE066), UellowColors.yellow, Color(0xFFE0A800)],
          ),
          textColor: UellowColors.darkBrown,
          side: const BorderRadius.all(Radius.circular(10)),
          shadow: const Color(0x33F5C320),
          onTap: () => _openBuySheet(context, p, isBuyNow: false),
        )),
        const SizedBox(width: 6),
        // ── Red Buy now — 1/3 of the row ────────────────────────────
        Expanded(flex: 1, child: _CtaButton(
          label: T.t('product.buy_now'),
          icon: Icons.bolt,
          gradient: const LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFFFF6B6B), Color(0xFFE03131), Color(0xFFB91C1C)],
          ),
          textColor: Colors.white,
          side: const BorderRadius.all(Radius.circular(10)),
          shadow: const Color(0x33DC2626),
          onTap: () => _openBuySheet(context, p, isBuyNow: true),
        )),
      ]),
    );
  }

  void _openBuySheet(BuildContext context, UellowProductFull p,
      {required bool isBuyNow}) {
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BuySheet(product: p, initialQty: qty, isBuyNow: isBuyNow),
    );
  }
}

/// Beena help icon — gradient bee with a small floating red "Any help?"
/// pill above. Tap opens the Beena chat.
class _BeenaHelpButton extends StatelessWidget {
  const _BeenaHelpButton({required this.onTap, required this.label});
  final VoidCallback onTap;
  final String label;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 44, height: 50,
        child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
          // Bee icon
          Container(
            width: 38, height: 38,
            margin: const EdgeInsets.only(top: 8),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                center: Alignment(-0.4, -0.5),
                colors: [Color(0xFFFFE066), UellowColors.yellow, Color(0xFFC99000)],
              ),
              boxShadow: [BoxShadow(
                color: Color(0x4DF5C320), blurRadius: 10, offset: Offset(0, 4)),
              ],
            ),
            alignment: Alignment.center,
            child: const Text('✨', style: TextStyle(fontSize: 22)),
          ),
          // "Any help?" floating red pill — points down with a tiny tail
          Positioned(
            top: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: UellowColors.danger,
                borderRadius: BorderRadius.circular(8),
                boxShadow: const [BoxShadow(
                    color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 1))],
              ),
              child: Text(label, style: const TextStyle(
                  color: Colors.white, fontSize: 8.5,
                  fontWeight: FontWeight.w900, letterSpacing: 0.2)),
            ),
          ),
        ]),
      ),
    );
  }
}

// ─── Shared gradient CTA button used by the bottom bar ───────────

class _CtaButton extends StatelessWidget {
  const _CtaButton({
    required this.label, required this.icon, required this.gradient,
    required this.textColor, required this.onTap, required this.side,
    this.shadow,
  });
  final String label;
  final IconData icon;
  final Gradient gradient;
  final Color textColor;
  final VoidCallback onTap;
  final BorderRadius side;
  final Color? shadow;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: side,
      child: InkWell(
        onTap: onTap,
        borderRadius: side,
        child: Container(
          height: 38,
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: side,
            boxShadow: shadow != null
                ? [BoxShadow(color: shadow!, blurRadius: 6, offset: const Offset(0, 3))]
                : null,
          ),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 14, color: textColor),
            const SizedBox(width: 5),
            Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w900,
                  color: textColor, fontSize: 11.5, letterSpacing: 0.1))),
          ]),
        ),
      ),
    );
  }
}

// ─── Buy sheet (qty + variants + ATC/Buy now) ──────────────────────

class _BuySheet extends StatefulWidget {
  const _BuySheet({required this.product, required this.initialQty, required this.isBuyNow});
  final UellowProductFull product;
  final int initialQty;
  final bool isBuyNow;
  @override
  State<_BuySheet> createState() => _BuySheetState();
}

class _BuySheetState extends State<_BuySheet> {
  int _qty = 1;
  int _selectedColor = 0;
  String _selectedSize = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _qty = widget.initialQty.clamp(1, 9999);
  }

  UellowAttributeLine? get _colorLine {
    for (final a in widget.product.attributes) {
      final n = a.attributeName.current(UellowApi.instance.lang).toLowerCase();
      if (n.contains('color') || n.contains('لون')) return a;
    }
    return null;
  }

  UellowAttributeLine? get _sizeLine {
    for (final a in widget.product.attributes) {
      final n = a.attributeName.current(UellowApi.instance.lang).toLowerCase();
      if (n.contains('size') || n.contains('مقاس')) return a;
    }
    return null;
  }

  String get _imageUrl {
    final cl = _colorLine;
    if (cl != null && cl.values.isNotEmpty
        && _selectedColor < cl.values.length) {
      final img = cl.values[_selectedColor].image;
      if (img != null && img.isNotEmpty) return img;
    }
    return widget.product.images.isNotEmpty
        ? widget.product.images.first : widget.product.image;
  }

  Future<void> _confirm() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await UellowApi.instance.cart.add(productId: widget.product.id, qty: _qty);
      if (!mounted) return;
      // Capture the NavigatorState BEFORE popping the buy sheet —
      // `context` becomes stale once the modal route is removed, which
      // was the root cause of the "buttons in success dialog do nothing"
      // bug. NavigatorState survives the pop.
      final nav = Navigator.of(context);
      nav.pop();
      if (widget.isBuyNow) {
        nav.pushNamed('/checkout');
      } else {
        _showAtcSuccessDialog(nav.context, widget.product, _qty);
      }
    } on UellowApiException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final lang = UellowApi.instance.lang;
    final ar = lang == 'ar';
    final hasDiscount = p.comparePrice != null
        && p.comparePrice!.amount > p.price.amount;
    final save = hasDiscount ? p.comparePrice!.amount - p.price.amount : 0.0;
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 8),
        Center(child: Container(width: 40, height: 4,
            decoration: BoxDecoration(color: UellowColors.border,
                borderRadius: BorderRadius.circular(2)))),
        Flexible(child: ListView(
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
          children: [
            // ── Big full-width image with zoom button ────────────
            AspectRatio(
              aspectRatio: 1.4,
              child: Stack(children: [
                Positioned.fill(child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 18),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAFAFA),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: CachedNetworkImage(
                    imageUrl: _imageUrl, fit: BoxFit.contain,
                  ),
                )),
                Positioned(top: 12, right: 30,
                    child: GestureDetector(
                      onTap: () => _openZoom(context),
                      child: Container(
                        width: 36, height: 36,
                        decoration: const BoxDecoration(
                          color: Color(0xF2FFFFFF), shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: Color(0x14000000),
                              blurRadius: 6, offset: Offset(0, 2))],
                        ),
                        child: const Icon(Icons.zoom_out_map, size: 18,
                            color: UellowColors.darkBrown),
                      ),
                    )),
              ]),
            ),
            const SizedBox(height: 14),
            // ── Name + price ────────────────────────
            Padding(padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.name.current(lang), maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15,
                      fontWeight: FontWeight.w800, color: UellowColors.ink)),
              const SizedBox(height: 8),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(p.price.formatLocalized(lang), style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w900,
                    color: UellowColors.ink, letterSpacing: -0.3)),
                if (hasDiscount) ...[
                  const SizedBox(width: 10),
                  Padding(padding: const EdgeInsets.only(bottom: 4),
                      child: MidStrikePrice(
                          text: p.comparePrice!.amount.toStringAsFixed(3),
                          fontSize: 14, color: UellowColors.muted,
                          lineColor: UellowColors.danger)),
                ],
                const Spacer(),
                if (hasDiscount) Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: UellowColors.danger,
                      borderRadius: BorderRadius.circular(6)),
                  child: Text('-${p.discountPct}%', style: const TextStyle(
                      color: Colors.white, fontSize: 11,
                      fontWeight: FontWeight.w900)),
                ),
              ]),
              if (hasDiscount) Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text((ar
                    ? 'وفّر ${save.toStringAsFixed(3)} ${p.price.displaySymbol(lang)}'
                    : 'You save ${save.toStringAsFixed(3)} ${p.price.displaySymbol(lang)}'),
                    style: const TextStyle(fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: UellowColors.successDk)),
              ),
            ])),
            const Divider(height: 24, color: UellowColors.border),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // ── Color variants ─────────────────────────
            if (_colorLine != null) ...[
              Text(ar ? 'اللون' : 'Color',
                  style: const TextStyle(fontSize: 11, color: UellowColors.muted,
                      fontWeight: FontWeight.w800, letterSpacing: 0.5)),
              const SizedBox(height: 8),
              SizedBox(height: 86, child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _colorLine!.values.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final v = _colorLine!.values[i];
                  final on = i == _selectedColor;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedColor = i),
                    child: Container(
                      width: 64,
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: on ? UellowColors.yellow : Colors.transparent,
                            width: 2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 54, height: 54,
                            child: (v.image != null && v.image!.isNotEmpty)
                              ? CachedNetworkImage(imageUrl: v.image!, fit: BoxFit.cover)
                              : Container(color: _hexColor(v.htmlColor)),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(v.name.current(lang), maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: UellowColors.text)),
                      ]),
                    ),
                  );
                },
              )),
              const SizedBox(height: 12),
            ],
            // ── Size variants ──────────────────────────
            if (_sizeLine != null) ...[
              Text(ar ? 'المقاس' : 'Size',
                  style: const TextStyle(fontSize: 11, color: UellowColors.muted,
                      fontWeight: FontWeight.w800, letterSpacing: 0.5)),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final v in _sizeLine!.values)
                  GestureDetector(
                    onTap: () => setState(() => _selectedSize = v.name.current(lang)),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: _selectedSize == v.name.current(lang)
                            ? UellowColors.darkBrown : Colors.white,
                        border: Border.all(color: UellowColors.border, width: 1.5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(v.name.current(lang), style: TextStyle(
                        color: _selectedSize == v.name.current(lang)
                            ? UellowColors.yellowLight : UellowColors.text,
                        fontWeight: FontWeight.w800, fontSize: 13,
                      )),
                    ),
                  ),
              ]),
              const SizedBox(height: 12),
            ],
            // ── Quantity ───────────────────────────────
            Text(ar ? 'الكميه' : 'Quantity',
                style: const TextStyle(fontSize: 11, color: UellowColors.muted,
                    fontWeight: FontWeight.w800, letterSpacing: 0.5)),
            const SizedBox(height: 8),
            Row(children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: UellowColors.bg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: UellowColors.border),
                ),
                child: Row(children: [
                  _qtyBtn('−', () => _qty > 1 ? setState(() => _qty--) : null),
                  SizedBox(width: 36, child: Text('$_qty',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
                  _qtyBtn('+', () => setState(() => _qty++)),
                ]),
              ),
              const Spacer(),
              Text(ar ? 'الإجمالي' : 'Subtotal',
                  style: const TextStyle(fontSize: 11, color: UellowColors.muted,
                      fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              Text('${(p.price.amount * _qty).toStringAsFixed(3)} ${p.price.displaySymbol(lang)}',
                  style: const TextStyle(fontSize: 16,
                      fontWeight: FontWeight.w900, color: UellowColors.ink)),
            ]),
            ])),    // close horizontal-padding Column+Padding for variants
          ],
        )),
        // ── Confirm CTA ─────────────────────────────────
        SafeArea(top: false, child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: SizedBox(width: double.infinity, child: ElevatedButton.icon(
            onPressed: _busy ? null : _confirm,
            icon: Icon(widget.isBuyNow ? Icons.bolt : Icons.add_shopping_cart,
                size: 18, color: widget.isBuyNow ? Colors.white : UellowColors.darkBrown),
            label: Text(_busy
                ? (ar ? 'جارٍ التنفيذ…' : 'Working…')
                : (widget.isBuyNow
                    ? T.t('product.buy_now') : T.t('product.add_cart')),
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15,
                    color: widget.isBuyNow ? Colors.white : UellowColors.darkBrown)),
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.isBuyNow ? UellowColors.danger : UellowColors.yellow,
              foregroundColor: widget.isBuyNow ? Colors.white : UellowColors.darkBrown,
              padding: const EdgeInsets.symmetric(vertical: 16),
              elevation: 4,
              shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(14))),
            ),
          )),
        )),
      ]),
    );
  }

  Widget _qtyBtn(String label, VoidCallback? onTap) {
    return GestureDetector(onTap: onTap, child: Container(
      width: 32, height: 32, alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.all(Radius.circular(6)),
      ),
      child: Text(label, style: const TextStyle(
          color: UellowColors.darkBrown, fontWeight: FontWeight.w900, fontSize: 18)),
    ));
  }

  Color _hexColor(String hex) {
    final h = hex.replaceAll('#', '');
    if (h.length == 6) {
      try { return Color(int.parse('ff$h', radix: 16)); } catch (_) {}
    }
    return UellowColors.muted;
  }

  void _openZoom(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => _ImageZoom(url: _imageUrl)));
  }
}

class _ImageZoom extends StatelessWidget {
  const _ImageZoom({required this.url});
  final String url;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(child: Stack(children: [
        Positioned.fill(child: InteractiveViewer(
          minScale: 1.0, maxScale: 4.0,
          child: Center(child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain)),
        )),
        Positioned(top: 8, right: 8, child: IconButton(
          icon: const Icon(Icons.close, color: Colors.white, size: 28),
          onPressed: () => Navigator.pop(context),
        )),
      ])),
    );
  }
}

void _showAtcSuccessDialog(BuildContext context, UellowProductFull p, int qty) {
  final ar = UellowApi.instance.lang == 'ar';
  showModalBottomSheet(
    context: context, backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) {
      // Capture this sheet's own NavigatorState so the buttons keep
      // working even after a re-parent (e.g. lang switch rebuilds).
      return Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: UellowColors.border,
                  borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 18),
          Container(
            width: 64, height: 64,
            decoration: const BoxDecoration(
                color: UellowColors.successBg, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: const Icon(Icons.check_circle, size: 40, color: UellowColors.success),
          ),
          const SizedBox(height: 12),
          Text(ar ? 'تمت إضافة المنتج إلى السلة' : 'Added to your cart',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900,
                  color: UellowColors.ink)),
          const SizedBox(height: 4),
          Text('$qty × ${p.name.current(UellowApi.instance.lang)}',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: UellowColors.muted)),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: () => Navigator.of(sheetContext).pop(),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: UellowColors.border, width: 1.5),
              ),
              child: Text(ar ? 'متابعة التسوق' : 'Continue shopping',
                  style: const TextStyle(fontWeight: FontWeight.w800,
                      color: UellowColors.darkBrown)),
            )),
            const SizedBox(width: 10),
            Expanded(child: ElevatedButton.icon(
              onPressed: () {
                final nav = Navigator.of(sheetContext);
                nav.pop();
                nav.pushNamed('/cart');
              },
              icon: const Icon(Icons.shopping_cart, size: 16,
                  color: UellowColors.darkBrown),
              label: Text(ar ? 'الذهاب إلى السلة' : 'Go to cart',
                  style: const TextStyle(fontWeight: FontWeight.w900,
                      color: UellowColors.darkBrown)),
              style: ElevatedButton.styleFrom(
                backgroundColor: UellowColors.yellow,
                foregroundColor: UellowColors.darkBrown,
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 4,
              ),
            )),
          ]),
        ]),
      );
    },
  );
}

// ─── Write review bottom sheet ────────────────────────────────────

class _WriteReviewSheet extends StatefulWidget {
  const _WriteReviewSheet({required this.productId, required this.onSubmitted});
  final int productId;
  final VoidCallback onSubmitted;
  @override
  State<_WriteReviewSheet> createState() => _WriteReviewSheetState();
}

class _WriteReviewSheetState extends State<_WriteReviewSheet> {
  int _rating = 5;
  final _body = TextEditingController();
  final List<File> _photos = [];
  bool _busy = false;

  Future<void> _pickPhoto(ImageSource src) async {
    final picker = ImagePicker();
    final p = await picker.pickImage(source: src,
        maxWidth: 1280, maxHeight: 1280, imageQuality: 80);
    if (p == null || !mounted) return;
    setState(() => _photos.add(File(p.path)));
  }

  Future<List<String>> _encodePhotos() async {
    final out = <String>[];
    for (final f in _photos) {
      try {
        final bytes = await f.readAsBytes();
        out.add(base64Encode(bytes));
      } catch (_) {}
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    final pad = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: pad),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: Container(width: 36, height: 4,
              decoration: BoxDecoration(color: UellowColors.border,
                  borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 14),
          Text(T.t('reviews.write'), style: UT.h2),
          const SizedBox(height: 14),
          Text(T.t('reviews.rating'), style: const TextStyle(
              fontSize: 12, color: UellowColors.muted,
              fontWeight: FontWeight.w800, letterSpacing: 0.5)),
          const SizedBox(height: 6),
          Row(children: [for (var i = 1; i <= 5; i++) GestureDetector(
            onTap: () => setState(() => _rating = i),
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(i <= _rating ? Icons.star : Icons.star_border,
                  size: 32, color: UellowColors.yellow),
            ),
          )]),
          const SizedBox(height: 14),
          Text(T.t('reviews.comment'), style: const TextStyle(
              fontSize: 12, color: UellowColors.muted,
              fontWeight: FontWeight.w800, letterSpacing: 0.5)),
          const SizedBox(height: 6),
          TextField(
            controller: _body,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: ar ? 'شاركنا رأيك بالمنتج…' : 'Tell others what you think…',
              fillColor: UellowColors.yellowFaint, filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: UellowColors.border, width: 1.5)),
            ),
          ),
          const SizedBox(height: 12),
          // Photo picker — up to 8 attachments. Each preview has a
          // remove button. Tap the dashed add tile to choose source.
          Text(ar ? 'الصور (اختياري)' : 'Photos (optional)',
              style: const TextStyle(fontSize: 12, color: UellowColors.muted,
                  fontWeight: FontWeight.w800, letterSpacing: 0.5)),
          const SizedBox(height: 6),
          SizedBox(height: 78, child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _photos.length + (_photos.length >= 8 ? 0 : 1),
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              if (i == _photos.length) return _addPhotoTile(ar);
              return Stack(children: [
                ClipRRect(borderRadius: BorderRadius.circular(10),
                    child: Image.file(_photos[i],
                        width: 78, height: 78, fit: BoxFit.cover)),
                Positioned(top: 2, right: 2, child: GestureDetector(
                  onTap: () => setState(() => _photos.removeAt(i)),
                  child: Container(
                    width: 20, height: 20, alignment: Alignment.center,
                    decoration: const BoxDecoration(
                        color: Colors.black54, shape: BoxShape.circle),
                    child: const Icon(Icons.close, size: 12, color: Colors.white),
                  ),
                )),
              ]);
            },
          )),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: _busy ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: UellowColors.yellow,
              foregroundColor: UellowColors.darkBrown,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: _busy
              ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2,
                      color: UellowColors.darkBrown))
              : Text(T.t('reviews.submit'),
                  style: const TextStyle(fontWeight: FontWeight.w900)),
          )),
        ]),
      ),
    );
  }

  Widget _addPhotoTile(bool ar) {
    return GestureDetector(
      onTap: () => showModalBottomSheet(context: context, builder: (sheetCtx) =>
          SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: Text(ar ? 'التقط صورة' : 'Take photo'),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                _pickPhoto(ImageSource.camera);
              }),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(ar ? 'من المعرض' : 'From gallery'),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                _pickPhoto(ImageSource.gallery);
              }),
          ]))),
      child: Container(
        width: 78, height: 78,
        decoration: BoxDecoration(
          color: UellowColors.yellowFaint,
          border: Border.all(color: UellowColors.warnBg, width: 1.5),
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.add_a_photo_outlined,
              size: 22, color: UellowColors.darkBrown),
          const SizedBox(height: 2),
          Text(ar ? 'إضافة' : 'Add',
              style: const TextStyle(fontSize: 10,
                  fontWeight: FontWeight.w800, color: UellowColors.darkBrown)),
        ]),
      ),
    );
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ar = UellowApi.instance.lang == 'ar';
    try {
      final photosB64 = await _encodePhotos();
      await UellowApi.instance.reviews.create(
        productId: widget.productId,
        rating: _rating.toDouble(),
        body: _body.text.trim().isEmpty
            ? (ar ? 'لا توجد ملاحظات' : 'No comment')
            : _body.text.trim(),
        photosBase64: photosB64,
      );
      if (!mounted) return;
      nav.pop();
      messenger.showSnackBar(SnackBar(content: Text(T.t('reviews.thanks'))));
      widget.onSubmitted();
    } on UellowApiException catch (e) {
      if (mounted) setState(() => _busy = false);
      if (e.isAuthError) {
        nav.pop();
        nav.pushNamed('/auth');
      } else {
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }
}

// ─── Verified badge (scalloped) ────────────────────────────────────

class _VerifiedBadge extends StatelessWidget {
  const _VerifiedBadge({this.size = 20});
  final double size;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size, height: size,
      child: Stack(alignment: Alignment.center, children: [
        CustomPaint(
          size: Size.square(size),
          painter: _ScallopPainter(color: const Color(0xFF1DA1F2)),
        ),
        Icon(Icons.check, size: size * 0.55, color: Colors.white),
      ]),
    );
  }
}

class _ScallopPainter extends CustomPainter {
  const _ScallopPainter({required this.color});
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    // Two interleaved offset circles produce a star/scallop with 8 bumps.
    // Easier: draw a regular 8-bumped path using cubics.
    const bumps = 12;
    final outer = size.width / 2;
    final inner = outer * 0.84;
    final path = Path();
    for (var i = 0; i < bumps * 2; i++) {
      final r = i.isEven ? outer : inner;
      final theta = (i / (bumps * 2)) * 2 * 3.141592653589793;
      final x = cx + r * math.cos(theta);
      final y = cy + r * math.sin(theta);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    canvas.drawPath(path, paint);
  }
  @override
  bool shouldRepaint(covariant _ScallopPainter old) => old.color != color;
}
