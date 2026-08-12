// =============================================================================
// AdminPosScreen (v2.2.10) — POS logbook: sessions (open/close, cash,
// totals) + sales feed, with per-session drill-down.
// =============================================================================
import 'package:flutter/material.dart';

import '../../../api/uellow_api.dart';
import '../../services/admin_mode.dart';
import '../../theme/uellow_theme.dart';

class AdminPosScreen extends StatefulWidget {
  const AdminPosScreen({super.key});
  @override
  State<AdminPosScreen> createState() => _AdminPosScreenState();
}

class _AdminPosScreenState extends State<AdminPosScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
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
        title: Text(ar ? '🧾 سجل نقاط البيع' : '🧾 POS Log',
            style: const TextStyle(fontSize: 16,
                fontWeight: FontWeight.w900, color: UellowColors.yellow)),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: UellowColors.yellow,
          labelColor: UellowColors.yellow,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontSize: 12.5,
              fontWeight: FontWeight.w800),
          tabs: [
            Tab(text: ar ? 'اليوميات' : 'Sessions'),
            Tab(text: ar ? 'العمليات' : 'Sales'),
            Tab(text: ar ? 'التقارير' : 'Reports'),
          ],
        ),
      ),
      body: TabBarView(controller: _tabs, children: const [
        _SessionsTab(),
        _PosOrdersTab(),
        _ReportTab(),
      ]),
    );
  }
}

// ─── sessions ────────────────────────────────────────────────────────────
class _SessionsTab extends StatefulWidget {
  const _SessionsTab();
  @override
  State<_SessionsTab> createState() => _SessionsTabState();
}

