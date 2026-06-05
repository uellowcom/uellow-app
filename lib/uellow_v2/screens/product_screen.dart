// =============================================================================
// ProductScreen — fully wired to v2 API. Real sold/views, brand block,
// bulk pricing, real description, real specs, paginated reviews, infinite
// load related, working share + wishlist + delivery sheet.
// =============================================================================
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../api/uellow_api.dart';
import '../../api/uellow_models.dart';
import '../router/uellow_router.dart';
import '../services/first_launch_service.dart';
import '../theme/uellow_l10n.dart';
import '../theme/uellow_theme.dart';
import 'auth_screen.dart';
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

  // v2.1.56 — sticky section tabs (نظرة عامة/التفاصيل/التقييمات/مقترحات)
  // that scroll to their section, AliExpress-style.
  final _kOverview = GlobalKey();
  final _kDetails = GlobalKey();
  final _kReviews = GlobalKey();
  final _kRelated = GlobalKey();
  int _sectionTab = 0;

  void _goSection(int i) {
    setState(() => _sectionTab = i);
    final key = [_kOverview, _kDetails, _kReviews, _kRelated][i];
    final ctx = key.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOut, alignment: 0.0);
    }
  }

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
          // v2.0.78 — pull-to-refresh wraps the scroll so the user can
          // drag the product page down to reload its data (price, stock,
          // related products, etc.).
          return RefreshIndicator(
            color: UellowColors.darkBrown,
            backgroundColor: Colors.white,
            onRefresh: () async {
              final f = UellowApi.instance.products.detail(widget.productId);
              setState(() { _future = f; });
              await f;
            },
            child: _buildScroll(snap.data!),
          );
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

    return CustomScrollView(
      // v2.0.78 — AlwaysScrollableScrollPhysics so the RefreshIndicator
      // above can trigger even when the page hasn't fully overflowed.
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
      SliverToBoxAdapter(child: _Gallery(
        images: gallery, videos: p.videos, page: _galleryPage,
        promo: p.promo,
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
      // v2.1.35 — promotion banner: SAME flash-sale style strip, but with
      // the campaign's own emoji / colors / pattern / title / subtitle
      // (configured per promotion in the backend) + live countdown.
      if (p.flashEndsAt == null && (p.promo?['banner'] as Map?) != null)
        SliverToBoxAdapter(child: Builder(builder: (_) {
          final b = (p.promo!['banner'] as Map).cast<String, dynamic>();
          final ar = UellowApi.instance.lang.toLowerCase().startsWith('ar');
          final l = ar ? 'ar' : 'en';
          final cols = ((b['colors'] as List?) ?? const [])
              .map((c) => _hexColor(c, UellowColors.yellow))
              .toList();
          final pct = ((p.promo!['discount_pct'] as num?) ?? 0).toInt();
          var iconUrl = (b['icon_url'] ?? '').toString();
          if (iconUrl.startsWith('/')) {
            iconUrl = '${UellowApi.instance.baseUrl}$iconUrl';
          }
          return FlashBanner(
            endsAt: DateTime.tryParse(
                (p.promo!['ends_at'] ?? '').toString()),
            compact: false, edgeToEdge: true,
            emoji: (b['emoji'] ?? '🎯').toString(),
            colors: cols.isEmpty ? null : cols,
            pattern: b['pattern'] != false,
            // v2.1.39 — pattern style + uploaded campaign icon (the icon
            // replaces the discount circle when set).
            patternStyle: (b['pattern_style'] ?? 'stripes').toString(),
            iconUrl: iconUrl.isEmpty ? null : iconUrl,
            iconBg: _hexColor(b['icon_bg'], Colors.white),
            discountPct: (iconUrl.isEmpty && pct > 0) ? pct : null,
            title: ((b['title'] as Map?)?[l] ?? '').toString(),
            subtitle: ((b['subtitle'] as Map?)?[l] ?? '').toString().isEmpty
                ? null
                : ((b['subtitle'] as Map?)?[l] ?? '').toString(),
          );
        })),
      // v2.1.56 — sticky section tabs; pin to the top once the gallery
      // scrolls away and jump to their section on tap.
      SliverPersistentHeader(pinned: true, delegate: _SectionTabs(
          tab: _sectionTab, onTap: _goSection)),
      SliverToBoxAdapter(child: KeyedSubtree(
          key: _kOverview, child: _Title(p: p))),
      SliverToBoxAdapter(child: _PriceRow(p: p)),
      // v2.0.78 — when a product has no vendor, show a "Fulfilled by
      // Uellow" badge so the user knows who's responsible (instead of an
      // empty / missing seller card).
      if (p.vendor != null)
        SliverToBoxAdapter(child: _VendorCard(vendor: p.vendor!))
      else
        const SliverToBoxAdapter(child: _FulfilledByUellowCard()),
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
      // v2.1.24 — Best Seller rank strip (tappable → that category).
      if (p.ranks.isNotEmpty)
        SliverToBoxAdapter(child: _RankStrip(ranks: p.ranks)),
      // v2.1.25 — price-history insight (sparkline + min/max).
      if (p.priceHistory != null
          && ((p.priceHistory!['points'] as List?)?.length ?? 0) >= 2)
        SliverToBoxAdapter(child: _PriceHistoryBlock(
            history: p.priceHistory!, trend: p.priceTrend)),
      // v2.1.35 — the "verified reviews" highlight strip was removed per
      // request; the full reviews block lower on the page remains.
      // v2.1.31 — specialist reviewers (uellow_reviewers): latest expert
      // verdicts + "ask a specialist" CTA.
      SliverToBoxAdapter(child: _ExpertReviewsBlock(productId: p.id)),
      // Show whenever there's at least one bulk tier — even a single
      // "buy 5+ → save 5%" hint is useful.
      if (p.bulkPricing.isNotEmpty)
        SliverToBoxAdapter(child: _BulkPricing(
          tiers: p.bulkPricing,
          currentQty: _qty,
          onTierTap: (minQty) => setState(() => _qty = minQty),
        )),
      SliverToBoxAdapter(child: KeyedSubtree(
          key: _kDetails, child: _DescriptionBlock(product: p))),
      SliverToBoxAdapter(child: _SpecsBlock(product: p,
          onOpen: () => _showSpecsDialog(context, p))),
      SliverToBoxAdapter(child: KeyedSubtree(
          key: _kReviews, child: _ReviewsBlock(productId: p.id))),
      SliverToBoxAdapter(child: KeyedSubtree(
          key: _kRelated, child: _RelatedInfinite(
          productId: p.id,
          categoryId: p.categories.isNotEmpty ? p.categories.first.id : null))),
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
    this.promo,
  });
  final Map<String, dynamic>? promo;
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
              // v2.0.78 — pass the first product image as a fallback
              // thumbnail so video tiles aren't featureless black squares.
              return _VideoTile(
                video: it['video'] as UellowProductVideo,
                fallbackImage: images.isNotEmpty ? images.first : null,
              );
            }
            return CachedNetworkImage(imageUrl: it['url'] as String, fit: BoxFit.contain);
          },
        )),
        // v2.1.43 — gallery promotion coin REMOVED per request (the
        // flash-style promo banner below the gallery is enough).
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
        // v2.0.76 — flip back-arrow icon in AR. Position stays on the
        // left so the wishlist/cart buttons keep their right-side row.
        Positioned(top: 14, left: 14, child: _btn(
            icon: UellowApi.instance.lang.toLowerCase().startsWith('ar')
                ? Icons.arrow_forward_ios : Icons.arrow_back_ios_new,
            color: UellowColors.darkBrown,
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
  const _VideoTile({required this.video, this.fallbackImage});
  final UellowProductVideo video;
  // v2.0.78 — if the video has no thumbnail AND we can't derive one from
  // YouTube, fall back to one of the product's gallery images so the
  // tile isn't a featureless black square.
  final String? fallbackImage;
  String get _thumb {
    // v2.1.16 — the PRODUCT image is the video cover (per request), with
    // the video's own thumbnail as the fallback. Absolute (Bunny CDN)
    // thumbnail URLs are used as-is — prefixing baseUrl broke them.
    if (fallbackImage != null && fallbackImage!.isNotEmpty) return fallbackImage!;
    if (video.thumbnail.isNotEmpty) {
      return video.thumbnail.startsWith('http')
          ? video.thumbnail
          : '${UellowApi.instance.baseUrl}${video.thumbnail}';
    }
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
          // v2.1.29 — Price-Intelligence badge at the end of the line.
          if (p.priceTrend != null) Builder(builder: (_) {
            final t = p.priceTrend!;
            final ar2 = lang.toLowerCase().startsWith('ar');
            final dir = (t['direction'] ?? 'stable').toString();
            final lowest = t['is_lowest'] == true;
            final down = dir == 'down' || lowest;
            final stable = dir == 'stable' && !lowest;
            final color = stable
                ? const Color(0xFF1565C0)
                : (down ? UellowColors.successDk : UellowColors.danger);
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                border: Border.all(color: color.withValues(alpha: 0.45)),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(stable ? Icons.trending_flat
                        : (down ? Icons.trending_down : Icons.trending_up),
                    size: 12, color: color),
                const SizedBox(width: 3),
                Text((((t['label'] as Map?)?[ar2 ? 'ar' : 'en']) ?? '')
                        .toString(),
                    style: TextStyle(fontSize: 10,
                        fontWeight: FontWeight.w800, color: color)),
              ]),
            );
          }),
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
          // v2.1.31 — simple Best-Seller mark: no background, plain gold.
          if (p.ranks.isNotEmpty) Flexible(child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 8),
            child: GestureDetector(
              onTap: () {
                final cid = p.ranks.first['category_id'] as int?;
                if (cid != null) {
                  Navigator.pushNamed(context, '/collection',
                      arguments: {'category_id': cid});
                }
              },
              child: Text(
                '🏆 ${(((p.ranks.first['label'] as Map?)?[lang.toLowerCase().startsWith('ar') ? 'ar' : 'en']) ?? '')}',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10.5,
                    fontWeight: FontWeight.w800, color: Color(0xFFB8860B)),
              ),
            ),
          )),
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
    // v2.0.77 redesign — keep everything on ONE line:
    //   • Big price with the currency symbol in a smaller superscript-ish
    //     font (saves horizontal space)
    //   • Struck-through compare price in black (was muted)
    //   • Discount pill: RED background (was green)
    //   • Save pill: GREEN background (was red) — same row, never wraps
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        // Price + small currency symbol (baseline-aligned)
        Text.rich(TextSpan(children: [
          TextSpan(text: p.price.amount.toStringAsFixed(3),
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900,
                  color: UellowColors.darkBrown, letterSpacing: -0.4, height: 1.0)),
          const TextSpan(text: ' '),
          TextSpan(text: sym,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                  color: UellowColors.muted, height: 1.0)),
        ])),
        if (hasDisc) ...[
          const SizedBox(width: 8),
          MidStrikePrice(
            text: p.comparePrice!.amount.toStringAsFixed(3),
            fontSize: 13, color: Colors.black87,
            lineColor: Colors.black87),
          const SizedBox(width: 6),
          // -X% pill — RED (the discount is the "warning" we want to draw the
          // eye to, then the green "Save" pill reinforces the positive value)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: UellowColors.danger,
                borderRadius: BorderRadius.circular(4)),
            child: Text('-${p.discountPct}%',
                style: const TextStyle(color: Colors.white,
                    fontSize: 10.5, fontWeight: FontWeight.w900, height: 1.0)),
          ),
          const SizedBox(width: 6),
          // Save pill — GREEN now; smaller text so the whole row stays on
          // a single line. Wrapped in Flexible so it clips with ellipsis
          // instead of wrapping if the screen is really narrow.
          Flexible(child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: UellowColors.success,
                borderRadius: BorderRadius.circular(4)),
            child: Text('$saveLabel ${save.toStringAsFixed(3)} $sym',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white,
                    fontSize: 10.5, fontWeight: FontWeight.w900, height: 1.0)),
          )),
        ],
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
            // v2.1.16 — brand logo: white background + BoxFit.contain so the
            // WHOLE logo is visible inside the square (cover was cropping it).
            Container(
              width: 52, height: 52,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: UellowColors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: (brand.image != null && brand.image!.isNotEmpty)
                ? CachedNetworkImage(imageUrl: brand.image!, fit: BoxFit.contain,
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

// v2.0.78 — fallback for products without a vendor — shows that Uellow
// itself fulfils the order. Mirrors _VendorCard's footprint so screen
// layout stays consistent.
class _FulfilledByUellowCard extends StatelessWidget {
  const _FulfilledByUellowCard();
  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    // v2.0.91 — shorter, slimmer card (was a 3-line block with a 44px
    // logo tile). Logo + single inline caption now fit in ~36px height.
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: UellowColors.yellowSoft,
          border: Border.all(color: UellowColors.yellow, width: 1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: UellowColors.yellow,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: UellowColors.darkBrown, width: 1),
            ),
            alignment: Alignment.center,
            child: const Text('u.',
                style: TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: UellowColors.darkBrown, letterSpacing: -0.5)),
          ),
          const SizedBox(width: 9),
          const Icon(Icons.verified_outlined, size: 12,
              color: UellowColors.muted),
          const SizedBox(width: 4),
          Expanded(child: Text.rich(TextSpan(children: [
            TextSpan(text: ar ? 'تم بواسطة ' : 'Fulfilled by ',
                style: const TextStyle(fontSize: 11,
                    color: UellowColors.muted, fontWeight: FontWeight.w700)),
            const TextSpan(text: 'Uellow',
                style: TextStyle(fontWeight: FontWeight.w900,
                    fontSize: 12.5, color: UellowColors.darkBrown)),
            TextSpan(text: ar
                ? '  —  شحن واستبدال مباشر'
                : '  —  shipping, returns, support',
                style: const TextStyle(fontSize: 10.5,
                    color: UellowColors.muted, fontWeight: FontWeight.w600)),
          ]), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
      ),
    );
  }
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

