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
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
                color: const Color(0xFFF3EFE6),
                borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.campaign_rounded, size: 22,
                color: Color(0xFFE8820A)),
          ),
          const SizedBox(width: 11),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14,
                    fontWeight: FontWeight.w900, color: UellowColors.ink)),
            const SizedBox(height: 2),
            Text('$pc ${ar ? 'منتج' : 'products'}',
                style: const TextStyle(fontSize: 11,
                    fontWeight: FontWeight.w600, color: UellowColors.muted)),
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
        ]),
      ]),
    );
  }

  Widget _badge(String t, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
            color: bg, borderRadius: BorderRadius.circular(999)),
        child: Text(t, style: TextStyle(fontSize: 10.5,
            fontWeight: FontWeight.w800, color: fg)),
      );

  String? _fmtDate(dynamic iso) {
    if (iso == null) return null;
    final d = DateTime.tryParse(iso.toString());
    if (d == null) return null;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }
}
