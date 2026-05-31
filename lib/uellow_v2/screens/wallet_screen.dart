// =============================================================================
// WalletScreen — real Odoo wallet (uellow.customer.wallet.tx) via
// /api/mobile/v2/wallet. Hero balance, quick actions (send, redeem gift,
// history), and full transaction list with proper icons + bilingual
// labels.  Send + Redeem flows talk straight to the backend.
// =============================================================================
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../api/uellow_api.dart';
import '../theme/uellow_theme.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});
  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  Future<_WalletData>? _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<_WalletData> _fetch() async {
    final token = await UellowApi.instance.tokenStore.readToken();
    if (token == null) return _WalletData.empty();
    final hdr = {'Accept': 'application/json', 'Authorization': 'Bearer $token'};
    try {
      final r = await http.get(Uri.parse(
          '${UellowApi.instance.baseUrl}/api/mobile/v2/wallet'), headers: hdr);
      final b = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (b['success'] == true) {
        final d = b['data'] as Map<String, dynamic>;
        final bal = d['balance'] as Map<String, dynamic>;
        return _WalletData(
          balance: (bal['amount'] ?? 0).toDouble(),
          symbol:  (bal['symbol'] ?? 'KD').toString(),
          transactions: (d['transactions'] as List).cast<Map<String, dynamic>>(),
          canSend:     (d['can_send'] ?? false) as bool,
          canTopup:    (d['can_topup'] ?? false) as bool,
          canGiftCard: (d['can_giftcard'] ?? false) as bool,
        );
      }
    } catch (_) {}
    return _WalletData.empty();
  }

  Future<void> _refresh() async {
    setState(() => _future = _fetch());
    await _future;
  }

  void _openSend(_WalletData d) {
    showModalBottomSheet(context: context, isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _SendSheet(balance: d.balance, symbol: d.symbol,
            onSent: () { Navigator.pop(context); _refresh(); }));
  }

  void _openGift() {
    showModalBottomSheet(context: context, isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _GiftSheet(onRedeemed: () {
          Navigator.pop(context); _refresh();
        }));
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return Scaffold(
      backgroundColor: UellowColors.bg,
      appBar: AppBar(
        leading: const BackButton(color: UellowColors.darkBrown),
        title: Text(ar ? 'محفظتي' : 'My Wallet', style: UT.h1),
      ),
      body: SafeArea(bottom: false, child: FutureBuilder<_WalletData>(
        future: _future,
        builder: (_, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: UellowColors.darkBrown));
          }
          final d = snap.data ?? _WalletData.empty();
          return RefreshIndicator(onRefresh: _refresh,
            child: ListView(padding: EdgeInsets.zero, children: [
              _Hero(data: d, ar: ar,
                  onSend: () => _openSend(d),
                  onGift: _openGift,
                  onHistory: () { Scrollable.ensureVisible(context); }),
              _PerksRow(ar: ar),
              _Transactions(txs: d.transactions, ar: ar),
              const SizedBox(height: 30),
            ]),
          );
        },
      )),
    );
  }
}

class _WalletData {
  _WalletData({
    required this.balance, required this.symbol,
    required this.transactions,
    this.canSend = false, this.canTopup = false, this.canGiftCard = false,
  });
  factory _WalletData.empty() => _WalletData(
      balance: 0, symbol: 'KD', transactions: const []);
  final double balance;
  final String symbol;
  final List<Map<String, dynamic>> transactions;
  final bool canSend, canTopup, canGiftCard;
}

// ─── Hero ──────────────────────────────────────────────────────────

