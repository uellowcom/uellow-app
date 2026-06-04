// =============================================================================
// ReelsScreen — TikTok-style vertical feed of products that have a video.
// v2.1.4 — search→grid, separate comments, wishlist heart (guest→sign-in +
//          red when saved), bottom engagement stats, pull-to-refresh, and a
//          GLOBAL mute (unmuting one reel applies to all + persists).
// =============================================================================
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../api/uellow_api.dart';
import '../router/uellow_router.dart';
import '../theme/uellow_theme.dart';
import '../widgets/uellow_bottom_nav.dart';
import 'auth_screen.dart';

// Global mute state — shared by every slide so unmuting one reel unmutes all,
// and the choice persists while the app is open. Starts muted (autoplay).
final ValueNotifier<bool> reelsMuted = ValueNotifier<bool>(true);

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
  // Fresh random seed each time the tab opens → different order every visit.
  int _seed = Random().nextInt(1 << 31);

  // Search
  bool _searchOpen = false;
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _searchLoading = false;
  Timer? _searchDebounce;

  bool get _ar => UellowApi.instance.lang.toLowerCase().startsWith('ar');

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _searchCtrl.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _fetch() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final url = Uri.parse(
        '${UellowApi.instance.baseUrl}/api/mobile/v2/videos/feed'
        '?limit=10&seed=$_seed${_cursor > 0 ? "&cursor=$_cursor" : ""}',
      );
      final r = await http.get(url, headers: await _headers())
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
    } catch (_) {/* swallow */}
    if (mounted) setState(() => _loading = false);
  }

  Future<Map<String, String>> _headers() async {
    final token = await UellowApi.instance.tokenStore.readToken();
    return {
      'Accept': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  // Pull-to-refresh — new random order from the top.
  Future<void> _refresh() async {
    _cursor = 0;
    _hasMore = true;
    _activeIdx = 0;
    _seed = Random().nextInt(1 << 31);
    setState(() => _items.clear());
    await _fetch();
    if (_pageCtrl.hasClients) _pageCtrl.jumpToPage(0);
  }

  void _onPageChanged(int i) {
    setState(() => _activeIdx = i);
    if (i >= _items.length - 3) _fetch();
  }

  void _onSearchChanged(String q) {
    _searchDebounce?.cancel();
    if (q.trim().isEmpty) {
      setState(() { _searchResults = []; _searchLoading = false; });
      return;
    }
    setState(() => _searchLoading = true);
    _searchDebounce = Timer(const Duration(milliseconds: 350),
        () => _runSearch(q.trim()));
  }

  Future<void> _runSearch(String q) async {
    try {
      final url = Uri.parse('${UellowApi.instance.baseUrl}'
          '/api/mobile/v2/videos/search?q=${Uri.encodeQueryComponent(q)}&limit=40');
      final r = await http.get(url, headers: await _headers())
          .timeout(const Duration(seconds: 12));
      final body = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      final items = body['success'] == true
          ? ((body['data']?['items'] as List? ?? const []).cast<Map<String, dynamic>>())
          : <Map<String, dynamic>>[];
      if (mounted) setState(() { _searchResults = items; _searchLoading = false; });
    } catch (_) {
      if (mounted) setState(() { _searchResults = []; _searchLoading = false; });
    }
  }

  // Tap a search result → play the search results as the feed.
  void _openResult(int i) {
    setState(() {
      _items
        ..clear()
        ..addAll(_searchResults);
      _activeIdx = i;
      _hasMore = false;
      _searchOpen = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageCtrl.hasClients) _pageCtrl.jumpToPage(i);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ar = _ar;
    return Scaffold(
      backgroundColor: Colors.black,
      bottomNavigationBar: const UellowBottomNav(active: UNavTab.reels),
      body: SafeArea(child: Stack(children: [
        if (_items.isEmpty && _loading)
          const Center(child: CircularProgressIndicator(color: Colors.white))
        else if (_items.isEmpty)
          _emptyState(ar)
        else
          RefreshIndicator(
            color: UellowColors.darkBrown,
            backgroundColor: Colors.white,
            onRefresh: _refresh,
            child: PageView.builder(
              controller: _pageCtrl,
              scrollDirection: Axis.vertical,
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: _items.length,
              onPageChanged: _onPageChanged,
              itemBuilder: (_, i) => _ReelSlide(
                item: _items[i], active: i == _activeIdx, ar: ar),
            ),
          ),
        // Top bar — title + search
        Positioned(top: 6, left: 8, right: 8, child: Row(children: [
          const SizedBox(width: 44),
          Expanded(child: Center(child: Text(ar ? 'فيديوهات' : 'Reels',
              style: const TextStyle(color: Colors.white, fontSize: 16,
                  fontWeight: FontWeight.w900,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 4)])))),
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white),
            onPressed: () => setState(() => _searchOpen = true),
          ),
        ])),
        if (_searchOpen) _searchOverlay(ar),
      ])),
    );
  }

  Widget _emptyState(bool ar) => ListView(children: [
        const SizedBox(height: 140),
        const Center(child: Icon(Icons.videocam_off_outlined,
            color: Colors.white54, size: 56)),
        const SizedBox(height: 12),
        Center(child: Text(ar ? 'لا توجد فيديوهات بعد — تابعنا لاحقاً'
                : 'No videos yet — check back later',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 14))),
      ]);

  Widget _searchOverlay(bool ar) {
    return Positioned.fill(child: Container(
      color: Colors.black.withValues(alpha: 0.97),
      child: SafeArea(child: Column(children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: Row(children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => setState(() {
                _searchOpen = false;
                _searchCtrl.clear();
                _searchResults = [];
              }),
            ),
            Expanded(child: Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Center(child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                onChanged: _onSearchChanged,
                textInputAction: TextInputAction.search,
                style: const TextStyle(color: Colors.black, fontSize: 14),
                cursorColor: UellowColors.darkBrown,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  hintText: ar ? 'ابحث باسم المنتج…' : 'Search by product name…',
                  hintStyle: const TextStyle(color: Colors.black45),
                  icon: const Icon(Icons.search, color: Colors.black45, size: 18),
                ),
              )),
            )),
          ]),
        ),
        if (_searchLoading)
          const Padding(padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(color: Colors.white))
        else if (_searchResults.isEmpty && _searchCtrl.text.isNotEmpty)
          Padding(padding: const EdgeInsets.all(30),
              child: Text(ar ? 'لا نتائج' : 'No results',
                  style: const TextStyle(color: Colors.white54)))
        else
          Expanded(child: GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3, crossAxisSpacing: 6, mainAxisSpacing: 6,
              childAspectRatio: 0.62,
            ),
            itemCount: _searchResults.length,
            itemBuilder: (_, i) => _SearchTile(
              item: _searchResults[i], ar: ar, onTap: () => _openResult(i)),
          )),
      ])),
    ));
  }
}

