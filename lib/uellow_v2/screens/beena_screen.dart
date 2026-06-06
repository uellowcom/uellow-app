// =============================================================================
// BeenaScreen — AI chat (v2.1.79). Full website-parity overhaul:
//   • CONTEXT: opens aware of a product (productId) or section (categoryId);
//     locks onto a product when the customer selects one so Beena keeps
//     discussing THAT product.
//   • PERSISTENCE: the whole thread (text/products/extra) is saved locally and
//     restored — survives navigating away or closing the app.
//   • ARCHIVE: an archive button in the header opens the full transcript.
//   • RICH CARDS: products + every extra.* block (loyalty, order/delivery,
//     try-on, fit, cart, reviewers, location, payment…) via beena_cards.dart.
//   • PRODUCT DIALOG: tapping a product opens it in a dialog with an
//     Add-to-cart button; on add Beena is told and continues the flow.
//   • VOICE: hold the mic to record → /ai/transcribe → send; replies are
//     spoken back via /ai/tts (like the website). Tap 🔊 to replay any reply.
//   • IMAGE: send a photo → visual product search (/ai/visual_search).
// =============================================================================
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../api/uellow_api.dart';
import '../router/uellow_router.dart';
import '../theme/uellow_theme.dart';
import '../widgets/beena_cards.dart';
import '../widgets/uellow_bottom_nav.dart';

const _kThreadKey = 'beena_thread_v2';

class BeenaScreen extends StatefulWidget {
  const BeenaScreen({super.key, this.productId, this.categoryId});
  /// Product the customer was viewing when they opened Beena (locks context).
  final int? productId;
  /// Category/section the customer was browsing.
  final int? categoryId;
  @override
  State<BeenaScreen> createState() => _BeenaScreenState();
}

