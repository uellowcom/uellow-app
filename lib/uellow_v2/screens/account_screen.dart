// =============================================================================
// AccountScreen — fetches /api/mobile/v2/account/overview and renders the
// user's real profile / loyalty / wallet / orders. Falls back to a friendly
// "sign in" view when no token.
// =============================================================================
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/uellow_api.dart';
import '../router/uellow_router.dart';
import '../theme/uellow_theme.dart';
import '../widgets/review_prompt_dialog.dart';
import '../widgets/uellow_bottom_nav.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  Future<Map<String, dynamic>?>? _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<Map<String, dynamic>?> _fetch() async {
    final token = await UellowApi.instance.tokenStore.readToken();
    if (token == null || token.isEmpty) return null;
    try {
      final uri = Uri.parse('${UellowApi.instance.baseUrl}/api/mobile/v2/account/overview');
      final r = await http.get(uri, headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      });
      final body = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (body['success'] == true) return body['data'] as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UellowColors.bg,
      bottomNavigationBar: const UellowBottomNav(active: UNavTab.account),
      body: SafeArea(bottom: false, child: FutureBuilder<Map<String, dynamic>?>(
        future: _future,
        builder: (_, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: UellowColors.darkBrown));
          }
          // Render the full layout for both authenticated users and
          // guests. When `data` is null the user isn't signed in — every
          // tile prompts them to sign in instead of opening the
          // protected destination (handled inside _ActionTiles etc.).
          return _buildContent(snap.data);
        },
      )),
    );
  }

  Widget _buildContent(Map<String, dynamic>? data) {
    final isGuest = data == null;
    final user = (data?['user'] as Map?) ?? const {};
    final banners = (data?['banners'] as List?) ?? const [];
    final stats = (data?['stats'] as Map?) ?? const {};
    final recent = data?['recent_order'] as Map?;
    final ar = UellowApi.instance.lang == 'ar';
    return RefreshIndicator(
      onRefresh: () async => setState(() => _future = _fetch()),
      child: ListView(padding: EdgeInsets.zero, children: [
        _ProfileHeader(user: user, isGuest: isGuest),
        // v2.1.57 — targeted announcement strip (admin-controlled).
        if (isGuest) _GuestSigninBanner(),
        if (!isGuest) _BannersRow(banners: banners),
        if (!isGuest && recent != null) _RecentOrderCard(order: recent),
        _SectionCard(
          title: ar ? 'طلباتي' : 'My Orders',
          trailingText: ar ? 'عرض الكل ›' : 'See all ›',
          onTrailing: () => _guard(context, isGuest,
              () => Navigator.pushNamed(context, '/orders')),
          child: _OrdersGrid(stats: stats, isGuest: isGuest)),
        const _RecentlyViewed(),
        _SectionCard(title: '', tightHorizontal: true,
            child: _ActionTiles(isGuest: isGuest)),
        // v2.1.68 — shown to GUESTS too: tapping Apply sends them to
        // sign in first (the card knows isGuest).
        _BecomeReviewerCard(isGuest: isGuest),
        const _MenuList(),
        const _SocialMediaSection(),
        if (!isGuest) const _SignOutBtn(),
        const _Version(),
      ]),
    );
  }

  /// Tap-shim used by every protected action — opens /auth instead of
  /// the destination when the user is a guest.
  static void _guard(BuildContext context, bool isGuest, VoidCallback go) {
    if (isGuest) {
      Navigator.pushNamed(context, '/auth');
    } else {
      go();
    }
  }
}

/// Sign-in banner shown directly under the avatar for guests so they
/// can clearly opt into the protected sections without losing context.
class _GuestSigninBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFFFFE066), UellowColors.yellow]),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        const Icon(Icons.person_outline, color: UellowColors.darkBrown),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(ar ? 'سجّل دخولك لتفعيل كل المزايا' : 'Sign in to unlock all features',
              style: const TextStyle(fontWeight: FontWeight.w900,
                  color: UellowColors.darkBrown, fontSize: 13.5)),
          Text(ar ? 'الطلبات · الولاء · المحفظة · المفضلة'
                  : 'Orders · Loyalty · Wallet · Wishlist',
              style: const TextStyle(color: Color(0xCC412402), fontSize: 11)),
        ])),
        ElevatedButton(
          onPressed: () => Navigator.pushNamed(context, '/auth'),
          style: ElevatedButton.styleFrom(
            backgroundColor: UellowColors.darkBrown,
            foregroundColor: UellowColors.yellowLight,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(10))),
          ),
          child: Text(ar ? 'دخول' : 'Sign in',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
        ),
      ]),
    );
  }
}

/// Social media section — light, compact, professional. Tap each icon
/// opens the official Uellow page in the platform browser.
class _SocialMediaSection extends StatelessWidget {
  const _SocialMediaSection();
  static const _channels = [
    (icon: Icons.facebook,           color: Color(0xFF1877F2),
        label: 'Facebook',  url: 'https://facebook.com/uellow'),
    (icon: Icons.camera_alt_outlined, color: Color(0xFFE4405F),
        label: 'Instagram', url: 'https://instagram.com/uellow'),
    (icon: Icons.tag,                 color: Color(0xFF000000),
        label: 'TikTok',    url: 'https://tiktok.com/@uellow'),
    (icon: Icons.alternate_email,     color: Color(0xFF1DA1F2),
        label: 'X',         url: 'https://x.com/uellow'),
    (icon: Icons.video_library_outlined, color: Color(0xFFFF0000),
        label: 'YouTube',   url: 'https://youtube.com/@uellow'),
    (icon: Icons.chat,                color: Color(0xFF25D366),
        label: 'WhatsApp',  url: 'https://wa.me/96560000000'),
  ];
  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(ar ? 'تابعنا' : 'Follow us', style: UT.h3),
        const SizedBox(height: 4),
        Text(ar ? 'كن أول من يعرف بالعروض والمنتجات الجديدة'
                : 'Be first to hear about deals and new arrivals',
            style: UT.subtitle),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: _channels.map((c) => _Channel(
              icon: c.icon, color: c.color, label: c.label, url: c.url,
            )).toList()),
      ]),
    );
  }
}

