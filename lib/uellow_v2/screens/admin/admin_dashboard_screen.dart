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
import 'admin_customer_service_screen.dart';
import 'admin_activity_screen.dart';
import 'admin_orders_screen.dart';
import 'admin_pos_screen.dart';
import 'admin_products_screen.dart';
import 'admin_purchase_screen.dart';
import 'admin_notifications_screen.dart';
import 'admin_gift_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});
  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String _period = '30d';
  String? _from;
  String? _to;

  @override
  void initState() {
    super.initState();
    _load();
    // v2.2.27 — defense-in-depth: re-confirm admin with the server on open.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final okAdmin = await AdminMode.verify();
      if (!okAdmin && mounted) Navigator.of(context).maybePop();
    });
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final d = await AdminApi.instance
          .dashboard(period: _period, from: _from, to: _to);
      if (!mounted) return;
      setState(() { _data = d; _loading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _pick(String p, {String? from, String? to}) {
    setState(() { _period = p; _from = from; _to = to; });
    _load();
  }

  static String _sym(Map<String, dynamic> d) {
    for (final k in ['month', 'week', 'today']) {
      final t = ((d[k] as Map?)?['total']) as Map?;
      final s = t?['symbol']?.toString();
      if (s != null && s.isNotEmpty) return s;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    if (_data == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF2F3F5),
        body: _loading
            ? const Center(child: CircularProgressIndicator(
                color: UellowColors.darkBrown))
            : _ErrorRetry(onRetry: _load),
      );
    }
    final d = _data!;
    final sym = _sym(d);
    final range = (d['range'] as Map?)?.cast<String, dynamic>();
    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F5),
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(child: _Header(d: d, ar: ar)),
          SliverToBoxAdapter(child: _LiveCard(
              live: (d['live'] as Map?)?.cast<String, dynamic>() ?? const {},
              ar: ar)),
          SliverToBoxAdapter(child: _SectionTitle(
              icon: Icons.grid_view_rounded,
              title: ar ? 'الإدارة' : 'Management')),
          SliverToBoxAdapter(child: _ManagementGrid(ar: ar)),
          SliverToBoxAdapter(child: _SectionTitle(
              icon: Icons.insights_rounded,
              title: ar ? 'التحليلات والمقارنات' : 'Analytics & comparisons')),
          SliverToBoxAdapter(child: _PeriodBar(
              period: _period, loading: _loading, ar: ar, onPick: _pick)),
          if (range != null) ...[
            SliverToBoxAdapter(child: _RangeSummary(range: range, ar: ar)),
            SliverToBoxAdapter(child: _KpiGrid(
                kpis: (range['kpis'] as Map?)?.cast<String, dynamic>()
                    ?? const {}, sym: sym, ar: ar)),
            SliverToBoxAdapter(child: _RangeChart(
                series: (range['series'] as List?) ?? const [],
                sym: sym, ar: ar)),
            SliverToBoxAdapter(child: _HourlyCard(
                hourly: (range['hourly'] as List?) ?? const [], ar: ar)),
            SliverToBoxAdapter(child: _Breakdown(
                title: ar ? 'المبيعات حسب القناة' : 'Sales by channel',
                icon: Icons.storefront_rounded,
                items: (range['by_channel'] as List?) ?? const [], sym: sym)),
            SliverToBoxAdapter(child: _Breakdown(
                title: ar ? 'المبيعات حسب الفئة' : 'Sales by category',
                icon: Icons.category_rounded,
                items: (range['by_category'] as List?) ?? const [], sym: sym)),
            SliverToBoxAdapter(child: _Breakdown(
                title: ar ? 'المبيعات حسب المحافظة' : 'Sales by governorate',
                icon: Icons.location_on_rounded,
                items: (range['by_governorate'] as List?) ?? const [],
                sym: sym)),
            SliverToBoxAdapter(child: _TopList(
                title: ar ? 'الأكثر مبيعاً' : 'Top products',
                icon: Icons.local_fire_department_rounded,
                items: (range['top_products'] as List?) ?? const [],
                sym: sym, qtyKey: 'qty', qtyLabel: ar ? 'قطعة' : 'pcs')),
            SliverToBoxAdapter(child: _TopList(
                title: ar ? 'أفضل العملاء' : 'Top customers',
                icon: Icons.emoji_events_rounded,
                items: (range['top_customers'] as List?) ?? const [],
                sym: sym, qtyKey: 'orders', qtyLabel: ar ? 'طلب' : 'orders')),
          ],
          SliverToBoxAdapter(child: _PosCard(
              pos: (d['pos'] as Map?)?.cast<String, dynamic>(), ar: ar)),
          const SliverToBoxAdapter(child: SizedBox(height: 30)),
        ]),
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
      (Icons.headset_mic_rounded, ar ? 'خدمة العملاء' : 'Customer Service',
          ar ? 'ردود مباشرة + بينا' : 'Live replies + Beena',
          const Color(0xFF2F7D72),
          () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => const AdminCustomerServiceScreen()))),
      (Icons.directions_walk_rounded, ar ? 'نشاط العملاء' : 'Activity',
          ar ? 'ماذا يفعل العميل لحظيًا' : 'What customers do',
          const Color(0xFF0EA5E9),
          () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => const AdminActivityScreen()))),
      (Icons.campaign_rounded, ar ? 'الإشعارات' : 'Notifications',
          ar ? 'إرسال Push + إحصائيات' : 'Send push + stats',
          const Color(0xFFC2410C),
          () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => const AdminNotificationsScreen()))),
      (Icons.card_giftcard_rounded, ar ? 'خدمة الهدايا' : 'Gift Service',
          ar ? 'الهدية المجانية والإعدادات' : 'Free gift & settings',
          const Color(0xFFCA8A04),
          () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => const AdminGiftScreen()))),
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

