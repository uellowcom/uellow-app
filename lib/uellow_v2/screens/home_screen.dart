// =============================================================================
// HomeScreen — primary surface of the app.
//
// Renders the home page designed in the visual builder when one is
// configured (mobile.page slug='home'). When the dynamic page is empty
// or the fetch fails, falls back to the legacy hand-built layout below:
//   • Top bar (search + barcode + camera)
//   • Category strip
//   • Hero slider · features chips · category icons · flash · product rails
// =============================================================================
import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../api/uellow_api.dart';
import '../../api/uellow_endpoints.dart';
import '../../api/uellow_models.dart';
import '../router/uellow_router.dart';
import '../services/ads_service.dart';
import '../theme/uellow_theme.dart';
import '../widgets/product_card.dart';
import '../widgets/review_requests_strip.dart';
import '../widgets/review_prompt_dialog.dart';
import '../widgets/update_gate.dart';
import '../widgets/uellow_bottom_nav.dart';
import '../widgets/updating_pane.dart';
import 'dynamic_page_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // v2.1.61 — SNAPSHOT-FIRST: the last good page renders instantly from
  // disk (zero flash, zero spinner on slow networks); the network fetch
  // then refreshes it in place. The legacy `/home` API call is gone.
  _DynHome? _dyn;
  bool _settled = false;

  @override
  void initState() {
    super.initState();
    _loadHome();
    // v2.1.27 — open-sequence ads: splash flash first, then popup
    // (frequency-capped). Runs once per app session.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AdsService.showOpenAds(context);
      // v2.1.50 — post-delivery review nudge with loyalty rewards
      // (shows only when a delivered order has unreviewed items).
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) ReviewPromptService.maybeShow(context);
      });
    });
    // v2.1.29 — warm the wishlist cache so card hearts render red.
    UellowApi.instance.wishlist.warm();
    // v2.1.34 — pull app settings once: best-seller badge placement
    // ('off' / 'category' / 'related' / 'all') is backend-controlled.
    UellowApi.instance.settings.get().then((s) {
      ProductCard.rankBadgeScope = s.rankBadgeScope;
      // v2.1.50 — premium update gate: when the backend's min version is
      // newer than this build, show the update sheet (blocking when
      // force_update is ON in Mobile App → Settings).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) UpdateGate.check(context, s);
      });
    }, onError: (_) {});
  }

  /// Fetch the builder-designed `home` page.
  ///
  /// v2.1.57 — the LEGACY hand-built home is gone: on slow networks its
  /// flash (old navbar/design) confused users. Strategy now:
  ///   1. network fetch (12s) → render + SAVE as the local snapshot
  ///   2. fetch failed → render the LAST GOOD snapshot (same current
  ///      design, refreshed on every successful load)
  ///   3. no snapshot either → null → error + retry state (never legacy)
  Future<void> _loadHome() async {
    // 1) snapshot instantly — current design, refreshed on every
    //    successful load, so slow starts show it with NO flash.
    final snap = await _readSnapshot();
    if (snap != null && mounted && _dyn == null) {
      setState(() => _dyn = snap);
    }
    // 2) network refresh in the background; swaps in when it lands.
    final fresh = await _fetchNetworkHome();
    if (!mounted) return;
    setState(() {
      if (fresh != null) _dyn = fresh;
      _settled = true;
    });
  }

  Future<_DynHome?> _readSnapshot() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw =
          prefs.getString('home_page_cache_v1_${UellowApi.instance.lang}');
      if (raw != null && raw.isNotEmpty) {
        final d = (jsonDecode(raw) as Map).cast<String, dynamic>();
        final blocks = (d['blocks'] as List? ?? const []).cast<dynamic>();
        if (blocks.isNotEmpty) {
          return _DynHome(
            theme: DynTheme.fromJson((d['theme'] as Map? ?? const {})),
            blocks: blocks
                .map((e) => (e as Map).cast<String, dynamic>())
                .toList(),
          );
        }
      }
    } catch (_) {}
    return null;
  }

  Future<_DynHome?> _fetchNetworkHome() async {
    final api = UellowApi.instance;
    final cacheKey = 'home_page_cache_v1_${api.lang}';
    try {
      // `_t` cache-buster forces every reload to bypass any HTTP cache so
      // edits made in the builder show up immediately after a refresh.
      final res = await http.get(
        Uri.parse('${api.baseUrl}/api/mobile/v2/pages/home?_t=${DateTime.now().millisecondsSinceEpoch}'),
        headers: {
          'Accept': 'application/json',
          'X-Lang': api.lang,
          'Cache-Control': 'no-cache',
        },
      ).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        if (j['success'] == true) {
          final d = (j['data'] as Map).cast<String, dynamic>();
          final blocks = (d['blocks'] as List? ?? const []).cast<dynamic>();
          if (blocks.isNotEmpty) {
            // snapshot replaced on EVERY successful load — offline /
            // slow starts always show the current design.
            try {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString(cacheKey, jsonEncode(d));
            } catch (_) {}
            return _DynHome(
              theme: DynTheme.fromJson((d['theme'] as Map? ?? const {})),
              blocks: blocks
                  .map((e) => (e as Map).cast<String, dynamic>())
                  .toList(),
            );
          }
        }
      }
    } catch (_) {/* snapshot (already rendered) stays */}
    return null;
  }

  Future<void> _refresh() async {
    final fresh = await _fetchNetworkHome();
    if (!mounted) return;
    setState(() {
      if (fresh != null) _dyn = fresh;
      _settled = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UellowColors.bg,
      body: SafeArea(bottom: false, child: RefreshIndicator(
        color: UellowColors.darkBrown,
        backgroundColor: UellowColors.yellowLight,
        onRefresh: _refresh,
        child: Builder(builder: (context) {
          // v2.1.61 — snapshot renders the instant it's read; network
          // result swaps in silently. Spinner only on a TRUE first install.
          if (_dyn != null) return _buildDynamic(context, _dyn!);
          if (!_settled) return const _LoadingState();
          return _ErrorState(
              message: UellowApi.instance.lang == 'ar'
                  ? 'تعذّر تحميل الصفحة الرئيسية — تحقق من الاتصال'
                  : 'Could not load the home page — check your connection',
              onRetry: _refresh);
        }),
      )),
      bottomNavigationBar: const UellowBottomNav(active: UNavTab.home),
      // v2.2.06 — page content shows THROUGH the floating strips area
      // (Beena bubble / reviewers banner): true transparency.
      extendBody: true,
    );
  }

  // ── Dynamic body — top bar + dynamic blocks from /api/mobile/v2/pages/home
  Widget _buildDynamic(BuildContext context, _DynHome dyn) {
    return Container(
      color: dyn.theme.pageBg,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _TopBar()),
          // v2.1.57 — targeted announcement strip (admin-controlled).
          // v2.1.59 — personal strip for the customer's specialist
          // requests (pending → replied).
          const SliverToBoxAdapter(child: ReviewRequestsStrip()),
          SliverList.builder(
            itemCount: dyn.blocks.length,
            itemBuilder: (ctx, i) => RepaintBoundary(
              child: renderDynamicBlock(ctx, dyn.blocks[i], dyn.theme),
            ),
            addAutomaticKeepAlives: false,
            addRepaintBoundaries: false, // we add it manually for tighter control
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
    );
  }

}

