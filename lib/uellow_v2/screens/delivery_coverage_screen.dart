// =============================================================================
// DeliveryCoverageScreen — "Check delivery to your area".
//
// v2.1.1 — Surfaces the Shipping Pro backend (cities + carrier quote) in a
// purely INFORMATIONAL, non-checkout screen: the customer picks their city
// and sees which carriers cover it, the delivery fee, the cash-on-delivery
// surcharge, and each carrier's delivery time window. Because this is a
// coverage lookup (not an order), showing the COD surcharge here is accurate
// and carries no order-total risk.
//
// Uses UellowApi.instance.shipping.cities() / .quote() (previously unwired).
// =============================================================================
import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/uellow_api.dart';
import '../theme/uellow_theme.dart';

class DeliveryCoverageScreen extends StatefulWidget {
  const DeliveryCoverageScreen({super.key});
  @override
  State<DeliveryCoverageScreen> createState() => _DeliveryCoverageScreenState();
}

class _DeliveryCoverageScreenState extends State<DeliveryCoverageScreen> {
  final _ctrl = TextEditingController();
  Timer? _debounce;

  List<Map<String, dynamic>> _cities = [];
  bool _searching = false;

  Map<String, dynamic>? _city;        // selected city
  String _payment = 'card';           // card | cash
  List<Map<String, dynamic>>? _quotes;
  bool _loadingQuote = false;
  String _quoteError = '';