class _SessionsTabState extends State<_SessionsTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  final _scroll = ScrollController();
  final List<Map<String, dynamic>> _rows = [];
  int _page = 1, _pages = 1;
  bool _loading = false;
  String _state = '';
  DateTime? _from;
  DateTime? _to;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
    _scroll.addListener(() {
      if (_scroll.position.pixels >
              _scroll.position.maxScrollExtent - 300 &&
          !_loading && _page < _pages) {
        _page += 1;
        _load();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      _page = 1;
      _rows.clear();
    }
    setState(() => _loading = true);
    try {
      final d = await AdminApi.instance.posSessions(
          page: _page, state: _state,
          dateFrom: _fmt(_from), dateTo: _fmt(_to));
      _pages = (d['pages'] as num?)?.toInt() ?? 1;
      _rows.addAll(((d['sessions'] as List?) ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>()));
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final ar = UellowApi.instance.lang == 'ar';
    return Column(children: [
      _filterBar(ar),
      Expanded(child: _body(ar)),
    ]);
  }

  String? _fmt(DateTime? d) => d == null
      ? null
      : '${d.year}-${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';

  Widget _filterBar(bool ar) {
    Widget chip(String label, String val) {
      final on = _state == val;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: GestureDetector(
          onTap: () {
            setState(() => _state = val);
            _load(reset: true);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
                color: on ? UellowColors.darkBrown : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: on ? UellowColors.darkBrown
                        : const Color(0xFFE4D8BF))),
            child: Text(label, style: TextStyle(fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: on ? UellowColors.yellow : UellowColors.darkBrown)),
          ),
        ),
      );
    }
    final hasDate = _from != null && _to != null;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              chip(ar ? 'الكل' : 'All', ''),
              chip(ar ? 'مفتوحة' : 'Open', 'opened'),
              chip(ar ? 'مغلقة' : 'Closed', 'closed'),
            ]),
          ),
        ),
        GestureDetector(
          onTap: () async {
            final r = await showDateRangePicker(
              context: context,
              firstDate: DateTime(2023),
              lastDate: DateTime.now().add(const Duration(days: 1)),
              initialDateRange: hasDate
                  ? DateTimeRange(start: _from!, end: _to!) : null,
            );
            if (r != null) {
              setState(() {
                _from = r.start;
                _to = r.end;
              });
              _load(reset: true);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
                color: hasDate ? const Color(0xFFFFF7DE) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE4D8BF))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.date_range_rounded, size: 15,
                  color: UellowColors.darkBrown),
              const SizedBox(width: 4),
              Text(hasDate ? '${_fmt(_from)} → ${_fmt(_to)}'
                  : (ar ? 'التاريخ' : 'Date'),
                  style: const TextStyle(fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: UellowColors.darkBrown)),
              if (hasDate) ...[
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _from = null;
                      _to = null;
                    });
                    _load(reset: true);
                  },
                  child: const Icon(Icons.close_rounded, size: 14,
                      color: UellowColors.muted),
                ),
              ],
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _body(bool ar) {
    if (_rows.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator(
          color: UellowColors.darkBrown));
    }
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        itemCount: _rows.length + (_loading ? 1 : 0),
        itemBuilder: (_, i) {
          if (i >= _rows.length) {
            return const Padding(padding: EdgeInsets.all(14),
                child: Center(child: SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))));
          }
          final s = _rows[i];
          final m = (s['total'] as Map?) ?? const {};
          final open = s['state'] == 'opened'
              || s['state'] == 'opening_control';
          return InkWell(
            onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => _SessionOrdersScreen(
                    sessionId: (s['id'] as num).toInt(),
                    title: s['name']?.toString() ?? ''))),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              margin: const EdgeInsets.only(bottom: 9),
              padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
              decoration: BoxDecoration(color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: open
                      ? const Color(0xFF10B981).withValues(alpha: .4)
                      : const Color(0xFFECECEC))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(children: [
                  Container(width: 9, height: 9, decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: open ? const Color(0xFF10B981)
                          : const Color(0xFF9CA3AF))),
                  const SizedBox(width: 7),
                  Expanded(child: Text(s['name']?.toString() ?? '',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: UellowColors.darkBrown))),
                  Text('${(m['amount'] as num? ?? 0).toStringAsFixed((m['digits'] as num?)?.toInt() ?? 3)} ${m['symbol'] ?? ''}',
                      style: const TextStyle(fontSize: 13.5,
                          fontWeight: FontWeight.w900,
                          color: UellowColors.darkBrown)),
                ]),
                const SizedBox(height: 6),
                Text('${s['config'] ?? ''} · ${s['user'] ?? ''}'
                    ' · ${s['orders'] ?? 0} ${ar ? 'عملية' : 'sales'}'
                    '${s['items'] != null ? ' · ${s['items']} ${ar ? 'صنف' : 'items'}' : ''}',
                    style: const TextStyle(fontSize: 10.5,
                        color: UellowColors.muted)),
                const SizedBox(height: 6),
                _profitPill(ar, s['profit'] as Map?, s['margin_pct'],
                    s['cost'] as Map?),
                const SizedBox(height: 3),
                Row(children: [
                  const Icon(Icons.play_circle_outline_rounded, size: 12,
                      color: Color(0xFF10B981)),
                  const SizedBox(width: 3),
                  Text(s['start_at']?.toString() ?? '—',
                      style: const TextStyle(fontSize: 10,
                          color: UellowColors.muted)),
                  const SizedBox(width: 10),
                  if (!open) ...[
                    const Icon(Icons.stop_circle_outlined, size: 12,
                        color: Color(0xFFEF4444)),
                    const SizedBox(width: 3),
                    Text(s['stop_at']?.toString() ?? '—',
                        style: const TextStyle(fontSize: 10,
                            color: UellowColors.muted)),
                  ] else Text(ar ? '● مفتوحة الآن' : '● open now',
                      style: const TextStyle(fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF10B981))),
                ]),
              ]),
            ),
          );
        },
      ),
    );
  }
}

// ─── sales feed (all or one session) ─────────────────────────────────────
class _PosOrdersTab extends StatefulWidget {
  const _PosOrdersTab({this.sessionId});
  final int? sessionId;
  @override
  State<_PosOrdersTab> createState() => _PosOrdersTabState();
}

