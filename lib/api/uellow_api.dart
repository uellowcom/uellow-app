// =============================================================================
// Uellow Mobile API Client — v2
// =============================================================================
//
// One file, one client, one error path. Replaces the legacy WooCommerce-style
// `base_woo_api.dart` and the dozen `*_api.dart` files in `lib/services/`.
//
// Usage:
//   final api = UellowApi.instance;
//   final user = await api.auth.login('email@x.com', 'pw');
//   final products = await api.products.list(page: 1, perPage: 20);
//   final cart = await api.cart.add(productId: 1786, qty: 1);
//
// Auth:
//   Token is issued by `/auth/login` and stored in flutter_secure_storage.
//   Every subsequent request adds `Authorization: Bearer <token>` automatically.
//   Logout clears it. 401 responses also clear it (kicks user to login).
//
// Errors:
//   Every method throws `UellowApiException` on failure. The exception has
//   `.code` (machine-friendly: AUTH_REQUIRED / NOT_FOUND / VALIDATION / ...)
//   and `.message` (already localized by the server for the active lang).
//
// Bilingual text:
//   Fields like product names come back as `{en: ..., ar: ...}`. Use the
//   helper `.localized(context)` extension on the typed models — never hardcode
//   one language.
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'uellow_endpoints.dart';
import 'uellow_models.dart';
import 'uellow_token_store.dart';

/// Base URL of the Odoo instance hosting the v2 API. Switch with
/// `--dart-define=UELLOW_API_BASE=https://staging.uellow.com` for staging.
const String kUellowApiBase = String.fromEnvironment(
  'UELLOW_API_BASE',
  defaultValue: 'https://www.uellow.com',
);

/// Default request timeout. Network-level only; the server has its own.
const Duration kDefaultTimeout = Duration(seconds: 25);

// =============================================================================
// Exceptions
// =============================================================================

class UellowApiException implements Exception {
  final String code;
  final String message;
  final int statusCode;
  final Map<String, dynamic>? raw;

  const UellowApiException({
    required this.code,
    required this.message,
    required this.statusCode,
    this.raw,
  });

  bool get isAuthError =>
      code == 'AUTH_REQUIRED' || statusCode == 401;
  bool get isNotFound => code == 'NOT_FOUND' || statusCode == 404;
  bool get isNetwork => code == 'NETWORK_ERROR';
  bool get isServer => statusCode >= 500;

  @override
  String toString() => 'UellowApiException($code, $statusCode): $message';
}

// =============================================================================
// Core client
// =============================================================================

class UellowApi {
  UellowApi._({
    required String baseUrl,
    required this.tokenStore,
    required http.Client httpClient,
  })  : _baseUrl = baseUrl,
        _http = httpClient {
    auth          = _AuthApi(this);
    profile       = _ProfileApi(this);
    home          = _HomeApi(this);
    products      = _ProductsApi(this);
    categories    = _CategoriesApi(this);
    vendors       = _VendorsApi(this);
    announcements = _AnnouncementsApi(this);
    affiliate     = _AffiliateApi(this);
    cart          = _CartApi(this);
    orders        = _OrdersApi(this);
    addresses     = _AddressesApi(this);
    wishlist      = _WishlistApi(this);
    search        = _SearchApi(this);
    reviews       = _ReviewsApi(this);
    loyalty       = _LoyaltyApi(this);
    wallet        = _WalletApi(this);
    notifications = _NotificationsApi(this);
    beena         = _BeenaApi(this);
    settings      = _SettingsApi(this);
    shipping      = _ShippingApi(this);
  }

  /// Singleton. Initialize once at app start via [UellowApi.init].
  static late UellowApi instance;

  /// Initialize the singleton. Call this in `main()` before any usage.
  /// The default constructor uses the real HTTP client and the secure
  /// token storage — only override for tests.
  static Future<UellowApi> init({
    String? baseUrl,
    UellowTokenStore? tokenStore,
    http.Client? httpClient,
  }) async {
    final store = tokenStore ?? await UellowTokenStore.create();
    // Prefer persisted base URL (set by country picker) over the
    // compile-time default — keeps the user on their chosen website.
    final saved = await store.readBaseUrl();
    final resolved = (saved != null && saved.isNotEmpty)
        ? saved
        : (baseUrl ?? kUellowApiBase);
    instance = UellowApi._(
      baseUrl: resolved.replaceAll(RegExp(r'/$'), ''),
      tokenStore: store,
      httpClient: httpClient ?? http.Client(),
    );
    return instance;
  }

  String _baseUrl;
  String get baseUrl => _baseUrl;
  final UellowTokenStore tokenStore;
  final http.Client _http;

  /// v2.1.59 — raw GET for endpoints without a typed wrapper yet.
  Future<Map<String, dynamic>> getRaw(String path,
          {Map<String, dynamic>? query, bool auth = false}) =>
      _get(path, query: query, auth: auth);

  /// Raw POST escape hatch (v2.1.62) — same contract as [getRaw].
  Future<Map<String, dynamic>> postRaw(String path,
          {Object? body, bool auth = false}) =>
      _post(path, body: body, auth: auth);

  /// Switch which Odoo website the app talks to. Used when the user
  /// changes country in the picker — every subsequent request goes
  /// against the new domain. Persisted via tokenStore so the choice
  /// survives app restart.
  Future<void> setBaseUrl(String url) async {
    if (url.isEmpty) return;
    var clean = url.trim().replaceAll(RegExp(r'/$'), '');
    if (!clean.startsWith('http')) clean = 'https://$clean';
    _baseUrl = clean;
    await tokenStore.writeBaseUrl(clean);
  }

  /// Active language, two letters ('ar' or 'en'). Reactive — the root
  /// MaterialApp wraps itself in a ValueListenableBuilder over this
  /// notifier so changing the language flips Directionality / Locale
  /// app-wide without a manual restart.
  final ValueNotifier<String> langNotifier = ValueNotifier<String>('en');
  void setLang(String code) {
    final next = code.toLowerCase().startsWith('ar') ? 'ar' : 'en';
    if (langNotifier.value != next) langNotifier.value = next;
  }
  String get lang => langNotifier.value;

