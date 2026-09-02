// =============================================================================
// HelpdeskConversationScreen — the ticket thread as a chat: the customer's
// messages + the AGENT REPLIES (which never used to show), plus a reply box so
// the customer can continue the conversation. Consumes
// /api/mobile/v2/helpdesk/ticket/<id> (GET, marks read) and .../reply (POST).
// =============================================================================
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../api/uellow_api.dart';
import '../theme/uellow_theme.dart';

class HelpdeskConversationScreen extends StatefulWidget {
  const HelpdeskConversationScreen({
    super.key,
    required this.ticketId,
    this.ref = '',
    this.subject = '',
  });
  final int ticketId;
  final String ref;
  final String subject;
  @override
  State<HelpdeskConversationScreen> createState() =>
      _HelpdeskConversationScreenState();
}

class _HelpdeskConversationScreenState
    extends State<HelpdeskConversationScreen> {
  bool _loading = true;
  bool _sending = false;
  String? _error;
  Map<String, dynamic> _t = const {};
  List<Map<String, dynamic>> _msgs = const [];
  final _reply = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reply.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final token = await UellowApi.instance.tokenStore.readToken();
      final r = await http.get(
        Uri.parse(
            '${UellowApi.instance.baseUrl}/api/mobile/v2/helpdesk/ticket/${widget.ticketId}'),
        headers: {
          'Accept': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );
      final b = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (!mounted) return;
      if (b['success'] == true && b['data'] is Map) {
        final d = (b['data'] as Map).cast<String, dynamic>();
        setState(() {
          _t = d;
          _msgs = ((d['messages'] as List?) ?? const [])
              .cast<Map<String, dynamic>>();
          _loading = false;
        });
        _jumpToEnd();
      } else {
        setState(() {
          _error = (b['error'] ?? 'Failed to load ticket').toString();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _jumpToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send() async {
    final text = _reply.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final token = await UellowApi.instance.tokenStore.readToken();
      final r = await http.post(
        Uri.parse(
            '${UellowApi.instance.baseUrl}/api/mobile/v2/helpdesk/ticket/${widget.ticketId}/reply'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'body': text}),
      );
      final b = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (b['success'] == true) {
        _reply.clear();
        await _load();
      }
    } catch (_) {}
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    final label =
        ((_t['stage_label'] as Map?)?[ar ? 'ar' : 'en'] ?? _t['stage'] ?? '')
            .toString();
    return Scaffold(
      backgroundColor: UellowColors.bg,
      appBar: AppBar(
        leading: const BackButton(color: UellowColors.darkBrown),
        title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  widget.subject.isNotEmpty
                      ? widget.subject
                      : (ar ? 'التذكرة' : 'Ticket'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: UellowColors.darkBrown)),
              if (label.isNotEmpty)
                Text('#${widget.ref} · $label',
                    style: const TextStyle(
                        fontSize: 11, color: UellowColors.muted)),
            ]),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: UellowColors.darkBrown))
            : _error != null
                ? Center(child: Text(_error!, style: UT.h3))
                : Column(children: [
                    Expanded(
                      child: ListView(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                        children: [
                          if ((_t['description'] ?? '')
                              .toString()
                              .trim()
                              .isNotEmpty)
                            _bubble(ar, true, _t['description'].toString(),
                                ar ? 'أنت' : 'You', null),
                          ..._msgs.map((m) => _bubble(
                              ar,
                              m['mine'] == true,
                              (m['body'] ?? '').toString(),
                              (m['author'] ?? '').toString(),
                              m['date'] as String?)),
                        ],
                      ),
                    ),
                    _composer(ar),
                  ]),
      ),
    );
  }

  Widget _bubble(bool ar, bool mine, String body, String author, String? date) {
    final align = mine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final color = mine ? UellowColors.yellow : Colors.white;
    final txtColor = mine ? UellowColors.darkBrown : UellowColors.ink;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: align, children: [
        if (!mine)
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 4, bottom: 2),
            child: Text(author,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: UellowColors.muted)),
          ),
        Container(
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(14),
              border: mine ? null : Border.all(color: UellowColors.border)),
          child: Text(body,
              style: TextStyle(fontSize: 13.5, height: 1.35, color: txtColor)),
        ),
        if (date != null && _fmt(date).isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
            child: Text(_fmt(date),
                style:
                    const TextStyle(fontSize: 10, color: UellowColors.muted)),
          ),
      ]),
    );
  }

  Widget _composer(bool ar) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: UellowColors.border))),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: _reply,
            minLines: 1,
            maxLines: 4,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(
              hintText: ar ? 'اكتب رسالتك...' : 'Type your message...',
              isDense: true,
              filled: true,
              fillColor: UellowColors.bg,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Material(
          color: UellowColors.yellow,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: _sending ? null : _send,
            child: Padding(
              padding: const EdgeInsets.all(11),
              child: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: UellowColors.darkBrown))
                  : const Icon(Icons.send,
                      size: 18, color: UellowColors.darkBrown),
            ),
          ),
        ),
      ]),
    );
  }

  String _fmt(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return '';
    final l = d.toLocal();
    String two(int n) => n < 10 ? '0$n' : '$n';
    return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
  }
}
