// =============================================================================
// SmartFitScreen (v2.1.77) — "مقاسي الذكي" / Smart Fit.
// Three states:
//   • guest      → benefits + an illustrated figure + "register measurements"
//   • no profile → prompt to fill measurements
//   • ready      → a PAINTED body figure (male/female, slim→plus) whose
//                  zones turn green (comfortable) / red (tight) / orange
//                  (loose) for the chosen product + size, with per-area
//                  bars, an overall ring and a size chip ladder.
// Data: POST /api/mobile/v2/fit/check { product_id? }.
// =============================================================================
import 'package:flutter/material.dart';

import '../../api/uellow_api.dart';
import '../theme/uellow_theme.dart';

const _cTight = Color(0xFFD2604E);      // red — too tight
const _cComfort = Color(0xFF2E9E6B);    // green — comfortable
const _cLoose = Color(0xFFE6A817);      // amber — loose
const _cUnknown = Color(0xFFCBD2CF);    // grey — unknown

class SmartFitScreen extends StatefulWidget {
  const SmartFitScreen({super.key, this.productId});
  final int? productId;
  @override
  State<SmartFitScreen> createState() => _SmartFitScreenState();
}

class _SmartFitScreenState extends State<SmartFitScreen> {
  bool _loading = true;
  bool _guest = false;
  Map<String, dynamic>? _data;   // /fit/check response

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final token = await UellowApi.instance.tokenStore.readToken();
    if (token == null || token.isEmpty) {
      if (mounted) setState(() { _guest = true; _loading = false; });
      return;
    }
    try {
      final res = await UellowApi.instance.postRaw(
          '/api/mobile/v2/fit/check', auth: true,
          body: {if (widget.productId != null) 'product_id': widget.productId});
      if (mounted) setState(() { _data = (res['data'] as Map?)?.cast<String, dynamic>(); _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: UellowColors.bg,
        appBar: AppBar(
          backgroundColor: Colors.white,
          leading: const BackButton(color: UellowColors.darkBrown),
          title: Text(ar ? '📐 مقاسي الذكي' : '📐 Smart Fit',
              style: const TextStyle(color: UellowColors.ink,
                  fontWeight: FontWeight.w900, fontSize: 16)),
        ),
        body: SafeArea(child: _loading
            ? const Center(child: CircularProgressIndicator(
                color: UellowColors.darkBrown))
            : _guest
                ? _GuestPitch(ar: ar)
                : ((_data?['has_profile'] != true)
                    ? _NoProfile(ar: ar, onSaved: _load)
                    : _Ready(ar: ar, data: _data!, onRefresh: _load))),
      ),
    );
  }
}

// ─── Guest: benefits + illustrated figure + register CTA ─────────────
class _GuestPitch extends StatelessWidget {
  const _GuestPitch({required this.ar});
  final bool ar;
  @override
  Widget build(BuildContext context) {
    final benefits = ar
        ? ['اعرف مقاسك الصحيح قبل الشراء',
           'شكل جسم يوضح أين يضيق وأين يتّسع',
           'توصية بالمقاس المثالي لكل منتج',
           'تقليل الإرجاع بسبب المقاس']
        : ['Know your right size before buying',
           'A body figure showing where it is tight or loose',
           'The ideal size recommended per product',
           'Fewer returns due to wrong size'];
    return ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
        children: [
      SizedBox(height: 220, child: CustomPaint(
          painter: _BodyPainter(gender: 'male', bodyType: 'regular',
              zones: const {}, faded: true),
          child: const SizedBox.expand())),
      const SizedBox(height: 8),
      Text(ar ? 'سجّل مقاساتك مرّة واحدة' : 'Register your measurements once',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900,
              color: UellowColors.ink)),
      const SizedBox(height: 6),
      Text(ar
          ? 'ندرس مقاساتك مع كل منتج ونوضّح لك على شكل جسمك إن كان المقاس مناسباً أم ضيقاً أم واسعاً — في أي منطقة بالضبط.'
          : 'We compare your measurements with each product and show — right on your body figure — whether the size is perfect, tight or loose, and exactly where.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, height: 1.6,
              color: UellowColors.muted)),
      const SizedBox(height: 18),
      for (final b in benefits) Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Container(width: 26, height: 26, alignment: Alignment.center,
            decoration: BoxDecoration(color: _cComfort.withValues(alpha: .14),
                shape: BoxShape.circle),
            child: const Icon(Icons.check, size: 15, color: _cComfort)),
          const SizedBox(width: 10),
          Expanded(child: Text(b, style: const TextStyle(fontSize: 13.5,
              fontWeight: FontWeight.w600, color: UellowColors.text))),
        ]),
      ),
      const SizedBox(height: 14),
      SizedBox(width: double.infinity, child: ElevatedButton.icon(
        onPressed: () => Navigator.pushNamed(context, '/auth'),
        icon: const Icon(Icons.login, size: 18),
        label: Text(ar ? 'سجّل الدخول وأدخل مقاساتك' : 'Sign in & add measurements',
            style: const TextStyle(fontWeight: FontWeight.w900)),
        style: ElevatedButton.styleFrom(
          backgroundColor: UellowColors.yellow,
          foregroundColor: UellowColors.darkBrown, elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
        ),
      )),
    ]);
  }
}