  /// Avatar source — either a data: URI (instant) or a cache-busted URL.
  /// Any screen that listens stays in sync the moment the profile photo
  /// is changed, so users don't have to log out / back in to see it.
  final ValueNotifier<String> avatarNotifier = ValueNotifier<String>('');
  void setAvatar(String src) {
    avatarNotifier.value = src;
  }

  /// App version + platform, sent on every request so the server can decide
  /// version gates / log analytics. Set once at startup.
  String _appVersion = '1.0.0';
  String _platform = 'android';
  void setAppMeta({required String appVersion, required String platform}) {
    _appVersion = appVersion;
    _platform = platform;
  }

  // ─── Resource APIs ───────────────────────────────────────────────────
  late final _AuthApi auth;
  late final _ProfileApi profile;
  late final _HomeApi home;
  late final _ProductsApi products;
  late final _CategoriesApi categories;
  late final _VendorsApi vendors;
  late final _AnnouncementsApi announcements;
  late final _AffiliateApi affiliate;
  late final _CartApi cart;
  late final _OrdersApi orders;
  late final _AddressesApi addresses;
  late final _WishlistApi wishlist;
  late final _SearchApi search;
  late final _ReviewsApi reviews;
  late final _LoyaltyApi loyalty;
  late final _WalletApi wallet;
  late final _NotificationsApi notifications;
  late final _BeenaApi beena;
  late final _SettingsApi settings;
  late final _ShippingApi shipping;

  // ─── Auth listener (lets ui react to 401 / logout) ───────────────────

  final _authChangedController = StreamController<UellowUser?>.broadcast();
  Stream<UellowUser?> get onAuthChanged => _authChangedController.stream;
  void _emitAuth(UellowUser? user) => _authChangedController.add(user);

  // ─── Low-level request ───────────────────────────────────────────────

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    bool requireAuth = false,
    Duration timeout = kDefaultTimeout,
  }) async {
    final url = Uri.parse('$baseUrl$path').replace(
      queryParameters: {
        ...?query?.map((k, v) => MapEntry(k, '$v')),
      },
    );

    final headers = <String, String>{
      'Content-Type': 'application/json; charset=utf-8',
      'Accept': 'application/json',
      'X-Lang': langNotifier.value,
      'X-App-Version': _appVersion,
      'X-Platform': _platform,
    };
    final token = await tokenStore.readToken();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    } else if (requireAuth) {
      throw UellowApiException(
        code: 'AUTH_REQUIRED',
        message: lang == 'ar' ? 'يجب تسجيل الدخول.' : 'You must be logged in.',
        statusCode: 401,
      );
    }
    final cartToken = await tokenStore.readCartToken();
    if (cartToken != null && cartToken.isNotEmpty) {
      headers['X-Cart-Token'] = cartToken;
    }
    // v2.1.16 — multi-website: scope every call to the selected website
    // (settings, builder pages, payment methods, carts…).
    final siteId = await tokenStore.readWebsiteId();
    if (siteId != null && siteId > 0) {
      headers['X-Website-Id'] = '$siteId';
    }

    http.Response resp;
    try {
      switch (method) {
        case 'GET':
          resp = await _http.get(url, headers: headers).timeout(timeout);
          break;
        case 'POST':
          resp = await _http
              .post(url,
                  headers: headers,
                  body: body == null ? null : jsonEncode(body))
              .timeout(timeout);
          break;
        case 'PUT':
          resp = await _http
              .put(url,
                  headers: headers,
                  body: body == null ? null : jsonEncode(body))
              .timeout(timeout);
          break;
        case 'DELETE':
          resp = await _http.delete(url, headers: headers).timeout(timeout);
          break;
        default:
          throw UellowApiException(
              code: 'BAD_METHOD',
              message: 'Unsupported HTTP method $method',
              statusCode: 0);
      }
    } on SocketException catch (e) {
      throw UellowApiException(
        code: 'NETWORK_ERROR',
        message: lang == 'ar'
            ? 'لا يوجد اتصال بالإنترنت: ${e.message}'
            : 'No internet connection: ${e.message}',
        statusCode: 0,
      );
    } on TimeoutException {
      // v2.1.59 — friendly, actionable copy instead of the raw
      // "UellowApiException(TIMEOUT)" feel.
      throw UellowApiException(
        code: 'TIMEOUT',
        message: lang == 'ar'
            ? '⏳ الاتصال يأخذ وقتاً أطول من المعتاد — حاول مرة أخرى أو اسحب الشاشة للتحديث'
            : '⏳ Taking longer than usual — please retry or pull to refresh',
        statusCode: 0,
      );
    } on HttpException catch (e) {
      throw UellowApiException(
        code: 'NETWORK_ERROR',
        message: e.message,
        statusCode: 0,
      );
    }

    if (kDebugMode) {
      debugPrint('UellowApi $method ${url.path} → ${resp.statusCode}');
    }

    Map<String, dynamic> json;
    try {
      json = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw UellowApiException(
        code: 'BAD_RESPONSE',
        message: lang == 'ar'
            ? 'استجابة غير صالحة من الخادم (الحالة ${resp.statusCode})'
            : 'Server returned non-JSON (status ${resp.statusCode})',
        statusCode: resp.statusCode,
      );
    }

    // Unified envelope: {success, data, meta, error, code}
    if (json['success'] == true) {
      return json;
    }
    final code = (json['code'] as String?) ?? 'UNKNOWN';
    final msg  = (json['error'] as String?)
        ?? (lang == 'ar' ? 'خطأ غير معروف' : 'Unknown error');

    // 401 → invalidate stored token + emit auth-changed
    if (resp.statusCode == 401 || code == 'AUTH_REQUIRED') {
      await tokenStore.clearToken();
      _emitAuth(null);
    }
    throw UellowApiException(
      code: code,
      message: msg,
      statusCode: resp.statusCode,
      raw: json,
    );
  }

  // Convenience shortcuts
  Future<Map<String, dynamic>> _get(String path,
          {Map<String, dynamic>? query, bool auth = false}) =>
      _request('GET', path, query: query, requireAuth: auth);
  Future<Map<String, dynamic>> _post(String path,
          {Object? body, bool auth = false,
           Duration timeout = kDefaultTimeout}) =>
      _request('POST', path, body: body, requireAuth: auth,
          timeout: timeout);

  /// Raw binary GET (e.g. for the invoice PDF). Uses the same headers
  /// + auth as the JSON helpers but returns bytes verbatim instead of
  /// trying to JSON-decode them.
  Future<List<int>> _getBytes(String path, {bool auth = false}) async {
    final url = Uri.parse('$baseUrl$path');
    final headers = <String, String>{
      'Accept': 'application/pdf, */*',
      'X-Lang': langNotifier.value,
    };
    final token = await tokenStore.readToken();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    } else if (auth) {
      throw UellowApiException(
        code: 'AUTH_REQUIRED',
        message: lang == 'ar' ? 'يجب تسجيل الدخول.' : 'You must be logged in.',
        statusCode: 401);
    }
    final resp = await _http.get(url, headers: headers).timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) {
      throw UellowApiException(
        code: 'BAD_STATUS',
        message: lang == 'ar'
            ? 'أرجع الخادم الحالة ${resp.statusCode}'
            : 'Server returned ${resp.statusCode}',
        statusCode: resp.statusCode);
    }
    return resp.bodyBytes;
  }

  void dispose() {
    _http.close();
    _authChangedController.close();
  }
}

