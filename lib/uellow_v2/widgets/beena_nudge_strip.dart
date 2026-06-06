// =============================================================================
// Beena proactive nudges (v2.1.82) — a premium teaser that floats ABOVE the
// bottom nav and rotates through Beena's unread proactive messages (abandoned
// cart, an order on the way, redeemable points). The Beena tab also shows a
// count badge = number of unread nudges. Opening Beena marks them seen.
//
// One shared cache (singleton) fans out to every page via ValueNotifiers, so
// it's a single throttled network call no matter how many screens mount it.
// =============================================================================
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../api/uellow_api.dart';
import '../router/uellow_router.dart';
import '../theme/uellow_theme.dart';

const _kSeenKey = 'beena_nudges_seen_v1';

class BeenaNudgeCache {
  BeenaNudgeCache._();
  static final BeenaNudgeCache instance = BeenaNudgeCache._();

  final ValueNotifier<List<Map<String, dynamic>>> items =
      ValueNotifier<List<Map<String, dynamic>>>(const []);
  final ValueNotifier<int> unread = ValueNotifier<int>(0);

  DateTime? _last;
  Set<String> _seen = {};
  bool _seenLoaded = false;

  Future<void> _loadSeen() async {
    if (_seenLoaded) return;
    try {
      final sp = await SharedPreferences.getInstance();
      _seen = (sp.getStringList(_kSeenKey) ?? const []).toSet();
    } catch (_) {}
    _seenLoaded = true;
  }

  Future<void> load({bool force = false}) async {
    if (!force && _last != null &&
        DateTime.now().difference(_last!).inSeconds < 45) return;
    _last = DateTime.now();
    await _loadSeen();
    try {
      final list = await UellowApi.instance.beena.nudges();
      items.value = list;
      // prune seen ids that no longer exist so the set stays small
      final ids = list.map((n) => '${n['id']}').toSet();
      _seen = _seen.intersection(ids);
      _recount();
    } catch (_) {/* keep last */}
  }

  void _recount() {
    unread.value =
        items.value.where((n) => !_seen.contains('${n['id']}')).length;
  }

  Future<void> markAllSeen() async {
    _seen.addAll(items.value.map((n) => '${n['id']}'));
    _recount();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setStringList(_kSeenKey, _seen.toList());
    } catch (_) {}
  }

  bool isUnread(Map<String, dynamic> n) => !_seen.contains('${n['id']}');
}

/// The floating teaser shown above the bottom nav. Auto-rotates through the
/// unread nudges; tap opens Beena.
class BeenaNudgeStrip extends StatefulWidget {
  const BeenaNudgeStrip({super.key});
  @override
  State<BeenaNudgeStrip> createState() => _BeenaNudgeStripState();
}

class _BeenaNudgeStripState extends State<BeenaNudgeStrip> {
  Timer? _rotate;
  int _idx = 0;
  bool _hidden = false;

  bool get _ar => UellowApi.instance.lang.toLowerCase().startsWith('ar');

  @override
  void initState() {
    super.initState();
    BeenaNudgeCache.instance.load();
    BeenaNudgeCache.instance.items.addListener(_onItems);
    _rotate = Timer.periodic(const Duration(seconds: 4), (_) {
      final list = _unreadList();
      if (list.length > 1 && mounted) setState(() => _idx = (_idx + 1) % list.length);
    });
  }

  @override
  void dispose() {
    _rotate?.cancel();
    BeenaNudgeCache.instance.items.removeListener(_onItems);
    super.dispose();
  }

  void _onItems() { if (mounted) setState(() { _idx = 0; _hidden = false; }); }

  List<Map<String, dynamic>> _unreadList() => BeenaNudgeCache.instance.items.value
      .where(BeenaNudgeCache.instance.isUnread).toList();

  IconData _icon(String k) {
    switch (k) {
      case 'truck': return Icons.local_shipping_outlined;
      case 'cart':  return Icons.shopping_cart_outlined;
      case 'gift':  return Icons.card_giftcard;
    }
    return Icons.auto_awesome;
  }

  @override
  Widget build(BuildContext context) {
    final list = _unreadList();
    if (_hidden || list.isEmpty) return const SizedBox.shrink();
    final n = list[_idx % list.length];
    final ar = _ar;
    final label = (n['text'] is Map)
        ? (n['text'][ar ? 'ar' : 'en'] ?? n['label'] ?? '').toString()
        : (n['label'] ?? '').toString();
    return GestureDetector(
      onTap: () {
        BeenaNudgeCache.instance.markAllSeen();
        final oid = (n['order_id'] as num?)?.toInt();
        if (n['kind'] == 'track' && oid != null) {
          Navigator.pushNamed(context, Routes.order, arguments: {'id': oid});
        } else if (n['kind'] == 'cart') {
          Navigator.pushNamed(context, Routes.beena);
        } else {
          Navigator.pushNamed(context, Routes.beena);
        }
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        transitionBuilder: (c, a) => SlideTransition(
          position: Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(a),
          child: FadeTransition(opacity: a, child: c)),
        child: Container(
          key: ValueKey('${n['id']}'),
          margin: const EdgeInsets.fromLTRB(10, 0, 10, 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFFFFF3C9), Color(0xFFFFE588)],
                begin: Alignment.centerLeft, end: Alignment.centerRight),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFEBC54B)),
            boxShadow: const [BoxShadow(color: Color(0x33C99000),
                blurRadius: 10, offset: Offset(0, 3))],
          ),
          child: Row(children: [
            // bee badge
            Container(
              width: 30, height: 30,
              decoration: const BoxDecoration(shape: BoxShape.circle,
                gradient: RadialGradient(center: Alignment(-0.3, -0.4),
                  colors: [Color(0xFFFFE45E), UellowColors.yellow, Color(0xFFC99000)])),
              alignment: Alignment.center,
              child: Icon(_icon((n['icon'] ?? '').toString()), size: 16,
                  color: UellowColors.darkBrown),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                const Text('Beena', style: TextStyle(fontSize: 10.5,
                    fontWeight: FontWeight.w900, color: UellowColors.darkBrown)),
                const SizedBox(width: 4),
                const Text('🐝', style: TextStyle(fontSize: 10)),
                if (list.length > 1) ...[
                  const Spacer(),
                  Row(mainAxisSize: MainAxisSize.min, children: List.generate(
                      list.length.clamp(0, 5), (i) => Container(
                    width: 5, height: 5, margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration: BoxDecoration(shape: BoxShape.circle,
                      color: (i == _idx % list.length)
                          ? UellowColors.darkBrown : const Color(0x55412402)),
                  ))),
                ],
              ]),
              const SizedBox(height: 1),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700,
                      color: UellowColors.darkBrown)),
            ])),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () { BeenaNudgeCache.instance.markAllSeen();
                  setState(() => _hidden = true); },
              child: const Padding(padding: EdgeInsets.all(2),
                child: Icon(Icons.close, size: 16, color: Color(0x99412402))),
            ),
          ]),
        ),
      ),
    );
  }
}
