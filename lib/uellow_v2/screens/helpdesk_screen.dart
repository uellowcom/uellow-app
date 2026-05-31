// =============================================================================
// HelpdeskScreen — creates a real helpdesk.ticket in Odoo via
// /api/mobile/v2/helpdesk/create. Bilingual; categories + team picker
// fetched from /helpdesk/form. Pre-fills order_ref / category if the
// caller passed them in (e.g. from the order tracking screen).
// =============================================================================
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../api/uellow_api.dart';
import '../theme/uellow_theme.dart';

class HelpdeskScreen extends StatefulWidget {
  const HelpdeskScreen({super.key, this.orderRef, this.category});
  final String? orderRef;
  final String? category;
  @override
  State<HelpdeskScreen> createState() => _HelpdeskScreenState();
}

class _HelpdeskScreenState extends State<HelpdeskScreen> {
  final _subject = TextEditingController();
  final _body    = TextEditingController();
  final _orderRef = TextEditingController();
  bool _busy = false;
  bool _loadingMeta = true;
  List<Map<String, dynamic>> _teams = const [];
  List<Map<String, dynamic>> _cats  = const [];
  int? _teamId;
  String _cat = 'other';
  String? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _orderRef.text = widget.orderRef ?? '';
    _cat = widget.category ?? 'other';
    _loadMeta();
  }

  @override
  void dispose() {
    _subject.dispose(); _body.dispose(); _orderRef.dispose();
    super.dispose();
  }

  Future<void> _loadMeta() async {
    try {
      final r = await http.get(Uri.parse(
          '${UellowApi.instance.baseUrl}/api/mobile/v2/helpdesk/form'));
      final b = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (b['success'] == true) {
        final d = b['data'] as Map<String, dynamic>;
        _teams = (d['teams'] as List).cast<Map<String, dynamic>>();
        _cats  = (d['categories'] as List).cast<Map<String, dynamic>>();
        if (_teams.isNotEmpty) _teamId = _teams.first['id'] as int?;
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingMeta = false);
  }

  Future<void> _submit() async {
    final ar = UellowApi.instance.lang == 'ar';
    if (_subject.text.trim().isEmpty || _body.text.trim().isEmpty) {
      setState(() => _error = ar
          ? 'العنوان والوصف مطلوبان' : 'Subject and description required');
      return;
    }
    setState(() { _busy = true; _error = null; _result = null; });
    try {
      final token = await UellowApi.instance.tokenStore.readToken();
      final r = await http.post(
        Uri.parse('${UellowApi.instance.baseUrl}/api/mobile/v2/helpdesk/create'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'subject':     _subject.text.trim(),
          'description': _body.text.trim(),
          'category':    _cat,
          'order_ref':   _orderRef.text.trim(),
          if (_teamId != null) 'team_id': _teamId,
        }),
      );
      final b = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (b['success'] == true) {
        final d = b['data'] as Map<String, dynamic>;
        setState(() {
          _busy = false;
          _result = ar
              ? 'تم إنشاء التذكرة #${d['number']} ❤️\nسيتواصل معك فريق الدعم قريباً.'
              : 'Ticket #${d['number']} created.\nOur support team will reach out shortly.';
          _subject.clear(); _body.clear();
        });
      } else {
        setState(() {
          _busy = false;
          _error = (b['error'] ?? 'Failed to create ticket').toString();
        });
      }
    } catch (e) {
      if (mounted) setState(() { _busy = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return Scaffold(
      backgroundColor: UellowColors.bg,
      appBar: AppBar(
        leading: const BackButton(color: UellowColors.darkBrown),
        title: Text(ar ? 'الدعم الفني' : 'Contact Support', style: UT.h1),
      ),
      body: SafeArea(bottom: true, child: _loadingMeta
        ? const Center(child: CircularProgressIndicator(color: UellowColors.darkBrown))
        : ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 24), children: [
            // ── Banner ─────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                gradient: UellowColors.heroWallet,
                borderRadius: BorderRadius.all(Radius.circular(16)),
              ),
              child: Row(children: [
                const Icon(Icons.support_agent, color: UellowColors.yellowLight, size: 32),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(ar ? 'كيف نقدر نساعدك؟' : 'How can we help?',
                      style: const TextStyle(color: UellowColors.yellowLight,
                          fontSize: 16, fontWeight: FontWeight.w900)),
                  Text(ar ? 'فريق الدعم يرد عادة خلال ساعات قليلة.'
                          : 'Our team usually replies within a few hours.',
                      style: const TextStyle(color: Color(0xCCFFD340), fontSize: 11.5)),
                ])),
              ]),
            ),
            const SizedBox(height: 14),
            // ── Category chips ─────────────────────────────
            Text(ar ? 'الفئة' : 'Category', style: UT.h3),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: _cats.map((c) {
              final key = c['key'] as String;
              final on = _cat == key;
              return ChoiceChip(
                label: Text((ar ? c['ar'] : c['en']).toString(),
                    style: TextStyle(fontWeight: FontWeight.w800,
                        color: on ? UellowColors.darkBrown : UellowColors.text)),
                selected: on,
                onSelected: (_) => setState(() => _cat = key),
                selectedColor: UellowColors.yellow,
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: on ? UellowColors.yellow : UellowColors.border)),
              );
            }).toList()),
            const SizedBox(height: 14),
            // ── Team picker (if multiple) ──────────────────
            if (_teams.length > 1) ...[
              Text(ar ? 'القسم' : 'Department', style: UT.h3),
              const SizedBox(height: 6),
              DropdownButtonFormField<int>(
                value: _teamId,
                items: _teams.map((t) => DropdownMenuItem<int>(
                    value: t['id'] as int,
                    child: Text(t['name'].toString()))).toList(),
                onChanged: (v) => setState(() => _teamId = v),
                decoration: const InputDecoration(isDense: true),
              ),
              const SizedBox(height: 14),
            ],
            // ── Order ref (auto-filled when navigated from order) ──
            Text(ar ? 'رقم الطلب (اختياري)' : 'Order reference (optional)',
                style: UT.h3),
            const SizedBox(height: 6),
            TextField(
              controller: _orderRef,
              decoration: InputDecoration(
                hintText: ar ? 'مثال: S00532' : 'e.g. S00532',
                prefixIcon: const Icon(Icons.receipt_long_outlined, size: 18),
                isDense: true,
              ),
            ),
            const SizedBox(height: 14),
            // ── Subject ────────────────────────────────────
            Text(ar ? 'العنوان' : 'Subject', style: UT.h3),
            const SizedBox(height: 6),
            TextField(
              controller: _subject,
              maxLength: 100,
              decoration: InputDecoration(
                hintText: ar ? 'ملخص موجز للمشكلة' : 'Brief summary of the issue',
                isDense: true,
              ),
            ),
            // ── Body ───────────────────────────────────────
            Text(ar ? 'الوصف' : 'Description', style: UT.h3),
            const SizedBox(height: 6),
            TextField(
              controller: _body,
              maxLines: 6, minLines: 4,
              decoration: InputDecoration(
                hintText: ar
                    ? 'صف المشكلة بالتفصيل…'
                    : 'Describe the issue in detail…',
                isDense: true,
              ),
            ),
            const SizedBox(height: 18),
            // ── Submit ─────────────────────────────────────
            SizedBox(width: double.infinity, child: ElevatedButton.icon(
              onPressed: _busy ? null : _submit,
              icon: _busy
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2,
                          color: UellowColors.darkBrown))
                  : const Icon(Icons.send, size: 18),
              label: Text(_busy
                  ? (ar ? 'جارٍ الإرسال…' : 'Submitting…')
                  : (ar ? 'إرسال التذكرة' : 'Submit ticket'),
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
              style: ElevatedButton.styleFrom(
                backgroundColor: UellowColors.yellow,
                foregroundColor: UellowColors.darkBrown,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(14))),
                elevation: 2,
              ),
            )),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 10),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: UellowColors.dangerBg,
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(_error!, style: const TextStyle(
                      color: UellowColors.dangerDk, fontWeight: FontWeight.w700)),
                )),
            if (_result != null) Padding(padding: const EdgeInsets.only(top: 10),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: UellowColors.successBg,
                      borderRadius: BorderRadius.circular(8)),
                  child: Row(children: [
                    const Icon(Icons.check_circle, color: UellowColors.successDk),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_result!, style: const TextStyle(
                        color: UellowColors.successDk, fontWeight: FontWeight.w700))),
                  ]),
                )),
          ])),
    );
  }
}
