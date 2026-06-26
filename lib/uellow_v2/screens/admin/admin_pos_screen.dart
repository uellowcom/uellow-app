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
  late final TabController _tabs = TabController(length: 2, vsync: this);

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
          ],
        ),
      ),
      body: TabBarView(controller: _tabs, children: const [
        _SessionsTab(),
        _PosOrdersTab(),
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
      final d = await AdminApi.instance.posSessions(page: _page);
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

class _SessionOrdersScreen extends StatelessWidget {
  const _SessionOrdersScreen({required this.sessionId, required this.title});
  final int sessionId;
  final String title;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF2F3F5),
    appBar: AppBar(
      backgroundColor: const Color(0xFF412402),
      foregroundColor: UellowColors.yellow,
      iconTheme: const IconThemeData(color: UellowColors.yellow),
      title: Text(title, style: const TextStyle(fontSize: 15,
          fontWeight: FontWeight.w900, color: UellowColors.yellow)),
    ),
    body: _PosOrdersTab(sessionId: sessionId),
  );
}
