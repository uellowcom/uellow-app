// لمّة يلو الجماعية «شارك لمّتك» — collaborative group buying for the app.
// Talks to /api/mobile/v2/lamma/group/* using a device-persistent token.
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import '../api/uellow_api.dart';
import 'lamma.dart';

bool get _gar => UellowApi.instance.lang == 'ar';
const _gY = Color(0xFFF5C320);
const _gY2 = Color(0xFFE0A72E);
const _gBrown = Color(0xFF412402);
const _gO1 = Color(0xFFFF7A1A);
const _gO2 = Color(0xFFFF9E45);
const _gGreen = Color(0xFF0E9F6E);
const _gInk = Color(0xFF151515);
const _gMuted = Color(0xFF6B6B6B);
const _avatColors = [
  Color(0xFFFF7A1A), Color(0xFF3B82F6), Color(0xFF8B5CF6), Color(0xFF0E9F6E),
  Color(0xFFE0A72E), Color(0xFFEF4444), Color(0xFF14B8A6), Color(0xFFF59E0B),
];

String _cur() => _gar ? 'د.ك' : 'KD';
String _m(v) => (v == null ? 0.0 : (v as num).toDouble()).toStringAsFixed(3);

/// Singleton API + persistent device token for group identity.
class LammaGroupApi {
  LammaGroupApi._();
  static final LammaGroupApi instance = LammaGroupApi._();
  String? _token;

  String get _base => UellowApi.instance.baseUrl;
  Map<String, String> get _headers =>
      {'Content-Type': 'application/json', 'X-Lang': UellowApi.instance.lang};

  Future<String> token() async {
    if (_token != null && _token!.isNotEmpty) return _token!;
    final p = await SharedPreferences.getInstance();
    var t = p.getString('lamma_group_token');
    if (t == null || t.isEmpty) {
      final r = Random.secure();
      const cs = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
      t = List.generate(32, (_) => cs[r.nextInt(cs.length)]).join();
      await p.setString('lamma_group_token', t);
    }
    _token = t;
    return t;
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    try {
      body['token'] = await token();
      final res = await http
          .post(Uri.parse('$_base/api/mobile/v2/lamma/group/$path'),
              headers: _headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 20));
      final j = jsonDecode(res.body);
      return (j is Map) ? Map<String, dynamic>.from(j) : {'error': 'bad'};
    } catch (_) {
      return {'error': 'network'};
    }
  }

  Future<Map<String, dynamic>> create(
      {String? name, String type = 'normal',
      List<int>? productIds, Map<String, int>? variants}) =>
      _post('create', {
        'name': name, 'type': type,
        'product_ids': productIds ?? const [],
        'variants': variants ?? const {},
      });
  Future<Map<String, dynamic>> state(String code) => _post('state', {'code': code});
  Future<Map<String, dynamic>> join(String code, {String? name}) =>
      _post('join', {'code': code, 'name': name});
  Future<Map<String, dynamic>> add(String code, int productId, {int? variantId}) =>
      _post('add', {'code': code, 'product_id': productId, 'variant_id': variantId});
  Future<Map<String, dynamic>> remove(String code, int productId) =>
      _post('remove', {'code': code, 'product_id': productId});
  Future<Map<String, dynamic>> lock(String code) => _post('lock', {'code': code});
  Future<Map<String, dynamic>> pay(String code) => _post('pay', {'code': code});
}

/// Items currently in the user's solo Lamma (to seed / add to a group).
List<Map<String, dynamic>> _myLammaItems() {
  final q = LammaService.instance.quote.value;
  final items = (q?['items'] as List?) ?? const [];
  return items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
}

/// Create a group from the current solo Lamma and open the group screen.
Future<void> startGroupLamma(BuildContext context) async {
  final items = _myLammaItems();
  final ids = <int>[];
  final vars = <String, int>{};
  for (final it in items) {
    final id = (it['id'] as num?)?.toInt();
    if (id == null) continue;
    ids.add(id);
    final vid = (it['variant_id'] as num?)?.toInt();
    if (vid != null) vars['$id'] = vid;
  }
  final d = await LammaGroupApi.instance
      .create(productIds: ids, variants: vars.isEmpty ? null : vars);
  if (!context.mounted) return;
  final code = d['code'] as String?;
  if (code == null) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_gar ? 'تعذّر إنشاء اللمّة الجماعية' : 'Could not start the group')));
    return;
  }
  Navigator.push(context,
      MaterialPageRoute(builder: (_) => GroupLammaScreen(code: code, initial: d)));
}