// ─── Logged in but no measurements yet ───────────────────────────────
class _NoProfile extends StatelessWidget {
  const _NoProfile({required this.ar, required this.onSaved});
  final bool ar;
  final VoidCallback onSaved;
  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
        children: [
      SizedBox(height: 200, child: CustomPaint(
          painter: _BodyPainter(gender: 'male', bodyType: 'regular',
              zones: const {}, faded: true),
          child: const SizedBox.expand())),
      const SizedBox(height: 10),
      Text(ar ? 'أكمل مقاساتك لتفعيل المقاس الذكي'
              : 'Add your measurements to enable Smart Fit',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900,
              color: UellowColors.ink)),
      const SizedBox(height: 16),
      SizedBox(width: double.infinity, child: ElevatedButton.icon(
        onPressed: () async {
          await showModalBottomSheet(context: context, isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => _MeasureSheet(ar: ar));
          onSaved();
        },
        icon: const Icon(Icons.straighten, size: 18),
        label: Text(ar ? 'أدخل مقاساتي' : 'Enter my measurements',
            style: const TextStyle(fontWeight: FontWeight.w900)),
        style: ElevatedButton.styleFrom(
          backgroundColor: UellowColors.yellow,
          foregroundColor: UellowColors.darkBrown, elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      )),
    ]);
  }
}

