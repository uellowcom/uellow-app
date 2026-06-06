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

/// v2.1.92 — a small CHAT BUBBLE that pops out of the Beena tab icon
/// (speech-bubble tail pointing at it), shows the nudge for a few seconds
/// and slips away on its own. Far less intrusive than the old full-width
/// strip; the unread badge on the tab stays as the persistent reminder.
class BeenaNudgeStrip extends StatefulWidget {
  const BeenaNudgeStrip({super.key, this.anchorFraction});
  /// Horizontal centre of the Beena tab as a 0..1 fraction of the nav row
  /// (in layout order). Null → centred.
  final double? anchorFraction;
  @override
  State<BeenaNudgeStrip> createState() => _BeenaNudgeStripState();
}

class _BeenaNudgeStripState extends State<BeenaNudgeStrip> {
  Timer? _rotate;
  Timer? _autoHide;
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
      if (list.length > 1 && mounted && !_hidden) {
        setState(() => _idx = (_idx + 1) % list.length);
      }
    });
    _armAutoHide();
  }

  // the bubble disappears by itself after a few seconds — the tab badge
  // keeps the reminder, so nothing nags the customer.
  void _armAutoHide() {
    _autoHide?.cancel();
    _autoHide = Timer(const Duration(seconds: 8), () {
      if (mounted && !_hidden) setState(() => _hidden = true);
    });
  }

  @override
  void dispose() {
    _rotate?.cancel();
    _autoHide?.cancel();
    BeenaNudgeCache.instance.items.removeListener(_onItems);
    super.dispose();
  }

  void _onItems() {
    if (!mounted) return;
    setState(() { _idx = 0; _hidden = false; });
    _armAutoHide();
  }

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
    final n = (_hidden || list.isEmpty) ? null : list[_idx % list.length];
    // Anchor the bubble (and its tail) over the Beena tab. The fraction is
    // in ROW ORDER — flip for RTL since Alignment.x is physical.
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final f = widget.anchorFraction ?? 0.5;
    final ax = (-1 + 2 * (rtl ? 1 - f : f)).clamp(-0.92, 0.92);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      transitionBuilder: (c, a) => ScaleTransition(
        scale: a, alignment: Alignment(ax, 1),
        child: FadeTransition(opacity: a, child: c)),
      child: n == null
          ? const SizedBox.shrink()
          : Align(
              key: ValueKey('${n['id']}-$_idx'),
              alignment: Alignment(ax, 0),
              child: _bubble(context, n, list.length),
            ),
    );
  }

  Widget _bubble(BuildContext context, Map<String, dynamic> n, int total) {
    final ar = _ar;
    final label = (n['text'] is Map)
        ? (n['text'][ar ? 'ar' : 'en'] ?? n['label'] ?? '').toString()
        : (n['label'] ?? '').toString();
    return GestureDetector(
      onTap: () {
        BeenaNudgeCache.instance.markAllSeen();
        setState(() => _hidden = true);
        final oid = (n['order_id'] as num?)?.toInt();
        if (n['kind'] == 'track' && oid != null) {
          Navigator.pushNamed(context, Routes.order, arguments: {'id': oid});
        } else {
          Navigator.pushNamed(context, Routes.beena);
        }
      },
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          constraints: const BoxConstraints(maxWidth: 250),
          margin: const EdgeInsets.symmetric(horizontal: 10),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFEBC54B)),
            boxShadow: const [BoxShadow(color: Color(0x2E412402),
                blurRadius: 10, offset: Offset(0, 3))],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 26, height: 26,
              decoration: const BoxDecoration(shape: BoxShape.circle,
                gradient: RadialGradient(center: Alignment(-0.3, -0.4),
                  colors: [Color(0xFFFFE45E), UellowColors.yellow, Color(0xFFC99000)])),
              alignment: Alignment.center,
              child: Icon(_icon((n['icon'] ?? '').toString()), size: 14,
                  color: UellowColors.darkBrown),
            ),
            const SizedBox(width: 8),
            Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min, children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                const Text('Beena 🐝', style: TextStyle(fontSize: 9.5,
                    fontWeight: FontWeight.w900, color: Color(0x99412402))),
                if (total > 1) ...[
                  const SizedBox(width: 6),
                  Text('${(_idx % total) + 1}/$total', style: const TextStyle(
                      fontSize: 8.5, fontWeight: FontWeight.w800,
                      color: Color(0x66412402))),
                ],
              ]),
              Text(label, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700,
                      color: UellowColors.darkBrown, height: 1.25)),
            ])),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () { BeenaNudgeCache.instance.markAllSeen();
                  setState(() => _hidden = true); },
              child: const Icon(Icons.close, size: 14, color: Color(0x77412402)),
            ),
          ]),
        ),
        // speech-bubble tail pointing down at the Beena icon
        Transform.translate(
          offset: const Offset(0, -5),
          child: Transform.rotate(
            angle: 0.7853981633974483, // 45°
            child: Container(width: 10, height: 10,
              decoration: const BoxDecoration(color: Colors.white,
                border: Border(
                  right: BorderSide(color: Color(0xFFEBC54B)),
                  bottom: BorderSide(color: Color(0xFFEBC54B)),
                ))),
          ),
        ),
      ]),
    );
  }
}
