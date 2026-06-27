// =============================================================================
// AdminDashboardScreen (v2.2.10) — 🛡️ the owner's console.
//
// Dark-premium header with live KPIs (today / yesterday / week / month),
// a 14-day revenue bar chart, POS snapshot (open sessions + today),
// top products of the month, sales by website, and quick links to the
// Orders / Products / POS managers.
// =============================================================================
import 'package:flutter/material.dart';

import '../../../api/uellow_api.dart';
import '../../services/admin_mode.dart';
import '../../theme/uellow_theme.dart';
import 'admin_helpdesk_screen.dart';
import 'admin_activity_screen.dart';
import 'admin_orders_screen.dart';
import 'admin_pos_screen.dart';
import 'admin_products_screen.dart';
import 'admin_purchase_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});
  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = AdminApi.instance.dashboard();
    // v2.2.27 — defense-in-depth: re-confirm admin with the server on open
    // and bounce anyone who isn't (handles stale flags / deep links). The
    // data endpoints are already server-gated, this just closes the UI.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final okAdmin = await AdminMode.verify();
      if (!okAdmin && mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F5),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (_, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(
                color: UellowColors.darkBrown));
          }
          if (snap.hasError || snap.data == null) {
            return _ErrorRetry(onRetry: () =>
                setState(() => _future = AdminApi.instance.dashboard()));
          }
          final d = snap.data!;
          return RefreshIndicator(
            onRefresh: () async =>
                setState(() => _future = AdminApi.instance.dashboard()),
            child: CustomScrollView(slivers: [
              SliverToBoxAdapter(child: _Header(d: d, ar: ar)),
              // ── Live now (who's on the app right now) ────────────────
              SliverToBoxAdapter(child: _LiveCard(
                  live: (d['live'] as Map?)?.cast<String, dynamic>()
                      ?? const {}, ar: ar)),
              // ── Management (the "menu") ──────────────────────────────
              SliverToBoxAdapter(child: _SectionTitle(
                  icon: Icons.grid_view_rounded,
                  title: ar ? 'الإدارة' : 'Management')),
              SliverToBoxAdapter(child: _ManagementGrid(ar: ar)),
              // ── Insights (the dashboard) ─────────────────────────────
              SliverToBoxAdapter(child: _SectionTitle(
                  icon: Icons.insights_rounded,
                  title: ar ? 'التحليلات' : 'Insights')),
              SliverToBoxAdapter(child: _ChartCard(
                  daily: (d['daily'] as List?) ?? const [], ar: ar)),
              SliverToBoxAdapter(child: _PosCard(
                  pos: (d['pos'] as Map?)?.cast<String, dynamic>(), ar: ar)),
              SliverToBoxAdapter(child: _TopProducts(
                  tops: (d['top_products'] as List?) ?? const [], ar: ar)),
              SliverToBoxAdapter(child: _ByWebsite(
                  sites: (d['by_website'] as List?) ?? const [], ar: ar)),
              const SliverToBoxAdapter(child: SizedBox(height: 30)),
            ]),
          );
        },
      ),
    );
  }
}

// ─── header: dark gradient + 4 KPI tiles ────────────────────────────────
class _Header extends StatelessWidget {
  const _Header({required this.d, required this.ar});
  final Map<String, dynamic> d;
  final bool ar;

  static String _amt(Map? m) {
    if (m == null) return '0';
    final a = (m['amount'] as num?) ?? 0;
    final dg = (m['digits'] as num?)?.toInt() ?? 3;
    return '${a.toStringAsFixed(dg)} ${m['symbol'] ?? ''}';
  }