class _DynHome {
  _DynHome({required this.theme, required this.blocks});
  final DynTheme theme;
  final List<Map<String, dynamic>> blocks;
}

// ─── Flash sale block ──────────────────────────────────────────────

class _FlashSaleBlock extends StatefulWidget {
  const _FlashSaleBlock();
  @override
  State<_FlashSaleBlock> createState() => _FlashSaleBlockState();
}

class _FlashSaleBlockState extends State<_FlashSaleBlock> {
  Future<List<UellowProductCard>>? _future;

  @override
  void initState() {
    super.initState();
    _future = UellowApi.instance.products.list(onSale: true, perPage: 8)
        .then((page) => page.items).catchError((_) => <UellowProductCard>[]);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<UellowProductCard>>(
      future: _future,
      builder: (_, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        final items = snap.data ?? [];
        if (items.isEmpty) return const SizedBox.shrink();
        final ar = UellowApi.instance.lang == 'ar';
        return GestureDetector(
          onTap: () => Navigator.pushNamed(context, Routes.flash),
          child: Container(
            margin: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [BoxShadow(
                  color: Color(0x29F5A800), blurRadius: 18, offset: Offset(0, 6))],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(children: [
              // Yellow → orange gradient base
              Positioned.fill(child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [Color(0xFFFFD340), Color(0xFFF59E0B), Color(0xFFEA580C)],
                    stops: [0.0, 0.55, 1.0],
                  ),
                ),
              )),
              // Subtle diagonal stripe pattern
              Positioned.fill(child: IgnorePointer(child: CustomPaint(
                painter: _DiagonalStripes(),
              ))),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(Icons.flash_on, color: Colors.white, size: 16),
                    const SizedBox(width: 4),
                    Text(ar ? 'فلاش سيل' : 'Flash Sale',
                        style: const TextStyle(color: Colors.white,
                            fontSize: 13, fontWeight: FontWeight.w900,
                            letterSpacing: 0.2)),
                    const SizedBox(width: 8),
                    // Tiny "See more" pill on the same header row.
                    // The whole block is already tappable to /flash, this
                    // is the visual affordance.
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: const [BoxShadow(
                            color: Color(0x33000000), blurRadius: 3,
                            offset: Offset(0, 1))],
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(ar ? 'المزيد' : 'See more',
                            style: const TextStyle(color: Color(0xFFEA580C),
                                fontSize: 9.5, fontWeight: FontWeight.w900,
                                letterSpacing: 0.2)),
                        const SizedBox(width: 1),
                        Icon(ar ? Icons.chevron_left : Icons.chevron_right,
                            size: 12, color: const Color(0xFFEA580C)),
                      ]),
                    ),
                    const Spacer(),
                    const _LiveDhmsCounter(),
                  ]),
                  const SizedBox(height: 10),
                  SizedBox(height: 216,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) => SizedBox(
                          width: 138,
                          child: ProductCard(product: items[i], inFlashSale: true)),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        );
      },
    );
  }
}

