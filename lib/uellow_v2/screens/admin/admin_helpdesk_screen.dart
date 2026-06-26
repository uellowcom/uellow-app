// =============================================================================
// AdminHelpdeskScreen (v2.2.53) — 🆘 support-ticket manager for the in-app
// admin console. Mirrors the Orders manager: KPI header, search, stage
// filter chips, infinite scroll, and a full ticket page with the customer
// conversation, reply box (public reply / internal note), stage change and
// agent assignment. All data comes from /api/mobile/v2/admin/helpdesk/*.
// =============================================================================
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../api/uellow_api.dart';
import '../../services/admin_mode.dart';
import '../../theme/uellow_theme.dart';

// ─── shared helpers ─────────────────────────────────────────────────────
String _plain(String html) {
  if (html.isEmpty) return '';
  final s = html
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");
  return s.trim();
}

/// Bilingual label coming from the API as {en, ar} — falls back gracefully.
String _bil(dynamic m, bool ar) {
  if (m is Map) return (ar ? m['ar'] : m['en'])?.toString() ?? '';
  return m?.toString() ?? '';
}

Color _stageColor(Map t) {
  if (t['closed'] == true) {
    final s = (t['stage'] ?? '').toString().toLowerCase();
    if (s.contains('cancel') || s.contains('ملغ')) return const Color(0xFFEF4444);
    return const Color(0xFF10B981); // solved / done
  }
  final s = (t['stage'] ?? '').toString().toLowerCase();
  if (s.contains('progress') || s.contains('تنفيذ')) return const Color(0xFFF59E0B);
  if (s.contains('hold') || s.contains('انتظار') || s.contains('معلق')) {
    return const Color(0xFF8B5CF6);
  }
  return const Color(0xFF2563EB); // new / open
}

const _priorityColors = {
  '0': Color(0xFF9CA3AF), '1': Color(0xFF2563EB),
  '2': Color(0xFFF59E0B), '3': Color(0xFFEF4444),
};

// ═══════════════════════════════════════════════════════════════════════
// LIST SCREEN
// ═══════════════════════════════════════════════════════════════════════
class AdminHelpdeskScreen extends StatefulWidget {
  const AdminHelpdeskScreen({super.key});
  @override
  State<AdminHelpdeskScreen> createState() => _AdminHelpdeskScreenState();
}

class _AdminHelpdeskScreenState extends State<AdminHelpdeskScreen> {
  final _scroll = ScrollController();
  final _searchCtl = TextEditingController();
  Timer? _debounce;

  final List<Map<String, dynamic>> _rows = [];
  int _page = 1, _pages = 1, _total = 0;
  bool _loading = false;
  String _q = '', _status = 'open';
  int? _stageId;

  Map<String, dynamic> _meta = const {};

