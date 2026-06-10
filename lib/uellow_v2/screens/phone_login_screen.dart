// =============================================================================
// PhoneLoginScreen — dedicated phone sign-in with a country-code + flag picker.
// Uses Firebase Phone Auth (Firebase sends the SMS), then exchanges the
// Firebase ID token for a Uellow bearer token via /auth/firebase.
// =============================================================================
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/fcm_service.dart';
import '../../api/uellow_api.dart';
import '../theme/uellow_theme.dart';

/// Push the phone-login screen. Returns true when sign-in succeeded.
Future<bool> showPhoneLogin(BuildContext context) async {
  final res = await Navigator.of(context).push<bool>(
    MaterialPageRoute(builder: (_) => const PhoneLoginScreen(), fullscreenDialog: true),
  );
  return res == true;
}

class _Country {
  final String name; final String nameAr; final String iso; final String dial;
  const _Country(this.name, this.nameAr, this.iso, this.dial);
  // Build the flag emoji from the ISO-2 code (regional indicator letters).
  String get flag => iso.toUpperCase().codeUnits
      .map((c) => String.fromCharCode(0x1F1E6 + c - 65)).join();
}

const List<_Country> _countries = [
  _Country('Kuwait', 'الكويت', 'KW', '965'),
  _Country('Saudi Arabia', 'السعودية', 'SA', '966'),
  _Country('United Arab Emirates', 'الإمارات', 'AE', '971'),
  _Country('Qatar', 'قطر', 'QA', '974'),
  _Country('Bahrain', 'البحرين', 'BH', '973'),
  _Country('Oman', 'عُمان', 'OM', '968'),
  _Country('Egypt', 'مصر', 'EG', '20'),
  _Country('Jordan', 'الأردن', 'JO', '962'),
  _Country('Lebanon', 'لبنان', 'LB', '961'),
  _Country('Iraq', 'العراق', 'IQ', '964'),
  _Country('Yemen', 'اليمن', 'YE', '967'),
  _Country('Syria', 'سوريا', 'SY', '963'),
  _Country('Palestine', 'فلسطين', 'PS', '970'),
  _Country('Sudan', 'السودان', 'SD', '249'),
  _Country('Libya', 'ليبيا', 'LY', '218'),
  _Country('Tunisia', 'تونس', 'TN', '216'),
  _Country('Algeria', 'الجزائر', 'DZ', '213'),
  _Country('Morocco', 'المغرب', 'MA', '212'),
  _Country('Turkey', 'تركيا', 'TR', '90'),
  _Country('India', 'الهند', 'IN', '91'),
  _Country('Pakistan', 'باكستان', 'PK', '92'),
  _Country('Bangladesh', 'بنغلاديش', 'BD', '880'),
  _Country('Philippines', 'الفلبين', 'PH', '63'),
  _Country('Nepal', 'نيبال', 'NP', '977'),
  _Country('Sri Lanka', 'سريلانكا', 'LK', '94'),
  _Country('United Kingdom', 'بريطانيا', 'GB', '44'),
  _Country('United States', 'أمريكا', 'US', '1'),
];

class PhoneLoginScreen extends StatefulWidget {
  const PhoneLoginScreen({super.key});
  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends State<PhoneLoginScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  _Country _country = _countries.first;
  bool _sent = false;
  bool _busy = false;
  String? _err;
  String _verificationId = '';

  bool get _ar => UellowApi.instance.lang.toLowerCase().startsWith('ar');
  String get _e164 =>
      '+${_country.dial}${_phone.text.replaceAll(RegExp(r'[^0-9]'), '')}';

