// =============================================================================
// GiftScreen — «هدية يلو» free-gift zone inside the app.
// Loads the server-rendered premium gift page (/gift?embed=1) in a WebView so
// it matches the design 1:1, and intercepts a gift tap (uellow://gift/<id>)
// to add the chosen gift (price 0) to the NATIVE cart, then opens the cart.
// =============================================================================
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../api/uellow_api.dart';
import '../router/uellow_router.dart';
import '../theme/uellow_theme.dart';

class GiftScreen extends StatefulWidget {
  const GiftScreen({super.key});
  @override
  State<GiftScreen> createState() => _GiftScreenState();
}

class _GiftScreenState extends State<GiftScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _adding = false;
  static final RegExp _bridge = RegExp(r'^uellow://gift/(\d+)');

  @override
  void initState() {
    super.initState();
    final plat = Platform.isIOS ? 'ios' : (Platform.isAndroid ? 'android' : 'web');
    final lang = UellowApi.instance.lang;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(UellowColors.bg)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (req) {
          final m = _bridge.firstMatch(req.url);
          if (m != null) {
            _addGift(int.tryParse(m.group(1) ?? '') ?? 0);
            return NavigationDecision.prevent;
          }
          if (req.url.startsWith('uellow://')) return NavigationDecision.prevent;
          return NavigationDecision.navigate;
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
        },
      ))
      ..loadRequest(Uri.parse(
          'https://www.uellow.com/gift?embed=1&lang=$lang&platform=$plat'));
  }

  Future<void> _addGift(int vid) async {
    if (vid <= 0 || _adding) return;
    _adding = true;
    final ar = UellowApi.instance.lang == 'ar';
    try {
      await UellowApi.instance.gift.add(vid);
      try {
        await UellowApi.instance.cart.get();
      } catch (_) {}
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ar
              ? '✓ أُضيفت هديّتك — أضف منتجًا لإتمام الطلب'
              : '✓ Gift added — add a product to complete')));
      Navigator.of(context).pushReplacementNamed(Routes.cart);
    } catch (e) {
      _adding = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(ar ? 'تعذّر إضافة الهديّة، حاول مجددًا'
                : 'Could not add the gift, try again')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Scaffold(
      backgroundColor: UellowColors.bg,
      body: Stack(children: [
        Positioned.fill(child: WebViewWidget(controller: _controller)),
        if (_loading)
          const Align(
            alignment: Alignment.topCenter,
            child: LinearProgressIndicator(
                minHeight: 2, color: UellowColors.darkBrown,
                backgroundColor: UellowColors.border),
          ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Align(
              alignment: rtl ? Alignment.topRight : Alignment.topLeft,
              child: Material(
                color: Colors.black.withOpacity(0.32),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.of(context).maybePop(),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.arrow_back, color: Colors.white, size: 22)),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
