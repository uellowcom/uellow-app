// =============================================================================
// Admin Console — Push Notifications (broadcast)
//
// Professional compose + send screen with ALL backend options
// (bilingual title/body, image, category, audience targeting [all / specific
// customers / segment], on-tap action [home / product / category / url /
// orders], send now or schedule) + a live reach estimate, plus a Stats &
// History tab with per-broadcast reach / open-rate analytics.
//
// Backend: /api/mobile/v2/admin/notify/{meta,estimate,send,history,<id>,customers}
// =============================================================================
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../api/uellow_api.dart';
import '../../services/admin_mode.dart';
import '../../theme/uellow_theme.dart';

String _two(int n) => n.toString().padLeft(2, '0');
// 'yyyy-MM-dd HH:mm:ss' (used for the scheduled_date payload, UTC).
String _fmtDtFull(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)} '
    '${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}';
// 'yyyy-MM-dd  HH:mm' (human display).
String _fmtDtShort(DateTime d) =>
    '${d.year}-${_two(d.month)}-${_two(d.day)}  ${_two(d.hour)}:${_two(d.minute)}';

class AdminNotificationsScreen extends StatefulWidget {
  const AdminNotificationsScreen({super.key});
  @override
  State<AdminNotificationsScreen> createState() =>
      _AdminNotificationsScreenState();
}

class _AdminNotificationsScreenState extends State<AdminNotificationsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  bool _loading = true;
  String? _error;

  // meta
  List<Map<String, dynamic>> _cats = [];
  List<Map<String, dynamic>> _auds = [];
  List<Map<String, dynamic>> _segs = [];
  List<Map<String, dynamic>> _acts = [];
  int _totalDevices = 0;
  int _totalCustomers = 0;
  Map<String, dynamic> _stats = {};

  @override
  void initState() {
    super.initState();
    _loadMeta();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadMeta() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await AdminApi.instance.notifyMeta();
      final opts = (d['options'] as Map?) ?? const {};
      final aud = (d['audience'] as Map?) ?? const {};
      _cats = _list(opts['categories']);
      _auds = _list(opts['audiences']);
      _segs = _list(opts['segments']);
      _acts = _list(opts['actions']);
      _totalDevices = (aud['total_devices'] ?? 0) as int;
      _totalCustomers = (aud['total_customers'] ?? 0) as int;
      _stats = ((d['stats'] as Map?) ?? const {}).cast<String, dynamic>();
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  static List<Map<String, dynamic>> _list(dynamic v) =>
      ((v as List?) ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return Scaffold(
      backgroundColor: UellowColors.bg,
      appBar: AppBar(
        backgroundColor: UellowColors.darkBrown,
        foregroundColor: UellowColors.yellow,
        iconTheme: const IconThemeData(color: UellowColors.yellow),
        title: Text(ar ? 'إشعارات التطبيق' : 'Push Notifications',
            style: const TextStyle(
                fontWeight: FontWeight.w900, color: UellowColors.yellow)),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: UellowColors.yellow,
          labelColor: UellowColors.yellow,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontWeight: FontWeight.w800),
          tabs: [
            Tab(text: ar ? 'إرسال' : 'Compose'),
            Tab(text: ar ? 'الإحصائيات' : 'Stats'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorRetry(msg: _error!, onRetry: _loadMeta, ar: ar)
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _ComposeTab(
                      ar: ar,
                      cats: _cats,
                      auds: _auds,
                      segs: _segs,
                      acts: _acts,
                      totalDevices: _totalDevices,
                      totalCustomers: _totalCustomers,
                      onSent: () {
                        _loadMeta();
                        _tabs.animateTo(1);
                      },
                    ),
                    _StatsTab(ar: ar, stats: _stats),
                  ],
                ),
    );
  }
}

// ═══════════════════════════ COMPOSE TAB ═══════════════════════════
class _ComposeTab extends StatefulWidget {
  const _ComposeTab({
    required this.ar,
    required this.cats,
    required this.auds,
    required this.segs,
    required this.acts,
    required this.totalDevices,
    required this.totalCustomers,
    required this.onSent,
  });
  final bool ar;
  final List<Map<String, dynamic>> cats, auds, segs, acts;
  final int totalDevices, totalCustomers;
  final VoidCallback onSent;

  @override
  State<_ComposeTab> createState() => _ComposeTabState();
}

class _ComposeTabState extends State<_ComposeTab> {
  final _titleEn = TextEditingController();
  final _bodyEn = TextEditingController();
  final _titleAr = TextEditingController();
  final _bodyAr = TextEditingController();
  final _url = TextEditingController();