  @override
  Widget build(BuildContext context) {
    final today = (d['today'] as Map?)?.cast<String, dynamic>() ?? {};
    final yest = (d['yesterday'] as Map?)?.cast<String, dynamic>() ?? {};
    final week = (d['week'] as Map?)?.cast<String, dynamic>() ?? {};
    final month = (d['month'] as Map?)?.cast<String, dynamic>() ?? {};
    final pending = (d['pending'] as Map?)?.cast<String, dynamic>() ?? {};
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, MediaQuery.of(context).padding.top + 10, 16, 22),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF241302), Color(0xFF412402), Color(0xFF5A3506)]),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(26)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _CircleBtn(icon: Icons.arrow_back,
              onTap: () => Navigator.pop(context)),
          const SizedBox(width: 10),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(ar ? '🛡️ لوحة الإدارة' : '🛡️ Admin Console',
                style: const TextStyle(color: UellowColors.yellow, fontSize: 19,
                    fontWeight: FontWeight.w900)),
            Text(ar ? 'المبيعات · البوس · المنتجات' : 'Sales · POS · Products',
                style: TextStyle(color: Colors.white.withValues(alpha: .55),
                    fontSize: 11.5, fontWeight: FontWeight.w600)),
          ])),
          if ((pending['to_deliver'] as num? ?? 0) > 0) Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: UellowColors.yellow.withValues(alpha: .15),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: UellowColors.yellow
                  .withValues(alpha: .45)),
            ),
            child: Text(
              ar ? '🚚 ${pending['to_deliver']} للتوصيل'
                 : '🚚 ${pending['to_deliver']} to ship',
              style: const TextStyle(color: UellowColors.yellowLight,
                  fontSize: 11, fontWeight: FontWeight.w800)),
          ),
        ]),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(child: _KpiBig(
            label: ar ? 'مبيعات اليوم' : "Today's sales",
            value: _amt(today['total'] as Map?),
            sub: ar ? '${today['count'] ?? 0} طلب'
                    : '${today['count'] ?? 0} orders',
          )),
          const SizedBox(width: 10),
          Expanded(child: _KpiBig(
            label: ar ? 'هذا الشهر' : 'This month',
            value: _amt(month['total'] as Map?),
            sub: ar ? '${month['count'] ?? 0} طلب · متوسط ${_amt(month['avg'] as Map?)}'
                    : '${month['count'] ?? 0} orders · avg ${_amt(month['avg'] as Map?)}',
          )),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _KpiSmall(
              label: ar ? 'أمس' : 'Yesterday',
              value: _amt(yest['total'] as Map?),
              sub: '${yest['count'] ?? 0}')),
          const SizedBox(width: 8),
          Expanded(child: _KpiSmall(
              label: ar ? 'آخر ٧ أيام' : 'Last 7 days',
              value: _amt(week['total'] as Map?),
              sub: '${week['count'] ?? 0}')),
          const SizedBox(width: 8),
          Expanded(child: _KpiSmall(
              label: ar ? 'متوسط الطلب' : 'Avg order',
              value: _amt(today['avg'] as Map?),
              sub: ar ? 'اليوم' : 'today')),
        ]),
      ]),
    );
  }
}

class _KpiBig extends StatelessWidget {
  const _KpiBig({required this.label, required this.value, required this.sub});
  final String label, value, sub;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .07),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white.withValues(alpha: .12)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(color: Colors.white.withValues(alpha: .6),
          fontSize: 11, fontWeight: FontWeight.w700)),
      const SizedBox(height: 5),
      FittedBox(child: Text(value, style: const TextStyle(
          color: UellowColors.yellow, fontSize: 21,
          fontWeight: FontWeight.w900))),
      const SizedBox(height: 2),
      Text(sub, style: TextStyle(color: Colors.white.withValues(alpha: .55),
          fontSize: 10.5)),
    ]),
  );
}

class _KpiSmall extends StatelessWidget {
  const _KpiSmall({required this.label, required this.value,
      required this.sub});
  final String label, value, sub;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .05),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(color: Colors.white.withValues(alpha: .55),
          fontSize: 9.5, fontWeight: FontWeight.w700)),
      const SizedBox(height: 3),
      FittedBox(child: Text(value, style: const TextStyle(color: Colors.white,
          fontSize: 13, fontWeight: FontWeight.w900))),
      Text(sub, style: TextStyle(color: Colors.white.withValues(alpha: .4),
          fontSize: 9)),
    ]),
  );
}

class _CircleBtn extends StatelessWidget {
  const _CircleBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap, borderRadius: BorderRadius.circular(999),
    child: Container(width: 36, height: 36,
      decoration: BoxDecoration(shape: BoxShape.circle,
          color: UellowColors.yellow.withValues(alpha: .15)),
      child: Icon(icon, color: UellowColors.yellow, size: 19)),
  );
}

