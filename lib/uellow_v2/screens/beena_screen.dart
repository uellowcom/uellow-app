// =============================================================================
// BeenaScreen — AI chat. v2.1.55 overhaul:
//   • fully bilingual + RTL (header, chips, greeting, errors)
//   • products render as REAL cards (image/name/price/view) from
//     extra.products — same knowledge as the website chat
//   • conversation HISTORY threading (context survives across turns)
//   • photo button → image picker → visual search via /ai/analyze-image
//     fallback to text describe; mic button → speech-style input sheet
//   • graceful bilingual error bubbles + retry chip
// =============================================================================
import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../api/uellow_api.dart';
import '../router/uellow_router.dart';
import '../theme/uellow_theme.dart';
import '../widgets/uellow_bottom_nav.dart';

class BeenaScreen extends StatefulWidget {
  const BeenaScreen({super.key});
  @override
  State<BeenaScreen> createState() => _BeenaScreenState();
}

class _BeenaScreenState extends State<BeenaScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  bool _typing = false;
  late final List<_Msg> _msgs;

  bool get _ar => UellowApi.instance.lang.toLowerCase().startsWith('ar');

  @override
  void initState() {
    super.initState();
    _msgs = [
      _Msg(isUser: false, text: _ar
          ? 'أهلاً! أنا بينا، مساعدتك الذكية من يلو 🐝\nأقدر أساعدك تلاقي منتجات، تتبع طلباتك، تستخدم نقاطك، أو أجاوب على أي سؤال.'
          : "Hi! I'm Beena, your Uellow AI assistant 🐝\nI can help you find products, track orders, use your points, or answer any question."),
    ];
  }

  List<Map<String, dynamic>> _historyPayload() {
    // last 8 turns, oldest→newest, skipping the greeting
    final turns = _msgs.skip(1).where((m) => m.text.isNotEmpty).toList();
    final tail = turns.length > 8 ? turns.sublist(turns.length - 8) : turns;
    return [
      for (final m in tail)
        {'role': m.isUser ? 'user' : 'assistant', 'content': m.text},
    ];
  }

  Future<void> _send([String? override]) async {
    final text = (override ?? _ctrl.text).trim();
    if (text.isEmpty || _typing) return;
    setState(() {
      _msgs.add(_Msg(isUser: true, text: text));
      _ctrl.clear();
      _typing = true;
    });
    _scrollToEnd();
    try {
      final res = await UellowApi.instance.beena.chat(
          message: text, history: _historyPayload());
      final reply = (res['reply'] ?? res['text'] ?? '').toString();
      // v2.1.55 — product cards from the AI's tool results.
      final extra = (res['extra'] as Map?)?.cast<String, dynamic>() ?? {};
      final products = ((extra['products'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => m.cast<String, dynamic>())
          .toList();
      if (!mounted) return;
      setState(() {
        _msgs.add(_Msg(
            isUser: false,
            text: reply.isEmpty
                ? (_ar ? 'تم!' : 'Got it!')
                : reply,
            products: products.isEmpty ? null : products));
        _typing = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _msgs.add(_Msg(
            isUser: false,
            isError: true,
            retryText: text,
            text: _ar
                ? 'بينا مشغولة قليلاً الآن 🙏 اضغط «إعادة المحاولة» أو جرّب بعد لحظات.'
                : 'Beena is a bit busy right now 🙏 tap "Retry" or try again shortly.'));
        _typing = false;
      });
    }
    _scrollToEnd();
  }

  // ── photo → visual search ──
  Future<void> _pickPhoto() async {
    final ar = _ar;
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (c) => SafeArea(child: Wrap(children: [
        ListTile(
          leading: const Icon(Icons.photo_camera_outlined),
          title: Text(ar ? 'التقط صورة' : 'Take a photo'),
          onTap: () => Navigator.pop(c, ImageSource.camera),
        ),
        ListTile(
          leading: const Icon(Icons.photo_library_outlined),
          title: Text(ar ? 'من المعرض' : 'From gallery'),
          onTap: () => Navigator.pop(c, ImageSource.gallery),
        ),
      ])),
    );
    if (src == null) return;
    final picked = await ImagePicker().pickImage(
        source: src, maxWidth: 1024, maxHeight: 1024, imageQuality: 75);
    if (picked == null || !mounted) return;
    setState(() {
      _msgs.add(_Msg(isUser: true,
          text: _ar ? '📸 صورة للبحث المرئي' : '📸 Visual search photo',
          localImage: File(picked.path)));
      _typing = true;
    });
    _scrollToEnd();
    try {
      final b64 = base64Encode(await File(picked.path).readAsBytes());
      final r = await http.post(
        Uri.parse('${UellowApi.instance.baseUrl}/ai/visual_search'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'jsonrpc': '2.0', 'params': {
          'image_base64': b64,
          'lang': UellowApi.instance.lang,
        }}),
      ).timeout(const Duration(seconds: 70));
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      final result = (j['result'] as Map?)?.cast<String, dynamic>() ?? {};
      final reply = (result['reply'] ?? '').toString();
      final products = ((result['products'] as List?)
              ?? ((result['extra'] as Map?)?['products'] as List?)
              ?? const [])
          .whereType<Map>()
          .map((m) => m.cast<String, dynamic>())
          .toList();
      if (!mounted) return;
      setState(() {
        _msgs.add(_Msg(isUser: false,
            text: reply.isNotEmpty
                ? reply
                : (_ar ? 'هذا ما وجدته مشابهاً لصورتك:' : 'Here is what I found:'),
            products: products.isEmpty ? null : products));
        _typing = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _msgs.add(_Msg(isUser: false, isError: true,
            text: _ar
                ? 'تعذر تحليل الصورة الآن — جرّب وصفها لي كتابةً 📝'
                : 'Could not analyze the photo — try describing it instead 📝'));
        _typing = false;
      });
    }
    _scrollToEnd();
  }

  // ── mic: dictation helper sheet (uses the keyboard's mic) ──
  void _voiceInput() {
    final ar = _ar;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (c) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 26),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
                color: UellowColors.yellowSoft, shape: BoxShape.circle),
            child: const Icon(Icons.mic, size: 28,
                color: UellowColors.darkBrown),
          ),
          const SizedBox(height: 12),
          Text(ar ? 'تحدث إلى بينا' : 'Talk to Beena',
              style: const TextStyle(fontSize: 15.5,
                  fontWeight: FontWeight.w900, color: UellowColors.ink)),
          const SizedBox(height: 6),
          Text(ar
                  ? 'اضغط على حقل الكتابة ثم اختر رمز الميكروفون 🎙 من لوحة المفاتيح — وسيتحول كلامك إلى نص تلقائياً.'
                  : 'Tap the message field, then the mic 🎙 on your keyboard — your speech becomes text automatically.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, height: 1.6,
                  color: UellowColors.muted)),
          const SizedBox(height: 14),
          SizedBox(width: double.infinity, child: ElevatedButton.icon(
            onPressed: () => Navigator.pop(c),
            icon: const Icon(Icons.keyboard, size: 16),
            label: Text(ar ? 'فهمت — افتح الكتابة' : 'Got it — start typing',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            style: ElevatedButton.styleFrom(
              backgroundColor: UellowColors.yellow,
              foregroundColor: UellowColors.darkBrown,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          )),
        ]),
      ),
    );
  }

  void _onChip(String label) {
    final clean = label.replaceFirst(RegExp(r'^[^\w؀-ۿ]+\s*'), '').trim();
    if (label.contains('📸')) { _pickPhoto(); return; }
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

  @override
  Widget build(BuildContext context) {
    final ar = _ar;
    return Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: const Color(0xFFFAFAFA),
          bottomNavigationBar: const UellowBottomNav(active: UNavTab.beena),
        body: SafeArea(child: Column(children: [
          _Header(ar: ar),
          _ChipsBar(ar: ar, onTap: _onChip),
          Expanded(child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            itemCount: _msgs.length + (_typing ? 1 : 0),
            itemBuilder: (_, i) {
              if (_typing && i == _msgs.length) return const _TypingBubble();
              return _MsgBubble(msg: _msgs[i], ar: ar,
                  onRetry: (t) => _send(t));
            },
          )),
          _InputBar(ctrl: _ctrl, ar: ar,
              onSend: _send, onPhoto: _pickPhoto, onMic: _voiceInput),
        ])),
      ),
    );
  }
}