class _PosOrdersTabState extends State<_PosOrdersTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  final _scroll = ScrollController();
  final List<Map<String, dynamic>> _rows = [];
  int _page = 1, _pages = 1;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
    _scroll.addListener(() {
      if (_scroll.position.pixels >
              _scroll.position.maxScrollExtent - 300 &&
          !_loading && _page < _pages) {
        _page += 1;
        _load();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      _page = 1;
      _rows.clear();
    }
    setState(() => _loading = true);
    try {
      final d = await AdminApi.instance
          .posOrders(page: _page, sessionId: widget.sessionId);
      _pages = (d['pages'] as num?)?.toInt() ?? 1;
      _rows.addAll(((d['orders'] as List?) ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>()));
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final ar = UellowApi.instance.lang == 'ar';
    if (_rows.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator(
          color: UellowColors.darkBrown));
    }
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        itemCount: _rows.length + (_loading ? 1 : 0),
        itemBuilder: (_, i) {
          if (i >= _rows.length) {
            return const Padding(padding: EdgeInsets.all(14),
                child: Center(child: SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))));
          }
          final o = _rows[i];
          final m = (o['total'] as Map?) ?? const {};
          final pays = (o['payments'] as List?) ?? const [];
          final lines = (o['lines'] as List?) ?? const [];
          return Container(
            margin: const EdgeInsets.only(bottom: 9),
            decoration: BoxDecoration(color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFECECEC))),
            child: Theme(
              data: Theme.of(context)
                  .copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(
                    horizontal: 13, vertical: 2),
                childrenPadding: const EdgeInsets.fromLTRB(13, 0, 13, 10),
                title: Row(children: [
                  Expanded(child: Text(o['name']?.toString() ?? '',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5,
                          fontWeight: FontWeight.w900,
                          color: UellowColors.darkBrown))),
                  Text('${(m['amount'] as num? ?? 0).toStringAsFixed((m['digits'] as num?)?.toInt() ?? 3)} ${m['symbol'] ?? ''}',
                      style: const TextStyle(fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: UellowColors.darkBrown)),
                ]),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(
                      '${o['date'] ?? ''} · ${o['items'] ?? 0} ${ar ? 'منتج' : 'items'}'
                      '${pays.isNotEmpty ? ' · ${pays.map((p) => (p as Map)['method']).join('+')}' : ''}',
                      style: const TextStyle(fontSize: 10,
                          color: UellowColors.muted)),
                  if (o['profit'] != null) ...[
                    const SizedBox(height: 5),
                    _profitPill(ar, o['profit'] as Map?, o['margin_pct'],
                        o['cost'] as Map?),
                  ],
                ]),
                children: [
                  for (final l in lines) Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(children: [
                      Expanded(child: Text(
                          '${(l as Map)['name'] ?? ''}',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10.5))),
                      if (l['margin'] != null)
                        Text('${ar ? 'ربح' : 'P'} ${l['margin']}  ',
                            style: TextStyle(fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: (l['margin'] as num? ?? 0) < 0
                                    ? const Color(0xFFEF4444)
                                    : const Color(0xFF059669))),
                      Text('×${(l['qty'] as num? ?? 0).toStringAsFixed(0)}'
                          '  ${l['total'] ?? 0}',
                          style: const TextStyle(fontSize: 10.5,
                              fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── reports (aggregate KPIs over a date range) ──────────────────────────
class _ReportTab extends StatefulWidget {
  const _ReportTab();
  @override
  State<_ReportTab> createState() => _ReportTabState();
}

class _ReportTabState extends State<_ReportTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  int _days = 30;
  Map<String, dynamic>? _data;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _data = await AdminApi.instance.posReport(days: _days);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final ar = UellowApi.instance.lang == 'ar';
    if (_data == null && _loading) {
      return const Center(child: CircularProgressIndicator(
          color: UellowColors.darkBrown));
    }
    final d = _data;
    if (d == null) {
      return Center(child: Text(ar ? 'تعذر التحميل' : 'Failed to load'));
    }
    final k = (d['kpi'] as Map?) ?? const {};
    final byPay = (d['by_payment'] as List?) ?? const [];
    final byCash = (d['by_cashier'] as List?) ?? const [];
    final top = (d['top_products'] as List?) ?? const [];
    final cur = d['currency']?.toString() ?? 'KD';
    num amt(dynamic m) => (m is Map ? (m['amount'] as num? ?? 0) : 0);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
        // period selector
        Row(children: [
          Text(ar ? 'الفترة:' : 'Period:', style: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w800,
              color: UellowColors.muted)),
          const SizedBox(width: 8),
          for (final n in const [7, 30, 90, 365]) Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text(n == 365 ? (ar ? 'سنة' : '1y') : '$n${ar ? 'ي' : 'd'}',
                  style: const TextStyle(fontSize: 11.5,
                      fontWeight: FontWeight.w800)),
              selected: _days == n,
              selectedColor: UellowColors.yellow,
              onSelected: (_) { setState(() => _days = n); _load(); },
            ),
          ),
          if (_loading) const Padding(padding: EdgeInsets.only(left: 6),
              child: SizedBox(width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2))),
        ]),
        const SizedBox(height: 12),
        // headline KPIs
        Row(children: [
          _kpi(ar ? 'المبيعات' : 'Sales',
              '${amt(k['sales']).toStringAsFixed(3)} $cur',
              const Color(0xFF412402)),
          const SizedBox(width: 10),
          _kpi(ar ? 'الربح' : 'Profit',
              '${amt(k['profit']).toStringAsFixed(3)} $cur',
              (amt(k['profit']) < 0)
                  ? const Color(0xFFEF4444) : const Color(0xFF059669),
              sub: '${k['margin_pct'] ?? 0}%'),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _kpi(ar ? 'العمليات' : 'Orders', '${k['orders'] ?? 0}',
              const Color(0xFF2563EB)),
          const SizedBox(width: 10),
          _kpi(ar ? 'الأصناف' : 'Items', '${k['items'] ?? 0}',
              const Color(0xFF7C3AED)),
          const SizedBox(width: 10),
          _kpi(ar ? 'متوسط السلة' : 'Avg basket',
              amt(k['avg_basket']).toStringAsFixed(3),
              const Color(0xFF0D9488)),
        ]),
        if ((k['refunds_count'] as num? ?? 0) != 0) ...[
          const SizedBox(height: 10),
          _kpi(ar ? 'المرتجعات' : 'Refunds',
              '${amt(k['refunds']).toStringAsFixed(3)} $cur '
              '(${k['refunds_count']})', const Color(0xFFEF4444)),
        ],
        const SizedBox(height: 16),
        if (byPay.isNotEmpty)
          _section(ar ? '💳 حسب طريقة الدفع' : '💳 By payment method', [
            for (final p in byPay) _line((p as Map)['method']?.toString() ?? '',
                '${(p['amount'] as num? ?? 0).toStringAsFixed(3)} $cur'),
          ]),
        if (byCash.isNotEmpty)
          _section(ar ? '👤 حسب الكاشير' : '👤 By cashier', [
            for (final c in byCash) _line(
                '${(c as Map)['name'] ?? ''} · ${c['orders'] ?? 0}',
                '${ar ? 'ربح' : 'P'} ${(c['profit'] as num? ?? 0).toStringAsFixed(3)} / '
                '${(c['sales'] as num? ?? 0).toStringAsFixed(3)}'),
          ]),
        if (top.isNotEmpty)
          _section(ar ? '🏆 الأكثر ربحًا' : '🏆 Top by profit', [
            for (final p in top) _line(
                '${(p as Map)['name'] ?? ''} ×${p['qty'] ?? 0}',
                '${(p['profit'] as num? ?? 0).toStringAsFixed(3)} $cur'),
          ]),
      ]),
    );
  }

  Widget _kpi(String label, String value, Color color, {String? sub}) =>
      Expanded(child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 12),
        decoration: BoxDecoration(color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFECECEC))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 10.5,
              color: UellowColors.muted, fontWeight: FontWeight.w700)),
          const SizedBox(height: 5),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
              child: Text(value, style: TextStyle(fontSize: 15,
                  fontWeight: FontWeight.w900, color: color))),
          if (sub != null) Text(sub, style: TextStyle(fontSize: 10.5,
              fontWeight: FontWeight.w800, color: color)),
        ]),
      ));

  Widget _section(String title, List<Widget> children) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
    decoration: BoxDecoration(color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFECECEC))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 12.5,
          fontWeight: FontWeight.w900, color: UellowColors.darkBrown)),
      const SizedBox(height: 8),
      ...children,
    ]),
  );

  Widget _line(String left, String right) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Expanded(child: Text(left, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11.5))),
      const SizedBox(width: 8),
      Text(right, style: const TextStyle(fontSize: 11.5,
          fontWeight: FontWeight.w800, color: UellowColors.darkBrown)),
    ]),
  );
}