  String _category = 'general';
  String _audience = 'all';
  String _segment = 'new_users';
  String _actionType = 'none';
  String _sendType = 'now';
  DateTime? _scheduled;

  String? _imageB64;
  final List<Map<String, dynamic>> _customers = [];
  Map<String, dynamic>? _product;
  Map<String, dynamic>? _category0;

  Map<String, dynamic>? _estimate;
  bool _estimating = false;
  bool _sending = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _segment = widget.segs.isNotEmpty
        ? widget.segs.first['value'].toString()
        : 'new_users';
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshEstimate());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [_titleEn, _bodyEn, _titleAr, _bodyAr, _url]) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> _payload({bool forSend = false}) {
    final m = <String, dynamic>{
      'title': _titleEn.text.trim(),
      'body': _bodyEn.text.trim(),
      'title_ar': _titleAr.text.trim(),
      'body_ar': _bodyAr.text.trim(),
      'category': _category,
      'target_audience': _audience,
      'action_type': _actionType,
      'send_type': _sendType,
    };
    if (_audience == 'segment') m['segment'] = _segment;
    if (_audience == 'specific') {
      m['partner_ids'] = _customers.map((e) => e['id']).toList();
    }
    if (_actionType == 'product' && _product != null) {
      m['product_id'] = _product!['id'];
    }
    if (_actionType == 'category' && _category0 != null) {
      m['category_id'] = _category0!['id'];
    }
    if (_actionType == 'url') m['action_url'] = _url.text.trim();
    if (forSend) {
      if (_imageB64 != null) m['image_base64'] = _imageB64;
      if (_sendType == 'scheduled' && _scheduled != null) {
        m['scheduled_date'] = _fmtDtFull(_scheduled!.toUtc());
      }
    }
    return m;
  }

  void _refreshEstimate() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _estimating = true);
      try {
        final e = await AdminApi.instance.notifyEstimate(_payload());
        if (mounted) setState(() => _estimate = e);
      } catch (_) {
        if (mounted) setState(() => _estimate = null);
      } finally {
        if (mounted) setState(() => _estimating = false);
      }
    });
  }

  Future<void> _pickImage() async {
    try {
      final x = await ImagePicker().pickImage(
          source: ImageSource.gallery, maxWidth: 1200, imageQuality: 82);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      setState(() => _imageB64 = base64Encode(bytes));
    } catch (_) {}
  }

  Future<void> _send() async {
    final ar = widget.ar;
    if (_titleEn.text.trim().isEmpty || _bodyEn.text.trim().isEmpty) {
      _toast(ar ? 'العنوان والنص مطلوبان' : 'Title and body are required');
      return;
    }
    if (_audience == 'specific' && _customers.isEmpty) {
      _toast(ar ? 'اختر عملاء أولاً' : 'Select customers first');
      return;
    }
    if (_sendType == 'scheduled' && _scheduled == null) {
      _toast(ar ? 'اختر موعد الجدولة' : 'Pick a schedule time');
      return;
    }
    final reach = _estimate?['devices'] ?? '?';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(_sendType == 'scheduled'
            ? (ar ? 'تأكيد الجدولة' : 'Confirm schedule')
            : (ar ? 'تأكيد الإرسال' : 'Confirm send')),
        content: Text(ar
            ? 'سيصل الإشعار إلى حوالي $reach جهاز. متابعة؟'
            : 'This will reach about $reach devices. Continue?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(ar ? 'إلغاء' : 'Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: UellowColors.darkBrown),
              onPressed: () => Navigator.pop(c, true),
              child: Text(ar ? 'إرسال' : 'Send',
                  style: const TextStyle(color: UellowColors.yellow))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _sending = true);
    try {
      final r = await AdminApi.instance.notifySend(_payload(forSend: true));
      if (!mounted) return;
      final scheduled = r['scheduled'] == true;
      await showDialog(
        context: context,
        builder: (c) => AlertDialog(
          icon: Icon(
              scheduled
                  ? Icons.schedule_rounded
                  : Icons.check_circle_rounded,
              color: UellowColors.success, size: 44),
          title: Text(scheduled
              ? (ar ? 'تمت الجدولة' : 'Scheduled')
              : (ar ? 'تم الإرسال' : 'Sent')),
          content: Text(scheduled
              ? (ar ? 'سيُرسل في موعده المحدد.' : 'Will be sent at the set time.')
              : (ar
                  ? 'وصل إلى ${r['reached'] ?? r['sent_count'] ?? 0} جهاز.'
                  : 'Reached ${r['reached'] ?? r['sent_count'] ?? 0} devices.')),
          actions: [
            FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: UellowColors.darkBrown),
                onPressed: () => Navigator.pop(c),
                child: Text(ar ? 'تمام' : 'OK',
                    style: const TextStyle(color: UellowColors.yellow))),
          ],
        ),
      );
      _resetForm();
      widget.onSent();
    } catch (e) {
      _toast('${ar ? 'فشل' : 'Failed'}: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _resetForm() {
    for (final c in [_titleEn, _bodyEn, _titleAr, _bodyAr, _url]) {
      c.clear();
    }
    setState(() {
      _category = 'general';
      _audience = 'all';
      _actionType = 'none';
      _sendType = 'now';
      _scheduled = null;
      _imageB64 = null;
      _customers.clear();
      _product = null;
      _category0 = null;
    });
  }

  void _toast(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final ar = widget.ar;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 40),
      children: [
        _reachCard(ar),
        const SizedBox(height: 14),
        _section(ar ? 'المحتوى' : 'Content', Icons.edit_note_rounded),
        _field(_titleEn, ar ? 'العنوان (إنجليزي)' : 'Title (EN)',
            onChanged: (_) {}),
        _field(_bodyEn, ar ? 'النص (إنجليزي)' : 'Body (EN)', lines: 3),
        _field(_titleAr, ar ? 'العنوان (عربي)' : 'Title (AR)'),
        _field(_bodyAr, ar ? 'النص (عربي)' : 'Body (AR)', lines: 3),
        const SizedBox(height: 6),
        _imageRow(ar),
        const SizedBox(height: 16),
        _section(ar ? 'الفئة' : 'Category', Icons.label_rounded),
        _chips(widget.cats, _category, (v) {
          setState(() => _category = v);
          _refreshEstimate();
        }),
        if (_category == 'system')
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
                ar
                    ? 'إشعارات النظام تتجاوز تفضيلات المستخدم (استخدمها للأمور الهامة فقط).'
                    : 'System notifications bypass user preferences (critical only).',
                style: const TextStyle(
                    fontSize: 12, color: UellowColors.warn)),
          ),
        const SizedBox(height: 16),
        _section(ar ? 'الجمهور المستهدف' : 'Target Audience',
            Icons.groups_rounded),
        _chips(widget.auds, _audience, (v) {
          setState(() => _audience = v);
          _refreshEstimate();
        }),
        if (_audience == 'segment') ...[
          const SizedBox(height: 10),
          _dropdown(widget.segs, _segment, (v) {
            setState(() => _segment = v);
            _refreshEstimate();
          }),
        ],
        if (_audience == 'specific') ...[
          const SizedBox(height: 10),
          _customersPicker(ar),
        ],
        const SizedBox(height: 16),
        _section(ar ? 'عند الضغط' : 'On Tap', Icons.touch_app_rounded),
        _dropdown(widget.acts, _actionType, (v) {
          setState(() {
            _actionType = v;
            _product = null;
            _category0 = null;
          });
        }, labelKey: true),
        if (_actionType == 'product') ...[
          const SizedBox(height: 8),
          _pickerTile(
              ar ? 'اختر المنتج' : 'Pick product',
              _product?['name'],
              Icons.inventory_2_rounded,
              () => _pickProduct(ar)),
        ],
        if (_actionType == 'category') ...[
          const SizedBox(height: 8),
          _pickerTile(ar ? 'اختر القسم' : 'Pick category',
              _category0?['name'], Icons.category_rounded, () => _pickCategory(ar)),
        ],
        if (_actionType == 'url') ...[
          const SizedBox(height: 8),
          _field(_url, 'https://...'),
        ],
        const SizedBox(height: 16),
        _section(ar ? 'التوقيت' : 'Timing', Icons.schedule_rounded),
        Row(children: [
          _timingBtn(ar ? 'الآن' : 'Now', 'now'),
          const SizedBox(width: 10),
          _timingBtn(ar ? 'جدولة' : 'Schedule', 'scheduled'),
        ]),
        if (_sendType == 'scheduled') ...[
          const SizedBox(height: 10),
          _pickerTile(
              ar ? 'اختر التاريخ والوقت' : 'Pick date & time',
              _scheduled == null ? null : _fmtDtShort(_scheduled!),
              Icons.event_rounded,
              _pickSchedule),
        ],
        const SizedBox(height: 24),
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: UellowColors.darkBrown,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14))),
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: UellowColors.yellow))
                : Icon(
                    _sendType == 'scheduled'
                        ? Icons.schedule_send_rounded
                        : Icons.send_rounded,
                    color: UellowColors.yellow),
            label: Text(
                _sendType == 'scheduled'
                    ? (ar ? 'جدولة الإشعار' : 'Schedule')
                    : (ar ? 'إرسال الإشعار' : 'Send Notification'),
                style: const TextStyle(
                    color: UellowColors.yellow,
                    fontWeight: FontWeight.w900,
                    fontSize: 15)),
          ),
        ),
      ],
    );
  }

  // ── reach estimate card ──
  Widget _reachCard(bool ar) {
    final dev = _estimate?['devices'];
    final cust = _estimate?['customers'];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [UellowColors.darkBrown, Color(0xFF6B3E0A)]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        const Icon(Icons.podcasts_rounded,
            color: UellowColors.yellow, size: 34),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(ar ? 'الوصول المتوقّع' : 'Estimated reach',
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            _estimating
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: UellowColors.yellow)))
                : Text(
                    dev == null
                        ? '—'
                        : (ar
                            ? '$dev جهاز · $cust عميل'
                            : '$dev devices · $cust customers'),
                    style: const TextStyle(
                        color: UellowColors.yellow,
                        fontSize: 20,
                        fontWeight: FontWeight.w900)),
            Text(
                ar
                    ? 'من إجمالي ${widget.totalDevices} جهاز مسجّل'
                    : 'of ${widget.totalDevices} registered devices',
                style: const TextStyle(color: Colors.white54, fontSize: 11)),
          ]),
        ),
        IconButton(
            onPressed: _refreshEstimate,
            icon: const Icon(Icons.refresh_rounded,
                color: UellowColors.yellow)),
      ]),
    );
  }

  Widget _imageRow(bool ar) {
    return Row(children: [
      if (_imageB64 != null)
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.memory(base64Decode(_imageB64!),
              width: 54, height: 54, fit: BoxFit.cover),
        ),
      if (_imageB64 != null) const SizedBox(width: 10),
      OutlinedButton.icon(
        onPressed: _pickImage,
        icon: const Icon(Icons.image_rounded, size: 18),
        label: Text(_imageB64 == null
            ? (ar ? 'إضافة صورة (اختياري)' : 'Add image (optional)')
            : (ar ? 'تغيير الصورة' : 'Change image')),
      ),
      if (_imageB64 != null)
        IconButton(
            onPressed: () => setState(() => _imageB64 = null),
            icon: const Icon(Icons.close_rounded, color: UellowColors.danger)),
    ]);
  }

  // ── specific customers ──
  Widget _customersPicker(bool ar) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      OutlinedButton.icon(
        onPressed: () => _pickCustomers(ar),
        icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
        label: Text(ar ? 'اختيار العملاء' : 'Select customers'),
      ),
      if (_customers.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in _customers)
                Chip(
                  label: Text(c['name']?.toString() ?? '—',
                      style: const TextStyle(fontSize: 12)),
                  onDeleted: () {
                    setState(() => _customers.remove(c));
                    _refreshEstimate();
                  },
                  backgroundColor: UellowColors.yellowSoft,
                ),
            ],
          ),
        ),
    ]);
  }

  Future<void> _pickCustomers(bool ar) async {
    final picked = await showModalBottomSheet<List<Map<String, dynamic>>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => _CustomerPickerSheet(
          ar: ar, already: List.of(_customers)),
    );
    if (picked != null) {
      setState(() {
        _customers
          ..clear()
          ..addAll(picked);
      });
      _refreshEstimate();
    }
  }

  Future<void> _pickProduct(bool ar) async {
    final r = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => const _ProductPickerSheet(),
    );
    if (r != null) setState(() => _product = r);
  }

  Future<void> _pickCategory(bool ar) async {
    final r = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => const _CategoryPickerSheet(),
    );
    if (r != null) setState(() => _category0 = r);
  }

  Future<void> _pickSchedule() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(hours: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
        context: context, initialTime: TimeOfDay.now());
    if (t == null) return;
    setState(() =>
        _scheduled = DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  // ── small building blocks ──
  Widget _section(String t, IconData ic) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 2),
        child: Row(children: [
          Icon(ic, size: 18, color: UellowColors.darkBrown),
          const SizedBox(width: 6),
          Text(t,
              style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  color: UellowColors.ink)),
        ]),
      );

  Widget _field(TextEditingController c, String hint,
          {int lines = 1, ValueChanged<String>? onChanged}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          maxLines: lines,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: UellowColors.border)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: UellowColors.border)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: UellowColors.yellow, width: 1.5)),
          ),
        ),
      );

  Widget _chips(List<Map<String, dynamic>> items, String sel,
          ValueChanged<String> onTap) =>
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final it in items)
            GestureDetector(
              onTap: () => onTap(it['value'].toString()),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: sel == it['value']
                      ? UellowColors.darkBrown
                      : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: sel == it['value']
                          ? UellowColors.darkBrown
                          : UellowColors.border),
                ),
                child: Text(
                    (widget.ar ? it['ar'] : it['en'])?.toString() ?? '',
                    style: TextStyle(
                        color: sel == it['value']
                            ? UellowColors.yellow
                            : UellowColors.ink,
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5)),
              ),
            ),
        ],
      );

  Widget _dropdown(List<Map<String, dynamic>> items, String val,
          ValueChanged<String> onChanged,
          {bool labelKey = false}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: UellowColors.border)),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: items.any((e) => e['value'] == val)
                ? val
                : (items.isNotEmpty ? items.first['value'].toString() : null),
            isExpanded: true,
            items: [
              for (final it in items)
                DropdownMenuItem(
                  value: it['value'].toString(),
                  child: Text(
                      (widget.ar ? it['ar'] : it['en'])?.toString() ?? '',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13.5)),
                ),
            ],
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      );

  Widget _pickerTile(
          String hint, String? value, IconData ic, VoidCallback onTap) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: UellowColors.border)),
          child: Row(children: [
            Icon(ic, size: 18, color: UellowColors.muted),
            const SizedBox(width: 10),
            Expanded(
                child: Text(value ?? hint,
                    style: TextStyle(
                        color: value == null
                            ? UellowColors.muted
                            : UellowColors.ink,
                        fontWeight: FontWeight.w700))),
            const Icon(Icons.chevron_right_rounded,
                color: UellowColors.muted),
          ]),
        ),
      );

  Widget _timingBtn(String label, String val) => Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _sendType = val),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color:
                  _sendType == val ? UellowColors.darkBrown : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: _sendType == val
                      ? UellowColors.darkBrown
                      : UellowColors.border),
            ),
            child: Text(label,
                style: TextStyle(
                    color: _sendType == val
                        ? UellowColors.yellow
                        : UellowColors.ink,
                    fontWeight: FontWeight.w800)),
          ),
        ),
      );
}