Color _hexColor(Object? raw, Color fallback) {
  try {
    var s = (raw ?? '').toString().replaceAll('#', '');
    // v2.1.56 — was the LITERAL string 'FF\$s' (escaped $), so every
    // 6-digit hex failed to parse and fell back to the default color:
    // the "banner colors / icon circle never change from the backend"
    // bug. Now interpolates correctly.
    if (s.length == 6) s = 'FF$s';
    return Color(int.parse(s, radix: 16));
  } catch (_) {
    return fallback;
  }
}

// ─── Best Seller rank strip (v2.1.24) ─────────────────────────────

class _RankStrip extends StatelessWidget {
  const _RankStrip({required this.ranks});
  final List<Map<String, dynamic>> ranks;
  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang.toLowerCase().startsWith('ar');
    return Container(
      color: Colors.white, margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final r in ranks.take(3)) Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: InkWell(
            onTap: () {
              final cid = r['category_id'] as int?;
              if (cid != null) {
                Navigator.pushNamed(context, '/collection',
                    arguments: {'category_id': cid});
              }
            },
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFFFFD700), Color(0xFFE8A800)]),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('🏆 #${r['rank']}',
                    style: const TextStyle(fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF412402))),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(
                  (((r['label'] as Map?)?[ar ? 'ar' : 'en']) ?? '').toString(),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: UellowColors.darkBrown))),
              Icon(ar ? Icons.chevron_left : Icons.chevron_right,
                  size: 16, color: UellowColors.muted),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ─── Price-history insight (v2.1.25) ──────────────────────────────

