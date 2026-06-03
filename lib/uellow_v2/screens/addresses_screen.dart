// =============================================================================
// AddressesScreen — list/add/edit res.partner shipping addresses via the
// /api/mobile/v2/addresses endpoints.
// =============================================================================
import 'package:flutter/material.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../../api/uellow_api.dart';
import '../../api/uellow_models.dart';
import '../theme/uellow_theme.dart';

class AddressesScreen extends StatefulWidget {
  const AddressesScreen({super.key});
  @override
  State<AddressesScreen> createState() => _AddressesScreenState();
}

class _AddressesScreenState extends State<AddressesScreen> {
  late Future<List<UellowAddress>> _future;
  @override
  void initState() {
    super.initState();
    _future = UellowApi.instance.addresses.list();
  }
  void _reload() => setState(() => _future = UellowApi.instance.addresses.list());

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return Scaffold(
      backgroundColor: UellowColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: Text(ar ? 'عناويني' : 'My addresses', style: UT.h1),
      ),
      body: SafeArea(child: FutureBuilder<List<UellowAddress>>(
        future: _future,
        builder: (_, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(
                color: UellowColors.darkBrown));
          }
          if (snap.hasError) {
            return Center(child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.error_outline, size: 48, color: UellowColors.muted),
                const SizedBox(height: 10),
                Text(snap.error.toString(), textAlign: TextAlign.center,
                    style: UT.body),
              ]),
            ));
          }
          final list = snap.data ?? [];
          if (list.isEmpty) return _empty();
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _tile(list[i]),
          );
        },
      )),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: UellowColors.yellow,
        foregroundColor: UellowColors.darkBrown,
        onPressed: _addNew,
        icon: const Icon(Icons.add_location_alt_outlined),
        label: Text(ar ? 'إضافة عنوان' : 'Add new'),
      ),
    );
  }

  Widget _tile(UellowAddress a) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(
            color: a.isDefault ? UellowColors.yellow : UellowColors.border,
            width: a.isDefault ? 2 : 1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(a.isDefault ? Icons.location_on : Icons.location_on_outlined,
            color: a.isDefault ? UellowColors.warn : UellowColors.muted),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(a.name.isNotEmpty ? a.name : a.city,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            if (a.isDefault) Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: UellowColors.yellow,
                    borderRadius: BorderRadius.circular(4)),
                child: Text(UellowApi.instance.lang == 'ar' ? 'افتراضي' : 'DEFAULT',
                    style: const TextStyle(
                    fontSize: 9, fontWeight: FontWeight.w900,
                    color: UellowColors.darkBrown, letterSpacing: 0.5)),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          Text([a.street, a.street2, a.city, a.country]
                  .where((s) => s.isNotEmpty).join(', '),
              style: const TextStyle(fontSize: 12, color: UellowColors.text)),
          if (a.phone.isNotEmpty) Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(a.phone, style: const TextStyle(
                fontSize: 11, color: UellowColors.muted)),
          ),
        ])),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: UellowColors.muted),
          onSelected: (v) async {
            if (v == 'delete') {
              await UellowApi.instance.addresses.delete(a.id);
              _reload();
            } else if (v == 'edit') {
              _addNew(initial: a);
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'edit',
                child: Text(UellowApi.instance.lang == 'ar' ? 'تعديل' : 'Edit')),
            PopupMenuItem(value: 'delete',
                child: Text(UellowApi.instance.lang == 'ar' ? 'حذف' : 'Delete',
                    style: const TextStyle(color: UellowColors.danger))),
          ],
        ),
      ]),
    );
  }

  Widget _empty() {
    final ar = UellowApi.instance.lang == 'ar';
    return Center(child: Padding(
      padding: const EdgeInsets.all(30),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.location_off_outlined, size: 64, color: UellowColors.muted),
        const SizedBox(height: 10),
        Text(ar ? 'لا توجد عناوين بعد' : 'No addresses yet',
            style: UT.body),
        const SizedBox(height: 14),
        ElevatedButton.icon(
          onPressed: _addNew,
          icon: const Icon(Icons.add_location_alt_outlined, size: 16),
          label: Text(ar ? 'إضافة عنوان' : 'Add address'),
        ),
      ]),
    ));
  }

  void _addNew({UellowAddress? initial}) {
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddressFormSheet(initial: initial, onSaved: _reload),
    );
  }
}

class AddressFormSheet extends StatefulWidget {
  const AddressFormSheet({this.initial, required this.onSaved});
  final UellowAddress? initial;
  final VoidCallback onSaved;
  @override
  State<AddressFormSheet> createState() => _AddressFormSheetState();
}

