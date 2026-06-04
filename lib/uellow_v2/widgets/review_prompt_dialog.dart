// =============================================================================
// ReviewPromptDialog (v2.1.50) — post-delivery review nudge with loyalty
// rewards. After an order is DELIVERED, the next app open greets the
// customer, lists the unreviewed items and offers points per review
// (more with a photo). Reviews are submitted inline — stars, text,
// photos — and the awarded points are celebrated on the spot.
//
// Snooze rules (SharedPreferences):
//   review_prompt_done_<orderId>    → never ask again for this order
//   review_prompt_snooze_<orderId>  → epoch ms; re-ask after 3 days
// =============================================================================
import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../api/uellow_api.dart';
import '../theme/uellow_theme.dart';

class ReviewPromptService {
  static bool _shownThisSession = false;

  static Future<void> maybeShow(BuildContext context) async {
    if (_shownThisSession) return;
    try {
      final token = await UellowApi.instance.tokenStore.readToken();
      if (token == null || token.isEmpty) return;
      final r = await http.get(
        Uri.parse('${UellowApi.instance.baseUrl}/api/mobile/v2/reviews/prompt'),
        headers: {'Accept': 'application/json',
                  'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 8));
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      final prompt = (j['data']?['prompt'] as Map?)?.cast<String, dynamic>();
      if (prompt == null) return;
      final orderId = (prompt['order_id'] as num?)?.toInt() ?? 0;
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('review_prompt_done_$orderId') == true) return;
      final snoozed = prefs.getInt('review_prompt_snooze_$orderId') ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - snoozed <
          3 * 24 * 3600 * 1000) {
        return;
      }
      if (!context.mounted) return;
      _shownThisSession = true;
      showModalBottomSheet(
        context: context, isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => ReviewPromptDialog(prompt: prompt),
      );
    } catch (_) {/* never block startup */}
  }
}

class ReviewPromptDialog extends StatefulWidget {
  const ReviewPromptDialog({super.key, required this.prompt});
  final Map<String, dynamic> prompt;
  @override
  State<ReviewPromptDialog> createState() => _ReviewPromptDialogState();
}

class _ReviewPromptDialogState extends State<ReviewPromptDialog> {
  late List<Map<String, dynamic>> _items;
  int _selected = 0;
  int _rating = 5;
  final _text = TextEditingController();
  final List<File> _photos = [];
  bool _busy = false;
  int? _justAwarded;          // success state when not null
  int _totalAwarded = 0;

  int get _orderId => (widget.prompt['order_id'] as num?)?.toInt() ?? 0;
  int get _ptsText => (widget.prompt['points_text'] as num?)?.toInt() ?? 5;
  int get _ptsPhoto => (widget.prompt['points_photo'] as num?)?.toInt() ?? 15;

  @override
  void initState() {
    super.initState();
    _items = ((widget.prompt['items'] as List?) ?? const [])
        .cast<Map>().map((m) => m.cast<String, dynamic>()).toList();
  }

