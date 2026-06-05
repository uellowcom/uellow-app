// =============================================================================
// AffiliateScreen (v2.1.58) — مركز شركاء يلو. Four tabs:
//   لوحتي  — code + tier + balances + next-tier progress + leaderboard
//   منتجاتي — sellable catalog w/ commission per product + 1-tap share
//   طلباتي — submitted orders (compose → admin review → approved/rejected)
//   محفظتي — commissions ledger + payout requests
// Guests / non-affiliates get a premium "join the program" pitch + apply.
// =============================================================================
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../api/uellow_api.dart';
import '../theme/uellow_theme.dart';

class AffiliateScreen extends StatefulWidget {
  const AffiliateScreen({super.key});
  @override
  State<AffiliateScreen> createState() => _AffiliateScreenState();
}

class _AffiliateScreenState extends State<AffiliateScreen> {
  Map<String, dynamic>? _me;        // null = loading
  bool _error = false;
  bool _signedOut = false;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final tok = await UellowApi.instance.tokenStore.readToken();
      if (tok == null || tok.isEmpty) {
        if (mounted) setState(() => _signedOut = true);
        return;
      }
      final me = await UellowApi.instance.affiliate.me();
      if (mounted) setState(() => _me = me);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: UellowColors.bg,
        appBar: AppBar(
          backgroundColor: UellowColors.darkBrown,
          foregroundColor: UellowColors.yellowLight,
          title: Text(ar ? '🤝 شركاء يلو' : '🤝 Uellow Partners',
              style: const TextStyle(fontWeight: FontWeight.w900,
                  fontSize: 16)),
        ),
        body: _body(ar),
      ),
    );
  }

  Widget _body(bool ar) {
    if (_signedOut) return _JoinPitch(signedOut: true, onDone: _load);
    if (_error) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.cloud_off_outlined, size: 56,
            color: UellowColors.muted),
        const SizedBox(height: 12),
        ElevatedButton(
            onPressed: () { setState(() => _error = false); _load(); },
            child: Text(ar ? 'إعادة المحاولة' : 'Retry')),
      ]));
    }
    final me = _me;
    if (me == null) {
      return const Center(child: CircularProgressIndicator(
          color: UellowColors.darkBrown));
    }
    final status = (me['status'] ?? 'none').toString();
    if (status == 'none') return _JoinPitch(onDone: _load);
    if (status == 'pending') {
      return Center(child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('⏳', style: TextStyle(fontSize: 52)),
          const SizedBox(height: 12),
          Text(ar ? 'طلبك قيد المراجعة' : 'Your application is under review',
              style: UT.h2, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(ar ? 'سيتم تفعيل حسابك من إدارة يلو قريباً — كودك: ${me['code']}'
                  : 'Uellow admin will activate you soon — your code: ${me['code']}',
              style: UT.body, textAlign: TextAlign.center),
        ]),
      ));
    }
    if (status == 'suspended') {
      return Center(child: Padding(
        padding: const EdgeInsets.all(36),
        child: Text(ar ? 'حسابك موقوف مؤقتاً — تواصل مع إدارة يلو'
                       : 'Your account is suspended — contact Uellow',
            style: UT.h2, textAlign: TextAlign.center),
      ));
    }
    // active
    return Column(children: [
      Container(
        color: Colors.white,
        child: Row(children: [
          for (final (i, label) in [
            (0, ar ? 'لوحتي' : 'Board'),
            (1, ar ? 'منتجاتي' : 'Products'),
            (2, ar ? 'طلباتي' : 'Orders'),
            (3, ar ? 'محفظتي' : 'Wallet'),
          ]) Expanded(child: InkWell(
            onTap: () => setState(() => _tab = i),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(
                color: _tab == i ? UellowColors.yellow : Colors.transparent,
                width: 2.5,
              ))),
              child: Text(label, textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5,
                      fontWeight:
                          _tab == i ? FontWeight.w900 : FontWeight.w600,
                      color: _tab == i
                          ? UellowColors.darkBrown : UellowColors.muted)),
            ),
          )),
        ]),
      ),
      Expanded(child: switch (_tab) {
        1 => const _ProductsTab(),
        2 => _OrdersTab(onChanged: _load),
        3 => _WalletTab(me: me, onChanged: _load),
        _ => _DashboardTab(me: me),
      }),
    ]);
  }
}

// ─── Join pitch + apply ───────────────────────────────────────────────