class _Channel extends StatelessWidget {
  const _Channel({required this.icon, required this.color,
      required this.label, required this.url});
  final IconData icon;
  final Color color;
  final String label;
  final String url;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => launchUrl(Uri.parse(url),
          mode: LaunchMode.externalApplication),
      borderRadius: BorderRadius.circular(12),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.18)),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 9.5,
            color: UellowColors.muted, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _ProfileHeader extends StatefulWidget {
  const _ProfileHeader({required this.user, this.isGuest = false});
  final Map user;
  final bool isGuest;
  @override
  State<_ProfileHeader> createState() => _ProfileHeaderState();
}

class _ProfileHeaderState extends State<_ProfileHeader> {
  String? _avatarOverride;     // local URL OR data: URI after upload
  Uint8List? _avatarBytes;     // raw bytes — instant render after upload
  bool _busy = false;

  String? _guestCountry;
  @override
  void initState() {
    super.initState();
    // Pull the saved country code for guests so the flag chip still
    // shows — they may not have a profile country yet.
    if (widget.isGuest) {
      SharedPreferences.getInstance().then((p) {
        final c = p.getString('uellow_country_code_v1');
        if (c != null && c.isNotEmpty && mounted) {
          setState(() => _guestCountry = c.toUpperCase());
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    final name = widget.isGuest
        ? (ar ? 'ضيف' : 'Guest')
        : ((widget.user['name'] as String?) ?? (ar ? 'عميل' : 'Customer'));
    final country = (widget.user['country'] as String?)
        ?? _guestCountry
        ?? 'KW';
    // Live avatar — listens to the global notifier so any upload (here or
    // on the profile screen) immediately re-paints this header.
    return ValueListenableBuilder<String>(
      valueListenable: UellowApi.instance.avatarNotifier,
      builder: (ctx, globalAvatar, _) {
        final avatar = _avatarOverride
            ?? (globalAvatar.isNotEmpty ? globalAvatar : null)
            ?? (widget.user['avatar'] as String?) ?? '';
        return _buildHeader(ar, name, country, avatar);
      },
    );
  }

  Widget _buildHeader(bool ar, String name, String country, String avatar) {
    final flag = _flagOf(country);
    final currency = _currencyOf(country);
    // Compact header: flag chip · avatar (center) · settings · all
    // on a single row. Tap avatar opens a chooser sheet to update the
    // profile photo (SHEIN/DHGate style).
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          // ── Country flag chip (left) ────────────────
          if (flag.isNotEmpty) Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: UellowColors.yellowSoft,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: UellowColors.yellow),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(flag, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              Text('$country · $currency', style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w800,
                  color: UellowColors.darkBrown)),
            ]),
          ),
          const Spacer(),
          // ── Avatar (center) — tap = change photo, or sign in
          GestureDetector(
            onTap: _busy ? null : () {
              if (widget.isGuest) {
                Navigator.pushNamed(context, '/auth');
              } else {
                _openAvatarSheet(context);
              }
            },
            child: Stack(clipBehavior: Clip.none, children: [
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFE066), UellowColors.yellow]),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: const [BoxShadow(
                      color: Color(0x29000000), blurRadius: 8, offset: Offset(0, 3))],
                ),
                clipBehavior: Clip.antiAlias,
                child: _busy
                  ? const Center(child: SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2,
                        color: UellowColors.darkBrown)))
                  : (_avatarBytes != null
                      // freshly-uploaded photo → instant render via memory
                      ? Image.memory(_avatarBytes!, fit: BoxFit.cover,
                          errorBuilder: (_,__,___) => _initial(name))
                      : (avatar.isNotEmpty
                          ? (avatar.startsWith('data:')
                              // data URI from the server (post-upload)
                              ? Image.memory(
                                  base64Decode(avatar.split(',').last),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_,__,___) => _initial(name))
                              : Image.network(avatar, fit: BoxFit.cover,
                                  errorBuilder: (_,__,___) => _initial(name)))
                          : _initial(name))),
              ),
              Positioned(bottom: -2, right: -2, child: Container(
                width: 22, height: 22,
                decoration: BoxDecoration(
                  color: UellowColors.darkBrown,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(Icons.camera_alt_outlined, size: 11,
                    color: UellowColors.yellowLight),
              )),
            ]),
          ),
          const Spacer(),
          // ── Settings (right) ────────────────────────
          IconButton(
            onPressed: () => Navigator.pushNamed(context, '/settings'),
            icon: const Icon(Icons.settings_outlined,
                color: UellowColors.darkBrown),
            style: IconButton.styleFrom(
              backgroundColor: UellowColors.yellowSoft,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(10))),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: UT.h2),
            const SizedBox(height: 2),
            Text(ar ? 'مرحباً بك في Uellow' : 'Welcome to Uellow',
                style: UT.subtitle),
          ])),
          // Tiny "Edit profile" / "Sign in" pill
          GestureDetector(
            onTap: () => Navigator.pushNamed(context,
                widget.isGuest ? '/auth' : '/profile'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: UellowColors.bg,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: UellowColors.border),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.edit_outlined, size: 12,
                    color: UellowColors.darkBrown),
                const SizedBox(width: 4),
                Text(widget.isGuest
                        ? (ar ? 'تسجيل الدخول' : 'Sign in')
                        : (ar ? 'تعديل الملف' : 'Edit profile'),
                    style: const TextStyle(color: UellowColors.darkBrown,
                        fontSize: 11, fontWeight: FontWeight.w800)),
              ]),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _initial(String name) => Container(
    alignment: Alignment.center,
    child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'U',
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900,
            color: UellowColors.darkBrown)),
  );

  String _flagOf(String code) {
    if (code.length != 2) return '🌐';
    final base = 127397;   // 'A' regional indicator base
    return String.fromCharCodes([code.codeUnitAt(0) + base, code.codeUnitAt(1) + base]);
  }

  String _currencyOf(String code) {
    const map = {
      'KW': 'KWD', 'SA': 'SAR', 'AE': 'AED', 'QA': 'QAR',
      'OM': 'OMR', 'EG': 'EGP', 'US': 'USD',
    };
    return map[code] ?? '—';
  }

  // ── Avatar change flow ──────────────────────────────────────────
  // Bottom sheet → camera/gallery → POST base64 to /api/mobile/v2/
  // profile/avatar. The server stores into res.partner.image_1920
  // and returns the new image URL.

  Future<void> _openAvatarSheet(BuildContext context) async {
    final ar = UellowApi.instance.lang == 'ar';
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius:
          BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4, margin: const EdgeInsets.only(top: 8, bottom: 12),
          decoration: BoxDecoration(color: UellowColors.border,
              borderRadius: BorderRadius.circular(2))),
        Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(ar ? 'تغيير صورة الملف' : 'Change profile photo',
                style: UT.h3)),
        ListTile(
          leading: const Icon(Icons.photo_camera_outlined,
              color: UellowColors.darkBrown),
          title: Text(ar ? 'التقط صورة' : 'Take photo',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          onTap: () => Navigator.pop(context, ImageSource.camera),
        ),
        ListTile(
          leading: const Icon(Icons.photo_library_outlined,
              color: UellowColors.darkBrown),
          title: Text(ar ? 'اختر من المعرض' : 'Choose from gallery',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          onTap: () => Navigator.pop(context, ImageSource.gallery),
        ),
        const SizedBox(height: 8),
      ])),
    );
    if (src == null || !mounted) return;
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: src,
        maxWidth: 800, maxHeight: 800, imageQuality: 85);
    if (picked == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final bytes = await File(picked.path).readAsBytes();
      final b64 = base64Encode(bytes);
      final token = await UellowApi.instance.tokenStore.readToken();
      final r = await http.post(
        Uri.parse('${UellowApi.instance.baseUrl}/api/mobile/v2/profile/avatar'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'image_base64': b64}),
      );
      final body = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (body['success'] == true && mounted) {
        final data = body['data'] as Map<String, dynamic>? ?? const {};
        final dataUri = data['avatar_data_uri'] as String?;
        final url     = data['avatar_url'] as String?;
        final winner = (dataUri?.isNotEmpty == true)
            ? dataUri!
            : (url?.isNotEmpty == true ? url! : _avatarOverride);
        setState(() {
          _avatarOverride = winner;
          _avatarBytes = bytes;
          _busy = false;
        });
        // Broadcast to the rest of the app — any screen listening to
        // avatarNotifier will immediately re-paint with the new image.
        if (winner != null && winner.isNotEmpty) {
          UellowApi.instance.setAvatar(winner);
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(ar ? 'تم تحديث الصورة' : 'Profile photo updated')));
      } else if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text((body['error'] ?? 'Upload failed').toString())));
      }
    } catch (e) {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// Loyalty + Wallet side-by-side cards. Replaces the horizontal slider
/// with a single row of two professional gradient cards so the user can
/// see both at-a-glance without having to scroll.
class _BannersRow extends StatelessWidget {
  const _BannersRow({required this.banners});
  final List banners;
  @override
  Widget build(BuildContext context) {
    // Find loyalty + wallet by their `kind` (server-side names them).
    Map? loyalty, wallet;
    for (final b in banners) {
      if (b is Map) {
        final k = b['kind'] as String?;
        if (k == 'loyalty' && loyalty == null) loyalty = b;
        if (k == 'wallet'  && wallet  == null) wallet  = b;
      }
    }
    // Defensive fallback — if backend ever returns neither, show both blank.
    loyalty ??= const {'kind': 'loyalty', 'title': {'en': 'Loyalty', 'ar': 'الولاء'},
        'subtitle': {'en': 'Earn rewards', 'ar': 'اكسب نقاط'},
        'cta': {'en': 'Open', 'ar': 'فتح'}};
    wallet  ??= const {'kind': 'wallet',  'title': {'en': 'Wallet',  'ar': 'المحفظة'},
        'subtitle': {'en': 'Manage credit', 'ar': 'إدارة الرصيد'},
        'cta': {'en': 'Open', 'ar': 'فتح'}};
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _BannerCard(banner: loyalty)),
          const SizedBox(width: 10),
          Expanded(child: _BannerCard(banner: wallet)),
        ])),
    );
  }
}