/// Diagonal-stripe pattern painter for the flash sale bg.
class _DiagonalStripes extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x14FFFFFF)
      ..strokeWidth = 6;
    final spacing = 18.0;
    for (var x = -size.height.toDouble(); x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0),
          Offset(x + size.height, size.height), paint);
    }
  }
  @override
  bool shouldRepaint(covariant _) => false;
}

class _LiveDhmsCounter extends StatefulWidget {
  const _LiveDhmsCounter();
  @override
  State<_LiveDhmsCounter> createState() => _LiveDhmsCounterState();
}

class _LiveDhmsCounterState extends State<_LiveDhmsCounter> {
  Timer? _t;
  Duration _left = const Duration(days: 1, hours: 4, minutes: 35);
  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _left = _left.inSeconds > 0
            ? _left - const Duration(seconds: 1)
            : const Duration(days: 1);
      });
    });
  }
  @override
  void dispose() { _t?.cancel(); super.dispose(); }
  String _two(int n) => n.toString().padLeft(2, '0');
  @override
  Widget build(BuildContext context) {
    final d = _left.inDays;
    final h = _left.inHours.remainder(24);
    final m = _left.inMinutes.remainder(60);
    final s = _left.inSeconds.remainder(60);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _cell(_two(d), 'D'), const SizedBox(width: 3),
      _cell(_two(h), 'H'), const SizedBox(width: 3),
      _cell(_two(m), 'M'), const SizedBox(width: 3),
      _cell(_two(s), 'S'),
    ]);
  }
  Widget _cell(String v, String u) => Container(
    width: 22, height: 24, alignment: Alignment.center,
    decoration: BoxDecoration(
      color: const Color(0xCC000000),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text(v, style: const TextStyle(
          color: Colors.white, fontWeight: FontWeight.w900,
          fontSize: 11, height: 1, fontFamily: 'monospace')),
      Text(u, style: const TextStyle(
          color: Color(0xB3FFFFFF), fontSize: 7,
          fontWeight: FontWeight.w800, letterSpacing: 0.3)),
    ]),
  );
}

class _LiveCountdownBoxes extends StatefulWidget {
  const _LiveCountdownBoxes();
  @override
  State<_LiveCountdownBoxes> createState() => _LiveCountdownBoxesState();
}

class _LiveCountdownBoxesState extends State<_LiveCountdownBoxes> {
  Timer? _t;
  Duration _left = const Duration(hours: 2, minutes: 14, seconds: 37);
  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _left = _left.inSeconds > 0
            ? _left - const Duration(seconds: 1)
            : const Duration(hours: 24);
      });
    });
  }
  @override
  void dispose() { _t?.cancel(); super.dispose(); }
  String _two(int n) => n.toString().padLeft(2, '0');
  @override
  Widget build(BuildContext context) {
    final h = _left.inHours;
    final m = _left.inMinutes.remainder(60);
    final s = _left.inSeconds.remainder(60);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _box(_two(h)),
      const Text(' : ', style: TextStyle(color: Colors.white,
          fontWeight: FontWeight.w900, fontSize: 14)),
      _box(_two(m)),
      const Text(' : ', style: TextStyle(color: Colors.white,
          fontWeight: FontWeight.w900, fontSize: 14)),
      _box(_two(s)),
    ]);
  }
  Widget _box(String v) => Container(
    width: 28, height: 28, alignment: Alignment.center,
    decoration: BoxDecoration(
      color: UellowColors.danger,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(v, style: const TextStyle(
        color: Colors.white, fontWeight: FontWeight.w900,
        fontSize: 13, fontFamily: 'monospace')),
  );
}

