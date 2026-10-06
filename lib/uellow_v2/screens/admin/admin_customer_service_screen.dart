// AdminCustomerServiceScreen — reply to customers live, right from the
// Admin Console. The human side of Beena: when CS mode is ON, customers'
// Beena flips to a live agent and their messages land here in real time.
//
// Fast by design: the conversation list polls unread every 6s; an open
// chat polls new messages (after=<lastId>) every 2.5s. Push notifications
// (backend) alert admins on every new customer message.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../api/uellow_api.dart';
import '../../theme/uellow_theme.dart';

const _teal = Color(0xFF2F7D72);
const _tealDark = Color(0xFF1F5A52);
const _online = Color(0xFF22C55E);

class AdminCustomerServiceScreen extends StatefulWidget {
  const AdminCustomerServiceScreen({super.key});
  @override
  State<AdminCustomerServiceScreen> createState() => _CSState();
}

class _CSState extends State<AdminCustomerServiceScreen> {
  bool get _ar => UellowApi.instance.lang.toLowerCase().startsWith('ar');
  List<Map<String, dynamic>> _rows = [];
  bool _loading = false;
  bool _csMode = false;
  int _totalUnread = 0;
  String _filter = 'all';
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 6), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final res = await UellowApi.instance.getRaw(
          '/api/mobile/v2/admin/cs/conversations',
          query: {'filter': _filter}, auth: true);
      final d = res['data'] ?? {};
      final mode = await UellowApi.instance
          .getRaw('/api/mobile/v2/admin/cs/mode', auth: true);
      if (!mounted) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(d['conversations'] ?? []);
        _totalUnread = (d['total_unread'] ?? 0) as int;
        _csMode = (mode['data']?['cs_mode'] ?? false) as bool;
      });
    } catch (_) {} finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  Future<void> _toggleMode(bool on) async {
    setState(() => _csMode = on);
    try {
      await UellowApi.instance.postRaw('/api/mobile/v2/admin/cs/mode',
          body: {'on': on}, auth: true);
    } catch (_) {}
    _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F3EC),
      appBar: AppBar(
        backgroundColor: _tealDark,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Row(children: [
          const Icon(Icons.headset_mic_rounded, size: 20),
          const SizedBox(width: 8),
          Text(_ar ? 'خدمة العملاء' : 'Customer Service',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          if (_totalUnread > 0) ...[
            const SizedBox(width: 8),
            _badge(_totalUnread),
          ],
        ]),
      ),
      body: Column(children: [
        _modeBar(),
        _filters(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            color: _tealDark,
            child: _rows.isEmpty
                ? ListView(children: [
                    const SizedBox(height: 120),
                    Icon(Icons.forum_outlined, size: 54, color: UellowColors.muted.withOpacity(.5)),
                    const SizedBox(height: 12),
                    Center(child: Text(_loading ? '…' : (_ar ? 'لا محادثات بعد' : 'No conversations yet'),
                        style: const TextStyle(color: UellowColors.muted, fontSize: 14, fontWeight: FontWeight.w700))),
                  ])
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 9),
                    itemBuilder: (_, i) => _convTile(_rows[i]),
                  ),
          ),
        ),
      ]),
    );
  }

  Widget _badge(int n) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: const Color(0xFFE11D48), borderRadius: BorderRadius.circular(999)),
        child: Text('$n', style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w900)),
      );

  Widget _modeBar() => Container(
        margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: _csMode ? const [_tealDark, _teal] : const [Color(0xFF6B6B6B), Color(0xFF8A8A8A)]),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: (_csMode ? _teal : Colors.grey).withOpacity(.35), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Row(children: [
          Icon(_csMode ? Icons.support_agent_rounded : Icons.smart_toy_rounded, color: Colors.white, size: 24),
          const SizedBox(width: 11),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_csMode ? (_ar ? 'وضع خدمة العملاء مُفعّل' : 'Live Customer Service ON')
                           : (_ar ? 'بينا (ذكاء اصطناعي)' : 'Beena (AI) mode'),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14.5)),
              Text(_csMode ? (_ar ? 'العملاء يتحدثون معكم مباشرة' : 'Customers chat with your team directly')
                           : (_ar ? 'بينا ترد آليًا على العملاء' : 'Beena replies to customers automatically'),
                  style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w600)),
            ]),
          ),
          Switch(value: _csMode, onChanged: _toggleMode,
              activeColor: Colors.white, activeTrackColor: Colors.white24,
              inactiveThumbColor: Colors.white, inactiveTrackColor: Colors.white24),
        ]),
      );

  Widget _filters() => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        child: Row(children: [
          _chip('all', _ar ? 'الكل' : 'All'),
          const SizedBox(width: 7),
          _chip('open', _ar ? 'مفتوحة' : 'Open'),
          const SizedBox(width: 7),
          _chip('unread', _ar ? 'غير مقروءة' : 'Unread'),
        ]),
      );

  Widget _chip(String key, String label) {
    final sel = _filter == key;
    return GestureDetector(
      onTap: () { setState(() => _filter = key); _load(); },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
        decoration: BoxDecoration(
          color: sel ? _tealDark : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: sel ? _tealDark : UellowColors.border),
        ),
        child: Text(label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5,
            color: sel ? Colors.white : UellowColors.darkBrown)),
      ),
    );
  }

  Widget _convTile(Map<String, dynamic> c) {
    final unread = (c['unread'] ?? 0) as int;
    final at = _fmtTime(c['at']);
    return InkWell(
      borderRadius: BorderRadius.circular(15),
      onTap: () async {
        await Navigator.push(context, MaterialPageRoute(
            builder: (_) => _ChatDetail(chat: c, ar: _ar)));
        _load(silent: true);
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: unread > 0 ? _teal.withOpacity(.4) : UellowColors.border),
          boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 6, offset: Offset(0, 2))],
        ),
        child: Row(children: [
          _avatar(c['avatar'], c['name'], 46),
          const SizedBox(width: 11),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(c['name'] ?? '',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5, color: UellowColors.darkBrown))),
                Text(at, style: const TextStyle(fontSize: 10.5, color: UellowColors.muted, fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 3),
              Row(children: [
                if (c['last_author'] == 'agent' || c['last_author'] == 'system')
                  const Padding(padding: EdgeInsets.only(left: 4),
                      child: Icon(Icons.reply_rounded, size: 13, color: UellowColors.muted)),
                Expanded(child: Text(c['preview'] ?? '',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: unread > 0 ? UellowColors.darkBrown : UellowColors.muted,
                        fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.w500))),
                if (unread > 0) ...[const SizedBox(width: 6), _badge(unread)],
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  static String _fmtTime(dynamic iso) {
    if (iso == null || iso.toString().isEmpty) return '';
    try {
      final d = DateTime.parse(iso.toString()).toLocal();
      final now = DateTime.now();
      if (d.year == now.year && d.month == now.month && d.day == now.day) {
        return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
      }
      return '${d.day}/${d.month}';
    } catch (_) { return ''; }
  }
}

Widget _avatar(dynamic url, dynamic name, double size) {
  final u = (url ?? '').toString();
  final full = u.startsWith('http') ? u : '${UellowApi.instance.baseUrl.replaceAll('/api/mobile/v2', '')}$u';
  return Container(
    width: size, height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: const LinearGradient(colors: [_teal, _tealDark]),
    ),
    clipBehavior: Clip.antiAlias,
    child: u.isEmpty
        ? Center(child: Text((name ?? '?').toString().characters.take(1).toString().toUpperCase(),
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: size * .4)))
        : Image.network(full, fit: BoxFit.cover, errorBuilder: (_, __, ___) =>
            Center(child: Text((name ?? '?').toString().characters.take(1).toString().toUpperCase(),
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: size * .4)))),
  );
}