class _JoinPitch extends StatelessWidget {
  const _JoinPitch({this.signedOut = false, required this.onDone});
  final bool signedOut;
  final VoidCallback onDone;
  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return ListView(padding: const EdgeInsets.all(18), children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [UellowColors.darkBrown, Color(0xFF7A4A08)]),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(children: [
          const Text('🤝', style: TextStyle(fontSize: 46)),
          const SizedBox(height: 8),
          Text(ar ? 'اربح مع يلو' : 'Earn with Uellow',
              style: const TextStyle(color: UellowColors.yellowLight,
                  fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(ar
              ? 'بِع منتجات يلو لعملائك واربح عمولة على كل طلب ناجح'
              : 'Sell Uellow products to your customers and earn a commission on every delivered order',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
        ]),
      ),
      const SizedBox(height: 14),
      for (final f in [
        (ar ? 'عمولة على كل منتج تبيعه — تشوفها قبل البيع' : 'Per-product commission, visible before you sell', '💰'),
        (ar ? 'رابط مشاركة جاهز لكل منتج (واتساب وغيره)' : 'Ready share link per product (WhatsApp etc.)', '🔗'),
        (ar ? 'سجّل طلب عميلك بنفسك وأرسله للإدارة' : 'Or place the order yourself for admin approval', '📝'),
        (ar ? 'مستويات Bronze → Platinum بمضاعفات عمولة' : 'Bronze → Platinum tiers with commission multipliers', '🏆'),
        (ar ? 'سحب الأرباح: بنك / KNET / رصيد محفظة يلو' : 'Withdraw: bank / KNET / Uellow wallet credit', '💸'),
      ]) Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Text(f.$2, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(child: Text(f.$1, style: const TextStyle(fontSize: 13,
              fontWeight: FontWeight.w600, color: UellowColors.text))),
        ]),
      ),
      const SizedBox(height: 16),
      ElevatedButton(
        onPressed: () async {
          if (signedOut) {
            Navigator.pushNamed(context, '/auth');
            return;
          }
          try {
            await UellowApi.instance.affiliate.apply();
            onDone();
          } on UellowApiException catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(e.message)));
            }
          }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: UellowColors.yellow,
          foregroundColor: UellowColors.darkBrown,
          padding: const EdgeInsets.symmetric(vertical: 15),
        ),
        child: Text(
            signedOut
                ? (ar ? 'سجّل دخولك أولاً' : 'Sign in first')
                : (ar ? 'قدّم طلب انضمام الآن' : 'Apply now'),
            style: const TextStyle(fontWeight: FontWeight.w900,
                fontSize: 14)),
      ),
    ]);
  }
}

// ─── Dashboard tab ────────────────────────────────────────────────────

class _DashboardTab extends StatelessWidget {
  const _DashboardTab({required this.me});
  final Map<String, dynamic> me;

