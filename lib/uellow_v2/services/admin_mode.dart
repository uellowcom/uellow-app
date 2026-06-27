// =============================================================================
// AdminMode (v2.2.27) — global "is this user an admin?" switch.
//
// SECURITY: this flag is **memory-only** and defaults to false on every
// cold start. It is NOT persisted — a persisted `true` used to survive an
// account switch on a shared device, exposing the admin console UI to a
// normal user (the data endpoints were always server-gated, but the
// console shell + entry chips must never appear). It is set true ONLY by a
// live server response (/account/overview is_admin, re-checked by
// /admin/check when the console opens) and is force-reset to false on every
// auth change (login / logout / 401). Every admin-only widget listens to
// [AdminMode.isAdmin].
// =============================================================================
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../api/uellow_api.dart';

class AdminMode {
  AdminMode._();

  static final ValueNotifier<bool> isAdmin = ValueNotifier<bool>(false);
  static const _legacyKey = 'uellow_is_admin_v1';

  /// Startup: always begin as a non-admin and scrub any legacy persisted
  /// flag from older builds (which is the cross-account leak vector).
  static Future<void> restore() async {
    isAdmin.value = false;
    try {
      final sp = await SharedPreferences.getInstance();
      if (sp.containsKey(_legacyKey)) await sp.remove(_legacyKey);
    } catch (_) {}
  }

  /// Called whenever /account/overview returns. Memory-only — never cached.
  static Future<void> set(bool value) async {
    if (isAdmin.value != value) isAdmin.value = value;
  }

  /// Force back to non-admin (auth change / logout / token cleared).
  static void reset() {
    if (isAdmin.value) isAdmin.value = false;
  }

