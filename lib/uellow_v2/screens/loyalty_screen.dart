// =============================================================================
// LoyaltyScreen — real points, tier, perks, earn rules, redeem options &
// history from /api/mobile/v2/loyalty. Redeem flow calls
// /loyalty/redeem and surfaces the issued coupon code in a beautiful
// dialog the customer can copy or use immediately at checkout.
// =============================================================================
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../api/uellow_api.dart';
import '../../api/uellow_models.dart';
import '../theme/uellow_theme.dart';

class LoyaltyScreen extends StatefulWidget {
  const LoyaltyScreen({super.key});
  @override
  State<LoyaltyScreen> createState() => _LoyaltyScreenState();
}

class _LoyaltyScreenState extends State<LoyaltyScreen> {
  Future<UellowLoyalty>? _future;

  @override
  void initState() {
    super.initState();
    _future = UellowApi.instance.loyalty.overview();
  }

  Future<void> _refresh() async {
    setState(() => _future = UellowApi.instance.loyalty.overview());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return Scaffold(
      backgroundColor: UellowColors.bg,
      appBar: AppBar(
        leading: const BackButton(color: UellowColors.darkBrown),
        title: Text(ar ? 'النقاط والمكافآت' : 'Loyalty & Rewards', style: UT.h1),
      ),
      body: SafeArea(bottom: false, child: FutureBuilder<UellowLoyalty>(
        future: _future,
        builder: (_, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: UellowColors.darkBrown));
          }
          if (snap.hasError || snap.data == null) {
            return _errorState(snap.error?.toString() ?? 'Failed to load', ar);
          }
          final l = snap.data!;
          return RefreshIndicator(onRefresh: _refresh,
            child: ListView(padding: EdgeInsets.zero, children: [
              _Hero(loyalty: l, ar: ar, onRedeem: () => _showRedeemSheet(l)),
              _TierStrip(currentTier: l.tier, ar: ar),
              if (l.perks.isNotEmpty)  _PerksCard(loyalty: l, ar: ar),
              if (l.earnWays.isNotEmpty) _EarnCard(ways: l.earnWays, ar: ar),
              if (l.redeemOptions.isNotEmpty)
                _RedeemGrid(loyalty: l, ar: ar,
                    onTap: (o) => _doRedeem(o.key, o.points)),
              _HistoryCard(history: l.history, ar: ar),
              const SizedBox(height: 30),
            ]),
          );
        },
      )),
    );
  }

  void _showRedeemSheet(UellowLoyalty l) {
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RedeemSheet(loyalty: l,
          onPick: (o) { Navigator.pop(context); _doRedeem(o.key, o.points); }),
    );
  }

  Future<void> _doRedeem(String key, int points) async {
    final ar = UellowApi.instance.lang == 'ar';
    showDialog(context: context, barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator(
            color: UellowColors.darkBrown)));
    try {
      final token = await UellowApi.instance.tokenStore.readToken();
      final r = await http.post(
        Uri.parse('${UellowApi.instance.baseUrl}/api/mobile/v2/loyalty/redeem'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'option_key': key, 'points': points}),
      );
      final body = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (!mounted) return;
      Navigator.pop(context);  // dismiss spinner
      if (body['success'] == true) {
        final d = body['data'] as Map<String, dynamic>;
        final code = (d['code'] ?? '').toString();
        final kd   = (d['kd_value']?['amount'] ?? 0).toString();
        final expires = (d['expires'] ?? '').toString();
        showDialog(context: context, builder: (_) =>
            _SuccessDialog(code: code, kdValue: kd, expires: expires, ar: ar));
        _refresh();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text((body['error'] ?? 'Failed').toString())));
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())));
    }
  }

  Widget _errorState(String msg, bool ar) {
    return Center(child: Padding(padding: const EdgeInsets.all(30),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline, size: 56, color: UellowColors.muted),
        const SizedBox(height: 12),
        Text(msg, textAlign: TextAlign.center, style: UT.body),
        const SizedBox(height: 16),
        ElevatedButton.icon(onPressed: _refresh,
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(ar ? 'إعادة المحاولة' : 'Retry')),
      ])));
  }
}

// ─── Hero card ─────────────────────────────────────────────────────