// Profit pill — green when positive, red on a loss; shows margin % + cost.
Widget _profitPill(bool ar, Map? profit, dynamic marginPct, [Map? cost]) {
  final v = (profit?['amount'] as num?) ?? 0;
  final loss = v < 0;
  final col = loss ? const Color(0xFFEF4444) : const Color(0xFF059669);
  final pct = (marginPct is num) ? marginPct : null;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
        color: col.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(8)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(loss ? Icons.trending_down_rounded : Icons.trending_up_rounded,
          size: 13, color: col),
      const SizedBox(width: 4),
      Text('${ar ? 'الربح' : 'Profit'} '
          '${v.toStringAsFixed((profit?['digits'] as num?)?.toInt() ?? 3)} '
          '${profit?['symbol'] ?? ''}',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900,
              color: col)),
      if (pct != null) Text('  ·  ${pct.toStringAsFixed(1)}%',
          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700,
              color: col)),
      if (cost != null && (cost['amount'] as num? ?? 0) != 0)
        Text('  ·  ${ar ? 'تكلفة' : 'cost'} '
            '${(cost['amount'] as num? ?? 0).toStringAsFixed((cost['digits'] as num?)?.toInt() ?? 3)}',
            style: const TextStyle(fontSize: 10,
                color: UellowColors.muted)),
    ]),
  );
}