  @override
  void initState() {
    super.initState();
    _loadMeta();
    _load(reset: true);
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300 &&
          !_loading && _page < _pages) {
        _page += 1;
        _load();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _searchCtl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadMeta() async {
    try {
      final m = await AdminApi.instance.helpdeskMeta();
      if (mounted) setState(() => _meta = m);
    } catch (_) {}
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      _page = 1;
      _rows.clear();
    }
    setState(() => _loading = true);
    try {
      final d = await AdminApi.instance.tickets(
          page: _page, q: _q, status: _status, stageId: _stageId);
      _pages = (d['pages'] as num?)?.toInt() ?? 1;
      _total = (d['total'] as num?)?.toInt() ?? 0;
      _rows.addAll(((d['tickets'] as List?) ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>()));
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    final kpi = (_meta['kpi'] as Map?) ?? const {};
    final stages = ((_meta['stages'] as List?) ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>()).toList();
    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF412402),
        foregroundColor: UellowColors.yellow,
        iconTheme: const IconThemeData(color: UellowColors.yellow),
        title: Text('${ar ? '🆘 الدعم' : '🆘 Helpdesk'}'
            '${_total > 0 ? ' ($_total)' : ''}',
            style: const TextStyle(fontSize: 16,
                fontWeight: FontWeight.w900, color: UellowColors.yellow)),
      ),
      body: Column(children: [
        Container(
          color: const Color(0xFF412402),
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          child: Column(children: [
            // KPI strip
            if (kpi.isNotEmpty)
              SizedBox(height: 52, child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _kpi(ar ? 'مفتوحة' : 'Open', kpi['open'],
                      const Color(0xFF2563EB)),
                  _kpi(ar ? 'غير مُسندة' : 'Unassigned', kpi['unassigned'],
                      const Color(0xFFF59E0B)),
                  _kpi(ar ? 'اليوم' : 'Today', kpi['today'],
                      const Color(0xFF10B981)),
                  _kpi(ar ? 'عاجلة' : 'Urgent', kpi['high_priority'],
                      const Color(0xFFEF4444)),
                  _kpi(ar ? 'الكل' : 'Total', kpi['total'],
                      const Color(0xFF9CA3AF)),
                ],
              )),
            if (kpi.isNotEmpty) const SizedBox(height: 10),
            TextField(
              controller: _searchCtl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: ar ? '🔍 رقم التذكرة / الموضوع / العميل'
                             : '🔍 Ticket # / subject / customer',
                hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: .45), fontSize: 12),
                filled: true,
                fillColor: Colors.white.withValues(alpha: .1),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 11),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
              onChanged: (v) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 450), () {
                  _q = v.trim();
                  _load(reset: true);
                });
              },
            ),
            const SizedBox(height: 9),
            // status filters
            SizedBox(height: 30, child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _statusChip(ar ? 'مفتوحة' : 'Open', 'open'),
                _statusChip(ar ? 'مغلقة' : 'Closed', 'closed'),
                _statusChip(ar ? 'الكل' : 'All', 'all'),
              ],
            )),
            if (stages.isNotEmpty) ...[
              const SizedBox(height: 7),
              SizedBox(height: 30, child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _stageChip(ar ? 'كل المراحل' : 'All stages', null, null),
                  for (final s in stages)
                    _stageChip('${s['name']} (${s['count'] ?? 0})',
                        (s['id'] as num).toInt(), s),
                ],
              )),
            ],
          ]),
        ),
        Expanded(child: _rows.isEmpty && _loading
            ? const Center(child: CircularProgressIndicator(
                color: UellowColors.darkBrown))
            : _rows.isEmpty
                ? Center(child: Text(ar ? 'لا توجد تذاكر' : 'No tickets',
                    style: const TextStyle(color: UellowColors.muted)))
                : RefreshIndicator(
                    onRefresh: () async {
                      await _loadMeta();
                      await _load(reset: true);
                    },
                    child: ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
                      itemCount: _rows.length + (_loading ? 1 : 0),
                      itemBuilder: (_, i) {
                        if (i >= _rows.length) {
                          return const Padding(
                            padding: EdgeInsets.all(14),
                            child: Center(child: SizedBox(width: 20,
                                height: 20, child: CircularProgressIndicator(
                                    strokeWidth: 2))),
                          );
                        }
                        return _TicketTile(
                            t: _rows[i], ar: ar, onChanged: () {
                          _loadMeta();
                          _load(reset: true);
                        });
                      },
                    ),
                  )),
      ]),
    );
  }

  Widget _kpi(String label, dynamic value, Color color) => Container(
    margin: const EdgeInsetsDirectional.only(end: 8),
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
    decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: .5))),
    child: Column(mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${(value as num?)?.toInt() ?? 0}', style: TextStyle(
          fontSize: 17, fontWeight: FontWeight.w900, color: color)),
      Text(label, style: TextStyle(fontSize: 9.5,
          color: Colors.white.withValues(alpha: .7),
          fontWeight: FontWeight.w700)),
    ]),
  );

  Widget _statusChip(String label, String value) {
    final sel = _status == value;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 11,
            fontWeight: FontWeight.w800, color: UellowColors.darkBrown)),
        selected: sel,
        showCheckmark: false,
        selectedColor: UellowColors.yellow,
        backgroundColor: Colors.white,
        side: BorderSide.none,
        visualDensity: VisualDensity.compact,
        onSelected: (_) {
          _status = value;
          _stageId = null;
          _load(reset: true);
        },
      ),
    );
  }

  Widget _stageChip(String label, int? value, Map? stage) {
    final sel = _stageId == value;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: ChoiceChip(
        label: Text(label, style: TextStyle(fontSize: 10.5,
            fontWeight: FontWeight.w800,
            color: sel ? UellowColors.darkBrown : Colors.white)),
        selected: sel,
        showCheckmark: false,
        selectedColor: UellowColors.yellow,
        backgroundColor: Colors.white.withValues(alpha: .12),
        side: BorderSide.none,
        visualDensity: VisualDensity.compact,
        onSelected: (_) {
          _stageId = value;
          _load(reset: true);
        },
      ),
    );
  }
}