// =============================================================================
// Resource APIs — thin wrappers around _request that produce typed models
// =============================================================================

class _AuthApi {
  _AuthApi(this._c);
  final UellowApi _c;

  Future<UellowAuthResult> login(String email, String password,
      {String? deviceId, String? deviceName, String? pushToken, String? appVersion}) async {
    final res = await _c._post(EP.authLogin, body: {
      'email': email,
      'password': password,
      if (deviceId   != null) 'device_id': deviceId,
      if (deviceName != null) 'device_name': deviceName,
      if (pushToken  != null) 'push_token': pushToken,
      if (appVersion != null) 'app_version': appVersion,
    });
    return _saveAuth(res);
  }

  Future<UellowAuthResult> register({
    required String name,
    required String email,
    required String password,
    String? phone,
    String? deviceId,
    String? pushToken,
  }) async {
    final res = await _c._post(EP.authRegister, body: {
      'name': name, 'email': email, 'password': password,
      if (phone     != null) 'phone': phone,
      if (deviceId  != null) 'device_id': deviceId,
      if (pushToken != null) 'push_token': pushToken,
    });
    return _saveAuth(res);
  }

  // v2.1.23 — Google sign-in: the app gets an id_token from
  // google_sign_in and the server verifies it with Google before
  // issuing our bearer token.
  Future<UellowAuthResult> googleSignIn(String idToken) async {
    final res = await _c._post('/api/mobile/v2/auth/social/google',
        body: {'id_token': idToken});
    return _saveAuth(res);
  }

  // v2.1.16 — email OTP (no SMS provider needed): request a 6-digit
  // code, then verify it. Verify returns the same auth payload as login.
  Future<String> otpEmailRequest(String emailOrPhone) async {
    final res = await _c._post('/api/mobile/v2/auth/otp/email/request',
        body: {'email_or_phone': emailOrPhone});
    return ((res['data'] as Map?)?['to'] ?? '').toString();
  }

  // v2.1.17 — combined channel: email OR phone (SMS). Returns the masked
  // destination; channel is picked server-side from the target's shape.
  Future<String> otpSend(String target) async {
    final res = await _c._post('/api/mobile/v2/auth/otp/send',
        body: {'target': target});
    return ((res['data'] as Map?)?['to'] ?? '').toString();
  }

  Future<UellowAuthResult> otpCheck({
    required String target,
    required String code,
    String? name,
  }) async {
    final res = await _c._post('/api/mobile/v2/auth/otp/check', body: {
      'target': target,
      'code': code,
      if (name != null && name.isNotEmpty) 'name': name,
    });
    return _saveAuth(res);
  }

  Future<UellowAuthResult> otpEmailVerify({
    required String emailOrPhone,
    required String code,
    String? name,
  }) async {
    final res = await _c._post('/api/mobile/v2/auth/otp/email/verify', body: {
      'email_or_phone': emailOrPhone,
      'code': code,
      if (name != null && name.isNotEmpty) 'name': name,
    });
    return _saveAuth(res);
  }

  Future<UellowAuthResult> verifyOtp({
    required String phone,
    required String firebaseUid,
    String? name,
    String? deviceId,
    String? pushToken,
  }) async {
    final res = await _c._post(EP.authOtpVerify, body: {
      'phone': phone, 'firebase_uid': firebaseUid,
      if (name      != null) 'name': name,
      if (deviceId  != null) 'device_id': deviceId,
      if (pushToken != null) 'push_token': pushToken,
    });
    return _saveAuth(res);
  }

  Future<UellowAuthResult> google({
    required String email, required String providerUserId, String? name,
  }) =>
      _social('/api/mobile/v2/auth/social/google', email, providerUserId, name);
  Future<UellowAuthResult> apple({
    required String email, required String providerUserId, String? name,
  }) =>
      _social('/api/mobile/v2/auth/social/apple', email, providerUserId, name);
  Future<UellowAuthResult> facebook({
    required String email, required String providerUserId, String? name,
  }) =>
      _social('/api/mobile/v2/auth/social/facebook', email, providerUserId, name);

  Future<UellowAuthResult> _social(
      String path, String email, String providerUid, String? name) async {
    final res = await _c._post(path, body: {
      'email': email,
      'provider_user_id': providerUid,
      if (name != null) 'name': name,
    });
    return _saveAuth(res);
  }

  Future<bool> forgotPassword(String email) async {
    final res = await _c._post(EP.authForgot, body: {'email': email});
    return res['data']?['sent'] == true;
  }