  String _fmt(Map? m) =>
      '${((m?['amount'] as num?) ?? 0).toStringAsFixed(3)} '
      '${UellowApi.instance.lang == 'ar' ? 'د.ك' : (m?['symbol'] ?? 'KD')}';

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    final tier = (me['tier'] ?? 'bronze').toString();
    final tierEmoji = {'bronze': '🥉', 'silver': '🥈', 'gold': '🥇',
        'platinum': '💎'}[tier] ?? '🥉';
    final next = (me['next_tier'] as Map?)?.cast<String, dynamic>();
    final code = (me['code'] ?? '').toString();
    final link = ((me['links'] as Map?)?['short']
        ?? (me['links'] as Map?)?['web'] ?? '').toString();
    return ListView(padding: const EdgeInsets.all(14), children: [
      // code card
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [
              UellowColors.darkBrown, Color(0xFF6B4A1B)]),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(children: [
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(ar ? 'كود الشريك' : 'Partner code',
                style: const TextStyle(color: Colors.white60, fontSize: 11)),
            Text(code, style: const TextStyle(
                color: UellowColors.yellowLight, fontSize: 24,
                fontWeight: FontWeight.w900, letterSpacing: 2)),
            Text('$tierEmoji ${tier.toUpperCase()} · ×${me['tier_multiplier'] ?? 1}',
                style: const TextStyle(color: Colors.white70,
                    fontSize: 11, fontWeight: FontWeight.w700)),
          ])),
          Column(children: [
            IconButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: link));
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    duration: const Duration(seconds: 1),
                    content: Text(ar ? 'نُسخ الرابط' : 'Link copied')));
              },
              icon: const Icon(Icons.copy, color: UellowColors.yellowLight),
            ),
            IconButton(
              onPressed: () => Share.share(ar
                  ? 'تسوّق من يلو عبر رابطي 🛍️\n$link'
                  : 'Shop Uellow through my link 🛍️\n$link'),
              icon: const Icon(Icons.share, color: UellowColors.yellowLight),
            ),
          ]),
        ]),
      ),
      const SizedBox(height: 12),
      // balances row
      Row(children: [
        _stat(ar ? 'متاح للسحب' : 'Available',
            _fmt(me['available'] as Map?), const Color(0xFF1F8A40)),
        const SizedBox(width: 8),
        _stat(ar ? 'قيد التوصيل' : 'Pending',
            _fmt(me['pending'] as Map?), const Color(0xFFB8860B)),
        const SizedBox(width: 8),
        _stat(ar ? 'مدفوع' : 'Paid',
            _fmt(me['paid'] as Map?), UellowColors.muted),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        _stat(ar ? 'مبيعات الشهر' : 'This month',
            _fmt(me['month_commission'] as Map?), UellowColors.darkBrown),
        const SizedBox(width: 8),
        _stat(ar ? 'إجمالي المبيعات' : 'Total sales',
            _fmt(me['total_sales'] as Map?), UellowColors.darkBrown),
        const SizedBox(width: 8),
        _stat(ar ? 'فتحات الرابط' : 'Link opens',
            '${me['click_count'] ?? 0}', UellowColors.darkBrown),
      ]),
      if (next != null) ...[
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white,
              borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(ar
                ? 'الترقية إلى ${next['tier']} عند ${next['needed']} د.ك مبيعات شهرية'
                : 'Reach ${next['needed']} KD monthly sales for ${next['tier']}',
                style: const TextStyle(fontSize: 12,
                    fontWeight: FontWeight.w800, color: UellowColors.ink)),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: ((next['progress'] as num?) ?? 0).toDouble(),
                minHeight: 9,
                backgroundColor: const Color(0xFFEFEFEF),
                color: UellowColors.yellow,
              ),
            ),
          ]),
        ),
      ],
      const SizedBox(height: 14),
      _Leaderboard(),
    ]);
  }

  Widget _stat(String label, String value, Color color) =>
      Expanded(child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(color: Colors.white,
            borderRadius: BorderRadius.circular(12)),
        child: Column(children: [
          FittedBox(child: Text(value, style: TextStyle(fontSize: 14,
              fontWeight: FontWeight.w900, color: color))),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 9.5,
              color: UellowColors.muted, fontWeight: FontWeight.w700)),
        ]),
      ));
}

class _Leaderboard extends StatefulWidget {
  @override
  State<_Leaderboard> createState() => _LeaderboardState();
}