// ═══════════════════════ CHAT DETAIL ═══════════════════════
class _ChatDetail extends StatefulWidget {
  const _ChatDetail({required this.chat, required this.ar});
  final Map<String, dynamic> chat;
  final bool ar;
  @override
  State<_ChatDetail> createState() => _ChatDetailState();
}

class _ChatDetailState extends State<_ChatDetail> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _msgs = [];
  int _lastId = 0;
  bool _sending = false;
  Timer? _poll;
  int get _chatId => (widget.chat['chat_id'] ?? 0) as int;
  bool get _ar => widget.ar;

  @override
  void initState() {
    super.initState();
    _fetch(initial: true);
    _poll = Timer.periodic(const Duration(milliseconds: 2500), (_) => _fetch());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _fetch({bool initial = false}) async {
    try {
      final res = await UellowApi.instance.getRaw('/api/mobile/v2/admin/cs/thread',
          query: {'chat_id': '$_chatId', 'after': '$_lastId'}, auth: true);
      final list = List<Map<String, dynamic>>.from(res['data']?['messages'] ?? []);
      if (list.isEmpty) return;
      if (!mounted) return;
      setState(() {
        _msgs.addAll(list);
        _lastId = _msgs.last['id'] as int;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _toBottom());
    } catch (_) {}
  }

  void _toBottom() {
    if (_scroll.hasClients) {
      _scroll.animateTo(_scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  Future<void> _reply({String? text, String? image, int? productId}) async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      final res = await UellowApi.instance.postRaw('/api/mobile/v2/admin/cs/reply',
          body: {
            'chat_id': _chatId,
            if (text != null) 'text': text,
            if (image != null) 'image': image,
            if (productId != null) 'product_id': productId,
          }, auth: true);
      final m = res['data']?['message'];
      if (m != null && mounted) {
        setState(() { _msgs.add(Map<String, dynamic>.from(m)); _lastId = _msgs.last['id'] as int; });
        WidgetsBinding.instance.addPostFrameCallback((_) => _toBottom());
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _send() async {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    _ctrl.clear();
    await _reply(text: t);
  }

  Future<void> _pickImage() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 72, maxWidth: 1400);
    if (x == null) return;
    final b64 = base64Encode(await File(x.path).readAsBytes());
    await _reply(image: b64);
  }

  Future<void> _pickProduct() async {
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => _ProductPicker(ar: _ar));
    if (picked != null) await _reply(productId: picked['id'] as int);
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.chat['name'] ?? '';
    return Scaffold(
      backgroundColor: const Color(0xFFF6F3EC),
      appBar: AppBar(
        backgroundColor: _tealDark, foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        titleSpacing: 0,
        title: Row(children: [
          _avatar(widget.chat['avatar'], name, 36),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15.5)),
            Row(children: [
              Container(width: 7, height: 7, decoration: const BoxDecoration(color: _online, shape: BoxShape.circle)),
              const SizedBox(width: 5),
              Text(_ar ? 'عميل' : 'Customer', style: const TextStyle(fontSize: 11, color: Colors.white70)),
            ]),
          ])),
        ]),
      ),
      body: Column(children: [
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
            itemCount: _msgs.length,
            itemBuilder: (_, i) => _bubble(_msgs[i]),
          ),
        ),
        _composer(),
      ]),
    );
  }

  Widget _bubble(Map<String, dynamic> m) {
    final mine = m['author'] == 'agent';
    final system = m['author'] == 'system';
    if (system) {
      return Center(child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: _teal.withOpacity(.12), borderRadius: BorderRadius.circular(999)),
        child: Text(m['body'] ?? '', style: const TextStyle(fontSize: 11.5, color: _tealDark, fontWeight: FontWeight.w700)),
      ));
    }
    final kind = m['kind'] ?? 'text';
    Widget content;
    if (kind == 'product' && m['product'] != null) {
      content = _productCard(Map<String, dynamic>.from(m['product']));
    } else if (kind == 'image' && m['media_url'] != null) {
      content = _imageBubble(m['media_url']);
    } else if (kind == 'file' && m['media_url'] != null) {
      content = _fileBubble(m);
    } else {
      content = Text(m['body'] ?? '', style: TextStyle(fontSize: 14, height: 1.5,
          color: mine ? Colors.white : UellowColors.darkBrown));
    }
    final bubbleColor = mine ? UellowColors.darkBrown : Colors.white;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .78),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: kind == 'product' ? const EdgeInsets.all(5) : const EdgeInsets.fromLTRB(13, 10, 13, 8),
        decoration: BoxDecoration(
          color: kind == 'product' ? Colors.transparent : bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16), topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 5), bottomRight: Radius.circular(mine ? 5 : 16),
          ),
          boxShadow: kind == 'product' ? null : const [BoxShadow(color: Color(0x12000000), blurRadius: 4)],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          content,
          const SizedBox(height: 3),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text(_CSState._fmtTime(m['at']), style: TextStyle(fontSize: 9.5,
                color: mine ? Colors.white60 : UellowColors.muted)),
            if (mine) ...[
              const SizedBox(width: 4),
              Icon(m['is_read'] == true ? Icons.done_all_rounded : Icons.done_rounded,
                  size: 13, color: m['is_read'] == true ? const Color(0xFF6FD3FF) : Colors.white60),
            ],
          ]),
        ]),
      ),
    );
  }

  Widget _imageBubble(String url) {
    final full = url.startsWith('http') ? url : '${UellowApi.instance.baseUrl.replaceAll('/api/mobile/v2', '')}$url';
    return ClipRRect(borderRadius: BorderRadius.circular(12),
        child: Image.network(full, width: 200, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(width: 200, height: 140, color: UellowColors.yellowSoft,
                child: const Icon(Icons.image_outlined, color: UellowColors.muted))));
  }

  Widget _fileBubble(Map<String, dynamic> m) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 38, height: 38, decoration: BoxDecoration(color: const Color(0xFFFDECEC),
            borderRadius: BorderRadius.circular(9)),
            child: const Icon(Icons.description_rounded, color: Color(0xFFD6453C), size: 20)),
        const SizedBox(width: 10),
        Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(m['file_name'] ?? 'file', maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
          Text('${((m['file_size'] ?? 0) / 1024).round()} KB',
              style: const TextStyle(fontSize: 10.5, color: UellowColors.muted)),
        ])),
      ]);

  Widget _productCard(Map<String, dynamic> p) {
    final img = (p['image'] ?? '').toString();
    final full = img.startsWith('http') ? img : '${UellowApi.instance.baseUrl.replaceAll('/api/mobile/v2', '')}$img';
    return Container(
      width: 190,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(13),
          border: Border.all(color: UellowColors.border)),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Image.network(full, height: 110, width: double.infinity, fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Container(height: 110, color: UellowColors.yellowFaint,
                child: const Icon(Icons.inventory_2_outlined, color: UellowColors.muted))),
        Padding(padding: const EdgeInsets.all(9), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(p['name'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: UellowColors.darkBrown)),
          const SizedBox(height: 4),
          Text('${p['price']} ${_ar ? 'د.ك' : 'KWD'}',
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: _tealDark)),
        ])),
      ]),
    );
  }

  Widget _composer() => SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          decoration: const BoxDecoration(color: Colors.white,
              border: Border(top: BorderSide(color: UellowColors.border))),
          child: Row(children: [
            _cBtn(Icons.image_outlined, _pickImage),
            _cBtn(Icons.shopping_bag_outlined, _pickProduct),
            Expanded(child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 6),
              child: TextField(
                controller: _ctrl, minLines: 1, maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: _ar ? 'اكتب ردك…' : 'Type your reply…',
                  filled: true, fillColor: const Color(0xFFF2EFE8),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide.none),
                ),
              ),
            )),
            GestureDetector(
              onTap: _sending ? null : _send,
              child: Container(width: 44, height: 44,
                  decoration: const BoxDecoration(color: _tealDark, shape: BoxShape.circle),
                  child: _sending
                      ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send_rounded, color: Colors.white, size: 20)),
            ),
          ]),
        ),
      );

  Widget _cBtn(IconData i, VoidCallback onTap) => IconButton(
      onPressed: onTap, icon: Icon(i, color: _tealDark), iconSize: 22,
      style: IconButton.styleFrom(backgroundColor: const Color(0xFFE5F3F0), shape: const CircleBorder()));
}

