// =============================================================================
// AdminGiftScreen — «🎁 خدمة الهدايا» settings, inside the owner console.
// Loads the server-rendered settings page (/gift/admin) in a WebView, passing
// the admin's auth token so it can read/write /api/admin/v2/gift/config.
// =============================================================================
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../api/uellow_api.dart';
import '../../theme/uellow_theme.dart';

class AdminGiftScreen extends StatefulWidget {
  const AdminGiftScreen({super.key});
  @override
  State<AdminGiftScreen> createState() => _AdminGiftScreenState();
}

class _AdminGiftScreenState extends State<AdminGiftScreen> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(UellowColors.bg)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
        },
      ));
    _load();
  }

  Future<void> _load() async {
    String tok = '';
    try {
      tok = await UellowApi.instance.tokenStore.readToken() ?? '';
    } catch (_) {}
    final base = UellowApi.instance.baseUrl;
    final lang = UellowApi.instance.lang;
    _controller.loadRequest(Uri.parse(
        '$base/gift/admin?lang=$lang&token=${Uri.encodeComponent(tok)}'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UellowColors.bg,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1206),
        foregroundColor: const Color(0xFFF5C320),
        title: const Text('خدمة الهدايا 🎁',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: Stack(children: [
        Positioned.fill(child: WebViewWidget(controller: _controller)),
        if (_loading)
          const Align(
            alignment: Alignment.topCenter,
            child: LinearProgressIndicator(
                minHeight: 2, color: UellowColors.darkBrown,
                backgroundColor: UellowColors.border)),
      ]),
    );
  }
}