/// Real ticking 24h countdown — resets every midnight so editors don't
/// have to update the static value.
class _LiveCountdown extends StatefulWidget {
  const _LiveCountdown();
  @override
  State<_LiveCountdown> createState() => _LiveCountdownState();
}

class _LiveCountdownState extends State<_LiveCountdown> {
  Duration _remaining = const Duration(hours: 2, minutes: 14, seconds: 37);
  late final Stream<int> _tick;
  @override
  void initState() {
    super.initState();
    _tick = Stream.periodic(const Duration(seconds: 1), (i) => i);
    _tick.listen((_) {
      if (!mounted) return;
      setState(() {
        _remaining = _remaining.inSeconds > 0
            ? Duration(seconds: _remaining.inSeconds - 1)
            : const Duration(hours: 23, minutes: 59, seconds: 59);
      });
    });
  }
  @override
  Widget build(BuildContext context) {
    final h = _remaining.inHours.remainder(24).toString().padLeft(2, '0');
    final m = _remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = _remaining.inSeconds.remainder(60).toString().padLeft(2, '0');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('$h:$m:$s', style: const TextStyle(
          color: Colors.white, fontFamily: 'monospace',
          fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: 1)),
    );
  }
}

// ─── Top bar ───────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: UellowColors.bg,
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
      child: Row(children: [
        Expanded(child: GestureDetector(
          onTap: () => Navigator.pushNamed(context, Routes.search),
          child: Container(
            height: 40, padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              const Icon(Icons.search, size: 18, color: UellowColors.muted),
              const SizedBox(width: 10),
              Expanded(child: Text(
                'ابحث عن منتج، ماركة، أو ﺗﺎﺟﺮ…',
                style: TextStyle(color: UellowColors.muted.withOpacity(.9), fontSize: 13),
              )),
            ]),
          ),
        )),
        const SizedBox(width: 6),
        _IconButton(icon: Icons.qr_code_scanner_outlined,
            onTap: () => Navigator.pushNamed(context, Routes.search)),
        const SizedBox(width: 6),
        _IconButton(icon: Icons.camera_alt_outlined,
            onTap: () => Navigator.pushNamed(context, Routes.search)),
      ]),
    );
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 18, color: UellowColors.text),
      ),
    );
  }
}

// ─── Category strip — fetched from real Odoo categories, text-only ───

class _CategoryStrip extends StatefulWidget {
  @override
  State<_CategoryStrip> createState() => _CategoryStripState();
}

class _CategoryStripState extends State<_CategoryStrip> {
  Future<List<UellowCategory>>? _future;
  int _selected = 0;
  @override
  void initState() {
    super.initState();
    _future = UellowApi.instance.categories.list().catchError((_) => <UellowCategory>[]);
  }
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<UellowCategory>>(
      future: _future,
      builder: (_, snap) {
        if (snap.connectionState != ConnectionState.done) return const SizedBox(height: 40);
        final realCats = (snap.data ?? []).take(12).toList();
        return SizedBox(
          height: 32,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: realCats.length + 1,
            separatorBuilder: (_, __) => const SizedBox(width: 16),
            itemBuilder: (_, i) {
              final label = i == 0 ? 'All'
                  : realCats[i - 1].name.current(UellowApi.instance.lang);
              return GestureDetector(
                onTap: () {
                  setState(() => _selected = i);
                  if (i == 0) {
                    Navigator.pushReplacementNamed(context, Routes.category);
                  } else {
                    // Land directly on that category's products list,
                    // not the shop browser.
                    UellowRouter.goCategory(context, realCats[i - 1].id);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(
                      color: _selected == i ? UellowColors.yellow : Colors.transparent,
                      width: 2.5,
                    )),
                  ),
                  alignment: Alignment.center,
                  child: Text(label, style: TextStyle(
                    color: _selected == i ? UellowColors.ink : UellowColors.muted,
                    fontWeight: _selected == i ? FontWeight.w800 : FontWeight.w600,
                    fontSize: 12.5,
                  )),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// ─── Hero slider — auto-rotating, no title overlay, pattern bg ─────

class _HeroSlider extends StatefulWidget {
  const _HeroSlider({required this.sliders});
  final List<UellowSlider> sliders;
  @override
  State<_HeroSlider> createState() => _HeroSliderState();
}

class _HeroSliderState extends State<_HeroSlider> {
  final _ctrl = PageController(viewportFraction: 1);
  int _page = 0;
  Timer? _t;
  // 5s default; will be settings-driven later
  static const _kAutoSec = 5;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: _kAutoSec), (_) {
      if (!mounted || !_ctrl.hasClients) return;
      final n = _items.length;
      if (n <= 1) return;
      _ctrl.animateToPage((_page + 1) % n,
          duration: const Duration(milliseconds: 380), curve: Curves.easeInOut);
    });
  }

  @override
  void dispose() { _t?.cancel(); _ctrl.dispose(); super.dispose(); }

  List<Widget> get _items => widget.sliders.isEmpty
      ? const [_DemoSlide()]
      : widget.sliders.map((s) => _RealSlide(s: s)).toList();

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 170,
          child: Stack(children: [
            PageView.builder(
              controller: _ctrl,
              itemCount: items.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (_, i) => items[i],
            ),
            if (items.length > 1) Positioned(
              left: 0, right: 0, bottom: 10,
              child: Center(child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.32),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children:
                    List.generate(items.length, (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: i == _page ? 16 : 5, height: 5,
                      margin: const EdgeInsets.symmetric(horizontal: 2.5),
                      decoration: BoxDecoration(
                        color: i == _page ? Colors.white
                                          : const Color(0x66FFFFFF),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    )),
                ),
              )),
            ),
          ]),
        ),
      ),
    );
  }
}

