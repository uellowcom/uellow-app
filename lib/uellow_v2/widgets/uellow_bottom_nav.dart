// =============================================================================
// UellowBottomNav — shared bottom tab bar wired to Navigator. Pushes the
// target route as a replacement so the back stack stays clean. Cart badge
// is pulled live from /api/mobile/v2/cart on every mount so it always
// matches what's in the user's cart.
//
// When the admin has configured a custom nav bar via the visual builder,
// `NavBarCache` loads it from /api/mobile/v2/navbar at app start and this
// widget renders those items instead of the hardcoded fallback. The user
// can add/reorder tabs in the builder and the change is live on the next
// app launch (or after a manual refresh).
// =============================================================================
import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../api/uellow_api.dart';
import '../router/uellow_router.dart';
import 'announcement_strip.dart';
import 'review_requests_strip.dart';
import '../screens/dynamic_page_screen.dart';
import '../theme/uellow_l10n.dart';
import '../theme/uellow_theme.dart';

// v2.0.39 — Render either an emoji or an uploaded PNG/SVG icon.
// The admin can paste any emoji OR upload a custom image; we detect by
// looking at the leading characters of the icon string.
Widget _renderNavIcon(String raw, {required Color color, double size = 22}) {
  if (raw.isEmpty) return Icon(Icons.circle_outlined, size: size, color: color);
  if (raw.startsWith('http') || raw.startsWith('/web/')) {
    final isSvg = raw.toLowerCase().contains('.svg') || raw.toLowerCase().contains('svg+xml');
    if (isSvg) {
      return SvgPicture.network(
        raw, width: size, height: size, fit: BoxFit.contain,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
        placeholderBuilder: (_) => SizedBox(width: size, height: size),
      );
    }
    return CachedNetworkImage(
      imageUrl: raw, width: size, height: size, fit: BoxFit.contain,
      color: color,            // tint PNG/JPG to the active/inactive color
      colorBlendMode: BlendMode.srcIn,
      placeholder: (_, __) => SizedBox(width: size, height: size),
      errorWidget: (_, __, ___) => Icon(Icons.broken_image_outlined, size: size, color: color),
    );
  }
  return Text(raw, style: TextStyle(fontSize: size * 0.95, color: color, height: 1));
}

// v2.0.85 — Reels added as a tab. Sits between beena and cart so the
// thumb-reach order is: home · shop · reels · cart · account · beena.
enum UNavTab { home, shop, reels, beena, cart, account }

// ── Dynamic nav bar items loaded from the admin's design ─────────────────

class DynNavItem {
  DynNavItem({
    required this.id, required this.icon,
    required this.labelEn, required this.labelAr,
    required this.targetType, required this.targetValue, required this.badge,
  });
  final String id;
  final String icon;       // emoji or material name; emojis stay raw
  // v2.1.61 — labels were resolved at FETCH time, so switching the app
  // language left the nav bar in the old language until restart. Keep
  // BOTH and resolve at render time instead.
  final String labelEn;
  final String labelAr;
  String get label {
    final ar = UellowApi.instance.lang.toLowerCase().startsWith('ar');
    final preferred = ar ? labelAr : labelEn;
    return preferred.isNotEmpty
        ? preferred
        : (labelEn.isNotEmpty ? labelEn : labelAr);
  }
  final String targetType; // 'page' | 'screen' | 'url' | 'product' | 'category'
  final String targetValue;
  final String? badge;     // 'cart_count' | 'wishlist_count' | 'notifications' | null

  factory DynNavItem.fromJson(Map j) {
    final lbl = j['label'];
    String en = '', arL = '';
    if (lbl is String) {
      en = lbl; arL = lbl;
    } else if (lbl is Map) {
      final m = lbl.cast<String, dynamic>();
      en = (m['en'] ?? '').toString();
      arL = (m['ar'] ?? '').toString();
    }
    final tgt = (j['target'] as Map?) ?? const {};
    return DynNavItem(
      id:           j['id']?.toString() ?? '',
      icon:         j['icon']?.toString() ?? '🔘',
      labelEn:      en,
      labelAr:      arL,
      targetType:   tgt['type']?.toString() ?? 'screen',
      targetValue:  tgt['value']?.toString() ?? 'home',
      badge:        j['badge']?.toString(),
    );
  }
}

