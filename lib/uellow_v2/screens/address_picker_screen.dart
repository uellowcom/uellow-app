// =============================================================================
// AddressPickerScreen — full-screen GPS + draggable pin + reverse-geocode +
// Odoo address form + landmark photo upload.
//
// Flow:
//   1. Open → request location permission → centre map on user's current
//      position (Kuwait City fallback).
//   2. User pans the map → centre pin stays under the crosshair → on stop,
//      reverse-geocode via OSM Nominatim (free, no key needed).
//   3. Confirm location → slide-up sheet with all Odoo address fields:
//        Address label · Contact name · Phone · Email · Country · State /
//        Governorate · Area / Block · Street · Building · Floor · Apt ·
//        Landmark notes · Landmark photo.
//   4. Save → POST /addresses/create with lat/lng + photo b64.
// =============================================================================
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../api/uellow_api.dart';
import '../theme/uellow_theme.dart';

class AddressPickerScreen extends StatefulWidget {
  const AddressPickerScreen({super.key, this.onSaved});
  /// Legacy callback (kept for compatibility with checkout). Modern
  /// callers should `await Navigator.push` and read the returned address
  /// id (or null on cancel).
  final VoidCallback? onSaved;
  @override
  State<AddressPickerScreen> createState() => _AddressPickerScreenState();
}

class _AddressPickerScreenState extends State<AddressPickerScreen> {
  WebViewController? _wv;
  double _lat = 29.3375;     // Kuwait City fallback
  double _lng = 47.9750;
  String _reverseAddress = '';
  bool _locating = true;
  bool _showForm = false;
  Timer? _debounce;

  @override
  void initState() { super.initState(); _bootstrap(); }
  @override
  void dispose() { _debounce?.cancel(); super.dispose(); }

  Future<void> _bootstrap() async {
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.always || perm == LocationPermission.whileInUse) {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 8)));
        _lat = pos.latitude; _lng = pos.longitude;
      }
    } catch (_) {}
    _initMap();
    _reverseGeocode();
    if (mounted) setState(() => _locating = false);
  }

  void _initMap() {
    try {
      _wv = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xFFEFEAE0))
        ..addJavaScriptChannel('PinMoved', onMessageReceived: (msg) {
          // msg = "lat,lng"
          final parts = msg.message.split(',');
          if (parts.length == 2) {
            final lat = double.tryParse(parts[0]);
            final lng = double.tryParse(parts[1]);
            if (lat != null && lng != null) {
              _lat = lat; _lng = lng;
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 600), _reverseGeocode);
            }
          }
        })
        ..loadHtmlString(_html());
    } catch (_) { _wv = null; }
  }

  Future<void> _reverseGeocode() async {
    try {
      final r = await http.get(Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=jsonv2'
        '&lat=$_lat&lon=$_lng&accept-language=${UellowApi.instance.lang}'),
        headers: {'User-Agent': 'UellowApp/2.0 (support@uellow.com)'},
      ).timeout(const Duration(seconds: 6));
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        final display = (j['display_name'] as String?) ?? '';
        if (mounted) setState(() => _reverseAddress = display);
      }
    } catch (_) {}
  }

  String _html() => '''
<!doctype html><html><head><meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no"/>
<link rel="stylesheet" href="https://unpkg.com/leaflet\@1.9.4/dist/leaflet.css"/>
<style>html,body,#m{margin:0;padding:0;height:100%;width:100%;background:#efeae0}
#pin{position:absolute;left:50%;top:50%;transform:translate(-50%,-100%);z-index:9999;font-size:38px;pointer-events:none;text-shadow:0 2px 5px rgba(0,0,0,.4)}
</style></head><body>
<div id="m"></div>
<div id="pin">📍</div>
<script src="https://unpkg.com/leaflet\@1.9.4/dist/leaflet.js"></script>
<script>
var map=L.map('m',{zoomControl:true,attributionControl:true}).setView([$_lat,$_lng],16);
L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
  {maxZoom:19,attribution:'© OSM'}).addTo(map);
var t=null;
map.on('move',function(){
  if(t)clearTimeout(t);
  t=setTimeout(function(){
    var c=map.getCenter();
    PinMoved.postMessage(c.lat+','+c.lng);
  },150);
});
</script></body></html>''';

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return Scaffold(
      backgroundColor: UellowColors.bg,
      appBar: AppBar(
        title: Text(ar ? 'حدد موقع التوصيل' : 'Pick delivery location',
            style: const TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: Colors.white,
        foregroundColor: UellowColors.darkBrown,
        actions: [
          IconButton(tooltip: ar ? 'تحديد موقعي' : 'My location',
              onPressed: () async {
                setState(() => _locating = true);
                await _bootstrap();
                try {
                  await _wv?.runJavaScript('map.setView([$_lat,$_lng],17);');
                } catch (_) {}
                _reverseGeocode();
              },
              icon: const Icon(Icons.my_location)),
        ],
      ),
      body: Stack(children: [
        if (_wv != null) Positioned.fill(child: WebViewWidget(controller: _wv!))
        else const Center(child: CircularProgressIndicator(color: UellowColors.darkBrown)),
        if (_locating) const Positioned(top: 12, left: 12, right: 12,
          child: _Banner(text: 'Locating you…')),
        Positioned(left: 12, right: 12, bottom: 12, child: _AddressCard(
          address: _reverseAddress.isEmpty
              ? (ar ? 'حرّك الخريطة لتحديد موقعك' : 'Move the map to set your spot')
              : _reverseAddress,
          onConfirm: () => _openForm(),
        )),
      ]),
    );
  }

  void _openForm() {
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddressForm(
        lat: _lat, lng: _lng, reverseAddress: _reverseAddress,
        onSaved: (newId) {
          widget.onSaved?.call();
          // Pop the address picker AND pass the new id back to the caller
          // so checkout / cart can auto-select it.
          Navigator.pop(context, newId);
        },
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 6)],
      ),
      child: Row(children: [
        const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(
            strokeWidth: 2, color: UellowColors.darkBrown)),
        const SizedBox(width: 10),
        Text(text, style: const TextStyle(fontWeight: FontWeight.w800,
            color: UellowColors.darkBrown, fontSize: 12.5)),
      ]),
    );
  }
}

