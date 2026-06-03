// =============================================================================
// WebViewScreen — simple in-app browser for Privacy, Returns, Helpdesk,
// etc. Loads a URL and injects a small bit of CSS to hide the website's
// header / footer / cookie banner so the content reads like a native page.
// =============================================================================
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../theme/uellow_theme.dart';

/// v2.1.14 — Payment DIALOG: opens the gateway page (KNET / Apple Pay /
/// card — white-label links go straight to the chosen gateway) as a modal
/// bottom sheet ON TOP of the checkout, instead of navigating away to a
/// full page. Returns true only when the gateway redirected to the
/// return/status URL without a failure result.
Future<bool> showPaymentSheet(BuildContext context,
    {required String url, required String title}) async {
  final r = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    useSafeArea: true,
    // v2.1.15 — the sheet's drag gesture was swallowing vertical swipes, so
    // long gateway pages could not scroll. Dragging is disabled (close via
    // the X button) and the webview claims all touch gestures below.
    enableDrag: false,
    builder: (_) => _PaymentSheet(url: url, title: title),
  );
  return r == true;
}

class _PaymentSheet extends StatefulWidget {
  const _PaymentSheet({required this.url, required this.title});
  final String url;
  final String title;
  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (req) {
          final u = req.url;
          if (u.contains('/payments/upayments/return') || u.contains('/payment/status')) {
            final up = u.toUpperCase();
            final failed = up.contains('NOT_CAPTURED') || up.contains('FAILED')
                || up.contains('CANCELED') || up.contains('CANCELLED');
            if (mounted) Navigator.of(context).maybePop(!failed);
            return NavigationDecision.prevent;
          }
          if (u.contains('/payments/upayments/cancel')) {
            if (mounted) Navigator.of(context).maybePop(false);
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
        },
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.92,
        child: Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            top: false,
            child: Column(children: [
              // Grab handle + header
              Container(
                margin: const EdgeInsets.only(top: 10),
                width: 44, height: 4,
                decoration: BoxDecoration(
                  color: UellowColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 6, 0),
                child: Row(children: [
                  const Icon(Icons.lock_outline,
                      size: 16, color: UellowColors.success),
                  const SizedBox(width: 6),
                  Expanded(child: Text(widget.title,
                      style: const TextStyle(fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: UellowColors.darkBrown))),
                  IconButton(
                    icon: const Icon(Icons.close, color: UellowColors.muted),
                    onPressed: () => Navigator.of(context).maybePop(false),
                  ),
                ]),
              ),
              if (_loading) const LinearProgressIndicator(
                  backgroundColor: UellowColors.border, minHeight: 2,
                  color: UellowColors.darkBrown),
              Expanded(child: WebViewWidget(
                controller: _controller,
                // Let the webview win every gesture inside its area so the
                // payment page scrolls/zooms normally inside the sheet.
                gestureRecognizers: {
                  Factory<OneSequenceGestureRecognizer>(
                      EagerGestureRecognizer.new),
                },
              )),
            ]),
          ),
        ),
      ),
    );
  }
}

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key, required this.url, required this.title});
  final String url;
  final String title;
  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(UellowColors.bg)
      ..setNavigationDelegate(NavigationDelegate(
        // Auto-close when a payment gateway redirects back to our return /
        // cancel / status URLs (UPayments etc.), returning success/cancel.
        onNavigationRequest: (req) {
          final u = req.url;
          if (u.contains('/payments/upayments/return') || u.contains('/payment/status')) {
            // v2.1.13 — UPayments redirects failures to the SAME returnUrl
            // with result=NOT_CAPTURED; only pop success on a clean capture.
            final up = u.toUpperCase();
            final failed = up.contains('NOT_CAPTURED') || up.contains('FAILED')
                || up.contains('CANCELED') || up.contains('CANCELLED');
            if (mounted) Navigator.of(context).maybePop(!failed);
            return NavigationDecision.prevent;
          }
          if (u.contains('/payments/upayments/cancel')) {
            if (mounted) Navigator.of(context).maybePop(false);
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
        onPageFinished: (_) async {
          // Hide common Odoo website chrome so the page feels native.
          await _controller.runJavaScript(r"""
            (function(){
              var sel = ['header.o_header_standard','#wrapwrap > header','header.o_main_header',
                         'footer','.o_footer','#footer','.cookies_bar',
                         '.s_popup','.btn_cookies'];
              sel.forEach(function(s){
                document.querySelectorAll(s).forEach(function(e){e.style.display='none';});
              });
              var style = document.createElement('style');
              style.textContent = 'body{padding:12px !important;}';
              document.head.appendChild(style);
            })();
          """);
          if (mounted) setState(() => _loading = false);
        },
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, style: UT.h2),
        backgroundColor: Colors.white,
      ),
      body: Stack(children: [
        WebViewWidget(controller: _controller),
        if (_loading) const LinearProgressIndicator(
            backgroundColor: UellowColors.border, minHeight: 2,
            color: UellowColors.darkBrown),
      ]),
    );
  }
}