class _PriceHistoryBlock extends StatelessWidget {
  const _PriceHistoryBlock({required this.history, this.trend});
  final Map<String, dynamic> history;
  final Map<String, dynamic>? trend;
  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang.toLowerCase().startsWith('ar');
    final pts = ((history['points'] as List?) ?? const [])
        .map((e) => ((e as Map)['p'] as num).toDouble()).toList();
    final mn = (history['min'] as num?)?.toDouble() ?? 0;
    final mx = (history['max'] as num?)?.toDouble() ?? 0;
    final cur = (history['current'] as num?)?.toDouble() ?? 0;
    final days = history['days'] ?? 90;
    final t = trend;
    final lowest = t?['is_lowest'] == true;
    return Container(
      color: Colors.white, margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.query_stats, size: 16, color: UellowColors.darkBrown),
          const SizedBox(width: 6),
          Text(ar ? 'تتبع السعر' : 'Price tracker', style: UT.h3),
          const Spacer(),
          Text(ar ? 'آخر $days يوم' : 'Last $days days',
              style: const TextStyle(fontSize: 10.5, color: UellowColors.muted,
                  fontWeight: FontWeight.w700)),
        ]),
        if (lowest) Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1),
              border: Border.all(color: const Color(0xFFE8A800)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.workspace_premium,
                  size: 14, color: Color(0xFFB8860B)),
              const SizedBox(width: 5),
              Text(ar ? '🔥 هذا أقل سعر خلال $days يوم — اغتنمه!'
                      : '🔥 Lowest price in $days days — grab it!',
                  style: const TextStyle(fontSize: 11.5,
                      fontWeight: FontWeight.w900, color: Color(0xFF8B6508))),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(height: 56, width: double.infinity,
            child: CustomPaint(painter: _SparklinePainter(pts))),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _stat(ar ? 'الأدنى' : 'Lowest', mn, UellowColors.successDk),
          _stat(ar ? 'الحالي' : 'Current', cur, UellowColors.darkBrown),
          _stat(ar ? 'الأعلى' : 'Highest', mx, UellowColors.muted),
        ]),
      ]),
    );
  }

  Widget _stat(String label, double v, Color color) => Column(children: [
    Text(label, style: const TextStyle(fontSize: 10,
        color: UellowColors.muted, fontWeight: FontWeight.w700)),
    const SizedBox(height: 2),
    Text(v.toStringAsFixed(3), style: TextStyle(fontSize: 12.5,
        fontWeight: FontWeight.w900, color: color)),
  ]);
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter(this.points);
  final List<double> points;
  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final mn = points.reduce((a, b) => a < b ? a : b);
    final mx = points.reduce((a, b) => a > b ? a : b);
    final span = (mx - mn) == 0 ? 1.0 : (mx - mn);
    final dx = size.width / (points.length - 1);
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = dx * i;
      final y = size.height - ((points[i] - mn) / span) * (size.height - 8) - 4;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    // soft fill under the line
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fill, Paint()
      ..style = PaintingStyle.fill
      ..shader = const LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Color(0x33F5C320), Color(0x00F5C320)],
      ).createShader(Offset.zero & size));
    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFC69B00));
    // end dot = current price
    final lastY = size.height -
        ((points.last - mn) / span) * (size.height - 8) - 4;
    canvas.drawCircle(Offset(size.width, lastY), 3.5,
        Paint()..color = const Color(0xFF412402));
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) =>
      old.points != points;
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
  // v2.1.22 — schedule-aware delivery lines from /orders/delivery-eta:
  // available-now methods show green, off-schedule ones show the next
  // receive day ("اطلب الآن واستلم يوم السبت").
  List<Map<String, dynamic>> _etaLines = const [];

  @override
  void initState() { super.initState(); _loadAddress(); _loadEta(); }

  Future<void> _loadEta() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cc = prefs.getString('uellow_country_code_v1') ?? '';
      final r = await http.get(Uri.parse(
          '${UellowApi.instance.baseUrl}/api/mobile/v2/orders/delivery-eta'
          '${cc.isNotEmpty ? "?country=$cc" : ""}'))
          .timeout(const Duration(seconds: 8));
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (j['success'] == true && mounted) {
        var lines = ((j['data']?['lines'] as List?) ?? const [])
            .cast<Map>().map((m) => m.cast<String, dynamic>()).toList();
        // v2.1.43 — a country filter with no scoped carriers returned an
        // empty list → the block fell back to "pick your address" even
        // for signed-in users. Retry once WITHOUT the country filter.
        if (lines.isEmpty && cc.isNotEmpty) {
          try {
            final r2 = await http.get(Uri.parse(
                '${UellowApi.instance.baseUrl}/api/mobile/v2/orders/delivery-eta'))
                .timeout(const Duration(seconds: 8));
            final j2 = jsonDecode(utf8.decode(r2.bodyBytes))
                as Map<String, dynamic>;
            if (j2['success'] == true) {
              lines = ((j2['data']?['lines'] as List?) ?? const [])
                  .cast<Map>().map((m) => m.cast<String, dynamic>()).toList();
            }
          } catch (_) {}
        }
        if (mounted) setState(() => _etaLines = lines);
      }
    } catch (_) {}
  }

  Future<void> _loadAddress() async {
    // v2.1.22 — "Country - City" format (per the map), as agreed.
    // v2.1.43 — robust fallbacks: an address with no country/city used to
    // produce an EMPTY summary, so signed-in users with a default address
    // still saw "اختر عنوانك". Now: country-city → city → name → street.
    try {
      final addrs = await UellowApi.instance.addresses.list();
      if (addrs.isNotEmpty) {
        final savedId = await UellowApi.instance.tokenStore.readAddressId();
        final pick = addrs.firstWhere((a) => a.id == savedId,
            orElse: () => addrs.firstWhere((a) => a.isDefault,
                orElse: () => addrs.first));
        final parts = [pick.country, pick.city]
            .where((s) => s.isNotEmpty).toList();
        var summary = parts.join(' - ');
        if (summary.isEmpty) summary = pick.city;
        if (summary.isEmpty) summary = pick.name;
        if (summary.isEmpty) summary = pick.street;
        if (summary.isNotEmpty) {
          if (mounted) setState(() => _summary = summary);
          return;
        }
      }
    } catch (_) {/* guest or 401 */}
    try {
      final fix = await FirstLaunchService.lastFix();
      if (fix != null && fix.address.isNotEmpty) {
        // Nominatim: "House, Street, City, Region, Country" — country is
        // the LAST piece; the city sits a couple of pieces before it.
        final pieces = fix.address.split(',').map((s) => s.trim())
            .where((s) => s.isNotEmpty && !RegExp(r'^[0-9]').hasMatch(s))
            .toList();
        if (pieces.isNotEmpty) {
          final country = pieces.last;
          final city = pieces.length >= 3
              ? pieces[pieces.length - 3]
              : (pieces.length >= 2 ? pieces[pieces.length - 2] : '');
          if (mounted) setState(() => _summary =
              city.isNotEmpty ? '$country - $city' : country);
        }
      }
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
            // v2.1.31 — ONE quiet dark-grey line: the EXPRESS method when
            // it is available right now, otherwise just the first option.
            const SizedBox(height: 2),
            Builder(builder: (_) {
              Map<String, dynamic>? pick;
              for (final l in _etaLines) {
                final nm = (((l['name'] as Map?)?['en']) ?? '')
                    .toString().toLowerCase();
                final nmAr = (((l['name'] as Map?)?['ar']) ?? '').toString();
                final isExpress = nm.contains('express')
                    || nm.contains('fast') || nmAr.contains('سريع');
                if (isExpress && l['status'] == 'now') { pick = l; break; }
              }
              pick ??= _etaLines.isNotEmpty ? _etaLines.first : null;
              final txt = pick == null
                  ? (ar ? 'اختر عنوانك لمعرفة مواعيد التوصيل'
                        : 'Pick your address to see delivery times')
                  : '${((pick['name'] as Map?)?[ar ? 'ar' : 'en'] ?? '')}: '
                    '${((pick['text'] as Map?)?[ar ? 'ar' : 'en'] ?? '')}';
              return Text(txt, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10.5, height: 1.3,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF555555)));
            }),
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
  bool _signedIn = false;
  // v2.1.35 — the dialog now shows the FULL delivery picture: every
  // method with live availability, cutoff, price and free-over rule.
  List<Map<String, dynamic>> _etaLines = const [];

  @override
  void initState() {
    super.initState();
    _future = UellowApi.instance.addresses.list().catchError((_) => <UellowAddress>[]);
    _loadEta();
    // v2.1.51 — guests must not see "Manage addresses".
    UellowApi.instance.tokenStore.readToken().then((t) {
      if (mounted) setState(() => _signedIn = t != null && t.isNotEmpty);
    });
  }

  Future<void> _loadEta() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cc = prefs.getString('uellow_country_code_v1') ?? '';
      final r = await http.get(Uri.parse(
          '${UellowApi.instance.baseUrl}/api/mobile/v2/orders/delivery-eta'
          '${cc.isNotEmpty ? "?country=$cc" : ""}'))
          .timeout(const Duration(seconds: 8));
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (j['success'] == true && mounted) {
        setState(() => _etaLines = ((j['data']?['lines'] as List?) ?? const [])
            .cast<Map>().map((m) => m.cast<String, dynamic>()).toList());
      }
    } catch (_) {}
  }

  Widget _methodCard(Map<String, dynamic> l, bool ar) {
    final isNow = l['status'] == 'now';
    final name = ((l['name'] as Map?)?[ar ? 'ar' : 'en'] ?? '').toString();
    final text = ((l['text'] as Map?)?[ar ? 'ar' : 'en'] ?? '').toString();
    final cutoff = (l['cutoff'] ?? '').toString();
    final price = (l['price'] as num?)?.toDouble();
    final freeOver = (l['free_over'] as num?)?.toDouble();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isNow ? const Color(0xFFF2FBF5) : Colors.white,
        border: Border.all(color: isNow
            ? UellowColors.success.withValues(alpha: 0.45)
            : UellowColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(isNow ? Icons.bolt : Icons.schedule,
              size: 16, color: isNow
                  ? UellowColors.successDk : UellowColors.muted),
          const SizedBox(width: 6),
          Expanded(child: Text(name,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13,
                  fontWeight: FontWeight.w800, color: UellowColors.ink))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
            decoration: BoxDecoration(
              color: isNow
                  ? UellowColors.success.withValues(alpha: 0.15)
                  : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
                isNow
                    ? (ar ? 'متاح الآن' : 'Available now')
                    : (ar ? 'لاحقاً' : 'Later'),
                style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900,
                    color: isNow
                        ? UellowColors.successDk : UellowColors.muted)),
          ),
        ]),
        const SizedBox(height: 5),
        Text(text, style: const TextStyle(fontSize: 11.5,
            color: UellowColors.text, height: 1.4)),
        if (cutoff.isNotEmpty || price != null || freeOver != null) ...[
          const SizedBox(height: 6),
          Wrap(spacing: 10, runSpacing: 3, children: [
            if (cutoff.isNotEmpty)
              Text(ar ? '⏰ آخر وقت للطلب: $cutoff'
                      : '⏰ Order cutoff: $cutoff',
                  style: const TextStyle(fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: UellowColors.muted)),
            if (price != null)
              Text(price <= 0
                      ? (ar ? '💰 التوصيل: مجاني' : '💰 Delivery: FREE')
                      : (ar ? '💰 التوصيل: ${price.toStringAsFixed(3)} د.ك'
                            : '💰 Delivery: ${price.toStringAsFixed(3)} KD'),
                  style: const TextStyle(fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: UellowColors.muted)),
            if (freeOver != null && freeOver > 0)
              Text(ar
                      ? '🎁 مجاني للطلبات فوق ${freeOver.toStringAsFixed(3)} د.ك'
                      : '🎁 Free over ${freeOver.toStringAsFixed(3)} KD',
                  style: const TextStyle(fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: UellowColors.successDk)),
          ]),
        ],
      ]),
    );
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
        Padding(padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
            child: Row(children: [
              Text(UellowApi.instance.lang == 'ar' ? 'التوصيل إلى' : 'Deliver to',
                  style: UT.h2),
            ])),
        Flexible(child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          children: [
            // v2.1.35 — FULL delivery details: every method, its live
            // availability, schedule note, cutoff, price and free-over.
            if (_etaLines.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 10, 0, 8),
                child: Row(children: [
                  const Icon(Icons.local_shipping_outlined,
                      size: 16, color: UellowColors.darkBrown),
                  const SizedBox(width: 6),
                  Text(UellowApi.instance.lang == 'ar'
                          ? 'خيارات التوصيل' : 'Delivery options',
                      style: const TextStyle(fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: UellowColors.ink)),
                ]),
              ),
              for (final l in _etaLines)
                _methodCard(l, UellowApi.instance.lang == 'ar'),
            ],
            // v2.1.44 — addresses now come AFTER the delivery options.
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 10, 0, 8),
              child: Row(children: [
                const Icon(Icons.location_on_outlined,
                    size: 16, color: UellowColors.darkBrown),
                const SizedBox(width: 6),
                Text(UellowApi.instance.lang == 'ar'
                        ? 'عناويني' : 'My addresses',
                    style: const TextStyle(fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: UellowColors.ink)),
              ]),
            ),
            FutureBuilder<List<UellowAddress>>(
              future: _future,
              builder: (_, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: Padding(
                    padding: EdgeInsets.all(20), child: CircularProgressIndicator()));
                }
                final list = snap.data ?? [];
                if (list.isEmpty) return _empty();
                return Column(children: [
                  for (final a in list) Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Builder(builder: (_) {
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
                            Text(a.name.isNotEmpty ? a.name : (a.city.isNotEmpty ? a.city : (UellowApi.instance.lang == 'ar' ? 'العنوان' : 'Address')),
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
                            child: Text(UellowApi.instance.lang == 'ar' ? 'افتراضي' : 'DEFAULT',
                                style: const TextStyle(
                                fontSize: 9, fontWeight: FontWeight.w900,
                                color: UellowColors.darkBrown, letterSpacing: 0.5)),
                          ),
                        ]),
                      ));
                    }),
                  ),
                ]);
              },
            ),
          ],
        )),
        Padding(padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
            child: Column(children: [
              // v2.1.51 — signed-in only; guests get the sign-in CTA from
              // the empty-state instead.
              if (_signedIn)
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
                child: Text(UellowApi.instance.lang == 'ar' ? 'إغلاق' : 'Close',
                    style: const TextStyle(color: UellowColors.text)),
              ),
            ])),
      ]),
    );
  }

  Widget _empty() {
    return Padding(padding: const EdgeInsets.all(20), child: Column(children: [
      const Icon(Icons.location_off_outlined, size: 48, color: UellowColors.muted),
      const SizedBox(height: 10),
      Text(UellowApi.instance.lang == 'ar'
          ? 'لا توجد عناوين محفوظة بعد.' : 'No saved addresses yet.', style: UT.body),
      const SizedBox(height: 14),
      SizedBox(width: double.infinity, child: ElevatedButton.icon(
        onPressed: () {
          Navigator.pop(context);
          Navigator.pushNamed(context, '/auth');
        },
        icon: const Icon(Icons.login, size: 16),
        label: Text(UellowApi.instance.lang == 'ar'
            ? 'سجّل الدخول لإضافة عنوان' : 'Sign in to add address'),
        style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14)),
      )),
    ]));
  }
}