class _AddressCard extends StatelessWidget {
  const _AddressCard({required this.address, required this.onConfirm});
  final String address;
  final VoidCallback onConfirm;
  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return Material(
      elevation: 6, borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(16),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const Icon(Icons.location_on, color: UellowColors.warn, size: 20),
            const SizedBox(width: 6),
            Expanded(child: Text(ar ? 'العنوان المحدد' : 'Selected location',
                style: const TextStyle(fontWeight: FontWeight.w900,
                    fontSize: 12, color: UellowColors.darkBrown))),
          ]),
          const SizedBox(height: 6),
          Text(address, maxLines: 3, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: UellowColors.text)),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: onConfirm,
            icon: const Icon(Icons.arrow_forward, size: 16),
            label: Text(ar ? 'متابعة لتفاصيل العنوان' : 'Continue to address details',
                style: const TextStyle(fontWeight: FontWeight.w900)),
            style: ElevatedButton.styleFrom(
              backgroundColor: UellowColors.darkBrown,
              foregroundColor: UellowColors.yellowLight,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12))),
            ),
          ),
        ]),
      ),
    );
  }
}

class _AddressForm extends StatefulWidget {
  const _AddressForm({
    required this.lat, required this.lng, required this.reverseAddress,
    required this.onSaved,
  });
  final double lat;
  final double lng;
  final String reverseAddress;
  final void Function(int? newAddressId) onSaved;
  @override
  State<_AddressForm> createState() => _AddressFormState();
}