class _Hero extends StatelessWidget {
  const _Hero({required this.loyalty, required this.ar, required this.onRedeem});
  final UellowLoyalty loyalty;
  final bool ar;
  final VoidCallback onRedeem;
  @override
  Widget build(BuildContext context) {
    final pts = loyalty.points;
    final kd  = loyalty.kdValue.amount;
    final tierLabel = loyalty.tierLabel.current(ar ? 'ar' : 'en').toUpperCase();
    final progress = loyalty.progressPct / 100.0;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      padding: const EdgeInsets.all(22),
      decoration: const BoxDecoration(
        gradient: UellowColors.heroLoyalty,
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
      child: Stack(children: [
        Positioned(right: -30, top: -30, child: Container(
          width: 160, height: 160,
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              colors: [Color(0x40FFFFFF), Colors.transparent],
            ),
            shape: BoxShape.circle,
          ),
        )),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(ar ? 'نقاطك' : 'YOUR POINTS', style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w800,
              color: UellowColors.darkBrown, letterSpacing: 0.6)),
          const SizedBox(height: 6),
          Text.rich(TextSpan(children: [
            TextSpan(text: '$pts', style: const TextStyle(
                fontSize: 50, fontWeight: FontWeight.w900,
                color: UellowColors.darkBrown, height: 1)),
            TextSpan(text: ar ? ' نقطة' : ' pts', style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700,
                color: UellowColors.darkBrown)),
          ])),
          const SizedBox(height: 4),
          Text(ar
              ? '= ${kd.toStringAsFixed(3)} د.ك قابلة للاستبدال'
              : '= ${kd.toStringAsFixed(3)} KD redeem value',
              style: const TextStyle(color: Color(0xFF5B3C00), fontSize: 13)),
          const SizedBox(height: 16),
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: const BoxDecoration(
                color: UellowColors.darkBrown,
                borderRadius: BorderRadius.all(Radius.circular(999)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('${_tierIcon(loyalty.tier)} $tierLabel',
                    style: const TextStyle(color: UellowColors.yellowLight,
                        fontSize: 12, fontWeight: FontWeight.w800)),
                if (loyalty.tierMultiplier > 1) ...[
                  const SizedBox(width: 6),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(color: UellowColors.yellow,
                        borderRadius: BorderRadius.circular(4)),
                    child: Text('×${loyalty.tierMultiplier.toStringAsFixed(1)}',
                        style: const TextStyle(color: UellowColors.darkBrown,
                            fontSize: 9, fontWeight: FontWeight.w900)),
                  ),
                ],
              ]),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                height: 8,
                decoration: BoxDecoration(
                  color: const Color(0x33412402),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft, widthFactor: progress,
                  child: const DecoratedBox(decoration: BoxDecoration(
                    color: UellowColors.darkBrown,
                    borderRadius: BorderRadius.all(Radius.circular(999)),
                  )),
                ),
              ),
              const SizedBox(height: 4),
              Text(loyalty.nextTier == null
                ? (ar ? 'أعلى مستوى — مبروك! 🎉'
                      : 'Top tier — congrats! 🎉')
                : (ar
                    ? '${loyalty.pointsToNext} نقطة للوصول إلى ${_tierLabelAr(loyalty.nextTier!).toUpperCase()}'
                    : '${loyalty.pointsToNext} pts to ${loyalty.nextTier!.toUpperCase()}'),
                  style: const TextStyle(color: Color(0xFF5B3C00), fontSize: 11)),
            ])),
          ]),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: ElevatedButton.icon(
            onPressed: pts >= loyalty.minRedeem ? onRedeem : null,
            icon: const Icon(Icons.card_giftcard, size: 16),
            label: Text(pts >= loyalty.minRedeem
                ? (ar ? 'استبدل نقاطك الآن' : 'Redeem your points')
                : (ar ? 'تحتاج ${loyalty.minRedeem} نقطة للاستبدال'
                      : 'Need ${loyalty.minRedeem} pts to redeem'),
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
            style: ElevatedButton.styleFrom(
              backgroundColor: UellowColors.darkBrown,
              foregroundColor: UellowColors.yellowLight,
              disabledBackgroundColor: const Color(0x55412402),
              disabledForegroundColor: const Color(0xFFFFE066),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12))),
            ),
          )),
        ]),
      ]),
    );
  }
}

String _tierIcon(String t) => switch (t) {
  'platinum' => '💎', 'gold' => '🥇', 'silver' => '🥈', _ => '🥉',
};

String _tierLabelAr(String t) => switch (t) {
  'platinum' => 'بلاتيني', 'gold' => 'ذهبي',
  'silver' => 'فضي', _ => 'برونزي',
};

// ─── Tier strip ────────────────────────────────────────────────────

