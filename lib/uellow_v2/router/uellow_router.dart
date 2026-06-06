// =============================================================================
// Centralized routing for all v2 screens. Plain Navigator + named routes —
// no GoRouter dep needed. Push by name or factory: UellowRouter.go(...).
// =============================================================================
import 'package:flutter/material.dart';

import '../screens/splash_screen.dart';
import '../screens/home_screen.dart';
import '../screens/product_screen.dart';
import '../screens/cart_screen.dart';
import '../screens/checkout_screen.dart';
import '../screens/account_screen.dart';
import '../screens/category_screen.dart';
import '../screens/collection_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/addresses_screen.dart';
import '../screens/order_confirmation_screen.dart';
import '../screens/recently_viewed_screen.dart';
import '../screens/webview_screen.dart';
import '../screens/orders_list_screen.dart';
import '../screens/barcode_scan_screen.dart';
import '../screens/search_screen.dart';
import '../screens/auth_screen.dart';
import '../screens/order_screen.dart';
import '../screens/wishlist_screen.dart';
import '../screens/notifications_screen.dart';
import '../screens/affiliate_screen.dart';
import '../screens/compare_screen.dart';
import '../screens/loyalty_screen.dart';
import '../screens/wallet_screen.dart';
import '../screens/coupons_screen.dart';
import '../screens/bestsellers_screen.dart';
import '../screens/brands_screen.dart';
import '../screens/my_reviews_screen.dart';
import '../screens/vendor_screen.dart';
import '../screens/flash_screen.dart';
import '../screens/tryon_screen.dart';
import '../screens/smart_fit_screen.dart';
import '../screens/beena_screen.dart';
import '../screens/helpdesk_screen.dart';
import '../screens/dynamic_page_screen.dart';
import '../screens/reels_screen.dart';
import '../screens/free_shipping_screen.dart';
import '../screens/delivery_coverage_screen.dart';

// Shared route observer so screens (e.g. Reels) can pause heavy work when a
// route is pushed on top of them and resume when it returns.
final RouteObserver<ModalRoute<void>> appRouteObserver =
    RouteObserver<ModalRoute<void>>();

class Routes {
  Routes._();
  static const splash        = '/';
  static const auth          = '/auth';
  static const home          = '/home';
  static const search        = '/search';
  static const category      = '/category';
  static const collection    = '/collection';  // single-category browse
  static const brands        = '/brands';
  static const bestsellers   = '/bestsellers';
  static const myReviews     = '/my-reviews';
  static const flash         = '/flash';
  static const product       = '/product';        // arg: productId (int)
  static const vendor        = '/vendor';         // arg: vendorId (int)
  static const tryOn         = '/tryon';          // arg: productId
  static const smartFit      = '/smart-fit';      // arg: productId (optional)
  static const cart          = '/cart';
  static const checkout      = '/checkout';
  static const order         = '/order';          // arg: orderId
  static const account       = '/account';
  static const loyalty       = '/loyalty';
  static const affiliate     = '/affiliate';     // v2.1.58 partner center
  static const compare       = '/compare';       // v2.1.58 product compare
  static const wallet        = '/wallet';
  static const coupons       = '/coupons';
  static const wishlist      = '/wishlist';
  static const notifications = '/notifications';
  static const beena         = '/beena';
  static const settings      = '/settings';
  static const profile       = '/profile';
  static const addresses     = '/addresses';
  static const orderConfirm  = '/order-confirmation';
  static const webview       = '/webview';
  static const recentlyViewed = '/recently-viewed';
  static const orders        = '/orders';
  static const scan          = '/scan';
  static const helpdesk      = '/helpdesk';
  static const dynPage       = '/dyn-page';   // arg: slug
  static const reels         = '/reels';      // v2.0.83 — vertical video feed
  static const freeShipping  = '/free-shipping'; // v2.0.89
  static const deliveryCoverage = '/delivery-coverage'; // v2.1.1 — Shipping Pro lookup
}

class UellowRouter {
  UellowRouter._();

  /// Routes registered for named navigation. Concrete pages that need
  /// arguments use [generate] below.
  static Map<String, WidgetBuilder> routes = {
    Routes.splash:        (ctx) => const SplashScreen(),
    Routes.auth:          (ctx) => const AuthScreen(),
    Routes.home:          (ctx) => const HomeScreen(),
    Routes.cart:          (ctx) => const CartScreen(),
    Routes.checkout:      (ctx) {
      // Selective checkout: cart passes {'line_ids': [..]} to pay for
      // only the selected lines.
      final args = ModalRoute.of(ctx)?.settings.arguments;
      List<int>? lineIds;
      if (args is Map && args['line_ids'] is List) {
        lineIds = (args['line_ids'] as List)
            .map((e) => e is int ? e : int.tryParse('$e') ?? 0)
            .where((e) => e > 0)
            .toList();
        if (lineIds.isEmpty) lineIds = null;
      }
      return CheckoutScreen(lineIds: lineIds);
    },
    Routes.account:       (ctx) => const AccountScreen(),
    Routes.category:      (ctx) => const CategoryScreen(),
    Routes.search:        (ctx) => const SearchScreen(),
    Routes.wishlist:      (ctx) => const WishlistScreen(),
    Routes.notifications: (ctx) => const NotificationsScreen(),
    Routes.loyalty:       (ctx) => const LoyaltyScreen(),
    Routes.affiliate:     (ctx) => const AffiliateScreen(),
    Routes.compare:       (ctx) => const CompareScreen(),
    Routes.wallet:        (ctx) => const WalletScreen(),
    Routes.coupons:       (ctx) => const CouponsScreen(),
    Routes.brands:        (ctx) => const BrandsScreen(),
    Routes.bestsellers:   (ctx) => const BestsellersScreen(),
    Routes.myReviews:     (ctx) => const MyReviewsScreen(),
    Routes.flash:         (ctx) => const FlashScreen(),
    Routes.beena:         (ctx) => const BeenaScreen(),
    Routes.settings:      (ctx) => const SettingsScreen(),
    Routes.profile:       (ctx) => const ProfileScreen(),
    Routes.addresses:     (ctx) => const AddressesScreen(),
    Routes.scan:          (ctx) {
      final args = ModalRoute.of(ctx)?.settings.arguments;
      final raw = args is Map && args['return_raw'] == true;
      return BarcodeScanScreen(returnRaw: raw);
    },
    Routes.reels:         (ctx) => const ReelsScreen(),
    Routes.freeShipping:  (ctx) => const FreeShippingScreen(),
    Routes.deliveryCoverage: (ctx) => const DeliveryCoverageScreen(),
  };