// ─── Bulk pricing ─────────────────────────────────────────────────

class _BulkPricing extends StatelessWidget {
  // v2.0.92 — tap-to-select: tapping a tier bumps the screen's qty
  // to that tier's minQty so the existing ATC / Buy Now CTA bar
  // automatically uses the right quantity. The currently-active tier
  // (the one matching the qty) is highlighted.
  const _BulkPricing({
    required this.tiers,
    required this.currentQty,
    required this.onTierTap,
  });
  final List<UellowBulkTier> tiers;
  final int currentQty;
  final ValueChanged<int> onTierTap;

  /// Returns the index of the tier whose qty range covers `qty`.
  int _activeTierIndex() {
    for (int i = tiers.length - 1; i >= 0; i--) {
      if (currentQty >= tiers[i].minQty) return i;
    }
    return -1;
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    final activeIdx = _activeTierIndex();
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
        // v2.0.78 — when more than 3 tiers are configured, switch from a
        // cramped equal-Expanded row to a horizontally-scrollable strip.
        // 3 tiles peek-fit at typical phone widths so the user sees there
        // are more to swipe to.
        // v2.1.21 — tighter grid: up to 4 small tiles share one row.
        if (tiers.length <= 4)
          Row(children: List.generate(tiers.length, (i) {
            final t = tiers[i];
            final nextMin = i < tiers.length - 1 ? tiers[i + 1].minQty - 1 : null;
            final qtyLabel = nextMin != null
                ? '${t.minQty}–$nextMin'
                : '${t.minQty}+';
            return Expanded(child: Padding(
              padding: EdgeInsets.only(right: i < tiers.length - 1 ? 4 : 0),
              child: _tier(qtyLabel: qtyLabel, price: t.price, sym: t.currency,
                  save: t.savePct, best: i == bestIdx && tiers.length > 1,
                  selected: i == activeIdx,
                  onTap: () => onTierTap(t.minQty),
                  capped: t.capped, ar: ar),
            ));
          }))
        else
          SizedBox(
            height: 112,
            child: ListView.separated(
              padding: EdgeInsets.zero,
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              itemCount: tiers.length,
              separatorBuilder: (_, __) => const SizedBox(width: 4),
              itemBuilder: (_, i) {
                final t = tiers[i];
                final nextMin = i < tiers.length - 1 ? tiers[i + 1].minQty - 1 : null;
                final qtyLabel = nextMin != null
                    ? '${t.minQty}–$nextMin'
                    : '${t.minQty}+';
                return SizedBox(
                  width: (MediaQuery.of(context).size.width - 28 - 14 - 12) / 4,
                  child: _tier(qtyLabel: qtyLabel, price: t.price,
                      sym: t.currency, save: t.savePct,
                      best: i == bestIdx,
                      selected: i == activeIdx,
                      onTap: () => onTierTap(t.minQty),
                      capped: t.capped, ar: ar),
                );
              },
            ),
          ),
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
      required int save, bool best = false, bool capped = false, required bool ar,
      bool selected = false, VoidCallback? onTap}) {
    // v2.0.92 — selected tier wins over "best" for visual emphasis. Tapping
    // bumps qty so ATC / Buy Now use the right quantity.
    final highlightDark = selected || best;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          padding: EdgeInsets.fromLTRB(4, (best || selected) ? 22 : 10, 4, 10),
          decoration: BoxDecoration(
            color: highlightDark ? UellowColors.darkBrown : Colors.white,
            border: Border.all(
                color: selected ? UellowColors.yellow
                    : (best ? UellowColors.darkBrown : UellowColors.border),
                width: (selected || best) ? 2.5 : 1),
            borderRadius: BorderRadius.circular(12),
            boxShadow: highlightDark ? [BoxShadow(
                color: UellowColors.darkBrown.withValues(alpha: 0.18),
                blurRadius: 10, offset: const Offset(0, 4))] : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,   // v2.1.28 — centered
            children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: highlightDark ? UellowColors.yellow : UellowColors.yellowSoft,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text('$qtyLabel ${ar ? "قطعة" : "pcs"}',
                  style: const TextStyle(fontSize: 9,
                      fontWeight: FontWeight.w900, color: UellowColors.darkBrown)),
            ),
            const SizedBox(height: 8),
            Text(price.toStringAsFixed(3), style: TextStyle(
                fontSize: 14.5, fontWeight: FontWeight.w900,
                color: highlightDark ? UellowColors.yellowLight : UellowColors.darkBrown)),
            Text('$sym ${ar ? "/ قطعة" : "/ pc"}',
                style: TextStyle(fontSize: 10,
                    color: highlightDark
                        ? UellowColors.yellowLight.withValues(alpha: 0.7)
                        : UellowColors.muted)),
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
        // v2.1.16 — chips sit INSIDE the tile's top edge: the old negative
        // offsets put them outside the box where the horizontal list
        // clipped them, so they never showed.
        // SELECTED chip (top-right) — overrides BEST chip when both apply
        if (selected) Positioned(top: 3, right: 3, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
          decoration: BoxDecoration(
            color: UellowColors.yellow,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white, width: 1.2),
            boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 4)],
          ),
          child: const Icon(Icons.check, size: 10, color: UellowColors.darkBrown),
        )),
        // v2.1.29 — smaller RED chip raised above the tile, with clear
        // breathing room from the qty pill below it.
        if (best && !selected) Positioned(top: 0, left: 0, right: 0, child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
          decoration: BoxDecoration(
            color: UellowColors.danger,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white, width: 1),
          ),
          child: Text(ar ? 'الأفضل' : 'BEST',
              style: const TextStyle(fontSize: 7.5,
                  fontWeight: FontWeight.w900, color: Colors.white,
                  letterSpacing: 0.3)),
        ),
      )),
    ]));
  }
}

