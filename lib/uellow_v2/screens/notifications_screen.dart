// =============================================================================
// NotificationsScreen — live inbox from /api/mobile/v2/notifications.
// v2.1.66: tap a notification → detail dialog; closing it marks THAT
// notification read (server + local). «تعليم الكل كمقروء» marks both the
// personal events and the broadcasts (per-user read state on the server).
// =============================================================================
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../api/uellow_api.dart';
import '../theme/uellow_theme.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>>? _items;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final token = await UellowApi.instance.tokenStore.readToken();
    List<Map<String, dynamic>> out = const [];
    if (token != null && token.isNotEmpty) {
      try {
        final r = await http.get(
          Uri.parse('${UellowApi.instance.baseUrl}/api/mobile/v2/notifications'),
          headers: {
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
            'X-Lang': UellowApi.instance.lang,
          },
        );
        final body = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
        if (body['success'] == true) {
          out = (body['data'] as List).cast<Map<String, dynamic>>();
        }
      } catch (_) {}
    }
    if (mounted) setState(() { _items = out; _loading = false; });
  }

  Future<void> _markAllRead() async {
    // Optimistic: flip everything read locally, then tell the server.
    setState(() {
      for (final n in _items ?? <Map<String, dynamic>>[]) {
        n['is_read'] = true;
      }
    });
    try {
      await UellowApi.instance.postRaw(
          '/api/mobile/v2/notifications/read-all', auth: true);
    } catch (_) {}
  }

  Future<void> _markOneRead(Map<String, dynamic> n) async {
    if (n['is_read'] == true) return;
    setState(() => n['is_read'] = true);
    try {
      await UellowApi.instance.postRaw(
          '/api/mobile/v2/notifications/${n['id']}/read', auth: true);
    } catch (_) {}
  }

  // ── detail dialog — closing it marks the notification read ────────
  Future<void> _openDetail(Map<String, dynamic> n) async {
    final ar = UellowApi.instance.lang == 'ar';
    await showDialog(
      context: context,
      builder: (dctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
          child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 40, height: 40,
                decoration: const BoxDecoration(
                  color: UellowColors.yellowSoft,
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
                child: Icon(_iconFor(n['category']?.toString()),
                    size: 21, color: UellowColors.warn),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(n['title']?.toString() ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w900,
                      fontSize: 14.5, color: UellowColors.ink))),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => Navigator.of(dctx).pop(),
                icon: const Icon(Icons.close, size: 20,
                    color: UellowColors.muted),
              ),
            ]),
            const SizedBox(height: 10),
            Flexible(child: SingleChildScrollView(
              child: Text(n['body']?.toString() ?? '',
                  style: const TextStyle(fontSize: 13.5,
                      color: UellowColors.text, height: 1.55)),
            )),
            const SizedBox(height: 12),
            Row(children: [
              _chip(_categoryLabel(n['category']?.toString(), ar)),
              const Spacer(),
              Text(_fmtDate(n['date']?.toString()), style: UT.small),
            ]),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(dctx).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: UellowColors.yellow,
                  foregroundColor: UellowColors.darkBrown,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(ar ? 'حسناً' : 'OK',
                    style: const TextStyle(fontWeight: FontWeight.w900)),
              ),
            ),
          ]),
        ),
      ),
    );
    // Dialog dismissed (OK / ✕ / tap-outside) → it's been seen.
    await _markOneRead(n);
  }

  Widget _chip(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: UellowColors.yellowFaint,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: UellowColors.yellow.withValues(alpha: .5)),
        ),
        child: Text(label, style: const TextStyle(fontSize: 10.5,
            fontWeight: FontWeight.w800, color: UellowColors.darkBrown)),
      );

  static IconData _iconFor(String? cat) {
    switch (cat) {
      case 'order_update': return Icons.local_shipping_outlined;
      case 'promotion':    return Icons.local_offer_outlined;
      case 'wallet':       return Icons.account_balance_wallet_outlined;
      case 'loyalty':      return Icons.stars_outlined;
      default:             return Icons.notifications_outlined;
    }
  }

  static String _categoryLabel(String? cat, bool ar) {
    switch (cat) {
      case 'order_update': return ar ? 'تحديث طلب' : 'Order update';
      case 'promotion':    return ar ? 'عرض' : 'Promotion';
      case 'wallet':       return ar ? 'المحفظة' : 'Wallet';
      case 'loyalty':      return ar ? 'نقاط الولاء' : 'Loyalty';
      case 'system':       return ar ? 'النظام' : 'System';
      default:             return ar ? 'عام' : 'General';
    }
  }

  static String _fmtDate(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    // 2026-06-05T16:04:11.123 → 2026-06-05 16:04
    final t = iso.replaceFirst('T', ' ');
    return t.length >= 16 ? t.substring(0, 16) : t;
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return Scaffold(
      backgroundColor: UellowColors.bg,
      appBar: AppBar(
        leading: const BackButton(color: UellowColors.darkBrown),
        title: Text(ar ? 'الإشعارات' : 'Notifications', style: UT.h1),
        actions: [Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(child: GestureDetector(
              onTap: _markAllRead,
              child: Text(ar ? 'تعليم الكل كمقروء' : 'Mark all read',
                  style: const TextStyle(
                  color: UellowColors.text, fontWeight: FontWeight.w700,
                  fontSize: 12)))))],
      ),
      body: SafeArea(bottom: false, child: _loading
          ? const Center(child: CircularProgressIndicator(
              color: UellowColors.darkBrown))
          : ((_items ?? []).isEmpty
              ? _empty()
              : RefreshIndicator(
                  color: UellowColors.darkBrown,
                  onRefresh: _load,
                  child: ListView(children: [
                    for (final n in _items!) _row(n),
                  ]),
                ))),
    );
  }

  Widget _empty() {
    final ar = UellowApi.instance.lang == 'ar';
    return ListView(children: [
      const SizedBox(height: 120),
      const Center(child: Icon(Icons.notifications_off_outlined,
          size: 80, color: UellowColors.muted)),
      const SizedBox(height: 18),
      Center(child: Text(ar ? 'لا توجد إشعارات بعد' : 'No notifications yet', style: UT.h2)),
      const SizedBox(height: 6),
      Center(child: Text(ar ? 'سنُعلمك عند وجود جديد' : "We'll let you know when there's news",
          style: UT.body)),
    ]);
  }

  Widget _row(Map<String, dynamic> n) {
    final unread = !(n['is_read'] == true);
    return InkWell(
      onTap: () => _openDetail(n),
      child: Container(
        decoration: BoxDecoration(
          color: unread ? UellowColors.yellowFaint : Colors.white,
          border: const Border(bottom: BorderSide(color: UellowColors.bg)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 38, height: 38,
            decoration: const BoxDecoration(
              color: UellowColors.yellowSoft,
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
            child: Icon(_iconFor(n['category']?.toString()),
                size: 20, color: UellowColors.warn),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(n['title']?.toString() ?? '',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontWeight: unread ? FontWeight.w900 : FontWeight.w700,
                      fontSize: 13, color: UellowColors.ink))),
              if (unread) Container(
                width: 7, height: 7,
                decoration: const BoxDecoration(
                    color: UellowColors.danger, shape: BoxShape.circle),
              ),
            ]),
            const SizedBox(height: 3),
            Text(n['body']?.toString() ?? '',
                maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12.5, color: UellowColors.text, height: 1.4)),
            if (n['date'] != null) Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(_fmtDate(n['date']?.toString()), style: UT.small),
            ),
          ])),
        ]),
      ),
    );
  }
}
