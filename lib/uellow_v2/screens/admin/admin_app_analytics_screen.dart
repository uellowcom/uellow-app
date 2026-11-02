// =============================================================================
// AdminAppAnalyticsScreen (v2.2.169) — تحليلات التطبيق:
// • «في الفترة المختارة» = مقاييس تتأثّر بالفلتر + مقارنة بالفترة السابقة (deltas)
// • «النشاط الآن» = متدحرج مستقل عن الفلتر (DAU/WAU/MAU/متصل)
// • أرقام صحيحة: النشطون/التثبيتات بالأجهزة (device_id)، القمع بـ screen_view فقط
// • فلتر نطاق مخصّص من→إلى + ترويسة واضحة بالفترة والمدى.
// المصدر: /api/mobile/v2/admin/app-analytics.
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
  String? _dateFrom; // نطاق مخصّص — من
  String? _dateTo; // نطاق مخصّص — إلى
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
      _data = await AdminApi.instance.appAnalytics(
          period: _period, dateFrom: _dateFrom, dateTo: _dateTo);
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
            tooltip: ar ? 'تصدير الملخّص' : 'Export summary',
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
    final pk = (d['period_kpi'] as Map?) ?? const {};
    final delta = (d['delta'] as Map?) ?? const {};
    final active = (d['active'] as Map?) ?? const {};
    final installs = (d['installs'] as Map?) ?? const {};
    final notif = (d['notifications'] as Map?) ?? const {};
    int gi(Map m, String k) => (m[k] as num?)?.toInt() ?? 0;
    double? gd(Map m, String k) => (m[k] as num?)?.toDouble();

    final plabel = (d['period_label'] as Map?) ?? const {};
    final range = (d['range'] as Map?) ?? const {};
    final rangeTxt = (range['from'] != null && range['to'] != null)
        ? (ar
            ? 'من ${range['from']} إلى ${range['to']}'
            : '${range['from']} → ${range['to']}')
        : '';

    return [
      _periodChips(ar),
      const SizedBox(height: 8),
      // ترويسة واضحة: الفترة والمدى
      Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 11),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFF3B2B10), Color(0xFF5A4316)],
              begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.insights_rounded,
                color: Color(0xFFF5C320), size: 17),
            const SizedBox(width: 7),
            Text(
                (plabel[ar ? 'ar' : 'en'] ??
                        (ar ? 'الفترة المختارة' : 'Selected period'))
                    .toString(),
                style: const TextStyle(color: Colors.white, fontSize: 14,
                    fontWeight: FontWeight.w900)),
          ]),
          if (rangeTxt.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(rangeTxt, style: const TextStyle(
                color: Color(0xFFE8D9B5), fontSize: 11.5,
                fontWeight: FontWeight.w600)),
          ],
        ]),
      ),
      const SizedBox(height: 12),

      // ── في الفترة المختارة (تتأثّر بالفلتر + مقارنة) ──
      _subhd(ar ? '📊 في الفترة المختارة · مقارنةً بالفترة السابقة'
                : '📊 Selected period · vs previous period'),
      _kpiGrid([
        _Kpi(ar ? '📱 أجهزة نشطة' : '📱 Active devices',
            '${gi(pk, 'active_devices')}', const Color(0xFF2563EB),
            delta: gd(delta, 'active_devices')),
        _Kpi(ar ? '🆕 أجهزة جديدة' : '🆕 New devices',
            '${gi(pk, 'new_devices')}', const Color(0xFF16A34A),
            delta: gd(delta, 'new_devices')),
        _Kpi(ar ? '👆 فتحات التطبيق' : '👆 App opens',
            '${gi(pk, 'opens')}', UellowColors.darkBrown,
            delta: gd(delta, 'opens')),
        _Kpi(ar ? '🧾 الجلسات' : '🧾 Sessions',
            '${gi(pk, 'sessions')}', const Color(0xFF1D5FB4),
            delta: gd(delta, 'sessions')),
        _Kpi(ar ? '🛒 الطلبات' : '🛒 Orders',
            '${gi(pk, 'orders')}', const Color(0xFFB45309),
            delta: gd(delta, 'orders')),
        _Kpi(ar ? '🔑 مسجّلون دخلوا' : '🔑 Logged-in',
            '${gi(pk, 'logins')}', const Color(0xFF7C3AED)),
      ]),
      Padding(
        padding: const EdgeInsets.only(top: 6, right: 2, left: 2),
        child: Text(
            ar ? 'السهم والنسبة = التغيّر مقابل نفس عدد الأيام قبل هذه الفترة.'
               : 'Arrow & % = change vs the same number of days before.',
            style: const TextStyle(fontSize: 10.5, color: UellowColors.muted,
                fontWeight: FontWeight.w600)),
      ),
      const SizedBox(height: 12),

      // ── النشاط الآن (متدحرج مستقل عن الفلتر) ──
      _subhd(ar ? '⚡ النشاط الآن · لا يتأثّر بالفلتر'
                : '⚡ Live activity · independent of filter'),
      _kpiGrid([
        _Kpi(ar ? '🟢 متصل الآن' : '🟢 Online now',
            '${gi(active, 'online')}', const Color(0xFF16A34A)),
        _Kpi(ar ? '📅 نشطون اليوم' : '📅 DAU (today)',
            '${gi(active, 'dau')}', UellowColors.darkBrown),
        _Kpi(ar ? '🗓️ آخر ٧ أيام' : '🗓️ WAU (7d)',
            '${gi(active, 'wau')}', UellowColors.darkBrown),
        _Kpi(ar ? '📆 آخر ٣٠ يوم' : '📆 MAU (30d)',
            '${gi(active, 'mau')}', UellowColors.darkBrown),
        _Kpi(ar ? '⬇️ أجهزة مثبّتة (تقديري)' : '⬇️ Installs (est.)',
            '${gi(installs, 'devices')}', const Color(0xFF2563EB)),
        _Kpi(ar ? '🔔 مفعّلو الإشعارات' : '🔔 Push-enabled',
            '${gi(installs, 'push_users')}', const Color(0xFF16A34A)),
        _Kpi(ar ? '🆕 أجهزة جديدة اليوم' : '🆕 New today',
            '${gi(installs, 'new_today')}', const Color(0xFF16A34A)),
        _Kpi(ar ? '🧮 إجمالي الجلسات' : '🧮 Total sessions',
            '${gi(installs, 'sessions_total')}', const Color(0xFF1D5FB4)),
      ]),

      if ((installs['store_synced_at'] ?? '').toString().isNotEmpty) ...[
        const SizedBox(height: 10),
        _subhd(ar
            ? '🏬 من المتجر · مُزامَن ${installs['store_synced_at']}'
            : '🏬 From store · synced ${installs['store_synced_at']}'),
        _kpiGrid([
          _Kpi(ar ? '⬇️ تحميلات المتجر' : '⬇️ Store downloads',
              '${gi(installs, 'store_downloads')}', const Color(0xFF2563EB)),
          _Kpi(ar ? '❌ ألغوا التثبيت' : '❌ Uninstalls',
              '${gi(installs, 'store_uninstalls')}', const Color(0xFFC23B2B)),
        ]),
      ],

      _card(ar ? '📈 الأجهزة النشطة · آخر ١٤ يوم' : '📈 Active devices · 14 days',
          _barChart((d['dau_series'] as List?) ?? const [])),
      _card(ar ? '🧭 المسار داخل التطبيق (الفترة)' : '🧭 In-app behaviour',
          _funnel((d['funnel'] as List?) ?? const [], ar)),
      if (((d['acq_funnel'] as List?) ?? const []).isNotEmpty)
        _card(ar ? '📥 قمع الاكتساب (نشِط→مسجّل→مشترٍ)'
                 : '📥 Acquisition funnel',
            _funnel((d['acq_funnel'] as List?) ?? const [], ar)),
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
                _kvRow(ar ? 'جلسات لكل جهاز' : 'Sessions per device',
                    '${((d['sessions'] as Map)['per_user'] ?? 0)}'),
              ],
            ])),
      _card(ar ? '📱 المنصّات (الفترة)' : '📱 Platforms',
          _splitBars((d['platforms'] as List?) ?? const [])),
      if (((d['languages'] as List?) ?? const []).isNotEmpty)
        _card(ar ? '🗣️ اللغات (الفترة)' : '🗣️ Languages',
            _splitBars(_langRows((d['languages'] as List?) ?? const [], ar))),
      if (((d['versions'] as List?) ?? const []).isNotEmpty)
        _card(ar ? '🔖 الإصدارات (الفترة)' : '🔖 App versions',
            _kvList((d['versions'] as List?) ?? const [], 'name', 'count')),
      _card(ar ? '🔔 الإشعارات (الفترة)' : '🔔 Notifications',
          Column(children: [
        _kvRow(ar ? 'مُرسلة' : 'Sent', '${gi(notif, 'sent')}'),
        _kvRow(ar ? 'وصلت' : 'Delivered', '${gi(notif, 'delivered')}'),
        _kvRow(ar ? 'فُتحت' : 'Opened', '${gi(notif, 'opened')}'),
      ])),
      if (((d['geo'] as List?) ?? const []).isNotEmpty)
        _card(ar ? '🌍 التوزيع الجغرافي (الفترة)' : '🌍 Geography',
            _kvList((d['geo'] as List?) ?? const [], 'country', 'count')),
    ];
  }

  List _langRows(List rows, bool ar) {
    String nm(String c) {
      switch (c) {
        case 'ar': return ar ? 'العربية' : 'Arabic';
        case 'en': return ar ? 'الإنجليزية' : 'English';
        default: return c;
      }
    }
    return [
      for (final r in rows)
        {'name': nm(((r as Map)['name'] ?? '—').toString()),
         'count': r['count'] ?? 0}
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
    Widget chip(bool on, String label, VoidCallback onTap) => Padding(
          padding: const EdgeInsetsDirectional.only(end: 7),
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: on ? const Color(0xFFE8A800) : Colors.white,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: on
                    ? const Color(0xFFE8A800) : const Color(0xFFE5E5E5)),
              ),
              child: Text(label, style: TextStyle(fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: on ? const Color(0xFF2A1D00) : UellowColors.muted)),
            ),
          ),
        );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (final o in opts)
          chip(_period == o.$1, o.$2, () {
            if (_period != o.$1) {
              _period = o.$1;
              _dateFrom = null;
              _dateTo = null;
              _load();
            }
          }),
        chip(_period == 'custom', ar ? '📅 مخصّص' : '📅 Custom',
            _pickCustomRange),
      ]),
    );
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: DateTimeRange(
          start: now.subtract(const Duration(days: 29)), end: now),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.light(
                primary: UellowColors.darkBrown,
                onPrimary: Colors.white)),
        child: child!,
      ),
    );
    if (picked != null) {
      String f(DateTime x) =>
          '${x.year}-${x.month.toString().padLeft(2, '0')}-'
          '${x.day.toString().padLeft(2, '0')}';
      _dateFrom = f(picked.start);
      _dateTo = f(picked.end);
      _period = 'custom';
      _load();
    }
  }

  Future<void> _export() async {
    final d = _data ?? const {};
    final pk = (d['period_kpi'] as Map?) ?? const {};
    final active = (d['active'] as Map?) ?? const {};
    final range = (d['range'] as Map?) ?? const {};
    final ar = _ar;
    final txt = StringBuffer()
      ..writeln(ar ? 'تقرير تحليلات التطبيق' : 'App analytics report')
      ..writeln('range: ${range['from']} → ${range['to']}')
      ..writeln('active_devices: ${pk['active_devices'] ?? 0}')
      ..writeln('new_devices: ${pk['new_devices'] ?? 0}')
      ..writeln('opens: ${pk['opens'] ?? 0}')
      ..writeln('sessions: ${pk['sessions'] ?? 0}')
      ..writeln('orders: ${pk['orders'] ?? 0}')
      ..writeln('— live —')
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
        childAspectRatio: 2.15,
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
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(k.value, style: TextStyle(fontSize: 20,
                fontWeight: FontWeight.w900, color: k.color)),
            if (k.delta != null) ...[
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: _deltaChip(k.delta!),
              ),
            ],
          ]),
        ]),
      );

  Widget _deltaChip(double pct) {
    final up = pct >= 0;
    final flat = pct.abs() < 0.05;
    final color = flat
        ? UellowColors.muted
        : (up ? const Color(0xFF16A34A) : const Color(0xFFC23B2B));
    final icon = flat
        ? Icons.remove_rounded
        : (up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 10, color: color),
        const SizedBox(width: 1),
        Text('${pct.abs().toStringAsFixed(pct.abs() >= 100 ? 0 : 1)}%',
            style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900,
                color: color)),
      ]),
    );
  }

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
  _Kpi(this.label, this.value, this.color, {this.delta});
  final String label;
  final String value;
  final Color color;
  final double? delta;
}