// ─── live-now snapshot (online users + reach) ───────────────────────────
class _LiveCard extends StatelessWidget {
  const _LiveCard({required this.live, required this.ar});
  final Map<String, dynamic> live;
  final bool ar;
  int _n(String k) => (live[k] as num?)?.toInt() ?? 0;
  @override
  Widget build(BuildContext context) {
    final online = _n('online_now');
    final stats = <(IconData, int, String, Color)>[
      (Icons.bolt_rounded, _n('active_30m'),
          ar ? 'نشط (٣٠ د)' : 'Active 30m', const Color(0xFF2563EB)),
      (Icons.today_rounded, _n('active_today'),
          ar ? 'نشط اليوم' : 'Active today', const Color(0xFF7C3AED)),
      (Icons.person_add_alt_1_rounded, _n('new_customers_today'),
          ar ? 'عملاء جدد' : 'New today', const Color(0xFF059669)),
      (Icons.shopping_cart_rounded, _n('carts_active'),
          ar ? 'سلات نشطة' : 'Live carts', const Color(0xFFEA580C)),
      (Icons.notifications_active_rounded, _n('push_reach'),
          ar ? 'وصول الإشعارات' : 'Push reach', const Color(0xFFDB2777)),
    ];
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 14, 14, 0),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [BoxShadow(color: Color(0x12000000),
              blurRadius: 10, offset: Offset(0, 4))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 9, height: 9, decoration: const BoxDecoration(
              shape: BoxShape.circle, color: Color(0xFF10B981))),
          const SizedBox(width: 7),
          Text(ar ? 'الآن على التطبيق' : 'Live on the app', style: UT.h3),
          const Spacer(),
          Text('$online ${ar ? 'متصل' : 'online'}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900,
                  color: Color(0xFF10B981))),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final s in stats) Container(
            width: (MediaQuery.of(context).size.width - 28 - 32 - 16) / 3,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(
              color: s.$4.withValues(alpha: .07),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(children: [
              Icon(s.$1, size: 17, color: s.$4),
              const SizedBox(height: 4),
              Text('${s.$2}', style: TextStyle(fontSize: 16,
                  fontWeight: FontWeight.w900, color: s.$4)),
              Text(s.$3, textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 9,
                      fontWeight: FontWeight.w700, color: UellowColors.muted)),
            ]),
          ),
        ]),
      ]),
    );
  }
}

// ─── section title ───────────────────────────────────────────────────────
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title});
  final IconData icon;
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 18, 18, 2),
    child: Row(children: [
      Icon(icon, size: 16, color: UellowColors.darkBrown),
      const SizedBox(width: 7),
      Text(title, style: const TextStyle(fontSize: 13.5,
          fontWeight: FontWeight.w900, color: UellowColors.darkBrown)),
    ]),
  );
}

// ─── management grid (the admin "menu") ──────────────────────────────────
class _ManagementGrid extends StatelessWidget {
  const _ManagementGrid({required this.ar});
  final bool ar;
  @override
  Widget build(BuildContext context) {
    final items = <(IconData, String, String, Color, VoidCallback)>[
      (Icons.receipt_long_rounded, ar ? 'الطلبات' : 'Orders',
          ar ? 'كل الطلبات والحالات' : 'All orders & statuses',
          const Color(0xFF2563EB),
          () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => const AdminOrdersScreen()))),
      (Icons.point_of_sale_rounded, ar ? 'سجل البوس' : 'POS Log',
          ar ? 'الجلسات والمبيعات' : 'Sessions & sales',
          const Color(0xFF7C3AED),
          () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => const AdminPosScreen()))),
      (Icons.inventory_2_rounded, ar ? 'المنتجات' : 'Products',
          ar ? 'الأسعار والمخزون' : 'Prices & stock',
          const Color(0xFF059669),
          () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => const AdminProductsScreen()))),
      (Icons.shopping_cart_checkout_rounded, ar ? 'المشتريات' : 'Purchases',
          ar ? 'أوامر الشراء والموردين' : 'POs & vendors',
          const Color(0xFFB45309),
          () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => const AdminPurchaseScreen()))),
      (Icons.support_agent_rounded, ar ? 'الدعم' : 'Helpdesk',
          ar ? 'تذاكر العملاء والردود' : 'Tickets & replies',
          const Color(0xFFE11D48),
          () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => const AdminHelpdeskScreen()))),
      (Icons.directions_walk_rounded, ar ? 'نشاط العملاء' : 'Activity',
          ar ? 'ماذا يفعل العميل لحظيًا' : 'What customers do',
          const Color(0xFF0EA5E9),
          () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => const AdminActivityScreen()))),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      child: GridView.count(
        crossAxisCount: 2, shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.55,
        children: [for (final it in items) _tile(it)],
      ),
    );
  }

  Widget _tile((IconData, String, String, Color, VoidCallback) it) =>
      InkWell(
        onTap: it.$5,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [BoxShadow(color: Color(0x14000000),
                blurRadius: 10, offset: Offset(0, 4))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Container(width: 40, height: 40,
              decoration: BoxDecoration(
                color: it.$4.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(12)),
              child: Icon(it.$1, color: it.$4, size: 21)),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(it.$2, style: const TextStyle(fontSize: 13.5,
                  fontWeight: FontWeight.w900,
                  color: UellowColors.darkBrown)),
              const SizedBox(height: 1),
              Text(it.$3, style: const TextStyle(fontSize: 10.5,
                  color: UellowColors.muted, fontWeight: FontWeight.w600)),
            ]),
          ]),
        ),
      );
}