class _Hero extends StatelessWidget {
  const _Hero({required this.data, required this.ar,
      required this.onSend, required this.onGift, required this.onHistory});
  final _WalletData data;
  final bool ar;
  final VoidCallback onSend, onGift, onHistory;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
      decoration: const BoxDecoration(
        gradient: UellowColors.heroWallet,
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
      child: Stack(children: [
        Positioned(right: -16, top: -16, child: Container(
          width: 110, height: 110,
          decoration: const BoxDecoration(
            gradient: RadialGradient(colors: [Color(0x33FFD340), Colors.transparent]),
            shape: BoxShape.circle))),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(ar ? 'الرصيد المتاح' : 'AVAILABLE BALANCE',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
                    color: UellowColors.yellowLight, letterSpacing: 0.8)),
            const Spacer(),
            const Icon(Icons.account_balance_wallet,
                color: UellowColors.yellowLight, size: 18),
          ]),
          const SizedBox(height: 6),
          Text.rich(TextSpan(children: [
            TextSpan(text: data.balance.toStringAsFixed(3), style: const TextStyle(
                fontSize: 44, fontWeight: FontWeight.w900,
                color: UellowColors.yellowLight, height: 1)),
            TextSpan(text: ' ${_localizedSymbol(data.symbol, ar)}',
                style: const TextStyle(fontSize: 18,
                    fontWeight: FontWeight.w700, color: UellowColors.yellowLight)),
          ])),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: _action(icon: Icons.swap_horiz,
                label: ar ? 'إرسال' : 'Send', primary: true, onTap: onSend)),
            const SizedBox(width: 8),
            Expanded(child: _action(icon: Icons.card_giftcard,
                label: ar ? 'كود هدية' : 'Gift code', onTap: onGift)),
            const SizedBox(width: 8),
            Expanded(child: _action(icon: Icons.history,
                label: ar ? 'السجل' : 'History', onTap: onHistory)),
          ]),
        ]),
      ]),
    );
  }
  Widget _action({required IconData icon, required String label,
      VoidCallback? onTap, bool primary = false}) {
    final bg = primary ? UellowColors.yellowLight : const Color(0x2EFFD340);
    final fg = primary ? UellowColors.darkBrown : UellowColors.yellowLight;
    return Material(color: bg, borderRadius: BorderRadius.circular(12),
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          child: Column(children: [
            Icon(icon, size: 16, color: fg),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: fg,
                fontWeight: FontWeight.w800, fontSize: 11.5)),
          ]),
        ),
      ),
    );
  }

  static String _localizedSymbol(String s, bool ar) {
    if (!ar) return s;
    return const {'KD': 'د.ك', 'KWD': 'د.ك', 'SAR': 'ر.س',
                  'AED': 'د.إ', 'EGP': 'ج.م', 'QAR': 'ر.ق', 'OMR': 'ر.ع.',
                  'USD': '\$', 'EUR': '€'}[s] ?? s;
  }
}

// ─── Perks row ────────────────────────────────────────────────────

class _PerksRow extends StatelessWidget {
  const _PerksRow({required this.ar});
  final bool ar;
  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.bolt, ar ? 'دفع فوري' : 'Instant pay',
        ar ? 'بدون رسوم' : 'No fees'),
      (Icons.shield_outlined, ar ? 'دفع آمن' : 'Secure',
        ar ? 'مشفّر بالكامل' : 'Fully encrypted'),
      (Icons.refresh, ar ? 'استرداد فوري' : 'Auto refund',
        ar ? 'للطلبات الملغاة' : 'On cancelled orders'),
    ];
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
      child: Row(children: items.map((it) => Expanded(child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(children: [
          Container(
            width: 36, height: 36, alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: UellowColors.yellowSoft, shape: BoxShape.circle),
            child: Icon(it.$1, color: UellowColors.darkBrown, size: 18),
          ),
          const SizedBox(height: 6),
          Text(it.$2, style: const TextStyle(fontSize: 11.5,
              fontWeight: FontWeight.w800, color: UellowColors.ink),
              textAlign: TextAlign.center),
          Text(it.$3, style: const TextStyle(fontSize: 10,
              color: UellowColors.muted), textAlign: TextAlign.center),
        ]),
      ))).toList()),
    );
  }
}

// ─── Transactions ─────────────────────────────────────────────────

