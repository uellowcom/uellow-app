// =============================================================================
// MyReturnsScreen (v2.2.163) — «مرتجعاتي»: قائمة طلبات الإرجاع الخاصة بالعميل
// من /api/mobile/v2/account/returns.
// =============================================================================
import 'package:flutter/material.dart';

import '../../api/uellow_api.dart';
import '../theme/uellow_theme.dart';

class MyReturnsScreen extends StatefulWidget {
  const MyReturnsScreen({super.key});
  @override
  State<MyReturnsScreen> createState() => _MyReturnsScreenState();
}

class _MyReturnsScreenState extends State<MyReturnsScreen> {
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await UellowApi.instance
          .getRaw('/api/mobile/v2/account/returns', auth: true);
      final d = r['data'];
      if (d is Map) {
        _rows = ((d['returns'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  (Color, Color) _stateColors(String code) {
    switch (code) {
      case 'approved':
      case 'refunded':
      case 'done':
        return (const Color(0xFFE3F3EA), const Color(0xFF1A7A46));
      case 'rejected':
      case 'cancel':
        return (const Color(0xFFF8E0DC), const Color(0xFFC23B2B));
      default: // pending / new
        return (const Color(0xFFFBEFD6), const Color(0xFFA9680A));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return Scaffold(
      backgroundColor: const Color(0xFFF6F4EE),
      appBar: AppBar(
        backgroundColor: UellowColors.yellow,
        foregroundColor: UellowColors.darkBrown,
        title: Text(ar ? 'مرتجعاتي' : 'My returns',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(
              color: UellowColors.darkBrown))
          : RefreshIndicator(
              onRefresh: _load,
              child: _rows.isEmpty
                  ? ListView(children: [
                      const SizedBox(height: 120),
                      Icon(Icons.assignment_return_outlined,
                          size: 54, color: UellowColors.muted.withOpacity(.5)),
                      const SizedBox(height: 12),
                      Center(child: Text(
                          ar ? 'لا توجد طلبات إرجاع' : 'No return requests',
                          style: const TextStyle(color: UellowColors.muted,
                              fontWeight: FontWeight.w700))),
                    ])
                  : ListView.builder(
                      padding: const EdgeInsets.all(14),
                      itemCount: _rows.length,
                      itemBuilder: (_, i) => _card(_rows[i], ar),
                    ),
            ),
    );
  }

  Widget _card(Map<String, dynamic> r, bool ar) {
    final (bg, fg) = _stateColors((r['state_code'] ?? '').toString());
    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFECE7DA)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('#${r['name'] ?? ''}', style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w900,
              color: UellowColors.darkBrown)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
                color: bg, borderRadius: BorderRadius.circular(999)),
            child: Text((r['state'] ?? '').toString(), style: TextStyle(
                fontSize: 10.5, fontWeight: FontWeight.w800, color: fg)),
          ),
        ]),
        const SizedBox(height: 7),
        if ((r['product'] ?? '').toString().isNotEmpty)
          Text(r['product'].toString(), maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5,
                  fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Row(children: [
          if ((r['order'] ?? '').toString().isNotEmpty)
            Text('${ar ? 'طلب' : 'Order'} ${r['order']}',
                style: const TextStyle(fontSize: 11,
                    color: UellowColors.muted, fontWeight: FontWeight.w600)),
          const Spacer(),
          Text((r['date'] ?? '').toString(),
              style: const TextStyle(fontSize: 11, color: UellowColors.muted)),
        ]),
        if ((r['reason'] ?? '').toString().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('${ar ? 'السبب' : 'Reason'}: ${r['reason']}',
              style: const TextStyle(fontSize: 11.5,
                  color: UellowColors.text)),
        ],
        if (((r['refund'] as num?) ?? 0) > 0) ...[
          const SizedBox(height: 4),
          Text('${ar ? 'مبلغ الاسترداد' : 'Refund'}: ${r['refund']}',
              style: const TextStyle(fontSize: 12,
                  fontWeight: FontWeight.w900, color: Color(0xFF1A7A46))),
        ],
      ]),
    );
  }
}