class _BannerCard extends StatelessWidget {
  const _BannerCard({required this.banner});
  final Map banner;
  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    final lang = ar ? 'ar' : 'en';
    final kind = (banner['kind'] as String?) ?? 'loyalty';
    final isLoyalty = kind == 'loyalty';
    final title = (banner['title'] as Map?)?[lang] as String? ?? '';
    final sub   = (banner['subtitle'] as Map?)?[lang] as String? ?? '';
    final progressPct = (banner['progress_pct'] as int?) ?? 0;
    // Big value is what counts. Server gives us subtitle like "1,250 points · Silver"
    // — keep the FIRST word as the headline, the rest as caption.
    final parts = sub.split(' ');
    final big = parts.isNotEmpty ? parts.first : '';
    final small = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context,
          isLoyalty ? Routes.loyalty : Routes.wallet),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        decoration: BoxDecoration(
          gradient: isLoyalty ? UellowColors.heroLoyalty : UellowColors.heroWallet,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(
            color: (isLoyalty ? UellowColors.darkBrown : UellowColors.darkBrown).withValues(alpha: .25),
            blurRadius: 16, offset: const Offset(0, 6))],
        ),
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header — icon + label
          Row(children: [
            Container(
              width: 30, height: 30, alignment: Alignment.center,
              decoration: BoxDecoration(
                color: (isLoyalty ? UellowColors.darkBrown : UellowColors.yellowLight)
                    .withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isLoyalty ? Icons.local_activity : Icons.account_balance_wallet,
                size: 16,
                color: isLoyalty ? UellowColors.darkBrown : UellowColors.yellowLight),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(title.toUpperCase(),
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: isLoyalty ? UellowColors.darkBrown : UellowColors.yellowLight,
                    fontSize: 10.5, fontWeight: FontWeight.w900, letterSpacing: 0.7))),
          ]),
          const SizedBox(height: 8),
          // Big value
          Text(big, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: isLoyalty ? UellowColors.darkBrown : UellowColors.yellowLight,
                  fontSize: 22, fontWeight: FontWeight.w900, height: 1.1)),
          if (small.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(small, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: (isLoyalty ? UellowColors.darkBrown : UellowColors.yellowLight)
                        .withValues(alpha: .85),
                    fontSize: 10.5, fontWeight: FontWeight.w700)),
          ],
          // Tier badge for loyalty only
          if (isLoyalty && (banner['tier'] as String?) != null) ...[
            const SizedBox(height: 8),
            _tierBadge(
              (banner['tier'] as String?) ?? 'bronze',
              ((banner['tier_label'] as Map?)?[lang] as String?)
                  ?? ((banner['tier'] as String?) ?? 'BRONZE').toUpperCase(),
            ),
          ],
          // Progress
          if (progressPct > 0) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 5,
                value: progressPct / 100.0,
                backgroundColor: (isLoyalty ? Colors.black : Colors.white).withValues(alpha: 0.18),
                valueColor: AlwaysStoppedAnimation(
                    isLoyalty ? UellowColors.darkBrown : UellowColors.yellowLight),
              ),
            ),
          ] else const SizedBox(height: 6),
          const SizedBox(height: 4),
          Row(children: [
            const Spacer(),
            Icon(Icons.arrow_forward, size: 12,
                color: isLoyalty ? UellowColors.darkBrown : UellowColors.yellowLight),
            const SizedBox(width: 3),
            Text(ar ? 'فتح' : 'OPEN',
                style: TextStyle(
                    color: isLoyalty ? UellowColors.darkBrown : UellowColors.yellowLight,
                    fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
          ]),
        ]),
      ),
    );
  }
}

