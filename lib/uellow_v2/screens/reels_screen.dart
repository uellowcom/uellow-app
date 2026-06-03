// =============================================================================
// ReelsScreen — TikTok-style vertical feed of products that have a video.
// v2.0.83 — first pass.
//
// Layout per slide:
//   • Full-bleed background = video (when direct upload) OR thumbnail with
//     a centered play badge (when only an embed/TikTok URL is available —
//     tap opens the embed in a webview).
//   • Bottom-left overlay: brand · product name (2 lines) · price + discount.
//   • Right rail (vertical): ❤️ Wishlist · 💬 Reviews · 🛒 Add to cart ·
//     📤 Share.
//   • Pre-fetches the next page when the user is 2 items from the end.
//
// Pagination: cursor-based via `cursor` query param (last seen product id).
// =============================================================================
import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../api/uellow_api.dart';
import '../router/uellow_router.dart';
import '../theme/uellow_theme.dart';
import '../widgets/uellow_bottom_nav.dart';

class ReelsScreen extends StatefulWidget {
  const ReelsScreen({super.key});
  @override
  State<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends State<ReelsScreen> {
  final _pageCtrl = PageController();
  final List<Map<String, dynamic>> _items = [];
  bool _loading = false;
  bool _hasMore = true;
  int _cursor = 0;
  int _activeIdx = 0;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final url = Uri.parse(
        '${UellowApi.instance.baseUrl}/api/mobile/v2/videos/feed'
        '?limit=10${_cursor > 0 ? "&cursor=$_cursor" : ""}',
      );
      final r = await http.get(url, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 12));
      final body = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (body['success'] == true) {
        final data = body['data'] as Map<String, dynamic>;
        final newItems = (data['items'] as List? ?? const [])
            .cast<Map<String, dynamic>>();
        if (mounted) {
          setState(() {
            _items.addAll(newItems);
            _cursor = (data['cursor'] as int?) ?? _cursor;
            _hasMore = (data['has_more'] as bool?) ?? false;
          });
        }
      }
    } catch (_) {/* swallow — show empty / loading state */}
    if (mounted) setState(() => _loading = false);
  }

  void _onPageChanged(int i) {
    setState(() => _activeIdx = i);
    // Pre-fetch when nearing the tail
    if (i >= _items.length - 3) _fetch();
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang.toLowerCase().startsWith('ar');
    return Scaffold(
      backgroundColor: Colors.black,
      // v2.0.91 — Reels screen gets the standard bottom nav so users
      // can jump to Home / Shop / Beena / Cart / Account without going
      // back. Active tab = reels.
      bottomNavigationBar: const UellowBottomNav(active: UNavTab.reels),
      body: SafeArea(child: Stack(children: [
        if (_items.isEmpty && _loading)
          const Center(child: CircularProgressIndicator(color: Colors.white))
        else if (_items.isEmpty)
          Center(child: Padding(padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.videocam_off_outlined, color: Colors.white54, size: 56),
              const SizedBox(height: 12),
              Text(ar ? 'لا توجد فيديوهات بعد — تابعنا لاحقاً'
                     : 'No videos yet — check back later',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 14)),
            ]),
          ))
        else PageView.builder(
          controller: _pageCtrl,
          scrollDirection: Axis.vertical,
          itemCount: _items.length,
          onPageChanged: _onPageChanged,
          itemBuilder: (_, i) => _ReelSlide(
            item: _items[i], active: i == _activeIdx, ar: ar),
        ),
        // Top header — centered title only. The close (X) button was removed:
        // on a nav tab there is nothing to pop, so it did nothing.
        Positioned(top: 10, left: 16, right: 16, child: Center(
          child: Text(ar ? 'فيديوهات' : 'Reels',
              style: const TextStyle(color: Colors.white,
                  fontSize: 16, fontWeight: FontWeight.w900,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 4)])),
        )),
      ])),
    );
  }
}

class _ReelSlide extends StatefulWidget {
  const _ReelSlide({required this.item, required this.active, required this.ar});
  final Map<String, dynamic> item;
  final bool active;
  final bool ar;
  @override
  State<_ReelSlide> createState() => _ReelSlideState();
}

class _ReelSlideState extends State<_ReelSlide> {
  VideoPlayerController? _ctrl;
  bool _muted = true;
  bool _initFailed = false;

