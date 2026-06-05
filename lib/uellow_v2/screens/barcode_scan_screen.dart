// =============================================================================
// BarcodeScanScreen — opens the camera, scans the first barcode it sees,
// hits /search/barcode and navigates to the matched product (or shows
// "not found" if none).
// =============================================================================
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../api/uellow_api.dart';
import '../theme/uellow_theme.dart';

class BarcodeScanScreen extends StatefulWidget {
  const BarcodeScanScreen({super.key, this.returnRaw = false});

  /// v2.1.66 — when true the scanner just pops with the raw scanned
  /// value (used by the cart QR import) instead of a product lookup.
  final bool returnRaw;
  @override
  State<BarcodeScanScreen> createState() => _BarcodeScanScreenState();
}

class _BarcodeScanScreenState extends State<BarcodeScanScreen> {
  final MobileScannerController _ctrl = MobileScannerController();
  bool _busy = false;

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _onDetect(BarcodeCapture cap) async {
    if (_busy) return;
    final code = cap.barcodes.firstOrNull?.rawValue?.trim() ?? '';
    if (code.isEmpty) return;
    setState(() => _busy = true);
    if (widget.returnRaw) {
      Navigator.of(context).pop(code);
      return;
    }
    try {
      final r = await http.post(
        Uri.parse('${UellowApi.instance.baseUrl}/api/mobile/v2/search/barcode'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'barcode': code}),
      );
      final body = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (body['success'] == true) {
        final id = (body['data']?['product']?['id'] as int?) ?? 0;
        if (id > 0 && mounted) {
          Navigator.pushReplacementNamed(context, '/product',
              arguments: {'id': id});
          return;
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(body['error']?.toString() ?? 'Not found')),
        );
        setState(() => _busy = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString())));
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(ar ? 'مسح الباركود' : 'Scan barcode',
            style: const TextStyle(color: Colors.white)),
        actions: [
          IconButton(onPressed: () => _ctrl.toggleTorch(),
              icon: const Icon(Icons.flash_on, color: Colors.white)),
        ],
      ),
      body: Stack(children: [
        MobileScanner(controller: _ctrl, onDetect: _onDetect),
        // Viewfinder frame
        Positioned.fill(child: IgnorePointer(child: Center(
          child: Container(
            width: 260, height: 200,
            decoration: BoxDecoration(
              border: Border.all(color: UellowColors.yellow, width: 3),
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ))),
        if (_busy) const Positioned(top: 10, left: 0, right: 0,
            child: LinearProgressIndicator(color: UellowColors.yellow,
                backgroundColor: Colors.black54)),
        Positioned(left: 16, right: 16, bottom: 30, child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xCC000000),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(ar
              ? 'وجه الكاميرا نحو الباركود لمسحه تلقائياً.'
              : 'Aim the camera at a product barcode — it scans automatically.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white)),
        )),
      ]),
    );
  }
}
