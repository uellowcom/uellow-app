// =============================================================================
// WebViewScreen — simple in-app browser for Privacy, Returns, Helpdesk,
// etc. Loads a URL and injects a small bit of CSS to hide the website's
// header / footer / cookie banner so the content reads like a native page.
// =============================================================================
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../theme/uellow_theme.dart';

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