// ═══════════════════════════ STATS TAB ═══════════════════════════
class _StatsTab extends StatefulWidget {
  const _StatsTab({required this.ar, required this.stats});
  final bool ar;
  final Map<String, dynamic> stats;
  @override
  State<_StatsTab> createState() => _StatsTabState();
}

class _StatsTabState extends State<_StatsTab> {
  final _items = <Map<String, dynamic>>[];
  bool _loading = true;
  int _page = 1;
  bool _hasMore = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    if (!more) setState(() => _loading = true);
    try {
      final d =
          await AdminApi.instance.notifyHistory(page: more ? _page + 1 : 1);
      final list = ((d['items'] as List?) ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
      setState(() {
        if (more) {
          _page += 1;
          _items.addAll(list);
        } else {
          _page = 1;
          _items
            ..clear()
            ..addAll(list);
        }
        _hasMore = d['has_more'] == true;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ar = widget.ar;
    final s = widget.stats;
    return RefreshIndicator(
      onRefresh: () => _load(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 40),
        children: [
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.7,
            children: [
              _kpi(ar ? 'إشعارات مُرسلة' : 'Broadcasts',
                  '${s['broadcasts_sent'] ?? 0}', Icons.campaign_rounded,
                  UellowColors.darkBrown),
              _kpi(ar ? 'إجمالي الوصول' : 'Total reach',
                  '${s['total_reach'] ?? 0}', Icons.podcasts_rounded,
                  UellowColors.success),
              _kpi(ar ? 'مرات الفتح' : 'Opens',
                  '${s['total_opened'] ?? 0}', Icons.open_in_new_rounded,
                  UellowColors.warn),
              _kpi(ar ? 'معدل الفتح' : 'Open rate',
                  '${s['avg_open_rate'] ?? 0}%', Icons.percent_rounded,
                  Colors.indigo),
            ],
          ),
          if ((s['scheduled'] ?? 0) != 0)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: _banner(
                  ar
                      ? '${s['scheduled']} إشعار مجدول قيد الانتظار'
                      : '${s['scheduled']} scheduled and pending',
                  Icons.schedule_rounded),
            ),
          const SizedBox(height: 18),
          Row(children: [
            const Icon(Icons.history_rounded,
                size: 18, color: UellowColors.darkBrown),
            const SizedBox(width: 6),
            Text(ar ? 'السجل' : 'History',
                style: const TextStyle(
                    fontWeight: FontWeight.w900, fontSize: 15)),
          ]),
          const SizedBox(height: 10),
          if (_loading)
            const Padding(
                padding: EdgeInsets.all(30),
                child: Center(child: CircularProgressIndicator()))
          else if (_items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(30),
              child: Center(
                  child: Text(ar ? 'لا يوجد سجل بعد' : 'No history yet',
                      style: const TextStyle(color: UellowColors.muted))),
            )
          else ...[
            for (final it in _items) _histTile(it, ar),
            if (_hasMore)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton(
                    onPressed: () => _load(more: true),
                    child: Text(ar ? 'عرض المزيد' : 'Load more')),
              ),
          ],
        ],
      ),
    );
  }

  Widget _kpi(String label, String value, IconData ic, Color c) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: UellowColors.border)),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(children: [
                Icon(ic, size: 18, color: c),
                const Spacer(),
              ]),
              const SizedBox(height: 6),
              Text(value,
                  style: TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w900, color: c)),
              Text(label,
                  style: const TextStyle(
                      fontSize: 11.5,
                      color: UellowColors.muted,
                      fontWeight: FontWeight.w700)),
            ]),
      );

  Widget _banner(String text, IconData ic) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: UellowColors.yellowSoft,
            borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Icon(ic, size: 18, color: UellowColors.darkBrown),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                      color: UellowColors.darkBrown))),
        ]),
      );

  Widget _histTile(Map<String, dynamic> it, bool ar) {
    final reached = (it['reached'] ?? 0) as int;
    final opened = (it['opened'] ?? 0) as int;
    final rate = (it['open_rate'] ?? 0).toDouble();
    final state = it['state']?.toString() ?? 'draft';
    final img = it['image_url']?.toString() ?? '';
    return InkWell(
      onTap: () => _openDetail(it['id'] as int, ar),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: UellowColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (img.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(img,
                      width: 42,
                      height: 42,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox()),
                ),
              ),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        (ar
                                ? (it['title_ar']?.toString().isNotEmpty == true
                                    ? it['title_ar']
                                    : it['title'])
                                : it['title'])
                            ?.toString() ??
                            '—',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 13.5)),
                    Text(it['sent_date']?.toString().split('.').first ??
                        it['create_date']?.toString().split('.').first ??
                        '',
                        style: const TextStyle(
                            fontSize: 11, color: UellowColors.muted)),
                  ]),
            ),
            _stateBadge(state, ar),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _miniStat(Icons.podcasts_rounded, '$reached',
                ar ? 'وصل' : 'reached'),
            _miniStat(Icons.open_in_new_rounded, '$opened',
                ar ? 'فُتح' : 'opened'),
            _miniStat(Icons.percent_rounded,
                '${rate.toStringAsFixed(0)}%', ar ? 'المعدل' : 'rate'),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: reached == 0 ? 0 : (opened / reached).clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: UellowColors.border,
              color: UellowColors.success,
            ),
          ),
        ]),
      ),
    );
  }

  Widget _miniStat(IconData ic, String v, String l) => Expanded(
        child: Row(children: [
          Icon(ic, size: 15, color: UellowColors.muted),
          const SizedBox(width: 4),
          Text(v,
              style: const TextStyle(
                  fontWeight: FontWeight.w900, fontSize: 13)),
          const SizedBox(width: 3),
          Text(l,
              style: const TextStyle(
                  fontSize: 10.5, color: UellowColors.muted)),
        ]),
      );

  Widget _stateBadge(String state, bool ar) {
    Color c;
    String t;
    switch (state) {
      case 'sent':
        c = UellowColors.success;
        t = ar ? 'مُرسل' : 'Sent';
        break;
      case 'scheduled':
        c = UellowColors.warn;
        t = ar ? 'مجدول' : 'Scheduled';
        break;
      case 'failed':
        c = UellowColors.danger;
        t = ar ? 'فشل' : 'Failed';
        break;
      default:
        c = UellowColors.muted;
        t = ar ? 'مسودة' : 'Draft';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: c.withOpacity(.12),
          borderRadius: BorderRadius.circular(999)),
      child: Text(t,
          style: TextStyle(
              color: c, fontWeight: FontWeight.w800, fontSize: 11)),
    );
  }

  Future<void> _openDetail(int id, bool ar) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => _DetailSheet(id: id, ar: ar),
    );
  }
}