  Map<String, dynamic> get _video =>
      (widget.item['video'] as Map).cast<String, dynamic>();
  Map<String, dynamic> get _product =>
      (widget.item['product'] as Map).cast<String, dynamic>();

  String? get _fileUrl {
    final f = _video['file_url']?.toString();
    if (f == null || f.isEmpty) return null;
    return f.startsWith('http') ? f : '${UellowApi.instance.baseUrl}$f';
  }

  @override
  void initState() {
    super.initState();
    _maybeInitVideo();
  }

  @override
  void didUpdateWidget(_ReelSlide old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _maybeInitVideo();
    if (!widget.active && old.active) _ctrl?.pause();
    if (widget.active && _ctrl != null && _ctrl!.value.isInitialized) {
      _ctrl!.play();
    }
  }

  Future<void> _maybeInitVideo() async {
    final url = _fileUrl;
    if (url == null) return;     // embed/tiktok-only — no inline player
    if (_ctrl != null) return;
    try {
      // v2.0.99 — Bunny Stream serves HLS (.m3u8). Without an explicit
      // formatHint, ExoPlayer falls back to extension-sniffing, which
      // silently fails when the CDN URL carries query params or redirects.
      // Detect HLS from the mime or the .m3u8 path and hint it explicitly.
      final mime = _video['mime']?.toString().toLowerCase() ?? '';
      final isHls = mime.contains('mpegurl') || mime.contains('hls')
          || Uri.parse(url).path.toLowerCase().endsWith('.m3u8');
      _ctrl = VideoPlayerController.networkUrl(Uri.parse(url),
          formatHint: isHls ? VideoFormat.hls : null);
      await _ctrl!.initialize();
      _ctrl!
        ..setLooping(true)
        ..setVolume(0)
        ..play();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => _initFailed = true);
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ar = widget.ar;
    final lang = UellowApi.instance.lang;
    final p = _product;
    final name = ((p['name'] as Map?)?[ar ? 'ar' : 'en'] as String?) ?? '';
    final brand = ((p['vendor'] as Map?)?['name'] as String?)
        ?? ((p['brand'] as Map?)?[ar ? 'ar' : 'en'] as String?);
    final price = (p['price'] as Map?)?.cast<String, dynamic>();
    final priceAmt = (price?['amount'] as num?)?.toDouble() ?? 0;
    final priceSym = (price?['symbol'] as String?) ?? '';
    final cmp = (p['compare_price'] as Map?)?.cast<String, dynamic>();
    final cmpAmt = (cmp?['amount'] as num?)?.toDouble();
    final disc = (p['discount_pct'] as num?)?.toInt() ?? 0;
    final thumb = _video['thumbnail']?.toString();
    final productId = (p['id'] as num?)?.toInt() ?? 0;
    return Stack(children: [
      // ── Background — video or thumbnail
      Positioned.fill(child: _initFailed || _ctrl == null || !_ctrl!.value.isInitialized
        ? _buildThumbnail(thumb)
        : FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _ctrl!.value.size.width,
              height: _ctrl!.value.size.height,
              child: VideoPlayer(_ctrl!),
            ),
          )),
      // Tap toggles play/pause / mute
      Positioned.fill(child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          if (_ctrl == null || !_ctrl!.value.isInitialized) {
            _openEmbedOrProduct();
            return;
          }
          setState(() {
            _muted = !_muted;
            _ctrl!.setVolume(_muted ? 0 : 1);
          });
        },
      )),
      // Tappable sound button — videos autoplay MUTED; tap to turn sound on.
      if (_ctrl != null && _ctrl!.value.isInitialized) Positioned(
        top: 44, right: 14,
        child: GestureDetector(
          onTap: () => setState(() {
            _muted = !_muted;
            _ctrl!.setVolume(_muted ? 0 : 1);
          }),
          child: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.55), width: 1),
            ),
            child: Icon(_muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                color: Colors.white, size: 21),
          ),
        ),
      ),
      // ── Bottom-left product details overlay
      Positioned(left: 16, right: 92, bottom: 28, child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (brand != null && brand.isNotEmpty)
            Text(brand,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 11, fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    shadows: const [Shadow(color: Colors.black87, blurRadius: 4)])),
          const SizedBox(height: 4),
          Text(name, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white,
                  fontSize: 14.5, fontWeight: FontWeight.w800,
                  height: 1.25,
                  shadows: [Shadow(color: Colors.black87, blurRadius: 6)])),
          const SizedBox(height: 8),
          Row(children: [
            Text('${priceAmt.toStringAsFixed(3)} $priceSym',
                style: const TextStyle(color: Colors.white,
                    fontSize: 16, fontWeight: FontWeight.w900,
                    shadows: [Shadow(color: Colors.black87, blurRadius: 4)])),
            if (cmpAmt != null && cmpAmt > priceAmt) ...[
              const SizedBox(width: 6),
              Text(cmpAmt.toStringAsFixed(3),
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.65),
                      fontSize: 11,
                      decoration: TextDecoration.lineThrough,
                      decorationColor: Colors.white.withValues(alpha: 0.65),
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(color: UellowColors.danger,
                    borderRadius: BorderRadius.circular(4)),
                child: Text('-$disc%',
                    style: const TextStyle(color: Colors.white, fontSize: 9.5,
                        fontWeight: FontWeight.w900)),
              ),
            ],
          ]),
          const SizedBox(height: 8),
          // CTA → product page
          GestureDetector(
            onTap: () => UellowRouter.goProduct(context, productId),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: UellowColors.yellow,
                borderRadius: BorderRadius.circular(999),
                boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 8)],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.shopping_bag_outlined, size: 14,
                    color: UellowColors.darkBrown),
                const SizedBox(width: 5),
                Text(ar ? 'عرض المنتج' : 'View product',
                    style: const TextStyle(color: UellowColors.darkBrown,
                        fontSize: 11.5, fontWeight: FontWeight.w900)),
              ]),
            ),
          ),
        ],
      )),
      // ── Right rail — like / comments / cart / share
      Positioned(right: 14, bottom: 100, child: Column(children: [
        _RailBtn(icon: Icons.favorite_border, label: '',
            onTap: () async {
              try { await UellowApi.instance.wishlist.add(productId); }
              catch (_) {}
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                duration: const Duration(milliseconds: 900),
                content: Text(ar ? 'تمت الإضافة لقائمة الأمنيات' : 'Added to wishlist'),
              ));
            }),
        const SizedBox(height: 14),
        _RailBtn(icon: Icons.chat_bubble_outline,
            label: '${(p['rating'] as Map?)?['count'] ?? 0}',
            onTap: () => UellowRouter.goProduct(context, productId)),
        const SizedBox(height: 14),
        _RailBtn(icon: Icons.shopping_cart_outlined, label: '',
            onTap: () => UellowRouter.goProduct(context, productId)),
        const SizedBox(height: 14),
        _RailBtn(icon: Icons.share_outlined, label: '',
            onTap: () {
              final slug = (p['slug'] as String?) ?? '';
              Share.share('${UellowApi.instance.baseUrl}/shop/$slug');
            }),
      ])),
    ]);
  }

  Widget _buildThumbnail(String? thumb) {
    if (thumb == null || thumb.isEmpty) {
      return Container(color: Colors.black,
        child: const Center(child: Icon(Icons.play_circle_outline,
            color: Colors.white38, size: 80)));
    }
    final url = thumb.startsWith('http') ? thumb : '${UellowApi.instance.baseUrl}$thumb';
    return Stack(fit: StackFit.expand, children: [
      CachedNetworkImage(imageUrl: url, fit: BoxFit.cover,
          errorWidget: (_, __, ___) => Container(color: Colors.black)),
      Container(color: Colors.black.withValues(alpha: 0.25)),
      const Center(child: Icon(Icons.play_circle_outline,
          color: Colors.white, size: 84)),
    ]);
  }

  void _openEmbedOrProduct() {
    final pid = (_product['id'] as num?)?.toInt() ?? 0;
    if (pid > 0) UellowRouter.goProduct(context, pid);
  }
}

class _RailBtn extends StatelessWidget {
  const _RailBtn({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(onTap: onTap, child: Column(children: [
      Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: Colors.white, size: 22),
      ),
      if (label.isNotEmpty) Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Text(label, style: const TextStyle(color: Colors.white,
            fontSize: 10.5, fontWeight: FontWeight.w800,
            shadows: [Shadow(color: Colors.black87, blurRadius: 4)])),
      ),
    ]));
  }
}
