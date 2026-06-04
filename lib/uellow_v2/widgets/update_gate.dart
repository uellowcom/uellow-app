// =============================================================================
// UpdateGate (v2.1.50) — premium in-app update prompt.
//
// Backend control (Mobile App → Settings):
//   app_version_android / app_version_ios  → minimum required version
//   force_update                            → true = blocking (no skip)
//
// When the running version is older than min_version a beautiful sheet
// appears: soft-update shows a "Later" escape, force-update is a full
// barrier (back button + outside taps disabled).
// =============================================================================
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/uellow_api.dart';
import '../../api/uellow_models.dart';
import '../../version.dart';
import '../theme/uellow_theme.dart';

class UpdateGate {
  static bool _shown = false;

  /// Compare dotted versions: returns true when [minimum] > [current].
  static bool _isOutdated(String current, String minimum) {
    List<int> parse(String v) => v
        .replaceAll(RegExp(r'[^0-9.]'), '')
        .split('.')
        .where((p) => p.isNotEmpty)
        .map(int.parse)
        .toList();
    final c = parse(current), m = parse(minimum);
    if (m.isEmpty) return false;
    for (var i = 0; i < m.length; i++) {
      final cv = i < c.length ? c[i] : 0;
      if (m[i] > cv) return true;
      if (m[i] < cv) return false;
    }
    return false;
  }

  static void check(BuildContext context, UellowAppSettings s) {
    if (_shown) return;
    final min = s.minVersion.trim();
    if (min.isEmpty || !_isOutdated(kAppVersion, min)) return;
    _shown = true;
    showGeneralDialog(
      context: context,
      barrierDismissible: !s.forceUpdate,
      barrierLabel: 'update',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 280),
      transitionBuilder: (_, anim, __, child) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(
            scale: Tween(begin: 0.92, end: 1.0).animate(
                CurvedAnimation(parent: anim, curve: Curves.easeOutBack)),
            child: child),
      ),
      pageBuilder: (ctx, _, __) => _UpdateDialog(
          minVersion: min, force: s.forceUpdate,
          storeUrl: (s.urls['play_store'] ?? '').toString()),
    );
  }
}

class _UpdateDialog extends StatelessWidget {
  const _UpdateDialog({required this.minVersion, required this.force,
      required this.storeUrl});
  final String minVersion;
  final bool force;
  final String storeUrl;

  Future<void> _update() async {
    final url = storeUrl.isNotEmpty
        ? storeUrl
        : 'https://github.com/uellowcom/uellow-app/releases/latest';
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return PopScope(
      canPop: !force,                      // force = back button disabled
      child: Center(child: Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 28),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [BoxShadow(
                color: Color(0x55000000), blurRadius: 30,
                offset: Offset(0, 12))],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // ── hero header ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 26, 20, 22),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [Color(0xFF412402), Color(0xFF6B3A05),
                           Color(0xFF8B5A0B)],
                ),
              ),
              child: Column(children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFFFFD340), Color(0xFFE8A800)]),
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(
                        color: const Color(0xFFF5C320)
                            .withValues(alpha: 0.55),
                        blurRadius: 26, spreadRadius: 2)],
                  ),
                  child: const Text('🚀', style: TextStyle(fontSize: 34)),
                ),
                const SizedBox(height: 14),
                Text(ar ? 'تحديث جديد متاح!' : 'A new update is here!',
                    style: const TextStyle(color: Colors.white,
                        fontSize: 19, fontWeight: FontWeight.w900)),
                const SizedBox(height: 10),
                // version chips: current → new
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  _verChip('v$kAppVersion', const Color(0x33FFFFFF),
                      const Color(0xCCFFFFFF)),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.arrow_forward, size: 15,
                        color: Color(0xFFFFD340)),
                  ),
                  _verChip('v$minVersion', const Color(0xFFFFD340),
                      const Color(0xFF412402)),
                ]),
              ]),
            ),
            // ── body ──
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
              child: Column(children: [
                Text(
                    ar
                        ? 'حدّثنا التطبيق بمزايا جديدة، أداءٍ أسرع وإصلاحات مهمة. حدّث الآن لتحصل على أفضل تجربة تسوق.'
                        : 'We shipped new features, faster performance and important fixes. Update now for the best shopping experience.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12.5, height: 1.65,
                        color: UellowColors.text)),
                const SizedBox(height: 16),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  _perk('⚡', ar ? 'أسرع' : 'Faster'),
                  _perk('✨', ar ? 'مزايا جديدة' : 'New features'),
                  _perk('🛡️', ar ? 'أكثر أماناً' : 'More secure'),
                ]),
                const SizedBox(height: 18),
                SizedBox(width: double.infinity, child: ElevatedButton.icon(
                  onPressed: _update,
                  icon: const Icon(Icons.system_update_alt, size: 17),
                  label: Text(ar ? 'تحديث الآن' : 'Update now',
                      style: const TextStyle(fontSize: 14.5,
                          fontWeight: FontWeight.w900)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: UellowColors.yellow,
                    foregroundColor: UellowColors.darkBrown,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                )),
                if (!force) TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(ar ? 'لاحقاً' : 'Later',
                      style: const TextStyle(fontSize: 12.5,
                          color: UellowColors.muted,
                          fontWeight: FontWeight.w600)),
                )
                else Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                    const Icon(Icons.lock_outline, size: 12,
                        color: UellowColors.muted),
                    const SizedBox(width: 4),
                    Text(ar
                            ? 'هذا التحديث إلزامي لمتابعة الاستخدام'
                            : 'This update is required to continue',
                        style: const TextStyle(fontSize: 10.5,
                            color: UellowColors.muted,
                            fontWeight: FontWeight.w600)),
                  ]),
                ),
              ]),
            ),
          ]),
        ),
      )),
    );
  }

  static Widget _verChip(String label, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
        color: bg, borderRadius: BorderRadius.circular(999)),
    child: Text(label, style: TextStyle(fontSize: 11.5,
        fontWeight: FontWeight.w900, color: fg)),
  );

  static Widget _perk(String emoji, String label) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Column(children: [
      Text(emoji, style: const TextStyle(fontSize: 18)),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(fontSize: 10,
          fontWeight: FontWeight.w700, color: UellowColors.muted)),
    ]),
  );
}