// ═══════════════════════ DETAIL BOTTOM SHEET ═══════════════════════
class _DetailSheet extends StatefulWidget {
  const _DetailSheet({required this.id, required this.ar});
  final int id;
  final bool ar;
  @override
  State<_DetailSheet> createState() => _DetailSheetState();
}

class _DetailSheetState extends State<_DetailSheet> {
  Map<String, dynamic>? _d;
  @override
  void initState() {
    super.initState();
    AdminApi.instance.notifyDetail(widget.id).then((d) {
      if (mounted) setState(() => _d = d);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ar = widget.ar;
    final d = _d;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .7,
      maxChildSize: .92,
      builder: (_, ctrl) => d == null
          ? const SizedBox(
              height: 200, child: Center(child: CircularProgressIndicator()))
          : ListView(
              controller: ctrl,
              padding: const EdgeInsets.all(18),
              children: [
                Center(
                  child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: UellowColors.border,
                          borderRadius: BorderRadius.circular(2))),
                ),
                const SizedBox(height: 14),
                Text(d['title']?.toString() ?? '',
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w900)),
                if ((d['title_ar']?.toString() ?? '').isNotEmpty)
                  Text(d['title_ar'].toString(),
                      style: const TextStyle(
                          fontSize: 14, color: UellowColors.muted)),
                const SizedBox(height: 8),
                Text(d['body']?.toString() ?? '',
                    style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 16),
                Row(children: [
                  _bigStat('${d['reached'] ?? 0}', ar ? 'وصل' : 'Reached',
                      UellowColors.success),
                  _bigStat('${d['opened'] ?? 0}', ar ? 'فُتح' : 'Opened',
                      UellowColors.warn),
                  _bigStat('${d['open_rate'] ?? 0}%',
                      ar ? 'المعدل' : 'Open rate', Colors.indigo),
                  _bigStat('${d['failed'] ?? 0}', ar ? 'فشل' : 'Failed',
                      UellowColors.danger),
                ]),
                const SizedBox(height: 18),
                Text(ar ? 'المستلمون' : 'Recipients',
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 14)),
                const SizedBox(height: 8),
                for (final r in ((d['recipients'] as List?) ?? const []))
                  _recipient((r as Map).cast<String, dynamic>(), ar),
                const SizedBox(height: 20),
              ],
            ),
    );
  }

  Widget _bigStat(String v, String l, Color c) => Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
              color: c.withOpacity(.08),
              borderRadius: BorderRadius.circular(12)),
          child: Column(children: [
            Text(v,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w900, color: c)),
            Text(l,
                style: const TextStyle(
                    fontSize: 10.5, color: UellowColors.muted)),
          ]),
        ),
      );

  Widget _recipient(Map<String, dynamic> r, bool ar) {
    final opened = r['opened'] == true;
    final reached = r['reached'] == true;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Icon(
            opened
                ? Icons.mark_email_read_rounded
                : reached
                    ? Icons.done_all_rounded
                    : Icons.error_outline_rounded,
            size: 18,
            color: opened
                ? UellowColors.success
                : reached
                    ? UellowColors.muted
                    : UellowColors.danger),
        const SizedBox(width: 10),
        Expanded(
            child: Text(r['customer']?.toString() ?? 'Guest',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 13))),
        Text(r['platform']?.toString() ?? '',
            style:
                const TextStyle(fontSize: 11, color: UellowColors.muted)),
      ]),
    );
  }
}