/// Open a group by its share code (from a shared link or manual entry).
void openGroupCode(BuildContext context, String code) {
  Navigator.push(context,
      MaterialPageRoute(builder: (_) => GroupLammaScreen(code: code.trim().toUpperCase())));
}

/// Ask for a code and open it (a lightweight "join by code" entry).
Future<void> promptJoinByCode(BuildContext context) async {
  final ctrl = TextEditingController();
  final code = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(_gar ? 'انضم بلمّة برمز' : 'Join with a code'),
      content: TextField(
        controller: ctrl, autofocus: true, textCapitalization: TextCapitalization.characters,
        decoration: InputDecoration(hintText: _gar ? 'مثال: YL-7K2Q' : 'e.g. YL-7K2Q'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_gar ? 'إلغاء' : 'Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(_gar ? 'انضم' : 'Join')),
      ],
    ),
  );
  if (code != null && code.isNotEmpty && context.mounted) openGroupCode(context, code);
}

// ---------------------------------------------------------------------------
class GroupLammaScreen extends StatefulWidget {
  const GroupLammaScreen({super.key, required this.code, this.initial});
  final String code;
  final Map<String, dynamic>? initial;
  @override
  State<GroupLammaScreen> createState() => _GroupLammaScreenState();
}

class _GroupLammaScreenState extends State<GroupLammaScreen> {
  final _api = LammaGroupApi.instance;
  Map<String, dynamic>? _d;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _d = widget.initial;
    _reload();
    // gentle live refresh while the screen is open
    _tick();
  }

  bool _alive = true;
  @override
  void dispose() { _alive = false; super.dispose(); }

  Future<void> _tick() async {
    while (_alive) {
      await Future.delayed(const Duration(seconds: 12));
      if (!_alive) break;
      await _reload(silent: true);
    }
  }

  Future<void> _reload({bool silent = false}) async {
    final d = await _api.state(widget.code);
    if (!mounted) return;
    if (d['error'] == null || _d == null) setState(() => _d = d);
  }

  Future<void> _run(Future<Map<String, dynamic>> Function() f, {String? ok}) async {
    setState(() => _busy = true);
    final d = await f();
    if (!mounted) return;
    setState(() { _busy = false; if (d['error'] == null) _d = d; });
    if (d['error'] != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_gar ? 'تعذّر تنفيذ العملية' : 'Action failed')));
    } else if (ok != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F2EE),
      body: SafeArea(
        child: d == null
            ? const Center(child: CircularProgressIndicator(color: _gO1))
            : (d['error'] != null && d['code'] == null)
                ? _notFound()
                : _content(d),
      ),
    );
  }

  Widget _notFound() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('🧺', style: TextStyle(fontSize: 46)),
          const SizedBox(height: 10),
          Text(_gar ? 'لمّة غير موجودة أو انتهت' : 'Lamma not found',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          const SizedBox(height: 14),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _gY, foregroundColor: _gBrown),
              onPressed: () => Navigator.pop(context),
              child: Text(_gar ? 'رجوع' : 'Back')),
        ]),
      );

  Widget _header(Map d) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        child: Row(children: [
          _circleBtn('‹', () => Navigator.pop(context)),
          const SizedBox(width: 8),
          Expanded(
            child: Text('${d['name'] ?? 'لمّة جماعية'} 🧺',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            decoration: BoxDecoration(
                color: const Color(0xFFE7FBF2), borderRadius: BorderRadius.circular(999)),
            child: Text('👥 ${d['member_count'] ?? 0}',
                style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF047857), fontSize: 12)),
          ),
        ]),
      );

  Widget _circleBtn(String t, VoidCallback onTap) => InkWell(
        onTap: onTap, borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFECECEC))),
          alignment: Alignment.center,
          child: Text(t, style: const TextStyle(fontSize: 18)),
        ),
      );

  Widget _content(Map d) {
    final isMember = d['me'] != null;
    final state = d['state'] ?? 'open';
    if (!isMember && state == 'open') return _joinView(d);
    if (!isMember) return Column(children: [_header(d), Expanded(child: _closed(d))]);
    return _liveView(d);
  }

  Widget _closed(Map d) => Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('🔒', style: TextStyle(fontSize: 40)),
        const SizedBox(height: 8),
        Text(_gar ? 'هذه اللمّة مقفلة' : 'This Lamma is closed',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
      ]));

  // ---- JOIN (non-member, open) ----
  final _nameCtrl = TextEditingController();
  Widget _joinView(Map d) {
    final members = (d['members'] as List?) ?? const [];
    return Column(children: [
      _header(d),
      Expanded(
        child: ListView(padding: EdgeInsets.zero, children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [_gO1, _gO2]),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(26)),
            ),
            padding: const EdgeInsets.fromLTRB(18, 26, 18, 22),
            child: Column(children: [
              const Text('🧺', style: TextStyle(fontSize: 36)),
              const SizedBox(height: 4),
              Text('${d['host'] ?? 'صديقك'} ${_gar ? 'يدعوك للمّته' : 'invites you'}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: Colors.white)),
              const SizedBox(height: 6),
              Text(
                  _gar ? 'انضم وأضِف منتجاتك — كل ما زدتم وفّرتم أكثر'
                       : 'Join and add your items — the more you add, the more you save',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 13.5)),
              const SizedBox(height: 14),
              _avatarRow(members, white: true),
              const SizedBox(height: 10),
              Text(
                  _gar
                      ? '${d['member_count']} مشاركين · وفّروا حتى الآن ${_m(d['saved'])} ${_cur()}'
                      : '${d['member_count']} members · saved ${_m(d['saved'])} ${_cur()}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w700)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              _progressCard(d, lite: true),
              const SizedBox(height: 12),
              TextField(
                controller: _nameCtrl,
                textAlign: TextAlign.right,
                decoration: InputDecoration(
                  hintText: _gar ? 'اسمك (اختياري)' : 'Your name (optional)',
                  filled: true, fillColor: Colors.white,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(13), borderSide: BorderSide.none),
                ),
              ),
            ]),
          ),
        ]),
      ),
      _bottomBar([
        _bigBtn(_gar ? '🛍️ انضم للّمة' : '🛍️ Join the Lamma', _gradO, () {
          _run(() => _api.join(widget.code, name: _nameCtrl.text.trim()),
              ok: _gar ? 'انضممت للّمة 🎉' : 'Joined 🎉');
        }),
      ]),
    ]);
  }

  // ---- LIVE (member) ----
  Widget _liveView(Map d) {
    final me = d['me'] as Map?;
    final members = (d['members'] as List?) ?? const [];
    final state = d['state'] ?? 'open';
    final isHost = me?['is_host'] == true;
    final saved = (d['saved'] as num?)?.toDouble() ?? 0;
    return Column(children: [
      _header(d),
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), children: [
          // progress hero (dark)
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF151515), Color(0xFF2A2115)]),
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(_gar ? 'تدفعون معًا' : 'You pay together',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: Color(0xFFFFD98A))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                      color: const Color(0x330E9F6E), borderRadius: BorderRadius.circular(999)),
                  child: Text('${_gar ? 'وفّرتم' : 'saved'} ${_m(saved)} ${_cur()} 💚',
                      style: const TextStyle(color: Color(0xFF4ADE9B), fontWeight: FontWeight.w800, fontSize: 11.5)),
                ),
              ]),
              const SizedBox(height: 6),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(_m(d['pays']),
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 27, color: Colors.white)),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(_cur(), style: const TextStyle(color: Color(0xFFB9C2CF), fontSize: 13)),
                ),
                if (saved > 0) ...[
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(_m(d['subtotal']),
                        style: const TextStyle(
                            color: Color(0xFF8A8577), fontSize: 13,
                            decoration: TextDecoration.lineThrough)),
                  ),
                ],
              ]),
              _progressBar(d, lite: false),
            ]),
          ),
          const SizedBox(height: 14),
          if (me != null) _myShareCard(me),
          const SizedBox(height: 14),
          Text(_gar ? 'من أضاف ماذا' : 'Who added what',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
          const SizedBox(height: 8),
          _membersCard(members),
          if (isHost && state == 'open') ...[
            const SizedBox(height: 14),
            _shareCard(d),
          ],
        ]),
      ),
      _actionBar(d),
    ]);
  }

  Widget _myShareCard(Map me) => Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFFFFF6DA), Colors.white]),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFF1E3AE)),
        ),
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          _avatar((me['name'] ?? 'ض').toString(), 0, 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_gar ? 'نصيبك (${me['n']} منتج)' : 'Your share (${me['n']})',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
              Text(me['paid'] == true ? (_gar ? '✔ دفعت' : 'Paid') : (_gar ? 'تدفع نصيبك فقط' : 'You pay only your share'),
                  style: const TextStyle(color: _gMuted, fontSize: 12.5)),
            ]),
          ),
          Text('${_m(me['pays'])} ${_cur()}',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
        ]),
      );

  Widget _membersCard(List members) => Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Column(
          children: List.generate(members.length, (i) {
            final m = members[i] as Map;
            final items = (m['items'] as List?) ?? const [];
            final n = m['n'] ?? 0;
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                  border: i == members.length - 1
                      ? null
                      : const Border(bottom: BorderSide(color: Color(0xFFF0F0F0)))),
              child: Row(children: [
                _avatar((m['name'] ?? 'ض').toString(), i, 34),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Flexible(child: Text(m['name'] ?? 'ضيف',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13))),
                      if (m['is_host'] == true)
                        const Text(' · المضيف', style: TextStyle(color: _gO1, fontSize: 11, fontWeight: FontWeight.w700)),
                      if (m['is_me'] == true)
                        const Text(' · أنت', style: TextStyle(color: _gGreen, fontSize: 11, fontWeight: FontWeight.w700)),
                    ]),
                    Text(
                        (n == 0)
                            ? (_gar ? 'لم يضف بعد' : 'nothing yet')
                            : '$n ${_gar ? 'منتج' : 'items'} · ${_m(m['pays'])} ${_cur()}${m['paid'] == true ? (_gar ? ' · دفع ✔' : ' · paid ✔') : ''}',
                        style: const TextStyle(color: _gMuted, fontSize: 12)),
                  ]),
                ),
                _thumbs(items),
              ]),
            );
          }),
        ),
      );

  Widget _thumbs(List items) {
    final base = UellowApi.instance.baseUrl;
    final shown = items.take(3).toList();
    return SizedBox(
      width: shown.isEmpty ? 0 : (shown.length * 26 + 8).toDouble(),
      height: 34,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              right: (i * 26).toDouble(),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: Image.network('$base${shown[i]['image']}',
                    width: 34, height: 34, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        Container(width: 34, height: 34, color: const Color(0xFFE3E3E3))),
              ),
            ),
        ],
      ),
    );
  }

  Widget _shareCard(Map d) => Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
        padding: const EdgeInsets.all(15),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_gar ? 'ادعُ ناسك 🔗' : 'Invite your people 🔗',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
          const SizedBox(height: 10),
          Center(
            child: Column(children: [
              Text(_gar ? 'رمز اللمّة' : 'Lamma code', style: const TextStyle(color: _gMuted, fontSize: 12)),
              Text('${d['code']}',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 26, letterSpacing: 4)),
            ]),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: _smallBtn('💬 ${_gar ? 'مشا​ركة' : 'Share'}', const Color(0xFF25D366), Colors.white, () {
                final url = d['share_url'] ?? '';
                Share.share(_gar
                    ? '🧺 انضم للمّتي على يلو! كل ما نضيف أكثر نوفّر أكثر 👇\n$url'
                    : '🧺 Join my Lamma on Uellow — the more we add, the more we save 👇\n$url');
              }),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: _smallBtn('🔗 ${_gar ? 'نسخ الرابط' : 'Copy link'}', Colors.white, _gInk, () {
                Clipboard.setData(ClipboardData(text: (d['share_url'] ?? '').toString()));
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(_gar ? 'نُسخ الرابط ✅' : 'Link copied ✅')));
              }, border: true),
            ),
          ]),
        ]),
      );

  Widget _actionBar(Map d) {
    final me = d['me'] as Map?;
    final state = d['state'] ?? 'open';
    final isHost = me?['is_host'] == true;
    if (state == 'open') {
      // Pay is only offered AFTER the host locks — otherwise a member could
      // check out an early share while others are still adding (which would
      // change everyone's combined discount).
      if (isHost) {
        return _bottomBar([
          Expanded(flex: 2, child: _bigBtn(_gar ? '➕ أضِف منتجاتي' : '➕ Add my items', _gradO, _addMine)),
          const SizedBox(width: 9),
          Expanded(child: _bigBtn(_gar ? 'إتمام' : 'Lock', _gradDark, _lock)),
        ]);
      }
      return _bottomBar([
        Expanded(child: _bigBtn(_gar ? '➕ أضِف منتجاتي' : '➕ Add my items', _gradO, _addMine)),
      ]);
    }
    if (state == 'locked') {
      final paid = me?['paid'] == true;
      return _bottomBar([
        Expanded(
          child: paid
              ? _bigBtn(_gar ? '✔ دفعت نصيبك' : '✔ Paid', _gradGhost, null)
              : _bigBtn('${_gar ? 'ادفع نصيبي' : 'Pay'} · ${_m(me?['pays'])} ${_cur()}', _gradY, _pay),
        ),
      ]);
    }
    return _bottomBar([
      Expanded(child: _bigBtn(_gar ? 'ابدأ لمّة جديدة 🧺' : 'Start a new Lamma 🧺', _gradY,
          () => Navigator.pop(context))),
    ]);
  }

  // ---- actions ----
  Future<void> _addMine() async {
    final items = _myLammaItems();
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_gar ? 'أضِف منتجات للمّتك من المتجر أولًا' : 'Add items from the shop first')));
      return;
    }
    setState(() => _busy = true);
    Map<String, dynamic> d = _d ?? {};
    for (final it in items) {
      final id = (it['id'] as num?)?.toInt();
      if (id == null) continue;
      d = await _api.add(widget.code, id, variantId: (it['variant_id'] as num?)?.toInt());
    }
    if (!mounted) return;
    setState(() { _busy = false; if (d['error'] == null) _d = d; });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_gar ? 'أُضيفت منتجاتك ✅' : 'Your items were added ✅')));
  }

  void _lock() => _run(() => _api.lock(widget.code), ok: _gar ? 'اللمّة جاهزة للدفع' : 'Ready to pay');

  Future<void> _pay() async {
    setState(() => _busy = true);
    final d = await _api.pay(widget.code);
    if (!mounted) return;
    setState(() => _busy = false);
    if (d['ok'] == true) {
      Navigator.pushNamed(context, '/cart');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(d['error'] == 'empty'
              ? (_gar ? 'أضِف منتجاتك أولًا' : 'Add your items first')
              : (_gar ? 'تعذّر الدفع' : 'Payment failed'))));
    }
  }

  // ---- shared bits ----
  static const _gradO = [_gO1, _gO2];
  static const _gradY = [_gY, _gY2];
  static const _gradDark = [_gBrown, _gBrown];
  static const _gradGhost = [Colors.white, Colors.white];

  Widget _bottomBar(List<Widget> children) => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFEEEEEE))),
        ),
        child: Row(children: children),
      );

  Widget _bigBtn(String label, List<Color> grad, VoidCallback? onTap) {
    final ghost = grad == _gradGhost;
    final dark = grad == _gradDark;
    return Opacity(
      opacity: onTap == null ? .6 : 1,
      child: InkWell(
        onTap: _busy ? null : onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 15),
          decoration: BoxDecoration(
            gradient: ghost ? null : LinearGradient(colors: grad),
            color: ghost ? Colors.white : null,
            borderRadius: BorderRadius.circular(15),
            border: ghost ? Border.all(color: const Color(0xFFE7E7E7), width: 1.6) : null,
          ),
          alignment: Alignment.center,
          child: Text(label,
              style: TextStyle(
                  fontWeight: FontWeight.w900, fontSize: 15,
                  color: dark ? _gY : (ghost ? _gInk : (grad == _gradY ? _gBrown : Colors.white)))),
        ),
      ),
    );
  }

  Widget _smallBtn(String t, Color bg, Color fg, VoidCallback onTap, {bool border = false}) =>
      InkWell(
        onTap: onTap, borderRadius: BorderRadius.circular(13),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: bg, borderRadius: BorderRadius.circular(13),
            border: border ? Border.all(color: const Color(0xFFE7E7E7), width: 1.6) : null,
          ),
          alignment: Alignment.center,
          child: Text(t, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 13)),
        ),
      );

  Widget _avatar(String name, int i, double size) => Container(
        width: size, height: size,
        decoration: BoxDecoration(
            color: _avatColors[i % _avatColors.length], shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Text(name.isEmpty ? 'ض' : name.characters.first,
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: size * .38)),
      );

  Widget _avatarRow(List members, {bool white = false}) {
    final shown = members.take(4).toList();
    return SizedBox(
      height: 42,
      child: Stack(alignment: Alignment.center, children: [
        for (var i = 0; i < shown.length; i++)
          Padding(
            padding: EdgeInsets.only(right: i * 30.0),
            child: Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: white ? Colors.white : _avatColors[i % _avatColors.length],
                shape: BoxShape.circle,
                border: Border.all(color: white ? Colors.white : Colors.transparent, width: 2),
              ),
              alignment: Alignment.center,
              child: Text((shown[i] as Map)['initial']?.toString() ?? 'ض',
                  style: TextStyle(
                      color: white ? _gO1 : Colors.white,
                      fontWeight: FontWeight.w900, fontSize: 15)),
            ),
          ),
      ]),
    );
  }

  Widget _progressCard(Map d, {bool lite = false}) => Container(
        decoration: BoxDecoration(
            color: const Color(0xFFE7FBF2), borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFC7F0DD))),
        padding: const EdgeInsets.all(14),
        child: _progressBar(d, lite: true),
      );

  Widget _progressBar(Map d, {required bool lite}) {
    final n = (d['n'] as num?)?.toInt() ?? 0;
    final nextTier = d['next_tier'] as Map?;
    final fsi = (d['free_shipping_items'] as num?)?.toInt() ?? 0;
    double pct; String label;
    if (nextTier != null) {
      final at = (nextTier['at'] as num?)?.toInt() ?? 1;
      pct = (n / at).clamp(0, 1).toDouble();
      final need = nextTier['need'];
      label = _gar
          ? 'باقي $need ${need == 1 ? 'منتج' : 'منتجات'} لخصم ${nextTier['pct']}٪'
          : '$need more for ${nextTier['pct']}% off';
      if (fsi > 0 && at >= fsi) label += _gar ? ' + شحن مجاني 🚚' : ' + free shipping 🚚';
    } else if (fsi > 0 && n < fsi) {
      pct = (n / fsi).clamp(0, 1).toDouble();
      label = _gar ? 'باقي ${fsi - n} للشحن المجاني 🚚' : '${fsi - n} more for free shipping 🚚';
    } else {
      pct = 1;
      label = (d['free_shipping'] == true)
          ? (_gar ? '🎉 خصم كامل + شحن مجاني!' : '🎉 Max discount + free shipping!')
          : (_gar ? '🎉 وصلتم لأعلى خصم!' : '🎉 Top discount reached!');
    }
    final col = lite ? const Color(0xFF0A7A58) : const Color(0xFFFFD98A);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(height: lite ? 9 : 12),
      ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: LinearProgressIndicator(
          value: pct, minHeight: 12,
          backgroundColor: lite ? const Color(0xFFEAEAEA) : const Color(0x2EFFFFFF),
          valueColor: const AlwaysStoppedAnimation(_gO1),
        ),
      ),
      const SizedBox(height: 9),
      Text('${lite ? '' : '🔥 '}$label',
          style: TextStyle(color: col, fontSize: 12, fontWeight: FontWeight.w700)),
    ]);
  }
}