  bool get _ar => UellowApi.instance.lang.toLowerCase().startsWith('ar');

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    if (v.trim().isEmpty) {
      setState(() { _cities = []; _searching = false; });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(v.trim()));
  }

  Future<void> _search(String q) async {
    try {
      final res = await UellowApi.instance.shipping.cities(country: 'KW', q: q);
      if (!mounted) return;
      setState(() { _cities = res; _searching = false; });
    } catch (_) {
      if (mounted) setState(() { _cities = []; _searching = false; });
    }
  }

  Future<void> _selectCity(Map<String, dynamic> city) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _city = city;
      _cities = [];
      _ctrl.text = (_ar ? city['name_ar'] : city['name_en'])?.toString() ?? '';
      _quotes = null;
      _quoteError = '';
    });
    await _loadQuote();
  }

  Future<void> _loadQuote() async {
    final city = _city;
    if (city == null) return;
    final id = (city['id'] as num?)?.toInt() ?? 0;
    if (id <= 0) return;
    setState(() { _loadingQuote = true; _quoteError = ''; });
    try {
      final res = await UellowApi.instance.shipping
          .quote(cityId: id, payment: _payment);
      if (!mounted) return;
      setState(() { _quotes = res; _loadingQuote = false; });
    } on UellowApiException catch (e) {
      if (!mounted) return;
      // NO_ZONE etc. — show a friendly "not covered yet" message.
      setState(() {
        _quotes = [];
        _loadingQuote = false;
        _quoteError = e.code == 'NO_ZONE'
            ? (_ar ? 'منطقتك غير مغطاة بعد.' : 'Your area is not covered yet.')
            : e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _quotes = [];
        _loadingQuote = false;
        _quoteError = _ar ? 'تعذّر جلب خيارات التوصيل.' : 'Could not load delivery options.';
      });
    }
  }

  // Float hour (e.g. 14.0, 21.5) → "2:00 PM" / "٢:٠٠ م".
  String _fmtHour(num h) {
    final hh = h.floor();
    final mm = ((h - hh) * 60).round();
    final period = hh < 12 ? (_ar ? 'ص' : 'AM') : (_ar ? 'م' : 'PM');
    final h12 = hh % 12 == 0 ? 12 : hh % 12;
    return '$h12:${mm.toString().padLeft(2, '0')} $period';
  }

  String _money(num v) {
    final n = v.toDouble().toStringAsFixed(3);
    return _ar ? '$n د.ك' : '$n KD';
  }

  @override
  Widget build(BuildContext context) {
    final ar = _ar;
    return Scaffold(
      backgroundColor: UellowColors.bg,
      appBar: AppBar(
        leading: const BackButton(color: UellowColors.darkBrown),
        title: Text(ar ? 'التوصيل إلى منطقتك' : 'Delivery to your area', style: UT.h1),
      ),
      body: SafeArea(top: false, child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(ar
              ? 'اختر مدينتك لمعرفة شركات التوصيل المتاحة وأسعارها وأوقاتها.'
              : 'Pick your city to see which carriers cover it, their prices and delivery windows.',
              style: UT.small),
          const SizedBox(height: 12),
          // City search box
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: UellowColors.border),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              const Icon(Icons.location_city_outlined, size: 18, color: UellowColors.muted),
              const SizedBox(width: 8),
              Expanded(child: TextField(
                controller: _ctrl,
                onChanged: _onSearchChanged,
                textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: ar ? 'ابحث عن مدينتك…' : 'Search your city…',
                ),
              )),
              if (_searching)
                const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
            ]),
          ),
          // City suggestions
          if (_cities.isNotEmpty) Container(
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: UellowColors.border),
            ),
            child: Column(children: _cities.take(12).map((c) {
              final nm = (ar ? c['name_ar'] : c['name_en'])?.toString() ?? '';
              final zone = (ar ? c['zone_name_ar'] : c['zone_name_en'])?.toString() ?? '';
              return ListTile(
                dense: true,
                leading: const Icon(Icons.place_outlined, size: 18, color: UellowColors.muted),
                title: Text(nm.isNotEmpty ? nm : (c['name_en']?.toString() ?? ''),
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                subtitle: zone.isNotEmpty
                    ? Text(zone, style: const TextStyle(fontSize: 11, color: UellowColors.muted))
                    : null,
                onTap: () => _selectCity(c),
              );
            }).toList()),
          ),
          // Quote section
          if (_city != null) ...[
            const SizedBox(height: 18),
            // payment toggle (affects whether the COD surcharge is shown)
            Row(children: [
              Text(ar ? 'طريقة الدفع:' : 'Payment:', style: UT.small),
              const SizedBox(width: 10),
              _payChip('card', ar ? 'بطاقة' : 'Card'),
              const SizedBox(width: 6),
              _payChip('cash', ar ? 'نقداً عند الاستلام' : 'Cash on delivery'),
            ]),
            const SizedBox(height: 12),
            if (_loadingQuote)
              const Padding(padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator(color: UellowColors.darkBrown)))
            else if (_quoteError.isNotEmpty)
              _infoBox(Icons.info_outline, _quoteError)
            else if ((_quotes ?? []).isEmpty)
              _infoBox(Icons.schedule,
                  ar ? 'لا توجد خيارات توصيل متاحة الآن لهذه المنطقة.'
                     : 'No delivery options available right now for this area.')
            else
              ...(_quotes!).map(_quoteCard),
          ],
        ],
      )),
    );
  }

  Widget _payChip(String value, String label) {
    final on = _payment == value;
    return GestureDetector(
      onTap: () {
        if (_payment == value) return;
        setState(() => _payment = value);
        _loadQuote();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: on ? UellowColors.darkBrown : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: on ? UellowColors.darkBrown : UellowColors.border),
        ),
        child: Text(label, style: TextStyle(
          fontSize: 11.5, fontWeight: FontWeight.w800,
          color: on ? UellowColors.yellowLight : UellowColors.text)),
      ),
    );
  }

  Widget _infoBox(IconData icon, String msg) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: UellowColors.yellowSoft,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: UellowColors.yellow.withValues(alpha: 0.5)),
    ),
    child: Row(children: [
      Icon(icon, size: 18, color: UellowColors.darkBrown),
      const SizedBox(width: 10),
      Expanded(child: Text(msg, style: const TextStyle(
          fontSize: 12.5, color: UellowColors.darkBrown, fontWeight: FontWeight.w600))),
    ]),
  );

  Widget _quoteCard(Map<String, dynamic> q) {
    final ar = _ar;
    final name = (q['carrier_name'] as String?) ?? '';
    final desc = (ar ? q['description_ar'] : q['description_en'])?.toString() ?? '';
    final fee = (q['delivery_fee'] as num?) ?? 0;
    final surcharge = (q['cash_surcharge'] as num?) ?? 0;
    final total = (q['total'] as num?) ?? fee;
    final ws = (q['time_window_start'] as num?) ?? 0;
    final we = (q['time_window_end'] as num?) ?? 0;
    final hasWindow = ws > 0 && we > 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: UellowColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 36, height: 36, alignment: Alignment.center,
            decoration: BoxDecoration(
              color: UellowColors.yellowSoft, borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.local_shipping_outlined, size: 18,
                color: UellowColors.darkBrown),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w900, color: UellowColors.ink)),
            if (desc.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2),
                child: Text(desc, style: const TextStyle(fontSize: 11, color: UellowColors.muted))),
          ])),
          Text(_money(total), style: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w900, color: UellowColors.darkBrown)),
        ]),
        if (hasWindow || surcharge > 0) ...[
          const SizedBox(height: 10),
          const Divider(height: 1, color: UellowColors.border),
          const SizedBox(height: 8),
          if (hasWindow) _line(Icons.schedule,
              ar ? 'نافذة التوصيل: ${_fmtHour(ws)} – ${_fmtHour(we)}'
                 : 'Delivery window: ${_fmtHour(ws)} – ${_fmtHour(we)}'),
          if (surcharge > 0) Padding(
            padding: const EdgeInsets.only(top: 4),
            child: _line(Icons.payments_outlined,
                ar ? 'رسوم الدفع نقداً: +${_money(surcharge)}'
                   : 'Cash-on-delivery fee: +${_money(surcharge)}'),
          ),
        ],
      ]),
    );
  }

  Widget _line(IconData icon, String text) => Row(children: [
    Icon(icon, size: 13, color: UellowColors.muted),
    const SizedBox(width: 6),
    Expanded(child: Text(text, style: const TextStyle(
        fontSize: 11.5, color: UellowColors.muted, fontWeight: FontWeight.w600))),
  ]);
}
