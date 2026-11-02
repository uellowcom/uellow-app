// =============================================================================
// AdminPosScreen (v2.2.10) — POS logbook: sessions (open/close, cash,
// totals) + sales feed, with per-session drill-down.
// =============================================================================
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../widgets/admin_console_nav.dart';

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
      bottomNavigationBar: const AdminConsoleNav(current: AdminTab.pos),
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
  const _PosOrdersTab({this.sessionId, this.header});
  final int? sessionId;
  final Widget? header; // v2.2.150 — يُعرض كأول عنصر يتسكرول مع القائمة
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
  // v2.2.145 — فلتر تاريخ شغّال (اليوم/٧ أيام/٣٠ يوم/الكل).
  String _range = 'today';
  // v2.2.161 — بحث + فلتر كاشير/دفع + ملخّص.
  String _q = '';
  String? _cashier, _payMethod;
  String? _customFrom, _customTo;
  Map<String, dynamic>? _summary;
  final _searchCtl = TextEditingController();

  ({String? from, String? to}) _rangeDates() {
    if (_range == 'all') return (from: null, to: null);
    if (_range == 'custom') return (from: _customFrom, to: _customTo);
    final now = DateTime.now();
    String fmt(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    final to = fmt(now);
    DateTime fromD;
    switch (_range) {
      case '7d':  fromD = now.subtract(const Duration(days: 6));  break;
      case '30d': fromD = now.subtract(const Duration(days: 29)); break;
      default:    fromD = now; // today
    }
    return (from: fmt(fromD), to: to);
  }

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
    _searchCtl.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      _page = 1;
      _rows.clear();
    }
    setState(() => _loading = true);
    try {
      // v2.2.145 — لا نطبّق فلتر التاريخ عند تصفّح جلسة محدّدة.
      final r = widget.sessionId != null
          ? (from: null, to: null)
          : _rangeDates();
      final d = await AdminApi.instance.posOrders(
          page: _page, sessionId: widget.sessionId,
          dateFrom: r.from, dateTo: r.to,
          q: _q, cashier: _cashier, paymentMethod: _payMethod);
      _pages = (d['pages'] as num?)?.toInt() ?? 1;
      _summary = (d['summary'] as Map?)?.cast<String, dynamic>();
      _rows.addAll(((d['orders'] as List?) ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>()));
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final ar = UellowApi.instance.lang == 'ar';
    final list = (_rows.isEmpty && _loading)
        ? const Center(child: CircularProgressIndicator(
            color: UellowColors.darkBrown))
        : RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        itemCount: (widget.header != null ? 1 : 0)
            + _rows.length + (_loading ? 1 : 0),
        itemBuilder: (_, idx) {
          // v2.2.150 — الهيدر كأول عنصر يتسكرول مع القائمة
          if (widget.header != null && idx == 0) {
            return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: widget.header!);
          }
          final i = widget.header != null ? idx - 1 : idx;
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
                  // v2.2.145 — صور منتجات مصغّرة متداخلة
                  _posThumbs(lines),
                  const SizedBox(width: 8),
                  Expanded(child: Text(o['name']?.toString() ?? '',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5,
                          fontWeight: FontWeight.w900,
                          color: UellowColors.darkBrown))),
                  Text('${(m['amount'] as num? ?? 0).toStringAsFixed((m['digits'] as num?)?.toInt() ?? 3)} ${m['symbol'] ?? ''}',
                      style: TextStyle(fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: ((m['amount'] as num? ?? 0) < 0)
                              ? const Color(0xFFEF4444)
                              : UellowColors.darkBrown)),
                ]),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(
                      '${(o['cashier'] ?? '').toString().isNotEmpty ? '${o['cashier']} · ' : ''}'
                      '${o['date'] ?? ''} · ${o['items'] ?? 0} ${ar ? 'منتج' : 'items'}',
                      style: const TextStyle(fontSize: 10,
                          color: UellowColors.muted)),
                  if (pays.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Wrap(spacing: 5, runSpacing: 4, children: [
                      for (final p in pays)
                        _payPill((p as Map)['method']?.toString() ?? ''),
                    ]),
                  ],
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
    // v2.2.145 — شيبات فلتر التاريخ أعلى القائمة (تُخفى داخل جلسة محدّدة).
    if (widget.sessionId != null) return list;
    return Column(children: [
      _searchSummary(ar), _filterChips(ar), Expanded(child: list)]);
  }

  // v2.2.145 — صور منتجات مصغّرة متداخلة (حتى 3 + عدّاد «+N»).
  Widget _posThumbs(List lines) {
    final imgs = <String>[];
    for (final l in lines) {
      final im = (l is Map) ? (l['image'] as String?) : null;
      if (im != null && im.isNotEmpty) imgs.add(im);
      if (imgs.length >= 3) break;
    }
    final extra = lines.length - imgs.length;
    if (imgs.isEmpty) {
      return Container(
        width: 34, height: 34,
        decoration: BoxDecoration(
          color: const Color(0xFFF1EEE7),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: const Color(0xFFE9E1D1)),
        ),
        child: const Icon(Icons.shopping_bag_outlined, size: 16,
            color: UellowColors.muted),
      );
    }
    Widget thumb(String url, {bool overlap = false}) => Container(
          width: 34, height: 34,
          margin: EdgeInsetsDirectional.only(start: overlap ? -10 : 0),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: const Color(0xFFE9E1D1)),
          ),
          clipBehavior: Clip.antiAlias,
          child: CachedNetworkImage(
            imageUrl: url.startsWith('http')
                ? url : '${UellowApi.instance.baseUrl}$url',
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => const Icon(
                Icons.image_outlined, size: 15, color: UellowColors.muted),
          ),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < imgs.length; i++) thumb(imgs[i], overlap: i > 0),
      if (extra > 0) Container(
        width: 34, height: 34,
        margin: const EdgeInsetsDirectional.only(start: -10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFE8A800),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: Colors.white, width: 1.5),
        ),
        child: Text('+$extra', style: const TextStyle(fontSize: 10,
            fontWeight: FontWeight.w900, color: Color(0xFF2A1D00))),
      ),
    ]);
  }

  Widget _searchSummary(bool ar) {
    final sm = _summary;
    final tot = (sm?['total'] as Map?);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: Column(children: [
        Row(children: [
          Expanded(child: SizedBox(height: 38, child: TextField(
            controller: _searchCtl,
            textInputAction: TextInputAction.search,
            onSubmitted: (v) { _q = v.trim(); _load(reset: true); },
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              hintText: ar ? 'بحث: رقم العملية / العميل'
                           : 'Search: ref / customer',
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _q.isNotEmpty
                  ? IconButton(icon: const Icon(Icons.clear, size: 16),
                      onPressed: () {
                        _searchCtl.clear(); _q = ''; _load(reset: true);
                      })
                  : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(11)),
            ),
          ))),
          const SizedBox(width: 8),
          InkWell(
            onTap: () => _openPosFilter(ar),
            borderRadius: BorderRadius.circular(11),
            child: Container(
              width: 40, height: 38,
              decoration: BoxDecoration(
                  color: (_cashier != null || _payMethod != null)
                      ? UellowColors.yellow : Colors.white,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: const Color(0xFFE5E5E5))),
              child: const Icon(Icons.tune_rounded, size: 18,
                  color: UellowColors.darkBrown)),
          ),
        ]),
        if (sm != null) Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(color: const Color(0xFFF3EFE6),
                  borderRadius: BorderRadius.circular(999)),
              child: Text(
                  '${sm['count'] ?? 0} ${ar ? 'عملية' : 'ops'} · '
                  '${tot?['amount'] ?? 0} ${tot?['symbol'] ?? ''}',
                  style: const TextStyle(fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: UellowColors.darkBrown)),
            ),
            if (_cashier != null) ...[const SizedBox(width: 6),
              _activeFilterChip('👤 $_cashier',
                  () { _cashier = null; _load(reset: true); })],
            if (_payMethod != null) ...[const SizedBox(width: 6),
              _activeFilterChip('💳 $_payMethod',
                  () { _payMethod = null; _load(reset: true); })],
          ]),
        ),
      ]),
    );
  }

  Widget _payPill(String method) {
    final m = method.toLowerCase();
    Color bg, fg;
    if (m.contains('knet') || m.contains('كي') || m.contains('card') ||
        m.contains('بطاق') || m.contains('visa') || m.contains('master')) {
      bg = const Color(0xFFE5EEFB); fg = const Color(0xFF1D5FB4);
    } else if (m.contains('cash') || m.contains('كاش') || m.contains('نقد')) {
      bg = const Color(0xFFE3F3EA); fg = const Color(0xFF1A7A46);
    } else if (m.contains('refund') || m.contains('مرتجع') ||
        m.contains('return')) {
      bg = const Color(0xFFF8E0DC); fg = const Color(0xFFC23B2B);
    } else {
      bg = const Color(0xFFFDF3D6); fg = const Color(0xFF6B4E00);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(method, style: TextStyle(fontSize: 9.5,
          fontWeight: FontWeight.w800, color: fg)),
    );
  }

  Widget _activeFilterChip(String t, VoidCallback onClear) => InkWell(
    onTap: onClear,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: const Color(0xFFFDF3D6),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFFEFD79A))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(t, style: const TextStyle(fontSize: 11,
            fontWeight: FontWeight.w800, color: Color(0xFF6B4E00))),
        const SizedBox(width: 3),
        const Icon(Icons.close, size: 12, color: Color(0xFF6B4E00)),
      ]),
    ),
  );

  Future<void> _openPosFilter(bool ar) async {
    final cCtl = TextEditingController(text: _cashier ?? '');
    final pCtl = TextEditingController(text: _payMethod ?? '');
    final go = await showDialog<bool>(context: context, builder: (c) =>
        AlertDialog(
          title: Text(ar ? 'فلترة العمليات' : 'Filter operations'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: cCtl, decoration: InputDecoration(
                labelText: ar ? '👤 الكاشير' : '👤 Cashier')),
            const SizedBox(height: 8),
            TextField(controller: pCtl, decoration: InputDecoration(
                labelText: ar ? '💳 طريقة الدفع' : '💳 Payment method')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false),
                child: Text(ar ? 'إلغاء' : 'Cancel')),
            TextButton(onPressed: () => Navigator.pop(c, true),
                child: Text(ar ? 'تطبيق' : 'Apply')),
          ],
        ));
    if (go == true) {
      _cashier = cCtl.text.trim().isEmpty ? null : cCtl.text.trim();
      _payMethod = pCtl.text.trim().isEmpty ? null : pCtl.text.trim();
      _load(reset: true);
    }
  }

  Widget _filterChips(bool ar) {
    final opts = <(String, String)>[
      ('today', ar ? 'اليوم' : 'Today'),
      ('7d', ar ? '٧ أيام' : '7 days'),
      ('30d', ar ? '٣٠ يوم' : '30 days'),
      ('all', ar ? 'الكل' : 'All'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 2),
      child: Row(children: [
        for (final o in opts) Padding(
          padding: const EdgeInsetsDirectional.only(end: 7),
          child: GestureDetector(
            onTap: () {
              if (_range == o.$1) return;
              setState(() => _range = o.$1);
              _load(reset: true);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: _range == o.$1
                    ? const Color(0xFFE8A800) : Colors.white,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: _range == o.$1
                    ? const Color(0xFFE8A800) : const Color(0xFFE5E5E5)),
              ),
              child: Text(o.$2, style: TextStyle(fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: _range == o.$1
                      ? const Color(0xFF2A1D00) : UellowColors.muted)),
            ),
          ),
        ),
        GestureDetector(
          onTap: _pickPosRange,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: _range == 'custom'
                  ? const Color(0xFFE8A800) : Colors.white,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: _range == 'custom'
                  ? const Color(0xFFE8A800) : const Color(0xFFE5E5E5)),
            ),
            child: Text(ar ? '📅 مخصّص' : '📅 Custom',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800,
                    color: _range == 'custom'
                        ? const Color(0xFF2A1D00) : UellowColors.muted)),
          ),
        ),
      ]),
    );
  }

  Future<void> _pickPosRange() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(context: context,
        firstDate: DateTime(now.year - 2), lastDate: now,
        initialDateRange: DateTimeRange(
            start: now.subtract(const Duration(days: 7)), end: now));
    if (r != null) {
      String f(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
      _customFrom = f(r.start);
      _customTo = f(r.end);
      setState(() => _range = 'custom');
      _load(reset: true);
    }
  }
}