// ─── Subtotal widget that reflects the active bulk tier ──────────────
//
// Given the product and the currently-selected quantity, returns the
// effective unit price (highest min_qty tier still <= qty) × qty.
// Always falls back to the original price when no tier matches.
class _Subtotal extends StatelessWidget {
  const _Subtotal({required this.product, required this.qty, required this.lang});
  final UellowProductFull product;
  final int qty;
  final String lang;

  double get _effectiveUnitPrice {
    final tiers = product.bulkPricing
        .where((t) => t.minQty <= qty)
        .toList()
      ..sort((a, b) => b.minQty.compareTo(a.minQty));
    if (tiers.isEmpty) return product.price.amount;
    return tiers.first.price;
  }

  @override
  Widget build(BuildContext context) {
    final unit = _effectiveUnitPrice;
    final total = unit * qty;
    final hasDiscount = unit < product.price.amount;
    return Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Text('${total.toStringAsFixed(3)} ${product.price.displaySymbol(lang)}',
          style: const TextStyle(fontSize: 16,
              fontWeight: FontWeight.w900, color: UellowColors.ink)),
      if (hasDiscount)
        Text(
          '${(unit).toStringAsFixed(3)} ${product.price.displaySymbol(lang)} '
          '${lang == "ar" ? "/ قطعة" : "/ pc"}',
          style: const TextStyle(fontSize: 10.5,
              color: UellowColors.success, fontWeight: FontWeight.w700)),
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
    // v2.1.16 — keep the raw HTML so embedded <img> tags render as images
    // (the website-description tab supports pictures).
    final html = product.descriptionHtml.current(lang).isNotEmpty
        ? product.descriptionHtml.current(lang)
        : product.descriptionShort.current(lang);
    final ar = lang == 'ar';
    final plain = _stripHtml(html);
    final hasImages = RegExp(r'<img', caseSensitive: false).hasMatch(html);
    final widgets = plain.isEmpty && !hasImages
        ? <Widget>[Text(ar ? 'لا يوجد وصف لهذا المنتج.'
            : 'No description provided for this product.', style: UT.body)]
        : _htmlToWidgets(html);
    final long = plain.length > 240 || hasImages;
    return Container(
      color: Colors.white, margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(ar ? 'الوصف' : 'Description', style: UT.h3),
        const SizedBox(height: 10),
        Stack(children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: widgets),
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
              builder: (_) => _DescriptionDialog(html: html),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: UellowColors.yellowSoft,
              foregroundColor: UellowColors.darkBrown, elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12))),
            ),
            child: Text(ar ? 'عرض الوصف كامل  ›' : 'See full description  ›',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          )),
        ],
      ]),
    );
  }
}

/// v2.1.16 — minimal HTML renderer for product descriptions: text chunks
/// become Text widgets, <img src> tags become cached images (relative
/// Odoo /web/image paths get the API base URL prefixed).
List<Widget> _htmlToWidgets(String html) {
  final out = <Widget>[];
  final imgRe = RegExp(r'<img[^>]*?src\s*=\s*"([^"]+)"[^>]*>', caseSensitive: false);
  var last = 0;
  void addText(String chunk) {
    final t = _stripHtml(chunk);
    if (t.isNotEmpty) {
      out.add(Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t, style: UT.body),
      ));
    }
  }
  for (final m in imgRe.allMatches(html)) {
    addText(html.substring(last, m.start));
    var src = (m.group(1) ?? '').replaceAll('&amp;', '&');
    if (src.startsWith('/')) src = '${UellowApi.instance.baseUrl}$src';
    if (src.startsWith('http')) {
      out.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: CachedNetworkImage(
            imageUrl: src, fit: BoxFit.contain, width: double.infinity,
            errorWidget: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      ));
    }
    last = m.end;
  }
  addText(html.substring(last));
  return out;
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
  const _DescriptionDialog({required this.html});
  final String html;
  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _SheetHeader(title: UellowApi.instance.lang == 'ar' ? 'الوصف' : 'Description'),
        Flexible(child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 30),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _htmlToWidgets(html)),
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
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(UellowApi.instance.lang == 'ar' ? 'المواصفات' : 'Specifications',
                  style: UT.h3),
              const SizedBox(height: 2),
              Text(UellowApi.instance.lang == 'ar'
                  ? 'الماركة، الخامات، الضمان والمزيد'
                  : 'Brand, materials, warranty & more', style: UT.small),
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
    final ar = lang == 'ar';
    final rows = <(String, String)>[];
    if (p.brand != null) rows.add((ar ? 'الماركة' : 'Brand', p.brand!.name.current(lang)));
    for (final line in p.attributes) {
      final attr = line.attributeName.current(lang);
      final lo = attr.toLowerCase();
      if (lo.contains('brand') || attr.contains('ماركة')
          || attr.contains('علامة') || lo.contains('trademark')) continue;
      if (line.values.isNotEmpty) {
        rows.add((attr, line.values.map((v) => v.name.current(lang)).join(' · ')));
      }
    }
    if (p.sku.isNotEmpty) rows.add((ar ? 'رقم المنتج' : 'SKU', p.sku));
    if (p.barcode.isNotEmpty) rows.add((ar ? 'الباركود' : 'Barcode', p.barcode));
    // v2.1.43 — warranty row only when the product ACTUALLY has one
    // (it used to default to 12 months and show on every product).
    if (p.warrantyMonths > 0) {
      rows.add((ar ? 'الضمان' : 'Warranty',
          ar ? '${p.warrantyMonths} شهر' : '${p.warrantyMonths} months'));
    }
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _SheetHeader(title: ar ? 'المواصفات' : 'Specifications'),
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

// ─── Specialist reviewers block (v2.1.31 — uellow_reviewers) ────────
// Latest expert verdicts for this product + a premium "ask a
// specialist" CTA that opens the online-specialists sheet.

class _ExpertReviewsBlock extends StatefulWidget {
  const _ExpertReviewsBlock({required this.productId});
  final int productId;
  @override
  State<_ExpertReviewsBlock> createState() => _ExpertReviewsBlockState();
}