// Grid tile in the search results.
class _SearchTile extends StatelessWidget {
  const _SearchTile({required this.item, required this.ar, required this.onTap});
  final Map<String, dynamic> item;
  final bool ar;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final video = (item['video'] as Map?)?.cast<String, dynamic>() ?? {};
    final p = (item['product'] as Map?)?.cast<String, dynamic>() ?? {};
    final stats = (item['stats'] as Map?)?.cast<String, dynamic>() ?? {};
    var thumb = video['thumbnail']?.toString() ?? '';
    if (thumb.isNotEmpty && !thumb.startsWith('http')) {
      thumb = '${UellowApi.instance.baseUrl}$thumb';
    }
    final name = ((p['name'] as Map?)?[ar ? 'ar' : 'en'] as String?) ?? '';
    final views = (stats['views'] as num?)?.toInt() ?? 0;
    return GestureDetector(onTap: onTap, child: ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(fit: StackFit.expand, children: [
        if (thumb.isNotEmpty)
          CachedNetworkImage(imageUrl: thumb, fit: BoxFit.cover,
              errorWidget: (_, __, ___) => Container(color: Colors.white12))
        else
          Container(color: Colors.white12,
              child: const Icon(Icons.play_circle_outline, color: Colors.white38)),
        const Positioned(top: 4, right: 4,
            child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 18)),
        Positioned(left: 0, right: 0, bottom: 0, child: Container(
          padding: const EdgeInsets.fromLTRB(6, 10, 6, 5),
          decoration: const BoxDecoration(gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black87])),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 10.5,
                    fontWeight: FontWeight.w700)),
            Row(children: [
              const Icon(Icons.visibility, color: Colors.white60, size: 11),
              const SizedBox(width: 3),
              Text('$views', style: const TextStyle(color: Colors.white60, fontSize: 10)),
            ]),
          ]),
        )),
      ]),
    ));
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

class _ReelSlideState extends State<_ReelSlide> with RouteAware {
  VideoPlayerController? _ctrl;
  bool _initFailed = false;
  late bool _faved;
  late int _wishlist;
  late int _shares;
  late int _views;
  late int _comments;

