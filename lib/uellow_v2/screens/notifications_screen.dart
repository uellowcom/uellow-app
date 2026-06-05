// =============================================================================
// NotificationsScreen — live inbox from /api/mobile/v2/notifications.
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
  int _tab = 0;
  Future<List<Map<String, dynamic>>>? _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List<Map<String, dynamic>>> _fetch() async {
    final token = await UellowApi.instance.tokenStore.readToken();
    if (token == null || token.isEmpty) return const [];
    try {
      final r = await http.get(
        Uri.parse('${UellowApi.instance.baseUrl}/api/mobile/v2/notifications'),
        headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token'},
      );
      final body = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (body['success'] == true) {
        return (body['data'] as List).cast<Map<String, dynamic>>();
      }
    } catch (_) {}
    return const [];
  }

  Future<void> _markAllRead() async {
    try {
      await UellowApi.instance.postRaw(
          '/api/mobile/v2/notifications/read-all', auth: true);
      if (mounted) setState(() => _future = _fetch());
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UellowColors.bg,
      appBar: AppBar(
        leading: const BackButton(color: UellowColors.darkBrown),
        title: Text(UellowApi.instance.lang == 'ar' ? 'الإشعارات' : 'Notifications',
            style: UT.h1),
        actions: [Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(child: GestureDetector(
              // v2.1.63 — actually marks everything read (was decorative).
              onTap: _markAllRead,
              child: Text(
                  UellowApi.instance.lang == 'ar' ? 'تعليم الكل كمقروء' : 'Mark all read',
                  style: const TextStyle(
                  color: UellowColors.text, fontWeight: FontWeight.w700, fontSize: 12)))))],
      ),
      body: SafeArea(bottom: false, child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (_, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: UellowColors.darkBrown));
          }
          final items = snap.data ?? [];
          // v2.1.63 — seeing the list clears the unread badge.
          if (items.any((n) => n['is_read'] != true)) {
            Future.microtask(() => UellowApi.instance.postRaw(
                '/api/mobile/v2/notifications/read-all', auth: true)
                .catchError((_) => <String, dynamic>{}));
          }
          if (items.isEmpty) return _empty();
          return ListView(children: [
            for (final n in items) _row(n),
          ]);
        },
      )),
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
    return Container(
      color: unread ? UellowColors.yellowFaint : Colors.white,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: UellowColors.bg)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 38, height: 38,
          decoration: const BoxDecoration(
            color: UellowColors.yellowSoft,
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          child: const Icon(Icons.notifications_outlined,
              size: 20, color: UellowColors.warn),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(n['title']?.toString() ?? '', style: const TextStyle(
                fontWeight: FontWeight.w800, fontSize: 13, color: UellowColors.ink))),
            if (unread) Container(
              width: 7, height: 7,
              decoration: const BoxDecoration(
                  color: UellowColors.danger, shape: BoxShape.circle),
            ),
          ]),
          const SizedBox(height: 3),
          Text(n['body']?.toString() ?? '', style: const TextStyle(
              fontSize: 12.5, color: UellowColors.text, height: 1.4)),
          if (n['date'] != null) Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('${n['date']}', style: UT.small),
          ),
        ])),
      ]),
    );
  }
}