  Future<void> logout() async {
    try {
      await _c._post(EP.authLogout, auth: true);
    } catch (_) {
      // Even if the server call fails, clear local state.
    }
    await _c.tokenStore.clearToken();
    _c._emitAuth(null);
  }

  Future<UellowUser> me() async {
    final res = await _c._get(EP.authMe, auth: true);
    return UellowUser.fromJson(res['data']['user'] as Map<String, dynamic>);
  }

  Future<UellowAuthResult> _saveAuth(Map<String, dynamic> res) async {
    final data = res['data'] as Map<String, dynamic>;
    final token = data['token'] as String;
    final user = UellowUser.fromJson(data['user'] as Map<String, dynamic>);
    await _c.tokenStore.writeToken(token);
    _c._emitAuth(user);
    return UellowAuthResult(token: token, user: user);
  }
}

class _ProfileApi {
  _ProfileApi(this._c);
  final UellowApi _c;

  Future<UellowUser> update({
    String? name, String? phone, String? email, String? lang,
  }) async {
    final res = await _c._post(EP.profileUpdate, auth: true, body: {
      if (name  != null) 'name': name,
      if (phone != null) 'phone': phone,
      if (email != null) 'email': email,
      if (lang  != null) 'lang': lang,
    });
    return UellowUser.fromJson(res['data']['user'] as Map<String, dynamic>);
  }

  Future<bool> changePassword({
    required String oldPassword, required String newPassword,
  }) async {
    final res = await _c._post(EP.profileChangePassword, auth: true, body: {
      'old_password': oldPassword,
      'new_password': newPassword,
    });
    return res['data']?['changed'] == true;
  }

  Future<void> deleteAccount() async {
    await _c._post(EP.profileDelete, auth: true);
    await _c.tokenStore.clearToken();
    _c._emitAuth(null);
  }
}

class _HomeApi {
  _HomeApi(this._c);
  final UellowApi _c;

  Future<UellowHome> get() async {
    final res = await _c._get(EP.home);
    return UellowHome.fromJson(res['data'] as Map<String, dynamic>);
  }
}

class _ProductsApi {
  _ProductsApi(this._c);
  final UellowApi _c;

  Future<UellowPage<UellowProductCard>> list({
    int page = 1, int perPage = 20,
    int? categoryId, String? search, String sort = 'newest',
    int? brandId, int? tagId, double? minPrice, double? maxPrice,
    bool? onSale,
  }) async {
    final res = await _c._get(EP.products, query: {
      'page': page, 'per_page': perPage, 'sort': sort,
      if (categoryId != null) 'category_id': categoryId,
      if (search     != null) 'search': search,
      if (brandId    != null) 'brand_id': brandId,
      if (tagId      != null) 'tag_id': tagId,
      if (minPrice   != null) 'min_price': minPrice,
      if (maxPrice   != null) 'max_price': maxPrice,
      if (onSale == true) 'on_sale': '1',
    });
    return UellowPage.fromJson(
      res,
      (item) => UellowProductCard.fromJson(item),
    );
  }

  Future<UellowProductFull> detail(int productId) async {
    final res = await _c._get('${EP.products}/$productId');
    return UellowProductFull.fromJson(
        res['data']['product'] as Map<String, dynamic>);
  }

  Future<List<UellowProductVariant>> variants(int productId) async {
    final res = await _c._get('${EP.products}/$productId/variants');
    final list = res['data']['variants'] as List;
    return list.map((e) => UellowProductVariant.fromJson(e)).toList();
  }

  Future<UellowReviewsResult> reviews(int productId,
      {int page = 1, int perPage = 20}) async {
    final res = await _c._get('${EP.products}/$productId/reviews',
        query: {'page': page, 'per_page': perPage});
    return UellowReviewsResult.fromJson(res);
  }

  Future<List<UellowProductCard>> related(int productId) async {
    final res = await _c._get('${EP.products}/$productId/related');
    return (res['data'] as List)
        .map((e) => UellowProductCard.fromJson(e))
        .toList();
  }

  Future<List<UellowProductCard>> topSelling() async {
    final res = await _c._get(EP.productsTopSelling);
    return (res['data'] as List)
        .map((e) => UellowProductCard.fromJson(e))
        .toList();
  }

  Future<List<UellowProductCard>> recommended() async {
    final res = await _c._get(EP.productsRecommended);
    return (res['data'] as List)
        .map((e) => UellowProductCard.fromJson(e))
        .toList();
  }

  Future<List<UellowProductCard>> recentlyViewed() async {
    final res = await _c._get(EP.productsRecentlyViewed);
    return (res['data'] as List)
        .map((e) => UellowProductCard.fromJson(e))
        .toList();
  }

  Future<List<UellowProductCard>> bySection(int sectionId) async {
    final res = await _c._get('${EP.products}/section/$sectionId');
    return (res['data'] as List)
        .map((e) => UellowProductCard.fromJson(e))
        .toList();
  }

  /// Lightweight random-feed for Explore More. Stable per (seed,page).
  Future<UellowPage<UellowProductCard>> explore({
    required int seed, int page = 1, int perPage = 12,
  }) async {
    final res = await _c._get('${EP.products}/explore', query: {
      'seed': seed, 'page': page, 'per_page': perPage,
    });
    return UellowPage.fromJson(res, (item) => UellowProductCard.fromJson(item));
  }
}

// v2.1.58 — Affiliate program (uellow_affiliate module).
class _AffiliateApi {
  _AffiliateApi(this._c);
  final UellowApi _c;

