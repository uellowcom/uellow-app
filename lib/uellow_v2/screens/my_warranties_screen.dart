// =============================================================================
// MyWarrantiesScreen — the customer's warranty cards from
// /api/mobile/v2/warranty. Bilingual, with policy, coverage, full terms and
// a one-tap certificate PDF (token-stamped).
// =============================================================================
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/uellow_api.dart';
import '../theme/uellow_theme.dart';

class MyWarrantiesScreen extends StatefulWidget {
  const MyWarrantiesScreen({super.key});
  @override
  State<MyWarrantiesScreen> createState() => _MyWarrantiesScreenState();
}

class _MyWarrantiesScreenState extends State<MyWarrantiesScreen> {
  Future<UellowWarrantyOverview>? _future;

  bool get _ar => UellowApi.instance.lang == 'ar';

  @override
  void initState() {
    super.initState();
    _future = UellowApi.instance.warranty.myWarranties();
  }

  Future<void> _refresh() async {
    setState(() => _future = UellowApi.instance.warranty.myWarranties());
    await _future;
  }

  Color _stateColor(String s) {
    switch (s) {
      case 'active':
        return UellowColors.successDk;
      case 'expired':
        return UellowColors.muted;
      case 'void':
        return UellowColors.dangerDk;
      case 'claimed':
        return UellowColors.warn;
      default:
        return UellowColors.muted;
    }
  }

  Future<void> _openCertificate(int id) async {
    final url = await UellowApi.instance.warranty.certificateUrl(id);
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ar = _ar;
    return Scaffold(
      backgroundColor: UellowColors.bg,
      appBar: AppBar(
        backgroundColor: UellowColors.bg,
        elevation: 0,
        leading: const BackButton(color: UellowColors.darkBrown),
        title: Text(ar ? 'ضماناتي' : 'My Warranties', style: UT.h2),
      ),
      body: SafeArea(
        bottom: false,
        child: FutureBuilder<UellowWarrantyOverview>(
          future: _future,
          builder: (_, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(
                  child: CircularProgressIndicator(color: UellowColors.darkBrown));
            }
            if (snap.hasError || snap.data == null) {
              return _errorState(ar);
            }
            final data = snap.data!;
            if (data.warranties.isEmpty) return _emptyState(ar);
            return RefreshIndicator(
              onRefresh: _refresh,
              color: UellowColors.darkBrown,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 30),
                children: [
                  _summary(data, ar),
                  const SizedBox(height: 12),
                  ...data.warranties.map((c) => _card(c, ar)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _summary(UellowWarrantyOverview d, bool ar) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: UellowColors.darkBrown,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_user, color: UellowColors.yellow, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              ar ? 'الضمانات النشطة' : 'Active warranties',
              style: UT.body.copyWith(color: Colors.white),
            ),
          ),
          Text('${d.active}/${d.count}',
              style: UT.h2.copyWith(color: UellowColors.yellow)),
        ],
      ),
    );
  }

  Widget _card(UellowWarrantyCard c, bool ar) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: UellowColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // header
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(c.image,
                      width: 56, height: 56, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                          width: 56, height: 56, color: UellowColors.yellowFaint,
                          child: const Icon(Icons.inventory_2_outlined,
                              color: UellowColors.muted))),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.product, style: UT.subtitle, maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 3),
                      Text(c.number, style: UT.tiny.copyWith(color: UellowColors.muted)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: UellowColors.yellow,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('${c.icon} ${c.months} ${ar ? 'شهر' : 'mo'}',
                      style: UT.small.copyWith(
                          color: UellowColors.darkBrown,
                          fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // dates + state
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Row(
              children: [
                Expanded(
                  child: _kv(ar ? 'يبدأ' : 'Start', c.dateStart, ar),
                ),
                Expanded(
                  child: _kv(ar ? 'ينتهي' : 'Expires', c.dateEnd, ar),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _stateColor(c.state).withOpacity(.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(c.stateLabel,
                      style: UT.small.copyWith(
                          color: _stateColor(c.state),
                          fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
          if (c.state == 'active' && c.daysLeft > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Text(
                ar ? 'متبقٍ ${c.daysLeft} يوم' : '${c.daysLeft} days left',
                style: UT.tiny.copyWith(color: UellowColors.successDk),
              ),
            ),
          // coverage
          if (c.coverage.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Text(c.coverage,
                  style: UT.small.copyWith(color: UellowColors.text)),
            ),
          // terms (expandable)
          if (c.terms.isNotEmpty)
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 14),
                childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                title: Text(ar ? 'الشروط والأحكام' : 'Terms & Conditions',
                    style: UT.small.copyWith(fontWeight: FontWeight.w800)),
                children: [
                  Align(
                    alignment: ar ? Alignment.centerRight : Alignment.centerLeft,
                    child: Text(c.terms,
                        textAlign: ar ? TextAlign.right : TextAlign.left,
                        style: UT.tiny.copyWith(
                            color: UellowColors.muted, height: 1.5)),
                  ),
                ],
              ),
            ),
          // certificate button
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _openCertificate(c.id),
                style: OutlinedButton.styleFrom(
                  foregroundColor: UellowColors.darkBrown,
                  side: const BorderSide(color: UellowColors.darkBrown),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: Text(ar ? 'شهادة الضمان' : 'Warranty Certificate',
                    style: UT.small.copyWith(fontWeight: FontWeight.w800)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v, bool ar) {
    return Column(
      crossAxisAlignment:
          ar ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(k, style: UT.tiny.copyWith(color: UellowColors.muted)),
        const SizedBox(height: 2),
        Text(v, style: UT.small.copyWith(fontWeight: FontWeight.w800)),
      ],
    );
  }

  Widget _emptyState(bool ar) {
    return ListView(
      children: [
        const SizedBox(height: 120),
        const Icon(Icons.verified_user_outlined,
            size: 64, color: UellowColors.muted),
        const SizedBox(height: 14),
        Center(
          child: Text(ar ? 'لا توجد ضمانات بعد' : 'No warranties yet',
              style: UT.subtitle),
        ),
        const SizedBox(height: 6),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              ar
                  ? 'الضمان يُضاف تلقائيًا عند شراء منتجات مشمولة بالضمان.'
                  : 'Warranties are added automatically when you buy covered products.',
              textAlign: TextAlign.center,
              style: UT.small.copyWith(color: UellowColors.muted),
            ),
          ),
        ),
      ],
    );
  }

  Widget _errorState(bool ar) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 56, color: UellowColors.muted),
            const SizedBox(height: 12),
            Text(ar ? 'تعذّر تحميل الضمانات' : 'Failed to load warranties',
                textAlign: TextAlign.center, style: UT.body),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _refresh,
              style: ElevatedButton.styleFrom(
                  backgroundColor: UellowColors.darkBrown,
                  foregroundColor: Colors.white),
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(ar ? 'إعادة المحاولة' : 'Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
