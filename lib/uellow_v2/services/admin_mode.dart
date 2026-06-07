// =============================================================================
// AdminMode (v2.2.10) — global "is this user an admin?" switch.
//
// Set from /account/overview's `is_admin` flag (and persisted so the
// shield icon / product-card admin chips appear instantly on next
// launch). Every admin-only widget listens to [AdminMode.isAdmin].
// =============================================================================
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../api/uellow_api.dart';

class AdminMode {
  AdminMode._();

  static final ValueNotifier<bool> isAdmin = ValueNotifier<bool>(false);
  static const _key = 'uellow_is_admin_v1';

  /// Restore the cached flag at startup (before overview loads).
  static Future<void> restore() async {
    try {
      final sp = await SharedPreferences.getInstance();
      isAdmin.value = sp.getBool(_key) ?? false;
    } catch (_) {}
  }

  /// Called whenever /account/overview returns. Persists the flag.
  static Future<void> set(bool value) async {
    if (isAdmin.value != value) isAdmin.value = value;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(_key, value);
    } catch (_) {}
  }
}

/// Thin typed wrapper over the admin endpoints (all `needAuth`).
class AdminApi {
  AdminApi._();
  static final AdminApi instance = AdminApi._();

  Future<Map<String, dynamic>> dashboard() async {
    final r = await UellowApi.instance
        .getRaw('/api/mobile/v2/admin/dashboard', auth: true);
    return (r['data'] as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> orders(
      {int page = 1, String q = '', String state = ''}) async {
    final r = await UellowApi.instance.getRaw('/api/mobile/v2/admin/orders',
        query: {
          'page': '$page',
          if (q.isNotEmpty) 'q': q,
          if (state.isNotEmpty) 'state': state,
        },
        auth: true);
    return (r['data'] as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> orderDetail(int id) async {
    final r = await UellowApi.instance
        .getRaw('/api/mobile/v2/admin/order/$id', auth: true);
    return (r['data'] as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> posSessions({int page = 1}) async {
    final r = await UellowApi.instance.getRaw(
        '/api/mobile/v2/admin/pos/sessions',
        query: {'page': '$page'},
        auth: true);
    return (r['data'] as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> posOrders({int page = 1, int? sessionId}) async {
    final r = await UellowApi.instance.getRaw(
        '/api/mobile/v2/admin/pos/orders',
        query: {
          'page': '$page',
          if (sessionId != null) 'session_id': '$sessionId',
        },
        auth: true);
    return (r['data'] as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> products({int page = 1, String q = ''}) async {
    final r = await UellowApi.instance.getRaw('/api/mobile/v2/admin/products',
        query: {'page': '$page', if (q.isNotEmpty) 'q': q}, auth: true);
    return (r['data'] as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> productDetail(int id) async {
    final r = await UellowApi.instance
        .getRaw('/api/mobile/v2/admin/product/$id', auth: true);
    return (r['data'] as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> productUpdate(Map<String, dynamic> body) async {
    final r = await UellowApi.instance
        .postRaw('/api/mobile/v2/admin/product/update', body: body, auth: true);
    if (r['success'] != true) {
      throw Exception(
          (r['error'] ?? r['code'] ?? 'update failed').toString());
    }
    return (r['data'] as Map).cast<String, dynamic>();
  }
}