  Future<void> _pickCountry() async {
    final picked = await showModalBottomSheet<_Country>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        final search = TextEditingController();
        List<_Country> list = List.of(_countries);
        return StatefulBuilder(builder: (ctx, setS) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.7,
              child: Column(children: [
                const SizedBox(height: 10),
                Container(width: 40, height: 4, decoration: BoxDecoration(
                    color: UellowColors.border,
                    borderRadius: BorderRadius.circular(2))),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: TextField(
                    controller: search,
                    onChanged: (q) => setS(() {
                      final qq = q.trim().toLowerCase();
                      list = _countries.where((c) =>
                          c.name.toLowerCase().contains(qq) ||
                          c.nameAr.contains(q.trim()) ||
                          c.dial.contains(qq)).toList();
                    }),
                    decoration: InputDecoration(
                      hintText: _ar ? 'ابحث عن دولة' : 'Search country',
                      prefixIcon: const Icon(Icons.search),
                      fillColor: UellowColors.yellowFaint, filled: true,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none),
                    ),
                  ),
                ),
                Expanded(child: ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final c = list[i];
                    return ListTile(
                      leading: Text(c.flag, style: const TextStyle(fontSize: 26)),
                      title: Text(_ar ? c.nameAr : c.name),
                      trailing: Text('+${c.dial}', style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: UellowColors.darkBrown)),
                      onTap: () => Navigator.of(ctx).pop(c),
                    );
                  },
                )),
              ]),
            ),
          );
        });
      },
    );
    if (picked != null) setState(() => _country = picked);
  }

  Future<void> _firebaseLogin(String idToken) async {
    await UellowApi.instance.auth.firebaseSignIn(idToken, phone: _e164);
    unawaited(FcmService.instance.register());
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _send() async {
    final digits = _phone.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 6) {
      setState(() => _err = _ar ? 'أدخل رقم هاتف صحيح' : 'Enter a valid phone number');
      return;
    }
    setState(() { _busy = true; _err = null; });
    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: _e164,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (cred) async {
          try {
            final uc = await FirebaseAuth.instance.signInWithCredential(cred);
            final idt = await uc.user?.getIdToken() ?? '';
            if (idt.isNotEmpty) await _firebaseLogin(idt);
          } catch (_) {}
        },
        verificationFailed: (e) {
          if (mounted) setState(() { _busy = false; _err = _ar
              ? 'تعذر إرسال الرمز: ${e.message ?? ''}'
              : 'Could not send code: ${e.message ?? ''}'; });
        },
        codeSent: (vid, _) {
          if (mounted) setState(() { _verificationId = vid; _sent = true; _busy = false; });
        },
        codeAutoRetrievalTimeout: (vid) => _verificationId = vid,
      );
    } catch (e) {
      if (mounted) setState(() { _busy = false; _err = _ar ? 'تعذر إرسال الرمز' : 'Could not send the code'; });
    }
  }

  Future<void> _verify() async {
    if (_code.text.trim().length < 6) {
      setState(() => _err = _ar ? 'أدخل الرمز المكوّن من 6 أرقام' : 'Enter the 6-digit code');
      return;
    }
    setState(() { _busy = true; _err = null; });
    try {
      final cred = PhoneAuthProvider.credential(
          verificationId: _verificationId, smsCode: _code.text.trim());
      final uc = await FirebaseAuth.instance.signInWithCredential(cred);
      final idt = await uc.user?.getIdToken() ?? '';
      if (idt.isEmpty) throw Exception('no token');
      await _firebaseLogin(idt);
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() { _busy = false; _err = _ar
          ? 'رمز غير صحيح أو منتهي' : (e.message ?? 'Invalid code'); });
    } on UellowApiException catch (e) {
      if (mounted) setState(() { _busy = false; _err = e.message; });
    } catch (e) {
      if (mounted) setState(() { _busy = false; _err = _ar ? 'فشل التأكيد' : 'Verification failed'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ar = _ar;
    return Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          foregroundColor: UellowColors.darkBrown,
          title: Text(ar ? 'الدخول برقم الهاتف' : 'Sign in with phone',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: 8),
              Icon(_sent ? Icons.sms_outlined : Icons.smartphone,
                  size: 48, color: UellowColors.yellow),
              const SizedBox(height: 12),
              Text(
                _sent
                    ? (ar ? 'أدخل الرمز المُرسل إلى\n$_e164'
                          : 'Enter the code sent to\n$_e164')
                    : (ar ? 'اختر دولتك وأدخل رقم هاتفك، وسنرسل لك رمز تأكيد'
                          : 'Pick your country and enter your phone — we will text you a code'),
                style: const TextStyle(fontSize: 13, color: UellowColors.muted,
                    height: 1.4)),
              const SizedBox(height: 22),

              if (!_sent) Row(children: [
                // country selector — flag + dial code
                InkWell(
                  onTap: _busy ? null : _pickCountry,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
                    decoration: BoxDecoration(
                      color: UellowColors.yellowFaint,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: UellowColors.border, width: 1.5),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(_country.flag, style: const TextStyle(fontSize: 22)),
                      const SizedBox(width: 6),
                      Text('+${_country.dial}', style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: UellowColors.darkBrown, fontSize: 15)),
                      const Icon(Icons.arrow_drop_down, color: UellowColors.muted),
                    ]),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  autofocus: true,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  decoration: InputDecoration(
                    hintText: '5XXXXXXX',
                    fillColor: UellowColors.yellowFaint, filled: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: UellowColors.border, width: 1.5)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: UellowColors.border, width: 1.5)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
                  ),
                )),
              ]) else TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                autofocus: true,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(fontSize: 26, letterSpacing: 12,
                    fontWeight: FontWeight.w900),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  counterText: '', hintText: '••••••',
                  fillColor: UellowColors.yellowFaint, filled: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: UellowColors.border, width: 1.5)),
                ),
              ),

              if (_err != null) Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_err!, style: const TextStyle(
                    color: UellowColors.danger, fontSize: 12.5)),
              ),
              const SizedBox(height: 18),

              SizedBox(width: double.infinity, child: ElevatedButton(
                onPressed: _busy ? null : (_sent ? _verify : _send),
                style: ElevatedButton.styleFrom(
                  backgroundColor: UellowColors.yellow,
                  foregroundColor: UellowColors.darkBrown,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12))),
                ),
                child: _busy
                    ? const SizedBox(width: 18, height: 18, child:
                        CircularProgressIndicator(color: UellowColors.darkBrown, strokeWidth: 2))
                    : Text(_sent
                        ? (ar ? 'تأكيد الرمز' : 'Verify code')
                        : (ar ? 'إرسال الرمز' : 'Send code'),
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
              )),

              if (_sent) Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                TextButton(
                  onPressed: _busy ? null : () => setState(() {
                    _sent = false; _code.clear(); _err = null;
                  }),
                  child: Text(ar ? 'تغيير الرقم' : 'Change number',
                      style: const TextStyle(fontSize: 12.5,
                          color: UellowColors.darkBrown, fontWeight: FontWeight.w700)),
                ),
                TextButton(
                  onPressed: _busy ? null : _send,
                  child: Text(ar ? 'إعادة إرسال' : 'Resend code',
                      style: const TextStyle(fontSize: 12.5,
                          color: UellowColors.darkBrown, fontWeight: FontWeight.w700)),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
