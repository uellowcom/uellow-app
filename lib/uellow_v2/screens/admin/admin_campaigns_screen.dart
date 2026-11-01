// =============================================================================
// AdminCampaignsScreen (v2.2.147) — كونسول العروض والحملات: تشغيل/إيقاف فوري +
// الجدولة + الحالة + عدد المنتجات. المصدر: /api/mobile/v2/admin/campaigns.
// =============================================================================
import 'package:flutter/material.dart';

import '../../../api/uellow_api.dart';
import '../../services/admin_mode.dart';
import '../../theme/uellow_theme.dart';

class AdminCampaignsScreen extends StatefulWidget {
  const AdminCampaignsScreen({super.key});
  @override
  State<AdminCampaignsScreen> createState() => _AdminCampaignsScreenState();
}

class _AdminCampaignsScreenState extends State<AdminCampaignsScreen> {
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;
  String? _error;
  final Set<int> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final d = await AdminApi.instance.campaigns();
      _rows = ((d['campaigns'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _toggle(Map<String, dynamic> c) async {
    final id = (c['id'] as num).toInt();
    final next = !(c['active'] == true);
    setState(() => _busy.add(id));
    try {
      final r = await AdminApi.instance.campaignToggle(id, next);
      final active = (r['data']?['active'] as bool?) ?? next;
      setState(() => c['active'] = active);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: UellowColors.danger));
      }
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F5),
      appBar: AppBar(
        backgroundColor: UellowColors.darkBrown,
        foregroundColor: Colors.white,
        title: Text(ar ? 'العروض والحملات' : 'Offers & campaigns',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
        actions: [
          IconButton(
            tooltip: ar ? 'عرض جديد' : 'New offer',
            onPressed: () => _createCampaign(ar),
            icon: const Icon(Icons.add_circle_outline_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(
              color: UellowColors.darkBrown))
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24),
                  child: Text(_error!, textAlign: TextAlign.center)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
                    children: [
                      if (_rows.isEmpty)
                        Padding(padding: const EdgeInsets.all(30),
                            child: Center(child: Text(
                                ar ? 'لا توجد حملات بعد.' : 'No campaigns yet.',
                                style: const TextStyle(
                                    color: UellowColors.muted)))),
                      for (final c in _rows) _card(c, ar),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFDF3D6),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFEFD79A)),
                        ),
                        child: Text(ar
                            ? 'ℹ️ إنشاء حملة جديدة وربط البنرات والمنتجات يتم من لوحة الويب (باني الصفحات). هنا تتحكم في التشغيل/الإيقاف والجدولة فورًا.'
                            : 'ℹ️ Creating new campaigns and linking banners/products is done from the web builder. Here you toggle them on/off instantly.',
                            style: const TextStyle(fontSize: 11.5,
                                height: 1.5, color: Color(0xFF6B4E00),
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _card(Map<String, dynamic> c, bool ar) {
    final id = (c['id'] as num).toInt();
    final active = c['active'] == true;
    final live = c['is_live'] == true;
    final name = (ar
            ? (c['name_ar'] ?? c['name']) : c['name'])?.toString() ?? '';
    final pc = (c['product_count'] as num?)?.toInt() ?? 0;
    final disc = (c['discount_pct'] as num?)?.toInt() ?? 0;
    final sub = (ar ? (c['subtitle_ar'] ?? c['subtitle']) : c['subtitle'])
            ?.toString() ?? '';
    final start = _fmtDate(c['start_date']);
    final end = _fmtDate(c['end_date']);
    final busy = _busy.contains(id);
    final ended = end != null && (c['end_date'] != null)
        && DateTime.tryParse(c['end_date'].toString())
                ?.isBefore(DateTime.now()) == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ended
            ? const Color(0xFFEEC3BC) : const Color(0xFFECECEC)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Builder(builder: (_) {
            final th = (c['thumbs'] as List?) ?? const [];
            final img = th.isNotEmpty ? th.first.toString() : '';
            return Container(
              width: 44, height: 44,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                  color: const Color(0xFFF3EFE6),
                  borderRadius: BorderRadius.circular(12)),
              child: img.isNotEmpty
                  ? Image.network(
                      img.startsWith('http')
                          ? img : '${UellowApi.instance.baseUrl}$img',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                          Icons.campaign_rounded, size: 22,
                          color: Color(0xFFE8820A)))
                  : const Icon(Icons.campaign_rounded, size: 22,
                      color: Color(0xFFE8820A)),
            );
          }),
          const SizedBox(width: 11),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14,
                    fontWeight: FontWeight.w900, color: UellowColors.ink)),
            const SizedBox(height: 2),
            Text('$pc ${ar ? 'منتج' : 'products'}'
                '${disc > 0 ? ' · ${ar ? 'خصم حتى' : 'up to'} $disc٪' : ''}',
                style: const TextStyle(fontSize: 11,
                    fontWeight: FontWeight.w600, color: UellowColors.muted)),
            if (sub.isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 1),
                child: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10.5,
                        color: UellowColors.muted))),
          ])),
          busy
              ? const SizedBox(width: 40, height: 24, child: Center(
                  child: SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))))
              : Switch(
                  value: active,
                  activeColor: Colors.white,
                  activeTrackColor: const Color(0xFF1A7A46),
                  onChanged: (_) => _toggle(c)),
        ]),
        const SizedBox(height: 9),
        Wrap(spacing: 6, runSpacing: 6, children: [
          if (ended) _badge(ar ? '⏰ منتهية' : '⏰ Ended',
              const Color(0xFFF8E0DC), const Color(0xFFC23B2B))
          else if (live) _badge(ar ? '🟢 نشطة الآن' : '🟢 Live now',
              const Color(0xFFE3F3EA), const Color(0xFF1A7A46))
          else if (active) _badge(ar ? '✓ مفعّلة' : '✓ Enabled',
              const Color(0xFFE5EEFB), const Color(0xFF1D5FB4))
          else _badge(ar ? 'متوقفة' : 'Off',
              const Color(0xFFF1EEE7), UellowColors.muted),
          if (start != null || end != null)
            _badge('📅 ${start ?? '—'} → ${end ?? '—'}',
                const Color(0xFFFDF3D6), const Color(0xFF6B4E00)),
          if (live && c['end_date'] != null)
            _badge('⏱️ ${_remaining(ar, c['end_date'])}',
                const Color(0xFFFBEFD6), const Color(0xFFA9680A)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _campBtn(Icons.event_rounded,
              ar ? '📅 الجدولة' : '📅 Schedule', () => _editSchedule(c, ar))),
          const SizedBox(width: 8),
          Expanded(child: _campBtn(Icons.inventory_2_outlined,
              ar ? '🏷️ المنتجات' : '🏷️ Products', () => _showProducts(c, ar))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _campBtn(Icons.palette_outlined,
              ar ? '🎨 الألوان' : '🎨 Colors', () => _editColors(c, ar))),
          const SizedBox(width: 8),
          Expanded(child: _campBtn(Icons.visibility_outlined,
              ar ? '👁️ معاينة' : '👁️ Preview', () => _showProducts(c, ar))),
        ]),
      ]),
    );
  }

  Future<void> _createCampaign(bool ar) async {
    final nC = TextEditingController();
    final go = await showDialog<bool>(context: context, builder: (c) =>
        AlertDialog(
          title: Text(ar ? '➕ عرض جديد' : '➕ New offer'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nC, decoration: InputDecoration(
                labelText: ar ? 'اسم الحملة' : 'Campaign name')),
            const SizedBox(height: 6),
            Text(ar
                ? 'المنتجات والبنر تُضاف من باني الويب بعد الإنشاء.'
                : 'Add products & banner from the web builder after creating.',
                style: const TextStyle(fontSize: 11,
                    color: UellowColors.muted)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false),
                child: Text(ar ? 'إلغاء' : 'Cancel')),
            TextButton(onPressed: () => Navigator.pop(c, true),
                child: Text(ar ? 'إنشاء' : 'Create')),
          ],
        ));
    if (go == true && nC.text.trim().isNotEmpty) {
      try {
        await AdminApi.instance.campaignCreate(
            {'name': nC.text.trim(), 'name_ar': nC.text.trim()});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(ar ? 'تم إنشاء الحملة' : 'Campaign created')));
          _load();
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: UellowColors.danger));
      }
    }
  }

  Future<void> _editColors(Map<String, dynamic> c, bool ar) async {
    final id = (c['id'] as num).toInt();
    final bgC = TextEditingController(
        text: (c['bg_color'] ?? '#F5C320').toString());
    final go = await showDialog<bool>(context: context, builder: (ctx) =>
        AlertDialog(
          title: Text(ar ? '🎨 ألوان الحملة' : '🎨 Campaign colors'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: bgC, decoration: InputDecoration(
                labelText: ar ? 'لون الخلفية (#RRGGBB)' : 'Background (#RRGGBB)')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: Text(ar ? 'إلغاء' : 'Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true),
                child: Text(ar ? 'حفظ' : 'Save')),
          ],
        ));
    if (go == true) {
      try {
        await AdminApi.instance.campaignStyle(id,
            {'background_color': bgC.text.trim()});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(ar ? 'تم حفظ الألوان' : 'Colors saved')));
          _load();
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: UellowColors.danger));
      }
    }
  }

  Widget _campBtn(IconData icon, String label, VoidCallback onTap) =>
      OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 15),
        label: Text(label, style: const TextStyle(
            fontSize: 11.5, fontWeight: FontWeight.w800)),
        style: OutlinedButton.styleFrom(
          foregroundColor: UellowColors.darkBrown,
          side: const BorderSide(color: Color(0xFFE9E1D1)),
          padding: const EdgeInsets.symmetric(vertical: 9),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11)),
        ),
      );

  Future<void> _editSchedule(Map<String, dynamic> c, bool ar) async {
    final id = (c['id'] as num).toInt();
    final now = DateTime.now();
    DateTime? start = DateTime.tryParse((c['start_date'] ?? '').toString());
    DateTime? end = DateTime.tryParse((c['end_date'] ?? '').toString());
    final s = await showDatePicker(context: context,
        initialDate: start ?? now,
        firstDate: DateTime(now.year - 1), lastDate: DateTime(now.year + 2),
        helpText: ar ? 'تاريخ البداية' : 'Start date');
    if (s == null) return;
    if (!mounted) return;
    final e = await showDatePicker(context: context,
        initialDate: end ?? s.add(const Duration(days: 7)),
        firstDate: s, lastDate: DateTime(now.year + 2),
        helpText: ar ? 'تاريخ النهاية' : 'End date');
    String fmt(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    try {
      await AdminApi.instance.campaignSchedule(id, {
        'start_date': fmt(s),
        if (e != null) 'end_date': '${fmt(e)} 23:59:59',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(ar ? 'تم تحديث الجدولة' : 'Schedule updated')));
        _load();
      }
    } catch (err) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(err.toString().replaceAll('Exception: ', '')),
          backgroundColor: UellowColors.danger));
    }
  }

  Future<void> _showProducts(Map<String, dynamic> c, bool ar) async {
    final id = (c['id'] as num).toInt();
    List prods = const [];
    try {
      final r = await AdminApi.instance.campaignProducts(id);
      prods = (r['products'] as List?) ?? const [];
    } catch (_) {}
    if (!mounted) return;
    await showModalBottomSheet(context: context, isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius:
          BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false, initialChildSize: 0.6, maxChildSize: 0.9,
        builder: (ctx, sc) => ListView(controller: sc,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24), children: [
          Text(ar ? '🏷️ منتجات الحملة (${prods.length})'
                  : '🏷️ Campaign products (${prods.length})',
              style: const TextStyle(fontSize: 15,
                  fontWeight: FontWeight.w900, color: UellowColors.ink)),
          const SizedBox(height: 10),
          if (prods.isEmpty)
            Padding(padding: const EdgeInsets.all(20),
                child: Center(child: Text(ar
                    ? 'لا منتجات (قد تكون الحملة تلقائية بالخصم).'
                    : 'No products (campaign may be auto-discount).',
                    style: const TextStyle(color: UellowColors.muted)))),
          for (final p in prods) Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              ClipRRect(borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                      '${UellowApi.instance.baseUrl}${(p as Map)['image'] ?? ''}',
                      width: 40, height: 40, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(width: 40,
                          height: 40, color: const Color(0xFFF1EEE7),
                          child: const Icon(Icons.image_outlined, size: 16,
                              color: UellowColors.muted)))),
              const SizedBox(width: 10),
              Expanded(child: Text(p['name']?.toString() ?? '',
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12,
                      fontWeight: FontWeight.w600))),
              const SizedBox(width: 8),
              Text('${p['price'] ?? 0}', style: const TextStyle(fontSize: 12,
                  fontWeight: FontWeight.w900, color: UellowColors.darkBrown)),
            ]),
          ),
          const SizedBox(height: 10),
          Text(ar
              ? 'ℹ️ إضافة/إزالة المنتجات والبنر من باني الويب.'
              : 'ℹ️ Add/remove products & banner from the web builder.',
              style: const TextStyle(fontSize: 11, color: UellowColors.muted,
                  fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  Widget _badge(String t, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
            color: bg, borderRadius: BorderRadius.circular(999)),
        child: Text(t, style: TextStyle(fontSize: 10.5,
            fontWeight: FontWeight.w800, color: fg)),
      );

  String _remaining(bool ar, dynamic iso) {
    final e = DateTime.tryParse(iso.toString());
    if (e == null) return '';
    final diff = e.difference(DateTime.now());
    if (diff.isNegative) return ar ? 'انتهت' : 'ended';
    if (diff.inDays >= 1) {
      return ar ? 'ينتهي خلال ${diff.inDays} يوم' : '${diff.inDays}d left';
    }
    if (diff.inHours >= 1) {
      return ar ? 'ينتهي خلال ${diff.inHours} ساعة' : '${diff.inHours}h left';
    }
    return ar ? 'ينتهي خلال ${diff.inMinutes} دقيقة' : '${diff.inMinutes}m left';
  }

  String? _fmtDate(dynamic iso) {
    if (iso == null) return null;
    final d = DateTime.tryParse(iso.toString());
    if (d == null) return null;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }
}