class _TierStrip extends StatelessWidget {
  const _TierStrip({required this.currentTier, required this.ar});
  final String currentTier;
  final bool ar;
  static const _tiers = [
    ('🥉','Bronze',  'برونزي',   '0 pts',       'bronze'),
    ('🥈','Silver',  'فضي',     '1,000 pts',  'silver'),
    ('🥇','Gold',    'ذهبي',    '5,000 pts',  'gold'),
    ('💎','Platinum','بلاتيني', '15,000 pts', 'platinum'),
  ];
  @override
  Widget build(BuildContext context) {
    final order = ['bronze','silver','gold','platinum'];
    final curIdx = order.indexOf(currentTier);
    return SizedBox(
      height: 130,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
        itemCount: _tiers.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final t = _tiers[i];
          final on = t.$5 == currentTier;
          final achieved = i <= curIdx;
          return Container(
            width: 130, padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
            decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: on ? UellowColors.yellow : Colors.transparent, width: 2),
            ),
            child: Stack(children: [
              if (on) Positioned(top: -8, left: 0, right: 0, child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: const BoxDecoration(
                    color: UellowColors.yellow,
                    borderRadius: BorderRadius.all(Radius.circular(999)),
                  ),
                  child: Text(ar ? 'أنت' : 'YOU', style: const TextStyle(
                      color: UellowColors.darkBrown,
                      fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                ),
              )),
              if (achieved && !on) Positioned(top: -2, right: -2, child: Container(
                width: 18, height: 18, alignment: Alignment.center,
                decoration: const BoxDecoration(
                    color: UellowColors.successDk, shape: BoxShape.circle),
                child: const Icon(Icons.check, size: 11, color: Colors.white))),
              Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Opacity(opacity: achieved || on ? 1 : 0.35,
                    child: Text(t.$1, style: const TextStyle(fontSize: 28))),
                const SizedBox(height: 4),
                Text(ar ? t.$3 : t.$2, style: const TextStyle(
                    fontWeight: FontWeight.w900, color: UellowColors.darkBrown,
                    fontSize: 13)),
                Text(t.$4, style: UT.tiny),
              ]),
            ]),
          );
        },
      ),
    );
  }
}

// ─── Perks ─────────────────────────────────────────────────────────

class _PerksCard extends StatelessWidget {
  const _PerksCard({required this.loyalty, required this.ar});
  final UellowLoyalty loyalty;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    final lang = ar ? 'ar' : 'en';
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.workspace_premium, size: 16,
              color: UellowColors.darkBrown),
          const SizedBox(width: 6),
          Expanded(child: Text(ar
              ? 'مزايا مستوى ${_tierLabelAr(loyalty.tier)}'
              : '${loyalty.tier.capitalize()} tier perks', style: UT.h3)),
        ]),
        const SizedBox(height: 10),
        Column(children: loyalty.perks.map((p) => Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: UellowColors.bg)),
          ),
          child: Row(children: [
            Container(
              width: 28, height: 28, alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: UellowColors.yellowSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(_perkIcon(p.key), size: 14, color: UellowColors.darkBrown),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(p.label.current(lang),
                style: const TextStyle(fontSize: 12.5,
                    fontWeight: FontWeight.w700, color: UellowColors.ink))),
            const Icon(Icons.check_circle, size: 14, color: UellowColors.successDk),
          ]),
        )).toList()),
      ]),
    );
  }
  IconData _perkIcon(String k) => switch (k) {
    'free_shipping' => Icons.local_shipping,
    'discount_voucher' => Icons.discount,
    'early_access' => Icons.flash_on,
    'priority_support' => Icons.support_agent,
    'birthday_gift' => Icons.cake,
    _ => Icons.star,
  };
}

extension _Cap on String {
  String capitalize() => isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}

// ─── Earn ways ─────────────────────────────────────────────────────

class _EarnCard extends StatelessWidget {
  const _EarnCard({required this.ways, required this.ar});
  final List<UellowEarnWay> ways;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    final lang = ar ? 'ar' : 'en';
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.bolt, size: 16, color: UellowColors.darkBrown),
          const SizedBox(width: 6),
          Text(ar ? 'طرق لكسب نقاط أكثر' : 'Ways to earn more', style: UT.h3),
        ]),
        const SizedBox(height: 8),
        for (final w in ways) Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: UellowColors.bg)),
          ),
          child: Row(children: [
            Container(
              width: 36, height: 36,
              decoration: const BoxDecoration(
                color: UellowColors.yellowSoft,
                borderRadius: BorderRadius.all(Radius.circular(10)),
              ),
              child: Icon(_icon(w.icon), size: 18, color: UellowColors.warn),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(w.title.current(lang), style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w800, color: UellowColors.ink)),
              Text(w.detail.current(lang), style: UT.small),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: const BoxDecoration(
                color: UellowColors.successBg,
                borderRadius: BorderRadius.all(Radius.circular(6)),
              ),
              child: Text(w.badge, style: const TextStyle(
                  color: UellowColors.successDk,
                  fontSize: 11, fontWeight: FontWeight.w900)),
            ),
          ]),
        ),
      ]),
    );
  }
  IconData _icon(String k) => switch (k) {
    'cart' => Icons.shopping_cart_outlined,
    'star' => Icons.star_outline,
    'person' => Icons.person_outline,
    'cake' => Icons.cake,
    _ => Icons.bolt_outlined,
  };
}