class _SessionOrdersScreen extends StatefulWidget {
  const _SessionOrdersScreen({required this.sessionId, required this.title});
  final int sessionId;
  final String title;
  @override
  State<_SessionOrdersScreen> createState() => _SessionOrdersScreenState();
}

class _SessionOrdersScreenState extends State<_SessionOrdersScreen> {
  Map<String, dynamic>? _d;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await AdminApi.instance.posSessionDetail(widget.sessionId);
      if (mounted) setState(() { _d = d; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _m(dynamic x) {
    if (x is Map) {
      final a = (x['amount'] as num? ?? 0)
          .toStringAsFixed((x['digits'] as num?)?.toInt() ?? 3);
      return '$a ${x['symbol'] ?? ''}'.trim();
    }
    return x?.toString() ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF412402),
        foregroundColor: UellowColors.yellow,
        iconTheme: const IconThemeData(color: UellowColors.yellow),
        title: Text(widget.title, style: const TextStyle(fontSize: 15,
            fontWeight: FontWeight.w900, color: UellowColors.yellow)),
      ),
      body: Column(children: [
        if (_loading)
          const LinearProgressIndicator(minHeight: 2)
        else if (_d != null)
          _SessionStatsHeader(d: _d!, fmt: _m),
        Expanded(child: _PosOrdersTab(sessionId: widget.sessionId)),
      ]),
    );
  }
}

// Stats header shown atop a session: cash / KNET / sales + products sold.
class _SessionStatsHeader extends StatelessWidget {
  const _SessionStatsHeader({required this.d, required this.fmt});
  final Map<String, dynamic> d;
  final String Function(dynamic) fmt;

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    final sess = (d['session'] as Map?) ?? const {};
    final payments = (d['payments'] as List?) ?? const [];
    final products = (d['products'] as List?) ?? const [];
    Widget stat(String label, String val, Color c, IconData ic) => Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFECECEC))),
        child: Column(children: [
          Icon(ic, size: 18, color: c),
          const SizedBox(height: 4),
          Text(val, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900,
                  color: c)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 10,
              color: UellowColors.muted, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
    return Container(
      color: const Color(0xFFF2F3F5),
      padding: const EdgeInsets.fromLTRB(11, 10, 11, 4),
      child: Column(children: [
        Row(children: [
          stat(ar ? 'كاش' : 'Cash', fmt(d['cash_total']),
              const Color(0xFF059669), Icons.payments_rounded),
          stat(ar ? 'كي نت' : 'KNET', fmt(d['knet_total']),
              const Color(0xFF2563EB), Icons.credit_card_rounded),
          stat(ar ? 'المبيعات' : 'Sales', fmt(sess['total']),
              UellowColors.darkBrown, Icons.receipt_long_rounded),
        ]),
        if (payments.length > 2)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              for (final p in payments)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFECECEC))),
                  child: Text(
                      '${(p as Map)['method'] ?? ''}: ${fmt(p['amount'])}',
                      style: const TextStyle(fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: UellowColors.darkBrown)),
                ),
            ]),
          ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFECECEC))),
          child: Theme(
            data:
                Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              initiallyExpanded: true,
              tilePadding: const EdgeInsets.symmetric(horizontal: 12),
              childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              leading: const Icon(Icons.inventory_2_rounded, size: 18,
                  color: UellowColors.darkBrown),
              title: Text(
                  '${ar ? 'المنتجات المباعة' : 'Products sold'} (${products.length})',
                  style: const TextStyle(fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                      color: UellowColors.darkBrown)),
              children: [
                if (products.isEmpty)
                  Padding(padding: const EdgeInsets.all(8),
                      child: Text(ar ? 'لا منتجات' : 'No products',
                          style: const TextStyle(fontSize: 11,
                              color: UellowColors.muted))),
                for (final p in products)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                            color: const Color(0xFFFFF7DE),
                            borderRadius: BorderRadius.circular(6)),
                        child: Text('${(p as Map)['qty'] ?? 0}×',
                            style: const TextStyle(fontSize: 11,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF7A5B00))),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(p['name']?.toString() ?? '',
                          maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5,
                              color: UellowColors.darkBrown))),
                      const SizedBox(width: 6),
                      Text(fmt(p['total']),
                          style: const TextStyle(fontSize: 11.5,
                              fontWeight: FontWeight.w900,
                              color: UellowColors.darkBrown)),
                    ]),
                  ),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}
