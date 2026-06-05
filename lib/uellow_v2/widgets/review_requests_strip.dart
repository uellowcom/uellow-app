// =============================================================================
// ReviewReplyBanner (v2.1.62 — full rework of ReviewRequestsStrip).
// A premium floating banner anchored ABOVE the bottom nav bar on every
// page that carries it. Appears right after the customer asks a
// specialist for a review and follows them everywhere until THEY close
// it (✕ on top). Shows the full state — product, specialist, status —
// waiting = deep blue, flips GREEN the moment the reply lands (a closed
// "waiting" banner re-appears on reply: dismissal is keyed per status).
// Tapping opens the detailed reply sheet.
// =============================================================================
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../api/uellow_api.dart';
import '../router/uellow_router.dart';
import '../theme/uellow_theme.dart';

/// Shared cache so every page shows the SAME banner instantly without
/// refetching: one network call, throttled to 45s, fanned out through a
/// ValueNotifier all banner instances listen to.
class ReviewBannerCache {
  ReviewBannerCache._();
  static final ReviewBannerCache instance = ReviewBannerCache._();
  /// All answered (un-dismissed) replies surface TOGETHER in one banner;
  /// otherwise a single waiting request. Empty list = nothing to show.
  final ValueNotifier<List<Map<String, dynamic>>> items =
      ValueNotifier<List<Map<String, dynamic>>>(const []);
  DateTime? _lastFetch;
  Set<String> _dismissed = {};
  bool _prefsLoaded = false;

  Future<void> load({bool force = false}) async {
    if (!force && _lastFetch != null &&
        DateTime.now().difference(_lastFetch!).inSeconds < 45) {
      return;
    }
    _lastFetch = DateTime.now();
    try {
      final tok = await UellowApi.instance.tokenStore.readToken();
      if (tok == null || tok.isEmpty) { items.value = const []; return; }
      if (!_prefsLoaded) {
        final prefs = await SharedPreferences.getInstance();
        _dismissed =
            (prefs.getStringList('review_banner_dismissed') ?? const [])
                .toSet();
        _prefsLoaded = true;
      }
      final res = await UellowApi.instance
          .getRaw('/api/mobile/v2/reviewers/my-requests', auth: true);
      final list = List<Map<String, dynamic>>.from(
          (res['data']?['items'] as List?) ?? const []);
      // priority 1: ALL completed replies the customer hasn't closed —
      // multiple specialists answering before the customer opens the
      // request share ONE combined banner.
      final answered = list.where((it) =>
          (it['state'] ?? '') == 'completed' &&
          !_dismissed.contains('${it['id']}:completed')).toList();
      if (answered.isNotEmpty) {
        items.value = answered;
        return;
      }
      // priority 2: a request still waiting (and not closed while waiting)
      for (final it in list) {
        final st = (it['state'] ?? '').toString();
        if ((st == 'pending' || st == 'accepted' || st == 'active') &&
            !_dismissed.contains('${it['id']}:waiting')) {
          items.value = [it];
          return;
        }
      }
      items.value = const [];
    } catch (_) {/* banner must never break a screen */}
  }

  Future<void> dismiss(List<Map<String, dynamic>> shown) async {
    for (final it in shown) {
      final answered = (it['state'] ?? '') == 'completed';
      _dismissed.add('${it['id']}:${answered ? 'completed' : 'waiting'}');
    }
    items.value = const [];
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
          'review_banner_dismissed', _dismissed.toList());
    } catch (_) {}
  }
}

class ReviewReplyBanner extends StatefulWidget {
  const ReviewReplyBanner({super.key});
  @override
  State<ReviewReplyBanner> createState() => _ReviewReplyBannerState();
}

class _ReviewReplyBannerState extends State<ReviewReplyBanner> {
  @override
  void initState() {
    super.initState();
    ReviewBannerCache.instance.load();
  }

