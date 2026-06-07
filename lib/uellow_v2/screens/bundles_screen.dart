// =============================================================================
// BundlesScreen — full grid of all published bundles (v2.2.21). Opened from
// the yellow "View more" button on the Bundles Showcase block.
// =============================================================================
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../api/uellow_api.dart';
import '../theme/uellow_theme.dart';
import 'promo_page_blocks.dart' show BundleShowcaseBlock;

class BundlesScreen extends StatefulWidget {
  const BundlesScreen({super.key});
  @override
  State<BundlesScreen> createState() => _BundlesScreenState();
}

class _BundlesScreenState extends State<BundlesScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final r = await http.get(
      Uri.parse('${UellowApi.instance.baseUrl}/api/mobile/v2/bundles'
          '?per_page=60'),
      headers: const {'Accept': 'application/json'},
    ).timeout(const Duration(seconds: 12));
    final body = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    if (body['success'] != true) return [];
    // Each bundle item carries its product `card` — feed those straight into
    // the same showcase block renderer so cards look identical.
    return ((body['data']?['items'] as List?) ?? const [])
        .cast<dynamic>()
        .map((e) => (e as Map).cast<String, dynamic>())
        .map((b) => (b['card'] as Map?)?.cast<String, dynamic>()
            ?? <String, dynamic>{})
        .where((c) => c.isNotEmpty)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang.toLowerCase().startsWith('ar');
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        title: Text(ar ? 'الباقات' : 'Bundles'),
        backgroundColor: Colors.white,
        foregroundColor: UellowColors.darkBrown,
        elevation: 0.5,
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (_, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data ?? const [];
          if (items.isEmpty) {
            return Center(child: Text(ar ? 'لا توجد باقات حالياً'
                : 'No bundles right now', style: UT.body));
          }
          // Reuse the showcase block in grid mode for one consistent card.
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: BundleShowcaseBlock(
              p: const {'layout': 'grid', 'titleEn': '', 'titleAr': '',
                        'c1': '#FFFFFF', 'c2': '#FFFFFF',
                        'text_color': '#412402', 'sub_color': '#777777',
                        'show_more': false},
              data: {'items': items},
              ar: ar,
            ),
          );
        },
      ),
    );
  }
}
