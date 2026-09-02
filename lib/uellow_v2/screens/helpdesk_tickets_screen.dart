// =============================================================================
// HelpdeskTicketsScreen — the customer's support hub: every ticket they raised,
// live stats, and a "new ticket" button. Tapping a ticket opens the full
// conversation (HelpdeskConversationScreen) where the agent replies show.
// Consumes /api/mobile/v2/helpdesk/{tickets,stats}.
// =============================================================================
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../api/uellow_api.dart';
import '../theme/uellow_theme.dart';
import 'helpdesk_screen.dart';
import 'helpdesk_conversation_screen.dart';

class HelpdeskTicketsScreen extends StatefulWidget {
  const HelpdeskTicketsScreen({super.key});
  @override
  State<HelpdeskTicketsScreen> createState() => _HelpdeskTicketsScreenState();
}

class _HelpdeskTicketsScreenState extends State<HelpdeskTicketsScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _tickets = const [];
  Map<String, dynamic> _stats = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Map<String, dynamic>?> _get(String path) async {
    final token = await UellowApi.instance.tokenStore.readToken();
    final r = await http.get(
      Uri.parse('${UellowApi.instance.baseUrl}/api/mobile/v2/helpdesk/$path'),
      headers: {
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );
    final b = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    if (b['success'] == true && b['data'] is Map) {
      return (b['data'] as Map).cast<String, dynamic>();
    }
    return null;
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = _tickets.isEmpty);
    try {
      final t = await _get('tickets');
      final s = await _get('stats');
      if (!mounted) return;
      setState(() {
        _tickets = ((t?['tickets'] as List?) ?? const [])
            .cast<Map<String, dynamic>>();
        _stats = s ?? const {};
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _newTicket() async {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => const HelpdeskScreen()));
    _load();
  }

  Future<void> _open(Map<String, dynamic> t) async {
    await Navigator.push(context, MaterialPageRoute(
        builder: (_) => HelpdeskConversationScreen(
              ticketId: t['id'] as int,
              ref: (t['ref'] ?? '').toString(),
              subject: (t['subject'] ?? '').toString(),
            )));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return Scaffold(
      backgroundColor: UellowColors.bg,
      appBar: AppBar(
        leading: const BackButton(color: UellowColors.darkBrown),
        title: Text(ar ? 'الدعم الفني' : 'Support', style: UT.h1),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: UellowColors.yellow,
        foregroundColor: UellowColors.darkBrown,
        icon: const Icon(Icons.add),
        label: Text(ar ? 'تذكرة جديدة' : 'New ticket',
            style: const TextStyle(fontWeight: FontWeight.w900)),
        onPressed: _newTicket,
      ),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: UellowColors.darkBrown))
            : RefreshIndicator(
                onRefresh: _load,
                color: UellowColors.darkBrown,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 96),
                  children: [
                    _statsCard(ar),
                    const SizedBox(height: 14),
                    if (_tickets.isEmpty)
                      _empty(ar)
                    else
                      ..._tickets.map((t) => _ticketCard(ar, t)),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _empty(bool ar) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(children: [
          const Icon(Icons.support_agent, size: 48, color: UellowColors.muted),
          const SizedBox(height: 10),
          Text(ar ? 'لا توجد تذاكر بعد' : 'No tickets yet', style: UT.h3),
          const SizedBox(height: 4),
          Text(
              ar
                  ? 'اضغط «تذكرة جديدة» لبدء محادثة مع فريق الدعم.'
                  : 'Tap "New ticket" to start a chat with support.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: UellowColors.muted, fontSize: 12)),
        ]),
      );

  Widget _statsCard(bool ar) {
    Widget chip(String label, dynamic v, Color c) => Expanded(
          child: Column(children: [
            Text('${v ?? 0}',
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w900, color: c)),
            Text(label,
                style: const TextStyle(fontSize: 11, color: UellowColors.muted)),
          ]),
        );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.all(Radius.circular(16))),
      child: Row(children: [
        chip(ar ? 'الكل' : 'Total', _stats['total'], UellowColors.darkBrown),
        chip(ar ? 'مفتوحة' : 'Open', _stats['open'], const Color(0xFFE79A2B)),
        chip(ar ? 'محلولة' : 'Solved', _stats['solved'],
            const Color(0xFF2E9E5B)),
        chip(ar ? 'غير مقروء' : 'Unread', _stats['unread'],
            UellowColors.danger),
      ]),
    );
  }

  Widget _ticketCard(bool ar, Map<String, dynamic> t) {
    final unread = (t['unread'] as int?) ?? 0;
    final closed = t['closed'] == true;
    final label =
        ((t['stage_label'] as Map?)?[ar ? 'ar' : 'en'] ?? t['stage'] ?? '')
            .toString();
    final orderName = (t['order'] as Map?)?['name']?.toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: unread > 0 ? UellowColors.yellow : UellowColors.border),
      ),
      child: ListTile(
        onTap: () => _open(t),
        title: Text((t['subject'] ?? '').toString(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontWeight: FontWeight.w800, color: UellowColors.ink)),
        subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text((t['last_message'] ?? '').toString(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(fontSize: 12, color: UellowColors.muted)),
              const SizedBox(height: 6),
              Row(children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: closed
                          ? const Color(0x1A2E9E5B)
                          : const Color(0x1AE79A2B),
                      borderRadius: BorderRadius.circular(6)),
                  child: Text(label,
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: closed
                              ? const Color(0xFF2E9E5B)
                              : const Color(0xFFE79A2B))),
                ),
                const SizedBox(width: 6),
                Text('#${t['ref']}',
                    style: const TextStyle(
                        fontSize: 10.5, color: UellowColors.muted)),
                if (orderName != null && orderName.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.receipt_long,
                      size: 12, color: UellowColors.muted),
                  const SizedBox(width: 2),
                  Text(orderName,
                      style: const TextStyle(
                          fontSize: 10.5, color: UellowColors.muted)),
                ],
              ]),
            ]),
        trailing: unread > 0
            ? Container(
                padding: const EdgeInsets.all(7),
                decoration: const BoxDecoration(
                    color: UellowColors.danger, shape: BoxShape.circle),
                child: Text('$unread',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w900)))
            : const Icon(Icons.chevron_right,
                color: Color(0xFFCBB78A), size: 18),
      ),
    );
  }
}