class _Msg {
  _Msg({required this.isUser, required this.text, this.products,
      this.isError = false, this.retryText, this.localImage});
  final bool isUser;
  final String text;
  final List<Map<String, dynamic>>? products;
  final bool isError;
  final String? retryText;
  final File? localImage;
}

class _Header extends StatelessWidget {
  const _Header({required this.ar});
  final bool ar;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 18, 16),
      decoration: const BoxDecoration(gradient: UellowColors.heroWallet),
      child: Row(children: [
        IconButton(
          onPressed: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              Navigator.pushReplacementNamed(context, '/home');
            }
          },
          icon: const Icon(Icons.arrow_back,   // auto-mirrors under RTL
              color: UellowColors.yellowLight),
          padding: EdgeInsets.zero, constraints: const BoxConstraints(),
        ),
        const SizedBox(width: 8),
        Container(
          width: 48, height: 48,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              center: Alignment(-0.4, -0.5),
              colors: [Color(0xFFFFE45E), UellowColors.yellow, Color(0xFFC99000)],
            ),
            boxShadow: [BoxShadow(color: Color(0x80F5C320), blurRadius: 12, offset: Offset(0, 4))],
          ),
          alignment: Alignment.center,
          child: const Text('✨', style: TextStyle(fontSize: 22)),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(ar ? 'بينا الذكية' : 'Beena AI', style: const TextStyle(
              color: UellowColors.yellowLight, fontSize: 17, fontWeight: FontWeight.w800)),
          Text(ar ? '🟢 متصلة الآن · مدعومة من يلو'
                  : '🟢 online · powered by Uellow',
              style: const TextStyle(color: Color(0x99FFD340), fontSize: 12)),
        ])),
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
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: UellowColors.border)),
      ),
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
            decoration: BoxDecoration(
              color: UellowColors.yellowSoft,
              border: Border.all(color: UellowColors.warnBg),
              borderRadius: BorderRadius.circular(999),
            ),
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
  const _MsgBubble({required this.msg, required this.ar, this.onRetry});
  final _Msg msg;
  final bool ar;
  final ValueChanged<String>? onRetry;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: msg.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!msg.isUser) _avatar(),
          if (!msg.isUser) const SizedBox(width: 10),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
            child: Column(
              crossAxisAlignment: msg.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: msg.isUser
                        ? UellowColors.darkBrown
                        : msg.isError ? const Color(0xFFFFF6F5) : Colors.white,
                    border: msg.isError
                        ? Border.all(color: const Color(0xFFFFD2CC)) : null,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: msg.isUser ? null
                        : [const BoxShadow(color: Color(0x0D000000), blurRadius: 4)],
                  ),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    if (msg.localImage != null) Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(msg.localImage!,
                            width: 140, height: 140, fit: BoxFit.cover),
                      ),
                    ),
                    Text(msg.text, style: TextStyle(
                      color: msg.isUser
                          ? UellowColors.yellowLight
                          : msg.isError
                              ? const Color(0xFF9A3324) : UellowColors.ink,
                      fontSize: 13.5, height: 1.5,
                    )),
                  ]),
                ),
                if (msg.isError && msg.retryText != null) Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: ActionChip(
                    onPressed: () => onRetry?.call(msg.retryText!),
                    avatar: const Icon(Icons.refresh, size: 14,
                        color: UellowColors.darkBrown),
                    label: Text(ar ? 'إعادة المحاولة' : 'Retry',
                        style: const TextStyle(fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: UellowColors.darkBrown)),
                    backgroundColor: UellowColors.yellowSoft,
                    side: const BorderSide(color: UellowColors.warnBg),
                  ),
                ),
                if (msg.products != null) _ProductsRail(
                    products: msg.products!, ar: ar),
              ],
            ),
          ),
          if (msg.isUser) const SizedBox(width: 10),
          if (msg.isUser) _userAvatar(),
        ],
      ),
    );
  }

  Widget _avatar() => Container(
    width: 28, height: 28,
    decoration: const BoxDecoration(
        color: UellowColors.yellowLight, shape: BoxShape.circle),
    alignment: Alignment.center,
    child: const Text('B', style: TextStyle(
        color: UellowColors.darkBrown, fontWeight: FontWeight.w800, fontSize: 12)),
  );

  Widget _userAvatar() => Container(
    width: 28, height: 28,
    decoration: const BoxDecoration(
        color: UellowColors.darkBrown, shape: BoxShape.circle),
    alignment: Alignment.center,
    child: const Icon(Icons.person, size: 15, color: UellowColors.yellowLight),
  );
}