// ═════════ v2.2.x — period filter + period-over-period comparisons ═══════════

BoxDecoration _cardDeco() => BoxDecoration(
    color: Colors.white, borderRadius: BorderRadius.circular(18),
    boxShadow: const [BoxShadow(color: Color(0x12000000),
        blurRadius: 10, offset: Offset(0, 4))]);

String _fmtNum(num v) {
  if (v >= 1000) {
    final k = v / 1000.0;
    return '${k.toStringAsFixed(k >= 100 ? 0 : 1)}k';
  }
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  return v.toStringAsFixed(v < 10 ? 2 : 1);
}

// ── period selector chips (today / 7d / 30d / month / YTD / custom) ──
class _PeriodBar extends StatelessWidget {
  const _PeriodBar({required this.period, required this.loading,
      required this.ar, required this.onPick});
  final String period;
  final bool loading;
  final bool ar;
  final void Function(String, {String? from, String? to}) onPick;

  @override
  Widget build(BuildContext context) {
    final opts = <(String, String)>[
      ('today', ar ? 'اليوم' : 'Today'),
      ('7d', ar ? '٧ أيام' : '7 days'),
      ('30d', ar ? '٣٠ يوم' : '30 days'),
      ('month', ar ? 'هذا الشهر' : 'This month'),
      ('ytd', ar ? 'السنة' : 'YTD'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 2),
      child: Row(children: [
        Expanded(child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final o in opts) Padding(
              padding: const EdgeInsets.only(right: 7),
              child: _chip(o.$2, period == o.$1, () => onPick(o.$1))),
            _chip(ar ? '📅 مخصّص' : '📅 Custom', period == 'custom',
                () => _pickRange(context)),
          ]),
        )),
        if (loading) const Padding(padding: EdgeInsets.only(left: 8),
          child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(
              strokeWidth: 2, color: UellowColors.darkBrown))),
      ]),
    );
  }

  Widget _chip(String label, bool on, VoidCallback onTap) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(999),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: on ? UellowColors.darkBrown : Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
            color: on ? UellowColors.darkBrown : const Color(0x22000000)),
      ),
      child: Text(label, style: TextStyle(fontSize: 12.5,
          fontWeight: FontWeight.w800,
          color: on ? Colors.white : UellowColors.darkBrown)),
    ),
  );

  Future<void> _pickRange(BuildContext context) async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: DateTimeRange(
          start: now.subtract(const Duration(days: 7)), end: now),
    );
    if (r == null) return;
    String f(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}'
        '-${d.day.toString().padLeft(2, '0')}';
    onPick('custom', from: f(r.start), to: f(r.end));
  }
}