  Future<void> _snooze() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('review_prompt_snooze_$_orderId',
        DateTime.now().millisecondsSinceEpoch);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _markDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('review_prompt_done_$_orderId', true);
  }

  Future<void> _pickPhoto() async {
    final p = await ImagePicker().pickImage(source: ImageSource.gallery,
        maxWidth: 1280, maxHeight: 1280, imageQuality: 80);
    if (p != null && mounted) setState(() => _photos.add(File(p.path)));
  }

  Future<void> _submit() async {
    if (_busy || _items.isEmpty) return;
    setState(() => _busy = true);
    final ar = UellowApi.instance.lang == 'ar';
    try {
      final photos = <String>[];
      for (final f in _photos) {
        try { photos.add(base64Encode(await f.readAsBytes())); } catch (_) {}
      }
      final item = _items[_selected];
      final res = await UellowApi.instance.reviews.create(
        productId: (item['product_id'] as num).toInt(),
        rating: _rating.toDouble(),
        body: _text.text.trim().isEmpty
            ? (ar ? 'لا توجد ملاحظات' : 'No comment')
            : _text.text.trim(),
        photosBase64: photos,
      );
      final pts = (res['points_awarded'] as num?)?.toInt() ?? 0;
      if (!mounted) return;
      setState(() {
        _totalAwarded += pts;
        _justAwarded = pts;
        _items.removeAt(_selected);
        _selected = 0;
        _rating = 5;
        _text.clear();
        _photos.clear();
        _busy = false;
      });
      if (_items.isEmpty) _markDone();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // ── celebratory gold header ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [Color(0xFFFFD340), Color(0xFFF5C320),
                           Color(0xFFE8A800)],
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              ),
              child: _justAwarded != null
                  ? Column(children: [
                      const Text('🎉', style: TextStyle(fontSize: 40)),
                      const SizedBox(height: 6),
                      Text(
                          _justAwarded! > 0
                              ? (ar ? '+$_justAwarded نقطة أُضيفت لرصيدك!'
                                    : '+$_justAwarded points added!')
                              : (ar ? 'شكراً لتقييمك!' : 'Thanks for your review!'),
                          style: const TextStyle(fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: UellowColors.darkBrown)),
                      if (_totalAwarded > _justAwarded!)
                        Text(ar
                                ? 'إجمالي هذه الجلسة: +$_totalAwarded نقطة'
                                : 'Session total: +$_totalAwarded points',
                            style: const TextStyle(fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xB3412402))),
                    ])
                  : Column(children: [
                      const Text('📦✨', style: TextStyle(fontSize: 34)),
                      const SizedBox(height: 6),
                      Text(ar ? 'وصل طلبك بالسلامة!' : 'Your order arrived!',
                          style: const TextStyle(fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: UellowColors.darkBrown)),
                      const SizedBox(height: 3),
                      Text(
                          ar
                              ? 'شاركنا رأيك في مشترياتك واكسب نقاط ولاء فورية'
                              : 'Rate your purchases and earn instant loyalty points',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xCC412402))),
                    ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
              child: _items.isEmpty
                  ? _allDone(ar)
                  : Column(crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                      // ── reward pills ──
                      Row(children: [
                        _pill('⭐ +$_ptsText ${ar ? "نقطة" : "pts"}',
                            const Color(0xFFFFF8E1), const Color(0xFF8B6508)),
                        const SizedBox(width: 6),
                        _pill('📸 +$_ptsPhoto ${ar ? "نقطة مع صورة" : "pts with photo"}',
                            const Color(0xFFE8F5E9), const Color(0xFF1B5E20)),
                      ]),
                      const SizedBox(height: 12),
                      // ── item selector ──
                      Text(ar ? 'اختر المنتج' : 'Pick a product',
                          style: const TextStyle(fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: UellowColors.text)),
                      const SizedBox(height: 6),
                      SizedBox(height: 76, child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) {
                          final it = _items[i];
                          final sel = i == _selected;
                          return GestureDetector(
                            onTap: () => setState(() => _selected = i),
                            child: Container(
                              width: 64,
                              decoration: BoxDecoration(
                                border: Border.all(
                                    color: sel
                                        ? UellowColors.yellow
                                        : UellowColors.border,
                                    width: sel ? 2.5 : 1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: CachedNetworkImage(
                                imageUrl: (it['image'] ?? '').toString(),
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => const Icon(
                                    Icons.image_outlined,
                                    color: UellowColors.muted),
                              ),
                            ),
                          );
                        },
                      )),
                      const SizedBox(height: 4),
                      Text(
                          ((_items[_selected]['name'] as Map?)?[
                                  ar ? 'ar' : 'en'] ?? '').toString(),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: UellowColors.ink)),
                      const SizedBox(height: 10),
                      // ── stars ──
                      Center(child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                        for (var i = 1; i <= 5; i++) GestureDetector(
                          onTap: () => setState(() => _rating = i),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: Icon(
                                i <= _rating
                                    ? Icons.star_rounded
                                    : Icons.star_outline_rounded,
                                size: 34,
                                color: i <= _rating
                                    ? const Color(0xFFFFC107)
                                    : const Color(0xFFD6D6D6)),
                          ),
                        ),
                      ])),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _text,
                        maxLines: 2,
                        style: const TextStyle(fontSize: 12.5),
                        decoration: InputDecoration(
                          hintText: ar
                              ? 'اكتب رأيك (اختياري)…'
                              : 'Write your thoughts (optional)…',
                          hintStyle: const TextStyle(fontSize: 11.5,
                              color: UellowColors.muted),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                  color: UellowColors.border)),
                          contentPadding: const EdgeInsets.all(10),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // ── photos (bonus points!) ──
                      Row(children: [
                        OutlinedButton.icon(
                          onPressed: _pickPhoto,
                          icon: const Icon(Icons.add_a_photo_outlined,
                              size: 15),
                          label: Text(
                              ar ? 'أضف صورة (+$_ptsPhoto)' : 'Add photo (+$_ptsPhoto)',
                              style: const TextStyle(fontSize: 11,
                                  fontWeight: FontWeight.w800)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF1B5E20),
                            side: const BorderSide(color: Color(0xFFC8E6C9)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        for (var i = 0; i < _photos.length; i++) Padding(
                          padding: const EdgeInsetsDirectional.only(end: 6),
                          child: Stack(children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(_photos[i],
                                  width: 40, height: 40, fit: BoxFit.cover),
                            ),
                            Positioned(top: -2, right: -2, child:
                              GestureDetector(
                                onTap: () => setState(
                                    () => _photos.removeAt(i)),
                                child: const CircleAvatar(radius: 8,
                                    backgroundColor: UellowColors.danger,
                                    child: Icon(Icons.close, size: 10,
                                        color: Colors.white)),
                              )),
                          ]),
                        ),
                      ]),
                      const SizedBox(height: 14),
                      // ── CTA row ──
                      Row(children: [
                        Expanded(child: ElevatedButton(
                          onPressed: _busy ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: UellowColors.darkBrown,
                            foregroundColor: UellowColors.yellowLight,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(13)),
                          ),
                          child: Text(
                              _busy
                                  ? (ar ? 'جارٍ الإرسال…' : 'Sending…')
                                  : (ar
                                      ? '⭐ قيّم واكسب النقاط'
                                      : '⭐ Rate & earn points'),
                              style: const TextStyle(fontSize: 13.5,
                                  fontWeight: FontWeight.w900)),
                        )),
                      ]),
                      Center(child: TextButton(
                        onPressed: _snooze,
                        child: Text(ar ? 'لاحقاً' : 'Maybe later',
                            style: const TextStyle(fontSize: 12,
                                color: UellowColors.muted,
                                fontWeight: FontWeight.w600)),
                      )),
                    ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _allDone(bool ar) => Column(children: [
    const SizedBox(height: 6),
    Text(ar ? 'قيّمت كل منتجات الطلب — شكراً لك! 🤝'
            : 'You rated everything in this order — thank you! 🤝',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800,
            color: UellowColors.ink, height: 1.5)),
    const SizedBox(height: 12),
    SizedBox(width: double.infinity, child: ElevatedButton(
      onPressed: () => Navigator.pop(context),
      style: ElevatedButton.styleFrom(
        backgroundColor: UellowColors.yellow,
        foregroundColor: UellowColors.darkBrown,
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      child: Text(ar ? 'تم' : 'Done',
          style: const TextStyle(fontWeight: FontWeight.w900)),
    )),
  ]);

  Widget _pill(String label, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
        color: bg, borderRadius: BorderRadius.circular(999)),
    child: Text(label, style: TextStyle(fontSize: 10.5,
        fontWeight: FontWeight.w800, color: fg)),
  );
}
