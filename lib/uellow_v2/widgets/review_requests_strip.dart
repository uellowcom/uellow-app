// =============================================================================
// ReviewRequestsStrip (v2.1.59) — quiet personal strip for the customer's
// specialist requests: «⏳ طلبك قيد الرد» while pending, flips to a green
// «✅ رد المختص — اعرض الرد» the moment a verdict lands. Tapping opens a
// clean dialog with the full reply + a button to the product. Answered
// items are remembered (prefs) so the strip never nags twice.
// =============================================================================
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../api/uellow_api.dart';
import '../router/uellow_router.dart';
import '../theme/uellow_theme.dart';

class ReviewRequestsStrip extends StatefulWidget {
  const ReviewRequestsStrip({super.key});
  @override
  State<ReviewRequestsStrip> createState() => _ReviewRequestsStripState();
}

class _ReviewRequestsStripState extends State<ReviewRequestsStrip> {
  Map<String, dynamic>? _item;     // the one request worth surfacing
  bool _answered = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final tok = await UellowApi.instance.tokenStore.readToken();
      if (tok == null || tok.isEmpty) return;
      final res = await UellowApi.instance
          .getRaw('/api/mobile/v2/reviewers/my-requests', auth: true);
      final items = List<Map<String, dynamic>>.from(
          (res['data']?['items'] as List?) ?? const []);
      if (items.isEmpty || !mounted) return;
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getStringList('seen_review_replies') ?? const [];
      // priority 1: a COMPLETED reply not seen yet
      for (final it in items) {
        if ((it['state'] ?? '') == 'completed' &&
            !seen.contains('${it['id']}')) {
          if (mounted) {
            setState(() { _item = it; _answered = true; });
          }
          return;
        }
      }
      // priority 2: a request still waiting (gentle status line)
      for (final it in items) {
        final st = (it['state'] ?? '').toString();
        if (st == 'pending' || st == 'accepted' || st == 'active') {
          if (mounted) {
            setState(() { _item = it; _answered = false; });
          }
          return;
        }
      }
    } catch (_) {/* strip must never break a screen */}
  }

  Future<void> _markSeen() async {
    final id = '${_item?['id']}';
    try {
      final prefs = await SharedPreferences.getInstance();
      final seen =
          prefs.getStringList('seen_review_replies') ?? <String>[];
      if (!seen.contains(id)) seen.add(id);
      await prefs.setStringList('seen_review_replies', seen);
    } catch (_) {}
  }

  void _open() {
    final it = _item;
    if (it == null) return;
    final ar = UellowApi.instance.lang == 'ar';
    final product =
        (it['product'] as Map?)?.cast<String, dynamic>() ?? const {};
    final reviewer =
        (it['reviewer'] as Map?)?.cast<String, dynamic>() ?? const {};
    final verdict = (it['verdict'] ?? '').toString();
    final notes = (it['notes'] ?? '').toString();
    final replies = List<Map<String, dynamic>>.from(
        (it['replies'] as List?) ?? const []);
    final q = (it['quality'] as num?)?.toInt() ?? 0;
    final v = (it['value'] as num?)?.toInt() ?? 0;
    final img = (product['image'] ?? '').toString();
    final (vIcon, vText, vColor) = switch (verdict) {
      'recommend' => ('👍', ar ? 'أنصح بالشراء' : 'Recommended',
          UellowColors.successDk),
      'not_recommend' => ('👎', ar ? 'لا أنصح' : 'Not recommended',
          UellowColors.danger),
      'neutral' => ('😐', ar ? 'محايد' : 'Neutral',
          const Color(0xFFB8860B)),
      _ => ('⏳', ar ? 'بانتظار الرد' : 'Waiting', UellowColors.muted),
    };
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius:
          BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 26),
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: const Color(0xFFE3E3E3),
                  borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 12),
          // product head
          Row(children: [
            if (img.isNotEmpty) ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: CachedNetworkImage(
                  imageUrl: img.startsWith('http')
                      ? img : '${UellowApi.instance.baseUrl}$img',
                  width: 50, height: 50, fit: BoxFit.cover,
                  errorWidget: (_, __, ___) =>
                      const ColoredBox(color: Color(0xFFEFEFEF))),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(((product['name'] as Map?)?[ar ? 'ar' : 'en'] ?? '')
                      .toString(),
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13,
                      fontWeight: FontWeight.w800)),
              Text((reviewer['name'] ?? '').toString(),
                  style: const TextStyle(fontSize: 11,
                      color: UellowColors.muted)),
            ])),
          ]),
          const SizedBox(height: 12),
          // verdict
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: vColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: vColor.withValues(alpha: 0.3)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Row(children: [
                Text(vIcon, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 6),
                Text(vText, style: TextStyle(fontSize: 14,
                    fontWeight: FontWeight.w900, color: vColor)),
                const Spacer(),
                if (q > 0) Text('⭐ $q/5  💎 $v/5',
                    style: const TextStyle(fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: UellowColors.muted)),
              ]),
              if (notes.isNotEmpty) Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(notes, style: const TextStyle(fontSize: 12.5,
                    height: 1.45)),
              ),
              for (final r in replies) Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('💬 ${r['text']}',
                    style: const TextStyle(fontSize: 12, height: 1.4,
                        color: UellowColors.text)),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                final pid = (product['id'] as num?)?.toInt() ?? 0;
                if (pid > 0) UellowRouter.goProduct(context, pid);
              },
              icon: const Icon(Icons.shopping_bag_outlined, size: 16),
              style: ElevatedButton.styleFrom(
                backgroundColor: UellowColors.yellow,
                foregroundColor: UellowColors.darkBrown,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              label: Text(ar ? 'فتح المنتج' : 'Open product',
                  style: const TextStyle(fontWeight: FontWeight.w900,
                      fontSize: 12.5)),
            )),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx),
              style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12)),
              child: Text(ar ? 'إغلاق' : 'Close',
                  style: const TextStyle(fontSize: 12.5)),
            ),
          ]),
        ]),
      ),
    ).whenComplete(() {
      if (_answered) {
        _markSeen();
        if (mounted) setState(() => _item = null);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final it = _item;
    if (it == null) return const SizedBox.shrink();
    final ar = UellowApi.instance.lang == 'ar';
    final product =
        (it['product'] as Map?)?.cast<String, dynamic>() ?? const {};
    final pname = ((product['name'] as Map?)?[ar ? 'ar' : 'en'] ?? '')
        .toString();
    final color = _answered
        ? UellowColors.successDk : const Color(0xFF1565C0);
    final bg = _answered
        ? const Color(0xFFEFFAF3) : const Color(0xFFF0F6FF);
    return Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: GestureDetector(
        onTap: _open,
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(children: [
            Text(_answered ? '✅' : '🎓',
                style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Expanded(child: Text(
                _answered
                    ? (ar ? 'رد عليك المختص بخصوص $pname'
                          : 'Specialist replied about $pname')
                    : (ar ? 'طلب مراجعتك لـ $pname قيد الرد…'
                          : 'Your review request for $pname is pending…'),
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5,
                    fontWeight: FontWeight.w800, color: color))),
            Text(_answered
                ? (ar ? 'اعرض الرد' : 'View')
                : (ar ? 'تفاصيل' : 'Details'),
                style: TextStyle(fontSize: 10.5,
                    fontWeight: FontWeight.w900, color: color)),
            Icon(Icons.chevron_right, size: 16, color: color),
          ]),
        ),
      ),
    );
  }
}