class _RealSlide extends StatelessWidget {
  const _RealSlide({required this.s});
  final UellowSlider s;
  @override
  Widget build(BuildContext context) {
    // No title overlay — keep the slide image clean and impactful.
    return GestureDetector(
      onTap: () => _runAction(context, s.actionType, s.actionValue),
      child: CachedNetworkImage(
        imageUrl: s.imageUrl, fit: BoxFit.cover,
        errorWidget: (_, __, ___) => const _DemoSlide(),
      ),
    );
  }
}

/// Run a (action_type, action_value) action from a slider / icon /
/// section "view more" CTA.
void _runAction(BuildContext context, String type, dynamic value) {
  switch (type) {
    case 'product':
      final id = value is int ? value : int.tryParse('$value');
      if (id != null) UellowRouter.goProduct(context, id);
      break;
    case 'category':
      final id = value is int ? value : int.tryParse('$value');
      if (id != null) UellowRouter.goCollection(context, id);
      break;
    case 'search':
      final q = value?.toString() ?? '';
      if (q.isNotEmpty) UellowRouter.goSearchResults(context, q);
      break;
    case 'screen':
      // v2.1.0 — block CTAs (slider/icon/section "view more") configured to
      // open an app screen were silently dropped. Map known screen tokens to
      // their routes, consistent with the bottom-nav target map.
      const screens = {
        'home': Routes.home, 'shop': Routes.category, 'categories': Routes.category,
        'wishlist': Routes.wishlist, 'cart': Routes.cart, 'account': Routes.account,
        'beena': Routes.beena, 'orders': Routes.orders, 'loyalty': Routes.loyalty,
        'wallet': Routes.wallet, 'coupons': Routes.coupons, 'search': Routes.search,
        'notifications': Routes.notifications, 'flash': Routes.flash,
        'free-shipping': Routes.freeShipping, 'reels': Routes.reels,
        'delivery-coverage': Routes.deliveryCoverage,
      };
      final r = screens[value?.toString() ?? ''];
      if (r != null) Navigator.of(context).pushNamed(r);
      break;
    case 'url':
      // Pass to launchUrl when url_launcher is wired; for now just
      // surface the deep link so the user can confirm something happened.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(UellowApi.instance.lang.toLowerCase().startsWith('ar')
            ? 'جارٍ الفتح: $value' : 'Opening: $value'),
        duration: const Duration(seconds: 1),
      ));
      break;
    case 'none':
    default:
      break;
  }
}

class _DemoSlide extends StatelessWidget {
  const _DemoSlide();
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [UellowColors.darkBrown, Color(0xFF6E3D05)]),
      ),
      padding: const EdgeInsets.all(18),
      alignment: Alignment.bottomLeft,
      child: Text(UellowApi.instance.lang.toLowerCase().startsWith('ar')
          ? 'تخفيضات كبيرة — حتى ٧٠٪' : 'Big Sale — Up to 70% off',
          style: const TextStyle(color: UellowColors.yellowLight,
              fontSize: 18, fontWeight: FontWeight.w800)),
    );
  }
}

// ─── Features chips ────────────────────────────────────────────────

