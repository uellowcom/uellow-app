// =============================================================================
// MyReviewsScreen (v2.1.62) — «سجل آراء المختصين» in the account page.
// Every specialist-review request the customer ever made: product image,
// status, and the review itself (verdict + specialist notes/replies).
// Tapping the product head opens the product page.
// =============================================================================
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../api/uellow_api.dart';
import '../router/uellow_router.dart';
import '../theme/uellow_theme.dart';

class MyReviewsScreen extends StatefulWidget {
  const MyReviewsScreen({super.key});
  @override
  State<MyReviewsScreen> createState() => _MyReviewsScreenState();
}

class _MyReviewsScreenState extends State<MyReviewsScreen> {
  List<Map<String, dynamic>>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _items = null; _error = null; });
    try {
      final res = await UellowApi.instance
          .getRaw('/api/mobile/v2/reviewers/my-requests', auth: true);
      if (!mounted) return;
      setState(() => _items = List<Map<String, dynamic>>.from(
          (res['data']?['items'] as List?) ?? const []));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
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
          backgroundColor: Colors.white,
          foregroundColor: UellowColors.darkBrown,
          title: Text(ar ? '🎓 سجل آراء المختصين' : '🎓 My specialist reviews',
              style: const TextStyle(
                  fontWeight: FontWeight.w900, fontSize: 16)),
        ),
        body: _error != null
            ? Center(child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.cloud_off_outlined, size: 48,
                      color: UellowColors.muted),
                  const SizedBox(height: 10),
                  Text(ar ? 'تعذّر التحميل' : 'Could not load',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  ElevatedButton(onPressed: _load,
                      child: Text(ar ? 'إعادة المحاولة' : 'Retry')),
                ])))
            : _items == null
                ? const Center(child: CircularProgressIndicator(
                    color: UellowColors.yellow))
                : _items!.isEmpty
                    ? Center(child: Column(
                        mainAxisSize: MainAxisSize.min, children: [
                        const Text('🎓', style: TextStyle(fontSize: 44)),
                        const SizedBox(height: 8),
                        Text(ar ? 'لا توجد طلبات آراء بعد'
                               : 'No review requests yet',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: UellowColors.muted)),
                        const SizedBox(height: 4),
                        Text(ar
                                ? 'اطلب رأي مختص من صفحة أي منتج'
                                : 'Ask a specialist from any product page',
                            style: const TextStyle(fontSize: 11.5,
                                color: UellowColors.muted)),
                      ]))
                    : RefreshIndicator(
                        color: UellowColors.darkBrown,
                        onRefresh: _load,
                        child: ListView.builder(
                          padding:
                              const EdgeInsets.fromLTRB(12, 12, 12, 24),
                          itemCount: _items!.length,
                          itemBuilder: (_, i) => _card(_items![i], ar),
                        ),
                      ),
      ),
    );
  }

  Widget _card(Map<String, dynamic> it, bool ar) {
    final product =
        (it['product'] as Map?)?.cast<String, dynamic>() ?? const {};
    final reviewer =
        (it['reviewer'] as Map?)?.cast<String, dynamic>() ?? const {};
    final pname =
        ((product['name'] as Map?)?[ar ? 'ar' : 'en'] ?? '').toString();
    final img = (product['image'] ?? '').toString();
    final state = (it['state'] ?? '').toString();
    final answered = state == 'completed';
    final verdict = (it['verdict'] ?? '').toString();
    final notes = (it['notes'] ?? '').toString();
    final replies = List<Map<String, dynamic>>.from(
        (it['replies'] as List?) ?? const []);
    final q = (it['quality'] as num?)?.toInt() ?? 0;
    final v = (it['value'] as num?)?.toInt() ?? 0;
    final (stLabel, stColor) = answered
        ? (ar ? '✔ تم الرد' : '✔ Replied', UellowColors.successDk)
        : state == 'expired'
            ? (ar ? 'منتهي' : 'Expired', UellowColors.muted)
            : (ar ? '⏳ قيد الرد' : '⏳ Pending', const Color(0xFF1D5FA8));
    final (vIcon, vText, vColor) = switch (verdict) {
      'recommend' => ('👍', ar ? 'أنصح بالشراء' : 'Recommended',
          UellowColors.successDk),
      'not_recommend' => ('👎', ar ? 'لا أنصح' : 'Not recommended',
          UellowColors.danger),
      'neutral' => ('😐', ar ? 'محايد' : 'Neutral', const Color(0xFFB8860B)),
      _ => ('', '', UellowColors.muted),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: answered
            ? const Color(0xFFBFE8CD) : UellowColors.border),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 6)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // product head — tappable
        GestureDetector(
          onTap: () {
            final pid = (product['id'] as num?)?.toInt() ?? 0;
            if (pid > 0) UellowRouter.goProduct(context, pid);
          },
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: img.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: img.startsWith('http')
                          ? img : '${UellowApi.instance.baseUrl}$img',
                      width: 54, height: 54, fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(
                          width: 54, height: 54,
                          color: const Color(0xFFF2F2F2)))
                  : Container(width: 54, height: 54,
                      color: const Color(0xFFF2F2F2),
                      alignment: Alignment.center,
                      child: const Icon(Icons.image_outlined,
                          color: UellowColors.muted)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(pname, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: stColor.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(stLabel, style: TextStyle(fontSize: 9.5,
                      fontWeight: FontWeight.w800, color: stColor)),
                ),
                if ((reviewer['name'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Flexible(child: Text('👤 ${reviewer['name']}',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10,
                          color: UellowColors.muted))),
                ],
              ]),
            ])),
            Icon(ar ? Icons.chevron_left : Icons.chevron_right,
                color: UellowColors.muted, size: 20),
          ]),
        ),
        // the review itself
        if (answered && (vText.isNotEmpty || notes.isNotEmpty ||
            replies.isNotEmpty)) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: vColor.withValues(alpha: .06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: vColor.withValues(alpha: .25)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              if (vText.isNotEmpty) Row(children: [
                Text(vIcon, style: const TextStyle(fontSize: 15)),
                const SizedBox(width: 5),
                Text(vText, style: TextStyle(fontSize: 12.5,
                    fontWeight: FontWeight.w900, color: vColor)),
                const Spacer(),
                if (q > 0) Text('⭐ $q/5  💎 $v/5',
                    style: const TextStyle(fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: UellowColors.muted)),
              ]),
              if (notes.isNotEmpty) Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(notes, style: const TextStyle(
                    fontSize: 11.5, height: 1.45)),
              ),
              for (final r in replies) Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text('💬 ${r['text']}', style: const TextStyle(
                    fontSize: 11, height: 1.4, color: UellowColors.text)),
              ),
            ]),
          ),
        ],
      ]),
    );
  }
}