class _Transactions extends StatelessWidget {
  const _Transactions({required this.txs, required this.ar});
  final List<Map<String, dynamic>> txs;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      padding: const EdgeInsets.all(14),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(ar ? 'سجل المعاملات' : 'Transaction history', style: UT.h3),
        const SizedBox(height: 6),
        if (txs.isEmpty) Padding(
          padding: const EdgeInsets.symmetric(vertical: 30),
          child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.account_balance_wallet_outlined,
                size: 56, color: UellowColors.muted),
            const SizedBox(height: 8),
            Text(ar ? 'لا توجد معاملات بعد' : 'No transactions yet',
                style: UT.body),
            const SizedBox(height: 4),
            Text(ar
                ? 'ابدأ بإضافة كود هدية أو استلام استرداد'
                : 'Start by redeeming a gift code or get a refund',
                style: UT.subtitle, textAlign: TextAlign.center),
          ])),
        ),
        for (final tx in txs) _row(tx),
      ]),
    );
  }
  Widget _row(Map<String, dynamic> tx) {
    final amt = (tx['amount'] as Map?)?['amount'] as num? ?? 0;
    final isIn = amt > 0;
    final type = (tx['type'] ?? '').toString();
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: UellowColors.bg)),
      ),
      child: Row(children: [
        Container(
          width: 38, height: 38, alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isIn ? UellowColors.successBg : UellowColors.dangerBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(_iconFor(type, isIn), size: 18,
              color: isIn ? UellowColors.successDk : UellowColors.dangerDk),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_titleFor(tx, ar), style: const TextStyle(fontSize: 13,
              fontWeight: FontWeight.w800, color: UellowColors.ink)),
          Text(_subtitleFor(tx, ar), style: UT.small,
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text((isIn ? '+' : '−') + amt.abs().toStringAsFixed(3),
              style: TextStyle(color: isIn ? UellowColors.successDk : UellowColors.dangerDk,
                  fontWeight: FontWeight.w900, fontSize: 14)),
          if ((tx['state'] ?? '') == 'pending')
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: UellowColors.warnBg,
                  borderRadius: BorderRadius.circular(4)),
              child: Text(ar ? 'قيد التنفيذ' : 'Pending',
                  style: const TextStyle(fontSize: 9, color: UellowColors.warn,
                      fontWeight: FontWeight.w800)),
            ),
        ]),
      ]),
    );
  }
  IconData _iconFor(String t, bool isIn) => switch (t) {
    'topup' => Icons.add_circle, 'gift_card' => Icons.card_giftcard,
    'spend' => Icons.shopping_cart, 'refund' => Icons.replay,
    'send' => Icons.call_made, 'receive' => Icons.call_received,
    'cashback' => Icons.savings, 'adjust' => Icons.tune,
    _ => isIn ? Icons.add : Icons.remove,
  };
  String _titleFor(Map<String, dynamic> tx, bool ar) {
    final t = (tx['type'] ?? '').toString();
    return ar ? switch (t) {
      'topup' => 'شحن المحفظة',
      'gift_card' => 'كود هدية',
      'spend' => 'دفع طلب ${tx['order_name'] ?? ''}',
      'refund' => 'استرداد طلب ${tx['order_name'] ?? ''}',
      'send' => 'إرسال إلى ${tx['counter_name'] ?? ''}',
      'receive' => 'استلام من ${tx['counter_name'] ?? ''}',
      'cashback' => 'كاش باك',
      'adjust' => 'تعديل يدوي',
      _ => 'معاملة',
    } : switch (t) {
      'topup' => 'Wallet top-up',
      'gift_card' => 'Gift card redeemed',
      'spend' => 'Order payment ${tx['order_name'] ?? ''}',
      'refund' => 'Refund ${tx['order_name'] ?? ''}',
      'send' => 'Sent to ${tx['counter_name'] ?? ''}',
      'receive' => 'Received from ${tx['counter_name'] ?? ''}',
      'cashback' => 'Cashback',
      'adjust' => 'Manual adjustment',
      _ => 'Transaction',
    };
  }
  String _subtitleFor(Map<String, dynamic> tx, bool ar) {
    final when = (tx['when'] ?? tx['date'] ?? '').toString();
    final desc = (tx['description'] ?? '').toString();
    final ref  = (tx['reference'] ?? '').toString();
    final parts = <String>[];
    if (when.isNotEmpty) parts.add(when.split('T').first);
    if (desc.isNotEmpty && desc != tx['type']) parts.add(desc);
    if (ref.isNotEmpty) parts.add(ref);
    return parts.join(' · ');
  }
}

// ─── Send sheet ───────────────────────────────────────────────────

class _SendSheet extends StatefulWidget {
  const _SendSheet({required this.balance, required this.symbol,
      required this.onSent});
  final double balance;
  final String symbol;
  final VoidCallback onSent;
  @override
  State<_SendSheet> createState() => _SendSheetState();
}

class _SendSheetState extends State<_SendSheet> {
  final _recipient = TextEditingController();
  final _amount    = TextEditingController();
  final _note      = TextEditingController();
  Map<String, dynamic>? _resolved;
  bool _busy = false;
  String? _error, _result;