class _TicketTile extends StatelessWidget {
  const _TicketTile({required this.t, required this.ar, required this.onChanged});
  final Map<String, dynamic> t;
  final bool ar;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final sc = _stageColor(t);
    final prio = (t['priority'] ?? '0').toString();
    final pc = _priorityColors[prio] ?? const Color(0xFF9CA3AF);
    final assignee = (t['assignee'] ?? '').toString();
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => AdminHelpdeskTicketScreen(
              ticketId: (t['id'] as num).toInt()))).then((_) => onChanged()),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
        decoration: BoxDecoration(color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFECECEC))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (prio == '3' || prio == '2')
              Padding(padding: const EdgeInsetsDirectional.only(end: 5),
                  child: Icon(Icons.priority_high_rounded, size: 14, color: pc)),
            Text('#${t['ref'] ?? t['id']}', style: const TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w900,
                color: UellowColors.darkBrown)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
              decoration: BoxDecoration(color: sc.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(6)),
              child: Text(t['stage']?.toString() ?? '', style: TextStyle(
                  fontSize: 9.5, fontWeight: FontWeight.w800, color: sc)),
            ),
            const Spacer(),
            Text(t['created']?.toString() ?? '', style: const TextStyle(
                fontSize: 9.5, color: UellowColors.muted)),
          ]),
          const SizedBox(height: 6),
          Text(t['subject']?.toString() ?? '', maxLines: 2,
              overflow: TextOverflow.ellipsis, style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w700,
                  color: UellowColors.text)),
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.person_outline_rounded, size: 13,
                color: UellowColors.muted),
            const SizedBox(width: 4),
            Expanded(child: Text(
                '${t['customer'] ?? ''}'
                '${(t['phone'] ?? '').toString().isNotEmpty ? ' · ${t['phone']}' : ''}',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: UellowColors.text))),
            if (assignee.isNotEmpty) ...[
              const Icon(Icons.support_agent_rounded, size: 13,
                  color: UellowColors.muted),
              const SizedBox(width: 3),
              Text(assignee, style: const TextStyle(fontSize: 10,
                  color: UellowColors.muted, fontWeight: FontWeight.w700)),
            ] else
              Text(ar ? 'غير مُسندة' : 'Unassigned', style: const TextStyle(
                  fontSize: 10, color: Color(0xFFF59E0B),
                  fontWeight: FontWeight.w800)),
          ]),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// DETAIL SCREEN
// ═══════════════════════════════════════════════════════════════════════
class AdminHelpdeskTicketScreen extends StatefulWidget {
  const AdminHelpdeskTicketScreen({super.key, required this.ticketId});
  final int ticketId;
  @override
  State<AdminHelpdeskTicketScreen> createState() =>
      _AdminHelpdeskTicketScreenState();
}

class _AdminHelpdeskTicketScreenState extends State<AdminHelpdeskTicketScreen> {
  late Future<Map<String, dynamic>> _future;
  final _replyCtl = TextEditingController();
  bool _internal = false;
  bool _busy = false;

  List<Map<String, dynamic>> _stages = const [];
  List<Map<String, dynamic>> _agents = const [];

  @override
  void initState() {
    super.initState();
    _future = AdminApi.instance.ticketDetail(widget.ticketId);
    _loadMeta();
  }

  @override
  void dispose() {
    _replyCtl.dispose();
    super.dispose();
  }

  Future<void> _loadMeta() async {
    try {
      final m = await AdminApi.instance.helpdeskMeta();
      _stages = ((m['stages'] as List?) ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>()).toList();
    } catch (_) {}
    try {
      _agents = await AdminApi.instance.helpdeskAgents();
    } catch (_) {}
    if (mounted) setState(() {});
  }