class _LeaderboardState extends State<_Leaderboard> {
  Map<String, dynamic>? _data;
  @override
  void initState() {
    super.initState();
    UellowApi.instance.affiliate.leaderboard().then((d) {
      if (mounted) setState(() => _data = d);
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    final top = List<Map<String, dynamic>>.from(
        (_data?['top'] as List?) ?? const []);
    if (top.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white,
          borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(ar ? '🏆 متصدرو الشهر' : '🏆 Monthly leaderboard',
            style: const TextStyle(fontSize: 13,
                fontWeight: FontWeight.w900, color: UellowColors.ink)),
        const SizedBox(height: 8),
        for (final r in top) Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            SizedBox(width: 26, child: Text(
                ['🥇', '🥈', '🥉'].elementAtOrNull(
                    ((r['rank'] as num?) ?? 4).toInt() - 1)
                    ?? '${r['rank']}.',
                style: const TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w800))),
            Expanded(child: Text((r['name'] ?? '').toString(),
                style: TextStyle(fontSize: 12,
                    fontWeight: r['me'] == true
                        ? FontWeight.w900 : FontWeight.w600,
                    color: r['me'] == true
                        ? UellowColors.darkBrown : UellowColors.text))),
            Text('${(((r['amount'] as Map?)?['amount'] as num?) ?? 0).toStringAsFixed(3)} ${ar ? 'د.ك' : 'KD'}',
                style: const TextStyle(fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1F8A40))),
          ]),
        ),
        if (_data?['my_rank'] != null) Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(ar ? 'ترتيبك: #${_data!['my_rank']}'
                         : 'Your rank: #${_data!['my_rank']}',
              style: const TextStyle(fontSize: 11,
                  color: UellowColors.muted, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}

// ─── Products tab ─────────────────────────────────────────────────────

class _ProductsTab extends StatefulWidget {
  const _ProductsTab();
  @override
  State<_ProductsTab> createState() => _ProductsTabState();
}

class _ProductsTabState extends State<_ProductsTab> {
  List<Map<String, dynamic>>? _items;
  final _q = TextEditingController();

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final v = await UellowApi.instance.affiliate
          .products(q: _q.text.trim());
      if (mounted) setState(() => _items = v);
    } catch (_) {
      if (mounted) setState(() => _items = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    final items = _items;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        child: TextField(
          controller: _q,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _load(),
          decoration: InputDecoration(
            hintText: ar ? 'ابحث في كتالوجك…' : 'Search your catalog…',
            prefixIcon: const Icon(Icons.search, size: 18),
            isDense: true, filled: true, fillColor: Colors.white,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none),
          ),
        ),
      ),
      Expanded(child: items == null
          ? const Center(child: CircularProgressIndicator(
              color: UellowColors.darkBrown))
          : items.isEmpty
              ? Center(child: Text(
                  ar ? 'لا توجد منتجات في كتالوجك بعد' : 'No products yet',
                  style: UT.body))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 20),
                  itemCount: items.length,
                  itemBuilder: (_, i) => _productRow(items[i], ar),
                )),
    ]);
  }

  Widget _productRow(Map<String, dynamic> m, bool ar) {
    final name = (((m['name'] as Map?)?[ar ? 'ar' : 'en'])
        ?? (m['name'] as Map?)?['en'] ?? '').toString();
    final img = (m['image'] as String?) ?? '';
    final price = ((m['price'] as Map?)?['amount'] as num?) ?? 0;
    final commPct = (m['commission_pct'] as num?) ?? 0;
    final commAmt = ((m['commission_amount'] as Map?)?['amount']
        as num?) ?? 0;
    final shareText = (m['share_text'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.white,
          borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: CachedNetworkImage(
              imageUrl: img.startsWith('http')
                  ? img : '${UellowApi.instance.baseUrl}$img',
              width: 64, height: 64, fit: BoxFit.cover,
              errorWidget: (_, __, ___) =>
                  const ColoredBox(color: Color(0xFFEFEFEF))),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12,
                  fontWeight: FontWeight.w700, color: UellowColors.ink)),
          const SizedBox(height: 4),
          Row(children: [
            Text('${price.toStringAsFixed(3)} ${ar ? 'د.ك' : 'KD'}',
                style: const TextStyle(fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: UellowColors.darkBrown)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFE6F7EF),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                  ar ? 'عمولتك ${commAmt.toStringAsFixed(3)} (${commPct.toStringAsFixed(1)}%)'
                     : 'Earn ${commAmt.toStringAsFixed(3)} (${commPct.toStringAsFixed(1)}%)',
                  style: const TextStyle(fontSize: 9.5,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1F8A40))),
            ),
          ]),
        ])),
        IconButton(
          tooltip: ar ? 'مشاركة' : 'Share',
          onPressed: () => Share.share(shareText),
          icon: const Icon(Icons.share, size: 20,
              color: UellowColors.darkBrown),
        ),
      ]),
    );
  }
}

// ─── Orders tab ───────────────────────────────────────────────────────