class _BeenaScreenState extends State<BeenaScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final _rec = AudioRecorder();
  final _player = AudioPlayer();
  bool _typing = false;
  bool _recording = false;
  bool _restored = false;
  int? _activeProductId;       // the product the conversation is locked onto
  late final List<_Msg> _msgs;

  bool get _ar => UellowApi.instance.lang.toLowerCase().startsWith('ar');

  @override
  void initState() {
    super.initState();
    _activeProductId = widget.productId;
    _msgs = [];
    _restore();
  }

  @override
  void dispose() {
    _rec.dispose();
    _player.dispose();
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ── persistence ──────────────────────────────────────────────────────────
  Future<void> _restore() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_kThreadKey);
      if (raw != null && raw.isNotEmpty) {
        final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        _msgs.addAll(list.map(_Msg.fromJson));
      }
    } catch (_) {}
    if (_msgs.isEmpty) {
      _msgs.add(_Msg(isUser: false, text: _ar
          ? 'أهلاً! أنا بينا، مساعدتك الذكية من يلو 🐝\nأقدر أساعدك تلاقي منتجات، تتبع طلباتك، تستخدم نقاطك، تجرّب اللبس، أو أجاوب على أي سؤال.'
          : "Hi! I'm Beena, your Uellow AI assistant 🐝\nI can help you find products, track orders, use your points, try things on, or answer anything."));
    }
    if (mounted) setState(() => _restored = true);
    // If opened from a product page, greet about it.
    if (widget.productId != null && _msgs.length <= 1) {
      _send(_ar ? 'حدثني عن هذا المنتج' : 'Tell me about this product',
          silentUser: false);
    }
    _scrollToEnd();
  }

  Future<void> _persist() async {
    try {
      final sp = await SharedPreferences.getInstance();
      // cap stored thread to last 120 messages
      final tail = _msgs.length > 120 ? _msgs.sublist(_msgs.length - 120) : _msgs;
      await sp.setString(_kThreadKey,
          jsonEncode(tail.map((m) => m.toJson()).toList()));
    } catch (_) {}
  }

  Future<void> _clearThread() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_kThreadKey);
    } catch (_) {}
    setState(() {
      _msgs
        ..clear()
        ..add(_Msg(isUser: false, text: _ar
            ? 'بدأنا محادثة جديدة 🐝 كيف أقدر أساعدك؟'
            : "Fresh start 🐝 how can I help?"));
      _activeProductId = widget.productId;
    });
    _persist();
  }

  List<Map<String, dynamic>> _historyPayload() {
    final turns = _msgs.skip(1).where((m) => m.text.isNotEmpty).toList();
    final tail = turns.length > 8 ? turns.sublist(turns.length - 8) : turns;
    return [
      for (final m in tail)
        {'role': m.isUser ? 'user' : 'assistant', 'content': m.text},
    ];
  }

  // ── send a message ───────────────────────────────────────────────────────
  Future<void> _send(String? override, {bool speakReply = false,
      bool silentUser = false}) async {
    final text = (override ?? _ctrl.text).trim();
    if (text.isEmpty || _typing) return;
    setState(() {
      if (!silentUser) _msgs.add(_Msg(isUser: true, text: text));
      _ctrl.clear();
      _typing = true;
    });
    _persist();
    _scrollToEnd();
    try {
      final res = await UellowApi.instance.beena.chat(
          message: text, history: _historyPayload(),
          productId: _activeProductId, categoryId: widget.categoryId);
      final reply = (res['reply'] ?? res['text'] ?? '').toString();
      final extra = (res['extra'] as Map?)?.cast<String, dynamic>() ?? {};
      final products = ((extra['products'] as List?) ?? const [])
          .whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
      if (!mounted) return;
      final msg = _Msg(isUser: false,
          text: reply.isEmpty ? (_ar ? 'تم!' : 'Got it!') : reply,
          products: products.isEmpty ? null : products,
          extra: extra.isEmpty ? null : extra);
      setState(() { _msgs.add(msg); _typing = false; });
      _persist();
      if (speakReply) _speak(msg.text);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _msgs.add(_Msg(isUser: false, isError: true, retryText: text,
            text: _ar
                ? 'بينا مشغولة قليلاً الآن 🙏 اضغط «إعادة المحاولة» أو جرّب بعد لحظات.'
                : 'Beena is a bit busy right now 🙏 tap "Retry" or try again shortly.'));
        _typing = false;
      });
      _persist();
    }
    _scrollToEnd();
  }

  // ── voice: record → transcribe → send → speak reply ──────────────────────
  Future<void> _toggleRecord() async {
    if (_recording) {
      String? path;
      try { path = await _rec.stop(); } catch (_) {}
      setState(() => _recording = false);
      if (path == null) return;
      setState(() => _typing = true);
      try {
        final bytes = await File(path).readAsBytes();
        final b64 = base64Encode(bytes);
        final r = await http.post(
          Uri.parse('${UellowApi.instance.baseUrl}/ai/transcribe'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'jsonrpc': '2.0', 'params': {
            'audio': b64, 'mimetype': 'audio/m4a',
            'lang': UellowApi.instance.lang,
          }}),
        ).timeout(const Duration(seconds: 60));
        final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
        final result = (j['result'] as Map?)?.cast<String, dynamic>() ?? {};
        final txt = (result['text'] ?? '').toString().trim();
        if (!mounted) return;
        setState(() => _typing = false);
        if (txt.isEmpty) {
          _snack(_ar ? 'لم أسمع بوضوح، حاول مرة أخرى 🎙' : "Didn't catch that, try again 🎙");
          return;
        }
        _send(txt, speakReply: true);   // voice in → voice out
      } catch (_) {
        if (mounted) setState(() => _typing = false);
        _snack(_ar ? 'تعذّر تحويل الصوت' : 'Could not transcribe');
      }
    } else {
      if (!await _rec.hasPermission()) {
        _snack(_ar ? 'فعّل إذن الميكروفون' : 'Enable microphone permission');
        return;
      }
      try {
        final dir = await getTemporaryDirectory();
        final p = '${dir.path}/beena_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _rec.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: p);
        setState(() => _recording = true);
      } catch (_) {
        _snack(_ar ? 'تعذّر بدء التسجيل' : 'Could not start recording');
      }
    }
  }

  Future<void> _speak(String text) async {
    if (text.trim().isEmpty) return;
    try {
      final r = await http.post(
        Uri.parse('${UellowApi.instance.baseUrl}/ai/tts'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'jsonrpc': '2.0', 'params': {
          'text': text, 'lang': UellowApi.instance.lang,
        }}),
      ).timeout(const Duration(seconds: 40));
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      final result = (j['result'] as Map?)?.cast<String, dynamic>() ?? {};
      final audio = (result['audio'] ?? '').toString();
      if (result['success'] == true && audio.isNotEmpty) {
        await _player.stop();
        await _player.play(BytesSource(base64Decode(audio)));
      }
    } catch (_) {}
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m), behavior: SnackBarBehavior.floating));
  }

  // ── product dialog → add to cart → Beena continues ───────────────────────
  void _openProduct(Map<String, dynamic> p) {
    final id = (p['id'] as num?)?.toInt() ?? 0;
    if (id <= 0) return;
    _activeProductId = id;          // lock conversation onto this product
    showBeenaProductDialog(context, p, ar: _ar,
      onView: () { Navigator.pop(context); UellowRouter.goProduct(context, id); },
      onAdded: (name) {
        _activeProductId = id;
        _send(_ar ? 'أضفت «$name» إلى سلتي، وش الخطوة الجاية؟'
                  : 'I added "$name" to my cart — what next?');
      });
  }

  // ── photo → visual search ────────────────────────────────────────────────
  Future<void> _pickPhoto() async {
    final ar = _ar;
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (c) => SafeArea(child: Wrap(children: [
        ListTile(leading: const Icon(Icons.photo_camera_outlined),
          title: Text(ar ? 'التقط صورة' : 'Take a photo'),
          onTap: () => Navigator.pop(c, ImageSource.camera)),
        ListTile(leading: const Icon(Icons.photo_library_outlined),
          title: Text(ar ? 'من المعرض' : 'From gallery'),
          onTap: () => Navigator.pop(c, ImageSource.gallery)),
      ])),
    );
    if (src == null) return;
    final picked = await ImagePicker().pickImage(
        source: src, maxWidth: 1024, maxHeight: 1024, imageQuality: 75);
    if (picked == null || !mounted) return;
    setState(() {
      _msgs.add(_Msg(isUser: true,
          text: ar ? '📸 صورة للبحث المرئي' : '📸 Visual search photo',
          localImagePath: picked.path));
      _typing = true;
    });
    _persist();
    _scrollToEnd();
    try {
      final b64 = base64Encode(await File(picked.path).readAsBytes());
      final r = await http.post(
        Uri.parse('${UellowApi.instance.baseUrl}/ai/visual_search'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'jsonrpc': '2.0', 'params': {
          'image_base64': b64, 'lang': UellowApi.instance.lang,
        }}),
      ).timeout(const Duration(seconds: 70));
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      final result = (j['result'] as Map?)?.cast<String, dynamic>() ?? {};
      final reply = (result['reply'] ?? '').toString();
      final vExtra = (result['extra'] as Map?)?.cast<String, dynamic>() ?? {};
      final products = ((result['products'] as List?) ?? (vExtra['products'] as List?)
              ?? const [])
          .whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
      if (!mounted) return;
      setState(() {
        _msgs.add(_Msg(isUser: false,
            text: reply.isNotEmpty ? reply
                : (ar ? 'هذا ما وجدته مشابهاً لصورتك:' : 'Here is what I found:'),
            products: products.isEmpty ? null : products,
            extra: vExtra.isEmpty ? null : vExtra));
        _typing = false;
      });
      _persist();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _msgs.add(_Msg(isUser: false, isError: true, text: ar
            ? 'تعذر تحليل الصورة الآن — جرّب وصفها لي كتابةً 📝'
            : 'Could not analyze the photo — try describing it instead 📝'));
        _typing = false;
      });
      _persist();
    }
    _scrollToEnd();
  }

  void _onChip(String label) {
    if (label.contains('📸')) { _pickPhoto(); return; }
    final clean = label.replaceFirst(RegExp(r'^[^\w؀-ۿ]+\s*'), '').trim();
    _send(clean.isEmpty ? label : clean);
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  void _openArchive() {
    Navigator.push(context, MaterialPageRoute(builder: (_) =>
        _ArchiveScreen(msgs: List.of(_msgs), ar: _ar, onClear: _clearThread)));
  }

  @override
  Widget build(BuildContext context) {
    final ar = _ar;
    return Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: const Color(0xFFFAFAFA),
        bottomNavigationBar: const UellowBottomNav(active: UNavTab.beena),
        body: SafeArea(child: Column(children: [
          _Header(ar: ar, onArchive: _openArchive),
          _ChipsBar(ar: ar, onTap: _onChip),
          Expanded(child: !_restored
              ? const Center(child: CircularProgressIndicator(
                  color: UellowColors.darkBrown))
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                  itemCount: _msgs.length + (_typing ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (_typing && i == _msgs.length) return const _TypingBubble();
                    return _MsgBubble(msg: _msgs[i], ar: ar,
                        onRetry: (t) => _send(t), onSend: (t) => _send(t),
                        onProduct: _openProduct, onSpeak: _speak);
                  },
                )),
          _InputBar(ctrl: _ctrl, ar: ar, recording: _recording,
              onSend: () => _send(null), onPhoto: _pickPhoto, onMic: _toggleRecord),
        ])),
      ),
    );
  }
}