class NavBarCache {
  NavBarCache._() {
    // v2.1.66 — SNAPSHOT-FIRST: the last good nav design renders from
    // disk instantly, so the old hardcoded tabs never flash on slow
    // starts (the same fix the home page got in v2.1.61).
    _loadSnapshot();
    // v2.1.61 — language switch refreshes the nav design + forces every
    // listening nav bar to rebuild (labels resolve per current lang).
    UellowApi.instance.langNotifier.addListener(() {
      final old = List<DynNavItem>.from(items.value);
      refresh();
      // immediate rebuild with the labels we already have
      items.value = old.isEmpty ? items.value : List.of(old);
    });
  }
  static final NavBarCache instance = NavBarCache._();
  final ValueNotifier<List<DynNavItem>> items =
      ValueNotifier<List<DynNavItem>>(const []);
  bool _loaded = false;
  Future<void>? _loading;

  static const _snapKey = 'navbar_cache_v1';

  Future<void> _loadSnapshot() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_snapKey);
      if (raw == null || raw.isEmpty || items.value.isNotEmpty) return;
      final list = (jsonDecode(raw) as List)
          .map((e) => DynNavItem.fromJson((e as Map)))
          .where((it) => it.label.isNotEmpty)
          .toList();
      if (list.isNotEmpty && items.value.isEmpty) items.value = list;
    } catch (_) {}
  }

  Future<void> ensure() {
    if (_loaded) return Future.value();
    return _loading ??= _fetch();
  }
  Future<void> refresh() async {
    _loaded = false; _loading = null;
    await ensure();
  }

  Future<void> _fetch() async {
    try {
      final api = UellowApi.instance;
      final res = await http.get(
        Uri.parse('${api.baseUrl}/api/mobile/v2/navbar'),
        headers: {'Accept': 'application/json', 'X-Lang': api.lang},
      ).timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return;
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      if (j['success'] != true) return;
      final d = (j['data'] as Map).cast<String, dynamic>();
      final raw = (d['items'] as List?) ?? const [];
      final list = raw
          .map((e) => DynNavItem.fromJson((e as Map)))
          .where((it) => it.label.isNotEmpty)
          .toList();
      if (list.isNotEmpty) {
        items.value = list;
        // persist for the next cold start (snapshot-first render)
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_snapKey, jsonEncode(raw));
        } catch (_) {}
      }
    } catch (_) {
      // ignore — snapshot (already rendered) or hardcoded tabs stay
    } finally {
      _loaded = true;
    }
  }
}

class UellowBottomNav extends StatefulWidget {
  const UellowBottomNav({super.key, required this.active, this.cartBadge});
  final UNavTab active;
  /// Optional override — if null, the widget fetches the count itself.
  final int? cartBadge;

  @override
  State<UellowBottomNav> createState() => _UellowBottomNavState();
}

class _UellowBottomNavState extends State<UellowBottomNav> {
  int _count = 0;
  @override
  void initState() {
    super.initState();
    if (widget.cartBadge == null) {
      _count = UellowApi.instance.cart.count.value;
      UellowApi.instance.cart.count.addListener(_syncCount);
      // Background refresh so the badge is accurate on first launch
      UellowApi.instance.cart.get().then((_) {}).catchError((_) {});
    }
    // Kick off (or reuse) the dynamic nav fetch — the build() below
    // re-renders automatically when items load via ValueListenableBuilder.
    NavBarCache.instance.ensure();
  }
  @override
  void dispose() {
    UellowApi.instance.cart.count.removeListener(_syncCount);
    super.dispose();
  }
  void _syncCount() {
    if (!mounted) return;
    setState(() => _count = UellowApi.instance.cart.count.value);
  }