  /// Defense-in-depth: ask the server directly. Returns true only when the
  /// authenticated caller really is an admin. Any error → false.
  static Future<bool> verify() async {
    try {
      final r = await UellowApi.instance
          .getRaw('/api/mobile/v2/admin/check', auth: true);
      final v = ((r['data'] as Map?)?['is_admin']) == true;
      await set(v);
      return v;
    } catch (_) {
      reset();
      return false;
    }
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

  /// Aggregate POS report (sales/profit/margin by day, cashier, payment,
  /// top products) over the last [days].
  Future<Map<String, dynamic>> posReport({int days = 30}) async {
    final r = await UellowApi.instance.getRaw(
        '/api/mobile/v2/admin/pos/report',
        query: {'days': '$days'}, auth: true);
    return ((r['data'] as Map?) ?? const {}).cast<String, dynamic>();
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

  // ── v2.2.41 — eCommerce category picker + sales actions ──────────────
  Future<List<Map<String, dynamic>>> categories() async {
    final r = await UellowApi.instance
        .getRaw('/api/mobile/v2/admin/categories', auth: true);
    final list = ((r['data'] as Map?)?['categories'] as List?) ?? const [];
    return list.map((e) => (e as Map).cast<String, dynamic>()).toList();
  }

  Future<Map<String, dynamic>> _post(String path,
      [Map<String, dynamic>? body]) async {
    final r = await UellowApi.instance
        .postRaw(path, body: body ?? const {}, auth: true);
    if (r['success'] != true) {
      throw Exception((r['error'] ?? r['code'] ?? 'failed').toString());
    }
    return ((r['data'] as Map?) ?? const {}).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> orderApprove(int id) =>
      _post('/api/mobile/v2/admin/order/$id/approve');

  Future<Map<String, dynamic>> orderCancel(int id) =>
      _post('/api/mobile/v2/admin/order/$id/cancel');

  Future<Map<String, dynamic>> deliveryOptions() async {
    final r = await UellowApi.instance
        .getRaw('/api/mobile/v2/admin/delivery/options', auth: true);
    return ((r['data'] as Map?) ?? const {}).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> assignDelivery(int id,
          Map<String, dynamic> body) =>
      _post('/api/mobile/v2/admin/order/$id/assign-delivery', body);

  Future<Map<String, dynamic>> orderCreate(Map<String, dynamic> body) =>
      _post('/api/mobile/v2/admin/order/create', body);

  // ── v2.2.54 — full order action set from the admin console ───────────
  Future<Map<String, dynamic>> orderLock(int id) =>
      _post('/api/mobile/v2/admin/order/$id/lock');

  Future<Map<String, dynamic>> orderUnlock(int id) =>
      _post('/api/mobile/v2/admin/order/$id/unlock');

  /// Create + post the customer invoice.
  Future<Map<String, dynamic>> orderInvoice(int id) =>
      _post('/api/mobile/v2/admin/order/$id/invoice');

  /// Validate the delivery (mark the picking done).
  Future<Map<String, dynamic>> orderDeliver(int id) =>
      _post('/api/mobile/v2/admin/order/$id/deliver');

  /// Register a payment on the posted unpaid invoice.
  Future<Map<String, dynamic>> orderRegisterPayment(int id,
          [Map<String, dynamic>? body]) =>
      _post('/api/mobile/v2/admin/order/$id/register-payment', body);

  /// Reconcile an online (UPayments) charge against the gateway — captures
  /// the order if the customer actually paid (heals a missed webhook).
  Future<Map<String, dynamic>> orderVerifyPayment(int id) =>
      _post('/api/mobile/v2/admin/order/$id/verify-payment');

  // ── v2.2.56 — customer journey / activity ────────────────────────────
  Future<Map<String, dynamic>> activityRecent(
      {int page = 1, String q = '', int? partnerId, String event = ''}) async {
    final r = await UellowApi.instance.getRaw(
        '/api/mobile/v2/admin/activity/recent',
        query: {
          'page': '$page',
          if (q.isNotEmpty) 'q': q,
          if (partnerId != null) 'partner_id': '$partnerId',
          if (event.isNotEmpty) 'event': event,
        },
        auth: true);
    return ((r['data'] as Map?) ?? const {}).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> customerActivity(int partnerId,
      {int page = 1}) async {
    final r = await UellowApi.instance.getRaw(
        '/api/mobile/v2/admin/customer/$partnerId/activity',
        query: {'page': '$page'}, auth: true);
    return ((r['data'] as Map?) ?? const {}).cast<String, dynamic>();
  }

  // ── v2.2.53 — Helpdesk (support tickets) ─────────────────────────────
  /// KPIs + stages + teams + priorities (filter chips on the list screen).
  Future<Map<String, dynamic>> helpdeskMeta() async {
    final r = await UellowApi.instance
        .getRaw('/api/mobile/v2/admin/helpdesk/meta', auth: true);
    return ((r['data'] as Map?) ?? const {}).cast<String, dynamic>();
  }

  /// Paginated ticket list. `status` = open|closed|all; optional filters by
  /// stage / team / priority / unassigned.
  Future<Map<String, dynamic>> tickets({
    int page = 1,
    String q = '',
    String status = 'open',
    int? stageId,
    int? teamId,
    String priority = '',
    bool unassigned = false,
  }) async {
    final r = await UellowApi.instance.getRaw(
        '/api/mobile/v2/admin/helpdesk/tickets',
        query: {
          'page': '$page',
          if (q.isNotEmpty) 'q': q,
          if (status.isNotEmpty) 'status': status,
          if (stageId != null) 'stage_id': '$stageId',
          if (teamId != null) 'team_id': '$teamId',
          if (priority.isNotEmpty) 'priority': priority,
          if (unassigned) 'unassigned': '1',
        },
        auth: true);
    return ((r['data'] as Map?) ?? const {}).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> ticketDetail(int id) async {
    final r = await UellowApi.instance
        .getRaw('/api/mobile/v2/admin/helpdesk/ticket/$id', auth: true);
    return ((r['data'] as Map?) ?? const {}).cast<String, dynamic>();
  }

  /// Post a customer reply (emails followers) or a private internal note.
  Future<Map<String, dynamic>> ticketReply(int id, String body,
          {bool internal = false}) =>
      _post('/api/mobile/v2/admin/helpdesk/ticket/$id/reply',
          {'body': body, 'internal': internal});

  Future<Map<String, dynamic>> ticketStage(int id, int stageId) =>
      _post('/api/mobile/v2/admin/helpdesk/ticket/$id/stage',
          {'stage_id': stageId});

  /// Assign to a user id, or pass `'me'` / `0` (unassign).
  Future<Map<String, dynamic>> ticketAssign(int id, dynamic userId) =>
      _post('/api/mobile/v2/admin/helpdesk/ticket/$id/assign',
          {'user_id': userId});

  Future<List<Map<String, dynamic>>> helpdeskAgents() async {
    final r = await UellowApi.instance
        .getRaw('/api/mobile/v2/admin/helpdesk/agents', auth: true);
    final list = ((r['data'] as Map?)?['agents'] as List?) ?? const [];
    return list.map((e) => (e as Map).cast<String, dynamic>()).toList();
  }

  // ── v2.2.57 — Purchase (procurement) manager ─────────────────────────
  /// State counts for the filter chips (rfq / to_approve / purchase / …).
  Future<Map<String, dynamic>> purchaseMeta() async {
    final r = await UellowApi.instance
        .getRaw('/api/mobile/v2/admin/purchase/meta', auth: true);
    return ((r['data'] as Map?) ?? const {}).cast<String, dynamic>();
  }

  /// Paginated purchase-order / RFQ list. `state` =
  /// rfq|to_approve|purchase|to_receive|to_bill|cancel|'' (all).
  Future<Map<String, dynamic>> purchases(
      {int page = 1, String q = '', String state = ''}) async {
    final r = await UellowApi.instance.getRaw(
        '/api/mobile/v2/admin/purchases',
        query: {
          'page': '$page',
          if (q.isNotEmpty) 'q': q,
          if (state.isNotEmpty) 'state': state,
        },
        auth: true);
    return ((r['data'] as Map?) ?? const {}).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> purchaseDetail(int id) async {
    final r = await UellowApi.instance
        .getRaw('/api/mobile/v2/admin/purchase/$id', auth: true);
    return ((r['data'] as Map?) ?? const {}).cast<String, dynamic>();
  }

  /// Confirm an RFQ → purchase order.
  Future<Map<String, dynamic>> purchaseConfirm(int id) =>
      _post('/api/mobile/v2/admin/purchase/$id/confirm');

  Future<Map<String, dynamic>> purchaseCancel(int id) =>
      _post('/api/mobile/v2/admin/purchase/$id/cancel');

  /// Validate the incoming receipt (set the goods received in stock).
  Future<Map<String, dynamic>> purchaseReceive(int id) =>
      _post('/api/mobile/v2/admin/purchase/$id/receive');

  /// Create + post the vendor bill.
  Future<Map<String, dynamic>> purchaseBill(int id) =>
      _post('/api/mobile/v2/admin/purchase/$id/bill');
}