class _AddressFormState extends State<_AddressForm> {
  final _label = TextEditingController(text: 'Home');
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _country = TextEditingController(text: 'Kuwait');
  final _city = TextEditingController();
  final _area = TextEditingController();
  final _block = TextEditingController();
  final _street = TextEditingController();
  final _building = TextEditingController();
  final _floor = TextEditingController();
  final _apt = TextEditingController();
  final _notes = TextEditingController();
  Uint8List? _photoBytes;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill from reverse-geocode if it parsed cleanly.
    final parts = widget.reverseAddress.split(',').map((s) => s.trim()).toList();
    if (parts.length >= 3) {
      _street.text = parts[0];
      _area.text = parts.length > 1 ? parts[1] : '';
      _city.text = parts.length > 2 ? parts[parts.length - 3] : '';
    }
  }

  Future<void> _pickPhoto() async {
    final src = await showModalBottomSheet<ImageSource>(
      context: context, builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min,
          children: [
        ListTile(leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take photo'),
            onTap: () => Navigator.pop(context, ImageSource.camera)),
        ListTile(leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.pop(context, ImageSource.gallery)),
      ])));
    if (src == null) return;
    final picked = await ImagePicker().pickImage(source: src,
        maxWidth: 1200, maxHeight: 1200, imageQuality: 80);
    if (picked == null) return;
    final bytes = await File(picked.path).readAsBytes();
    if (mounted) setState(() => _photoBytes = bytes);
  }

  Future<void> _save() async {
    final ar = UellowApi.instance.lang == 'ar';
    if (_phone.text.trim().isEmpty || _name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          ar ? 'الاسم والهاتف مطلوبان' : 'Name and phone are required')));
      return;
    }
    setState(() => _busy = true);
    try {
      final street2 = [
        if (_block.text.trim().isNotEmpty) 'Block ${_block.text.trim()}',
        if (_building.text.trim().isNotEmpty) 'Bldg ${_building.text.trim()}',
        if (_floor.text.trim().isNotEmpty) 'Floor ${_floor.text.trim()}',
        if (_apt.text.trim().isNotEmpty) 'Apt ${_apt.text.trim()}',
      ].join(', ');
      final body = {
        'name': _name.text.trim(),
        'phone': _phone.text.trim(),
        'email': _email.text.trim(),
        'street': _street.text.trim(),
        'street2': street2,
        'city': _city.text.trim(),
        'state': _area.text.trim(),
        'country_code': _countryCode(_country.text.trim()),
        'type': 'delivery',
        'address_label': _label.text.trim(),
        'lat': widget.lat,
        'lng': widget.lng,
        'notes': _notes.text.trim(),
        if (_photoBytes != null) 'landmark_photo': base64Encode(_photoBytes!),
      };
      final created = await UellowApi.instance.addresses.create(body);
      if (!mounted) return;
      // Persist as the default-selected address so the calling screen
      // pre-selects it on its next refresh.
      try {
        await UellowApi.instance.tokenStore.writeAddressId(created.id);
      } catch (_) {}
      // Close the bottom sheet first, then let the picker pop with the id.
      Navigator.pop(context);
      widget.onSaved(created.id);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _countryCode(String name) {
    final n = name.toLowerCase();
    if (n.contains('kuwait') || n.contains('كويت')) return 'KW';
    if (n.contains('saudi') || n.contains('سعود')) return 'SA';
    if (n.contains('uae') || n.contains('emirat') || n.contains('إمار')) return 'AE';
    if (n.contains('qatar') || n.contains('قطر')) return 'QA';
    if (n.contains('bahrain') || n.contains('بحري')) return 'BH';
    if (n.contains('oman') || n.contains('عُمان') || n.contains('عمان')) return 'OM';
    return '';
  }

  static const _labelChips = [
    ('Home', 'المنزل', Icons.home_outlined),
    ('Office', 'العمل', Icons.work_outline),
    ('Family', 'العائلة', Icons.favorite_border),
    ('Other', 'أخرى', Icons.location_on_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.94),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // ── Drag handle + header ──────────────────────────────
          Container(width: 40, height: 4, margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(color: UellowColors.border,
                  borderRadius: BorderRadius.circular(2))),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 4, 16, 14),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: UellowColors.border)),
            ),
            child: Row(children: [
              Container(
                width: 36, height: 36, alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: UellowColors.yellowSoft, shape: BoxShape.circle),
                child: const Icon(Icons.location_on,
                    color: UellowColors.darkBrown, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(ar ? 'تفاصيل العنوان' : 'Address details', style: UT.h2),
                Text(widget.reverseAddress,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: UT.small),
              ])),
              IconButton(icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(context)),
            ]),
          ),
          Flexible(child: ListView(padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
              children: [
            // ── Address label as chips
            _section(ar ? 'تسمية العنوان' : 'Address label', Icons.bookmark_border),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final chip in _labelChips) _labelChip(chip.$1, chip.$2, chip.$3, ar),
            ]),
            const SizedBox(height: 4),
            // ── Recipient
            _section(ar ? 'بيانات المستلم' : 'Recipient', Icons.person_outline),
            _f(ar ? 'الاسم الكامل' : 'Full name', _name,
                icon: Icons.person_outline,
                hint: ar ? 'مثال: علي محمد' : 'e.g. John Smith'),
            _f(ar ? 'رقم الهاتف' : 'Phone number', _phone,
                type: TextInputType.phone,
                icon: Icons.phone_outlined,
                hint: '+965 9999 9999'),
            _f(ar ? 'البريد الإلكتروني (اختياري)' : 'Email (optional)', _email,
                type: TextInputType.emailAddress,
                icon: Icons.alternate_email),
            // ── Delivery location
            _section(ar ? 'موقع التوصيل' : 'Delivery location', Icons.map_outlined),
            _f(ar ? 'الدولة' : 'Country', _country, icon: Icons.public),
            _f(ar ? 'المحافظة / المدينة' : 'Governorate / City', _city,
                icon: Icons.location_city_outlined),
            _f(ar ? 'المنطقة' : 'Area', _area,
                icon: Icons.place_outlined),
            Row(children: [
              Expanded(child: _f(ar ? 'القطعة' : 'Block', _block, padded: false)),
              const SizedBox(width: 10),
              Expanded(flex: 2,
                  child: _f(ar ? 'الشارع' : 'Street', _street, padded: false)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(flex: 2,
                  child: _f(ar ? 'المنزل / المبنى' : 'Building', _building, padded: false)),
              const SizedBox(width: 10),
              Expanded(child: _f(ar ? 'الدور' : 'Floor', _floor, padded: false)),
              const SizedBox(width: 10),
              Expanded(child: _f(ar ? 'الشقة' : 'Apt', _apt, padded: false)),
            ]),
            const SizedBox(height: 12),
            _f(ar ? 'ملاحظات للسائق' : 'Notes for the driver',
                _notes, lines: 2, icon: Icons.sticky_note_2_outlined,
                hint: ar ? 'علامة مميزة قرب العنوان...'
                          : 'A landmark or instructions...'),
            const SizedBox(height: 14),
            _section(ar ? 'صورة دلالية (اختياري)' : 'Landmark photo (optional)',
                Icons.add_photo_alternate_outlined),
            InkWell(
              onTap: _pickPhoto,
              child: Container(
                height: 110,
                decoration: BoxDecoration(
                  color: UellowColors.yellowSoft,
                  border: Border.all(color: UellowColors.yellow, width: 1.5,
                      style: BorderStyle.solid),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _photoBytes != null
                    ? ClipRRect(borderRadius: BorderRadius.circular(11),
                        child: Image.memory(_photoBytes!, fit: BoxFit.cover,
                            width: double.infinity))
                    : Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.add_photo_alternate_outlined,
                            color: UellowColors.darkBrown, size: 28),
                        const SizedBox(height: 6),
                        Text(ar
                            ? 'أضف صورة المبنى / الشارع لمساعدة السائق'
                            : 'Add a photo of the building / street',
                            style: const TextStyle(fontSize: 12,
                                color: UellowColors.darkBrown,
                                fontWeight: FontWeight.w700)),
                      ])),
              ),
            ),
            const SizedBox(height: 16),
          ])),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: UellowColors.border)),
            ),
            child: SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: _busy ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: UellowColors.success,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(14))),
              ),
              child: _busy
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(ar ? 'حفظ العنوان' : 'Save address',
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
            )),
          ),
        ]),
      ),
    );
  }

  Widget _section(String t, [IconData? icon]) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Row(children: [
      if (icon != null) ...[
        Icon(icon, size: 14, color: UellowColors.darkBrown),
        const SizedBox(width: 6),
      ],
      Text(t.toUpperCase(), style: const TextStyle(
          fontSize: 11.5, fontWeight: FontWeight.w900,
          color: UellowColors.darkBrown, letterSpacing: 0.6)),
      const SizedBox(width: 10),
      Expanded(child: Container(height: 1, color: UellowColors.border)),
    ]),
  );

  Widget _labelChip(String en, String ar, IconData icon, bool isAr) {
    final on = _label.text.trim().toLowerCase() == en.toLowerCase();
    final text = isAr ? ar : en;
    return GestureDetector(
      onTap: () => setState(() => _label.text = en),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: on ? UellowColors.yellow : Colors.white,
          border: Border.all(
            color: on ? UellowColors.yellow : UellowColors.border,
            width: on ? 2 : 1),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14,
              color: on ? UellowColors.darkBrown : UellowColors.muted),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w900,
              color: on ? UellowColors.darkBrown : UellowColors.text)),
        ]),
      ),
    );
  }

  Widget _f(String label, TextEditingController c,
      {TextInputType? type, int lines = 1, bool padded = true,
      IconData? icon, String? hint}) {
    final field = TextField(
      controller: c,
      keyboardType: type,
      minLines: lines, maxLines: lines,
      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 12, color: UellowColors.muted),
        prefixIcon: icon != null ? Icon(icon, size: 18,
            color: UellowColors.muted) : null,
        prefixIconConstraints: const BoxConstraints(minWidth: 38),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(11)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(color: UellowColors.darkBrown, width: 1.5)),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
    return padded ? Padding(padding: const EdgeInsets.only(bottom: 10), child: field) : field;
  }
}