class _FeaturesChips extends StatelessWidget {
  const _FeaturesChips();
  static const _features = [
    (Icons.local_shipping_outlined, 'Free delivery KD 10+', 'توصيل مجاني فوق ١٠ د.ك'),
    (Icons.bolt_outlined,           'Same-day delivery',    'توصيل في نفس اليوم'),
    (Icons.replay_outlined,         '30-day returns',        'إرجاع خلال ٣٠ يوم'),
    (Icons.shield_outlined,         'Original products',     'منتجات أصلية'),
  ];
  @override
  Widget build(BuildContext context) {
    final lang = UellowApi.instance.lang;
    return SizedBox(
      height: 28,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: _features.length,
        separatorBuilder: (_, __) => const SizedBox(width: 5),
        itemBuilder: (_, i) {
          final (icon, en, ar) = _features[i];
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFE8E8E8), width: 1),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 16, height: 16, alignment: Alignment.center,
                decoration: const BoxDecoration(
                    color: UellowColors.yellowSoft, shape: BoxShape.circle),
                child: Icon(icon, size: 10, color: UellowColors.darkBrown),
              ),
              const SizedBox(width: 6),
              Text(lang == 'ar' ? ar : en, style: const TextStyle(
                color: UellowColors.ink, fontWeight: FontWeight.w700, fontSize: 10.5,
              )),
            ]),
          );
        },
      ),
    );
  }
}

// ─── Category icons row ────────────────────────────────────────────

class _CategoryIcons extends StatelessWidget {
  const _CategoryIcons({required this.icons});
  final List<UellowCategoryIcon> icons;
  @override
  Widget build(BuildContext context) {
    final lang = UellowApi.instance.lang;
    final list = icons.isEmpty
        ? const [
            ('📱','Phones'),('💻','Laptops'),('👗','Fashion'),('🏠','Home'),
            ('👶','Baby'),('🎮','Gaming'),('💄','Beauty'),('⚽','Sports'),
          ]
        : icons.map((ic) => (ic.iconUrl, ic.label.current(lang))).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 2),
      child: SizedBox(
        height: 86,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(width: 14),
          itemBuilder: (_, i) {
            final item = list[i];
            final isEmoji = item.$1.length <= 4;
            // Real icons can carry an action; emoji fallback opens shop
            final original = (!isEmoji && i < icons.length) ? icons[i] : null;
            return GestureDetector(
              onTap: () {
                if (original != null) {
                  _runAction(context, original.actionType, original.actionValue);
                } else {
                  Navigator.pushNamed(context, '/category');
                }
              },
              child: SizedBox(
                width: 64,
                child: Column(children: [
                  Container(
                    width: 60, height: 60,
                    decoration: BoxDecoration(
                      color: isEmoji ? UellowColors.yellowSoft : Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      image: isEmoji ? null : DecorationImage(
                        image: CachedNetworkImageProvider(item.$1), fit: BoxFit.cover,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: isEmoji ? Text(item.$1,
                        style: const TextStyle(fontSize: 26)) : null,
                  ),
                  const SizedBox(height: 6),
                  Text(item.$2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11, color: UellowColors.ink, fontWeight: FontWeight.w600,
                      )),
                ]),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─── Feature banners rail (admin-curated info strip) ───────────────

class _FeatureBannersRail extends StatelessWidget {
  const _FeatureBannersRail({required this.banners});
  final List<UellowFeatureBanner> banners;
  // Just an accent palette for the round icon backdrop — the card
  // itself is white so the home page stays clean (no yellow halo).
  static const _accents = [
    Color(0xFFF5C320),  // brand yellow
    Color(0xFFEF4444),  // red
    Color(0xFF10B981),  // green
    Color(0xFF0EA5E9),  // blue
    Color(0xFF8B5CF6),  // purple
    Color(0xFFF59E0B),  // orange
  ];
  @override
  Widget build(BuildContext context) {
    final lang = UellowApi.instance.lang;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: SizedBox(
        height: 78,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          itemCount: banners.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final b = banners[i];
            final accent = _parseHex(b.backgroundColor)
                ?? _parseHex(b.textColor)
                ?? _accents[i % _accents.length];
            return Container(
              width: 220,
              padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: UellowColors.border, width: 1),
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [BoxShadow(
                    color: Color(0x10000000), blurRadius: 4, offset: Offset(0, 2))],
              ),
              child: Row(children: [
                // Icon — colored circle with emoji or backend image
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: (b.iconType == 'image'
                          && b.iconUrl != null && b.iconUrl!.isNotEmpty)
                      ? ClipOval(child: CachedNetworkImage(imageUrl: b.iconUrl!,
                          width: 36, height: 36, fit: BoxFit.cover,
                          errorWidget: (_,__,___) => Text(b.iconEmoji.isEmpty ? '✨' : b.iconEmoji,
                              style: const TextStyle(fontSize: 20))))
                      : Text(b.iconEmoji.isEmpty ? '✨' : b.iconEmoji,
                          style: const TextStyle(fontSize: 20)),
                ),
                const SizedBox(width: 10),
                Expanded(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(b.title.current(lang),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: UellowColors.ink,
                            fontSize: 12.5, fontWeight: FontWeight.w900,
                            height: 1.15)),
                    if (b.subtitle.current(lang).isNotEmpty) Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(b.subtitle.current(lang),
                          maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: UellowColors.muted,
                              fontSize: 10.5, height: 1.25)),
                    ),
                ])),
              ]),
            );
          },
        ),
      ),
    );
  }

  static Color? _parseHex(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    var s = hex.trim();
    if (s.startsWith('#')) s = s.substring(1);
    if (s.length == 6) s = 'FF$s';
    if (s.length != 8) return null;
    return Color(int.tryParse(s, radix: 16) ?? 0);
  }
}

