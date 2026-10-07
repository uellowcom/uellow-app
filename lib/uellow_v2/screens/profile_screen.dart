// =============================================================================
// ProfileScreen — edit account fields (name, email, phone, language).
// Wires to /api/mobile/v2/profile/update.
// =============================================================================
import 'package:flutter/material.dart';

import '../../api/uellow_api.dart';
import '../theme/uellow_l10n.dart';
import '../theme/uellow_theme.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final me = await UellowApi.instance.auth.me();
      if (!mounted) return;
      _name.text  = me.name;
      _email.text = me.email;
      _phone.text = me.phone;
    } on UellowApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)));
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await UellowApi.instance.profile.update(
        name: _name.text.trim(),
        email: _email.text.trim(),
        phone: _phone.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(UellowApi.instance.lang == 'ar'
            ? 'تم حفظ التغييرات' : 'Profile updated'),
        backgroundColor: UellowColors.success,
      ));
      Navigator.pop(context);
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
    return Scaffold(
      backgroundColor: UellowColors.bg,
      appBar: AppBar(
        title: Text(ar ? 'ملفي الشخصي' : 'My profile'),
        backgroundColor: Colors.white,
      ),
      body: SafeArea(child: _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(padding: const EdgeInsets.all(16), children: [
            _field(T.t('account.name'), _name),
            const SizedBox(height: 12),
            _field(T.t('account.email'), _email),
            const SizedBox(height: 12),
            _field(T.t('account.phone'), _phone),
            const SizedBox(height: 24),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: _busy ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: UellowColors.yellow,
                foregroundColor: UellowColors.darkBrown,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _busy
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: UellowColors.darkBrown))
                : Text(T.t('action.save'),
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
            )),
            const SizedBox(height: 20),
            Card(child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(ar ? 'إعدادات الحساب' : 'Account settings',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                const SizedBox(height: 8),
                _link(ar ? 'تغيير كلمة المرور' : 'Change password',
                    Icons.lock_outline, _openChangePassword),
                _link(ar ? 'العناوين' : 'My addresses',
                    Icons.location_on_outlined, () => Navigator.pushNamed(context, '/addresses')),
                _link(ar ? 'الإعدادات' : 'Settings',
                    Icons.settings_outlined, () => Navigator.pushNamed(context, '/settings')),
                const Divider(height: 18),
                InkWell(onTap: _confirmDeleteAccount, child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(children: [
                    const Icon(Icons.delete_outline, size: 18, color: Color(0xFFD6453C)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(ar ? 'حذف حسابي' : 'Delete my account',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFFD6453C)))),
                    const Icon(Icons.chevron_right, color: Color(0x66D6453C)),
                  ]),
                )),
              ]),
            )),
          ])),
    );
  }

  Widget _field(String label, TextEditingController c) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(label.toUpperCase(), style: const TextStyle(
              fontSize: 11, color: UellowColors.muted,
              fontWeight: FontWeight.w800, letterSpacing: 0.5))),
      TextField(
        controller: c,
        decoration: InputDecoration(
          fillColor: Colors.white, filled: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: UellowColors.border, width: 1.5)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: UellowColors.border, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
      ),
    ]);
  }

  Widget _link(String label, IconData icon, VoidCallback onTap) {
    return InkWell(onTap: onTap, child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Icon(icon, size: 18, color: UellowColors.darkBrown),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: const TextStyle(
            fontWeight: FontWeight.w600, fontSize: 13))),
        const Icon(Icons.chevron_right, color: UellowColors.muted),
      ]),
    ));
  }

  Future<void> _confirmDeleteAccount() async {
    final ar = UellowApi.instance.lang == 'ar';
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(ar ? 'حذف الحساب' : 'Delete account',
            style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFFD6453C))),
        content: Text(ar
            ? 'سيتم حذف حسابك وبياناتك الشخصية نهائيًا ولا يمكن التراجع عن هذا الإجراء. هل تريد المتابعة؟'
            : 'Your account and personal data will be permanently deleted. This cannot be undone. Continue?',
            style: const TextStyle(height: 1.5)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false),
              child: Text(ar ? 'إلغاء' : 'Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFD6453C)),
            onPressed: () => Navigator.pop(d, true),
            child: Text(ar ? 'حذف نهائيًا' : 'Delete permanently')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    showDialog(context: context, barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator(color: UellowColors.darkBrown)));
    try {
      await UellowApi.instance.profile.deleteAccount();
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ar ? 'تم حذف حسابك' : 'Your account has been deleted')));
      Navigator.of(context).pushNamedAndRemoveUntil('/home', (r) => false);
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ar ? 'تعذّر حذف الحساب، حاول مجددًا' : 'Could not delete account, try again')));
    }
  }

  void _openChangePassword() {
    final ar = UellowApi.instance.lang == 'ar';
    final oldP = TextEditingController();
    final newP = TextEditingController();
    final newP2 = TextEditingController();
    bool busy = false;
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheet) => StatefulBuilder(builder: (ctx, set) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
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
            Text(ar ? 'تغيير كلمة المرور' : 'Change password', style: UT.h2),
            const SizedBox(height: 14),
            _pw(ar ? 'كلمة المرور الحالية' : 'Current password', oldP),
            _pw(ar ? 'كلمة المرور الجديدة' : 'New password', newP),
            _pw(ar ? 'تأكيد كلمة المرور' : 'Confirm new password', newP2),
            const SizedBox(height: 14),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: busy ? null : () async {
                if (newP.text.trim() != newP2.text.trim()) {
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                      content: Text(ar ? 'كلمتا المرور غير متطابقتين'
                                       : 'Passwords do not match')));
                  return;
                }
                if (newP.text.trim().length < 6) {
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                      content: Text(ar ? 'كلمة المرور قصيرة جداً'
                                       : 'Password too short')));
                  return;
                }
                set(() => busy = true);
                try {
                  await UellowApi.instance.profile.changePassword(
                    oldPassword: oldP.text, newPassword: newP.text);
                  if (!sheet.mounted) return;
                  Navigator.pop(sheet);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(ar ? 'تم تغيير كلمة المرور'
                                       : 'Password changed'),
                      backgroundColor: UellowColors.success));
                } on UellowApiException catch (e) {
                  set(() => busy = false);
                  ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text(e.message)));
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: UellowColors.yellow,
                foregroundColor: UellowColors.darkBrown,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: busy
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2,
                        color: UellowColors.darkBrown))
                : Text(ar ? 'حفظ' : 'Update password',
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
            )),
          ]),
        ),
      )),
    );
  }

  Widget _pw(String label, TextEditingController c) {
    return Padding(padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c, obscureText: true,
          decoration: InputDecoration(
            labelText: label, isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ));
  }
}