// ─── Redeem grid ───────────────────────────────────────────────────

class _RedeemGrid extends StatelessWidget {
  const _RedeemGrid({required this.loyalty, required this.ar, required this.onTap});
  final UellowLoyalty loyalty;
  final bool ar;
  final void Function(UellowRedeemOption) onTap;
  @override
  Widget build(BuildContext context) {
    final lang = ar ? 'ar' : 'en';
    final items = loyalty.redeemOptions;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(ar ? 'استبدل نقاطك' : 'Redeem your points',
              style: UT.h3)),
        ]),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2, crossAxisSpacing: 8, mainAxisSpacing: 8,
            childAspectRatio: 0.9,
          ),
          itemCount: items.length,
          itemBuilder: (_, i) {
            final it = items[i];
            final disabled = !it.affordable;
            return Opacity(opacity: disabled ? 0.55 : 1, child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [UellowColors.yellowSoft, UellowColors.yellowFaint],
                ),
                border: Border.all(color: UellowColors.warnBg),
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [BoxShadow(color: Color(0x14000000),
                    blurRadius: 4, offset: Offset(0, 2))],
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(it.icon, style: const TextStyle(fontSize: 32)),
                const SizedBox(height: 4),
                Text(it.label.current(lang), textAlign: TextAlign.center,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800,
                        color: UellowColors.darkBrown, fontSize: 12)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: UellowColors.border)),
                  child: Text('${it.points} pts',
                      style: const TextStyle(fontSize: 10.5,
                          fontWeight: FontWeight.w800, color: UellowColors.text)),
                ),
                const SizedBox(height: 6),
                SizedBox(width: double.infinity, child: ElevatedButton(
                  onPressed: disabled ? null : () => onTap(it),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: UellowColors.yellow,
                    foregroundColor: UellowColors.darkBrown,
                    disabledBackgroundColor: UellowColors.yellowSoft,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(Radius.circular(8))),
                  ),
                  child: Text(disabled
                      ? (ar ? 'غير كافٍ' : 'Locked')
                      : (ar ? 'استبدال' : 'Redeem'),
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
                )),
              ]),
            ));
          },
        ),
      ]),
    );
  }
}

// ─── History ──────────────────────────────────────────────────────

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.history, required this.ar});
  final List<UellowLoyaltyEvent> history;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    final lang = ar ? 'ar' : 'en';
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(ar ? 'سجل النقاط' : 'Points history', style: UT.h3)),
          Text('${history.length}', style: const TextStyle(fontSize: 11,
              color: UellowColors.muted, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 8),
        if (history.isEmpty) Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Center(child: Text(ar
              ? 'لا توجد عمليات بعد — اطلب منتج لتبدأ بكسب النقاط!'
              : 'No transactions yet — place an order to start earning!',
              textAlign: TextAlign.center, style: UT.subtitle)),
        ),
        for (final e in history) Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: UellowColors.bg)),
          ),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.label.current(lang), style: const TextStyle(
                  fontSize: 13, color: UellowColors.ink, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(_friendlyDate(e.when, ar), style: UT.small),
            ])),
            Text((e.pts >= 0 ? '+' : '') + e.pts.toString(),
              style: TextStyle(
                color: e.isEarn ? UellowColors.successDk : UellowColors.dangerDk,
                fontWeight: FontWeight.w900, fontSize: 14)),
          ]),
        ),
      ]),
    );
  }
  static String _friendlyDate(String iso, bool ar) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    return '${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}';
  }
}

// ─── Redeem sheet (full picker) ───────────────────────────────────

