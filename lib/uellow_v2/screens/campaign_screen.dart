// =============================================================================
// CampaignScreen — full-quality Anker/campaign page inside the app.
// Loads the server-rendered premium page (/c/<slug>?embed=1) in a WebView so
// it matches the web design 1:1, and intercepts product taps
// (uellow://product/<id>) to open the NATIVE product screen instead of
// navigating inside the WebView.
// =============================================================================
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../theme/uellow_theme.dart';
import '../router/uellow_router.dart';

class CampaignScreen extends StatefulWidget {
  const CampaignScreen({super.key, this.slug = 'anker'});
  final String slug;
  @override
  State<CampaignScreen> createState() => _CampaignScreenState();
}

class _CampaignScreenState extends State<CampaignScreen> {
  late final WebViewController _controller;
  bool _loading = true;

  static final RegExp _scheme = RegExp(r'^uellow://product/(\d+)');
  static final RegExp _webProd =
      RegExp(r'uellow\.com/(?:[a-z]{2}/)?shop/[^?#]*-(\d+)(?:[/?#]|$)');

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(UellowColors.bg)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (req) {
          final u = req.url;
          // Native product open via custom scheme.
          final m = _scheme.firstMatch(u);
          if (m != null) {
            final id = int.tryParse(m.group(1) ?? '') ?? 0;
            if (id > 0) UellowRouter.goProduct(context, id);
            return NavigationDecision.prevent;
          }
          // Any other custom scheme → swallow (don't error the WebView).
          if (u.startsWith('uellow://')) return NavigationDecision.prevent;
          // A stray product WEB link → open native too.
          final w = _webProd.firstMatch(u);
          if (w != null) {
            final id = int.tryParse(w.group(1) ?? '') ?? 0;
            if (id > 0) {
              UellowRouter.goProduct(context, id);
              return NavigationDecision.prevent;
            }
          }
          return NavigationDecision.navigate;
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
        },
      ))
      ..loadRequest(Uri.parse(
          'https://www.uellow.com/c/${widget.slug}?embed=1&app=1'));
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
                backgroundColor: UellowColors.border,
                minHeight: 2,
                color: UellowColors.darkBrown),
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
                    child: Icon(Icons.arrow_back,
                        color: Colors.white, size: 22)),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