// ── range label (from → to · N days · vs previous) ──
class _RangeSummary extends StatelessWidget {
  const _RangeSummary({required this.range, required this.ar});
  final Map<String, dynamic> range;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    final from = range['from']?.toString() ?? '';
    final to = range['to']?.toString() ?? '';
    final days = (range['days'] as num?)?.toInt() ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
      child: Row(children: [
        const Icon(Icons.event_rounded, size: 13, color: UellowColors.muted),
        const SizedBox(width: 5),
        Expanded(child: Text('$from → $to · $days ${ar ? 'يوم' : 'days'}',
            style: const TextStyle(fontSize: 11, color: UellowColors.muted,
                fontWeight: FontWeight.w700))),
        Text(ar ? 'مقارنة بالفترة السابقة' : 'vs previous period',
            style: const TextStyle(fontSize: 10, color: UellowColors.muted)),
      ]),
    );
  }
}

// ── KPI grid with period-over-period deltas (↑/↓ %) ──
class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.kpis, required this.sym, required this.ar});
  final Map<String, dynamic> kpis;
  final String sym;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    final defs = <(String, String, IconData, bool)>[
      ('revenue', ar ? 'الإيرادات' : 'Revenue', Icons.payments_rounded, true),
      ('orders', ar ? 'الطلبات' : 'Orders', Icons.receipt_long_rounded, false),
      ('aov', ar ? 'متوسط الطلب' : 'Avg order', Icons.sell_rounded, true),
      ('units', ar ? 'القطع المباعة' : 'Units sold',
          Icons.inventory_2_rounded, false),
      ('new_customers', ar ? 'عملاء جدد' : 'New customers',
          Icons.person_add_alt_1_rounded, false),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      child: GridView.count(
        crossAxisCount: 2, shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.5,
        children: [
          for (final def in defs)
            _KpiCard(label: def.$2, icon: def.$3, money: def.$4, sym: sym,
                kpi: (kpis[def.$1] as Map?)?.cast<String, dynamic>()
                    ?? const {}),
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.label, required this.icon, required this.kpi,
      required this.money, required this.sym});
  final String label;
  final IconData icon;
  final Map<String, dynamic> kpi;
  final bool money;
  final String sym;
  @override
  Widget build(BuildContext context) {
    final v = (kpi['value'] as num?) ?? 0;
    final dp = kpi['delta_pct'] as num?;
    final up = (dp ?? 0) >= 0;
    final col = dp == null ? UellowColors.muted
        : (up ? const Color(0xFF059669) : const Color(0xFFDC2626));
    final valStr = money ? '${_fmtNum(v)} $sym' : _fmtNum(v);
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: _cardDeco(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(children: [
          Icon(icon, size: 16, color: UellowColors.darkBrown),
          const SizedBox(width: 6),
          Expanded(child: Text(label, maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5,
                  fontWeight: FontWeight.w700, color: UellowColors.muted))),
        ]),
        Text(valStr, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900,
                color: UellowColors.darkBrown)),
        Row(children: [
          Icon(dp == null ? Icons.remove
              : (up ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded), size: 13, color: col),
          const SizedBox(width: 2),
          Text(dp == null ? '—' : '${dp.abs().toStringAsFixed(1)}%',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
                  color: col)),
        ]),
      ]),
    );
  }
}

// ── revenue over the period: current bars + previous-period line ──
class _RangeChart extends StatelessWidget {
  const _RangeChart({required this.series, required this.sym,
      required this.ar});
  final List series;
  final String sym;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    if (series.isEmpty) return const SizedBox.shrink();
    double tot = 0, ptot = 0;
    for (final s in series) {
      tot += ((s as Map)['total'] as num?)?.toDouble() ?? 0;
      ptot += (s['prev'] as num?)?.toDouble() ?? 0;
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: _cardDeco(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.show_chart_rounded, size: 18,
              color: UellowColors.darkBrown),
          const SizedBox(width: 6),
          Text(ar ? 'الإيراد عبر الفترة' : 'Revenue over period', style: UT.h3),
          const Spacer(),
          _legend(const Color(0xFFF5C320), ar ? 'الحالية' : 'Current'),
          const SizedBox(width: 8),
          _legend(const Color(0xFF9CA3AF), ar ? 'السابقة' : 'Previous'),
        ]),
        const SizedBox(height: 14),
        SizedBox(height: 130, width: double.infinity,
            child: CustomPaint(painter: _RangePainter(series))),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('${ar ? 'الإجمالي' : 'Total'}: ${_fmtNum(tot)} $sym',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                  color: UellowColors.darkBrown)),
          Text('${ar ? 'السابق' : 'Prev'}: ${_fmtNum(ptot)} $sym',
              style: const TextStyle(fontSize: 11, color: UellowColors.muted)),
        ]),
      ]),
    );
  }

  Widget _legend(Color c, String t) => Row(mainAxisSize: MainAxisSize.min,
      children: [
    Container(width: 9, height: 9, decoration: BoxDecoration(
        color: c, borderRadius: BorderRadius.circular(2))),
    const SizedBox(width: 3),
    Text(t, style: const TextStyle(fontSize: 9.5, color: UellowColors.muted)),
  ]);
}

