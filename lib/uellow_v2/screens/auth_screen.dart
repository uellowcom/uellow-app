// =============================================================================
// AuthScreen — tabbed Sign in / Sign up + social providers + Phone OTP.
// Wires to UellowApi.auth.login / register / google / apple / facebook.
// =============================================================================
import 'package:flutter/material.dart';

import '../../api/uellow_api.dart';
import '../theme/uellow_l10n.dart';
import '../theme/uellow_theme.dart';
import '../widgets/uellow_logo.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, this.asSheet = false});
  // When shown as a modal sheet, success pops with `true` and the caller stays
  // on the same page (instead of redirecting to /home).
  final bool asSheet;
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

/// Show the login/register flow as a DIALOG that keeps the user on the
/// current page. Returns true when authentication succeeded.
Future<bool> showAuthSheet(BuildContext context) async {
  final r = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    useSafeArea: true,
    builder: (_) => const AuthScreen(asSheet: true),
  );
  return r == true;
}

class _AuthScreenState extends State<AuthScreen> {
  int _tab = 0;   // 0 = sign in, 1 = sign up
  bool _busy = false;
  String? _err;
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();

  Future<void> _submit() async {
    setState(() { _busy = true; _err = null; });
    try {
      if (_tab == 0) {
        await UellowApi.instance.auth.login(_email.text, _password.text);
      } else {
        await UellowApi.instance.auth.register(
          name: _name.text, email: _email.text,
          password: _password.text, phone: _phone.text,
        );
      }
      if (!mounted) return;
      if (widget.asSheet) {
        Navigator.of(context).pop(true);     // stay on the current page
      } else {
        Navigator.of(context).pushReplacementNamed('/home');
      }
    } on UellowApiException catch (e) {
      setState(() => _err = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFFFFD340), UellowColors.yellow, Color(0xFFC99000)],
        ),
      ),
      child: SafeArea(
        top: !widget.asSheet,
        child: ListView(
          padding: EdgeInsets.fromLTRB(24, widget.asSheet ? 16 : 40, 24, 30),
          children: [
            if (widget.asSheet)
              Align(alignment: Alignment.centerRight, child: IconButton(
                icon: const Icon(Icons.close, color: UellowColors.darkBrown),
                onPressed: () => Navigator.of(context).maybePop(false),
              ))
            else
              // Full page (e.g. after logout): give a way back to browsing
              // so the user isn't trapped on the login screen.
              Align(alignment: Alignment.centerLeft, child: TextButton.icon(
                onPressed: () => Navigator.of(context)
                    .pushNamedAndRemoveUntil('/home', (_) => false),
                icon: const Icon(Icons.arrow_back, color: UellowColors.darkBrown, size: 18),
                label: Text(
                    UellowApi.instance.lang.toLowerCase().startsWith('ar')
                        ? 'تصفّح كضيف' : 'Browse as guest',
                    style: const TextStyle(color: UellowColors.darkBrown,
                        fontWeight: FontWeight.w800)),
              )),
            _logo(),
            const SizedBox(height: 24),
            _card(),
          ],
        ),
      ),
    );
    if (widget.asSheet) {
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.9,
            child: content,
          ),
        ),
      );
    }
    return Scaffold(body: content);
  }

  Widget _logo() {
    return const Center(child: UellowLogo(height: 56));
  }

  Widget _card() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.circular(20)),
        boxShadow: [BoxShadow(color: Color(0x40412402),
            blurRadius: 40, offset: Offset(0, 16))],
      ),
      child: Column(children: [
        _tabs(),
        const SizedBox(height: 22),
        if (_tab == 1) _field(T.t('account.name'), _name, hint: T.t('account.name')),
        _field(_tab == 1 ? T.t('account.email') : T.t('account.email_or_phone'),
            _email, hint: 'you@example.com'),
        if (_tab == 1) _field(T.t('account.phone'), _phone, hint: '+965 9999 0000'),
        _field(T.t('account.password'), _password, hint: '••••••••', obscure: true),
        if (_err != null) Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(_err!, style: const TextStyle(color: UellowColors.danger, fontSize: 12)),
        ),
        if (_tab == 0) Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(children: [
            const Checkbox(value: true, onChanged: null, activeColor: UellowColors.yellow),
            Text(T.t('account.remember'), style: const TextStyle(color: UellowColors.text, fontSize: 12)),
            const Spacer(),
            Text(T.t('account.forgot'),
                style: const TextStyle(color: UellowColors.darkBrown,
                    fontWeight: FontWeight.w800, fontSize: 12)),
          ]),
        ),
        const SizedBox(height: 14),
        SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: _busy ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: UellowColors.yellow,
            foregroundColor: UellowColors.darkBrown,
            padding: const EdgeInsets.symmetric(vertical: 14),
            elevation: 4,
            shadowColor: UellowColors.yellow.withValues(alpha: 0.4),
            shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(12))),
          ),
          child: _busy
              ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(color: UellowColors.darkBrown, strokeWidth: 2))
              : Text(_tab == 0 ? T.t('account.signin_arrow') : T.t('account.create'),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
        )),
        const SizedBox(height: 18),
        Row(children: [
          const Expanded(child: Divider(color: UellowColors.border)),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(T.t('account.or'),
                  style: const TextStyle(color: UellowColors.muted, fontSize: 11))),
          const Expanded(child: Divider(color: UellowColors.border)),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _socialBtn('Google', Icons.g_mobiledata, const Color(0xFF4285F4),
              () => _socialPending('Google'))),
          const SizedBox(width: 8),
          Expanded(child: _socialBtn('Apple', Icons.apple, Colors.black,
              () => _socialPending('Apple'))),
        ]),
        const SizedBox(height: 8),
        SizedBox(width: double.infinity, child: _socialBtn(
            UellowApi.instance.lang.toLowerCase().startsWith('ar')
                ? 'رمز لمرة واحدة (OTP)' : 'One-time code (OTP)',
            Icons.password_outlined, UellowColors.darkBrown,
            _otpFlow)),
        const SizedBox(height: 16),
        Text(T.t('account.terms'),
            style: const TextStyle(color: UellowColors.text, fontSize: 11),
            textAlign: TextAlign.center),
      ]),
    );
  }

  Widget _tabs() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: const BoxDecoration(
        color: UellowColors.border,
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      child: Row(children: [
        Expanded(child: _tabBtn(T.t('account.sign_in'), 0)),
        const SizedBox(width: 4),
        Expanded(child: _tabBtn(T.t('account.create_short'), 1)),
      ]),
    );
  }

  Widget _tabBtn(String label, int idx) {
    final on = _tab == idx;
    return GestureDetector(
      onTap: () => setState(() {
        // v2.0.76 — when switching to sign-up tab, clear pre-filled fields
        // so the user starts fresh (was leaking the sign-in email).
        if (idx == 1 && _tab != 1) {
          _email.clear(); _password.clear();
          _name.clear(); _phone.clear();
          _err = null;
        }
        _tab = idx;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: on ? UellowColors.darkBrown : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(label, style: TextStyle(
            color: on ? UellowColors.yellowLight : UellowColors.text,
            fontWeight: FontWeight.w800, fontSize: 13)),
      ),
    );
  }

  Widget _field(String label, TextEditingController c, {String? hint, bool obscure = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(label.toUpperCase(), style: const TextStyle(
                fontSize: 11, color: UellowColors.muted, fontWeight: FontWeight.w800,
                letterSpacing: 0.5))),
        TextField(
          controller: c, obscureText: obscure,
          decoration: InputDecoration(
            hintText: hint,
            fillColor: UellowColors.yellowFaint, filled: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: UellowColors.border, width: 1.5)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: UellowColors.border, width: 1.5)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
        ),
      ]),
    );
  }

  Widget _socialBtn(String label, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: UellowColors.border, width: 1.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(
              fontWeight: FontWeight.w700, fontSize: 13, color: color)),
        ]),
      ),
    );
  }

  // v2.1.16 — email OTP sign-in: ask for email (or account phone), send a
  // 6-digit code, verify, and complete exactly like a password login.
  Future<void> _otpFlow() async {
    final ar = UellowApi.instance.lang.toLowerCase().startsWith('ar');
    final target = TextEditingController(text: _email.text);
    final codeCtl = TextEditingController();
    bool sent = false; bool busy = false; String? err; String maskedTo = '';
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        Future<void> send() async {
          setS(() { busy = true; err = null; });
          try {
            maskedTo = await UellowApi.instance.auth
                .otpSend(target.text.trim());
            setS(() { sent = true; busy = false; });
          } on UellowApiException catch (e) {
            setS(() { err = e.message; busy = false; });
          }
        }
        Future<void> verify() async {
          setS(() { busy = true; err = null; });
          try {
            await UellowApi.instance.auth.otpCheck(
                target: target.text.trim(), code: codeCtl.text.trim());
            if (ctx.mounted) Navigator.of(ctx).pop(true);
          } on UellowApiException catch (e) {
            setS(() { err = e.message; busy = false; });
          }
        }
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 18, 20,
              MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(ar ? 'الدخول برمز لمرة واحدة' : 'Sign in with a one-time code',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900,
                    color: UellowColors.darkBrown)),
            const SizedBox(height: 4),
            Text(sent
                ? (ar ? 'أرسلنا الرمز إلى $maskedTo' : 'We sent a code to $maskedTo')
                : (ar ? 'أدخل بريدك الإلكتروني أو رقم هاتفك وسنرسل لك رمز دخول'
                      : 'Enter your email or phone and we will send you a sign-in code'),
                style: const TextStyle(fontSize: 12, color: UellowColors.muted)),
            const SizedBox(height: 14),
            if (!sent) TextField(
              controller: target,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                hintText: 'you@example.com / 9XXXXXXX',
                fillColor: UellowColors.yellowFaint, filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ) else TextField(
              controller: codeCtl,
              keyboardType: TextInputType.number,
              maxLength: 6,
              style: const TextStyle(fontSize: 22, letterSpacing: 10,
                  fontWeight: FontWeight.w900),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                counterText: '', hintText: '••••••',
                fillColor: UellowColors.yellowFaint, filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            if (err != null) Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(err!, style: const TextStyle(
                  color: UellowColors.danger, fontSize: 12)),
            ),
            const SizedBox(height: 14),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: busy ? null : (sent ? verify : send),
              style: ElevatedButton.styleFrom(
                backgroundColor: UellowColors.yellow,
                foregroundColor: UellowColors.darkBrown,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12))),
              ),
              child: busy
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(
                          color: UellowColors.darkBrown, strokeWidth: 2))
                  : Text(sent
                      ? (ar ? 'تأكيد الرمز' : 'Verify code')
                      : (ar ? 'إرسال الرمز' : 'Send code'),
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 14)),
            )),
            if (sent) TextButton(
              onPressed: busy ? null : send,
              child: Text(ar ? 'إعادة إرسال الرمز' : 'Resend code',
                  style: const TextStyle(fontSize: 12,
                      color: UellowColors.darkBrown,
                      fontWeight: FontWeight.w700)),
            ),
          ]),
        );
      }),
    );
    if (done == true && mounted) {
      if (widget.asSheet) {
        Navigator.of(context).pop(true);
      } else {
        Navigator.of(context).pushReplacementNamed('/home');
      }
    }
  }

  void _socialPending(String name) {
    // v2.0.79 — bilingual placeholder until each provider's SDK is wired
    // (Apple/Google/Etisalat need separate auth-flow integrations).
    final ar = UellowApi.instance.lang.toLowerCase().startsWith('ar');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ar
          ? 'تسجيل الدخول عبر $name سيتاح قريباً — استخدم البريد الإلكتروني ورقم الهاتف الآن'
          : '$name sign-in is coming soon — use email + password for now'),
      duration: const Duration(seconds: 3),
    ));
  }
}