Widget _tierBadge(String tier, String label) {
  final colors = {
    'bronze':   [const Color(0xFF8B5A2B), const Color(0xFFCD7F32)],
    'silver':   [const Color(0xFF707070), const Color(0xFFBCBCBC)],
    'gold':     [const Color(0xFF8B6A14), const Color(0xFFE6C04A)],
    'platinum': [const Color(0xFF3A4F66), const Color(0xFFA7C7E7)],
  }[tier] ?? [const Color(0xFF707070), const Color(0xFFBCBCBC)];
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: colors),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.star, size: 10, color: Colors.white),
      const SizedBox(width: 3),
      Text('${label.toUpperCase()} TIER',
          style: const TextStyle(color: Colors.white,
              fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
    ]),
  );
}

/// Latest-order tracking card — redesigned: stage progress dots + status
/// label + total + "Track" pill. Tap anywhere → order screen.
class _RecentOrderCard extends StatelessWidget {
  const _RecentOrderCard({required this.order});
  final Map order;
  static const _stages = ['draft', 'confirmed', 'preparing', 'shipping', 'delivered'];
  static const _stageLabelsEn = {
    'draft': 'Placed', 'confirmed': 'Confirmed', 'preparing': 'Preparing',
    'shipping': 'Shipping', 'delivered': 'Delivered',
    'cancelled': 'Cancelled', 'returned': 'Returned',
  };
  static const _stageLabelsAr = {
    'draft': 'تم الطلب', 'confirmed': 'مؤكد', 'preparing': 'قيد التجهيز',
    'shipping': 'قيد الشحن', 'delivered': 'تم التسليم',
    'cancelled': 'ملغي', 'returned': 'مرتجع',
  };
  static const _stageIcons = {
    'draft': Icons.edit_outlined,
    'confirmed': Icons.task_alt_outlined,
    'preparing': Icons.inventory_2_outlined,
    'shipping': Icons.local_shipping_outlined,
    'delivered': Icons.home_outlined,
  };
  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    final status = (order['uellow_status'] as String?)
        ?? (order['state'] as String?)
        ?? 'confirmed';
    final stageIdx = _stages.indexOf(status);
    final activeIdx = stageIdx < 0 ? 1 : stageIdx;
    final label = (ar ? _stageLabelsAr : _stageLabelsEn)[status] ?? status;
    final totalAmount = ((order['total'] as Map?)?['amount'])?.toString() ?? '';
    final currency = ((order['total'] as Map?)?['currency'] as String?) ?? '';
    return InkWell(
      onTap: () => Navigator.pushNamed(context, Routes.order,
          arguments: {'id': order['id']}),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [BoxShadow(
              color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 4))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Header row
          Padding(padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
              child: Row(children: [
                Container(
                  width: 38, height: 38, alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: UellowColors.yellowSoft, shape: BoxShape.circle),
                  child: Icon(_stageIcons[status] ?? Icons.local_shipping_outlined,
                      size: 18, color: UellowColors.darkBrown),
                ),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text((order['name'] ?? '').toString(),
                        style: const TextStyle(fontFamily: 'monospace',
                            fontWeight: FontWeight.w900, fontSize: 12.5,
                            color: UellowColors.ink)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: _statusColor(status).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(label.toUpperCase(),
                          style: TextStyle(color: _statusColor(status),
                              fontSize: 9.5, fontWeight: FontWeight.w900,
                              letterSpacing: 0.4)),
                    ),
                  ]),
                  const SizedBox(height: 2),
                  Text(ar
                      ? 'آخر طلب • $currency $totalAmount'
                      : 'Latest order • $currency $totalAmount',
                      style: const TextStyle(fontSize: 11.5,
                          color: UellowColors.muted, fontWeight: FontWeight.w600)),
                ])),
                // v2.1.94 — delivered → the button becomes a green "Rate"
                // that opens the review sheet for THIS order.
                status == 'delivered'
                    ? GestureDetector(
                        onTap: () => ReviewPromptService.showForOrder(
                            context, (order['id'] as num?)?.toInt() ?? 0),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: UellowColors.successDk,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.star_rounded, size: 13,
                                color: Colors.white),
                            const SizedBox(width: 4),
                            Text(ar ? 'قيّم' : 'Rate',
                                style: const TextStyle(color: Colors.white,
                                    fontSize: 11, fontWeight: FontWeight.w900)),
                          ]),
                        ),
                      )
                    : Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: UellowColors.darkBrown,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(ar ? 'تتبع' : 'Track',
                              style: const TextStyle(
                                  color: UellowColors.yellowLight,
                                  fontSize: 11, fontWeight: FontWeight.w900)),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_forward, size: 12,
                              color: UellowColors.yellowLight),
                        ]),
                      ),
              ])),
          // ── Progress dots
          Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Row(children: List.generate(_stages.length * 2 - 1, (i) {
                if (i.isOdd) {
                  final segIdx = i ~/ 2;
                  return Expanded(child: Container(
                    height: 2, margin: const EdgeInsets.symmetric(horizontal: 2),
                    color: segIdx < activeIdx
                        ? _statusColor(status)
                        : UellowColors.border,
                  ));
                }
                final dotIdx = i ~/ 2;
                final isDone = dotIdx < activeIdx;
                final isNow = dotIdx == activeIdx;
                return Container(
                  width: isNow ? 10 : 8, height: isNow ? 10 : 8,
                  decoration: BoxDecoration(
                    color: (isDone || isNow)
                        ? _statusColor(status)
                        : UellowColors.border,
                    shape: BoxShape.circle,
                    border: isNow
                        ? Border.all(color: _statusColor(status).withValues(alpha: 0.25), width: 3)
                        : null,
                  ),
                );
              }))),
        ]),
      ),
    );
  }
  Color _statusColor(String s) => switch (s) {
    'draft'     => UellowColors.muted,
    'confirmed' => const Color(0xFF0EA5E9),
    'preparing' => const Color(0xFF8B5CF6),
    'shipping'  => const Color(0xFFF59E0B),
    'delivered' => UellowColors.successDk,
    'cancelled' => UellowColors.muted,
    'returned'  => UellowColors.danger,
    _ => const Color(0xFF0EA5E9),
  };
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child,
      this.trailingText, this.onTrailing, this.tightHorizontal = false});
  final String title;
  final Widget child;
  final String? trailingText;
  final VoidCallback? onTrailing;
  /// Use 6px horizontal inner padding instead of 14px — for icon grids
  /// where the children already carry their own spacing.
  final bool tightHorizontal;
  @override
  Widget build(BuildContext context) {
    final hPad = tightHorizontal ? 6.0 : 14.0;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      padding: EdgeInsets.fromLTRB(hPad, 14, hPad, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (title.isNotEmpty) Padding(
          padding: EdgeInsets.only(left: tightHorizontal ? 8 : 0,
              right: tightHorizontal ? 8 : 0, bottom: 12),
          child: Row(children: [
            Expanded(child: Text(title, style: UT.h3)),
            if (trailingText != null) GestureDetector(
              onTap: onTrailing,
              child: Text(trailingText!,
                  style: const TextStyle(fontSize: 11,
                      color: UellowColors.darkBrown,
                      fontWeight: FontWeight.w800)),
            ),
          ]),
        ),
        child,
      ]),
    );
  }
}