// ═══════════════════════ CUSTOMER PICKER ═══════════════════════
class _CustomerPickerSheet extends StatefulWidget {
  const _CustomerPickerSheet({required this.ar, required this.already});
  final bool ar;
  final List<Map<String, dynamic>> already;
  @override
  State<_CustomerPickerSheet> createState() => _CustomerPickerSheetState();
}

class _CustomerPickerSheetState extends State<_CustomerPickerSheet> {
  final _q = TextEditingController();
  final _sel = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  Timer? _deb;

  @override
  void initState() {
    super.initState();
    _sel.addAll(widget.already);
    _search('');
  }

  void _onChanged(String v) {
    _deb?.cancel();
    _deb = Timer(const Duration(milliseconds: 300), () => _search(v));
  }

  Future<void> _search(String q) async {
    setState(() => _loading = true);
    try {
      final r = await AdminApi.instance.notifyCustomers(q: q);
      if (mounted) setState(() => _results = r);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _isSel(Map<String, dynamic> c) =>
      _sel.any((e) => e['id'] == c['id']);

  @override
  Widget build(BuildContext context) {
    final ar = widget.ar;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .8,
      maxChildSize: .95,
      builder: (_, ctrl) => Column(children: [
        const SizedBox(height: 10),
        Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: UellowColors.border,
                borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.all(14),
          child: TextField(
            controller: _q,
            onChanged: _onChanged,
            decoration: InputDecoration(
              hintText: ar ? 'ابحث بالاسم/الهاتف/البريد' : 'Search name/phone/email',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: UellowColors.bg,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
            ),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  controller: ctrl,
                  itemCount: _results.length,
                  itemBuilder: (_, i) {
                    final c = _results[i];
                    final sel = _isSel(c);
                    return CheckboxListTile(
                      value: sel,
                      activeColor: UellowColors.darkBrown,
                      title: Text(c['name']?.toString() ?? '—',
                          style:
                              const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text([
                        if ((c['phone']?.toString() ?? '').isNotEmpty)
                          c['phone'],
                        if ((c['email']?.toString() ?? '').isNotEmpty)
                          c['email'],
                      ].join(' · ')),
                      onChanged: (_) {
                        setState(() {
                          if (sel) {
                            _sel.removeWhere((e) => e['id'] == c['id']);
                          } else {
                            _sel.add(c);
                          }
                        });
                      },
                    );
                  },
                ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              height: 48,
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: UellowColors.darkBrown),
                onPressed: () => Navigator.pop(context, _sel),
                child: Text(
                    ar
                        ? 'تأكيد (${_sel.length})'
                        : 'Confirm (${_sel.length})',
                    style: const TextStyle(
                        color: UellowColors.yellow,
                        fontWeight: FontWeight.w900)),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

// ═══════════════════════ PRODUCT PICKER ═══════════════════════
class _ProductPickerSheet extends StatefulWidget {
  const _ProductPickerSheet();
  @override
  State<_ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<_ProductPickerSheet> {
  final _q = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  Timer? _deb;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  void _onChanged(String v) {
    _deb?.cancel();
    _deb = Timer(const Duration(milliseconds: 300), () => _search(v));
  }

  Future<void> _search(String q) async {
    setState(() => _loading = true);
    try {
      final d = await AdminApi.instance.products(q: q);
      final list = ((d['items'] as List?) ?? (d['products'] as List?) ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
      if (mounted) setState(() => _results = list);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .8,
      maxChildSize: .95,
      builder: (_, ctrl) => Column(children: [
        const SizedBox(height: 10),
        Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: UellowColors.border,
                borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.all(14),
          child: TextField(
            controller: _q,
            onChanged: _onChanged,
            decoration: InputDecoration(
              hintText: ar ? 'ابحث عن منتج' : 'Search product',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: UellowColors.bg,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
            ),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  controller: ctrl,
                  itemCount: _results.length,
                  itemBuilder: (_, i) {
                    final p = _results[i];
                    final name = (p['name'] is Map)
                        ? ((ar ? p['name']['ar'] : p['name']['en']) ??
                            p['name']['en'])
                        : p['name'];
                    return ListTile(
                      title: Text(name?.toString() ?? '—',
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.pop(
                          context, {'id': p['id'], 'name': name?.toString()}),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

// ═══════════════════════ CATEGORY PICKER ═══════════════════════
class _CategoryPickerSheet extends StatefulWidget {
  const _CategoryPickerSheet();
  @override
  State<_CategoryPickerSheet> createState() => _CategoryPickerSheetState();
}

class _CategoryPickerSheetState extends State<_CategoryPickerSheet> {
  List<Map<String, dynamic>> _cats = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await UellowApi.instance
          .getRaw('/api/mobile/v2/admin/categories', auth: true);
      final list = (((r['data'] as Map?)?['items'] as List?) ??
              ((r['data'] as Map?)?['categories'] as List?) ??
              const [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
      if (mounted) {
        setState(() {
          _cats = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .7,
      maxChildSize: .92,
      builder: (_, ctrl) => _loading
          ? const SizedBox(
              height: 200, child: Center(child: CircularProgressIndicator()))
          : ListView.builder(
              controller: ctrl,
              padding: const EdgeInsets.all(8),
              itemCount: _cats.length,
              itemBuilder: (_, i) {
                final c = _cats[i];
                final name = (c['name'] is Map)
                    ? ((ar ? c['name']['ar'] : c['name']['en']) ??
                        c['name']['en'])
                    : c['name'];
                return ListTile(
                  title: Text(name?.toString() ?? '—'),
                  onTap: () => Navigator.pop(
                      context, {'id': c['id'], 'name': name?.toString()}),
                );
              },
            ),
    );
  }
}

// ═══════════════════════ ERROR ═══════════════════════
class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry(
      {required this.msg, required this.onRetry, required this.ar});
  final String msg;
  final VoidCallback onRetry;
  final bool ar;
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.lock_outline_rounded,
              size: 36, color: UellowColors.muted),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: Text(msg,
                textAlign: TextAlign.center,
                style: const TextStyle(color: UellowColors.muted)),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            style:
                FilledButton.styleFrom(backgroundColor: UellowColors.darkBrown),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 16, color: UellowColors.yellow),
            label: Text(ar ? 'إعادة' : 'Retry',
                style: const TextStyle(color: UellowColors.yellow)),
          ),
        ]),
      );
}