  Map<String, dynamic> get _video =>
      (widget.item['video'] as Map).cast<String, dynamic>();
  Map<String, dynamic> get _product =>
      (widget.item['product'] as Map).cast<String, dynamic>();
  int get _videoId => (_video['id'] as num?)?.toInt() ?? 0;
  int get _productId => (_product['id'] as num?)?.toInt() ?? 0;

  @override
  void initState() {
    super.initState();
    _faved = widget.item['is_wishlisted'] == true;
    final s = (widget.item['stats'] as Map?)?.cast<String, dynamic>() ?? {};
    _wishlist = (s['wishlist'] as num?)?.toInt() ?? 0;
    _shares = (s['shares'] as num?)?.toInt() ?? 0;
    _views = (s['views'] as num?)?.toInt() ?? 0;
    _comments = (s['comments'] as num?)?.toInt() ?? 0;
    reelsMuted.addListener(_applyMute);
    _maybeInitVideo();
  }

  @override
  void didUpdateWidget(_ReelSlide old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _maybeInitVideo();
    if (!widget.active && old.active) _ctrl?.pause();
    if (widget.active && _ctrl != null && _ctrl!.value.isInitialized) _ctrl!.play();
  }

  String? get _fileUrl {
    final f = _video['file_url']?.toString();
    if (f == null || f.isEmpty) return null;
    return f.startsWith('http') ? f : '${UellowApi.instance.baseUrl}$f';
  }

  void _applyMute() {
    if (_ctrl != null && _ctrl!.value.isInitialized) {
      _ctrl!.setVolume(reelsMuted.value ? 0 : 1);
    }
  }

