// =============================================================================
// DocViewerScreen (v2.2.170) — عارض مستندات PDF داخل التطبيق + طباعة + مشاركة.
// يُستخدَم من تفاصيل الطلب (فاتورة/ضمان/ليبل) ومن المشتريات (أمر الشراء/كشف
// الحساب). يجلب البايتات من رابط موقّع عام (access_token) فلا يحتاج مصادقة.
// =============================================================================
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';

import '../theme/uellow_theme.dart';

class DocViewerScreen extends StatelessWidget {
  const DocViewerScreen({
    super.key,
    required this.title,
    required this.url,
    this.fileName,
  });

  final String title;
  final String url;
  final String? fileName;

  Future<Uint8List> _fetch() async {
    final r = await http.get(Uri.parse(url));
    if (r.statusCode >= 200 && r.statusCode < 300) {
      return r.bodyBytes;
    }
    throw Exception('HTTP ${r.statusCode}');
  }

  @override
  Widget build(BuildContext context) {
    final ar = _isAr(context);
    return Scaffold(
      backgroundColor: const Color(0xFF3A3A3A),
      appBar: AppBar(
        backgroundColor: UellowColors.darkBrown,
        foregroundColor: Colors.white,
        title: Text(title,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
      ),
      body: PdfPreview(
        build: (format) => _fetch(),
        useActions: true,
        allowPrinting: true,
        allowSharing: true,
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        maxPageWidth: 820,
        pdfFileName: fileName ?? 'document.pdf',
        loadingWidget: const Center(
            child: CircularProgressIndicator(color: Color(0xFFE8A800))),
        onError: (ctx, error) => Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.picture_as_pdf_rounded,
                  color: Colors.white54, size: 48),
              const SizedBox(height: 12),
              Text(
                  ar
                      ? 'تعذّر فتح المستند. تحقّق من الاتصال وحاول مجددًا.'
                      : 'Could not open the document. Check your connection.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ]),
          ),
        ),
      ),
    );
  }

  bool _isAr(BuildContext context) =>
      Directionality.of(context) == TextDirection.rtl;
}