// ─── Product rail (horizontal section of cards) ────────────────────

class _ProductRail extends StatefulWidget {
  const _ProductRail({required this.section});
  final UellowSection section;
  @override
  State<_ProductRail> createState() => _ProductRailState();
}

class _ProductRailState extends State<_ProductRail> {
  late Future<List<UellowProductCard>> _future;
  @override
  void initState() {
    super.initState();
    _future = UellowApi.instance.products.bySection(widget.section.id);
  }

  String _subFor(UellowSection s) {
    final ar = UellowApi.instance.lang == 'ar';
    switch (s.sectionType) {
      case 'flash':       return ar ? 'عروض محدودة الوقت' : 'Limited-time deals';
      case 'newest':      return ar ? 'وصل حديثاً'        : 'Fresh arrivals';
      case 'top_selling': return ar ? 'الأكثر مبيعاً'      : 'Best sellers right now';
      case 'recommended': return ar ? 'مختار لك خصيصاً'    : 'Picked for you';
      case 'brand':       return ar ? 'علامة تجارية رسمية' : 'Official brand showcase';
      default:            return ar ? 'تشكيلة مختارة'      : 'Curated selection';
    }
  }
  @override
  Widget build(BuildContext context) {
    final lang = UellowApi.instance.lang;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 2, 10, 0),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.section.title.current(lang), style: UT.h2),
              const SizedBox(height: 2),
              Text(_subFor(widget.section), style: UT.subtitle),
            ])),
            if (widget.section.showViewMore) GestureDetector(
              onTap: () => Navigator.pushNamed(context, Routes.category),
              child: Text(UellowApi.instance.lang == 'ar' ? 'عرض الكل  ←' : 'See all  →',
                  style: const TextStyle(color: UellowColors.text,
                      fontWeight: FontWeight.w700, fontSize: 12)),
            ),
          ]),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 270,
          child: FutureBuilder<List<UellowProductCard>>(
            future: _future,
            builder: (_, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError || (snap.data?.isEmpty ?? true)) {
                return Center(child: Text(
                    UellowApi.instance.lang.toLowerCase().startsWith('ar')
                        ? 'لا توجد منتجات' : 'No products', style: UT.small));
              }
              final items = snap.data!;
              return ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) =>
                  SizedBox(width: 150, child: ProductCard(product: items[i])),
              );
            },
          ),
        ),
      ]),
    );
  }
}

// ─── Bottom nav (visible on all logged-in screens) ─────────────────

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.active});
  final int active;
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: UellowColors.border, width: .5)),
      ),
      padding: const EdgeInsets.only(top: 6, bottom: 8),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Row(children: [
            _NavTab(icon: Icons.home_filled, label: 'Home', on: active == 0),
            _NavTab(icon: Icons.grid_view, label: 'Shop', on: active == 1),
            _BeenaTab(),
            _NavTab(icon: Icons.shopping_cart_outlined, label: 'Cart', badge: 2, on: active == 3),
            _NavTab(icon: Icons.person_outline, label: 'Account', on: active == 4),
          ]),
        ),
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  const _NavTab({required this.icon, required this.label, this.badge, this.on = false});
  final IconData icon;
  final String label;
  final int? badge;
  final bool on;
  @override
  Widget build(BuildContext context) {
    final col = on ? UellowColors.darkBrown : const Color(0xFF9D8A60);
    return Expanded(
      child: Stack(alignment: Alignment.center, children: [
        Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 22, color: col),
          const SizedBox(height: 3),
          Text(label,
              style: TextStyle(fontSize: 10.5, color: col, fontWeight: FontWeight.w600)),
        ]),
        if (badge != null) Positioned(
          top: 6, right: 28,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: UellowColors.danger,
              borderRadius: BorderRadius.circular(9),
            ),
            constraints: const BoxConstraints(minWidth: 18),
            child: Text('$badge', textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white,
                    fontSize: 10, fontWeight: FontWeight.w800)),
          ),
        ),
      ]),
    );
  }
}

