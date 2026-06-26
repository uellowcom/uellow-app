// =============================================================================
// AdminActivityScreen (v2.2.56) — customer journey viewer.
// Recent activity feed across all customers (search) → tap a row to open
// that customer's full timeline (summary + chronological events).
// =============================================================================
import 'package:flutter/material.dart';

import '../../../api/uellow_api.dart';
import '../../services/admin_mode.dart';
import '../../theme/uellow_theme.dart';

// event → (icon, EN, AR)
(IconData, String, String) _evt(String e) {
  switch (e) {
    case 'app_open':
      return (Icons.login_rounded, 'Opened app', 'فتح التطبيق');
    case 'app_close':
      return (Icons.logout_rounded, 'Closed app', 'أغلق التطبيق');
    case 'screen_view':
      return (Icons.visibility_rounded, 'Viewed', 'شاهد');
    case 'screen_leave':
      return (Icons.exit_to_app_rounded, 'Left', 'غادر');
    case 'add_to_cart':
      return (Icons.add_shopping_cart_rounded, 'Added to cart', 'أضاف للسلة');
    case 'remove_from_cart':
      return (Icons.remove_shopping_cart_rounded, 'Removed from cart',
          'أزال من السلة');
    case 'search':
      return (Icons.search_rounded, 'Searched', 'بحث');
    case 'checkout_start':
      return (Icons.shopping_bag_rounded, 'Started checkout', 'بدأ الدفع');
    case 'order_placed':
      return (Icons.receipt_long_rounded, 'Placed order', 'أنشأ طلبًا');
    default:
      return (Icons.touch_app_rounded, e, e);
  }
}

String _dur(int ms) {
  if (ms <= 0) return '';
  if (ms < 1000) return '${ms}ms';
  final s = ms / 1000.0;
  if (s < 60) return '${s.toStringAsFixed(1)}s';
  return '${(s / 60).toStringAsFixed(1)}m';
}

class AdminActivityScreen extends StatefulWidget {
  const AdminActivityScreen({super.key});
  @override
  State<AdminActivityScreen> createState() => _AdminActivityScreenState();
}

class _AdminActivityScreenState extends State<AdminActivityScreen> {
  final _scroll = ScrollController();
  final _searchCtrl = TextEditingController();
  final List<Map<String, dynamic>> _rows = [];
  int _page = 1, _pages = 1;
  bool _loading = false;
  String _q = '';

  @override
  void initState() {
    super.initState();
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
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      _page = 1;
      _rows.clear();
    }
    setState(() => _loading = true);
    try {
      final d = await AdminApi.instance.activityRecent(page: _page, q: _q);
      _pages = (d['pages'] as num?)?.toInt() ?? 1;
      _rows.addAll(((d['activities'] as List?) ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>()));
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
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
        title: Text(ar ? '👣 نشاط العملاء' : '👣 Customer activity',
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: UellowColors.yellow)),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
          child: TextField(
            controller: _searchCtrl,
            onSubmitted: (v) {
              _q = v.trim();
              _load(reset: true);
            },
            decoration: InputDecoration(
              hintText: ar
                  ? 'ابحث باسم العميل / الشاشة / المنتج'
                  : 'Search customer / screen / product',
              prefixIcon: const Icon(Icons.search_rounded),
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
            ),
          ),
        ),
        Expanded(
          child: (_rows.isEmpty && _loading)
              ? const Center(
                  child: CircularProgressIndicator(
                      color: UellowColors.darkBrown))
              : RefreshIndicator(
                  onRefresh: () => _load(reset: true),
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
                    itemCount: _rows.length + (_loading ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i >= _rows.length) {
                        return const Padding(
                            padding: EdgeInsets.all(14),
                            child: Center(
                                child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))));
                      }
                      return _tile(_rows[i], ar);
                    },
                  ),
                ),
        ),
      ]),
    );
  }

  Widget _tile(Map<String, dynamic> a, bool ar) {
    final (icon, en, arr) = _evt(a['event']?.toString() ?? '');
    final cust = (a['customer'] as Map?) ?? const {};
    final cid = (cust['id'] as num?)?.toInt() ?? 0;
    final label = a['label']?.toString() ?? '';
    final screen = a['screen']?.toString() ?? '';
    final dur = _dur((a['duration_ms'] as num?)?.toInt() ?? 0);
    return InkWell(
      onTap: cid > 0
          ? () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => AdminCustomerActivityScreen(
                      partnerId: cid,
                      name: cust['name']?.toString() ?? '')))
          : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 7),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFECECEC))),
        child: Row(children: [
          Icon(icon, size: 20, color: UellowColors.darkBrown),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(
                          '${ar ? arr : en}'
                          '${screen.isNotEmpty ? ' · $screen' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w800)),
                    ),
                    if (dur.isNotEmpty)
                      Text(dur,
                          style: const TextStyle(
                              fontSize: 10.5, color: UellowColors.muted)),
                  ]),
                  if (label.isNotEmpty)
                    Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11, color: UellowColors.muted)),
                  const SizedBox(height: 2),
                  Text(
                      '${cust['name'] ?? 'Guest'} · ${a['when'] ?? ''}'
                      '${(a['app_version'] ?? '').toString().isNotEmpty ? ' · v${a['app_version']}' : ''}',
                      style: const TextStyle(
                          fontSize: 10, color: UellowColors.muted)),
                ]),
          ),
          if (cid > 0)
            const Icon(Icons.chevron_right_rounded,
                size: 18, color: UellowColors.muted),
        ]),
      ),
    );
  }
}