  // Navigate to a dynamic item's target. Page slugs open DynamicPageScreen,
  // built-in screen names map to existing named routes.
  void _gotoDyn(BuildContext context, DynNavItem it) {
    switch (it.targetType) {
      case 'page':
        UellowRouter.goDynPage(context, it.targetValue);
        break;
      case 'screen':
        const map = {
          'home': Routes.home, 'shop': Routes.category,
          'wishlist': Routes.wishlist, 'cart': Routes.cart,
          'account': Routes.account, 'beena': Routes.beena,
          'orders': Routes.orders, 'loyalty': Routes.loyalty,
          'wallet': Routes.wallet, 'coupons': Routes.coupons,
          'notifications': Routes.notifications, 'search': Routes.search,
          // v2.1.0 — these screens existed + had routes but were unreachable
          // from admin-configured 'screen' nav/action targets (the builder
          // offers a free-shipping chip; the tap was silently dropped).
          'free-shipping': Routes.freeShipping, 'reels': Routes.reels,
          'delivery-coverage': Routes.deliveryCoverage,
        };
        final r = map[it.targetValue];
        if (r != null) Navigator.of(context).pushReplacementNamed(r);
        break;
      case 'product':
        final id = int.tryParse(it.targetValue) ?? 0;
        if (id > 0) UellowRouter.goProduct(context, id);
        break;
      case 'category':
        final id = int.tryParse(it.targetValue) ?? 0;
        if (id > 0) UellowRouter.goCollection(context, id);
        break;
    }
  }

  // Map the legacy `active` enum to a target-value so we can highlight the
  // matching dynamic item.
  String _activeValue() {
    switch (widget.active) {
      case UNavTab.home:    return 'home';
      case UNavTab.shop:    return 'shop';
      case UNavTab.reels:   return 'reels';
      case UNavTab.beena:   return 'beena';
      case UNavTab.cart:    return 'cart';
      case UNavTab.account: return 'account';
    }
  }

  void _goto(BuildContext context, UNavTab tab) {
    if (tab == widget.active) return;
    String route;
    switch (tab) {
      case UNavTab.home:    route = Routes.home; break;
      case UNavTab.shop:    route = Routes.category; break;
      case UNavTab.reels:   route = Routes.reels; break;
      case UNavTab.beena:   route = Routes.beena; break;
      case UNavTab.cart:    route = Routes.cart; break;
      case UNavTab.account: route = Routes.account; break;
    }
    Navigator.of(context).pushReplacementNamed(route);
  }

  @override
  // v2.1.66 — admin Announcement Strips render directly ABOVE the nav bar
  // (so they only ever appear on pages that HAVE a nav bar) and stay
  // screen-targeted via the tab → screen mapping.
  String _stripScreen() {
    switch (widget.active) {
      case UNavTab.home:    return 'home';
      case UNavTab.shop:    return 'shop';
      case UNavTab.cart:    return 'cart';
      case UNavTab.account: return 'account';
      case UNavTab.reels:   return 'reels';
      case UNavTab.beena:   return 'beena';
    }
  }

  Widget build(BuildContext context) {
    // v2.1.62 — the specialist-review banner floats ABOVE the nav bar on
    // every page that carries it, until the customer closes it.
    return Column(mainAxisSize: MainAxisSize.min, children: [
      const ReviewReplyBanner(),
      AnnouncementStrip(screen: _stripScreen()),
      ValueListenableBuilder<List<DynNavItem>>(
        valueListenable: NavBarCache.instance.items,
        builder: (_, items, __) {
          if (items.isNotEmpty) return _buildDynamic(context, items);
          return _buildStatic(context);
        },
      ),
    ]);
  }

