import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uellow/api/uellow_api.dart';
import 'package:uellow/uellow_v2/router/uellow_router.dart';
import 'package:uellow/uellow_v2/theme/uellow_theme.dart';
import 'package:uellow/uellow_v2/services/deep_link_service.dart';
import 'package:uellow/uellow_v2/services/push_service.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await UellowApi.init();
  UellowApi.instance.setAppMeta(appVersion: '2.0.22', platform: 'android');
  // Hydrate language from prefs before first paint so Directionality is right.
  try {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('uellow_lang_v1');
    if (saved != null && saved.isNotEmpty) UellowApi.instance.setLang(saved);
  } catch (_) {}
  // Local notifications channels + ongoing-banner support.
  unawaited(PushService.instance.init());
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

class _UellowAppState extends State<UellowApp> {
  @override
  void initState() {
    super.initState();
    // After first frame the navigator key has a state — wire deep links.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DeepLinkService.instance.attach(widget.navigatorKey);
    });
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
        );
      },
    );
  }
}