class _ExpertReviewsBlockState extends State<_ExpertReviewsBlock> {
  List<Map<String, dynamic>> _items = const [];
  int _online = 0;
  bool _loaded = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final r = await http.get(Uri.parse(
          '${UellowApi.instance.baseUrl}/api/mobile/v2/products/'
          '${widget.productId}/expert-reviews'),
          headers: {'Accept': 'application/json'});
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (mounted && j['success'] == true) {
        setState(() {
          _items = ((j['data']?['items'] as List?) ?? const [])
              .cast<Map>().map((m) => m.cast<String, dynamic>()).toList();
          _online = (j['data']?['online_count'] as num?)?.toInt() ?? 0;
          _loaded = true;
        });
      }
    } catch (_) {}
  }

  Color _verdictColor(String v) => v == 'recommend'
      ? UellowColors.successDk
      : v == 'not_recommend' ? UellowColors.danger : const Color(0xFF1565C0);

  // v2.1.35 — denser, smaller, more data: level + specialty + date +
  // quality/value mini-ratings per verdict; the CTA shrank into a small
  // pill in the header.
  @override
  Widget build(BuildContext context) {
    if (!_loaded || (_items.isEmpty && _online == 0)) {
      return const SizedBox.shrink();
    }
    final ar = UellowApi.instance.lang.toLowerCase().startsWith('ar');
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFFF3F7FF), Colors.white],
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('🎓', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 5),
          Text(ar ? 'آراء المتخصصين' : 'Expert opinions',
              style: const TextStyle(fontSize: 13,
                  fontWeight: FontWeight.w900, color: UellowColors.ink)),
          if (_online > 0) ...[
            const SizedBox(width: 8),
            Container(width: 6, height: 6, decoration: const BoxDecoration(
                color: UellowColors.success, shape: BoxShape.circle)),
            const SizedBox(width: 3),
            Text(ar ? '$_online متاح' : '$_online online',
                style: const TextStyle(fontSize: 9.5,
                    color: UellowColors.successDk,
                    fontWeight: FontWeight.w800)),
          ],
          const Spacer(),
          // small CTA pill — the big full-width button is gone.
          Material(
            color: const Color(0xFF1565C0),
            shape: const StadiumBorder(),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () => _openSpecialists(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                child: Text(ar ? 'اطلب رأي متخصص' : 'Ask a specialist',
                    style: const TextStyle(color: Colors.white,
                        fontSize: 9.5, fontWeight: FontWeight.w900)),
              ),
            ),
          ),
        ]),
        for (final it in _items.take(2)) _verdictCard(it, ar),
      ]),
    );
  }

  Widget _verdictCard(Map<String, dynamic> it, bool ar) {
    final rv = (it['reviewer'] as Map?)?.cast<String, dynamic>() ?? const {};
    final verdict = (it['verdict'] ?? '').toString();
    final q = (it['quality'] as num?)?.toInt() ?? 0;
    final v = (it['value'] as num?)?.toInt() ?? 0;
    return Container(
      margin: const EdgeInsets.only(top: 7),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE3EAF6)),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Stack(children: [
          CircleAvatar(
            radius: 14, backgroundColor: const Color(0xFFE3EAF6),
            backgroundImage: rv['avatar'] != null
                ? CachedNetworkImageProvider(rv['avatar'].toString()) : null,
            child: rv['avatar'] == null
                ? const Icon(Icons.person, size: 14,
                    color: Color(0xFF1565C0)) : null,
          ),
          if (rv['online'] == true) Positioned(right: 0, bottom: 0,
            child: Container(width: 9, height: 9, decoration: BoxDecoration(
              color: UellowColors.success, shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5),
            ))),
        ]),
        const SizedBox(width: 8),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Flexible(child: Text((rv['name'] ?? '').toString(),
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.5,
                    fontWeight: FontWeight.w800, color: UellowColors.ink))),
            if (rv['verified'] == true) const Padding(
              padding: EdgeInsetsDirectional.only(start: 3),
              child: Icon(Icons.verified, size: 12, color: Color(0xFF1565C0)),
            ),
            if ((rv['level'] ?? '').toString().isNotEmpty) Container(
              margin: const EdgeInsetsDirectional.only(start: 5),
              padding: const EdgeInsets.symmetric(
                  horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF4FF),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text((rv['level'] ?? '').toString(),
                  style: const TextStyle(fontSize: 8,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1565C0))),
            ),
            const Spacer(),
            Text((it['date'] ?? '').toString(),
                style: const TextStyle(fontSize: 8.5,
                    color: UellowColors.muted)),
          ]),
          if ((rv['specialty'] ?? '').toString().isNotEmpty)
            Text((rv['specialty'] ?? '').toString(),
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 9,
                    color: UellowColors.muted)),
          const SizedBox(height: 3),
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(
                color: _verdictColor(verdict).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                ((it['verdict_label'] as Map?)?[ar ? 'ar' : 'en'] ?? '')
                    .toString(),
                style: TextStyle(fontSize: 8.5,
                    fontWeight: FontWeight.w900,
                    color: _verdictColor(verdict)),
              ),
            ),
            if (q > 0) ...[
              const SizedBox(width: 7),
              Text(ar ? 'الجودة $q/5' : 'Quality $q/5',
                  style: const TextStyle(fontSize: 8.5,
                      fontWeight: FontWeight.w700,
                      color: UellowColors.muted)),
            ],
            if (v > 0) ...[
              const SizedBox(width: 7),
              Text(ar ? 'القيمة $v/5' : 'Value $v/5',
                  style: const TextStyle(fontSize: 8.5,
                      fontWeight: FontWeight.w700,
                      color: UellowColors.muted)),
            ],
          ]),
          if ((it['notes'] ?? '').toString().isNotEmpty) Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text((it['notes'] ?? '').toString(),
                maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10.5,
                    color: UellowColors.text, height: 1.35)),
          ),
        ])),
      ]),
    );
  }

  // v2.1.35 — richer specialists sheet: service explainer, online-only
  // filter, full profile facts (level, rating + count, both prices) and
  // a request composer with session type + optional question.
  void _openSpecialists(BuildContext context) async {
    final ar = UellowApi.instance.lang.toLowerCase().startsWith('ar');
    List<Map<String, dynamic>> revs = const [];
    try {
      final r = await http.get(Uri.parse(
          '${UellowApi.instance.baseUrl}/api/mobile/v2/reviewers/online'),
          headers: {'Accept': 'application/json'});
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (j['success'] == true) {
        revs = ((j['data'] as List?) ?? const [])
            .cast<Map>().map((m) => m.cast<String, dynamic>()).toList();
      }
    } catch (_) {}
    if (!context.mounted) return;
    var onlineOnly = false;
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        final shown = onlineOnly
            ? revs.where((r) => r['online'] == true).toList()
            : revs;
        return SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.78,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
              child: Row(children: [
                Text(ar ? '🎓 المتخصصون' : '🎓 Specialists', style: UT.h2),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(ctx)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
              child: Text(ar
                  ? 'استشر خبيراً حقيقياً قبل الشراء — يفحص المنتج ويرد عليك برأي موثوق.'
                  : 'Consult a real expert before you buy — they review the product and reply with a trusted opinion.',
                  style: const TextStyle(fontSize: 11.5,
                      color: UellowColors.muted, height: 1.4)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 4),
              child: Row(children: [
                _filterChip(ar ? 'الكل' : 'All', !onlineOnly,
                    () => setSheet(() => onlineOnly = false)),
                const SizedBox(width: 6),
                _filterChip(ar ? '🟢 متاح الآن' : '🟢 Online now',
                    onlineOnly,
                    () => setSheet(() => onlineOnly = true)),
              ]),
            ),
            Expanded(child: shown.isEmpty
                ? Center(child: Text(
                    ar ? 'لا يوجد متخصصون متاحون حالياً'
                       : 'No specialists available right now',
                    style: UT.body))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                    itemCount: shown.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _specialistTile(ctx, shown[i], ar),
                  )),
          ]),
        );
      }),
    );
  }

  Widget _filterChip(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF1565C0) : Colors.white,
          border: Border.all(color: active
              ? const Color(0xFF1565C0) : UellowColors.border),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label, style: TextStyle(fontSize: 10.5,
            fontWeight: FontWeight.w800,
            color: active ? Colors.white : UellowColors.text)),
      ),
    );
  }

  Widget _specialistTile(BuildContext ctx, Map<String, dynamic> rv, bool ar) {
    final count = (rv['review_count'] as num?)?.toInt() ?? 0;
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        border: Border.all(color: UellowColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Stack(children: [
          CircleAvatar(
            radius: 21, backgroundColor: const Color(0xFFE3EAF6),
            backgroundImage: rv['avatar'] != null
                ? CachedNetworkImageProvider(rv['avatar'].toString()) : null,
            child: rv['avatar'] == null
                ? const Icon(Icons.person, color: Color(0xFF1565C0)) : null,
          ),
          if (rv['online'] == true) Positioned(right: 0, bottom: 0,
            child: Container(width: 12, height: 12, decoration: BoxDecoration(
              color: UellowColors.success, shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ))),
        ]),
        const SizedBox(width: 10),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Flexible(child: Text((rv['name'] ?? '').toString(),
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800,
                    fontSize: 12.5))),
            if (rv['verified'] == true) const Padding(
              padding: EdgeInsetsDirectional.only(start: 3),
              child: Icon(Icons.verified, size: 13, color: Color(0xFF1565C0)),
            ),
            if ((rv['level'] ?? '').toString().isNotEmpty) Container(
              margin: const EdgeInsetsDirectional.only(start: 5),
              padding: const EdgeInsets.symmetric(
                  horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF4FF),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text((rv['level'] ?? '').toString(),
                  style: const TextStyle(fontSize: 8.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1565C0))),
            ),
          ]),
          Text((rv['specialty'] ?? '').toString(),
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10,
                  color: UellowColors.muted)),
          const SizedBox(height: 2),
          Row(children: [
            const Icon(Icons.star_rounded, size: 11, color: Color(0xFFFFB400)),
            Text(' ${(rv['rating'] ?? 0)}', style: const TextStyle(
                fontSize: 10, fontWeight: FontWeight.w800)),
            if (count > 0)
              Text(ar ? ' ($count رأي)' : ' ($count reviews)',
                  style: const TextStyle(fontSize: 9,
                      color: UellowColors.muted)),
          ]),
          const SizedBox(height: 2),
          // v2.1.39 — prices removed from the specialists UI per request;
          // only the session TYPES are shown.
          Wrap(spacing: 6, children: [
            if (rv['allow_written'] != false)
              Text(ar ? '📝 رأي كتابي' : '📝 Written opinion',
                  style: const TextStyle(fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: UellowColors.text)),
            if (rv['allow_chat'] == true)
              Text(ar ? '💬 محادثة مباشرة' : '💬 Live chat',
                  style: const TextStyle(fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: UellowColors.text)),
          ]),
        ])),
        ElevatedButton(
          onPressed: () => _openComposer(ctx, rv),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1565C0),
            foregroundColor: Colors.white, elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(9))),
          ),
          child: Text(ar ? 'اطلب' : 'Ask', style: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w900)),
        ),
      ]),
    );
  }

  // Request composer: pick the session type, optionally write your
  // question, then send. Guests get the sign-in sheet first.
  void _openComposer(BuildContext ctx, Map<String, dynamic> rv) async {
    final ar = UellowApi.instance.lang.toLowerCase().startsWith('ar');
    final token = await UellowApi.instance.tokenStore.readToken();
    if (token == null || token.isEmpty) {
      if (ctx.mounted) {
        Navigator.pop(ctx);
        await showAuthSheet(context);
      }
      return;
    }
    if (!ctx.mounted) return;
    var session = rv['allow_written'] != false ? 'written' : 'chat';
    final noteCtrl = TextEditingController();
    var sending = false;
    showModalBottomSheet(
      context: ctx, isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (c2) => StatefulBuilder(builder: (c2, setS) => Padding(
        padding: EdgeInsets.fromLTRB(18, 16, 18,
            18 + MediaQuery.of(c2).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              radius: 16, backgroundColor: const Color(0xFFE3EAF6),
              backgroundImage: rv['avatar'] != null
                  ? CachedNetworkImageProvider(rv['avatar'].toString())
                  : null,
              child: rv['avatar'] == null
                  ? const Icon(Icons.person, size: 16,
                      color: Color(0xFF1565C0)) : null,
            ),
            const SizedBox(width: 8),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text((rv['name'] ?? '').toString(),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13,
                      fontWeight: FontWeight.w900)),
              Text((rv['specialty'] ?? '').toString(),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10,
                      color: UellowColors.muted)),
            ])),
            IconButton(icon: const Icon(Icons.close, size: 18),
                onPressed: () => Navigator.pop(c2)),
          ]),
          const SizedBox(height: 10),
          Text(ar ? 'نوع الجلسة' : 'Session type',
              style: const TextStyle(fontSize: 11,
                  fontWeight: FontWeight.w800, color: UellowColors.text)),
          const SizedBox(height: 6),
          Row(children: [
            if (rv['allow_written'] != false) Expanded(
              child: _sessionOption(c2, ar,
                  active: session == 'written',
                  emoji: '📝',
                  label: ar ? 'رأي كتابي' : 'Written opinion',
                  onTap: () => setS(() => session = 'written')),
            ),
            if (rv['allow_written'] != false && rv['allow_chat'] == true)
              const SizedBox(width: 8),
            if (rv['allow_chat'] == true) Expanded(
              child: _sessionOption(c2, ar,
                  active: session == 'chat',
                  emoji: '💬',
                  label: ar ? 'محادثة مباشرة' : 'Live chat',
                  onTap: () => setS(() => session = 'chat')),
            ),
          ]),
          const SizedBox(height: 12),
          Text(ar ? 'سؤالك (اختياري)' : 'Your question (optional)',
              style: const TextStyle(fontSize: 11,
                  fontWeight: FontWeight.w800, color: UellowColors.text)),
          const SizedBox(height: 6),
          TextField(
            controller: noteCtrl,
            maxLines: 3, maxLength: 500,
            style: const TextStyle(fontSize: 12.5),
            decoration: InputDecoration(
              counterText: '',
              hintText: ar
                  ? 'مثال: هل يناسب الاستخدام اليومي؟ وما رأيك بالخامة؟'
                  : 'e.g. Is it good for daily use? What about the material?',
              hintStyle: const TextStyle(fontSize: 11.5,
                  color: UellowColors.muted),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: UellowColors.border)),
              contentPadding: const EdgeInsets.all(10),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: sending ? null : () async {
              setS(() => sending = true);
              final ok2 = await _send(rv, session, noteCtrl.text.trim());
              if (c2.mounted) Navigator.pop(c2);
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(ok2
                        ? (ar ? '✅ تم إرسال طلبك — سيرد عليك المتخصص قريباً'
                              : '✅ Request sent — the specialist will reply soon')
                        : (ar ? 'تعذر إرسال الطلب' : 'Could not send the request'))));
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1565C0),
              foregroundColor: Colors.white, elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12))),
            ),
            child: Text(
                sending
                    ? (ar ? 'جارٍ الإرسال…' : 'Sending…')
                    : (ar ? 'إرسال الطلب' : 'Send request'),
                style: const TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w900)),
          )),
        ]),
      )),
    );
  }

  Widget _sessionOption(BuildContext c, bool ar,
      {required bool active, required String emoji, required String label,
       required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFEFF4FF) : Colors.white,
          border: Border.all(
              color: active ? const Color(0xFF1565C0) : UellowColors.border,
              width: active ? 1.5 : 1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(emoji, style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 4),
            Flexible(child: Text(label,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: active
                        ? const Color(0xFF1565C0) : UellowColors.ink))),
          ]),
        ]),
      ),
    );
  }

  Future<bool> _send(Map<String, dynamic> rv, String session,
      String note) async {
    try {
      final token = await UellowApi.instance.tokenStore.readToken();
      final r = await http.post(Uri.parse(
          '${UellowApi.instance.baseUrl}/api/mobile/v2/reviewers/request'),
          headers: {'Content-Type': 'application/json',
                    'Authorization': 'Bearer $token'},
          body: jsonEncode({'reviewer_id': rv['id'],
                            'product_id': widget.productId,
                            'session_type': session,
                            if (note.isNotEmpty) 'note': note}));
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      return j['success'] == true;
    } catch (_) {
      return false;
    }
  }
}

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
      // v2.1.38 — send the token when signed in: the backend then also
      // returns the user's OWN pending review (marked "under review").
      final token = await UellowApi.instance.tokenStore.readToken();
      final r = await http.get(
        Uri.parse('${UellowApi.instance.baseUrl}/api/mobile/v2/products/${widget.productId}/reviews'),
        headers: {
          'Accept': 'application/json',
          if (token != null && token.isNotEmpty)
            'Authorization': 'Bearer $token',
        },
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
          // v2.0.78 — solid yellow pill, smaller, with a leading star icon.
          // Reads as a clear branded CTA instead of a thin outlined button.
          Material(
            color: UellowColors.yellow,
            shape: const StadiumBorder(),
            elevation: 0,
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () => _openWriteReview(context),
              child: Padding(
                // v2.1.16 — slimmer pill + smaller font per request.
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.star_rounded, size: 12, color: UellowColors.darkBrown),
                  const SizedBox(width: 3),
                  // v2.1.35 — never fade the label mid-word ("اكتب…").
                  Text(T.t('product.write_review'),
                      maxLines: 1, softWrap: false,
                      overflow: TextOverflow.visible,
                      style: const TextStyle(fontSize: 9.5,
                          fontWeight: FontWeight.w800, color: UellowColors.darkBrown,
                          letterSpacing: -0.1)),
                ]),
              ),
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
            // v2.0.79 — Reviews block redesign.
            // Layout: big avg + stars on the LEFT, 5-bar rating breakdown
            // on the RIGHT, then either the review cards OR a warm empty
            // state that invites the user to be the first reviewer.
            final breakdown = (summary['breakdown'] as Map?)?.cast<String, dynamic>() ?? {};
            final ar = UellowApi.instance.lang.toLowerCase().startsWith('ar');
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Header strip
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: UellowColors.yellowSoft.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: UellowColors.yellow.withValues(alpha: 0.3)),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  // Left — average score
                  Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
                    Text(avg.toStringAsFixed(1), style: const TextStyle(
                        fontSize: 36, fontWeight: FontWeight.w900,
                        color: UellowColors.darkBrown, height: 1, letterSpacing: -1)),
                    const SizedBox(height: 4),
                    Row(children: [for (var i = 0; i < 5; i++) Icon(
                      i < avg.round() ? Icons.star_rounded : Icons.star_outline_rounded,
                      size: 14, color: UellowColors.yellow)]),
                    const SizedBox(height: 3),
                    Text(ar ? '$total ${total == 1 ? "تقييم" : "تقييمات"}'
                            : 'Based on $total ${total == 1 ? "review" : "reviews"}',
                        style: const TextStyle(color: UellowColors.muted,
                            fontSize: 10.5, fontWeight: FontWeight.w700)),
                  ]),
                  Container(width: 1, height: 70,
                      margin: const EdgeInsets.symmetric(horizontal: 14),
                      color: UellowColors.yellow.withValues(alpha: 0.25)),
                  // Right — rating breakdown (5★, 4★, …)
                  Expanded(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    for (final s in const [5, 4, 3, 2, 1])
                      Padding(padding: const EdgeInsets.symmetric(vertical: 1.5),
                        child: _RatingBar(
                          star: s,
                          count: (breakdown['$s'] as num?)?.toInt() ?? 0,
                          total: total == 0 ? 1 : total,
                        )),
                  ])),
                ]),
              ),
              const SizedBox(height: 14),
              if (reviews.isEmpty)
                // Warm empty state — invite the first review
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAFAFA),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: UellowColors.border),
                  ),
                  child: Row(children: [
                    Container(
                      width: 44, height: 44,
                      decoration: const BoxDecoration(
                        color: UellowColors.yellowSoft, shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: const Icon(Icons.rate_review_outlined,
                          color: UellowColors.darkBrown, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(ar ? 'كن أول من يقيّم' : 'Be the first to review',
                          style: const TextStyle(fontWeight: FontWeight.w900,
                              fontSize: 13, color: UellowColors.ink)),
                      const SizedBox(height: 2),
                      Text(ar
                          ? 'شارك تجربتك مع المنتج لتساعد المشترين الآخرين'
                          : 'Share your experience to help other shoppers',
                          style: const TextStyle(fontSize: 11.5,
                              color: UellowColors.muted, height: 1.35)),
                    ])),
                  ]),
                )
              else ...[
                // v2.1.38 — ONE full review; the second peeks through a
                // white fade as a teaser; "المزيد" opens the full dialog
                // (all reviews + photos).
                _reviewCard(reviews.first as Map<String, dynamic>),
                if (reviews.length > 1)
                  Stack(children: [
                    SizedBox(
                      height: 64,
                      child: ClipRect(child: OverflowBox(
                        alignment: Alignment.topCenter,
                        maxHeight: 200,
                        child: _reviewCard(
                            reviews[1] as Map<String, dynamic>),
                      )),
                    ),
                    Positioned.fill(child: IgnorePointer(child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withValues(alpha: 0.25),
                            Colors.white.withValues(alpha: 0.95),
                          ],
                        ),
                      ),
                    ))),
                  ]),
                if (reviews.length > 1 || total > 1) Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: SizedBox(width: double.infinity, child: ElevatedButton.icon(
                    onPressed: () => _openAllReviews(
                        context, reviews, avg, total),
                    icon: const Icon(Icons.reviews_outlined, size: 15),
                    label: Text(ar ? 'المزيد ($total)' : 'More ($total)',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: UellowColors.yellowSoft,
                      foregroundColor: UellowColors.darkBrown, elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                    ),
                  )),
                ),
              ],
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
    final pending = r['pending'] == true;
    final photos = ((r['photos'] as List?) ?? const [])
        .map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    final ar = UellowApi.instance.lang == 'ar';
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
              Flexible(child: Text(author,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
              if (verified) Padding(
                padding: const EdgeInsetsDirectional.only(start: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: UellowColors.success,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(ar ? 'موثّق' : 'VERIFIED',
                      style: const TextStyle(
                      color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
                ),
              ),
              // v2.1.38 — author sees their not-yet-approved review.
              if (pending) Padding(
                padding: const EdgeInsetsDirectional.only(start: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3CD),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(ar ? '⏳ قيد المراجعة' : '⏳ Under review',
                      style: const TextStyle(color: Color(0xFF8A6D00),
                          fontSize: 9, fontWeight: FontWeight.w800)),
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
        // v2.1.38 — review photos: 56px thumbs, tap → full-screen viewer.
        if (photos.isNotEmpty) Padding(
          padding: const EdgeInsets.only(top: 8),
          child: SizedBox(height: 56, child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: photos.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (ctx, i) => GestureDetector(
              onTap: () => _openPhoto(ctx, photos, i),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: photos[i], width: 56, height: 56,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                      width: 56, height: 56, color: UellowColors.border),
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
          )),
        ),
      ]),
    );
  }

  void _openPhoto(BuildContext context, List<String> photos, int index) {
    showDialog(context: context, builder: (_) => Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(children: [
        PageView.builder(
          controller: PageController(initialPage: index),
          itemCount: photos.length,
          itemBuilder: (_, i) => InteractiveViewer(
            child: Center(child: CachedNetworkImage(imageUrl: photos[i])),
          ),
        ),
        PositionedDirectional(top: 30, end: 12, child: IconButton(
          icon: const Icon(Icons.close, color: Colors.white, size: 26),
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
        )),
      ]),
    ));
  }

  // v2.1.38 — full reviews dialog: avg header + every review with photos.
  void _openAllReviews(BuildContext context,
      List reviews, double avg, int total) {
    final ar = UellowApi.instance.lang == 'ar';
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.85,
        child: Column(children: [
          const SizedBox(height: 10),
          Container(width: 36, height: 4,
              decoration: BoxDecoration(color: UellowColors.border,
                  borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
            child: Row(children: [
              Text(ar ? 'التقييمات' : 'Reviews', style: UT.h2),
              const SizedBox(width: 8),
              const Icon(Icons.star_rounded,
                  size: 16, color: UellowColors.yellow),
              Text(' ${avg.toStringAsFixed(1)}',
                  style: const TextStyle(fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: UellowColors.ink)),
              Text(ar ? '  ·  $total تقييم' : '  ·  $total reviews',
                  style: const TextStyle(fontSize: 12,
                      color: UellowColors.muted,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              IconButton(icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(ctx)),
            ]),
          ),
          Expanded(child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
            itemCount: reviews.length,
            itemBuilder: (_, i) =>
                _reviewCard(reviews[i] as Map<String, dynamic>),
          )),
        ]),
      ),
    );
  }
}