class _OrdersTab extends StatefulWidget {
  const _OrdersTab({required this.onChanged});
  final VoidCallback onChanged;
  @override
  State<_OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends State<_OrdersTab> {
  List<Map<String, dynamic>>? _orders;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final v = await UellowApi.instance.affiliate.orders();
      if (mounted) setState(() => _orders = v);
    } catch (_) {
      if (mounted) setState(() => _orders = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    final orders = _orders;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: UellowColors.yellow,
        foregroundColor: UellowColors.darkBrown,
        onPressed: () async {
          final created = await Navigator.push<bool>(context,
              MaterialPageRoute(builder: (_) =>
                  const AffiliateOrderComposer()));
          if (created == true) { _load(); widget.onChanged(); }
        },
        icon: const Icon(Icons.add),
        label: Text(ar ? 'طلب جديد' : 'New order',
            style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: orders == null
          ? const Center(child: CircularProgressIndicator(
              color: UellowColors.darkBrown))
          : orders.isEmpty
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(30),
                  child: Text(
                      ar ? 'سجّل أول طلب لعميلك بزر «طلب جديد» —\nبعد موافقة الإدارة وتسليمه تنزل عمولتك تلقائياً'
                         : 'Create your first customer order — once approved and delivered your commission books automatically',
                      textAlign: TextAlign.center, style: UT.body)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 90),
                  itemCount: orders.length,
                  itemBuilder: (_, i) => _orderCard(orders[i], ar),
                ),
    );
  }

  Widget _orderCard(Map<String, dynamic> o, bool ar) {
    final state = (o['state'] ?? '').toString();
    final (chipBg, chipFg, label) = switch (state) {
      'submitted' => (const Color(0xFFFFF3D6), const Color(0xFF8B6508),
          ar ? '📨 قيد المراجعة' : '📨 Under review'),
      'approved' => (const Color(0xFFE6F7EF), const Color(0xFF1F8A40),
          ar ? '✅ مقبول' : '✅ Approved'),
      'rejected' => (const Color(0xFFFDE8E8), const Color(0xFFC0392B),
          ar ? '❌ مرفوض' : '❌ Rejected'),
      _ => (const Color(0xFFEFEFEF), UellowColors.muted,
          ar ? 'مسودة' : 'Draft'),
    };
    final total = ((o['total'] as Map?)?['amount'] as num?) ?? 0;
    final comm = ((o['commission'] as Map?)?['amount'] as num?) ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white,
          borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text((o['name'] ?? '').toString(), style: const TextStyle(
              fontWeight: FontWeight.w900, fontSize: 13,
              color: UellowColors.ink)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: chipBg,
                borderRadius: BorderRadius.circular(999)),
            child: Text(label, style: TextStyle(fontSize: 10,
                fontWeight: FontWeight.w900, color: chipFg)),
          ),
        ]),
        const SizedBox(height: 6),
        Text('${o['customer_name']} · ${o['customer_phone']}',
            style: const TextStyle(fontSize: 11.5,
                color: UellowColors.muted)),
        const SizedBox(height: 6),
        Row(children: [
          Text('${total.toStringAsFixed(3)} ${ar ? 'د.ك' : 'KD'}',
              style: const TextStyle(fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: UellowColors.darkBrown)),
          const SizedBox(width: 10),
          Text(ar ? 'عمولتك: ${comm.toStringAsFixed(3)}'
                  : 'Commission: ${comm.toStringAsFixed(3)}',
              style: const TextStyle(fontSize: 11,
                  fontWeight: FontWeight.w800, color: Color(0xFF1F8A40))),
        ]),
      ]),
    );
  }
}

// ─── Wallet tab ───────────────────────────────────────────────────────

class _WalletTab extends StatefulWidget {
  const _WalletTab({required this.me, required this.onChanged});
  final Map<String, dynamic> me;
  final VoidCallback onChanged;
  @override
  State<_WalletTab> createState() => _WalletTabState();
}