  Future<void> _maybeInitVideo() async {
    final url = _fileUrl;
    if (url == null || _ctrl != null) return;
    try {
      final mime = _video['mime']?.toString().toLowerCase() ?? '';
      final isHls = mime.contains('mpegurl') || mime.contains('hls')
          || Uri.parse(url).path.toLowerCase().endsWith('.m3u8');
      _ctrl = VideoPlayerController.networkUrl(Uri.parse(url),
          formatHint: isHls ? VideoFormat.hls : null);
      await _ctrl!.initialize();
      _ctrl!
        ..setLooping(true)
        ..setVolume(reelsMuted.value ? 0 : 1)
        ..play();
      _reportView();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => _initFailed = true);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) appRouteObserver.subscribe(this, route);
  }

  // RouteAware — play ONLY while the reels route is the visible top route.
  @override
  void didPushNext() => _ctrl?.pause();   // a screen opened on top of reels
  @override
  void didPopNext() => _resumeIfActive(); // returned to reels

  @override
  void deactivate() {
    // Leaving the tab (or covering the screen) must STOP playback+audio
    // immediately, frozen at the current frame — not keep playing in the bg.
    _ctrl?.pause();
    super.deactivate();
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    reelsMuted.removeListener(_applyMute);
    _ctrl?.dispose();
    super.dispose();
  }

  // v2.1.29 — count a view ONCE per video per session the moment it
  // starts playing (Bunny stats lag a day; this moves instantly).
  static final Set<int> _viewReported = {};
  void _reportView() {
    if (_videoId == 0 || _viewReported.contains(_videoId)) return;
    _viewReported.add(_videoId);
    http.post(Uri.parse('${UellowApi.instance.baseUrl}'
        '/api/mobile/v2/videos/$_videoId/view'),
        headers: {'Content-Type': 'application/json'}, body: '{}')
        .then((_) {
      if (mounted) setState(() => _views += 1);
    }).catchError((_) => http.Response('', 599));
  }

  Future<void> _toggleFav() async {
    var token = await UellowApi.instance.tokenStore.readToken();
    if (token == null || token.isEmpty) {
      // Login as a DIALOG — keeps the user on the reel.
      final ok = await showAuthSheet(context);
      if (!ok || !mounted) return;
      token = await UellowApi.instance.tokenStore.readToken();
      if (token == null || token.isEmpty) return;
    }
    final wasFaved = _faved;
    setState(() {
      _faved = !wasFaved;
      _wishlist = (_wishlist + (wasFaved ? -1 : 1)).clamp(0, 1 << 30);
    });
    try {
      if (wasFaved) {
        await UellowApi.instance.wishlist.remove(_productId);
      } else {
        await UellowApi.instance.wishlist.add(_productId);
      }
    } catch (_) {
      if (mounted) setState(() {
        _faved = wasFaved;
        _wishlist = (_wishlist + (wasFaved ? 1 : -1)).clamp(0, 1 << 30);
      });
    }
  }

  // Fully stop playback (frees the stream / saves data) while we're on
  // another screen, then resume only if this slide is still the active one.
  void _pause() => _ctrl?.pause();
  void _resumeIfActive() {
    if (mounted && widget.active && _ctrl != null && _ctrl!.value.isInitialized) {
      _ctrl!.play();
    }
  }

  Future<void> _goProduct() async {
    _pause();
    await Navigator.of(context)
        .pushNamed(Routes.product, arguments: {'id': _productId});
    _resumeIfActive();
  }

  Future<void> _share() async {
    _pause();
    final slug = (_product['slug'] as String?) ?? '';
    setState(() => _shares += 1);
    try {
      await http.post(Uri.parse('${UellowApi.instance.baseUrl}'
          '/api/mobile/v2/videos/$_videoId/share'));
    } catch (_) {}
    try {
      await Share.share('${UellowApi.instance.baseUrl}/shop/$slug');
    } catch (_) {}
    _resumeIfActive();
  }

  void _openComments() {
    _pause();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CommentsSheet(
        videoId: _videoId, ar: widget.ar,
        onAdded: () { if (mounted) setState(() => _comments += 1); },
      ),
    ).whenComplete(_resumeIfActive);
  }

  @override
  Widget build(BuildContext context) {
    final ar = widget.ar;
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
    return Stack(children: [
      Positioned.fill(child: _initFailed || _ctrl == null || !_ctrl!.value.isInitialized
        ? _buildThumbnail(thumb)
        : FittedBox(fit: BoxFit.cover, child: SizedBox(
            width: _ctrl!.value.size.width,
            height: _ctrl!.value.size.height,
            child: VideoPlayer(_ctrl!)))),
      // Tap anywhere toggles the GLOBAL mute (or opens product if no player).
      Positioned.fill(child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          if (_ctrl == null || !_ctrl!.value.isInitialized) {
            _openEmbedOrProduct();
            return;
          }
          reelsMuted.value = !reelsMuted.value;
        },
      )),
      // Sound button (reflects + toggles the global mute)
      if (_ctrl != null && _ctrl!.value.isInitialized) Positioned(
        top: 44, right: 14,
        child: ValueListenableBuilder<bool>(
          valueListenable: reelsMuted,
          builder: (_, muted, __) => GestureDetector(
            onTap: () => reelsMuted.value = !muted,
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.55), width: 1),
              ),
              child: Icon(muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                  color: Colors.white, size: 21),
            ),
          ),
        ),
      ),
      // Bottom-left product details + engagement stats
      Positioned(left: 16, right: 92, bottom: 28, child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (brand != null && brand.isNotEmpty)
            Text(brand, style: TextStyle(color: Colors.white.withValues(alpha: 0.85),
                fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.5,
                shadows: const [Shadow(color: Colors.black87, blurRadius: 4)])),
          const SizedBox(height: 4),
          Text(name, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 14.5,
                  fontWeight: FontWeight.w800, height: 1.25,
                  shadows: [Shadow(color: Colors.black87, blurRadius: 6)])),
          const SizedBox(height: 8),
          Row(children: [
            Text('${priceAmt.toStringAsFixed(3)} $priceSym',
                style: const TextStyle(color: Colors.white, fontSize: 16,
                    fontWeight: FontWeight.w900,
                    shadows: [Shadow(color: Colors.black87, blurRadius: 4)])),
            if (cmpAmt != null && cmpAmt > priceAmt) ...[
              const SizedBox(width: 6),
              Text(cmpAmt.toStringAsFixed(3), style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65), fontSize: 11,
                  decoration: TextDecoration.lineThrough,
                  decorationColor: Colors.white.withValues(alpha: 0.65),
                  fontWeight: FontWeight.w600)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(color: UellowColors.danger,
                    borderRadius: BorderRadius.circular(4)),
                child: Text('-$disc%', style: const TextStyle(color: Colors.white,
                    fontSize: 9.5, fontWeight: FontWeight.w900)),
              ),
            ],
          ]),
          const SizedBox(height: 8),
          // Engagement stats — small, grey, translucent
          Row(children: [
            _stat(Icons.favorite, _wishlist),
            _stat(Icons.visibility, _views),
            _stat(Icons.reply, _shares),
            _stat(Icons.mode_comment, _comments),
          ]),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _goProduct,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(color: UellowColors.yellow,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 8)]),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.shopping_bag_outlined, size: 14, color: UellowColors.darkBrown),
                const SizedBox(width: 5),
                Text(ar ? 'عرض المنتج' : 'View product',
                    style: const TextStyle(color: UellowColors.darkBrown,
                        fontSize: 11.5, fontWeight: FontWeight.w900)),
              ]),
            ),
          ),
        ],
      )),
      // Right rail — wishlist / comments / cart / share
      Positioned(right: 14, bottom: 120, child: Column(children: [
        _RailBtn(
          icon: _faved ? Icons.favorite : Icons.favorite_border,
          color: _faved ? UellowColors.danger : Colors.white,
          label: _wishlist > 0 ? _fmt(_wishlist) : '',
          onTap: _toggleFav),
        const SizedBox(height: 14),
        _RailBtn(icon: Icons.mode_comment_outlined,
            label: _comments > 0 ? _fmt(_comments) : '',
            onTap: _openComments),
        const SizedBox(height: 14),
        _RailBtn(icon: Icons.shopping_cart_outlined, label: '',
            onTap: _goProduct),
        const SizedBox(height: 14),
        _RailBtn(icon: Icons.reply, label: _shares > 0 ? _fmt(_shares) : '',
            onTap: _share),
      ])),
    ]);
  }

  Widget _stat(IconData icon, int n) => Padding(
    padding: const EdgeInsets.only(right: 14),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: Colors.white.withValues(alpha: 0.6)),
      const SizedBox(width: 4),
      Text(_fmt(n), style: TextStyle(color: Colors.white.withValues(alpha: 0.6),
          fontSize: 11, fontWeight: FontWeight.w700)),
    ]),
  );

  static String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
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
      const Center(child: Icon(Icons.play_circle_outline, color: Colors.white, size: 84)),
    ]);
  }

  void _openEmbedOrProduct() {
    if (_productId > 0) UellowRouter.goProduct(context, _productId);
  }
}