// ── message model (serializable) ─────────────────────────────────────────────
class _Msg {
  _Msg({required this.isUser, required this.text, this.products, this.extra,
      this.isError = false, this.retryText, this.localImagePath});
  final bool isUser;
  final String text;
  final List<Map<String, dynamic>>? products;
  final Map<String, dynamic>? extra;
  final bool isError;
  final String? retryText;
  final String? localImagePath;

  Map<String, dynamic> toJson() => {
        'u': isUser, 't': text,
        if (products != null) 'p': products,
        if (extra != null) 'e': extra,
        if (localImagePath != null) 'img': localImagePath,
      };
  static _Msg fromJson(Map<String, dynamic> j) => _Msg(
        isUser: j['u'] == true,
        text: (j['t'] ?? '').toString(),
        products: (j['p'] as List?)?.whereType<Map>()
            .map((m) => m.cast<String, dynamic>()).toList(),
        extra: (j['e'] as Map?)?.cast<String, dynamic>(),
        localImagePath: j['img'] as String?,
      );
}

class _Header extends StatelessWidget {
  const _Header({required this.ar, required this.onArchive});
  final bool ar;
  final VoidCallback onArchive;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 14, 12, 16),
      decoration: const BoxDecoration(gradient: UellowColors.heroWallet),
      child: Row(children: [
        IconButton(
          onPressed: () => Navigator.canPop(context)
              ? Navigator.pop(context)
              : Navigator.pushReplacementNamed(context, '/home'),
          icon: const Icon(Icons.arrow_back, color: UellowColors.yellowLight),
          padding: EdgeInsets.zero, constraints: const BoxConstraints(),
        ),
        const SizedBox(width: 4),
        Container(
          width: 44, height: 44,
          decoration: const BoxDecoration(shape: BoxShape.circle,
            gradient: RadialGradient(center: Alignment(-0.4, -0.5),
              colors: [Color(0xFFFFE45E), UellowColors.yellow, Color(0xFFC99000)]),
            boxShadow: [BoxShadow(color: Color(0x80F5C320), blurRadius: 12, offset: Offset(0, 4))]),
          alignment: Alignment.center,
          child: const Text('✨', style: TextStyle(fontSize: 20)),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(ar ? 'بينا الذكية' : 'Beena AI', style: const TextStyle(
              color: UellowColors.yellowLight, fontSize: 16, fontWeight: FontWeight.w800)),
          Text(ar ? '🟢 متصلة الآن · مدعومة من يلو' : '🟢 online · powered by Uellow',
              style: const TextStyle(color: Color(0x99FFD340), fontSize: 11)),
        ])),
        IconButton(
          onPressed: onArchive,
          tooltip: ar ? 'أرشيف المحادثة' : 'Conversation archive',
          icon: const Icon(Icons.inventory_2_outlined,
              color: UellowColors.yellowLight, size: 22),
        ),
      ]),
    );
  }
}