class _OrdersGrid extends StatelessWidget {
  const _OrdersGrid({required this.stats, this.isGuest = false});
  final Map stats;
  final bool isGuest;
  // Mirrors backend uellow_status enum
  // (see api_v2/orders.py:_UELLOW_STATUS_DICT).
  static const _en = ['Draft', 'Confirmed', 'Preparing', 'Shipping', 'Delivered'];
  static const _ar = ['مسودة', 'مؤكد', 'قيد التجهيز', 'قيد الشحن', 'تم التوصيل'];
  // All outlined (thin) variants — no solid icons for a lighter look.
  static const _icons = [
    Icons.edit_outlined,
    Icons.task_alt_outlined,
    Icons.inventory_2_outlined,
    Icons.local_shipping_outlined,
    Icons.home_outlined,
  ];
  static const _filters = ['draft', 'confirmed', 'preparing', 'shipping', 'delivered'];
  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    final labels = ar ? _ar : _en;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5, crossAxisSpacing: 6, mainAxisSpacing: 6, childAspectRatio: 0.75,
      ),
      itemCount: _icons.length,
      itemBuilder: (_, i) {
        final counts = (stats['status_counts'] as Map?) ?? const {};
        final n = (counts[_filters[i]] as num?)?.toInt() ?? 0;
        return InkWell(
          onTap: () => Navigator.pushNamed(context,
              isGuest ? '/auth' : '/orders',
              arguments: isGuest ? null : {'filter': _filters[i]}),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            // icon + count badge
            Stack(clipBehavior: Clip.none, children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: UellowColors.border, width: 1),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(_icons[i], size: 22, color: UellowColors.darkBrown),
              ),
              if (n > 0) PositionedDirectional(
                top: -5, end: -5,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  constraints: const BoxConstraints(minWidth: 18),
                  decoration: BoxDecoration(
                    color: UellowColors.yellow,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  alignment: Alignment.center,
                  child: Text('$n', style: const TextStyle(
                      color: UellowColors.darkBrown, fontSize: 9.5,
                      fontWeight: FontWeight.w900)),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            Text(labels[i], textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 10.5, fontWeight: FontWeight.w700,
                  color: UellowColors.darkBrown,
                )),
          ]),
        );
      },
    );
  }
}