class _RedeemSheet extends StatelessWidget {
  const _RedeemSheet({required this.loyalty, required this.onPick});
  final UellowLoyalty loyalty;
  final void Function(UellowRedeemOption) onPick;
  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    final lang = ar ? 'ar' : 'en';
    return DraggableScrollableSheet(
      expand: false, initialChildSize: 0.7, minChildSize: 0.5, maxChildSize: 0.9,
      builder: (_, scroll) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(children: [
          Container(width: 40, height: 4, margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(color: UellowColors.border,
                  borderRadius: BorderRadius.circular(2))),
          Padding(padding: const EdgeInsets.fromLTRB(18, 6, 18, 4),
              child: Row(children: [
                Text(ar ? 'اختر مكافأتك' : 'Choose your reward', style: UT.h2),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: UellowColors.yellowSoft,
                      borderRadius: BorderRadius.circular(999)),
                  child: Text('${loyalty.points} pts',
                      style: const TextStyle(fontSize: 12,
                          fontWeight: FontWeight.w900, color: UellowColors.darkBrown)),
                ),
              ])),
          const SizedBox(height: 10),
          Expanded(child: ListView.separated(
            controller: scroll,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            itemCount: loyalty.redeemOptions.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final it = loyalty.redeemOptions[i];
              final disabled = !it.affordable;
              return Opacity(opacity: disabled ? 0.6 : 1, child: Material(
                color: Colors.white, borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: disabled ? null : () => onPick(it),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: UellowColors.border),
                    ),
                    child: Row(children: [
                      Container(
                        width: 50, height: 50, alignment: Alignment.center,
                        decoration: BoxDecoration(color: UellowColors.yellowSoft,
                            borderRadius: BorderRadius.circular(12)),
                        child: Text(it.icon, style: const TextStyle(fontSize: 26)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(it.label.current(lang), style: const TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 14, color: UellowColors.ink)),
                        const SizedBox(height: 2),
                        Text('${it.points} pts → ${it.kd.toStringAsFixed(3)} KD',
                          style: const TextStyle(color: UellowColors.muted, fontSize: 12)),
                      ])),
                      Icon(disabled ? Icons.lock_outline : Icons.chevron_right,
                          color: UellowColors.muted, size: 22),
                    ]),
                  ),
                ),
              ));
            },
          )),
        ]),
      ),
    );
  }
}

// ─── Success dialog after redeem ──────────────────────────────────

class _SuccessDialog extends StatelessWidget {
  const _SuccessDialog({required this.code, required this.kdValue,
      required this.expires, required this.ar});
  final String code, kdValue, expires;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      child: Padding(padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 64, height: 64, alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: UellowColors.successBg, shape: BoxShape.circle),
            child: const Icon(Icons.celebration,
                color: UellowColors.successDk, size: 32),
          ),
          const SizedBox(height: 12),
          Text(ar ? 'مبروك! 🎉' : 'Congrats! 🎉',
              style: UT.h2, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(ar
              ? 'تم إصدار قسيمة بقيمة $kdValue د.ك'
              : 'A $kdValue KD voucher has been issued',
              textAlign: TextAlign.center, style: UT.subtitle),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            decoration: BoxDecoration(
              color: UellowColors.yellowFaint,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: UellowColors.yellow, width: 2),
            ),
            child: Column(children: [
              Text(ar ? 'الكود' : 'CODE', style: const TextStyle(
                  fontSize: 10, letterSpacing: 1,
                  fontWeight: FontWeight.w800, color: UellowColors.muted)),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: code));
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      duration: const Duration(seconds: 1),
                      content: Text(ar ? 'تم نسخ الكود' : 'Code copied')));
                },
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(code, style: const TextStyle(fontFamily: 'monospace',
                      fontWeight: FontWeight.w900, fontSize: 22,
                      color: UellowColors.darkBrown, letterSpacing: 1.5)),
                  const SizedBox(width: 8),
                  const Icon(Icons.copy, size: 16, color: UellowColors.muted),
                ]),
              ),
            ]),
          ),
          if (expires.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8),
              child: Text(ar
                  ? 'صالح حتى ${expires.split("T").first}'
                  : 'Valid until ${expires.split("T").first}',
                  style: UT.small)),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: UellowColors.darkBrown,
                side: const BorderSide(color: UellowColors.border),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text(ar ? 'لاحقاً' : 'Later',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            )),
            const SizedBox(width: 8),
            Expanded(child: ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/cart');
              },
              icon: const Icon(Icons.shopping_cart, size: 16),
              label: Text(ar ? 'سوّق الآن' : 'Shop now',
                  style: const TextStyle(fontWeight: FontWeight.w900)),
              style: ElevatedButton.styleFrom(
                backgroundColor: UellowColors.yellow,
                foregroundColor: UellowColors.darkBrown,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(10))),
              ),
            )),
          ]),
        ]),
      ),
    );
  }
}