class _RailBtn extends StatelessWidget {
  const _RailBtn({required this.icon, required this.label, required this.onTap,
      this.color = Colors.white});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(onTap: onTap, child: Column(children: [
      Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35), shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Icon(icon, color: color, size: 22),
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

// ── Comments bottom sheet (separate from product reviews) ───────────────────
class _CommentsSheet extends StatefulWidget {
  const _CommentsSheet({required this.videoId, required this.ar, required this.onAdded});
  final int videoId;
  final bool ar;
  final VoidCallback onAdded;
  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final _ctrl = TextEditingController();
  final _inputFocus = FocusNode();
  List<Map<String, dynamic>> _comments = [];
  bool _loading = true;
  bool _sending = false;
  int? _replyToId;          // when set, the next send is a reply
  String? _replyToAuthor;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _startReply(Map<String, dynamic> c) {
    setState(() {
      _replyToId = (c['id'] as num?)?.toInt();
      _replyToAuthor = (c['author'] ?? '').toString();
    });
    _inputFocus.requestFocus();
  }

  void _cancelReply() => setState(() { _replyToId = null; _replyToAuthor = null; });

  Future<void> _load() async {
    try {
      final r = await http.get(Uri.parse('${UellowApi.instance.baseUrl}'
          '/api/mobile/v2/videos/${widget.videoId}/comments'),
          headers: {'Accept': 'application/json'}).timeout(const Duration(seconds: 12));
      final body = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (body['success'] == true && mounted) {
        setState(() {
          _comments = ((body['data']?['items'] as List? ?? const [])
              .cast<Map<String, dynamic>>());
          _loading = false;
        });
        return;
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    var token = await UellowApi.instance.tokenStore.readToken();
    if (token == null || token.isEmpty) {
      final ok = await showAuthSheet(context);
      if (!ok || !mounted) return;
      token = await UellowApi.instance.tokenStore.readToken();
      if (token == null || token.isEmpty) return;
    }
    final replyTo = _replyToId;
    setState(() => _sending = true);
    try {
      final r = await http.post(
        Uri.parse('${UellowApi.instance.baseUrl}'
            '/api/mobile/v2/videos/${widget.videoId}/comments'),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'body': text, if (replyTo != null) 'parent_id': replyTo}),
      ).timeout(const Duration(seconds: 12));
      final body = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (body['success'] == true && mounted) {
        final created = (body['data'] as Map).cast<String, dynamic>();
        setState(() {
          if (replyTo != null) {
            final parent = _comments.firstWhere(
                (x) => (x['id'] as num?)?.toInt() == replyTo, orElse: () => {});
            if (parent.isNotEmpty) {
              final reps = (parent['replies'] as List?)?.cast<Map<String, dynamic>>()
                  ?? <Map<String, dynamic>>[];
              reps.add(created);
              parent['replies'] = reps;
            }
          } else {
            _comments.insert(0, created);
          }
          _ctrl.clear();
          _replyToId = null;
          _replyToAuthor = null;
        });
        widget.onAdded();
      }
    } catch (_) {}
    if (mounted) setState(() => _sending = false);
  }

  Widget _commentTile(Map<String, dynamic> c, {bool isReply = false}) {
    final ar = widget.ar;
    final seller = c['is_seller'] == true;
    final replies = (c['replies'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CircleAvatar(radius: isReply ? 13 : 16,
            backgroundColor: seller ? UellowColors.darkBrown : UellowColors.yellowSoft,
            child: Icon(seller ? Icons.storefront : Icons.person,
                size: isReply ? 14 : 18,
                color: seller ? UellowColors.yellowLight : UellowColors.darkBrown)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Flexible(child: Text((c['author'] ?? '').toString(),
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5))),
            if (seller) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: UellowColors.yellow,
                    borderRadius: BorderRadius.circular(4)),
                child: Text(ar ? 'المتجر' : 'Store',
                    style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900,
                        color: UellowColors.darkBrown)),
              ),
            ],
          ]),
          const SizedBox(height: 2),
          Text((c['body'] ?? '').toString(),
              style: const TextStyle(fontSize: 13, color: UellowColors.ink)),
          if (!isReply) GestureDetector(
            onTap: () => _startReply(c),
            child: Padding(padding: const EdgeInsets.only(top: 4),
                child: Text(ar ? 'رد' : 'Reply',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800,
                        color: UellowColors.muted))),
          ),
        ])),
      ]),
      if (replies.isNotEmpty) Padding(
        padding: EdgeInsetsDirectional.only(start: 38, top: 8),
        child: Column(children: [
          for (final rr in replies) Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _commentTile(rr, isReply: true)),
        ]),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final ar = widget.ar;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        child: Column(children: [
          const SizedBox(height: 10),
          Center(child: Container(width: 36, height: 4,
              decoration: BoxDecoration(color: UellowColors.border,
                  borderRadius: BorderRadius.circular(2)))),
          Padding(padding: const EdgeInsets.all(14),
              child: Text(ar ? 'التعليقات' : 'Comments', style: UT.h3)),
          const Divider(height: 1),
          Expanded(child: _loading
            ? const Center(child: CircularProgressIndicator(color: UellowColors.darkBrown))
            : _comments.isEmpty
              ? Center(child: Text(ar ? 'كن أول من يعلّق' : 'Be the first to comment',
                  style: const TextStyle(color: UellowColors.muted)))
              : ListView.separated(
                  padding: const EdgeInsets.all(14),
                  itemCount: _comments.length,
                  separatorBuilder: (_, __) => const Divider(height: 22),
                  itemBuilder: (_, i) => _commentTile(_comments[i]),
                )),
          if (_replyToId != null) Container(
            color: UellowColors.yellowSoft,
            padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
            child: Row(children: [
              Expanded(child: Text(
                  '${ar ? "رد على" : "Replying to"} ${_replyToAuthor ?? ''}',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: UellowColors.darkBrown,
                      fontWeight: FontWeight.w700))),
              GestureDetector(onTap: _cancelReply,
                  child: const Icon(Icons.close, size: 16, color: UellowColors.darkBrown)),
            ]),
          ),
          SafeArea(top: false, child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(children: [
              Expanded(child: TextField(
                controller: _ctrl,
                focusNode: _inputFocus,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                style: const TextStyle(color: Colors.black),
                decoration: InputDecoration(
                  hintText: _replyToId != null
                      ? (ar ? 'اكتب ردك…' : 'Write your reply…')
                      : (ar ? 'أضف تعليقاً…' : 'Add a comment…'),
                  filled: true, fillColor: UellowColors.border.withValues(alpha: 0.4),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999), borderSide: BorderSide.none),
                ),
              )),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _sending ? null : _send,
                icon: _sending
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send, color: UellowColors.darkBrown),
              ),
            ]),
          )),
        ]),
      ),
    );
  }
}