// ─── Product cards inside the chat (v2.1.55) — like the website ─────
class _ProductsRail extends StatelessWidget {
  const _ProductsRail({required this.products, required this.ar});
  final List<Map<String, dynamic>> products;
  final bool ar;

  String _name(Map<String, dynamic> p) {
    final n = p['name'];
    if (n is Map) {
      return (n[ar ? 'ar' : 'en'] ?? n['en_US'] ?? n.values.first ?? '')
          .toString();
    }
    return (n ?? '').toString();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SizedBox(height: 188, child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: products.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final p = products[i];
          final id = (p['id'] as num?)?.toInt() ?? 0;
          var img = (p['image_url'] ?? p['image'] ?? '').toString();
          if (img.startsWith('/')) {
            img = '${UellowApi.instance.baseUrl}$img';
          }
          final price = (p['price'] as num?)?.toDouble() ?? 0;
          final inStock = p['in_stock'] != false;
          return GestureDetector(
            onTap: id > 0 ? () => UellowRouter.goProduct(context, id) : null,
            child: Container(
              width: 132,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: UellowColors.border),
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                SizedBox(height: 96, width: double.infinity,
                    child: CachedNetworkImage(
                      imageUrl: img, fit: BoxFit.cover,
                      placeholder: (_, __) =>
                          const ColoredBox(color: Color(0xFFF4F4F4)),
                      errorWidget: (_, __, ___) => const ColoredBox(
                          color: Color(0xFFF4F4F4),
                          child: Icon(Icons.image_outlined,
                              color: UellowColors.muted)),
                    )),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(_name(p), maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10.5, height: 1.3,
                            fontWeight: FontWeight.w700,
                            color: UellowColors.ink)),
                    const SizedBox(height: 4),
                    Row(children: [
                      Text(
                          '${price.toStringAsFixed(3)} '
                          '${UellowMoneyShim.symbol(ar)}',
                          style: const TextStyle(fontSize: 11.5,
                              fontWeight: FontWeight.w900,
                              color: UellowColors.darkBrown)),
                      const Spacer(),
                      if (!inStock)
                        Text(ar ? 'نفد' : 'OUT',
                            style: const TextStyle(fontSize: 8.5,
                                fontWeight: FontWeight.w900,
                                color: UellowColors.danger)),
                    ]),
                    const SizedBox(height: 5),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      decoration: const BoxDecoration(
                        color: UellowColors.yellowLight,
                        borderRadius: BorderRadius.all(Radius.circular(6)),
                      ),
                      alignment: Alignment.center,
                      child: Text(ar ? 'عرض المنتج' : 'View',
                          style: const TextStyle(
                              color: UellowColors.darkBrown, fontSize: 10,
                              fontWeight: FontWeight.w800)),
                    ),
                  ]),
                ),
              ]),
            ),
          );
        },
      )),
    );
  }
}