class _ActionTiles extends StatefulWidget {
  const _ActionTiles({this.isGuest = false});
  final bool isGuest;
  @override
  State<_ActionTiles> createState() => _ActionTilesState();
}

class _ActionTilesState extends State<_ActionTiles> {
  bool get isGuest => widget.isGuest;
  // v2.1.63 — unread badge on the Alerts tile (personal event
  // notifications: orders, wallet, loyalty, review replies…).
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    if (!isGuest) _loadUnread();
  }

  Future<void> _loadUnread() async {
    try {
      final res = await UellowApi.instance.getRaw(
          '/api/mobile/v2/notifications/unread-count', auth: true);
      final n = (res['data']?['unread'] as num?)?.toInt() ?? 0;
      if (mounted && n != _unread) setState(() => _unread = n);
    } catch (_) {}
  }

  // v2.1.66 — Settings tile removed (the gear stays in the header only).
  static const _en = ['Wishlist','Alerts','Coupons','Loyalty',
                      'Wallet','Smart Fit','Tracking','My Reviews'];
  static const _ar = ['المفضلة','التنبيهات','الكوبونات','الولاء',
                      'المحفظة','مقاسي','التتبع','آراء المختصين'];
  // Public tiles work for guests too — the rest need a session, so guests
  // get bounced to /auth.
  static const _public = {Routes.tryOn};
  static const _tiles = [
    (Icons.favorite_border, Routes.wishlist),
    (Icons.notifications_outlined, Routes.notifications),
    (Icons.card_giftcard, Routes.coupons),
    (Icons.local_offer_outlined, Routes.loyalty),
    (Icons.account_balance_wallet_outlined, Routes.wallet),
    // v2.1.84 — restored: 'مقاسي' opens Virtual Try-On (was Smart Fit).
    (Icons.checkroom_outlined, Routes.tryOn),
    // Tracking → the orders list (non-cancelled), not a single auto-track.
    (Icons.local_shipping_outlined, Routes.orders),
    // v2.1.62 — specialist-review history (product + the review itself).
    (Icons.rate_review_outlined, Routes.myReviews),
  ];
  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      // v2.1.20 — bigger tiles per request (icons were tiny).
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4, crossAxisSpacing: 2, mainAxisSpacing: 10, childAspectRatio: 0.82,
      ),
      itemCount: _tiles.length,
      itemBuilder: (_, i) {
        final (icon, route) = _tiles[i];
        final label = ar ? _ar[i] : _en[i];
        final needsAuth = isGuest && !_public.contains(route);
        return InkWell(
          onTap: () {
            if (needsAuth) {
              Navigator.pushNamed(context, '/auth');
              return;
            }
            // v2.1.41 — "Tracking" used to push OrderScreen with id 0
            // (→ 404). It now resolves the LATEST order and opens it,
            // or falls back to the orders list when there are none.
            if (route == Routes.order) {
              _openTracking(context);
              return;
            }
            if (route == Routes.notifications) {
              Navigator.pushNamed(context, route)
                  .then((_) => _loadUnread());
              return;
            }
            Navigator.pushNamed(context, route);
          },
          borderRadius: BorderRadius.circular(12),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Stack(clipBehavior: Clip.none, children: [
              Container(
                width: 54, height: 54,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: UellowColors.border, width: 1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, size: 26, color: UellowColors.darkBrown),
              ),
              if (route == Routes.notifications && _unread > 0)
                PositionedDirectional(
                  top: -5, end: -5,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 2),
                    constraints: const BoxConstraints(minWidth: 18),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE63946),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    alignment: Alignment.center,
                    child: Text(_unread > 99 ? '99+' : '$_unread',
                        style: const TextStyle(color: Colors.white,
                            fontSize: 9.5, fontWeight: FontWeight.w900,
                            height: 1.0)),
                  ),
                ),
            ]),
            const SizedBox(height: 6),
            Text(label, textAlign: TextAlign.center,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.5,
                    fontWeight: FontWeight.w700, color: UellowColors.text)),
          ]),
        );
      },
    );
  }

  // v2.1.41 — Tracking tile: open the user's most recent order's
  // tracking; with no orders yet, land on the (empty-state) orders list.
  Future<void> _openTracking(BuildContext context) async {
    final ar = UellowApi.instance.lang == 'ar';
    final messenger = ScaffoldMessenger.of(context);
    try {
      final page = await UellowApi.instance.orders.list(page: 1, perPage: 1);
      if (!context.mounted) return;
      if (page.items.isNotEmpty) {
        Navigator.pushNamed(context, Routes.order,
            arguments: {'id': page.items.first.id});
      } else {
        Navigator.pushNamed(context, '/orders');
        messenger.showSnackBar(SnackBar(content: Text(
            ar ? 'لا توجد طلبات لتتبعها بعد' : 'No orders to track yet')));
      }
    } on UellowApiException {
      if (context.mounted) Navigator.pushNamed(context, '/orders');
    } catch (_) {
      if (context.mounted) Navigator.pushNamed(context, '/orders');
    }
  }
}

class _MenuList extends StatefulWidget {
  const _MenuList();
  @override
  State<_MenuList> createState() => _MenuListState();
}