  void _open(Map<String, dynamic> it) {
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
    );
  }

  /// Up to 3 overlapping product thumbs for the combined banner.
  Widget _stackedThumbs(List<Map<String, dynamic>> all) {
    final imgs = all.take(3).map((e) =>
        ((e['product'] as Map?)?['image'] ?? '').toString()).toList();
    return SizedBox(
      width: 46.0 + (imgs.length - 1) * 18.0, height: 50,
      child: Stack(children: [
        for (var i = 0; i < imgs.length; i++)
          PositionedDirectional(
            start: i * 18.0, top: 2,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(
                    color: const Color(0xFFB7F0CC), width: 2),
              ),
              child: ClipOval(
                child: imgs[i].isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: imgs[i].startsWith('http')
                            ? imgs[i]
                            : '${UellowApi.instance.baseUrl}${imgs[i]}',
                        width: 38, height: 38, fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                            width: 38, height: 38,
                            color: const Color(0xFFEFEFEF)))
                    : Container(width: 38, height: 38,
                        color: const Color(0xFFEFEFEF),
                        alignment: Alignment.center,
                        child: const Text('🎓',
                            style: TextStyle(fontSize: 16))),
              ),
            ),
          ),
      ]),
    );
  }

  /// Combined sheet — every reply in one scrollable list, each with its
  /// product head, verdict and the specialist's words.
  void _openAll(List<Map<String, dynamic>> all) {
    final ar = UellowApi.instance.lang == 'ar';
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius:
          BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false, initialChildSize: .7, maxChildSize: .92,
        builder: (_, ctrl) => Column(children: [
          const SizedBox(height: 10),
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: const Color(0xFFE3E3E3),
                  borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
            child: Row(children: [
              Text(ar ? '✅ ردود المختصين (${all.length})'
                      : '✅ Specialist replies (${all.length})',
                  style: const TextStyle(fontSize: 15,
                      fontWeight: FontWeight.w900)),
            ]),
          ),
          Expanded(child: ListView.builder(
            controller: ctrl,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            itemCount: all.length,
            itemBuilder: (_, i) => _replyCard(ctx, all[i], ar),
          )),
        ]),
      ),
    );
  }

  Widget _replyCard(BuildContext ctx, Map<String, dynamic> it, bool ar) {
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
      _ => ('💬', ar ? 'رد' : 'Reply', UellowColors.muted),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBFE8CD)),
        boxShadow: const [BoxShadow(
            color: Color(0x0A000000), blurRadius: 6)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        GestureDetector(
          onTap: () {
            final pid = (product['id'] as num?)?.toInt() ?? 0;
            if (pid > 0) {
              Navigator.pop(ctx);
              UellowRouter.goProduct(context, pid);
            }
          },
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: img.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: img.startsWith('http')
                          ? img : '${UellowApi.instance.baseUrl}$img',
                      width: 44, height: 44, fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(
                          width: 44, height: 44,
                          color: const Color(0xFFEFEFEF)))
                  : Container(width: 44, height: 44,
                      color: const Color(0xFFEFEFEF)),
            ),
            const SizedBox(width: 9),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(((product['name'] as Map?)?[ar ? 'ar' : 'en'] ?? '')
                      .toString(),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5,
                      fontWeight: FontWeight.w800)),
              Text('👤 ${reviewer['name'] ?? ''}',
                  style: const TextStyle(fontSize: 10.5,
                      color: UellowColors.muted)),
            ])),
            Icon(ar ? Icons.chevron_left : Icons.chevron_right,
                size: 18, color: UellowColors.muted),
          ]),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: vColor.withValues(alpha: .07),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: vColor.withValues(alpha: .25)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Row(children: [
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
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Map<String, dynamic>>>(
      valueListenable: ReviewBannerCache.instance.items,
      builder: (context, all, _) {
        if (all.isEmpty) return const SizedBox.shrink();
        final it = all.first;
        final many = all.length > 1;
        final ar = UellowApi.instance.lang == 'ar';
        final answered = (it['state'] ?? '') == 'completed';
        final product =
            (it['product'] as Map?)?.cast<String, dynamic>() ?? const {};
        final reviewer =
            (it['reviewer'] as Map?)?.cast<String, dynamic>() ?? const {};
        final pname =
            ((product['name'] as Map?)?[ar ? 'ar' : 'en'] ?? '').toString();
        final rname = (reviewer['name'] ?? '').toString();
        final img = (product['image'] ?? '').toString();
        final type = (it['review_type'] ?? '').toString();
        final typeLabel = switch (type) {
          'chat'  => ar ? 'استشارة مباشرة' : 'Live chat',
          'video' => ar ? 'مراجعة فيديو' : 'Video review',
          'photo' => ar ? 'مراجعة بالصور' : 'Photo review',
          _       => ar ? 'رأي مكتوب' : 'Written review',
        };
        // waiting = deep blue night, answered = fresh green
        final g1 = answered ? const Color(0xFF146C36) : const Color(0xFF143B66);
        final g2 = answered ? const Color(0xFF27AE60) : const Color(0xFF1D5FA8);
        final chipBg = Colors.white.withValues(alpha: .16);
        return Directionality(
          textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
            child: Stack(clipBehavior: Clip.none, children: [
              // ── the banner card ──
              GestureDetector(
                onTap: () => many ? _openAll(all) : _open(it),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                        begin: AlignmentDirectional.centerStart,
                        end: AlignmentDirectional.centerEnd,
                        colors: [g1, g2]),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(
                        color: g2.withValues(alpha: .45),
                        blurRadius: 14, offset: const Offset(0, 4))],
                  ),
                  child: Row(children: [
                    // product thumb — single ring, or an overlapping
                    // stack when several specialists replied together.
                    many ? _stackedThumbs(all) : Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: answered
                                ? const Color(0xFFB7F0CC)
                                : const Color(0xFFFFD75E),
                            width: 2),
                      ),
                      child: ClipOval(
                        child: img.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: img.startsWith('http')
                                    ? img
                                    : '${UellowApi.instance.baseUrl}$img',
                                width: 46, height: 46, fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => Container(
                                    width: 46, height: 46,
                                    color: Colors.white24))
                            : Container(width: 46, height: 46,
                                color: Colors.white24,
                                alignment: Alignment.center,
                                child: const Text('🎓',
                                    style: TextStyle(fontSize: 20))),
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(
                          many
                              ? (ar ? '✅ وصلك ${all.length} ردود من المختصين!'
                                    : '✅ ${all.length} specialist replies!')
                              : answered
                                  ? (ar ? '✅ وصلك رد المختص!'
                                        : '✅ Specialist replied!')
                                  : (ar ? '🎓 طلب رأي مختص'
                                        : '🎓 Specialist review request'),
                          style: const TextStyle(color: Colors.white,
                              fontSize: 13.5, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 3),
                      Text(
                          many
                              ? (ar
                                  ? all.map((e) => (((e['product']
                                          as Map?)?['name'] as Map?)?['ar']
                                      ?? '').toString()).join(' · ')
                                  : all.map((e) => (((e['product']
                                          as Map?)?['name'] as Map?)?['en']
                                      ?? '').toString()).join(' · '))
                              : pname,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: .92),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 5),
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(color: chipBg,
                              borderRadius: BorderRadius.circular(20)),
                          child: Text(
                              answered
                                  ? (many
                                      ? (ar ? '✔ ${all.length} ردود'
                                            : '✔ ${all.length} replies')
                                      : (ar ? '✔ تم الرد' : '✔ Replied'))
                                  : (ar ? '⏳ قيد الرد' : '⏳ Pending'),
                              style: const TextStyle(color: Colors.white,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800)),
                        ),
                        if (!many) ...[
                          const SizedBox(width: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(color: chipBg,
                                borderRadius: BorderRadius.circular(20)),
                            child: Text(typeLabel,
                                style: const TextStyle(color: Colors.white,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800)),
                          ),
                        ],
                        if (many || rname.isNotEmpty) ...[
                          const SizedBox(width: 5),
                          Flexible(child: Text(
                              many
                                  ? '👤 ${all.map((e) => ((e['reviewer'] as Map?)?['name'] ?? '').toString()).where((n) => n.isNotEmpty).toSet().join('، ')}'
                                  : '👤 $rname',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color:
                                      Colors.white.withValues(alpha: .85),
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700))),
                        ],
                      ]),
                    ])),
                    const SizedBox(width: 8),
                    // CTA pill
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 11, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                          many
                              ? (ar ? 'اعرض الردود' : 'View replies')
                              : answered
                                  ? (ar ? 'اعرض الرد' : 'View reply')
                                  : (ar ? 'التفاصيل' : 'Details'),
                          style: TextStyle(
                              color: answered
                                  ? const Color(0xFF146C36)
                                  : const Color(0xFF143B66),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w900)),
                    ),
                  ]),
                ),
              ),
              // ── close button floating on the top edge ──
              PositionedDirectional(
                top: -9, end: 6,
                child: GestureDetector(
                  onTap: () => ReviewBannerCache.instance.dismiss(all),
                  child: Container(
                    width: 22, height: 22,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFE2E2E2)),
                      boxShadow: const [BoxShadow(
                          color: Color(0x33000000), blurRadius: 6)],
                    ),
                    child: const Icon(Icons.close, size: 14,
                        color: Color(0xFF555555)),
                  ),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }
}

/// Backwards-compat alias — old call sites render nothing now; the banner
/// lives globally above the bottom nav.
class ReviewRequestsStrip extends StatelessWidget {
  const ReviewRequestsStrip({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