class _ChipsBar extends StatelessWidget {
  const _ChipsBar({required this.ar, required this.onTap});
  final bool ar;
  final ValueChanged<String> onTap;
  static const _chipsEn = ['📸 Visual search', '📦 Track my order',
      '🎁 Use my points', '💬 Ask a question', '🎂 Gift ideas'];
  static const _chipsAr = ['📸 بحث بالصورة', '📦 تتبع طلبي',
      '🎁 استخدم نقاطي', '💬 اسأل سؤالاً', '🎂 أفكار هدايا'];
  @override
  Widget build(BuildContext context) {
    final chips = ar ? _chipsAr : _chipsEn;
    return Container(
      decoration: const BoxDecoration(color: Colors.white,
        border: Border(bottom: BorderSide(color: UellowColors.border))),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: SizedBox(height: 32, child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) => GestureDetector(
          onTap: () => onTap(chips[i]),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(color: UellowColors.yellowSoft,
              border: Border.all(color: UellowColors.warnBg),
              borderRadius: BorderRadius.circular(999)),
            alignment: Alignment.center,
            child: Text(chips[i], style: const TextStyle(
                color: UellowColors.darkBrown, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ),
      )),
    );
  }
}

class _MsgBubble extends StatelessWidget {
  const _MsgBubble({required this.msg, required this.ar, this.onRetry,
      this.onSend, this.onProduct, this.onSpeak});
  final _Msg msg;
  final bool ar;
  final ValueChanged<String>? onRetry;
  final ValueChanged<String>? onSend;
  final void Function(Map<String, dynamic>)? onProduct;
  final ValueChanged<String>? onSpeak;
  @override
  Widget build(BuildContext context) {
    final rich = msg.products != null || msg.extra != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: msg.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!msg.isUser) _avatar(),
          if (!msg.isUser) const SizedBox(width: 10),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width *
                (rich ? 0.86 : 0.78)),
            child: Column(
              crossAxisAlignment: msg.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: msg.isUser ? UellowColors.darkBrown
                        : msg.isError ? const Color(0xFFFFF6F5) : Colors.white,
                    border: msg.isError ? Border.all(color: const Color(0xFFFFD2CC)) : null,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: msg.isUser ? null
                        : [const BoxShadow(color: Color(0x0D000000), blurRadius: 4)],
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (msg.localImagePath != null &&
                        File(msg.localImagePath!).existsSync()) Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: ClipRRect(borderRadius: BorderRadius.circular(10),
                        child: Image.file(File(msg.localImagePath!),
                            width: 140, height: 140, fit: BoxFit.cover)),
                    ),
                    Text(msg.text, style: TextStyle(
                      color: msg.isUser ? UellowColors.yellowLight
                          : msg.isError ? const Color(0xFF9A3324) : UellowColors.ink,
                      fontSize: 13.5, height: 1.5)),
                    if (!msg.isUser && !msg.isError && msg.text.isNotEmpty)
                      GestureDetector(
                        onTap: () => onSpeak?.call(msg.text),
                        child: Padding(padding: const EdgeInsets.only(top: 6),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.volume_up_outlined, size: 14,
                                color: UellowColors.muted),
                            const SizedBox(width: 4),
                            Text(ar ? 'استمع' : 'Listen', style: const TextStyle(
                                fontSize: 10.5, color: UellowColors.muted,
                                fontWeight: FontWeight.w700)),
                          ])),
                      ),
                  ]),
                ),
                if (msg.isError && msg.retryText != null) Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: ActionChip(
                    onPressed: () => onRetry?.call(msg.retryText!),
                    avatar: const Icon(Icons.refresh, size: 14, color: UellowColors.darkBrown),
                    label: Text(ar ? 'إعادة المحاولة' : 'Retry', style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w800, color: UellowColors.darkBrown)),
                    backgroundColor: UellowColors.yellowSoft,
                    side: const BorderSide(color: UellowColors.warnBg),
                  ),
                ),
                if (msg.products != null)
                  _ProductsRail(products: msg.products!, ar: ar, onProduct: onProduct),
                ...buildBeenaCards(context, msg.extra, ar, (t) => onSend?.call(t)),
              ],
            ),
          ),
          if (msg.isUser) const SizedBox(width: 10),
          if (msg.isUser) _userAvatar(),
        ],
      ),
    );
  }

  Widget _avatar() => Container(width: 28, height: 28,
    decoration: const BoxDecoration(color: UellowColors.yellowLight, shape: BoxShape.circle),
    alignment: Alignment.center,
    child: const Text('B', style: TextStyle(color: UellowColors.darkBrown,
        fontWeight: FontWeight.w800, fontSize: 12)));
  Widget _userAvatar() => Container(width: 28, height: 28,
    decoration: const BoxDecoration(color: UellowColors.darkBrown, shape: BoxShape.circle),
    alignment: Alignment.center,
    child: const Icon(Icons.person, size: 15, color: UellowColors.yellowLight));
}