class _MenuListState extends State<_MenuList> {
  Map<String, dynamic>? _urls;
  @override
  void initState() {
    super.initState();
    _loadUrls();
  }
  Future<void> _loadUrls() async {
    try {
      final uri = Uri.parse('${UellowApi.instance.baseUrl}/api/mobile/v2/app/settings');
      final r = await http.get(uri, headers: const {'Accept':'application/json'});
      final body = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (body['success'] == true) {
        _urls = (body['data']?['urls'] as Map?)?.cast<String, dynamic>();
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  void _openWeb(String url, String title) {
    Navigator.pushNamed(context, '/webview',
        arguments: {'url': url, 'title': title});
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    final items = <(IconData, String, VoidCallback)>[
      // v2.1.58 — Affiliate / partner center
      (Icons.handshake_outlined, ar ? '🤝 شركاء يلو — اربح معنا' : '🤝 Uellow Partners — earn with us',
        () => Navigator.pushNamed(context, '/affiliate')),
      (Icons.chat_bubble_outline, ar ? 'الدعم الفني' : 'Customer support',
        () {
          final hd = (_urls?['helpdesk'] as String?) ?? '';
          if (hd.isNotEmpty) _openWeb(hd, ar ? 'الدعم الفني' : 'Customer support');
          else ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(ar ? 'لم يتم إعداد رابط الدعم' : 'Helpdesk URL not configured')));
        }),
      (Icons.shield_outlined, ar ? 'الخصوصية والأمان' : 'Privacy & security',
        () {
          final u = (_urls?['privacy'] as String?) ?? '';
          if (u.isNotEmpty) _openWeb(u, ar ? 'الخصوصية' : 'Privacy');
        }),
      (Icons.replay_outlined, ar ? 'الإرجاع والاسترداد' : 'Returns & refunds',
        () {
          final u = (_urls?['returns'] as String?) ?? '';
          if (u.isNotEmpty) _openWeb(u, ar ? 'الإرجاع والاسترداد' : 'Returns & refunds');
        }),
      (Icons.star_outline, ar ? 'قيّم التطبيق' : 'Rate the app',
        () async {
          // Try the platform's store URL; Android = play_store, iOS = app_store.
          final isIOS = Theme.of(context).platform == TargetPlatform.iOS;
          final key = isIOS ? 'app_store' : 'play_store';
          final url = (_urls?[key] as String?) ?? '';
          if (url.isNotEmpty) {
            try {
              await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
            } catch (_) {/* fall through to snackbar */}
          } else if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(ar ? 'لم يتم إعداد رابط المتجر' : 'Store URL not configured')));
          }
        }),
      (Icons.public, ar ? 'الدولة واللغة' : 'Country & language',
        () => Navigator.pushNamed(context, '/settings')),
    ];
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
      child: Column(children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            leading: Container(
              width: 32, height: 32,
              decoration: const BoxDecoration(
                color: UellowColors.border,
                borderRadius: BorderRadius.all(Radius.circular(8)),
              ),
              child: Icon(items[i].$1, size: 16, color: UellowColors.muted),
            ),
            title: Text(items[i].$2,
                style: const TextStyle(fontSize: 13, color: UellowColors.ink)),
            trailing: const Icon(Icons.chevron_right,
                color: Color(0xFFCBB78A), size: 18),
            dense: true,
            onTap: items[i].$3,
          ),
        ],
      ]),
    );
  }
}

class _SignOutBtn extends StatelessWidget {
  const _SignOutBtn();
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
      child: ListTile(
        leading: Container(
          width: 32, height: 32,
          decoration: const BoxDecoration(
            color: UellowColors.dangerBg, borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
          child: const Icon(Icons.logout, size: 16, color: UellowColors.danger),
        ),
        title: Text(UellowApi.instance.lang == 'ar' ? 'تسجيل الخروج' : 'Sign out',
            style: const TextStyle(color: UellowColors.danger, fontWeight: FontWeight.w700)),
        dense: true,
        onTap: () async {
          await UellowApi.instance.auth.logout();
          if (context.mounted) Navigator.pushReplacementNamed(context, Routes.auth);
        },
      ),
    );
  }
}

class _Version extends StatelessWidget {
  const _Version();
  @override
  Widget build(BuildContext context) => const SizedBox(height: 30);
}

// ─── Recently viewed rail ──────────────────────────────────────────

class _RecentlyViewed extends StatefulWidget {
  const _RecentlyViewed();
  @override
  State<_RecentlyViewed> createState() => _RecentlyViewedState();
}

class _RecentlyViewedState extends State<_RecentlyViewed> {
  late Future<List<dynamic>> _future;
  @override
  void initState() {
    super.initState();
    _future = UellowApi.instance.products.recentlyViewed()
        .then<List<dynamic>>((v) => v)
        .catchError((_) => <dynamic>[]);
  }
  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return FutureBuilder<List<dynamic>>(
      future: _future,
      builder: (_, snap) {
        final items = snap.data ?? const [];
        if (items.isEmpty) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.all(Radius.circular(14)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(right: 8),
              child: Row(children: [
                Expanded(child: Text(ar ? 'شاهدتها مؤخراً' : 'Recently viewed',
                    style: UT.h3)),
                GestureDetector(
                  // v2.1.23 — opens the recently-viewed LIST (was the shop).
                  onTap: () => Navigator.pushNamed(context, '/recently-viewed'),
                  child: Text(ar ? 'عرض الكل ›' : 'See more ›',
                      style: const TextStyle(fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: UellowColors.darkBrown)),
                ),
              ])),
            const SizedBox(height: 10),
            SizedBox(height: 130, child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final p = items[i];
                final id = (p.id as int?) ?? 0;
                final image = p.image as String? ?? '';
                final price = p.price;
                return GestureDetector(
                  onTap: () => Navigator.pushNamed(context, '/product',
                      arguments: {'id': id}),
                  child: SizedBox(width: 90, child: Column(children: [
                    Container(
                      width: 90, height: 90,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFAFAFA),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: UellowColors.border),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: image.isEmpty ? const Icon(Icons.image_outlined,
                              color: UellowColors.muted)
                        : Image.network(image, fit: BoxFit.cover),
                    ),
                    const SizedBox(height: 6),
                    Text(price.format(),
                        style: const TextStyle(fontSize: 11.5,
                            fontWeight: FontWeight.w900,
                            color: UellowColors.ink)),
                  ])),
                );
              },
            )),
          ]),
        );
      },
    );
  }
}