// ─── per-customer timeline ─────────────────────────────────────────────────
class AdminCustomerActivityScreen extends StatefulWidget {
  const AdminCustomerActivityScreen(
      {super.key, required this.partnerId, required this.name});
  final int partnerId;
  final String name;
  @override
  State<AdminCustomerActivityScreen> createState() =>
      _AdminCustomerActivityScreenState();
}

class _AdminCustomerActivityScreenState
    extends State<AdminCustomerActivityScreen> {
  late Future<Map<String, dynamic>> _future;
  @override
  void initState() {
    super.initState();
    _future = AdminApi.instance.customerActivity(widget.partnerId);
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
        title: Text(widget.name.isNotEmpty ? widget.name : (ar ? 'العميل' : 'Customer'),
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: UellowColors.yellow)),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (_, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(
                child: CircularProgressIndicator(
                    color: UellowColors.darkBrown));
          }
          final d = snap.data ?? const {};
          final sum = (d['summary'] as Map?) ?? const {};
          final tl = (d['timeline'] as List?) ?? const [];
          final tops = (sum['top_screens'] as List?) ?? const [];
          return ListView(padding: const EdgeInsets.all(14), children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFECECEC))),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      _stat(ar ? 'أحداث' : 'Events', '${sum['events'] ?? 0}'),
                      _stat(ar ? 'جلسات' : 'Sessions',
                          '${sum['sessions'] ?? 0}'),
                    ]),
                    const SizedBox(height: 8),
                    Text(
                        '${ar ? 'أول ظهور' : 'First seen'}: ${sum['first_seen'] ?? '—'}',
                        style: const TextStyle(
                            fontSize: 11, color: UellowColors.muted)),
                    Text(
                        '${ar ? 'آخر ظهور' : 'Last seen'}: ${sum['last_seen'] ?? '—'}',
                        style: const TextStyle(
                            fontSize: 11, color: UellowColors.muted)),
                    if (tops.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(ar ? 'أكثر الشاشات' : 'Top screens',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w900,
                              color: UellowColors.darkBrown)),
                      const SizedBox(height: 4),
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        for (final s in tops)
                          Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text(
                                '${(s as Map)['screen']} (${s['count']})',
                                style: const TextStyle(fontSize: 10.5)),
                            backgroundColor: const Color(0xFFFFF7E0),
                          ),
                      ]),
                    ],
                  ]),
            ),
            const SizedBox(height: 12),
            Text(ar ? 'الخط الزمني' : 'Timeline',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: UellowColors.darkBrown)),
            const SizedBox(height: 6),
            for (final a in tl) _row((a as Map).cast<String, dynamic>(), ar),
            const SizedBox(height: 24),
          ]);
        },
      ),
    );
  }

  Widget _stat(String label, String value) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value,
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: UellowColors.darkBrown)),
          Text(label,
              style: const TextStyle(fontSize: 11, color: UellowColors.muted)),
        ]),
      );

  Widget _row(Map<String, dynamic> a, bool ar) {
    final (icon, en, arr) = _evt(a['event']?.toString() ?? '');
    final label = a['label']?.toString() ?? '';
    final screen = a['screen']?.toString() ?? '';
    final dur = _dur((a['duration_ms'] as num?)?.toInt() ?? 0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 17, color: UellowColors.darkBrown),
        const SizedBox(width: 9),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                '${ar ? arr : en}'
                '${screen.isNotEmpty ? ' · $screen' : ''}'
                '${dur.isNotEmpty ? '  ($dur)' : ''}',
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700)),
            if (label.isNotEmpty)
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 10.5, color: UellowColors.muted)),
          ]),
        ),
        Text(a['when']?.toString().split(' ').last ?? '',
            style: const TextStyle(fontSize: 10, color: UellowColors.muted)),
      ]),
    );
  }
}