  Future<void> _lookup() async {
    final q = _recipient.text.trim();
    if (q.isEmpty) return;
    try {
      final token = await UellowApi.instance.tokenStore.readToken();
      final r = await http.get(Uri.parse(
          '${UellowApi.instance.baseUrl}/api/mobile/v2/wallet/lookup?q=${Uri.encodeComponent(q)}'),
          headers: {if (token != null) 'Authorization': 'Bearer $token'});
      final b = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (b['success'] == true) setState(() => _resolved = b['data'] as Map<String, dynamic>);
      else setState(() { _resolved = null; _error = b['error']?.toString(); });
    } catch (e) { setState(() => _error = e.toString()); }
  }

  Future<void> _send() async {
    final ar = UellowApi.instance.lang == 'ar';
    final amt = double.tryParse(_amount.text.trim()) ?? 0;
    if (amt <= 0) { setState(() => _error = ar ? 'المبلغ غير صالح' : 'Invalid amount'); return; }
    if (amt > widget.balance) { setState(() => _error = ar ? 'الرصيد غير كافٍ' : 'Insufficient balance'); return; }
    setState(() { _busy = true; _error = null; });
    try {
      final token = await UellowApi.instance.tokenStore.readToken();
      final r = await http.post(
        Uri.parse('${UellowApi.instance.baseUrl}/api/mobile/v2/wallet/send'),
        headers: {'Content-Type': 'application/json',
                  if (token != null) 'Authorization': 'Bearer $token'},
        body: jsonEncode({
          'recipient': _recipient.text.trim(),
          'amount': amt, 'note': _note.text.trim(),
        }),
      );
      final b = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (b['success'] == true) {
        final d = b['data'] as Map<String, dynamic>;
        setState(() {
          _result = ar
              ? 'تم إرسال ${d['sent']['amount']} د.ك إلى ${(d['recipient'] as Map)['name']}'
              : 'Sent ${d['sent']['amount']} ${widget.symbol} to ${(d['recipient'] as Map)['name']}';
          _busy = false;
        });
        await Future.delayed(const Duration(milliseconds: 900));
        widget.onSent();
      } else {
        setState(() { _busy = false; _error = (b['error'] ?? 'Failed').toString(); });
      }
    } catch (e) { setState(() { _busy = false; _error = e.toString(); }); }
  }

  @override
  void dispose() { _recipient.dispose(); _amount.dispose(); _note.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20,
          MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 40, height: 4,
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(color: UellowColors.border,
                borderRadius: BorderRadius.circular(2)))),
        Text(ar ? 'إرسال إلى صديق' : 'Send to a friend', style: UT.h2),
        const SizedBox(height: 4),
        Text(ar ? 'الرصيد الحالي: ${widget.balance.toStringAsFixed(3)} ${widget.symbol}'
                : 'Current balance: ${widget.balance.toStringAsFixed(3)} ${widget.symbol}',
            style: UT.subtitle),
        const SizedBox(height: 14),
        TextField(
          controller: _recipient,
          onSubmitted: (_) => _lookup(),
          decoration: InputDecoration(
            labelText: ar ? 'البريد أو رقم الهاتف' : 'Email or phone',
            prefixIcon: const Icon(Icons.person_outline, size: 18),
            suffixIcon: IconButton(onPressed: _lookup,
                icon: const Icon(Icons.search, size: 18)),
            isDense: true,
          ),
        ),
        if (_resolved != null) Padding(padding: const EdgeInsets.only(top: 8),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: UellowColors.successBg,
                  borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                const Icon(Icons.check_circle, color: UellowColors.successDk, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(_resolved!['name'].toString(),
                    style: const TextStyle(fontWeight: FontWeight.w800,
                        color: UellowColors.successDk))),
              ]),
            )),
        const SizedBox(height: 10),
        TextField(
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: ar ? 'المبلغ (${widget.symbol})' : 'Amount (${widget.symbol})',
            prefixIcon: const Icon(Icons.payments_outlined, size: 18),
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _note,
          maxLength: 80,
          decoration: InputDecoration(
            labelText: ar ? 'ملاحظة (اختياري)' : 'Note (optional)',
            prefixIcon: const Icon(Icons.edit_outlined, size: 18),
            isDense: true,
          ),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: const TextStyle(
                color: UellowColors.danger, fontWeight: FontWeight.w700))),
        if (_result != null) Padding(padding: const EdgeInsets.only(top: 8),
            child: Text(_result!, style: const TextStyle(
                color: UellowColors.successDk, fontWeight: FontWeight.w700))),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, child: ElevatedButton.icon(
          onPressed: _busy ? null : _send,
          icon: _busy
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2,
                      color: UellowColors.darkBrown))
              : const Icon(Icons.send, size: 18),
          label: Text(_busy ? (ar ? 'جارٍ الإرسال…' : 'Sending…')
                            : (ar ? 'إرسال' : 'Send'),
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          style: ElevatedButton.styleFrom(
            backgroundColor: UellowColors.yellow,
            foregroundColor: UellowColors.darkBrown,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(14))),
          ),
        )),
      ]),
    );
  }
}