// ─── product cards inside chat — equal height, button bottom-aligned ─────────
class _ProductsRail extends StatelessWidget {
  const _ProductsRail({required this.products, required this.ar, this.onProduct});
  final List<Map<String, dynamic>> products;
  final bool ar;
  final void Function(Map<String, dynamic>)? onProduct;

  String _name(Map<String, dynamic> p) {
    final n = p['name'];
    if (n is Map) {
      return (n[ar ? 'ar' : 'en'] ?? n['en_US'] ?? n.values.first ?? '').toString();
    }
    return (n ?? '').toString();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SizedBox(height: 196, child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: products.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final p = products[i];
          var img = (p['image_url'] ?? p['image'] ?? '').toString();
          if (img.startsWith('/')) img = '${UellowApi.instance.baseUrl}$img';
          final price = (p['price'] as num?)?.toDouble() ?? 0;
          final inStock = p['in_stock'] != false;
          return GestureDetector(
            onTap: () => onProduct?.call(p),
            child: Container(
              width: 134,
              decoration: BoxDecoration(color: Colors.white,
                border: Border.all(color: UellowColors.border),
                borderRadius: BorderRadius.circular(12)),
              clipBehavior: Clip.antiAlias,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(height: 96, width: double.infinity, child: CachedNetworkImage(
                    imageUrl: img, fit: BoxFit.cover,
                    placeholder: (_, __) => const ColoredBox(color: Color(0xFFF4F4F4)),
                    errorWidget: (_, __, ___) => const ColoredBox(color: Color(0xFFF4F4F4),
                        child: Icon(Icons.image_outlined, color: UellowColors.muted)))),
                Expanded(child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // fixed 2-line height so the price+button align across cards
                    SizedBox(height: 28, child: Text(_name(p), maxLines: 2,
                        overflow: TextOverflow.ellipsis, style: const TextStyle(
                            fontSize: 10.5, height: 1.3, fontWeight: FontWeight.w700,
                            color: UellowColors.ink))),
                    const SizedBox(height: 4),
                    Row(children: [
                      Expanded(child: Text(
                          '${price.toStringAsFixed(3)} ${ar ? 'د.ك' : 'KD'}',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5,
                              fontWeight: FontWeight.w900, color: UellowColors.darkBrown))),
                      if (!inStock) Text(ar ? 'نفد' : 'OUT', style: const TextStyle(
                          fontSize: 8.5, fontWeight: FontWeight.w900, color: UellowColors.danger)),
                    ]),
                    const Spacer(),
                    Container(width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      decoration: const BoxDecoration(color: UellowColors.yellowLight,
                        borderRadius: BorderRadius.all(Radius.circular(6))),
                      alignment: Alignment.center,
                      child: Text(ar ? 'عرض المنتج' : 'View', style: const TextStyle(
                          color: UellowColors.darkBrown, fontSize: 10,
                          fontWeight: FontWeight.w800))),
                  ]),
                )),
              ]),
            ),
          );
        },
      )),
    );
  }
}

