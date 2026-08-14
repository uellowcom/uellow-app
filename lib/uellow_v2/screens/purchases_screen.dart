// مشترياتي — all purchases (website معرض + POS سيلز) with a receipt viewer.
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';
import '../../api/uellow_api.dart';

class PurchasesScreen extends StatefulWidget {
  const PurchasesScreen({super.key});
  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> {
  List _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await UellowApi.instance
          .getRaw('/api/mobile/v2/purchases', auth: true);
      final data = (r['data'] as Map?) ?? const {};
      _items = (data['purchases'] as List?) ?? const [];
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _openReceipt(String path) async {
    try {
      final token = await UellowApi.instance.tokenStore.readToken();
      final headers = <String, String>{'X-Lang': UellowApi.instance.lang};
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
      final r = await http.get(
          Uri.parse('${UellowApi.instance.baseUrl}$path'), headers: headers);
      if (!mounted) return;
      if (r.statusCode == 200 &&
          (r.headers['content-type'] ?? '').contains('text/html')) {
        Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => _ReceiptView(html: r.body)));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('تعذّر فتح الإيصال')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('تعذّر فتح الإيصال')));
      }
    }
  }

  String _amt(dynamic m) {
    if (m is Map) {
      final a = (m['amount'] as num? ?? 0)
          .toStringAsFixed((m['digits'] as num?)?.toInt() ?? 3);
      return '$a ${m['symbol'] ?? ''}'.trim();
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: const Color(0xFFF3EDE0),
        appBar: AppBar(
          backgroundColor: const Color(0xFF412402),
          foregroundColor: const Color(0xFFF5C320),
          iconTheme: const IconThemeData(color: Color(0xFFF5C320)),
          title: Text(ar ? 'مشترياتي 🧾' : 'My Purchases 🧾',
              style: const TextStyle(
                  fontWeight: FontWeight.w900, color: Color(0xFFF5C320))),
        ),
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF412402)))
            : _items.isEmpty
                ? Center(
                    child: Text(ar ? 'لا مشتريات بعد' : 'No purchases yet',
                        style: const TextStyle(
                            color: Color(0xFF9A8763),
                            fontWeight: FontWeight.w700)))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _items.length,
                      itemBuilder: (_, i) =>
                          _row(_items[i] as Map, ar),
                    ),
                  ),
      ),
    );
  }

  Widget _row(Map p, bool ar) {
    final isPos = p['source'] == 'pos';
    final date = (p['date'] ?? '').toString();
    final d = date.length >= 10 ? date.substring(0, 10) : date;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFEDE4CC))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
                color: isPos
                    ? const Color(0xFFFFF2D6)
                    : const Color(0xFFE7F0FF),
                borderRadius: BorderRadius.circular(7)),
            child: Text(
                isPos ? (ar ? 'المعرض 🏬' : 'In-store 🏬') : (ar ? 'اونلاين 🛍️' : 'Online 🛍️'),
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    color: isPos
                        ? const Color(0xFFA06A00)
                        : const Color(0xFF2563EB))),
          ),
          const SizedBox(width: 8),
          Expanded(
              child: Text('${p['name'] ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: Color(0xFF20242C)))),
          Text(_amt(p['amount']),
              style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13.5,
                  color: Color(0xFFC85A00))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Text(d,
              style: const TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFF8A7A5A),
                  fontWeight: FontWeight.w600)),
          const Spacer(),
          if (isPos)
            InkWell(
              onTap: () => _openReceipt('${p['receipt']}'),
              borderRadius: BorderRadius.circular(9),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                    color: const Color(0xFFF5C320),
                    borderRadius: BorderRadius.circular(9)),
                child: Text(ar ? '🧾 الإيصال' : '🧾 Receipt',
                    style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        color: Color(0xFF412402))),
              ),
            ),
        ]),
      ]),
    );
  }
}

class _ReceiptView extends StatefulWidget {
  final String html;
  const _ReceiptView({required this.html});
  @override
  State<_ReceiptView> createState() => _ReceiptViewState();
}

class _ReceiptViewState extends State<_ReceiptView> {
  late final WebViewController _c;
  @override
  void initState() {
    super.initState();
    _c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadHtmlString(widget.html);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF412402),
        foregroundColor: const Color(0xFFF5C320),
        iconTheme: const IconThemeData(color: Color(0xFFF5C320)),
        title: const Text('الإيصال',
            style: TextStyle(
                color: Color(0xFFF5C320), fontWeight: FontWeight.w900)),
      ),
      body: WebViewWidget(controller: _c),
    );
  }
}
