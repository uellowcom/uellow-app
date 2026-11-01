// =============================================================================
// AdminAppAnalyticsScreen (v2.2.146) — تحليلات التطبيق الشاملة:
// التثبيتات/النشطون/الفتحات + DAU 14 يوم + المنصّات + الإصدارات + القمع +
// الإشعارات + التوزيع الجغرافي. المصدر: /api/mobile/v2/admin/app-analytics.
// =============================================================================
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../api/uellow_api.dart';
import '../../services/admin_mode.dart';
import '../../theme/uellow_theme.dart';

class AdminAppAnalyticsScreen extends StatefulWidget {
  const AdminAppAnalyticsScreen({super.key});
  @override
  State<AdminAppAnalyticsScreen> createState() =>
      _AdminAppAnalyticsScreenState();
}

class _AdminAppAnalyticsScreenState extends State<AdminAppAnalyticsScreen> {
  String _period = '30d';
  String? _dateFrom; // v2.2.152 — نطاق مخصّص
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      _data = await AdminApi.instance
          .appAnalytics(period: _period, dateFrom: _dateFrom);
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
    }
    if (mounted) setState(() => _loading = false);
  }

  bool get _ar => UellowApi.instance.lang == 'ar';

  @override
  Widget build(BuildContext context) {
    final ar = _ar;
    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F5),
      appBar: AppBar(
        backgroundColor: UellowColors.darkBrown,
        foregroundColor: Colors.white,
        title: Text(ar ? 'تحليلات التطبيق' : 'App analytics',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
        actions: [
          IconButton(
            tooltip: ar ? 'مزامنة أرقام المتجر' : 'Sync store numbers',
            onPressed: _storeSync,
            icon: const Icon(Icons.sync_rounded),
          ),
          IconButton(
            tooltip: ar ? 'تصدير التقرير' : 'Export report',
            onPressed: _export,
            icon: const Icon(Icons.ios_share_rounded),
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
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 30),
                    children: _body(ar),
                  ),
                ),
    );
  }

  List<Widget> _body(bool ar) {
    final d = _data ?? const {};
    final active = (d['active'] as Map?) ?? const {};
    final installs = (d['installs'] as Map?) ?? const {};
    final opens = (d['opens'] as Map?) ?? const {};
    final notif = (d['notifications'] as Map?) ?? const {};
    int gi(Map m, String k) => (m[k] as num?)?.toInt() ?? 0;
    return [
      _periodChips(ar),
      const SizedBox(height: 10),
      _subhd(ar ? 'التثبيت والنشاط' : 'Installs & activity'),
      _kpiGrid([
        _Kpi(ar ? '⬇️ أجهزة مثبّتة' : '⬇️ Installs',
            '${gi(installs, 'downloads')}', const Color(0xFF2563EB)),
        _Kpi(ar ? '🆕 تثبيتات اليوم' : '🆕 New today',
            '${gi(installs, 'new_today')}', const Color(0xFF16A34A)),
        _Kpi(ar ? '📲 عندهم التطبيق' : '📲 Have the app',
            '${gi(installs, 'push_users')}', const Color(0xFF16A34A)),
        _Kpi(ar ? '🟢 متصل الآن' : '🟢 Online now',
            '${gi(active, 'online')}', const Color(0xFF16A34A)),
        _Kpi(ar ? '📅 نشطون اليوم (DAU)' : '📅 DAU',
            '${gi(active, 'dau')}', UellowColors.darkBrown),
        _Kpi(ar ? '🗓️ هذا الأسبوع (WAU)' : '🗓️ WAU',
            '${gi(active, 'wau')}', UellowColors.darkBrown),
        _Kpi(ar ? '📆 هذا الشهر (MAU)' : '📆 MAU',
            '${gi(active, 'mau')}', UellowColors.darkBrown),
        _Kpi(ar ? '🧾 إجمالي الجلسات' : '🧾 Sessions',
            '${gi(installs, 'sessions_total')}', const Color(0xFF1D5FB4)),
      ]),
      if ((installs['store_synced_at'] ?? '').toString().isNotEmpty) ...[
        const SizedBox(height: 6),
        _subhd(ar
            ? 'من المتجر (مُزامَن ${installs['store_synced_at']})'
            : 'From store (synced ${installs['store_synced_at']})'),
        _kpiGrid([
          _Kpi(ar ? '⬇️ تحميلات المتجر' : '⬇️ Store downloads',
              '${gi(installs, 'store_downloads')}', const Color(0xFF2563EB)),
          _Kpi(ar ? '❌ ألغوا التثبيت' : '❌ Uninstalls',
              '${gi(installs, 'store_uninstalls')}', const Color(0xFFC23B2B)),
        ]),
      ],
      const SizedBox(height: 6),
      _subhd(ar ? 'فتحات التطبيق' : 'App opens'),
      _kpiGrid([
        _Kpi(ar ? 'اليوم' : 'Today', '${gi(opens, 'today')}',
            UellowColors.darkBrown),
        _Kpi(ar ? '٧ أيام' : '7 days', '${gi(opens, 'week')}',
            UellowColors.darkBrown),
        _Kpi(ar ? '٣٠ يوم' : '30 days', '${gi(opens, 'month')}',
            UellowColors.darkBrown),
      ]),
      const SizedBox(height: 6),
      if (d['retention'] is Map || d['sessions'] is Map)
        _card(ar ? '🔁 الاحتفاظ والجلسات' : '🔁 Retention & sessions',
            Column(children: [
              if (d['retention'] is Map) ...[
                _kvRow(ar ? 'العائدون بعد ٧ أيام' : 'Returning after 7d',
                    '${gi(d['retention'] as Map, 'd7')}%'),
                _kvRow(ar ? 'العائدون بعد ٣٠ يوم' : 'Returning after 30d',
                    '${gi(d['retention'] as Map, 'd30')}%'),
              ],
              if (d['sessions'] is Map) ...[
                _kvRow(ar ? 'متوسط مدة الجلسة (دقيقة)' : 'Avg session (min)',
                    '${((d['sessions'] as Map)['avg_minutes'] ?? 0)}'),
                _kvRow(ar ? 'جلسات لكل مستخدم' : 'Sessions per user',
                    '${((d['sessions'] as Map)['per_user'] ?? 0)}'),
              ],
            ])),
      _card(ar ? '📈 الجلسات آخر ١٤ يوم' : '📈 Sessions (14 days)',
          _barChart((d['dau_series'] as List?) ?? const [])),
      _card(ar ? '🧭 المسار السلوكي داخل التطبيق' : '🧭 In-app behaviour',
          _funnel((d['funnel'] as List?) ?? const [], ar)),
      if (((d['acq_funnel'] as List?) ?? const []).isNotEmpty)
        _card(ar ? '📥 مسار الاكتساب (تثبيت→فتح→تسجيل→شراء)'
                 : '📥 Acquisition funnel',
            _funnel((d['acq_funnel'] as List?) ?? const [], ar)),
      _card(ar ? '📱 المنصّات' : '📱 Platforms',
          _splitBars((d['platforms'] as List?) ?? const [])),
      if (((d['versions'] as List?) ?? const []).isNotEmpty)
        _card(ar ? '🔖 الإصدارات' : 'App versions',
            _kvList((d['versions'] as List?) ?? const [], 'name', 'count')),
      _card(ar ? '🔔 الإشعارات' : 'Notifications', Column(children: [
        _kvRow(ar ? 'مُرسلة' : 'Sent', '${gi(notif, 'sent')}'),
        _kvRow(ar ? 'وصلت' : 'Delivered', '${gi(notif, 'delivered')}'),
        _kvRow(ar ? 'فُتحت' : 'Opened', '${gi(notif, 'opened')}'),
      ])),
      if (((d['geo'] as List?) ?? const []).isNotEmpty)
        _card(ar ? '🌍 التوزيع الجغرافي' : 'Geography',
            _kvList((d['geo'] as List?) ?? const [], 'country', 'count')),
    ];
  }

  // ── pieces ──
  Widget _periodChips(bool ar) {
    final opts = <(String, String)>[
      ('today', ar ? 'اليوم' : 'Today'),
      ('7d', ar ? '٧ أيام' : '7 days'),
      ('30d', ar ? '٣٠ يوم' : '30 days'),
      ('all', ar ? 'كل الوقت' : 'All time'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (final o in opts) Padding(
          padding: const EdgeInsetsDirectional.only(end: 7),
          child: GestureDetector(
            onTap: () { if (_period != o.$1) { _period = o.$1; _load(); } },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _period == o.$1 ? const Color(0xFFE8A800) : Colors.white,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: _period == o.$1
                    ? const Color(0xFFE8A800) : const Color(0xFFE5E5E5)),
              ),
              child: Text(o.$2, style: TextStyle(fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: _period == o.$1
                      ? const Color(0xFF2A1D00) : UellowColors.muted)),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.only(end: 7),
          child: GestureDetector(
            onTap: _pickCustomRange,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _period == 'custom'
                    ? const Color(0xFFE8A800) : Colors.white,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: _period == 'custom'
                    ? const Color(0xFFE8A800) : const Color(0xFFE5E5E5)),
              ),
              child: Text(ar ? '📅 مخصّص' : '📅 Custom',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
                      color: _period == 'custom'
                          ? const Color(0xFF2A1D00) : UellowColors.muted)),
            ),
          ),
        ),
      ]),
    );
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context, firstDate: DateTime(now.year - 2),
      lastDate: now, initialDate: now.subtract(const Duration(days: 30)));
    if (picked != null) {
      _dateFrom =
          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-'
          '${picked.day.toString().padLeft(2, '0')}';
      _period = 'custom';
      _load();
    }
  }

  Future<void> _export() async {
    final d = _data ?? const {};
    final installs = (d['installs'] as Map?) ?? const {};
    final active = (d['active'] as Map?) ?? const {};
    final ar = _ar;
    final txt = StringBuffer()
      ..writeln(ar ? 'تقرير تحليلات التطبيق' : 'App analytics report')
      ..writeln('period: ${d['period'] ?? _period}')
      ..writeln('installs: ${installs['downloads'] ?? 0}')
      ..writeln('new_today: ${installs['new_today'] ?? 0}')
      ..writeln('online: ${active['online'] ?? 0}')
      ..writeln('dau: ${active['dau'] ?? 0}  wau: ${active['wau'] ?? 0}'
          '  mau: ${active['mau'] ?? 0}');
    await Clipboard.setData(ClipboardData(text: txt.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ar ? 'تم نسخ ملخّص التقرير'
                            : 'Report summary copied')));
    }
  }

  Future<void> _storeSync() async {
    final ar = _ar;
    final inst = (_data?['installs'] as Map?) ?? const {};
    final dlC = TextEditingController(
        text: '${(inst['store_downloads'] as num?)?.toInt() ?? ''}');
    final unC = TextEditingController(
        text: '${(inst['store_uninstalls'] as num?)?.toInt() ?? ''}');
    final go = await showDialog<bool>(context: context, builder: (c) =>
        AlertDialog(
          title: Text(ar ? '🔄 مزامنة أرقام المتجر' : '🔄 Sync store numbers'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(ar
                ? 'أدخل الأرقام من Play Console / App Store Connect.'
                : 'Enter totals from Play Console / App Store Connect.',
                style: const TextStyle(fontSize: 12,
                    color: UellowColors.muted)),
            const SizedBox(height: 10),
            TextField(controller: dlC, keyboardType: TextInputType.number,
                decoration: InputDecoration(
                    labelText: ar ? 'إجمالي التحميلات' : 'Total downloads')),
            const SizedBox(height: 8),
            TextField(controller: unC, keyboardType: TextInputType.number,
                decoration: InputDecoration(
                    labelText: ar ? 'إجمالي إلغاء التثبيت' : 'Total uninstalls')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false),
                child: Text(ar ? 'إلغاء' : 'Cancel')),
            TextButton(onPressed: () => Navigator.pop(c, true),
                child: Text(ar ? 'حفظ' : 'Save')),
          ],
        ));
    if (go == true) {
      try {
        await AdminApi.instance.storeSync(
            int.tryParse(dlC.text.trim()) ?? 0,
            int.tryParse(unC.text.trim()) ?? 0);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(ar ? 'تم حفظ أرقام المتجر' : 'Store numbers saved')));
          _load();
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: UellowColors.danger));
      }
    }
  }

  Widget _subhd(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 6, 2, 8),
        child: Text(t, style: const TextStyle(fontSize: 12,
            fontWeight: FontWeight.w900, color: UellowColors.muted)),
      );

  Widget _kpiGrid(List<_Kpi> kpis) => GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2, crossAxisSpacing: 9, mainAxisSpacing: 9,
        childAspectRatio: 2.4,
        children: [for (final k in kpis) _kpiCard(k)],
      );

  Widget _kpiCard(_Kpi k) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFECECEC))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(k.label, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11,
                  fontWeight: FontWeight.w700, color: UellowColors.muted)),
          const SizedBox(height: 3),
          Text(k.value, style: TextStyle(fontSize: 20,
              fontWeight: FontWeight.w900, color: k.color)),
        ]),
      );

  Widget _card(String title, Widget child) => Container(
        margin: const EdgeInsets.only(top: 11),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFECECEC))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 13,
              fontWeight: FontWeight.w900, color: UellowColors.darkBrown)),
          const SizedBox(height: 10),
          child,
        ]),
      );

  Widget _barChart(List series) {
    if (series.isEmpty) return const SizedBox.shrink();
    final vals = series
        .map((e) => ((e as Map)['count'] as num?)?.toInt() ?? 0)
        .toList();
    final maxV = (vals.isEmpty ? 1 : vals.reduce((a, b) => a > b ? a : b))
        .clamp(1, 1 << 30);
    return SizedBox(
      height: 110,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end,
          children: [
        for (var i = 0; i < vals.length; i++)
          Expanded(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1.5),
            child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
              Text('${vals[i]}', style: const TextStyle(fontSize: 7.5,
                  fontWeight: FontWeight.w700, color: UellowColors.muted)),
              const SizedBox(height: 2),
              Container(
                height: (vals[i] / maxV * 80).clamp(2, 80).toDouble(),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      colors: [Color(0xFFF5C320), Color(0xFFE8A800)]),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ]),
          )),
      ]),
    );
  }

  Widget _funnel(List rows, bool ar) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final first = ((rows.first as Map)['count'] as num?)?.toInt() ?? 0;
    final base = first <= 0 ? 1 : first;
    return Column(children: [
      for (final r in rows) ...[
        Builder(builder: (_) {
          final m = r as Map;
          final lbl = m['label'];
          final label = lbl is Map
              ? (lbl[ar ? 'ar' : 'en'] ?? lbl['en'] ?? '').toString()
              : (lbl?.toString() ?? '');
          final c = (m['count'] as num?)?.toInt() ?? 0;
          final pct = (c / base * 100).clamp(0, 100).toDouble();
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              SizedBox(width: 96, child: Text(label,
                  style: const TextStyle(fontSize: 11,
                      fontWeight: FontWeight.w700, color: UellowColors.ink))),
              Expanded(child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Stack(children: [
                  Container(height: 20, color: const Color(0xFFF1EEE7)),
                  FractionallySizedBox(
                    widthFactor: (pct / 100).clamp(0.02, 1),
                    child: Container(height: 20,
                        decoration: const BoxDecoration(
                            gradient: LinearGradient(colors: [
                          Color(0xFFF5C320), Color(0xFFE8A800)
                        ]))),
                  ),
                ]),
              )),
              SizedBox(width: 52, child: Text('  $c',
                  style: const TextStyle(fontSize: 11,
                      fontWeight: FontWeight.w800))),
            ]),
          );
        }),
      ],
    ]);
  }

  Widget _splitBars(List rows) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final total = rows.fold<int>(
        0, (s, e) => s + (((e as Map)['count'] as num?)?.toInt() ?? 0));
    final base = total <= 0 ? 1 : total;
    const colors = [Color(0xFF16A34A), Color(0xFF1D5FB4), Color(0xFFE8A800),
        Color(0xFFC23B2B)];
    return Column(children: [
      for (var i = 0; i < rows.length; i++) Builder(builder: (_) {
        final m = rows[i] as Map;
        final name = (m['name'] ?? '—').toString();
        final c = (m['count'] as num?)?.toInt() ?? 0;
        final pct = (c / base * 100);
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            SizedBox(width: 72, child: Text(name,
                style: const TextStyle(fontSize: 11,
                    fontWeight: FontWeight.w700))),
            Expanded(child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Stack(children: [
                Container(height: 18, color: const Color(0xFFF1EEE7)),
                FractionallySizedBox(
                  widthFactor: (pct / 100).clamp(0.02, 1),
                  child: Container(height: 18,
                      color: colors[i % colors.length]),
                ),
              ]),
            )),
            SizedBox(width: 64, child: Text('  $c (${pct.toStringAsFixed(0)}%)',
                style: const TextStyle(fontSize: 10.5,
                    fontWeight: FontWeight.w800))),
          ]),
        );
      }),
    ]);
  }

  Widget _kvList(List rows, String kField, String vField) => Column(
        children: [
          for (final r in rows)
            _kvRow(((r as Map)[kField] ?? '—').toString(),
                '${r[vField] ?? 0}'),
        ],
      );

  Widget _kvRow(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(k, style: const TextStyle(fontSize: 12,
              fontWeight: FontWeight.w600, color: UellowColors.ink))),
          Text(v, style: const TextStyle(fontSize: 13,
              fontWeight: FontWeight.w900, color: UellowColors.darkBrown)),
        ]),
      );
}

class _Kpi {
  _Kpi(this.label, this.value, this.color);
  final String label;
  final String value;
  final Color color;
}