class _TypingBubble extends StatefulWidget {
  const _TypingBubble();
  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(children: [
      Container(width: 28, height: 28,
        decoration: const BoxDecoration(color: UellowColors.yellowLight, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: const Text('B', style: TextStyle(color: UellowColors.darkBrown,
            fontWeight: FontWeight.w800, fontSize: 12))),
      const SizedBox(width: 10),
      Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: const BoxDecoration(color: Colors.white,
          borderRadius: BorderRadius.all(Radius.circular(16)),
          boxShadow: [BoxShadow(color: Color(0x0D000000), blurRadius: 4)]),
        child: AnimatedBuilder(animation: _ctrl,
          builder: (_, __) => Row(mainAxisSize: MainAxisSize.min, children: List.generate(3, (i) {
            final t = (_ctrl.value + i * 0.2) % 1;
            return Padding(padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: Container(width: 6, height: 6, decoration: BoxDecoration(
                  color: Color.lerp(const Color(0xFFCCCCCC), UellowColors.muted, t)!,
                  shape: BoxShape.circle)));
          }))),
      ),
    ]));
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({required this.ctrl, required this.ar, required this.recording,
      required this.onSend, required this.onPhoto, required this.onMic});
  final TextEditingController ctrl;
  final bool ar;
  final bool recording;
  final VoidCallback onSend, onPhoto, onMic;
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: Colors.white,
        border: Border(top: BorderSide(color: UellowColors.border))),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (recording) Padding(padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            const _RecDot(),
            const SizedBox(width: 8),
            Text(ar ? 'جارٍ التسجيل… اضغط الميكروفون للإرسال'
                    : 'Recording… tap mic to send',
                style: const TextStyle(fontSize: 12, color: UellowColors.danger,
                    fontWeight: FontWeight.w700)),
          ])),
        Row(children: [
          _iconBtn(Icons.camera_alt_outlined, onPhoto),
          const SizedBox(width: 6),
          _iconBtn(recording ? Icons.stop : Icons.mic_none_outlined, onMic,
              primary: recording, danger: recording),
          const SizedBox(width: 6),
          Expanded(child: TextField(
            controller: ctrl,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => onSend(),
            decoration: InputDecoration(
              hintText: ar ? 'اكتبي رسالتك…' : 'Type your message…',
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(18)),
                borderSide: BorderSide(color: UellowColors.border, width: 1)),
              enabledBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(18)),
                borderSide: BorderSide(color: UellowColors.border, width: 1)),
              focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(18)),
                borderSide: BorderSide(color: UellowColors.yellow, width: 1.5)),
              fillColor: Colors.white, filled: true,
            ),
          )),
          const SizedBox(width: 6),
          _iconBtn(Icons.send, onSend, primary: true),
        ]),
      ])),
    );
  }
  Widget _iconBtn(IconData icon, VoidCallback onTap, {bool primary = false, bool danger = false}) {
    return GestureDetector(onTap: onTap, child: Container(
      width: 42, height: 42,
      decoration: BoxDecoration(
        color: danger ? UellowColors.danger
            : primary ? UellowColors.yellowLight : Colors.white,
        border: (primary || danger) ? null : Border.all(color: UellowColors.border, width: 1),
        borderRadius: BorderRadius.circular(12)),
      child: Icon(icon, size: 18, color: danger ? Colors.white
          : primary ? UellowColors.darkBrown : UellowColors.text)));
  }
}