  Widget _buildStatic(BuildContext context) {
    final badge = widget.cartBadge ?? _count;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: UellowColors.border, width: 0.5)),
      ),
      padding: const EdgeInsets.only(top: 6, bottom: 6),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Row(children: [
            _tab(context, UNavTab.home,    Icons.home_filled,             T.t('nav.home')),
            _tab(context, UNavTab.shop,    Icons.grid_view,               T.t('nav.shop')),
            // v2.0.85 — Reels tab between Shop and Beena
            _tab(context, UNavTab.reels,   Icons.play_circle_filled,
                UellowApi.instance.lang.toLowerCase().startsWith('ar') ? 'فيديو' : 'Reels'),
            _beenaTab(context),
            _tab(context, UNavTab.cart,    Icons.shopping_cart_outlined,  T.t('nav.cart'), badge: badge),
            _tab(context, UNavTab.account, Icons.person_outline,          T.t('nav.account')),
          ]),
        ),
      ),
    );
  }

  Widget _buildDynamic(BuildContext context, List<DynNavItem> items) {
    final cartBadge = widget.cartBadge ?? _count;
    final active = _activeValue();
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: UellowColors.border, width: 0.5)),
      ),
      padding: const EdgeInsets.only(top: 6, bottom: 6),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Row(children: items.map((it) {
            final on = it.targetValue == active;
            int badge = 0;
            if (it.badge == 'cart_count') badge = cartBadge;
            return Expanded(child: InkWell(
              onTap: () => _gotoDyn(context, it),
              child: Stack(alignment: Alignment.center, children: [
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  // v2.1.66 — the ACTIVE tab gets a yellow pill behind its
                  // icon so the current page is unmistakable.
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 3),
                    decoration: on
                        ? BoxDecoration(
                            color: UellowColors.yellow,
                            borderRadius: BorderRadius.circular(14),
                          )
                        : null,
                    child: _renderNavIcon(
                      it.icon,
                      color: on ? UellowColors.darkBrown : const Color(0xFF3F3F3F),
                      size: 22,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(it.label, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 10.5,
                          color: on ? UellowColors.darkBrown : const Color(0xFF3F3F3F),
                          fontWeight: on ? FontWeight.w900 : FontWeight.w600)),
                ]),
                if (badge > 0) Positioned(
                  top: 4, right: 20,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: UellowColors.danger, borderRadius: BorderRadius.circular(9),
                    ),
                    constraints: const BoxConstraints(minWidth: 18),
                    child: Text('$badge', textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white,
                            fontSize: 10, fontWeight: FontWeight.w800)),
                  ),
                ),
              ]),
            ));
          }).toList()),
        ),
      ),
    );
  }

  Widget _tab(BuildContext context, UNavTab tab, IconData icon, String label, {int badge = 0}) {
    final on = tab == widget.active;
    // Active = brand dark brown; inactive = very dark gray for legibility
    final col = on ? UellowColors.darkBrown : const Color(0xFF3F3F3F);
    return Expanded(child: InkWell(
      onTap: () => _goto(context, tab),
      child: Stack(alignment: Alignment.center, children: [
        Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          // v2.1.66 — yellow pill behind the active tab's icon.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
            decoration: on
                ? BoxDecoration(
                    color: UellowColors.yellow,
                    borderRadius: BorderRadius.circular(14),
                  )
                : null,
            child: Icon(icon, size: 22, color: col),
          ),
          const SizedBox(height: 3),
          Text(label, style: TextStyle(
              fontSize: 10.5, color: col,
              fontWeight: on ? FontWeight.w900 : FontWeight.w600)),
        ]),
        if (badge > 0) Positioned(
          top: 6, right: 28,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: UellowColors.danger, borderRadius: BorderRadius.circular(9),
            ),
            constraints: const BoxConstraints(minWidth: 18),
            child: Text('$badge', textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white,
                    fontSize: 10, fontWeight: FontWeight.w800)),
          ),
        ),
      ]),
    ));
  }

  Widget _beenaTab(BuildContext context) {
    return Expanded(child: InkWell(
      onTap: () => _goto(context, UNavTab.beena),
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
        Text(T.t('nav.beena'),
            style: const TextStyle(color: Color(0xFF3F3F3F),
                fontWeight: FontWeight.w800, fontSize: 10.5)),
      ]),
    ));
  }
}