  /// Handles dynamic routes that take arguments (e.g. /product with id).
  static Route<dynamic>? generate(RouteSettings settings) {
    switch (settings.name) {
      case Routes.product:
        final id = (settings.arguments as Map?)?['id'] as int? ?? 0;
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => ProductScreen(productId: id),
        );
      case Routes.order:
        final id = (settings.arguments as Map?)?['id'] as int? ?? 0;
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => OrderScreen(orderId: id),
        );
      case Routes.vendor:
        final id = (settings.arguments as Map?)?['id'] as int? ?? 0;
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => VendorScreen(vendorId: id),
        );
      case Routes.tryOn:
        final id = (settings.arguments as Map?)?['id'] as int?;
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => TryOnScreen(productId: id),
        );
      case Routes.smartFit:
        final id = (settings.arguments as Map?)?['id'] as int?;
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => SmartFitScreen(productId: id),
        );
      case Routes.collection:
        final args = (settings.arguments as Map?) ?? const {};
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => CollectionScreen(
            categoryId: args['category_id'] as int?,
            searchQuery: args['search'] as String?,
            brandValueId: args['brand_value_id'] as int?,
            brandName: args['brand_name'] as String?,
          ),
        );
      case Routes.orderConfirm:
        final a = (settings.arguments as OrderConfirmationArgs?)
            ?? const OrderConfirmationArgs(success: true);
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => OrderConfirmationScreen(args: a),
        );
      case Routes.recentlyViewed:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const RecentlyViewedScreen(),
        );
      case Routes.webview:
        final args = (settings.arguments as Map?) ?? const {};
        // v2.1.13 — MUST be Route<bool>: checkout awaits pushNamed<bool> for
        // the payment result; an untyped MaterialPageRoute<dynamic> made that
        // cast throw at runtime and the payment webview silently never opened.
        return MaterialPageRoute<bool>(
          settings: settings,
          builder: (_) => WebViewScreen(
            url: (args['url'] as String?) ?? '',
            title: (args['title'] as String?) ?? '',
          ),
        );
      case Routes.orders:
        final args = (settings.arguments as Map?) ?? const {};
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => OrdersListScreen(
            filterState: args['filter'] as String?,
          ),
        );
      case Routes.helpdesk:
        final args = (settings.arguments as Map?) ?? const {};
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => HelpdeskScreen(
            orderRef: args['order_ref'] as String?,
            category: args['category'] as String?,
          ),
        );
      case Routes.dynPage:
        final slug = (settings.arguments as Map?)?['slug'] as String? ?? '';
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => DynamicPageScreen(slug: slug),
        );
    }
    return null;
  }

  static void goDynPage(BuildContext context, String slug) =>
      Navigator.of(context).pushNamed(Routes.dynPage, arguments: {'slug': slug});

  static void goVendor(BuildContext context, int vendorId) =>
      Navigator.of(context).pushNamed(Routes.vendor, arguments: {'id': vendorId});

  static void goTryOn(BuildContext context, {int? productId}) =>
      Navigator.of(context).pushNamed(Routes.tryOn, arguments: {'id': productId});

  /// Convenience helpers — strongly-typed nav wrappers.
  static Future<T?> push<T>(BuildContext context, Widget page) =>
      Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => page));

  static Future<T?> pushNamed<T>(BuildContext context, String name,
          {Object? arguments}) =>
      Navigator.of(context).pushNamed<T>(name, arguments: arguments);

  static void goProduct(BuildContext context, int productId) =>
      Navigator.of(context).pushNamed(Routes.product, arguments: {'id': productId});

  /// Open the SHOP browser (sidebar of all categories).
  static void goShop(BuildContext context) =>
      Navigator.of(context).pushNamed(Routes.category);

  /// Open a dedicated single-category page (subcats + sort + grid).
  static void goCategory(BuildContext context, int categoryId) =>
      Navigator.of(context).pushNamed(Routes.collection,
          arguments: {'category_id': categoryId});

  /// Alias used by the home `_CategoryStrip`.
  static void goCollection(BuildContext context, int categoryId) =>
      Navigator.of(context).pushNamed(Routes.collection,
          arguments: {'category_id': categoryId});

  static void goSearchResults(BuildContext context, String query) =>
      Navigator.of(context).pushNamed(Routes.collection,
          arguments: {'search': query});

  static void goBrand(BuildContext context, int brandValueId, String name) =>
      Navigator.of(context).pushNamed(Routes.collection,
          arguments: {'brand_value_id': brandValueId, 'brand_name': name});
}
