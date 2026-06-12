// =============================================================================
// DeepLinkService — captures cold-start + warm app_links events and routes
// uellow.com/* (and uellow:// scheme) URIs to the right in-app screen.
//
// Supported patterns:
//   https://uellow.com/product/<slug>-<id>   → ProductScreen(id)
//   https://uellow.com/category/<id>         → CollectionScreen(category_id)
//   https://uellow.com/my/orders/<id>        → OrderScreen(id)
//   https://uellow.com/coupons               → CouponsScreen
//   https://uellow.com/brand/<id>            → CollectionScreen(brand_value_id)
//   uellow://product/123                     → ProductScreen(123)
// Anything else falls back to the home screen (with the URL silently
// dropped so the user isn't left on a blank screen).
// =============================================================================
import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import '../router/uellow_router.dart';

class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService instance = DeepLinkService._();

  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;
  GlobalKey<NavigatorState>? _navKey;
  bool _initialHandled = false;

  Future<void> attach(GlobalKey<NavigatorState> navKey) async {
    _navKey = navKey;
    // Cold start
    if (!_initialHandled) {
      _initialHandled = true;
      try {
        final initial = await _appLinks.getInitialLink();
        if (initial != null) _route(initial);
      } catch (_) {}
    }
    // Warm: subsequent uri streams
    _sub?.cancel();
    _sub = _appLinks.uriLinkStream.listen(_route, onError: (_) {});
  }

  void dispose() { _sub?.cancel(); _sub = null; }

  void _route(Uri uri) {
    final nav = _navKey?.currentState;
    if (nav == null) return;
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    // For custom schemes (uellow://shop/slug-123) the first token lands in the
    // URI *host*, not pathSegments. Fold it back in so https and scheme links
    // route through the exact same rules.
    if (uri.scheme != 'http' && uri.scheme != 'https' &&
        (uri.host).isNotEmpty) {
      segs.insert(0, uri.host);
    }
    if (segs.isEmpty) {
      nav.pushNamedAndRemoveUntil(Routes.home, (r) => false);
      return;
    }
    // Odoo eCommerce categories: /shop/category/<slug>-<id>
    // (checked BEFORE the product rule so a category isn't mistaken for a
    // product by its trailing id).
    if (segs.length >= 3 && segs[0] == 'shop' && segs[1] == 'category') {
      final id = _trailingId(segs[2]);
      if (id != null) {
        nav.pushNamed(Routes.collection, arguments: {'category_id': id});
        return;
      }
    }
    // Product URLs:
    //   /product/<slug>-<id>            (custom / uellow:// scheme)
    //   /shop/product/<slug>-<id>       (legacy)
    //   /shop/<slug>-<id>               (Odoo 18 website_sale default) ← live
    // The last form collides with non-product /shop/* pages (cart, wishlist,
    // checkout…), so guard with a reserved-word skip list.
    const shopReserved = {
      'cart', 'wishlist', 'checkout', 'address', 'payment', 'confirmation',
      'category', 'product', 'compare', 'pricelist', 'extra_info',
    };
    int? productId;
    if (segs[0] == 'product' && segs.length >= 2) {
      productId = _trailingId(segs[1]);
    } else if (segs[0] == 'shop' && segs.length >= 3 && segs[1] == 'product') {
      productId = _trailingId(segs[2]);
    } else if (segs[0] == 'shop' && segs.length == 2 &&
        !shopReserved.contains(segs[1])) {
      productId = _trailingId(segs[1]);
    }
    if (productId != null) {
      nav.pushNamed(Routes.product, arguments: {'id': productId});
      return;
    }
    // /category/<id>  (custom short form)
    if (segs.length >= 2 && segs[0] == 'category') {
      final id = _trailingId(segs[1]);
      if (id != null) {
        nav.pushNamed(Routes.collection, arguments: {'category_id': id});
        return;
      }
    }
    // /my/orders/<id>
    if (segs.length >= 3 && segs[0] == 'my' && segs[1] == 'orders') {
      final id = int.tryParse(segs[2]);
      if (id != null) {
        nav.pushNamed(Routes.order, arguments: {'id': id});
        return;
      }
    }
    if (segs.length == 2 && segs[0] == 'my' && segs[1] == 'orders') {
      nav.pushNamed(Routes.orders);
      return;
    }
    // /coupons
    if (segs[0] == 'coupons') {
      nav.pushNamed(Routes.coupons);
      return;
    }
    // /brand/<id>
    if (segs.length >= 2 && segs[0] == 'brand') {
      final id = _trailingId(segs[1]);
      if (id != null) {
        nav.pushNamed(Routes.collection, arguments: {
          'brand_value_id': id, 'brand_name': segs[1]});
        return;
      }
    }
    // bare /shop (no product/category) → home
    if (segs[0] == 'shop') {
      nav.pushNamedAndRemoveUntil(Routes.home, (r) => false);
      return;
    }
    // /flash
    if (segs[0] == 'flash') { nav.pushNamed(Routes.flash); return; }
    // /wishlist
    if (segs[0] == 'wishlist') { nav.pushNamed(Routes.wishlist); return; }
    // /loyalty
    if (segs[0] == 'loyalty') { nav.pushNamed(Routes.loyalty); return; }
    // /app — the public download landing page. A user opening this already HAS
    // the app, and the page redirects to market://, so loading it in a webview
    // dead-ends on an error. Just go home. (Same for the bare site root.)
    if (segs[0] == 'app') {
      nav.pushNamedAndRemoveUntil(Routes.home, (r) => false);
      return;
    }
    // Fallback — open as in-app webview so content links never dead-end.
    // Skip schemes a webview can't render (store/app deep links).
    final url = uri.toString();
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      nav.pushNamed(Routes.webview, arguments: {'url': url, 'title': ''});
    } else {
      nav.pushNamedAndRemoveUntil(Routes.home, (r) => false);
    }
  }

  // Pull the trailing integer out of slugs like "smart-watch-1786".
  int? _trailingId(String segment) {
    final m = RegExp(r'(\d+)$').firstMatch(segment);
    if (m == null) return null;
    return int.tryParse(m.group(1)!);
  }
}