class _BeenaTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 44, height: 44,
          margin: const EdgeInsets.only(top: -16),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              center: Alignment(-0.4, -0.5),
              colors: [Color(0xFFFFE45E), UellowColors.yellow, Color(0xFFC99000)],
            ),
            boxShadow: [BoxShadow(
              color: Color(0xA6F5C320), blurRadius: 18, offset: Offset(0, 6),
            )],
          ),
          alignment: Alignment.center,
          child: const Text('✨', style: TextStyle(fontSize: 20)),
        ),
        const SizedBox(height: 4),
        const Text('Beena',
            style: TextStyle(color: UellowColors.darkBrown,
                fontWeight: FontWeight.w800, fontSize: 10.5)),
      ]),
    );
  }
}

// ─── Loading + Error states ────────────────────────────────────────

class _LoadingState extends StatelessWidget {
  const _LoadingState();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(color: UellowColors.darkBrown),
    );
  }
}

class _ErrorState extends StatelessWidget {
  // v2.1.66 — friendly "app is being updated" pane (animated icon +
  // retry) instead of the raw connection-error text.
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    return ListView(children: [
      const SizedBox(height: 70),
      SizedBox(height: 380, child: UpdatingPane(onRetry: onRetry)),
    ]);
  }
}

// ─── Explore More — random infinite-load grid ──────────────────────
//
// Server-friendly: each call asks for /products/explore?seed=…&page=N.
// The server returns a stable random permutation for that seed so paging
// is idempotent and cache-friendly. Auto-loads three batches as the user
// scrolls; after that, requires tapping "Load more" so we don't drain
// the user's data on accidental long scrolls.

class _ExploreMoreSliver extends StatefulWidget {
  const _ExploreMoreSliver();
  @override
  State<_ExploreMoreSliver> createState() => _ExploreMoreSliverState();
}

class _ExploreMoreSliverState extends State<_ExploreMoreSliver> {
  // Pseudo-random seed picked once per session.
  late final int _seed;
  final List<UellowProductCard> _items = [];
  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;
  int _autoRounds = 0;
  static const int _kAutoLimit = 3;

  @override
  void initState() {
    super.initState();
    // Seed seeded by current millis but kept stable for this widget's
    // lifetime so scrolling doesn't reshuffle existing items.
    _seed = DateTime.now().microsecondsSinceEpoch & 0x7FFFFFFF;
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final page = await UellowApi.instance.products.explore(
          seed: _seed, page: _page, perPage: 12);
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
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
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(10, 18, 10, 10),
      sliver: SliverMainAxisGroup(slivers: [
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 0, 6, 12),
          child: Builder(builder: (_) {
            final ar = UellowApi.instance.lang.toLowerCase().startsWith('ar');
            return Row(children: [
              const Icon(Icons.explore_outlined, size: 18, color: UellowColors.darkBrown),
              const SizedBox(width: 6),
              Text(ar ? 'اكتشف المزيد' : 'Explore More', style: UT.h2),
              const SizedBox(width: 8),
              Text(ar ? 'لك' : 'for you', style: const TextStyle(
                  color: UellowColors.muted, fontSize: 12)),
            ]);
          }),
        )),
        SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2, crossAxisSpacing: 8, mainAxisSpacing: 8,
            childAspectRatio: 0.585,
          ),
          delegate: SliverChildBuilderDelegate(
            (_, i) {
              // Lazy-prefetch trigger: when the user reaches the second-to-
              // last visible row in the auto-load window, request more.
              if (_autoRounds < _kAutoLimit
                  && _hasMore && !_loading
                  && i >= _items.length - 4) {
                WidgetsBinding.instance.addPostFrameCallback((_) => _loadMore());
              }
              return ProductCard(rich: true, product: _items[i]);
            },
            childCount: _items.length,
          ),
        ),
        if (_loading) const SliverToBoxAdapter(child: Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator(
              color: UellowColors.darkBrown, strokeWidth: 2.5)),
        )),
        if (!_loading && _hasMore && _autoRounds >= _kAutoLimit)
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(40, 14, 40, 10),
            child: ElevatedButton.icon(
              onPressed: _loadMore,
              icon: const Icon(Icons.arrow_downward, size: 16),
              label: Text(UellowApi.instance.lang.toLowerCase().startsWith('ar')
                  ? 'تحميل المزيد' : 'Load more',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              style: ElevatedButton.styleFrom(
                backgroundColor: UellowColors.yellowSoft,
                foregroundColor: UellowColors.darkBrown, elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          )),
        if (!_hasMore && _items.isNotEmpty) const SliverToBoxAdapter(
          child: Padding(padding: EdgeInsets.all(20),
              child: Center(child: Text('—  end of feed  —',
                  style: TextStyle(color: UellowColors.muted)))),
        ),
      ]),
    );
  }
}