  /// Dashboard. status: none|pending|active|suspended (+ code, tier,
  /// balances, next_tier, links, min_payout when an account exists).
  Future<Map<String, dynamic>> me() async {
    final res = await _c._get('/api/mobile/v2/affiliate/me', auth: true);
    return (res['data'] as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> apply({String? name, String? phone}) async {
    final res = await _c._post('/api/mobile/v2/affiliate/apply', auth: true,
        body: {
          if (name != null) 'name': name,
          if (phone != null) 'phone': phone,
        });
    return (res['data'] as Map).cast<String, dynamic>();
  }

  Future<List<Map<String, dynamic>>> products(
      {String q = '', int page = 1}) async {
    final res = await _c._get('/api/mobile/v2/affiliate/products',
        auth: true, query: {'page': page, if (q.isNotEmpty) 'q': q});
    return List<Map<String, dynamic>>.from(
        (res['data']?['products'] as List?) ?? const []);
  }

  Future<List<Map<String, dynamic>>> orders() async {
    final res =
        await _c._get('/api/mobile/v2/affiliate/orders', auth: true);
    return List<Map<String, dynamic>>.from(
        (res['data']?['orders'] as List?) ?? const []);
  }

  Future<Map<String, dynamic>> submitOrder({
    required String customerName,
    required String customerPhone,
    String area = '', String address = '', String note = '',
    required List<Map<String, dynamic>> lines,
  }) async {
    final res = await _c._post('/api/mobile/v2/affiliate/orders',
        auth: true,
        body: {
          'customer_name': customerName,
          'customer_phone': customerPhone,
          'customer_area': area,
          'customer_address': address,
          'customer_note': note,
          'lines': lines,
        });
    return (res['data'] as Map).cast<String, dynamic>();
  }

  Future<List<Map<String, dynamic>>> commissions() async {
    final res =
        await _c._get('/api/mobile/v2/affiliate/commissions', auth: true);
    return List<Map<String, dynamic>>.from(
        (res['data']?['commissions'] as List?) ?? const []);
  }

  Future<List<Map<String, dynamic>>> payouts() async {
    final res =
        await _c._get('/api/mobile/v2/affiliate/payouts', auth: true);
    return List<Map<String, dynamic>>.from(
        (res['data']?['payouts'] as List?) ?? const []);
  }

  Future<Map<String, dynamic>> requestPayout(
      {required double amount, required String method,
       String details = ''}) async {
    final res = await _c._post('/api/mobile/v2/affiliate/payouts',
        auth: true,
        body: {'amount': amount, 'method': method, 'details': details});
    return (res['data'] as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> leaderboard() async {
    final res =
        await _c._get('/api/mobile/v2/affiliate/leaderboard', auth: true);
    return (res['data'] as Map).cast<String, dynamic>();
  }
}

// v2.1.57 — targeted announcement strips (Mobile App ▸ Marketing).
class _AnnouncementsApi {
  _AnnouncementsApi(this._c);
  final UellowApi _c;

  Future<List<Map<String, dynamic>>> forScreen(String screen) async {
    final res = await _c._get('/api/mobile/v2/announcements',
        query: {'screen': screen});
    return List<Map<String, dynamic>>.from(
        (res['data']?['strips'] as List?) ?? const []);
  }
}

// v2.1.56 — real vendor-store data (was missing; the vendor screen ran
// on hardcoded mock content).
class _VendorsApi {
  _VendorsApi(this._c);
  final UellowApi _c;

  /// Full vendor profile: name{en,ar}, tagline, logo, banner,
  /// brand_color, tier, product_count, order_count, rating{avg,count},
  /// about{en,ar}, sla_hours, categories[{id,name,count}].
  Future<Map<String, dynamic>> detail(int id) async {
    final res = await _c._get('/api/mobile/v2/vendors/$id');
    return (res['data'] as Map).cast<String, dynamic>();
  }

  Future<UellowPage<UellowProductCard>> products(int id,
      {String sort = 'newest', int page = 1, int perPage = 20}) async {
    final res = await _c._get('/api/mobile/v2/vendors/$id/products', query: {
      'sort': sort, 'page': page, 'per_page': perPage,
    });
    return UellowPage.fromJson(res, (e) => UellowProductCard.fromJson(e));
  }
}

class _CategoriesApi {
  _CategoriesApi(this._c);
  final UellowApi _c;

  Future<List<UellowCategory>> list({int? parentId, bool withChildren = false}) async {
    final res = await _c._get(EP.categories, query: {
      if (parentId != null) 'parent_id': parentId,
      'with_children': withChildren ? 'true' : 'false',
    });
    return (res['data'] as List)
        .map((e) => UellowCategory.fromJson(e))
        .toList();
  }

  Future<List<UellowCategory>> tree() async {
    final res = await _c._get(EP.categoriesTree);
    return (res['data'] as List)
        .map((e) => UellowCategory.fromJson(e))
        .toList();
  }

  Future<UellowCategory> detail(int id) async {
    final res = await _c._get('${EP.categories}/$id');
    return UellowCategory.fromJson(
        res['data']['category'] as Map<String, dynamic>);
  }

  /// v2.1.56 — header slides for the shop page slider. Each item:
  /// {image_url, link: {type: product|category|url|none, value}}.
  Future<List<Map<String, dynamic>>> slides(int id) async {
    final res = await _c._get('/api/mobile/v2/category/$id/slides');
    return List<Map<String, dynamic>>.from(
        (res['data']?['slides'] as List?) ?? const []);
  }

  /// v2.1.57 — shop page section toggles + the "For You" hand-picked
  /// categories/brands (Mobile App ▸ Settings).
  Future<Map<String, dynamic>> shopConfig() async {
    final res = await _c._get('/api/mobile/v2/shop/config');
    return (res['data'] as Map).cast<String, dynamic>();
  }

  /// v2.1.57 — top brands: [{value_id, name, image, product_count}].
  Future<List<Map<String, dynamic>>> brands() async {
    final res = await _c._get('/api/mobile/v2/brands');
    return List<Map<String, dynamic>>.from(
        (res['data']?['brands'] as List?) ?? const []);
  }
}

class _CartApi {
  _CartApi(this._c);
  final UellowApi _c;

  /// Live cart line count. Widgets (bottom nav badge, gallery cart icon)
  /// can listen and rebuild instantly when items are added/removed.
  final ValueNotifier<int> count = ValueNotifier(0);

  Future<UellowCart> get() async {
    final res = await _c._get(EP.cart);
    return _save(UellowCart.fromJson(res['data']['cart']));
  }

  Future<UellowCart> add({required int productId, int qty = 1}) async {
    final res = await _c._post(EP.cartAdd,
        body: {'product_id': productId, 'qty': qty});
    return _save(UellowCart.fromJson(res['data']['cart']));
  }

  Future<UellowCart> update({required int lineId, required int qty}) async {
    final res = await _c._post(EP.cartUpdate,
        body: {'line_id': lineId, 'qty': qty});
    return _save(UellowCart.fromJson(res['data']['cart']));
  }

  Future<UellowCart> remove(int lineId) async {
    final res = await _c._post(EP.cartRemove, body: {'line_id': lineId});
    return _save(UellowCart.fromJson(res['data']['cart']));
  }

  Future<UellowCart> clear() async {
    final res = await _c._post(EP.cartClear);
    return _save(UellowCart.fromJson(res['data']['cart']));
  }

  Future<UellowCart> applyCoupon(String code) async {
    final res = await _c._post(EP.cartApplyCoupon, body: {'code': code});
    return _save(UellowCart.fromJson(res['data']['cart']));
  }

  Future<UellowCart> removeCoupon([String? code]) async {
    // v2.1.56 — pass the specific code so only THAT coupon is removed
    // (no code = legacy wipe-all).
    final res = await _c._post(EP.cartRemoveCoupon,
        body: code == null ? null : {'code': code});
    return _save(UellowCart.fromJson(res['data']['cart']));
  }

  /// Returns a shareable URL the user can send to anyone — opens the cart
  /// in browser/app and lets the recipient adopt the items.
  Future<String> share() async {
    final res = await _c._post(EP.cartShare);
    return (res['data']?['url'] as String?) ?? '';
  }

  /// v2.1.66 — full share payload for the QR dialog:
  /// {url, token, serial, serial_display}.
  Future<Map<String, dynamic>> shareDetails() async {
    final res = await _c._post(EP.cartShare);
    return (res['data'] as Map?)?.cast<String, dynamic>() ?? {};
  }

  /// v2.1.66 — adopt a shared cart by QR value / link / typed serial.
  /// Returns (cart, addedCount).
  Future<(UellowCart, int)> importShared(String code) async {
    final res = await _c._post('/api/mobile/v2/cart/import',
        body: {'code': code});
    final cart = UellowCart.fromJson(
        (res['data']?['cart'] as Map).cast<String, dynamic>());
    await _save(cart);
    return (cart, (res['data']?['added'] as num?)?.toInt() ?? 0);
  }

  Future<UellowCart> bulkRemove(List<int> lineIds) async {
    final res = await _c._post(EP.cartBulkRemove, body: {'line_ids': lineIds});
    return _save(UellowCart.fromJson(res['data']['cart']));
  }

  Future<UellowCart> bulkMoveToWishlist(List<int> lineIds) async {
    final res = await _c._post(EP.cartBulkWishlist, body: {'line_ids': lineIds});
    return _save(UellowCart.fromJson(res['data']['cart']));
  }

  Future<UellowCart> _save(UellowCart cart) async {
    if (cart.cartToken.isNotEmpty) {
      await _c.tokenStore.writeCartToken(cart.cartToken);
    }
    count.value = cart.lineCount;
    return cart;
  }
}

class _OrdersApi {
  _OrdersApi(this._c);
  final UellowApi _c;

  Future<UellowPage<UellowOrderSummary>> list({
    int page = 1, int perPage = 20, String? state,
  }) async {
    final res = await _c._get(EP.orders, query: {
      'page': page, 'per_page': perPage,
      if (state != null && state.isNotEmpty) 'state': state,
    }, auth: true);
    return UellowPage.fromJson(
        res, (e) => UellowOrderSummary.fromJson(e));
  }

  // v2.1.42 — customer cancellation: returns 'cancelled' (done) or
  // 'requested' (paid order → awaits admin approval).
  Future<String> cancel(int id, {String? reason}) async {
    final res = await _c._post('${EP.orders}/$id/cancel', body: {
      if (reason != null && reason.isNotEmpty) 'reason': reason,
    }, auth: true);
    return ((res['data'] as Map?)?['result'] ?? '').toString();
  }

  Future<UellowOrderDetail> detail(int id) async {
    final res = await _c._get('${EP.orders}/$id', auth: true);
    return UellowOrderDetail.fromJson(
        res['data']['order'] as Map<String, dynamic>);
  }

  Future<List<UellowShippingMethod>> shippingMethods() async {
    final res = await _c._get(EP.shippingMethods);
    return (res['data'] as List)
        .map((e) => UellowShippingMethod.fromJson(e))
        .toList();
  }

  Future<List<UellowPaymentMethod>> paymentMethods({String? country}) async {
    final res = await _c._get(EP.paymentMethods,
        query: country != null && country.isNotEmpty ? {'country': country} : null);
    return (res['data'] as List)
        .map((e) => UellowPaymentMethod.fromJson(e))
        .toList();
  }

  Future<UellowCheckoutSummary> checkoutSummary() async {
    final res = await _c._get(EP.checkoutSummary, auth: true);
    return UellowCheckoutSummary.fromJson(res['data'] as Map<String, dynamic>);
  }

  /// Fully-qualified URL to the invoice PDF endpoint. The app passes
  /// this to share_plus/url_launcher after fetching the binary, but the
  /// helper also lets the webview screen open it directly.
  String invoiceUrl(int orderId) =>
      '${_c.baseUrl}/api/mobile/v2/orders/$orderId/invoice';

  /// Download invoice bytes (requires auth header) — caller writes to
  /// disk and opens via OpenFile / shares via share_plus.
  Future<List<int>> invoiceBytes(int orderId) async {
    final bytes = await _c._getBytes(
        '/api/mobile/v2/orders/$orderId/invoice', auth: true);
    return bytes;
  }

  /// Refresh-button equivalent — same payload as detail() but talks to
  /// the dedicated /refresh route so the request is recognisably user-
  /// triggered in server logs.
  Future<UellowOrderDetail> refresh(int id) async {
    final res = await _c._get('${EP.orders}/$id/refresh', auth: true);
    return UellowOrderDetail.fromJson(
        res['data']['order'] as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> contactSeller({
    required int orderId, required String subject, required String body,
    List<String>? photosBase64,
  }) async {
    final res = await _c._post(
      '${EP.orders}/$orderId/contact-seller',
      auth: true,
      body: {
        'subject': subject, 'body': body,
        if (photosBase64 != null && photosBase64.isNotEmpty) 'photos': photosBase64,
      },
    );
    return Map<String, dynamic>.from(res['data'] as Map);
  }

  Future<UellowCheckoutConfirm> checkoutConfirm({
    int? deliveryAddressId,
    int? invoiceAddressId,
    int? carrierId,
    String? paymentMethod,
    bool guest = false,
    List<int>? lineIds, // selective checkout: pay for ONLY these lines
  }) async {
    final res = await _c._post(EP.checkoutConfirm, auth: !guest, body: {
      if (deliveryAddressId != null) 'delivery_address_id': deliveryAddressId,
      if (invoiceAddressId  != null) 'invoice_address_id': invoiceAddressId,
      if (carrierId         != null) 'carrier_id': carrierId,
      if (paymentMethod     != null) 'payment_method': paymentMethod,
      if (guest) 'guest': 1,
      if (lineIds != null && lineIds.isNotEmpty)
        'line_ids': lineIds.join(','),
    });
    return UellowCheckoutConfirm.fromJson(res['data'] as Map<String, dynamic>);
  }
}

class _AddressesApi {
  _AddressesApi(this._c);
  final UellowApi _c;

  Future<List<UellowAddress>> list() async {
    final res = await _c._get(EP.addresses, auth: true);
    return (res['data'] as List)
        .map((e) => UellowAddress.fromJson(e))
        .toList();
  }

  Future<UellowAddress> create(Map<String, dynamic> data) async {
    // v2.1.20 — guests create an ad-hoc address attached to their cart
    // (server allows it only when guest checkout is enabled).
    final token = await _c.tokenStore.readToken();
    final body = {
      ...data,
      if (token == null || token.isEmpty) 'guest': 1,
    };
    final res = await _c._post(EP.addressesCreate, auth: false, body: body);
    return UellowAddress.fromJson(
        res['data']['address'] as Map<String, dynamic>);
  }

  Future<UellowAddress> update(int id, Map<String, dynamic> data) async {
    final token = await _c.tokenStore.readToken();
    final body = {
      ...data,
      if (token == null || token.isEmpty) 'guest': 1,
    };
    final res = await _c._post('${EP.addresses}/$id/update', auth: false, body: body);
    return UellowAddress.fromJson(
        res['data']['address'] as Map<String, dynamic>);
  }

  Future<bool> delete(int id) async {
    final res = await _c._post('${EP.addresses}/$id/delete', auth: true);
    return res['data']?['deleted'] == true;
  }

  // v2.1.20 — mark one address as the primary/default delivery address.
  Future<UellowAddress> setDefault(int id) async {
    final res = await _c._post('${EP.addresses}/$id/set-default', auth: true);
    return UellowAddress.fromJson(
        res['data']['address'] as Map<String, dynamic>);
  }
}

class _WishlistApi {
  _WishlistApi(this._c);
  final UellowApi _c;

  // v2.1.29 — in-memory cache of wishlisted TEMPLATE ids so hearts stay
  // red across navigation. Warmed once per session; updated on toggle.
  static final Set<int> _cache = {};
  static bool _warmed = false;
  bool isCached(int productId) => _cache.contains(productId);

  Future<void> warm({bool force = false}) async {
    if (_warmed && !force) return;
    try {
      final token = await _c.tokenStore.readToken();
      if (token == null || token.isEmpty) return;
      final items = await list();
      _cache
        ..clear()
        ..addAll(items.map((p) => p.id));
      _warmed = true;
    } catch (_) {}
  }

  Future<List<UellowProductCard>> list() async {
    final res = await _c._get(EP.wishlist, auth: true);
    final items = (res['data'] as List)
        .map((e) => UellowProductCard.fromJson(e))
        .toList();
    _cache
      ..clear()
      ..addAll(items.map((p) => p.id));
    _warmed = true;
    return items;
  }

  Future<bool> add(int productId) async {
    final res = await _c._post(EP.wishlistAdd, auth: true,
        body: {'product_id': productId});
    _cache.add(productId);
    return res['data']?['added'] == true;
  }

  Future<bool> remove(int productId) async {
    final res = await _c._post(EP.wishlistRemove, auth: true,
        body: {'product_id': productId});
    _cache.remove(productId);
    return res['data']?['removed'] == true;
  }
}

class _SearchApi {
  _SearchApi(this._c);
  final UellowApi _c;

  Future<UellowSearchResult> search(String query,
      {int page = 1, int perPage = 20, bool log = true}) async {
    // v2.1.56 — log:false for as-you-type suggestion calls so half-typed
    // words never reach recent/trending analytics.
    final res = await _c._get(EP.search, query: {
      'q': query, 'page': page, 'per_page': perPage,
      if (!log) 'log': '0',
    });
    return UellowSearchResult.fromJson(res);
  }

  /// v2.1.56 — record a FINISHED search (submit / result tap).
  Future<void> record(String query) async {
    try {
      await _c._post('/api/mobile/v2/search/record', body: {'q': query});
    } catch (_) {/* analytics must never break UX */}
  }

  Future<List<UellowPopularQuery>> popular() async {
    final res = await _c._get(EP.searchPopular);
    return (res['data'] as List)
        .map((e) => UellowPopularQuery.fromJson(e))
        .toList();
  }

  Future<List<Map<String, dynamic>>> trending() async {
    final res = await _c._get('/api/mobile/v2/search/trending');
    final d = res['data'] as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(d['trending'] as List? ?? const []);
  }

  Future<List<Map<String, dynamic>>> recent() async {
    final res = await _c._get('/api/mobile/v2/search/recent');
    final d = res['data'] as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(d['recent'] as List? ?? const []);
  }

  Future<int> clearRecent() async {
    final res = await _c._post('/api/mobile/v2/search/recent/clear');
    final d = res['data'] as Map<String, dynamic>;
    return (d['cleared'] as int?) ?? 0;
  }
}

class _ReviewsApi {
  _ReviewsApi(this._c);
  final UellowApi _c;

  Future<Map<String, dynamic>> create({
    required int productId, required double rating,
    String? title, String? body, List<String>? photosBase64,
  }) async {
    final res = await _c._post(EP.reviewsCreate, auth: true, body: {
      'product_id': productId, 'rating': rating,
      if (title != null) 'title': title,
      if (body  != null) 'body': body,
      if (photosBase64 != null && photosBase64.isNotEmpty)
        'photos': photosBase64,
    });
    return res['data'] as Map<String, dynamic>;
  }

  Future<List<UellowMyReview>> mine() async {
    final res = await _c._get(EP.reviewsMine, auth: true);
    return (res['data'] as List)
        .map((e) => UellowMyReview.fromJson(e))
        .toList();
  }
}

class _LoyaltyApi {
  _LoyaltyApi(this._c);
  final UellowApi _c;

  Future<UellowLoyalty> overview() async {
    final res = await _c._get(EP.loyalty, auth: true);
    return UellowLoyalty.fromJson(res['data'] as Map<String, dynamic>);
  }
}

class _WalletApi {
  _WalletApi(this._c);
  final UellowApi _c;

  Future<UellowMoney> balance() async {
    final res = await _c._get(EP.walletBalance, auth: true);
    return UellowMoney.fromJson(res['data']['balance'] as Map<String, dynamic>);
  }

  Future<List<UellowWalletTx>> transactions() async {
    final res = await _c._get(EP.walletTransactions, auth: true);
    return (res['data'] as List)
        .map((e) => UellowWalletTx.fromJson(e))
        .toList();
  }
}

class _NotificationsApi {
  _NotificationsApi(this._c);
  final UellowApi _c;

  Future<List<UellowNotification>> list() async {
    final res = await _c._get(EP.notifications, auth: true);
    return (res['data'] as List)
        .map((e) => UellowNotification.fromJson(e))
        .toList();
  }

  Future<bool> markRead(int id) async {
    final res = await _c._post('${EP.notifications}/$id/read', auth: true);
    return res['data']?['read'] == true;
  }

  Future<void> registerDevice({
    required String deviceId,
    required String pushToken,
    String? platform, String? deviceName, String? osVersion, String? appVersion,
  }) async {
    await _c._post(EP.notificationsRegister, body: {
      'device_id': deviceId,
      'push_token': pushToken,
      // Live app language → server localizes push notifications to it.
      'lang': _c.lang,
      if (platform    != null) 'platform': platform,
      if (deviceName  != null) 'device_name': deviceName,
      if (osVersion   != null) 'os_version': osVersion,
      if (appVersion  != null) 'app_version': appVersion,
    });
  }
}

class _BeenaApi {
  _BeenaApi(this._c);
  final UellowApi _c;

  Future<Map<String, dynamic>> config() async {
    final res = await _c._get(EP.beenaConfig);
    return res['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> chat({
    required String message, List<Map<String, dynamic>>? history,
    int? productId, int? categoryId,
  }) async {
    // v2.1.55 — Claude calls can take 20-40s; the default 25s timeout
    // was a major source of "sorry, error" replies.
    final res = await _c._post(EP.beenaChat, body: {
      'message': message,
      if (history    != null) 'history': history,
      if (productId  != null) 'product_id': productId,
      if (categoryId != null) 'category_id': categoryId,
    }, timeout: const Duration(seconds: 70));
    return res['data'] as Map<String, dynamic>;
  }
}

class _SettingsApi {
  _SettingsApi(this._c);
  final UellowApi _c;

  Future<UellowAppSettings> get() async {
    final res = await _c._get(EP.appSettings, query: {'platform': _c._platform});
    return UellowAppSettings.fromJson(res['data'] as Map<String, dynamic>);
  }

  Future<List<UellowCountry>> countries() async {
    final res = await _c._get(EP.appCountries);
    return (res['data'] as List)
        .map((e) => UellowCountry.fromJson(e))
        .toList();
  }

  Future<List<UellowState>> states(int countryId) async {
    final res = await _c._get(EP.appStates, query: {'country_id': countryId});
    return (res['data'] as List)
        .map((e) => UellowState.fromJson(e))
        .toList();
  }

  Future<UellowVersionCheck> versionCheck(String version) async {
    final res = await _c._get(EP.appVersionCheck,
        query: {'version': version, 'platform': _c._platform});
    return UellowVersionCheck.fromJson(res['data'] as Map<String, dynamic>);
  }
}

// v2.0.89 — Shipping Pro endpoints (cities typeahead + carrier quote)
class _ShippingApi {
  _ShippingApi(this._c);
  final UellowApi _c;

  /// Typeahead lookup. country defaults to KW; `q` is a fuzzy partial.
  Future<List<Map<String, dynamic>>> cities(
      {String country = 'KW', String? q}) async {
    final res = await _c._get(
      '/api/mobile/v2/shipping/cities',
      query: {'country': country, if (q != null && q.isNotEmpty) 'q': q},
    );
    return (res['data'] as List).cast<Map<String, dynamic>>();
  }

  /// Available carriers for a city + payment method. Backend filters by
  /// time window so a 3-hour driver only shows up between 14:00 and 21:00.
  Future<List<Map<String, dynamic>>> quote(
      {required int cityId, required String payment}) async {
    final res = await _c._get(
      '/api/mobile/v2/shipping/quote',
      query: {'city_id': cityId, 'payment': payment},
    );
    return (res['data'] as List).cast<Map<String, dynamic>>();
  }
}
