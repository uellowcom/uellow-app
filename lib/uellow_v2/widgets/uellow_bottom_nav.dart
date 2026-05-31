// =============================================================================
// UellowBottomNav — shared bottom tab bar wired to Navigator. Pushes the
// target route as a replacement so the back stack stays clean. Cart badge
// is pulled live from /api/mobile/v2/cart on every mount so it always
// matches what's in the user's cart.
// =============================================================================
import 'package:flutter/material.dart';

import '../../api/uellow_api.dart';
import '../router/uellow_router.dart';
import '../theme/uellow_l10n.dart';
import '../theme/uellow_theme.dart';

enum UNavTab { home, shop, beena, cart, account }

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

  void _goto(BuildContext context, UNavTab tab) {
    if (tab == widget.active) return;
    String route;
    switch (tab) {
      case UNavTab.home:    route = Routes.home; break;
      case UNavTab.shop:    route = Routes.category; break;
      case UNavTab.beena:   route = Routes.beena; break;
      case UNavTab.cart:    route = Routes.cart; break;
      case UNavTab.account: route = Routes.account; break;
    }
    Navigator.of(context).pushReplacementNamed(route);
  }

  @override
  Widget build(BuildContext context) {
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
            _beenaTab(context),
            _tab(context, UNavTab.cart,    Icons.shopping_cart_outlined,  T.t('nav.cart'), badge: badge),
            _tab(context, UNavTab.account, Icons.person_outline,          T.t('nav.account')),
          ]),
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
          Icon(icon, size: 22, color: col),
          const SizedBox(height: 3),
          Text(label, style: TextStyle(
              fontSize: 10.5, color: col, fontWeight: FontWeight.w600)),
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