class _RangePainter extends CustomPainter {
  _RangePainter(this.series);
  final List series;
  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty) return;
    double maxV = 1.0;
    for (final s in series) {
      final a = ((s as Map)['total'] as num?)?.toDouble() ?? 0;
      final b = (s['prev'] as num?)?.toDouble() ?? 0;
      if (a > maxV) maxV = a;
      if (b > maxV) maxV = b;
    }
    final n = series.length;
    final gap = n > 40 ? 1.0 : 4.0;
    final bw = (size.width - gap * (n - 1)) / n;
    final cur = Paint()..color = const Color(0xFFF5C320);
    final prevLine = Paint()
      ..color = const Color(0xFF9CA3AF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final h = size.height - 6;
    final path = Path();
    for (var i = 0; i < n; i++) {
      final m = series[i] as Map;
      final v = (m['total'] as num?)?.toDouble() ?? 0;
      final p = (m['prev'] as num?)?.toDouble() ?? 0;
      final x = i * (bw + gap);
      final bh = (v / maxV) * h;
      canvas.drawRRect(RRect.fromRectAndRadius(
          Rect.fromLTWH(x, size.height - bh, bw, bh.clamp(1.0, h)),
          const Radius.circular(3)), cur);
      final cx = x + bw / 2;
      final py = size.height - (p / maxV) * h;
      if (i == 0) {
        path.moveTo(cx, py);
      } else {
        path.lineTo(cx, py);
      }
    }
    canvas.drawPath(path, prevLine);
  }

  @override
  bool shouldRepaint(covariant _RangePainter old) => old.series != series;
}

// ── sales by hour of day (peak-hour highlight) ──
class _HourlyCard extends StatelessWidget {
  const _HourlyCard({required this.hourly, required this.ar});
  final List hourly;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    if (hourly.isEmpty) return const SizedBox.shrink();
    int best = 0;
    double bestV = -1;
    for (var i = 0; i < hourly.length; i++) {
      final v = (hourly[i] as num?)?.toDouble() ?? 0;
      if (v > bestV) { bestV = v; best = i; }
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: _cardDeco(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.schedule_rounded, size: 18,
              color: UellowColors.darkBrown),
          const SizedBox(width: 6),
          Text(ar ? 'المبيعات حسب الساعة' : 'Sales by hour', style: UT.h3),
          const Spacer(),
          Text('${ar ? 'الذروة' : 'Peak'}: $best:00',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                  color: Color(0xFFB45309))),
        ]),
        const SizedBox(height: 12),
        SizedBox(height: 86, width: double.infinity,
            child: CustomPaint(painter: _HourlyPainter(hourly, best))),
        const SizedBox(height: 4),
        const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('0', style: TextStyle(fontSize: 8.5, color: UellowColors.muted)),
          Text('12', style: TextStyle(fontSize: 8.5, color: UellowColors.muted)),
          Text('23', style: TextStyle(fontSize: 8.5, color: UellowColors.muted)),
        ]),
      ]),
    );
  }
}