class _WalletTabState extends State<_WalletTab> {
  List<Map<String, dynamic>>? _comms;
  List<Map<String, dynamic>>? _payouts;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final c = await UellowApi.instance.affiliate.commissions();
      final p = await UellowApi.instance.affiliate.payouts();
      if (mounted) setState(() { _comms = c; _payouts = p; });
    } catch (_) {
      if (mounted) setState(() { _comms = const []; _payouts = const []; });
    }
  }

  Future<void> _requestPayout() async {
    final ar = UellowApi.instance.lang == 'ar';
    final available =
        (((widget.me['available'] as Map?)?['amount'] as num?) ?? 0)
            .toDouble();
    final minPayout = ((widget.me['min_payout'] as num?) ?? 5).toDouble();
    final amountCtrl = TextEditingController(
        text: available.toStringAsFixed(3));
    var method = (widget.me['payout_method'] ?? 'wallet').toString();
    final detailsCtrl = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius:
          BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) =>
        Directionality(
          textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
          child: Padding(
            padding: EdgeInsets.fromLTRB(18, 16, 18,
                18 + MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(ar ? '💸 طلب سحب' : '💸 Request payout', style: UT.h2),
              const SizedBox(height: 4),
              Text(ar
                  ? 'المتاح: ${available.toStringAsFixed(3)} د.ك · الحد الأدنى ${minPayout.toStringAsFixed(3)}'
                  : 'Available: ${available.toStringAsFixed(3)} KD · min ${minPayout.toStringAsFixed(3)}',
                  style: UT.small),
              const SizedBox(height: 12),
              TextField(
                controller: amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true),
                decoration: InputDecoration(
                    labelText: ar ? 'المبلغ' : 'Amount',
                    border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              Wrap(spacing: 8, children: [
                for (final m in [
                  ('wallet', ar ? '👛 محفظة يلو' : '👛 Wallet'),
                  ('knet', '💳 KNET'),
                  ('bank', ar ? '🏦 بنك' : '🏦 Bank'),
                ]) ChoiceChip(
                  label: Text(m.$2, style: const TextStyle(fontSize: 12)),
                  selected: method == m.$1,
                  selectedColor: UellowColors.yellowSoft,
                  onSelected: (_) => setSheet(() => method = m.$1),
                ),
              ]),
              if (method != 'wallet') Padding(
                padding: const EdgeInsets.only(top: 10),
                child: TextField(
                  controller: detailsCtrl,
                  decoration: InputDecoration(
                      labelText: ar ? 'IBAN / رقم الهاتف' : 'IBAN / phone',
                      border: const OutlineInputBorder()),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(width: double.infinity, child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                    backgroundColor: UellowColors.yellow,
                    foregroundColor: UellowColors.darkBrown,
                    padding: const EdgeInsets.symmetric(vertical: 13)),
                child: Text(ar ? 'إرسال الطلب' : 'Submit',
                    style: const TextStyle(fontWeight: FontWeight.w900)),
              )),
            ]),
          ),
        )),
    );
    if (ok != true) return;
    try {
      await UellowApi.instance.affiliate.requestPayout(
        amount: double.tryParse(amountCtrl.text.trim()) ?? 0,
        method: method,
        details: detailsCtrl.text.trim(),
      );
      _load(); widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
            UellowApi.instance.lang == 'ar'
                ? 'تم إرسال طلب السحب ✓' : 'Payout requested ✓')));
      }
    } on UellowApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    final comms = _comms;
    return ListView(padding: const EdgeInsets.fromLTRB(12, 10, 12, 30),
        children: [
      SizedBox(width: double.infinity, child: ElevatedButton.icon(
        onPressed: _requestPayout,
        icon: const Icon(Icons.account_balance_wallet_outlined, size: 17),
        label: Text(ar ? 'طلب سحب الأرباح' : 'Request payout',
            style: const TextStyle(fontWeight: FontWeight.w900)),
        style: ElevatedButton.styleFrom(
            backgroundColor: UellowColors.darkBrown,
            foregroundColor: UellowColors.yellowLight,
            padding: const EdgeInsets.symmetric(vertical: 13)),
      )),
      if ((_payouts ?? const []).isNotEmpty) ...[
        const SizedBox(height: 12),
        Text(ar ? 'طلبات السحب' : 'Payout requests',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900,
                color: UellowColors.ink)),
        const SizedBox(height: 6),
        for (final p in _payouts!) Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(color: Colors.white,
              borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Text((p['name'] ?? '').toString(), style: const TextStyle(
                fontWeight: FontWeight.w800, fontSize: 12)),
            const Spacer(),
            Text('${(((p['amount'] as Map?)?['amount'] as num?) ?? 0).toStringAsFixed(3)} ${ar ? 'د.ك' : 'KD'}',
                style: const TextStyle(fontWeight: FontWeight.w900,
                    fontSize: 12, color: UellowColors.darkBrown)),
            const SizedBox(width: 8),
            Text(switch ((p['state'] ?? '').toString()) {
              'paid' => ar ? '✅ مدفوع' : '✅ Paid',
              'rejected' => ar ? '❌ مرفوض' : '❌ Rejected',
              _ => ar ? '⏳ معلّق' : '⏳ Pending',
            }, style: const TextStyle(fontSize: 10.5,
                fontWeight: FontWeight.w800, color: UellowColors.muted)),
          ]),
        ),
      ],
      const SizedBox(height: 12),
      Text(ar ? 'سجل العمولات' : 'Commission ledger',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900,
              color: UellowColors.ink)),
      const SizedBox(height: 6),
      if (comms == null)
        const Center(child: Padding(padding: EdgeInsets.all(20),
            child: CircularProgressIndicator(color: UellowColors.darkBrown)))
      else if (comms.isEmpty)
        Padding(padding: const EdgeInsets.all(20),
            child: Center(child: Text(
                ar ? 'لا توجد عمولات بعد — ابدأ بمشاركة منتجاتك!'
                   : 'No commissions yet — start sharing!',
                style: UT.body)))
      else for (final c in comms) Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(color: Colors.white,
            borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Text(switch ((c['source'] ?? '').toString()) {
            'link' => '🔗', 'submitted' => '📝',
            'bonus' => '🎁', _ => '✏️',
          }, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((c['order'] ?? '').toString().isEmpty
                    ? (ar ? 'عمولة' : 'Commission')
                    : (c['order'] ?? '').toString(),
                style: const TextStyle(fontSize: 12,
                    fontWeight: FontWeight.w800, color: UellowColors.ink)),
            Text(((c['date'] ?? '') as String).split('T').first,
                style: const TextStyle(fontSize: 10,
                    color: UellowColors.muted)),
          ])),
          Text('+${(((c['amount'] as Map?)?['amount'] as num?) ?? 0).toStringAsFixed(3)}',
              style: const TextStyle(fontSize: 13,
                  fontWeight: FontWeight.w900, color: Color(0xFF1F8A40))),
          const SizedBox(width: 8),
          Text(switch ((c['state'] ?? '').toString()) {
            'confirmed' => '✅', 'paid' => '💸',
            'cancelled' => '❌', _ => '⏳',
          }, style: const TextStyle(fontSize: 13)),
        ]),
      ),
    ]);
  }
}