// ─── 14-day revenue bar chart (pure CustomPaint — no dependency) ────────
class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.daily, required this.ar});
  final List daily;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    if (daily.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 14, 14, 0),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [BoxShadow(color: Color(0x12000000),
              blurRadius: 10, offset: Offset(0, 4))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.bar_chart_rounded, size: 18,
              color: UellowColors.darkBrown),
          const SizedBox(width: 6),
          Text(ar ? 'إيرادات آخر ١٤ يوم' : 'Revenue — last 14 days',
              style: UT.h3),
        ]),
        const SizedBox(height: 12),
        SizedBox(height: 120, width: double.infinity,
            child: CustomPaint(painter: _BarsPainter(daily))),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(_dayLabel(daily.first), style: const TextStyle(fontSize: 9,
              color: UellowColors.muted)),
          Text(_dayLabel(daily.last), style: const TextStyle(fontSize: 9,
              color: UellowColors.muted)),
        ]),
      ]),
    );
  }

  static String _dayLabel(dynamic d) {
    final s = (d as Map)['date']?.toString() ?? '';
    return s.length >= 10 ? s.substring(5) : s;
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(this.daily);
  final List daily;
  @override
  void paint(Canvas canvas, Size size) {
    if (daily.isEmpty) return;
    final maxV = daily.fold<double>(1.0, (m, d) {
      final v = ((d as Map)['total'] as num?)?.toDouble() ?? 0;
      return v > m ? v : m;
    });
    final n = daily.length;
    final gap = 5.0;
    final bw = (size.width - gap * (n - 1)) / n;
    final today = Paint()..color = const Color(0xFFF5C320);
    final normal = Paint()..color = const Color(0xFF412402)
        .withValues(alpha: .22);
    final txt = TextPainter(textDirection: TextDirection.ltr);
    for (var i = 0; i < n; i++) {
      final v = ((daily[i] as Map)['total'] as num?)?.toDouble() ?? 0;
      final h = (v / maxV) * (size.height - 16);
      final x = i * (bw + gap);
      final r = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, size.height - h, bw, h.clamp(2, size.height)),
          const Radius.circular(4));
      canvas.drawRRect(r, i == n - 1 ? today : normal);
      // value label on the highest + last bars
      if (v > 0 && (v == maxV || i == n - 1)) {
        txt.text = TextSpan(text: v >= 100
            ? v.toStringAsFixed(0) : v.toStringAsFixed(1),
            style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800,
                color: i == n - 1 ? const Color(0xFFB58A00)
                    : const Color(0xFF412402).withValues(alpha: .6)));
        txt.layout();
        txt.paint(canvas, Offset(
            x + bw / 2 - txt.width / 2, size.height - h - 12));
      }
    }
  }
  @override
  bool shouldRepaint(covariant _BarsPainter old) => old.daily != daily;
}

// ─── POS snapshot ────────────────────────────────────────────────────────
class _PosCard extends StatelessWidget {
  const _PosCard({required this.pos, required this.ar});
  final Map<String, dynamic>? pos;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    if (pos == null || pos!['available'] != true) {
      return const SizedBox.shrink();
    }
    final sessions = (pos!['open_sessions'] as List?) ?? const [];
    final tt = (pos!['today_total'] as Map?) ?? const {};
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 14, 14, 0),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [BoxShadow(color: Color(0x12000000),
              blurRadius: 10, offset: Offset(0, 4))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.point_of_sale_rounded, size: 18,
              color: Color(0xFF7C3AED)),
          const SizedBox(width: 6),
          Text(ar ? 'نقاط البيع اليوم' : 'POS today', style: UT.h3),
          const Spacer(),
          Text('${(tt['amount'] as num? ?? 0).toStringAsFixed((tt['digits'] as num?)?.toInt() ?? 3)} ${tt['symbol'] ?? ''} · ${pos!['today_count'] ?? 0} ${ar ? 'عملية' : 'sales'}',
              style: const TextStyle(fontSize: 11.5,
                  fontWeight: FontWeight.w800, color: Color(0xFF7C3AED))),
        ]),
        if (sessions.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final s in sessions) Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (s['state'] == 'opened')
                      ? const Color(0xFF10B981) : UellowColors.warn)),
              const SizedBox(width: 8),
              Expanded(child: Text(
                  '${s['name']} · ${s['user']}',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5,
                      fontWeight: FontWeight.w700))),
              Text('${s['orders']} ${ar ? 'طلب' : 'orders'}',
                  style: const TextStyle(fontSize: 10.5,
                      color: UellowColors.muted)),
            ]),
          ),
        ] else Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(ar ? 'لا توجد يومية مفتوحة الآن'
                        : 'No open session right now',
              style: const TextStyle(fontSize: 11,
                  color: UellowColors.muted)),
        ),
      ]),
    );
  }
}