// ═══════════════════════ PRODUCT PICKER ═══════════════════════
class _ProductPicker extends StatefulWidget {
  const _ProductPicker({required this.ar});
  final bool ar;
  @override
  State<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends State<_ProductPicker> {
  final _q = TextEditingController();
  List<Map<String, dynamic>> _items = [];
  Timer? _deb;
  bool _loading = false;

  @override
  void initState() { super.initState(); _search(''); }
  @override
  void dispose() { _deb?.cancel(); _q.dispose(); super.dispose(); }

  Future<void> _search(String q) async {
    setState(() => _loading = true);
    try {
      final res = await UellowApi.instance.getRaw('/api/mobile/v2/admin/cs/product_search',
          query: {'q': q}, auth: true);
      if (mounted) setState(() => _items = List<Map<String, dynamic>>.from(res['data']?['products'] ?? []));
    } catch (_) {} finally { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    final ar = widget.ar;
    return DraggableScrollableSheet(
      initialChildSize: .8, maxChildSize: .95, minChildSize: .5, expand: false,
      builder: (_, sc) => Container(
        decoration: const BoxDecoration(color: Color(0xFFF6F3EC),
            borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
        child: Column(children: [
          const SizedBox(height: 10),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: UellowColors.border, borderRadius: BorderRadius.circular(9))),
          Padding(padding: const EdgeInsets.all(14), child: Text(ar ? 'اقترح منتجًا للعميل' : 'Recommend a product',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: UellowColors.darkBrown))),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 14),
            child: TextField(controller: _q, autofocus: true,
              onChanged: (v) { _deb?.cancel(); _deb = Timer(const Duration(milliseconds: 350), () => _search(v)); },
              decoration: InputDecoration(hintText: ar ? 'ابحث بالاسم أو الكود…' : 'Search name or SKU…',
                prefixIcon: const Icon(Icons.search_rounded), filled: true, fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none)))),
          Expanded(child: _loading && _items.isEmpty
            ? const Center(child: CircularProgressIndicator(color: _tealDark))
            : GridView.builder(
                controller: sc, padding: const EdgeInsets.all(14),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: .72),
                itemCount: _items.length,
                itemBuilder: (_, i) {
                  final p = _items[i];
                  final img = (p['image'] ?? '').toString();
                  final full = img.startsWith('http') ? img : '${UellowApi.instance.baseUrl.replaceAll('/api/mobile/v2', '')}$img';
                  return GestureDetector(
                    onTap: () => Navigator.pop(context, p),
                    child: Container(
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(13),
                          border: Border.all(color: UellowColors.border)),
                      clipBehavior: Clip.antiAlias,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(child: Image.network(full, width: double.infinity, fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Container(color: UellowColors.yellowFaint,
                                child: const Icon(Icons.inventory_2_outlined, color: UellowColors.muted)))),
                        Padding(padding: const EdgeInsets.all(8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(p['name'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 3),
                          Text('${p['price']} ${ar ? 'د.ك' : 'KWD'}',
                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: _tealDark)),
                        ])),
                      ]),
                    ),
                  );
                },
              )),
        ]),
      ),
    );
  }
}