// ─── Gift / promo code sheet ──────────────────────────────────────

class _GiftSheet extends StatefulWidget {
  const _GiftSheet({required this.onRedeemed});
  final VoidCallback onRedeemed;
  @override
  State<_GiftSheet> createState() => _GiftSheetState();
}

class _GiftSheetState extends State<_GiftSheet> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error, _result;

  Future<void> _redeem() async {
    final ar = UellowApi.instance.lang == 'ar';
    if (_code.text.trim().isEmpty) {
      setState(() => _error = ar ? 'أدخل الكود' : 'Enter the code');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final token = await UellowApi.instance.tokenStore.readToken();
      final r = await http.post(
        Uri.parse('${UellowApi.instance.baseUrl}/api/mobile/v2/wallet/redeem-gift'),
        headers: {'Content-Type': 'application/json',
                  if (token != null) 'Authorization': 'Bearer $token'},
        body: jsonEncode({'code': _code.text.trim()}),
      );
      final b = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (b['success'] == true) {
        final d = b['data'] as Map<String, dynamic>;
        final credited = (d['credited'] as Map)['amount'];
        setState(() {
          _busy = false;
          _result = ar
              ? 'تمت إضافة $credited د.ك إلى محفظتك 🎉'
              : '$credited credited to your wallet 🎉';
        });
        await Future.delayed(const Duration(milliseconds: 1100));
        widget.onRedeemed();
      } else {
        setState(() { _busy = false; _error = (b['error'] ?? 'Failed').toString(); });
      }
    } catch (e) { setState(() { _busy = false; _error = e.toString(); }); }
  }

  @override
  void dispose() { _code.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20,
          MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 40, height: 4,
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(color: UellowColors.border,
                borderRadius: BorderRadius.circular(2)))),
        Row(children: [
          const Icon(Icons.card_giftcard, color: UellowColors.darkBrown, size: 22),
          const SizedBox(width: 8),
          Text(ar ? 'استرداد كود هدية' : 'Redeem gift code', style: UT.h2),
        ]),
        const SizedBox(height: 4),
        Text(ar ? 'أدخل كود البطاقة لإضافة قيمتها إلى محفظتك.'
                : 'Enter a gift card code to add its value to your wallet.',
            style: UT.subtitle),
        const SizedBox(height: 14),
        TextField(
          controller: _code,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: ar ? 'كود الهدية' : 'Gift code',
            hintText: 'UEL-XXXXXXXX',
            prefixIcon: const Icon(Icons.qr_code, size: 18),
            isDense: true,
          ),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: const TextStyle(
                color: UellowColors.danger, fontWeight: FontWeight.w700))),
        if (_result != null) Padding(padding: const EdgeInsets.only(top: 8),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: UellowColors.successBg,
                  borderRadius: BorderRadius.circular(8)),
              child: Text(_result!, style: const TextStyle(
                  color: UellowColors.successDk, fontWeight: FontWeight.w900)),
            )),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, child: ElevatedButton.icon(
          onPressed: _busy ? null : _redeem,
          icon: _busy
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2,
                      color: UellowColors.darkBrown))
              : const Icon(Icons.redeem, size: 18),
          label: Text(_busy ? (ar ? 'جارٍ الاسترداد…' : 'Redeeming…')
                            : (ar ? 'استرداد' : 'Redeem'),
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          style: ElevatedButton.styleFrom(
            backgroundColor: UellowColors.yellow,
            foregroundColor: UellowColors.darkBrown,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(14))),
          ),
        )),
      ]),
    );
  }
}