// ─── Order composer (separate page) ───────────────────────────────────

class AffiliateOrderComposer extends StatefulWidget {
  const AffiliateOrderComposer({super.key});
  @override
  State<AffiliateOrderComposer> createState() =>
      _AffiliateOrderComposerState();
}

class _AffiliateOrderComposerState extends State<AffiliateOrderComposer> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _area = TextEditingController();
  final _address = TextEditingController();
  final _note = TextEditingController();
  final List<Map<String, dynamic>> _lines = [];   // {product map, qty}
  bool _busy = false;

  Future<void> _pickProduct() async {
    final ar = UellowApi.instance.lang == 'ar';
    final qCtrl = TextEditingController();
    List<Map<String, dynamic>> results = [];
    await showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius:
          BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        Future<void> search() async {
          try {
            final v = await UellowApi.instance.affiliate
                .products(q: qCtrl.text.trim());
            setSheet(() => results = v);
          } catch (_) {}
        }
        if (results.isEmpty && qCtrl.text.isEmpty) search();
        return Directionality(
          textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.75,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: TextField(
                  controller: qCtrl,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => search(),
                  decoration: InputDecoration(
                    hintText: ar ? 'ابحث عن منتج…' : 'Search a product…',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              Expanded(child: ListView.builder(
                itemCount: results.length,
                itemBuilder: (_, i) {
                  final m = results[i];
                  final nm = (((m['name'] as Map?)?[ar ? 'ar' : 'en'])
                      ?? (m['name'] as Map?)?['en'] ?? '').toString();
                  final img = (m['image'] as String?) ?? '';
                  final price =
                      ((m['price'] as Map?)?['amount'] as num?) ?? 0;
                  return ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                          imageUrl: img.startsWith('http')
                              ? img
                              : '${UellowApi.instance.baseUrl}$img',
                          width: 44, height: 44, fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => const ColoredBox(
                              color: Color(0xFFEFEFEF))),
                    ),
                    title: Text(nm, maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5)),
                    subtitle: Text(
                        '${price.toStringAsFixed(3)} ${ar ? 'د.ك' : 'KD'}',
                        style: const TextStyle(fontSize: 11,
                            fontWeight: FontWeight.w800)),
                    onTap: () {
                      setState(() => _lines.add({'product': m, 'qty': 1}));
                      Navigator.pop(ctx);
                    },
                  );
                },
              )),
            ]),
          ),
        );
      }),
    );
  }

  Future<void> _submit() async {
    final ar = UellowApi.instance.lang == 'ar';
    if (_name.text.trim().isEmpty || _phone.text.trim().isEmpty
        || _lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          ar ? 'أكمل اسم العميل + الهاتف + المنتجات'
             : 'Customer name + phone + items required')));
      return;
    }
    setState(() => _busy = true);
    try {
      await UellowApi.instance.affiliate.submitOrder(
        customerName: _name.text.trim(),
        customerPhone: _phone.text.trim(),
        area: _area.text.trim(),
        address: _address.text.trim(),
        note: _note.text.trim(),
        lines: [for (final l in _lines) {
          'product_id': (l['product'] as Map)['id'],
          'qty': l['qty'],
        }],
      );
      if (mounted) Navigator.pop(context, true);
    } on UellowApiException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    double total = 0, comm = 0;
    for (final l in _lines) {
      final m = l['product'] as Map;
      final qty = (l['qty'] as num).toDouble();
      total += (((m['price'] as Map?)?['amount'] as num?) ?? 0) * qty;
      comm += (((m['commission_amount'] as Map?)?['amount'] as num?) ?? 0)
          * qty;
    }
    return Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: UellowColors.bg,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: UellowColors.darkBrown,
          title: Text(ar ? 'طلب جديد لعميلك' : 'New customer order',
              style: const TextStyle(fontWeight: FontWeight.w900,
                  fontSize: 15)),
        ),
        body: ListView(padding: const EdgeInsets.all(14), children: [
          _field(_name, ar ? 'اسم العميل *' : 'Customer name *'),
          _field(_phone, ar ? 'هاتف العميل *' : 'Customer phone *',
              keyboard: TextInputType.phone),
          _field(_area, ar ? 'المنطقة / المدينة' : 'Area / city'),
          _field(_address, ar ? 'تفاصيل العنوان' : 'Address details',
              lines: 2),
          _field(_note, ar ? 'ملاحظة للتوصيل' : 'Delivery note'),
          const SizedBox(height: 8),
          Row(children: [
            Text(ar ? 'المنتجات (${_lines.length})'
                    : 'Items (${_lines.length})',
                style: const TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w900, color: UellowColors.ink)),
            const Spacer(),
            TextButton.icon(
              onPressed: _pickProduct,
              icon: const Icon(Icons.add, size: 16),
              label: Text(ar ? 'إضافة منتج' : 'Add item',
                  style: const TextStyle(fontWeight: FontWeight.w800,
                      fontSize: 12)),
            ),
          ]),
          for (var i = 0; i < _lines.length; i++) _lineRow(i, ar),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white,
                borderRadius: BorderRadius.circular(14)),
            child: Column(children: [
              Row(children: [
                Text(ar ? 'الإجمالي' : 'Total', style: UT.body),
                const Spacer(),
                Text('${total.toStringAsFixed(3)} ${ar ? 'د.ك' : 'KD'}',
                    style: const TextStyle(fontWeight: FontWeight.w900,
                        fontSize: 15, color: UellowColors.darkBrown)),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                Text(ar ? 'عمولتك المتوقعة' : 'Your est. commission',
                    style: UT.small),
                const Spacer(),
                Text('+${comm.toStringAsFixed(3)}',
                    style: const TextStyle(fontWeight: FontWeight.w900,
                        fontSize: 13, color: Color(0xFF1F8A40))),
              ]),
            ]),
          ),
          const SizedBox(height: 14),
          ElevatedButton(
            onPressed: _busy ? null : _submit,
            style: ElevatedButton.styleFrom(
                backgroundColor: UellowColors.yellow,
                foregroundColor: UellowColors.darkBrown,
                padding: const EdgeInsets.symmetric(vertical: 15)),
            child: _busy
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5))
                : Text(ar ? '📨 إرسال للإدارة للمراجعة'
                          : '📨 Submit for review',
                    style: const TextStyle(fontWeight: FontWeight.w900,
                        fontSize: 14)),
          ),
          const SizedBox(height: 30),
        ]),
      ),
    );
  }

  Widget _field(TextEditingController c, String label,
      {TextInputType? keyboard, int lines = 1}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: c, keyboardType: keyboard, maxLines: lines,
          decoration: InputDecoration(
            labelText: label, isDense: true,
            filled: true, fillColor: Colors.white,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none),
          ),
        ),
      );

  Widget _lineRow(int i, bool ar) {
    final m = _lines[i]['product'] as Map;
    final qty = (_lines[i]['qty'] as num).toInt();
    final nm = (((m['name'] as Map?)?[ar ? 'ar' : 'en'])
        ?? (m['name'] as Map?)?['en'] ?? '').toString();
    final price = ((m['price'] as Map?)?['amount'] as num?) ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.white,
          borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Expanded(child: Text(nm, maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12,
                fontWeight: FontWeight.w700))),
        Text('${price.toStringAsFixed(3)}', style: const TextStyle(
            fontSize: 11.5, fontWeight: FontWeight.w800,
            color: UellowColors.darkBrown)),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => setState(() {
            if (qty > 1) _lines[i]['qty'] = qty - 1;
          }),
          child: const Icon(Icons.remove_circle_outline, size: 20,
              color: UellowColors.muted),
        ),
        SizedBox(width: 26, child: Text('$qty', textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w900))),
        GestureDetector(
          onTap: () => setState(() => _lines[i]['qty'] = qty + 1),
          child: const Icon(Icons.add_circle_outline, size: 20,
              color: UellowColors.darkBrown),
        ),
        const SizedBox(width: 6),
        GestureDetector(
          onTap: () => setState(() => _lines.removeAt(i)),
          child: const Icon(Icons.delete_outline, size: 19,
              color: UellowColors.danger),
        ),
      ]),
    );
  }
}