// ─── Ready: body figure + analysis ───────────────────────────────────
class _Ready extends StatelessWidget {
  const _Ready({required this.ar, required this.data, required this.onRefresh});
  final bool ar;
  final Map<String, dynamic> data;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final gender = (data['gender'] ?? 'male').toString();
    final bodyType = (data['body_type'] ?? 'regular').toString();
    final areas = ((data['areas'] as List?) ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>()).toList();
    final sizes = ((data['sizes'] as List?) ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>()).toList();
    final overall = (data['overall_pct'] as num?)?.toInt() ?? 0;
    final rec = (data['recommended_size'] ?? '').toString();
    final hasProduct = data['product'] != null && areas.isNotEmpty;
    // map area.key → fit bucket for the painter
    final zones = <String, String>{
      for (final a in areas) (a['key'] ?? '').toString(): (a['fit'] ?? 'unknown').toString()
    };

    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
        children: [
      if (!hasProduct) Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: UellowColors.yellowFaint,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: UellowColors.yellow.withValues(alpha: .5))),
        child: Text(ar
            ? 'افتح أي منتج أزياء واضغط «المقاس الذكي» لترى مدى ملاءمته على شكل جسمك.'
            : 'Open any fashion product and tap “Smart Fit” to see how it fits on your body figure.',
            style: const TextStyle(fontSize: 12.5, height: 1.5,
                color: UellowColors.darkBrown)),
      ),
      // figure + overall ring
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white,
            borderRadius: BorderRadius.circular(18)),
        child: Column(children: [
          if (hasProduct) Row(children: [
            _OverallRing(pct: overall),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(ar ? 'المقاس الموصى به' : 'Recommended size',
                  style: const TextStyle(fontSize: 11,
                      color: UellowColors.muted, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(rec.isEmpty ? '—' : rec,
                  style: const TextStyle(fontSize: 26,
                      fontWeight: FontWeight.w900, color: UellowColors.ink)),
            ])),
          ]),
          if (hasProduct) const SizedBox(height: 6),
          SizedBox(height: 300, child: CustomPaint(
              painter: _BodyPainter(gender: gender, bodyType: bodyType,
                  zones: zones),
              child: const SizedBox.expand())),
          // legend
          Wrap(spacing: 12, runSpacing: 4, alignment: WrapAlignment.center,
              children: [
            _legend(_cComfort, ar ? 'مناسب' : 'Perfect'),
            _legend(_cTight, ar ? 'ضيّق' : 'Tight'),
            _legend(_cLoose, ar ? 'واسع' : 'Loose'),
          ]),
        ]),
      ),
      const SizedBox(height: 12),
      // per-area bars
      if (areas.isNotEmpty) Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
        decoration: BoxDecoration(color: Colors.white,
            borderRadius: BorderRadius.circular(18)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(ar ? 'تفصيل حسب المنطقة' : 'Area breakdown',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900,
                  color: UellowColors.ink)),
          const SizedBox(height: 10),
          for (final a in areas) _areaBar(a, ar),
        ]),
      ),
      const SizedBox(height: 12),
      // size ladder chips
      if (sizes.isNotEmpty) Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(color: Colors.white,
            borderRadius: BorderRadius.circular(18)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(ar ? 'كل المقاسات' : 'All sizes',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900,
                  color: UellowColors.ink)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final s in sizes) _sizeChip(s, ar),
          ]),
        ]),
      ),
      const SizedBox(height: 14),
      Center(child: TextButton.icon(
        onPressed: () async {
          await showModalBottomSheet(context: context, isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => _MeasureSheet(ar: ar));
          onRefresh();
        },
        icon: const Icon(Icons.edit_outlined, size: 16,
            color: UellowColors.darkBrown),
        label: Text(ar ? 'تعديل مقاساتي' : 'Edit my measurements',
            style: const TextStyle(color: UellowColors.darkBrown,
                fontWeight: FontWeight.w800)),
      )),
    ]);
  }

  Widget _legend(Color c, String t) => Row(mainAxisSize: MainAxisSize.min,
      children: [
    Container(width: 10, height: 10, decoration: BoxDecoration(color: c,
        shape: BoxShape.circle)),
    const SizedBox(width: 4),
    Text(t, style: const TextStyle(fontSize: 10.5, color: UellowColors.muted,
        fontWeight: FontWeight.w700)),
  ]);

  Widget _areaBar(Map<String, dynamic> a, bool ar) {
    final fit = (a['fit'] ?? 'unknown').toString();
    final pct = (a['pct'] as num?)?.toInt() ?? 0;
    final diff = (a['diff_cm'] as num?)?.toDouble() ?? 0;
    final label = ((a['label'] as Map?)?[ar ? 'ar' : 'en'] ?? a['key']).toString();
    final c = {'tight': _cTight, 'comfortable': _cComfort,
               'loose': _cLoose}[fit] ?? _cUnknown;
    final fitTxt = {
      'tight': ar ? 'ضيّق' : 'Tight',
      'comfortable': ar ? 'مناسب' : 'Perfect',
      'loose': ar ? 'واسع' : 'Loose',
    }[fit] ?? (ar ? '—' : '—');
    final diffTxt = diff == 0 ? '' :
        (diff > 0 ? '+${diff.toStringAsFixed(1)} cm' : '${diff.toStringAsFixed(1)} cm');
    return Padding(padding: const EdgeInsets.only(bottom: 12), child:
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12.5,
              fontWeight: FontWeight.w800, color: UellowColors.ink))),
          Text(fitTxt, style: TextStyle(fontSize: 11.5,
              fontWeight: FontWeight.w900, color: c)),
          if (diffTxt.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(diffTxt, style: const TextStyle(fontSize: 10.5,
                color: UellowColors.muted)),
          ],
        ]),
        const SizedBox(height: 5),
        ClipRRect(borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(value: (pct / 100).clamp(0, 1),
              minHeight: 7, backgroundColor: const Color(0xFFF0F0F0),
              valueColor: AlwaysStoppedAnimation(c))),
      ]),
    );
  }

  Widget _sizeChip(Map<String, dynamic> s, bool ar) {
    final size = (s['size'] ?? '').toString();
    final pct = (s['pct'] as num?)?.toInt() ?? 0;
    final isRec = s['recommended'] == true;
    final col = {'green': _cComfort, 'yellow': _cLoose, 'orange': _cLoose,
                 'red': _cTight}[(s['fit_color'] ?? '').toString()] ?? _cUnknown;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isRec ? col.withValues(alpha: .12) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isRec ? col : UellowColors.border,
            width: isRec ? 1.6 : 1),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Text(size, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900,
              color: isRec ? col : UellowColors.ink)),
          if (isRec) ...[
            const SizedBox(width: 4),
            const Icon(Icons.star, size: 12, color: _cComfort),
          ],
        ]),
        Text('$pct%', style: const TextStyle(fontSize: 10,
            color: UellowColors.muted, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _OverallRing extends StatelessWidget {
  const _OverallRing({required this.pct});
  final int pct;
  @override
  Widget build(BuildContext context) {
    final c = pct >= 85 ? _cComfort : (pct >= 60 ? _cLoose : _cTight);
    return SizedBox(width: 64, height: 64, child: Stack(
        alignment: Alignment.center, children: [
      SizedBox(width: 64, height: 64, child: CircularProgressIndicator(
          value: (pct / 100).clamp(0, 1), strokeWidth: 6,
          backgroundColor: const Color(0xFFEFEFEF),
          valueColor: AlwaysStoppedAnimation(c))),
      Text('$pct%', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900,
          color: c)),
    ]));
  }
}

// ─── The painted body figure ─────────────────────────────────────────
class _BodyPainter extends CustomPainter {
  _BodyPainter({required this.gender, required this.bodyType,
      required this.zones, this.faded = false});
  final String gender;       // male | female
  final String bodyType;     // slim | regular | athletic | plus
  final Map<String, String> zones;   // area key → tight|comfortable|loose
  final bool faded;

  Color _z(String key) {
    if (faded) return const Color(0xFFE3E8E6);
    final f = zones[key];
    if (f == 'tight') return _cTight;
    if (f == 'comfortable') return _cComfort;
    if (f == 'loose') return _cLoose;
    return _cUnknown;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final h = size.height;
    // width factor by body type
    final wf = {'slim': 0.82, 'regular': 1.0, 'athletic': 1.08,
                'plus': 1.25}[bodyType] ?? 1.0;
    final female = gender == 'female';
    final unit = h / 8.0;                 // ~8 heads tall
    final shoulderW = unit * 1.7 * wf * (female ? 0.92 : 1.0);
    final hipW = unit * 1.5 * wf * (female ? 1.12 : 0.95);
    final waistW = unit * 1.15 * wf * (female ? 0.82 : 1.0);

    final stroke = Paint()
      ..style = PaintingStyle.stroke..strokeWidth = 2
      ..color = const Color(0xFF233330).withValues(alpha: .55);
    Paint fill(String key) => Paint()
      ..style = PaintingStyle.fill
      ..color = _z(key).withValues(alpha: faded ? .5 : .85);

    // head
    final headR = unit * 0.5;
    final headC = Offset(cx, unit * 0.7);
    canvas.drawCircle(headC, headR, Paint()..color = const Color(0xFFEFE6D5));
    canvas.drawCircle(headC, headR, stroke);
    // neck
    final neckTop = headC.dy + headR;
    final shoulderY = neckTop + unit * 0.45;

    // ── torso polygon (shoulders → waist → hips) ──
    final torsoTop = shoulderY;
    final waistY = torsoTop + unit * 2.1;
    final hipY = waistY + unit * 1.1;
    Path torso = Path()
      ..moveTo(cx - shoulderW / 2, torsoTop)
      ..lineTo(cx + shoulderW / 2, torsoTop)
      ..lineTo(cx + waistW / 2, waistY)
      ..lineTo(cx + hipW / 2, hipY)
      ..lineTo(cx - hipW / 2, hipY)
      ..lineTo(cx - waistW / 2, waistY)
      ..close();
    // base torso
    canvas.drawPath(torso, Paint()..color = const Color(0xFFF3EFE6));

    // chest zone (upper third of torso)
    final chestRect = Rect.fromLTRB(cx - shoulderW / 2 + 4, torsoTop + 4,
        cx + shoulderW / 2 - 4, torsoTop + unit * 1.1);
    _zoneClip(canvas, torso, () => canvas.drawRRect(
        RRect.fromRectAndRadius(chestRect, const Radius.circular(10)),
        fill('chest')));
    // waist zone (middle)
    final waistRect = Rect.fromLTRB(cx - waistW / 2, waistY - unit * 0.7,
        cx + waistW / 2, waistY + unit * 0.2);
    _zoneClip(canvas, torso, () => canvas.drawRRect(
        RRect.fromRectAndRadius(waistRect, const Radius.circular(8)),
        fill('waist')));
    // hip zone (lower torso)
    final hipRect = Rect.fromLTRB(cx - hipW / 2, waistY + unit * 0.2,
        cx + hipW / 2, hipY);
    _zoneClip(canvas, torso, () => canvas.drawRRect(
        RRect.fromRectAndRadius(hipRect, const Radius.circular(8)),
        fill('hip')));
    canvas.drawPath(torso, stroke);

    // shoulders accent line
    final shPaint = Paint()..style = PaintingStyle.stroke..strokeWidth = 7
      ..strokeCap = StrokeCap.round..color = _z('shoulder').withValues(alpha: faded ? .5 : .9);
    canvas.drawLine(Offset(cx - shoulderW / 2, torsoTop),
        Offset(cx + shoulderW / 2, torsoTop), shPaint);

    // ── arms (sleeve zone) ──
    final armPaint = Paint()..style = PaintingStyle.stroke
      ..strokeWidth = unit * 0.42..strokeCap = StrokeCap.round
      ..color = _z('sleeve').withValues(alpha: faded ? .5 : .85);
    final armTopL = Offset(cx - shoulderW / 2 + 4, torsoTop + 6);
    canvas.drawLine(armTopL, Offset(cx - shoulderW / 2 - unit * 0.2,
        waistY + unit * 0.2), armPaint);
    final armTopR = Offset(cx + shoulderW / 2 - 4, torsoTop + 6);
    canvas.drawLine(armTopR, Offset(cx + shoulderW / 2 + unit * 0.2,
        waistY + unit * 0.2), armPaint);

    // ── legs (inseam / length zone) ──
    final legColor = _z(zones.containsKey('inseam') ? 'inseam' : 'length');
    final legPaint = Paint()..style = PaintingStyle.stroke
      ..strokeWidth = unit * 0.6..strokeCap = StrokeCap.round
      ..color = legColor.withValues(alpha: faded ? .5 : .85);
    final legTopY = hipY;
    final legBottomY = h - unit * 0.3;
    canvas.drawLine(Offset(cx - hipW / 4, legTopY),
        Offset(cx - hipW / 4, legBottomY), legPaint);
    canvas.drawLine(Offset(cx + hipW / 4, legTopY),
        Offset(cx + hipW / 4, legBottomY), legPaint);
  }

  void _zoneClip(Canvas canvas, Path clip, VoidCallback draw) {
    canvas.save();
    canvas.clipPath(clip);
    draw();
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BodyPainter old) =>
      old.zones != zones || old.gender != gender ||
      old.bodyType != bodyType || old.faded != faded;
}

// ─── Measurements bottom sheet ───────────────────────────────────────
class _MeasureSheet extends StatefulWidget {
  const _MeasureSheet({required this.ar});
  final bool ar;
  @override
  State<_MeasureSheet> createState() => _MeasureSheetState();
}

class _MeasureSheetState extends State<_MeasureSheet> {
  final _c = <String, TextEditingController>{};
  String _gender = 'male';
  String _bodyType = 'regular';
  String _fit = 'regular';
  bool _saving = false;

  static const _num = [
    ('height', 'Height (cm)', 'الطول (سم)'),
    ('weight', 'Weight (kg)', 'الوزن (كجم)'),
    ('chest', 'Chest (cm)', 'الصدر (سم)'),
    ('waist', 'Waist (cm)', 'الخصر (سم)'),
    ('shoulder', 'Shoulder (cm)', 'الكتف (سم)'),
    ('hip', 'Hip (cm)', 'الورك (سم)'),
    ('arm_length', 'Sleeve (cm)', 'الكم (سم)'),
    ('inseam', 'Inseam (cm)', 'طول الساق (سم)'),
    ('shoe_size_eu', 'Shoe EU', 'الحذاء EU'),
  ];

  @override
  void initState() {
    super.initState();
    for (final f in _num) { _c[f.$1] = TextEditingController(); }
    _prefill();
  }

  Future<void> _prefill() async {
    try {
      final res = await UellowApi.instance.getRaw(
          '/api/mobile/v2/fit/profile', auth: true);
      final p = (res['data']?['profile'] as Map?)?.cast<String, dynamic>();
      if (p == null) return;
      for (final f in _num) {
        final v = p[f.$1];
        if (v != null && (v is num) && v != 0) _c[f.$1]!.text = '$v';
      }
      setState(() {
        _gender = (p['gender'] ?? 'male').toString();
        _bodyType = (p['body_type'] ?? 'regular').toString();
        _fit = (p['preferred_fit'] ?? 'regular').toString();
      });
    } catch (_) {}
  }

  @override
  void dispose() { for (final c in _c.values) { c.dispose(); } super.dispose(); }

  Future<void> _save() async {
    setState(() => _saving = true);
    final body = <String, dynamic>{
      'gender': _gender, 'body_type': _bodyType, 'preferred_fit': _fit,
    };
    for (final f in _num) {
      final t = _c[f.$1]!.text.trim();
      if (t.isNotEmpty) body[f.$1] = double.tryParse(t) ?? 0;
    }
    try {
      await UellowApi.instance.postRaw('/api/mobile/v2/fit/profile/save',
          auth: true, body: body);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ar = widget.ar;
    return Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: Container(
        decoration: const BoxDecoration(color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
        padding: EdgeInsets.fromLTRB(18, 14, 18,
            16 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 42, height: 4, decoration: BoxDecoration(
              color: const Color(0xFFE3E3E3),
              borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 12),
          Text(ar ? 'مقاساتي' : 'My measurements',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900,
                  color: UellowColors.ink)),
          const SizedBox(height: 12),
          Flexible(child: SingleChildScrollView(child: Column(children: [
            _seg(ar ? 'النوع' : 'Gender', _gender, {
              'male': ar ? 'ذكر' : 'Male', 'female': ar ? 'أنثى' : 'Female',
            }, (v) => setState(() => _gender = v)),
            _seg(ar ? 'بنية الجسم' : 'Body type', _bodyType, {
              'slim': ar ? 'نحيف' : 'Slim', 'regular': ar ? 'متوسط' : 'Regular',
              'athletic': ar ? 'رياضي' : 'Athletic', 'plus': ar ? 'ممتلئ' : 'Plus',
            }, (v) => setState(() => _bodyType = v)),
            _seg(ar ? 'القَصّة المفضّلة' : 'Preferred fit', _fit, {
              'slim': ar ? 'ضيّقة' : 'Slim', 'regular': ar ? 'عادية' : 'Regular',
              'loose': ar ? 'واسعة' : 'Loose',
            }, (v) => setState(() => _fit = v)),
            const SizedBox(height: 6),
            GridView.count(crossAxisCount: 2, shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 3.0, mainAxisSpacing: 8, crossAxisSpacing: 10,
                children: [
              for (final f in _num) TextField(
                controller: _c[f.$1], keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: ar ? f.$3 : f.$2,
                  labelStyle: const TextStyle(fontSize: 11),
                  isDense: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ]),
          ]))),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: UellowColors.yellow,
              foregroundColor: UellowColors.darkBrown, elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: _saving
                ? const SizedBox(width: 20, height: 20, child:
                    CircularProgressIndicator(strokeWidth: 2,
                        color: UellowColors.darkBrown))
                : Text(ar ? 'حفظ' : 'Save',
                    style: const TextStyle(fontWeight: FontWeight.w900)),
          )),
        ]),
      ),
    );
  }

  Widget _seg(String label, String val, Map<String, String> opts,
      ValueChanged<String> onSel) {
    return Padding(padding: const EdgeInsets.only(bottom: 10), child:
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 12,
            fontWeight: FontWeight.w800, color: UellowColors.muted)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in opts.entries) GestureDetector(
            onTap: () => onSel(e.key),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: val == e.key ? UellowColors.yellow : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: val == e.key
                    ? UellowColors.yellow : UellowColors.border),
              ),
              child: Text(e.value, style: TextStyle(fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: val == e.key ? UellowColors.darkBrown
                      : UellowColors.text)),
            ),
          ),
        ]),
      ]),
    );
  }
}