  void _reload() => setState(() {
        _future = AdminApi.instance.ticketDetail(widget.ticketId);
      });

  Future<void> _run(Future<Map<String, dynamic>> Function() op,
      String okMsg) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await op();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(okMsg)));
        _reload();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: UellowColors.danger));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF412402),
        foregroundColor: UellowColors.yellow,
        iconTheme: const IconThemeData(color: UellowColors.yellow),
        title: Text(ar ? 'تفاصيل التذكرة' : 'Ticket details',
            style: const TextStyle(fontSize: 16,
                fontWeight: FontWeight.w900, color: UellowColors.yellow)),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (_, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(
                color: UellowColors.darkBrown));
          }
          final d = snap.data;
          if (d == null || d.isEmpty) {
            return Center(child: Text(ar ? 'تعذر التحميل' : 'Failed to load'));
          }
          final sc = _stageColor(d);
          final prio = (d['priority'] ?? '0').toString();
          final order = (d['order'] as Map?) ?? const {};
          final thread = ((d['thread'] as List?) ?? const [])
              .map((e) => (e as Map).cast<String, dynamic>()).toList();
          return ListView(padding: const EdgeInsets.all(14), children: [
            _card(children: [
              Row(children: [
                Text('#${d['ref'] ?? d['id']}', style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w900,
                    color: UellowColors.darkBrown)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: sc.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(7)),
                  child: Text(d['stage']?.toString() ?? '', style: TextStyle(
                      fontSize: 10.5, fontWeight: FontWeight.w800, color: sc)),
                ),
                const Spacer(),
                Text(_bil(d['priority_label'], ar), style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w800,
                    color: _priorityColors[prio] ?? UellowColors.muted)),
              ]),
              const SizedBox(height: 8),
              Text(d['subject']?.toString() ?? '', style: const TextStyle(
                  fontSize: 14.5, fontWeight: FontWeight.w900,
                  color: UellowColors.text)),
              const SizedBox(height: 4),
              Text('${d['team'] ?? ''} · ${d['created'] ?? ''}',
                  style: const TextStyle(fontSize: 10.5,
                      color: UellowColors.muted)),
            ]),
            _card(title: ar ? '👤 العميل' : '👤 Customer', children: [
              _kv(ar ? 'الاسم' : 'Name', d['customer']?.toString() ?? ''),
              if ((d['phone'] ?? '').toString().isNotEmpty)
                _kv(ar ? 'الهاتف' : 'Phone', d['phone'].toString()),
              if ((d['email'] ?? '').toString().isNotEmpty)
                _kv('Email', d['email'].toString()),
              if ((d['assignee'] ?? '').toString().isNotEmpty)
                _kv(ar ? 'المسؤول' : 'Agent', d['assignee'].toString()),
              if ((order['name'] ?? '').toString().isNotEmpty)
                _kv(ar ? 'الطلب' : 'Order', order['name'].toString()),
            ]),
            if (_plain(d['description']?.toString() ?? '').isNotEmpty)
              _card(title: ar ? '📝 الوصف' : '📝 Description', children: [
                Text(_plain(d['description'].toString()),
                    style: const TextStyle(fontSize: 12, height: 1.4,
                        color: UellowColors.text)),
              ]),
            _card(title: ar ? '💬 المحادثة' : '💬 Conversation', children: [
              if (thread.isEmpty)
                Text(ar ? 'لا توجد رسائل بعد' : 'No messages yet',
                    style: const TextStyle(fontSize: 11,
                        color: UellowColors.muted))
              else
                for (final m in thread) _bubble(m, ar),
            ]),
            _replyBox(ar),
            _actionCard(d, ar),
            const SizedBox(height: 24),
          ]);
        },
      ),
    );
  }

  Widget _bubble(Map<String, dynamic> m, bool ar) {
    final note = m['is_note'] == true;
    final bg = note ? const Color(0xFFFFF7E0) : const Color(0xFFF1F5F9);
    final border = note ? const Color(0xFFF5C320) : const Color(0xFFE2E8F0);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
      decoration: BoxDecoration(color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(m['author']?.toString() ?? '', style: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w900,
              color: UellowColors.darkBrown)),
          const SizedBox(width: 6),
          if (note)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                  color: const Color(0xFFF5C320).withValues(alpha: .25),
                  borderRadius: BorderRadius.circular(5)),
              child: Text(ar ? 'ملاحظة داخلية' : 'Internal note',
                  style: const TextStyle(fontSize: 8.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF8A6D00))),
            ),
          const Spacer(),
          Text(m['date']?.toString() ?? '', style: const TextStyle(
              fontSize: 9, color: UellowColors.muted)),
        ]),
        const SizedBox(height: 4),
        Text(_plain(m['body']?.toString() ?? ''),
            style: const TextStyle(fontSize: 11.5, height: 1.35,
                color: UellowColors.text)),
      ]),
    );
  }

  Widget _replyBox(bool ar) => _card(
      title: ar ? '✍️ الرد' : '✍️ Reply', children: [
    TextField(
      controller: _replyCtl,
      maxLines: 4, minLines: 2,
      style: const TextStyle(fontSize: 12.5),
      decoration: InputDecoration(
        hintText: ar ? 'اكتب ردك للعميل أو ملاحظة داخلية…'
                     : 'Reply to the customer or write an internal note…',
        hintStyle: const TextStyle(fontSize: 11.5, color: UellowColors.muted),
        filled: true, fillColor: const Color(0xFFF7F8FA),
        contentPadding: const EdgeInsets.all(12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none),
      ),
    ),
    const SizedBox(height: 8),
    Row(children: [
      Expanded(child: GestureDetector(
        onTap: () => setState(() => _internal = !_internal),
        child: Row(children: [
          Icon(_internal ? Icons.lock_rounded : Icons.lock_open_rounded,
              size: 16,
              color: _internal ? const Color(0xFFE11D48) : UellowColors.muted),
          const SizedBox(width: 5),
          Flexible(child: Text(
              _internal
                  ? (ar ? 'ملاحظة داخلية (لا تُرسل للعميل)'
                        : 'Internal note (not sent to customer)')
                  : (ar ? 'رد علني للعميل' : 'Public reply to customer'),
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700,
                  color: _internal ? const Color(0xFFE11D48)
                                   : UellowColors.muted))),
          Switch(value: _internal, activeColor: const Color(0xFFE11D48),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (v) => setState(() => _internal = v)),
        ]),
      )),
    ]),
    const SizedBox(height: 6),
    SizedBox(width: double.infinity, child: ElevatedButton.icon(
      onPressed: _busy ? null : () {
        final body = _replyCtl.text.trim();
        if (body.isEmpty) return;
        _run(() => AdminApi.instance.ticketReply(
                widget.ticketId, body, internal: _internal),
            _internal ? (ar ? 'تمت إضافة الملاحظة' : 'Note added')
                      : (ar ? 'تم إرسال الرد' : 'Reply sent'))
            .then((_) => _replyCtl.clear());
      },
      icon: const Icon(Icons.send_rounded, size: 18),
      label: Text(_internal ? (ar ? 'حفظ الملاحظة' : 'Save note')
                            : (ar ? 'إرسال الرد' : 'Send reply'),
          style: const TextStyle(fontWeight: FontWeight.w900)),
      style: ElevatedButton.styleFrom(
        backgroundColor: _internal ? const Color(0xFFE11D48)
                                   : UellowColors.darkBrown,
        foregroundColor: Colors.white, elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
      ),
    )),
  ]);

  Widget _actionCard(Map<String, dynamic> d, bool ar) => _card(
      title: ar ? '⚙️ إجراءات' : '⚙️ Actions', children: [
    if (_busy) const Padding(padding: EdgeInsets.only(bottom: 8),
        child: LinearProgressIndicator(minHeight: 2)),
    Row(children: [
      Expanded(child: _actBtn(
          Icons.swap_horiz_rounded, ar ? 'تغيير المرحلة' : 'Change stage',
          UellowColors.darkBrown, () => _openStagePicker(ar))),
      const SizedBox(width: 8),
      Expanded(child: _actBtn(
          Icons.support_agent_rounded, ar ? 'إسناد' : 'Assign',
          const Color(0xFF2563EB), () => _openAssignPicker(ar))),
    ]),
  ]);

  Widget _actBtn(IconData icon, String label, Color color, VoidCallback onTap) =>
      ElevatedButton.icon(
        onPressed: _busy ? null : onTap,
        icon: Icon(icon, size: 17),
        label: Text(label, style: const TextStyle(fontSize: 12,
            fontWeight: FontWeight.w900)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color, foregroundColor: Colors.white, elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 11),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
      );

  Future<void> _openStagePicker(bool ar) async {
    if (_stages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ar ? 'جارٍ تحميل المراحل…' : 'Loading stages…')));
      await _loadMeta();
    }
    if (!mounted) return;
    final picked = await showModalBottomSheet<int>(
      context: context, backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius:
          BorderRadius.vertical(top: Radius.circular(18))),
      builder: (c) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min,
          children: [
        Padding(padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
            child: Row(children: [Text(ar ? 'اختر المرحلة' : 'Choose stage',
                style: UT.h3)])),
        for (final s in _stages)
          ListTile(
            leading: Icon(s['fold'] == true ? Icons.check_circle_outline_rounded
                : Icons.radio_button_unchecked_rounded,
                color: s['fold'] == true ? const Color(0xFF10B981)
                    : const Color(0xFF2563EB), size: 20),
            title: Text(s['name']?.toString() ?? '',
                style: const TextStyle(fontWeight: FontWeight.w700,
                    fontSize: 13)),
            onTap: () => Navigator.pop(c, (s['id'] as num).toInt()),
          ),
        const SizedBox(height: 8),
      ])),
    );
    if (picked != null) {
      _run(() => AdminApi.instance.ticketStage(widget.ticketId, picked),
          ar ? 'تم تغيير المرحلة' : 'Stage updated');
    }
  }

  Future<void> _openAssignPicker(bool ar) async {
    if (_agents.isEmpty) await _loadMeta();
    if (!mounted) return;
    final picked = await showModalBottomSheet<dynamic>(
      context: context, backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius:
          BorderRadius.vertical(top: Radius.circular(18))),
      builder: (c) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min,
          children: [
        Padding(padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
            child: Row(children: [Text(ar ? 'إسناد التذكرة' : 'Assign ticket',
                style: UT.h3)])),
        ListTile(
          leading: const Icon(Icons.person_pin_circle_rounded,
              color: Color(0xFF2563EB), size: 20),
          title: Text(ar ? 'أسند لي' : 'Assign to me',
              style: const TextStyle(fontWeight: FontWeight.w800,
                  fontSize: 13)),
          onTap: () => Navigator.pop(c, 'me'),
        ),
        ListTile(
          leading: const Icon(Icons.person_off_rounded,
              color: UellowColors.muted, size: 20),
          title: Text(ar ? 'إلغاء الإسناد' : 'Unassign',
              style: const TextStyle(fontWeight: FontWeight.w700,
                  fontSize: 13)),
          onTap: () => Navigator.pop(c, 0),
        ),
        if (_agents.isNotEmpty) const Divider(height: 1),
        Flexible(child: ListView(shrinkWrap: true, children: [
          for (final a in _agents)
            ListTile(
              leading: const Icon(Icons.support_agent_rounded,
                  color: UellowColors.darkBrown, size: 20),
              title: Text(a['name']?.toString() ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w700,
                      fontSize: 13)),
              onTap: () => Navigator.pop(c, (a['id'] as num).toInt()),
            ),
        ])),
        const SizedBox(height: 8),
      ])),
    );
    if (picked != null) {
      _run(() => AdminApi.instance.ticketAssign(widget.ticketId, picked),
          ar ? 'تم تحديث الإسناد' : 'Assignment updated');
    }
  }

  Widget _card({String? title, required List<Widget> children}) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
    decoration: BoxDecoration(color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFECECEC))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (title != null) ...[
        Text(title, style: UT.h3),
        const SizedBox(height: 8),
      ],
      ...children,
    ]),
  );

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 92, child: Text(k, style: const TextStyle(
          fontSize: 11, color: UellowColors.muted,
          fontWeight: FontWeight.w700))),
      Expanded(child: Text(v, style: const TextStyle(fontSize: 11.5,
          fontWeight: FontWeight.w600))),
    ]),
  );
}
