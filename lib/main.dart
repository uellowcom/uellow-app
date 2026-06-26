import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uellow/api/uellow_api.dart';
import 'package:uellow/uellow_v2/router/uellow_router.dart';
import 'package:uellow/uellow_v2/theme/uellow_theme.dart';
import 'package:uellow/uellow_v2/services/admin_mode.dart';
import 'package:uellow/version.dart';
import 'package:uellow/uellow_v2/services/deep_link_service.dart';
import 'package:uellow/uellow_v2/services/fcm_service.dart';
import 'package:uellow/uellow_v2/services/push_service.dart';
import 'package:uellow/uellow_v2/services/activity_tracker.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialise Firebase up-front so phone-OTP (Firebase Auth) and FCM are
  // both ready before any login attempt. Idempotent + non-fatal on iOS if
  // GoogleService-Info.plist is missing.
  try {
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
  } catch (_) {}
  await UellowApi.init();
  // v2.2.43 — detect the real platform so the update gate sends the right
  // store: iOS users were sent to Google Play because this was hard-coded.
  UellowApi.instance.setAppMeta(
      appVersion: kAppVersion, platform: Platform.isIOS ? 'ios' : 'android');
  // Hydrate language from prefs before first paint so Directionality is right.
  try {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('uellow_lang_v1');
    if (saved != null && saved.isNotEmpty) UellowApi.instance.setLang(saved);
  } catch (_) {}
  // v2.2.27 — admin flag is memory-only: start as non-admin, scrub any
  // legacy persisted flag, and force back to non-admin on EVERY auth change
  // (login / logout / 401) so the admin console can never bleed across an
  // account switch on a shared device. Real admins are re-confirmed live by
  // /account/overview + /admin/check.
  unawaited(AdminMode.restore());
  UellowApi.instance.onAuthChanged.listen((_) => AdminMode.reset());
  // Local notifications channels + ongoing-banner support.
  unawaited(PushService.instance.init());
  // v2.1.64 — FCM: token registration + foreground display.
  unawaited(FcmService.instance.init());
  // v2.2.56 — customer journey tracking (screen views + app lifecycle).
  ActivityTracker.instance.start();
  runApp(UellowApp(navigatorKey: rootNavigatorKey));
}

/// Reactive root. Listens to `UellowApi.instance.langNotifier` so the
/// whole MaterialApp (Directionality + Locale) flips the instant the
/// user picks a different language — no more "restart to take effect".
class UellowApp extends StatefulWidget {
  const UellowApp({super.key, required this.navigatorKey});
  final GlobalKey<NavigatorState> navigatorKey;
  @override
  State<UellowApp> createState() => _UellowAppState();
}

class _UellowAppState extends State<UellowApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // After first frame the navigator key has a state — wire deep links.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DeepLinkService.instance.attach(widget.navigatorKey);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // v2.2.56 — log app foreground/background for the customer journey.
    if (state == AppLifecycleState.resumed) {
      ActivityTracker.instance.log('app_open');
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      ActivityTracker.instance.log('app_close');
      unawaited(ActivityTracker.instance.flush());
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: UellowApi.instance.langNotifier,
      builder: (context, lang, _) {
        final isAr = lang == 'ar';
        return MaterialApp(
          title: 'Uellow',
          navigatorKey: widget.navigatorKey,
          debugShowCheckedModeBanner: false,
          theme: uellowThemeData(),
          locale: isAr ? const Locale('ar') : const Locale('en'),
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) => Directionality(
            textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
            child: child ?? const SizedBox.shrink(),
          ),
          initialRoute: Routes.splash,
          routes: UellowRouter.routes,
          onGenerateRoute: UellowRouter.generate,
          navigatorObservers: [
            appRouteObserver,
            ActivityTracker.instance.observer,
          ],
        );
      },
    );
  }
}