class _HourlyPainter extends CustomPainter {
  _HourlyPainter(this.hourly, this.best);
  final List hourly;
  final int best;
  @override
  void paint(Canvas canvas, Size size) {
    if (hourly.isEmpty) return;
    double maxV = 1.0;
    for (final h in hourly) {
      final v = (h as num?)?.toDouble() ?? 0;
      if (v > maxV) maxV = v;
    }
    final n = hourly.length;
    const gap = 3.0;
    final bw = (size.width - gap * (n - 1)) / n;
    final norm = Paint()
      ..color = const Color(0xFF412402).withValues(alpha: .22);
    final hot = Paint()..color = const Color(0xFFF5C320);
    for (var i = 0; i < n; i++) {
      final v = (hourly[i] as num?)?.toDouble() ?? 0;
      final bh = (v / maxV) * (size.height - 2);
      final x = i * (bw + gap);
      canvas.drawRRect(RRect.fromRectAndRadius(
          Rect.fromLTWH(x, size.height - bh, bw, bh.clamp(1.0, size.height)),
          const Radius.circular(2)), i == best ? hot : norm);
    }
  }

  @override
  bool shouldRepaint(covariant _HourlyPainter old) => old.hourly != hourly;
}

// ── generic breakdown with horizontal bars (channel / category / gov) ──
class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.title, required this.icon,
      required this.items, required this.sym});
  final String title;
  final IconData icon;
  final List items;
  final String sym;
  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    double maxV = 1.0;
    for (final it in items) {
      final v = ((it as Map)['total'] as num?)?.toDouble() ?? 0;
      if (v > maxV) maxV = v;
    }
    const palette = [Color(0xFFF5C320), Color(0xFF2563EB), Color(0xFF059669),
        Color(0xFF7C3AED), Color(0xFFE11D48), Color(0xFFB45309),
        Color(0xFF0EA5E9)];
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: _cardDeco(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 18, color: UellowColors.darkBrown),
          const SizedBox(width: 6),
          Text(title, style: UT.h3),
        ]),
        const SizedBox(height: 12),
        for (var i = 0; i < items.length; i++)
          _bar(items[i] as Map, maxV, palette[i % palette.length]),
      ]),
    );
  }

  Widget _bar(Map it, double maxV, Color c) {
    final v = (it['total'] as num?)?.toDouble() ?? 0;
    final name = it['name']?.toString() ?? '';
    final frac = (v / maxV).clamp(0.02, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(name, maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                  color: UellowColors.darkBrown))),
          Text('${_fmtNum(v)} $sym', style: const TextStyle(fontSize: 11.5,
              fontWeight: FontWeight.w800, color: UellowColors.darkBrown)),
        ]),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(value: frac, minHeight: 7,
            backgroundColor: const Color(0x11000000),
            valueColor: AlwaysStoppedAnimation<Color>(c)),
        ),
      ]),
    );
  }
}

// ── ranked list (top products / top customers) ──
class _TopList extends StatelessWidget {
  const _TopList({required this.title, required this.icon, required this.items,
      required this.sym, required this.qtyKey, required this.qtyLabel});
  final String title;
  final IconData icon;
  final List items;
  final String sym;
  final String qtyKey;
  final String qtyLabel;
  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: _cardDeco(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 18, color: UellowColors.darkBrown),
          const SizedBox(width: 6),
          Text(title, style: UT.h3),
        ]),
        const SizedBox(height: 10),
        for (var i = 0; i < items.length; i++)
          _row(i + 1, items[i] as Map),
      ]),
    );
  }

  Widget _row(int rank, Map it) {
    final name = it['name']?.toString() ?? '';
    final q = (it[qtyKey] as num?)?.toInt() ?? 0;
    final tot = (it['total'] as num?)?.toDouble() ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Container(width: 22, height: 22, alignment: Alignment.center,
          decoration: BoxDecoration(
            color: rank <= 3 ? const Color(0xFFF5C320) : const Color(0x11000000),
            borderRadius: BorderRadius.circular(7)),
          child: Text('$rank', style: TextStyle(fontSize: 11,
              fontWeight: FontWeight.w900,
              color: rank <= 3 ? const Color(0xFF412402)
                  : UellowColors.muted))),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700,
                  color: UellowColors.darkBrown)),
          Text('$q $qtyLabel', style: const TextStyle(fontSize: 10,
              color: UellowColors.muted)),
        ])),
        const SizedBox(width: 8),
        Text('${_fmtNum(tot)} $sym', style: const TextStyle(fontSize: 12.5,
            fontWeight: FontWeight.w900, color: UellowColors.darkBrown)),
      ]),
    );
  }
}