// v2.0.79 — single row in the rating-breakdown chart: ⭐n on the left,
// a filled progress bar in the middle, and the absolute count on the
// right. Width-fraction is count/total.
class _RatingBar extends StatelessWidget {
  const _RatingBar({required this.star, required this.count, required this.total});
  final int star;
  final int count;
  final int total;
  @override
  Widget build(BuildContext context) {
    final frac = total <= 0 ? 0.0 : (count / total).clamp(0.0, 1.0);
    return Row(children: [
      Text('$star', style: const TextStyle(
          fontSize: 10.5, fontWeight: FontWeight.w900,
          color: UellowColors.darkBrown)),
      const SizedBox(width: 2),
      const Icon(Icons.star_rounded, size: 10, color: UellowColors.yellow),
      const SizedBox(width: 6),
      Expanded(child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          height: 6,
          child: Stack(children: [
            Container(color: Colors.white),
            FractionallySizedBox(
              widthFactor: frac,
              child: Container(color: UellowColors.yellow),
            ),
          ]),
        ),
      )),
      const SizedBox(width: 6),
      SizedBox(width: 18, child: Text('$count',
          textAlign: TextAlign.right,
          style: const TextStyle(fontSize: 10,
              color: UellowColors.muted, fontWeight: FontWeight.w800))),
    ]);
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
  // v2.1.29 — infinite-load the first 3 rounds, then show a Load-more
  // button (per design) while the backend reports hasNext.
  static const int _kAutoLimit = 3;
  @override
  void initState() { super.initState(); _loadMore(); }
  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      // Same-category only — that's what makes them "related". If the
      // product has no public category, fall back to the global list.
      // v2.0.79 — larger pages (10 → 16) so the auto-load doesn't fire as
      // aggressively while still feeling infinite.
      final page = await UellowApi.instance.products.list(
          categoryId: widget.categoryId,
          page: _page, perPage: 16);
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
              childAspectRatio: 0.585,
            ),
            itemCount: _items.length,
            // v2.1.33 — rich card everywhere products grid.
            itemBuilder: (_, i) => ProductCard(rich: true, surface: 'related', product: _items[i]),
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
            child: Row(children: [
              const Icon(Icons.notifications_active_outlined, size: 18,
                  color: UellowColors.yellowLight),
              const SizedBox(width: 10),
              Text(UellowApi.instance.lang == 'ar'
                  ? 'أبلغني عند توفّره' : 'Notify me when back in stock',
                  style: const TextStyle(
                  color: UellowColors.yellowLight, fontSize: 14,
                  fontWeight: FontWeight.w900, letterSpacing: 0.2)),
              const Spacer(),
              const Icon(Icons.arrow_forward, size: 16,
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
                  _qtyBtn('+', () => _qty < p.maxQtyBuyable
                      ? setState(() => _qty++) : null),
                ]),
              ),
              const SizedBox(width: 6),
              Text(ar ? '/ ${p.maxQtyBuyable} كحد أقصى'
                     : '/ ${p.maxQtyBuyable} max',
                  style: const TextStyle(fontSize: 10.5,
                      color: UellowColors.muted, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(ar ? 'الإجمالي' : 'Subtotal',
                  style: const TextStyle(fontSize: 11, color: UellowColors.muted,
                      fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              // Subtotal reflects the active bulk-pricing tier if the
              // selected qty crosses any tier threshold.
              _Subtotal(product: p, qty: _qty, lang: lang),
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
  // v2.0.78 — enableDrag: true so the user can swipe the sheet down to
  // close (the default is true but make it explicit). isDismissible too.
  showModalBottomSheet(
    context: context, backgroundColor: Colors.transparent,
    isScrollControlled: true,
    enableDrag: true,
    isDismissible: true,
    showDragHandle: true,
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
      // v2.1.35 — reviews now need admin approval before going live.
      messenger.showSnackBar(SnackBar(
          duration: const Duration(seconds: 4),
          content: Text(ar
              ? '✅ شكراً! تقييمك قيد المراجعة وسيظهر فور اعتماده'
              : '✅ Thanks! Your review is pending approval and will appear once approved')));
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

// ─── Sticky section tabs (v2.1.56) ───────────────────────────────────
// AliExpress-style: نظرة عامة / التفاصيل / التقييمات / مقترحات. Pinned
// under the status bar once the gallery scrolls away; taps jump to the
// section anchors.
class _SectionTabs extends SliverPersistentHeaderDelegate {
  _SectionTabs({required this.tab, required this.onTap});
  final int tab;
  final ValueChanged<int> onTap;

  static List<String> get _labels => UellowApi.instance.lang == 'ar'
      ? const ['نظرة عامة', 'التفاصيل', 'التقييمات', 'مقترحات']
      : const ['Overview', 'Details', 'Reviews', 'For you'];

  @override
  Widget build(BuildContext c, double shrink, bool overlaps) {
    final ar = UellowApi.instance.lang == 'ar';
    return Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: Container(
        color: Colors.white,
        decoration: BoxDecoration(
          color: Colors.white,
          border: const Border(bottom: BorderSide(color: UellowColors.border)),
          boxShadow: overlaps
              ? const [BoxShadow(color: Color(0x14000000),
                  blurRadius: 6, offset: Offset(0, 2))]
              : null,
        ),
        child: Row(children: [
          for (var i = 0; i < _labels.length; i++) Expanded(
            child: InkWell(
              onTap: () => onTap(i),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(
                    color: i == tab
                        ? UellowColors.yellow : Colors.transparent,
                    width: 2.5,
                  )),
                ),
                child: Text(_labels[i], style: TextStyle(
                  fontSize: 12,
                  fontWeight: i == tab ? FontWeight.w900 : FontWeight.w600,
                  color: i == tab
                      ? UellowColors.darkBrown : UellowColors.muted,
                )),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  @override double get maxExtent => 42;
  @override double get minExtent => 42;
  @override bool shouldRebuild(_SectionTabs old) => old.tab != tab;
}