class _AddressFormSheetState extends State<AddressFormSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _street = TextEditingController();
  final _street2 = TextEditingController();
  final _city = TextEditingController();
  final _zip = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final a = widget.initial;
    if (a != null) {
      _name.text = a.name;
      _phone.text = a.phone;
      _street.text = a.street;
      _street2.text = a.street2;
      _city.text = a.city;
      _zip.text = a.zip;
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final body = {
        'name': _name.text.trim(),
        'phone': _phone.text.trim(),
        'street': _street.text.trim(),
        'street2': _street2.text.trim(),
        'city': _city.text.trim(),
        'zip': _zip.text.trim(),
        'type': 'delivery',
      };
      if (widget.initial != null) {
        await UellowApi.instance.addresses.update(widget.initial!.id, body);
      } else {
        await UellowApi.instance.addresses.create(body);
      }
      if (!mounted) return;
      Navigator.pop(context);
      widget.onSaved();
    } on UellowApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: UellowColors.border,
                  borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 14),
          Text(widget.initial != null
              ? (ar ? 'تعديل العنوان' : 'Edit address')
              : (ar ? 'إضافة عنوان جديد' : 'Add new address'),
              style: UT.h2),
          const SizedBox(height: 14),
          _f(ar ? 'الاسم' : 'Full name', _name),
          _f(ar ? 'الهاتف' : 'Phone', _phone),
          _f(ar ? 'الشارع' : 'Street', _street),
          _f(ar ? 'الشارع 2 (اختياري)' : 'Street 2 (optional)', _street2),
          _cityPicker(ar),
          _f(ar ? 'الرمز البريدي' : 'ZIP', _zip),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: _busy ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: UellowColors.yellow,
              foregroundColor: UellowColors.darkBrown,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: _busy
              ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2,
                      color: UellowColors.darkBrown))
              : Text(ar ? 'حفظ' : 'Save',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          )),
        ]),
      ),
    );
  }

  // v2.1.17 — city comes from the delivery.city list (640 map-matching
  // cities seeded for KW/SA/QA/AE/EG/OM/US) so spelling always matches
  // the shipping zones. Falls back to free text if the list is empty.
  Widget _cityPicker(bool ar) {
    return Padding(padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: _city,
          readOnly: true,
          onTap: () => _openCitySheet(ar),
          decoration: InputDecoration(
            labelText: ar ? 'المدينة' : 'City',
            suffixIcon: const Icon(Icons.arrow_drop_down,
                color: UellowColors.muted),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            isDense: true,
          ),
        ));
  }

  Future<void> _openCitySheet(bool ar) async {
    final prefs = await SharedPreferences.getInstance();
    final cc = prefs.getString('uellow_country_code_v1') ?? 'KW';
    List<Map<String, dynamic>> all = [];
    try {
      all = await UellowApi.instance.shipping.cities(country: cc);
    } catch (_) {}
    if (!mounted) return;
    if (all.isEmpty) {
      // No list for this country — let the user type freely.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          ar ? 'اكتب اسم مدينتك' : 'Type your city name')));
      setState(() {});
      return;
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        String q = '';
        return StatefulBuilder(builder: (ctx, setS) {
          final list = q.isEmpty
              ? all
              : all.where((c) {
                  final en = (c['name_en'] ?? c['name'] ?? '')
                      .toString().toLowerCase();
                  final arName = (c['name_ar'] ?? '').toString();
                  return en.contains(q.toLowerCase()) || arName.contains(q);
                }).toList();
          return SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.75,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: TextField(
                  autofocus: true,
                  onChanged: (v) => setS(() => q = v),
                  style: const TextStyle(color: UellowColors.ink),
                  decoration: InputDecoration(
                    hintText: ar ? 'ابحث عن مدينتك…' : 'Search your city…',
                    prefixIcon: const Icon(Icons.search,
                        color: UellowColors.muted),
                    fillColor: UellowColors.yellowFaint, filled: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    isDense: true,
                  ),
                ),
              ),
              Expanded(child: ListView.builder(
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final c = list[i];
                  final en = (c['name_en'] ?? c['name'] ?? '').toString();
                  final arName = (c['name_ar'] ?? '').toString();
                  return ListTile(
                    dense: true,
                    title: Text(ar && arName.isNotEmpty ? arName : en,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: ar && arName.isNotEmpty
                        ? Text(en, style: const TextStyle(fontSize: 11))
                        : (arName.isNotEmpty
                            ? Text(arName, style: const TextStyle(fontSize: 11))
                            : null),
                    onTap: () => Navigator.pop(ctx, en),
                  );
                },
              )),
            ]),
          );
        });
      },
    );
    if (picked != null && picked.isNotEmpty && mounted) {
      setState(() => _city.text = picked);
    }
  }

  Widget _f(String label, TextEditingController c) {
    return Padding(padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          decoration: InputDecoration(
            labelText: label,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            isDense: true,
          ),
        ));
  }
}