// ─── Become a reviewer (v2.1.62) ────────────────────────────────────────────
// «انضم كمراجع معتمد» — apply to the reviewers program right from the
// account page. Status-aware: no profile → apply sheet; pending → quiet
// "under review" chip; approved → green confirmation.
class _BecomeReviewerCard extends StatefulWidget {
  const _BecomeReviewerCard({this.isGuest = false});
  final bool isGuest;
  @override
  State<_BecomeReviewerCard> createState() => _BecomeReviewerCardState();
}

class _BecomeReviewerCardState extends State<_BecomeReviewerCard> {
  String? _status; // null=loading, 'none', 'pending', 'approved', ...

  @override
  void initState() {
    super.initState();
    if (widget.isGuest) {
      _status = 'none';       // guests always see the pitch card
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final res = await UellowApi.instance
          .getRaw('/api/mobile/v2/reviewer/me', auth: true);
      if (mounted) {
        setState(() =>
            _status = (res['data']?['status'] ?? 'none').toString());
      }
    } catch (_) {
      if (mounted) setState(() => _status = 'none');
    }
  }

  void _applySheet() {
    // Guests must sign in before applying.
    if (widget.isGuest) {
      Navigator.pushNamed(context, '/auth');
      return;
    }
    final ar = UellowApi.instance.lang == 'ar';
    final nameC = TextEditingController();
    final bioC = TextEditingController();
    final specC = TextEditingController();
    bool sending = false;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius:
          BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => Padding(
        padding: EdgeInsets.fromLTRB(
            18, 14, 18, 18 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Directionality(
          textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
          child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: const Color(0xFFE3E3E3),
                    borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 12),
            Text(ar ? '🎓 التقديم كمراجع معتمد'
                    : '🎓 Apply as a certified reviewer',
                style: const TextStyle(fontSize: 16,
                    fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(ar
                    ? 'راجع المنتجات، اكسب نقاطاً تتحول لرصيد، ونسبة أرباح من مبيعات مراجعاتك.'
                    : 'Review products, earn redeemable points and a profit share on sales from your reviews.',
                style: const TextStyle(fontSize: 11.5,
                    color: UellowColors.muted, height: 1.5)),
            const SizedBox(height: 14),
            TextField(controller: nameC, decoration: InputDecoration(
                labelText: ar ? 'الاسم المعروض' : 'Display name',
                border: const OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: specC, decoration: InputDecoration(
                labelText: ar ? 'تخصصاتك (إلكترونيات، أزياء…)'
                              : 'Specialties (electronics, fashion…)',
                border: const OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: bioC, maxLines: 3,
                decoration: InputDecoration(
                    labelText: ar ? 'نبذة عنك وخبرتك'
                                  : 'About you & your experience',
                    border: const OutlineInputBorder())),
            const SizedBox(height: 14),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: sending ? null : () async {
                setS(() => sending = true);
                try {
                  await UellowApi.instance.postRaw(
                      '/api/mobile/v2/reviewer/apply',
                      auth: true,
                      body: {
                        'name': nameC.text.trim(),
                        'bio': bioC.text.trim(),
                        'specialties': specC.text.trim(),
                      });
                  if (ctx.mounted) Navigator.pop(ctx);
                  _load();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(ar
                            ? '✅ تم إرسال طلبك — سنراجعه قريباً'
                            : '✅ Application sent — we will review it soon')));
                  }
                } catch (_) {
                  setS(() => sending = false);
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                        content: Text(ar ? 'تعذّر الإرسال — حاول مجدداً'
                                         : 'Could not send — try again')));
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: UellowColors.yellow,
                foregroundColor: UellowColors.darkBrown,
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              child: Text(
                  sending
                      ? (ar ? 'جارٍ الإرسال…' : 'Sending…')
                      : (ar ? 'إرسال الطلب' : 'Submit application'),
                  style: const TextStyle(fontWeight: FontWeight.w900)),
            )),
          ]),
        ),
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = _status;
    if (st == null) return const SizedBox.shrink();
    final ar = UellowApi.instance.lang == 'ar';
    final approved = st == 'approved' || st == 'active';
    final pending = st == 'pending';
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        gradient: approved
            ? const LinearGradient(
                colors: [Color(0xFF146C36), Color(0xFF27AE60)])
            : const LinearGradient(
                colors: [Color(0xFF2B1D66), Color(0xFF5B3FA8)]),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        const Text('🎓', style: TextStyle(fontSize: 26)),
        const SizedBox(width: 11),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              approved
                  ? (ar ? 'أنت مراجع معتمد ✓' : 'Certified reviewer ✓')
                  : pending
                      ? (ar ? 'طلبك قيد المراجعة' : 'Application under review')
                      : (ar ? 'انضم كمراجع معتمد' : 'Become a reviewer'),
              style: const TextStyle(color: Colors.white, fontSize: 13.5,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(
              approved
                  ? (ar ? 'حمّل تطبيق المراجعين وابدأ الكسب'
                        : 'Get the reviewers app and start earning')
                  : pending
                      ? (ar ? 'سنخطرك فور الموافقة على طلبك'
                            : 'We will notify you once approved')
                      : (ar ? 'اكسب نقاطاً ورصيداً ونسبة أرباح من مراجعاتك'
                            : 'Earn points, cash and profit share from reviews'),
              style: TextStyle(color: Colors.white.withValues(alpha: .85),
                  fontSize: 10.5, height: 1.35)),
        ])),
        if (!approved && !pending)
          GestureDetector(
            onTap: _applySheet,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 7),
              decoration: BoxDecoration(color: Colors.white,
                  borderRadius: BorderRadius.circular(20)),
              child: Text(ar ? 'قدّم الآن' : 'Apply now',
                  style: const TextStyle(color: Color(0xFF2B1D66),
                      fontSize: 11, fontWeight: FontWeight.w900)),
            ),
          ),
      ]),
    );
  }
}