// Currency shim — chat product payloads carry a bare float price.
class UellowMoneyShim {
  static String symbol(bool ar) => ar ? 'د.ك' : 'KD';
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
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat();
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(children: [
      Container(
        width: 28, height: 28,
        decoration: const BoxDecoration(color: UellowColors.yellowLight, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: const Text('B', style: TextStyle(
            color: UellowColors.darkBrown, fontWeight: FontWeight.w800, fontSize: 12)),
      ),
      const SizedBox(width: 10),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.all(Radius.circular(16)),
          boxShadow: [BoxShadow(color: Color(0x0D000000), blurRadius: 4)],
        ),
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) => Row(mainAxisSize: MainAxisSize.min, children: List.generate(3, (i) {
            final t = (_ctrl.value + i * 0.2) % 1;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: Container(
                width: 6, height: 6,
                decoration: BoxDecoration(
                  color: Color.lerp(const Color(0xFFCCCCCC), UellowColors.muted, t)!,
                  shape: BoxShape.circle,
                ),
              ),
            );
          })),
        ),
      ),
    ]));
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({required this.ctrl, required this.ar,
      required this.onSend, required this.onPhoto, required this.onMic});
  final TextEditingController ctrl;
  final bool ar;
  final VoidCallback onSend, onPhoto, onMic;
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: UellowColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: SafeArea(top: false, child: Row(children: [
        _iconBtn(Icons.camera_alt_outlined, onPhoto),
        const SizedBox(width: 6),
        _iconBtn(Icons.mic_none_outlined, onMic),
        const SizedBox(width: 6),
        Expanded(child: TextField(
          controller: ctrl,
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => onSend(),
          decoration: InputDecoration(
            hintText: ar ? 'اكتبي رسالتك…' : 'Type your message…',
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            border: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(18)),
              borderSide: BorderSide(color: UellowColors.border, width: 1)),
            enabledBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(18)),
              borderSide: BorderSide(color: UellowColors.border, width: 1)),
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(18)),
              borderSide: BorderSide(color: UellowColors.yellow, width: 1.5)),
            fillColor: Colors.white, filled: true,
          ),
        )),
        const SizedBox(width: 6),
        _iconBtn(Icons.send, onSend, primary: true),
      ])),
    );
  }
  Widget _iconBtn(IconData icon, VoidCallback onTap, {bool primary = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42, height: 42,
        decoration: BoxDecoration(
          color: primary ? UellowColors.yellowLight : Colors.white,
          border: primary ? null
              : Border.all(color: UellowColors.border, width: 1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 18,
            color: primary ? UellowColors.darkBrown : UellowColors.text),
      ),
    );
  }
}