// ─── top products of the month ───────────────────────────────────────────
class _TopProducts extends StatelessWidget {
  const _TopProducts({required this.tops, required this.ar});
  final List tops;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    if (tops.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 14, 14, 0),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [BoxShadow(color: Color(0x12000000),
              blurRadius: 10, offset: Offset(0, 4))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.local_fire_department_rounded, size: 18,
              color: Color(0xFFEF4444)),
          const SizedBox(width: 6),
          Text(ar ? 'الأكثر مبيعاً هذا الشهر' : 'Top sellers this month',
              style: UT.h3),
        ]),
        const SizedBox(height: 8),
        for (var i = 0; i < tops.length; i++) _row(i, tops[i] as Map),
      ]),
    );
  }

  Widget _row(int i, Map t) {
    final m = (t['total'] as Map?) ?? const {};
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Text('${i + 1}', style: TextStyle(fontSize: 13,
            fontWeight: FontWeight.w900,
            color: i == 0 ? const Color(0xFFB58A00) : UellowColors.muted)),
        const SizedBox(width: 10),
        ClipRRect(borderRadius: BorderRadius.circular(8),
            child: Image.network(t['image']?.toString() ?? '',
                width: 36, height: 36, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(width: 36, height: 36,
                    color: UellowColors.border))),
        const SizedBox(width: 10),
        Expanded(child: Text(t['name']?.toString() ?? '',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12,
                fontWeight: FontWeight.w700))),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${(m['amount'] as num? ?? 0).toStringAsFixed((m['digits'] as num?)?.toInt() ?? 3)} ${m['symbol'] ?? ''}',
              style: const TextStyle(fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                  color: UellowColors.darkBrown)),
          Text('×${t['qty'] ?? 0}', style: const TextStyle(fontSize: 9.5,
              color: UellowColors.muted)),
        ]),
      ]),
    );
  }
}

// ─── sales by website ───────────────────────────────────────────────────
class _ByWebsite extends StatelessWidget {
  const _ByWebsite({required this.sites, required this.ar});
  final List sites;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    if (sites.isEmpty) return const SizedBox.shrink();
    final maxV = sites.fold<double>(1.0, (m, s) {
      final v = ((s as Map)['total'] as num?)?.toDouble() ?? 0;
      return v > m ? v : m;
    });
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 14, 14, 0),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [BoxShadow(color: Color(0x12000000),
              blurRadius: 10, offset: Offset(0, 4))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.public_rounded, size: 18,
              color: Color(0xFF2563EB)),
          const SizedBox(width: 6),
          Text(ar ? 'المبيعات حسب الموقع (الشهر)' : 'Sales by site (month)',
              style: UT.h3),
        ]),
        const SizedBox(height: 10),
        for (final s in sites) Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Row(children: [
              Expanded(child: Text((s as Map)['website']?.toString() ?? '',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5,
                      fontWeight: FontWeight.w700))),
              Text('${((s['total'] as num?) ?? 0).toStringAsFixed(3)} KD · ${s['count']}',
                  style: const TextStyle(fontSize: 10.5,
                      color: UellowColors.muted,
                      fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 4),
            ClipRRect(borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (((s['total'] as num?) ?? 0) / maxV)
                    .clamp(0.02, 1).toDouble(),
                minHeight: 6,
                backgroundColor: const Color(0xFFF0F0F0),
                color: const Color(0xFF2563EB),
              )),
          ]),
        ),
      ]),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.lock_outline_rounded, size: 36,
          color: UellowColors.muted),
      const SizedBox(height: 10),
      Text(ar ? 'تعذر تحميل لوحة الإدارة' : 'Couldn\'t load the console',
          style: UT.subtitle),
      const SizedBox(height: 12),
      ElevatedButton.icon(onPressed: onRetry,
          icon: const Icon(Icons.refresh, size: 16),
          label: Text(ar ? 'إعادة المحاولة' : 'Retry')),
    ]));
  }
}