class _RecDot extends StatefulWidget {
  const _RecDot();
  @override
  State<_RecDot> createState() => _RecDotState();
}
class _RecDotState extends State<_RecDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 700))..repeat(reverse: true);
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => FadeTransition(opacity: _c,
      child: Container(width: 10, height: 10, decoration: const BoxDecoration(
          color: UellowColors.danger, shape: BoxShape.circle)));
}

// ─── Archive: full transcript ────────────────────────────────────────────────
class _ArchiveScreen extends StatelessWidget {
  const _ArchiveScreen({required this.msgs, required this.ar, required this.onClear});
  final List<_Msg> msgs;
  final bool ar;
  final Future<void> Function() onClear;
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: const Color(0xFFFAFAFA),
        appBar: AppBar(
          backgroundColor: Colors.white,
          leading: const BackButton(color: UellowColors.darkBrown),
          title: Text(ar ? 'أرشيف المحادثة' : 'Conversation archive',
              style: const TextStyle(color: UellowColors.ink,
                  fontWeight: FontWeight.w900, fontSize: 16)),
          actions: [
            TextButton.icon(
              onPressed: () async {
                final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
                  title: Text(ar ? 'مسح المحادثة؟' : 'Clear conversation?'),
                  content: Text(ar ? 'سيتم حذف كامل سجل المحادثة.' : 'This deletes the whole history.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c, false),
                        child: Text(ar ? 'إلغاء' : 'Cancel')),
                    TextButton(onPressed: () => Navigator.pop(c, true),
                        child: Text(ar ? 'مسح' : 'Clear',
                            style: const TextStyle(color: UellowColors.danger))),
                  ],
                ));
                if (ok == true) { await onClear(); if (context.mounted) Navigator.pop(context); }
              },
              icon: const Icon(Icons.delete_outline, size: 18, color: UellowColors.danger),
              label: Text(ar ? 'مسح' : 'Clear',
                  style: const TextStyle(color: UellowColors.danger)),
            ),
          ],
        ),
        body: msgs.isEmpty
            ? Center(child: Text(ar ? 'لا توجد محادثات' : 'No conversation yet',
                style: const TextStyle(color: UellowColors.muted)))
            : ListView.separated(
                padding: const EdgeInsets.all(14),
                itemCount: msgs.length,
                separatorBuilder: (_, __) => const Divider(height: 16),
                itemBuilder: (_, i) {
                  final m = msgs[i];
                  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(width: 26, height: 26, alignment: Alignment.center,
                      decoration: BoxDecoration(shape: BoxShape.circle,
                          color: m.isUser ? UellowColors.darkBrown : UellowColors.yellowLight),
                      child: m.isUser
                          ? const Icon(Icons.person, size: 14, color: UellowColors.yellowLight)
                          : const Text('B', style: TextStyle(fontSize: 11,
                              fontWeight: FontWeight.w900, color: UellowColors.darkBrown))),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(m.isUser ? (ar ? 'أنت' : 'You') : 'Beena',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900,
                              color: UellowColors.muted)),
                      const SizedBox(height: 2),
                      Text(m.text, style: const TextStyle(fontSize: 13, height: 1.5,
                          color: UellowColors.ink)),
                      if (m.products != null) Padding(padding: const EdgeInsets.only(top: 4),
                        child: Text('🛍 ${m.products!.length} ${ar ? "منتج" : "products"}',
                            style: const TextStyle(fontSize: 11, color: UellowColors.muted))),
                    ])),
                  ]);
                },
              ),
      ),
    );
  }
}