// ─── reports (aggregate KPIs over a date range) ──────────────────────────
class _ReportTab extends StatefulWidget {
  const _ReportTab();
  @override
  State<_ReportTab> createState() => _ReportTabState();
}

// v2.2.168 — تاب تقارير احترافي: فلاتر شهر/سنة/مخصّص + مقارنة + ساعات ذروة
// + دونات دفع + لوحة كاشير + فئات + أكثر ربحًا/كمية + أبرز أرقام + تنبيه ذكي.
class _ReportTabState extends State<_ReportTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  String _period = 'month';
  String? _from, _to;
  Map<String, dynamic>? _data;
  bool _loading = false;
  bool _topQty = false;

  static const _gold = Color(0xFFE8A800);
  static const _good = Color(0xFF1A7A46);
  static const _bad = Color(0xFFC23B2B);
  static const _info = Color(0xFF1D5FB4);
  static const _pos = Color(0xFF7C3AED);
  static const _cash = Color(0xFF0D9488);
  static const _brown = Color(0xFF412402);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _data = await AdminApi.instance.posReport(
          period: _period, dateFrom: _from, dateTo: _to);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(context: context,
        firstDate: DateTime(now.year - 3), lastDate: now,
        initialDateRange: DateTimeRange(
            start: now.subtract(const Duration(days: 29)), end: now));
    if (r != null) {
      String f(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}'
          '-${d.day.toString().padLeft(2, '0')}';
      _from = f(r.start);
      _to = f(r.end);
      _period = 'custom';
      _load();
    }
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
    if (d['available'] == false) {
      return Center(child: Text(ar ? 'نقاط البيع غير مفعّلة'
                                   : 'POS not available'));
    }
    final k = (d['kpi'] as Map?) ?? const {};
    final dl = (d['delta'] as Map?) ?? const {};
    final cur = (d['currency'] ?? 'KD').toString();
    final hl = (d['highlights'] as Map?) ?? const {};
    final alert = d['alert'] as Map?;
    num nv(dynamic x) => (x as num?) ?? 0;
    String money(dynamic x) =>
        '${nv(x).toStringAsFixed(nv(x).abs() >= 1000 ? 0 : 1)} $cur';

    return RefreshIndicator(onRefresh: _load, child: ListView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 30), children: [
      _periodChips(ar),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Text(_periodLabel(ar, d), style: const TextStyle(fontSize: 15,
              fontWeight: FontWeight.w900, color: UellowColors.darkBrown)),
          Text(ar ? 'مقارنة بالفترة السابقة' : 'vs previous period',
              style: const TextStyle(fontSize: 11,
                  color: UellowColors.muted, fontWeight: FontWeight.w700)),
        ])),
        InkWell(
          onTap: () => _export(ar, d),
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(color: const Color(0xFFFDF3D6),
                borderRadius: BorderRadius.circular(999)),
            child: Text(ar ? '⬇️ تصدير' : '⬇️ Export',
                style: const TextStyle(fontSize: 11.5,
                    fontWeight: FontWeight.w800, color: Color(0xFF6B4E00))),
          ),
        ),
      ]),
      const SizedBox(height: 10),
      if (alert != null) _alertBanner(ar, alert),
      Row(children: [
        Expanded(child: _kpiCard(ar ? 'المبيعات' : 'Sales',
            money(k['net']), dl['sales'], _gold)),
        const SizedBox(width: 9),
        Expanded(child: _kpiCard(ar ? 'صافي الربح' : 'Profit',
            '${money(k['profit'])} · ${nv(k['margin_pct'])}%',
            dl['profit'], _good)),
      ]),
      const SizedBox(height: 9),
      Row(children: [
        Expanded(child: _kpiCard(ar ? 'عدد العمليات' : 'Orders',
            '${nv(k['orders'])}', dl['orders'], _pos)),
        const SizedBox(width: 9),
        Expanded(child: _kpiCard(ar ? 'متوسط السلة' : 'Avg basket',
            money(k['avg_basket']), dl['avg_basket'], _info)),
      ]),
      const SizedBox(height: 9),
      Row(children: [
        _miniKpi('${nv(k['items'])}', ar ? 'الأصناف' : 'Items'),
        const SizedBox(width: 7),
        _miniKpi('${nv(k['refunds'])}',
            ar ? 'مرتجعات (${nv(k['refunds_count'])})' : 'Refunds', red: true),
        const SizedBox(width: 7),
        _miniKpi(money(k['daily_avg']), ar ? 'متوسط يومي' : 'Daily avg'),
        const SizedBox(width: 7),
        _miniKpi('${nv(k['sessions'])}', ar ? 'جلسات' : 'Sessions'),
      ]),
      const SizedBox(height: 12),
      _section(ar ? '📈 المبيعات اليومية' : '📈 Daily sales',
          [_dailyChart((d['by_day'] as List?) ?? const [])],
          side: ar ? 'الحالي · السابق' : 'current · prev'),
      _section(ar ? '🕒 ساعات الذروة' : '🕒 Peak hours',
          [_hourChart((d['hourly'] as List?) ?? const [], ar)]),
      if (((d['by_payment'] as List?) ?? const []).isNotEmpty)
        _section(ar ? '💳 توزيع طرق الدفع' : '💳 Payment mix',
            [_payMix((d['by_payment'] as List?) ?? const [], cur)]),
      if (((d['by_cashier'] as List?) ?? const []).isNotEmpty)
        _section(ar ? '👤 أداء الكاشيرية' : '👤 Cashiers', [
          for (int i = 0; i < ((d['by_cashier'] as List).length);
               i++)
            _cashierRow(i, (d['by_cashier'] as List)[i] as Map, cur, ar),
        ]),
      _section(ar ? '🏆 أكثر المنتجات' : '🏆 Top products', [
        _segToggle(ar),
        const SizedBox(height: 4),
        for (final p in ((_topQty ? d['top_qty'] : d['top_profit']) as List?)
            ?? const [])
          _prodRow(p as Map, cur, ar),
      ]),
      if (((d['by_category'] as List?) ?? const []).isNotEmpty)
        _section(ar ? '🗂️ المبيعات حسب الفئة' : '🗂️ By category',
            [_catBars((d['by_category'] as List?) ?? const [], cur)]),
      _section(ar ? '✨ أبرز الأرقام' : '✨ Highlights',
          [_highlights(ar, hl, cur)]),
      const SizedBox(height: 6),
      Text(ar ? 'كل رقم يتحدّث حسب الفلتر المختار ومصدره نقاط البيع الفعلية.'
              : 'Everything updates with the selected filter, from real POS.',
          textAlign: TextAlign.center, style: const TextStyle(fontSize: 10.5,
              color: UellowColors.muted, fontWeight: FontWeight.w600)),
    ]));
  }

  // ── pieces ──
  Widget _periodChips(bool ar) {
    final opts = <(String, String)>[
      ('today', ar ? 'اليوم' : 'Today'),
      ('week', ar ? 'أسبوع' : 'Week'),
      ('month', ar ? 'الشهر' : 'Month'),
      ('year', ar ? 'السنة' : 'Year'),
    ];
    return SingleChildScrollView(scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (final o in opts) Padding(
          padding: const EdgeInsetsDirectional.only(end: 7),
          child: GestureDetector(
            onTap: () {
              if (_period == o.$1) return;
              setState(() { _period = o.$1; _from = null; _to = null; });
              _load();
            },
            child: _chipBox(o.$2, _period == o.$1)),
        ),
        GestureDetector(onTap: _pickCustom,
            child: _chipBox(ar ? '📅 مخصّص' : '📅 Custom', _period == 'custom')),
      ]),
    );
  }

  Widget _chipBox(String t, bool on) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(
      color: on ? _gold : Colors.white,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: on ? _gold : const Color(0xFFE5E5E5)),
    ),
    child: Text(t, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
        color: on ? const Color(0xFF2A1D00) : UellowColors.muted)),
  );

  String _periodLabel(bool ar, Map d) {
    final p = (d['period'] ?? '').toString();
    const mAr = ['', 'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
        'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
    final from = DateTime.tryParse('${d['from']}');
    if (p == 'month' && from != null) {
      return ar ? '${mAr[from.month]} ${from.year}'
                : '${from.month}/${from.year}';
    }
    if (p == 'year' && from != null) return '${from.year}';
    if (p == 'today') return ar ? 'اليوم' : 'Today';
    if (p == 'week') return ar ? 'آخر ٧ أيام' : 'Last 7 days';
    return '${d['from']} → ${d['to']}';
  }

  Widget _alertBanner(bool ar, Map a) {
    final down = a['level'] == 'down';
    final c = down ? _bad : _good;
    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(color: c.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.withValues(alpha: .30))),
      child: Row(children: [
        Icon(down ? Icons.trending_down_rounded : Icons.trending_up_rounded,
            color: c, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text((ar ? a['ar'] : a['en'])?.toString() ?? '',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800,
                color: c))),
      ]),
    );
  }

  Widget _kpiCard(String label, String value, dynamic delta, Color accent) {
    final dn = delta is num;
    final down = dn && delta < 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
      decoration: BoxDecoration(color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: const Color(0xFFECECEC))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 4, height: 15, decoration: BoxDecoration(
              color: accent, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 6),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 11,
              color: UellowColors.muted, fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 5),
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
            child: Text(value, style: const TextStyle(fontSize: 18,
                fontWeight: FontWeight.w900, color: UellowColors.darkBrown))),
        if (dn) ...[
          const SizedBox(height: 3),
          Text('${down ? '▼' : '▲'} ${delta.abs()}%',
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800,
                  color: down ? _bad : _good)),
        ],
      ]),
    );
  }

  Widget _miniKpi(String v, String l, {bool red = false}) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 5),
      decoration: BoxDecoration(color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFECECEC))),
      child: Column(children: [
        FittedBox(fit: BoxFit.scaleDown, child: Text(v, style: TextStyle(
            fontSize: 14, fontWeight: FontWeight.w900,
            color: red ? _bad : UellowColors.darkBrown))),
        const SizedBox(height: 2),
        Text(l, textAlign: TextAlign.center, style: const TextStyle(
            fontSize: 9.5, color: UellowColors.muted,
            fontWeight: FontWeight.w700)),
      ]),
    ),
  );

  Widget _section(String title, List<Widget> children, {String? side}) =>
      Container(
    margin: const EdgeInsets.only(bottom: 11),
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFECECEC))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(title, style: const TextStyle(fontSize: 14,
            fontWeight: FontWeight.w900, color: UellowColors.darkBrown))),
        if (side != null) Text(side, style: const TextStyle(fontSize: 10.5,
            color: UellowColors.muted, fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 10),
      ...children,
    ]),
  );

  Widget _dailyChart(List days) {
    final list = days.whereType<Map>().toList();
    if (list.isEmpty) return const SizedBox(height: 40);
    final show = list.length > 31 ? list.sublist(list.length - 31) : list;
    double mx = 1;
    for (final d in show) {
      final a = (d['sales'] as num?)?.toDouble() ?? 0;
      final b = (d['prev'] as num?)?.toDouble() ?? 0;
      if (a > mx) mx = a;
      if (b > mx) mx = b;
    }
    return SizedBox(height: 96, child: Row(
      crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final d in show)
          Expanded(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: Stack(alignment: Alignment.bottomCenter, children: [
              Container(
                height: (((d['prev'] as num?)?.toDouble() ?? 0) / mx * 80)
                    .clamp(0, 80),
                decoration: BoxDecoration(color: const Color(0xFFD9D2C4),
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(2))),
              ),
              FractionallySizedBox(widthFactor: 0.6, child: Container(
                height: (((d['sales'] as num?)?.toDouble() ?? 0) / mx * 80)
                    .clamp(1, 80),
                decoration: BoxDecoration(color: _gold,
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(2))),
              )),
            ]),
          )),
      ],
    ));
  }

  Widget _hourChart(List hourly, bool ar) {
    final h = hourly.map((e) => (e as num?)?.toDouble() ?? 0).toList();
    while (h.length < 24) h.add(0);
    double mx = 1;
    int peak = 0;
    for (int i = 0; i < 24; i++) {
      if (h[i] > mx) mx = h[i];
      if (h[i] > h[peak]) peak = i;
    }
    return Column(children: [
      SizedBox(height: 70, child: Row(
        crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (int i = 0; i < 24; i++)
            Expanded(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0.8),
              child: Container(
                height: (h[i] / mx * 60).clamp(2, 60),
                decoration: BoxDecoration(
                    color: i == peak ? _bad
                        : (h[i] > mx * .6 ? _gold : const Color(0xFFE7DFCB)),
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(2))),
              ),
            )),
        ],
      )),
      const SizedBox(height: 4),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: const [
        Text('12', style: TextStyle(fontSize: 8.5, color: UellowColors.muted)),
        Text('6', style: TextStyle(fontSize: 8.5, color: UellowColors.muted)),
        Text('12', style: TextStyle(fontSize: 8.5, color: UellowColors.muted)),
        Text('18', style: TextStyle(fontSize: 8.5, color: UellowColors.muted)),
        Text('23', style: TextStyle(fontSize: 8.5, color: UellowColors.muted)),
      ]),
    ]);
  }

  Widget _payMix(List pays, String cur) {
    final list = pays.whereType<Map>().toList();
    final cols = [_info, _cash, _pos, _gold, _brown];
    return Column(children: [
      ClipRRect(borderRadius: BorderRadius.circular(999),
        child: SizedBox(height: 16, child: Row(children: [
          for (int i = 0; i < list.length; i++)
            Expanded(flex: ((list[i]['pct'] as num?)?.toInt() ?? 0)
                .clamp(1, 100),
                child: Container(color: cols[i % cols.length])),
        ])),
      ),
      const SizedBox(height: 10),
      for (int i = 0; i < list.length; i++) Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Container(width: 12, height: 12, decoration: BoxDecoration(
              color: cols[i % cols.length],
              borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 8),
          Expanded(child: Text(list[i]['method']?.toString() ?? '',
              style: const TextStyle(fontSize: 12.5,
                  fontWeight: FontWeight.w700))),
          Text('${list[i]['amount'] ?? 0} $cur',
              style: const TextStyle(fontSize: 11.5,
                  color: UellowColors.muted, fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Text('${list[i]['pct'] ?? 0}%', style: const TextStyle(fontSize: 12.5,
              fontWeight: FontWeight.w900, color: UellowColors.darkBrown)),
        ]),
      ),
    ]);
  }

  Widget _cashierRow(int i, Map c, String cur, bool ar) {
    const medals = ['🥇', '🥈', '🥉'];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        SizedBox(width: 24, child: Text(i < 3 ? medals[i] : '${i + 1}',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900,
                color: UellowColors.muted))),
        const SizedBox(width: 6),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Text(c['name']?.toString() ?? '', maxLines: 1,
              overflow: TextOverflow.ellipsis, style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w800)),
          Text('${c['orders'] ?? 0} ${ar ? 'عملية' : 'ops'} · '
              '${ar ? 'هامش' : 'margin'} ${c['margin_pct'] ?? 0}%',
              style: const TextStyle(fontSize: 10.5,
                  color: UellowColors.muted, fontWeight: FontWeight.w600)),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${c['sales'] ?? 0} $cur', style: const TextStyle(fontSize: 13,
              fontWeight: FontWeight.w900, color: UellowColors.darkBrown)),
          Text('${ar ? 'ربح' : 'P'} ${c['profit'] ?? 0}',
              style: const TextStyle(fontSize: 10,
                  color: _good, fontWeight: FontWeight.w800)),
        ]),
      ]),
    );
  }

  Widget _segToggle(bool ar) => Row(children: [
    GestureDetector(onTap: () => setState(() => _topQty = false),
        child: _segBox(ar ? 'الأكثر ربحًا' : 'By profit', !_topQty)),
    const SizedBox(width: 6),
    GestureDetector(onTap: () => setState(() => _topQty = true),
        child: _segBox(ar ? 'الأكثر كمية' : 'By quantity', _topQty)),
  ]);

  Widget _segBox(String t, bool on) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
    decoration: BoxDecoration(color: on ? _brown : const Color(0xFFF1EEE7),
        borderRadius: BorderRadius.circular(999)),
    child: Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
        color: on ? const Color(0xFFF5C320) : UellowColors.muted)),
  );

  Widget _prodRow(Map p, String cur, bool ar) {
    final metric = _topQty
        ? '${(p['qty'] as num?)?.toStringAsFixed(0) ?? 0} ${ar ? 'قطعة' : 'pcs'}'
        : '${p['profit'] ?? 0} $cur';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        ClipRRect(borderRadius: BorderRadius.circular(9),
            child: Image.network(
                (p['image'] ?? '').toString().startsWith('http')
                    ? p['image'].toString()
                    : '${UellowApi.instance.baseUrl}${p['image'] ?? ''}',
                width: 38, height: 38, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(width: 38, height: 38,
                    color: const Color(0xFFF1EEE7),
                    child: const Icon(Icons.inventory_2_outlined, size: 16,
                        color: UellowColors.muted)))),
        const SizedBox(width: 9),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Text(p['name']?.toString() ?? '', maxLines: 1,
              overflow: TextOverflow.ellipsis, style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700)),
          Text('×${(p['qty'] as num?)?.toStringAsFixed(0) ?? 0} · '
              '${ar ? 'مبيعات' : 'sales'} ${p['sales'] ?? 0}',
              style: const TextStyle(fontSize: 10,
                  color: UellowColors.muted, fontWeight: FontWeight.w600)),
        ])),
        Text(metric, style: const TextStyle(fontSize: 13,
            fontWeight: FontWeight.w900, color: UellowColors.darkBrown)),
      ]),
    );
  }

  Widget _catBars(List cats, String cur) {
    final list = cats.whereType<Map>().toList();
    double mx = 1;
    for (final c in list) {
      final v = (c['total'] as num?)?.toDouble() ?? 0;
      if (v > mx) mx = v;
    }
    return Column(children: [
      for (final c in list) Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          SizedBox(width: 92, child: Text(c['name']?.toString() ?? '',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5,
                  fontWeight: FontWeight.w700))),
          Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(999),
            child: Container(height: 10, color: const Color(0xFFF1EEE7),
              child: FractionallySizedBox(alignment: Alignment.centerRight,
                widthFactor: (((c['total'] as num?)?.toDouble() ?? 0) / mx)
                    .clamp(0.02, 1.0),
                child: Container(decoration: const BoxDecoration(
                    gradient: LinearGradient(
                        colors: [_gold, Color(0xFFF5C320)]))))),
          )),
          const SizedBox(width: 8),
          Text('${c['total'] ?? 0}', style: const TextStyle(fontSize: 11.5,
              fontWeight: FontWeight.w900, color: UellowColors.darkBrown)),
        ]),
      ),
    ]);
  }

  Widget _highlights(bool ar, Map hl, String cur) {
    final bd = (hl['best_day'] as Map?) ?? const {};
    final pk = (hl['peak_hour'] as Map?) ?? const {};
    final bo = (hl['biggest_order'] as Map?) ?? const {};
    final da = (hl['daily_avg'] as Map?) ?? const {};
    final ph = (pk['hour'] as num?)?.toInt() ?? 0;
    String hr(int h) => h == 0 ? '12${ar ? 'ص' : 'am'}'
        : h < 12 ? '$h${ar ? 'ص' : 'am'}'
        : h == 12 ? '12${ar ? 'م' : 'pm'}'
        : '${h - 12}${ar ? 'م' : 'pm'}';
    Widget card(String l, String v, String s) => Expanded(child: Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
          gradient: const LinearGradient(begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [Color(0xFFFDF3D6), Colors.white]),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: const Color(0xFFEFE4C6))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l, style: const TextStyle(fontSize: 10.5,
            color: UellowColors.muted, fontWeight: FontWeight.w800)),
        const SizedBox(height: 3),
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
            child: Text(v, style: const TextStyle(fontSize: 15,
                fontWeight: FontWeight.w900, color: UellowColors.darkBrown))),
        const SizedBox(height: 1),
        Text(s, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 9.5, color: UellowColors.muted,
                fontWeight: FontWeight.w700)),
      ]),
    ));
    return Column(children: [
      Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        card(ar ? '📅 أفضل يوم' : '📅 Best day',
            '${bd['date'] ?? '—'}',
            '${bd['sales'] ?? 0} $cur · ${bd['orders'] ?? 0} ${ar ? 'عملية' : 'ops'}'),
        const SizedBox(width: 9),
        card(ar ? '🕗 أعلى ساعة' : '🕗 Peak hour', hr(ph),
            '${pk['pct'] ?? 0}% ${ar ? 'من المبيعات' : 'of sales'}'),
      ]),
      const SizedBox(height: 9),
      Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        card(ar ? '🧾 أكبر عملية' : '🧾 Biggest order',
            '${bo['amount'] ?? 0} $cur',
            '${bo['cashier'] ?? ''} · ${bo['date'] ?? ''}'),
        const SizedBox(width: 9),
        card(ar ? '📈 متوسط يومي' : '📈 Daily avg',
            '${da['sales'] ?? 0} $cur',
            '${da['orders'] ?? 0} ${ar ? 'عملية/يوم' : 'ops/day'}'),
      ]),
    ]);
  }

  Future<void> _export(bool ar, Map d) async {
    final k = (d['kpi'] as Map?) ?? const {};
    final cur = (d['currency'] ?? 'KD').toString();
    final t = StringBuffer()
      ..writeln(ar ? 'تقرير نقاط البيع' : 'POS report')
      ..writeln('${d['from']} → ${d['to']}')
      ..writeln('${ar ? 'المبيعات' : 'Sales'}: ${k['net']} $cur')
      ..writeln('${ar ? 'الربح' : 'Profit'}: ${k['profit']} $cur '
          '(${k['margin_pct']}%)')
      ..writeln('${ar ? 'العمليات' : 'Orders'}: ${k['orders']}')
      ..writeln('${ar ? 'متوسط السلة' : 'Avg basket'}: ${k['avg_basket']} $cur')
      ..writeln('${ar ? 'المرتجعات' : 'Refunds'}: ${k['refunds']} $cur');
    await Clipboard.setData(ClipboardData(text: t.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ar ? 'تم نسخ ملخّص التقرير' : 'Report summary copied')));
    }
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
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        // v2.2.150 — الهيدر بقى جزء من القائمة المتحركة (مش مثبّت)
        Expanded(child: _PosOrdersTab(
            sessionId: widget.sessionId,
            header: _d != null ? _SessionStatsHeader(d: _d!, fmt: _m)
                               : null)),
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
