// =============================================================================
// CartScreen — list cart lines + delivery progress + coupon + totals + CTA.
// Pulls live data from /api/mobile/v2/cart. Supports guest cart (token in
// X-Cart-Token header is auto-managed by UellowApi).
// =============================================================================
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../api/uellow_api.dart';
import '../../api/uellow_models.dart';
import '../theme/uellow_theme.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});
  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  late Future<UellowCart> _future;
  final _couponCtrl = TextEditingController();

  // Multi-select mode
  bool _selectMode = false;
  final Set<int> _selected = {};

  @override
  void initState() {
    super.initState();
    _future = UellowApi.instance.cart.get();
  }

  Future<void> _reload() async {
    setState(() => _future = UellowApi.instance.cart.get());
    await _future;
  }

  Future<void> _updateLine(int lineId, int qty) async {
    try {
      final c = await UellowApi.instance.cart.update(lineId: lineId, qty: qty);
      setState(() => _future = Future.value(c));
    } on UellowApiException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _remove(int lineId) async {
    final c = await UellowApi.instance.cart.remove(lineId);
    setState(() => _future = Future.value(c));
  }

  Future<void> _applyCoupon() async {
    if (_couponCtrl.text.trim().isEmpty) return;
    try {
      final c = await UellowApi.instance.cart.applyCoupon(_couponCtrl.text.trim());
      _couponCtrl.clear();
      setState(() => _future = Future.value(c));
    } on UellowApiException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _removeCoupon() async {
    try {
      final c = await UellowApi.instance.cart.removeCoupon();
      setState(() => _future = Future.value(c));
      _snack(UellowApi.instance.lang == 'ar' ? 'تم حذف الكوبون' : 'Coupon removed');
    } on UellowApiException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _shareCart() async {
    // v2.0.77 — was only catching UellowApiException, so a PlatformException
    // from share_plus (e.g. no installed share targets) bubbled up as a red
    // overlay. Now any failure surfaces as a friendly snackbar.
    final ar = UellowApi.instance.lang == 'ar';
    try {
      final url = await UellowApi.instance.cart.share();
      if (url.isEmpty) {
        _snack(ar ? 'تعذّر مشاركة السلة' : 'Could not share cart');
        return;
      }
      final msg = ar
          ? 'شاهد سلتي في يلو 🛒\n$url'
          : 'Check out my Uellow cart 🛒\n$url';
      await Share.share(msg, subject: ar ? 'سلتي' : 'My Uellow cart');
    } on UellowApiException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack(ar
          ? 'تعذّر فتح المشاركة — تأكد من تثبيت تطبيقات مشاركة'
          : 'Sharing failed — make sure a share target app is installed');
    }
  }

  void _toggleSelectMode() {
    setState(() {
      _selectMode = !_selectMode;
      _selected.clear();
    });
  }

  void _toggleSelected(int lineId) {
    setState(() {
      if (_selected.contains(lineId)) {
        _selected.remove(lineId);
      } else {
        _selected.add(lineId);
      }
    });
  }

  void _selectAll(List<UellowCartLine> lines) {
    setState(() {
      if (_selected.length == lines.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(lines.map((l) => l.id));
      }
    });
  }

  Future<void> _bulkDelete() async {
    if (_selected.isEmpty) return;
    try {
      final c = await UellowApi.instance.cart.bulkRemove(_selected.toList());
      setState(() {
        _future = Future.value(c);
        _selected.clear();
        _selectMode = false;
      });
    } on UellowApiException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _bulkWishlist() async {
    if (_selected.isEmpty) return;
    try {
      final c = await UellowApi.instance.cart.bulkMoveToWishlist(_selected.toList());
      setState(() {
        _future = Future.value(c);
        _selected.clear();
        _selectMode = false;
      });
      _snack(UellowApi.instance.lang == 'ar'
          ? 'تم النقل إلى المفضّلة' : 'Moved to wishlist');
    } on UellowApiException catch (e) {
      _snack(e.message);
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UellowColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          // v2.0.76 — flip back arrow in AR so it points the natural way.
          icon: Icon(_selectMode
              ? Icons.close
              : (UellowApi.instance.lang.toLowerCase().startsWith('ar')
                  ? Icons.arrow_forward
                  : Icons.arrow_back),
              color: UellowColors.darkBrown),
          onPressed: () {
            if (_selectMode) {
              setState(() { _selectMode = false; _selected.clear(); });
              return;
            }
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              Navigator.pushReplacementNamed(context, '/home');
            }
          },
        ),
        title: Text(
            _selectMode
                ? (UellowApi.instance.lang == 'ar'
                    ? '${_selected.length} محدّد'
                    : '${_selected.length} selected')
                : (UellowApi.instance.lang == 'ar' ? 'سلة التسوق' : 'My Cart'),
            style: const TextStyle(color: UellowColors.ink,
                fontWeight: FontWeight.w900, fontSize: 16)),
        actions: [
          FutureBuilder<UellowCart>(
            future: _future,
            builder: (_, snap) {
              final hasLines = snap.data?.lineCount != null && snap.data!.lineCount > 0;
              if (!hasLines) return const SizedBox.shrink();
              if (_selectMode) {
                return TextButton(
                  onPressed: () => _selectAll(snap.data!.lines),
                  child: Text(
                    _selected.length == snap.data!.lines.length
                        ? (UellowApi.instance.lang == 'ar' ? 'إلغاء' : 'Clear')
                        : (UellowApi.instance.lang == 'ar' ? 'تحديد الكل' : 'Select all'),
                    style: const TextStyle(
                        color: UellowColors.darkBrown,
                        fontWeight: FontWeight.w800, fontSize: 12),
                  ),
                );
              }
              return Row(children: [
                IconButton(
                  icon: const Icon(Icons.checklist_rtl,
                      color: UellowColors.darkBrown, size: 22),
                  tooltip: UellowApi.instance.lang == 'ar' ? 'تحديد' : 'Select',
                  onPressed: _toggleSelectMode,
                ),
                IconButton(
                  icon: const Icon(Icons.share_outlined,
                      color: UellowColors.darkBrown, size: 22),
                  tooltip: UellowApi.instance.lang == 'ar' ? 'مشاركة' : 'Share',
                  onPressed: _shareCart,
                ),
              ]);
            },
          ),
        ],
      ),
      body: FutureBuilder<UellowCart>(
        future: _future,
        builder: (_, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: UellowColors.darkBrown));
          }
          if (snap.hasError) return _ErrorPane(message: snap.error.toString(), onRetry: _reload);
          final cart = snap.data!;
          if (cart.lineCount == 0) return _EmptyCart();
          return _buildContent(cart);
        },
      ),
      bottomNavigationBar: FutureBuilder<UellowCart>(
        future: _future,
        builder: (_, snap) {
          if (snap.connectionState != ConnectionState.done || snap.hasError) {
            return const SizedBox.shrink();
          }
          final c = snap.data!;
          if (c.lineCount == 0) return const SizedBox.shrink();
          if (_selectMode) {
            return _BulkActionsBar(
              count: _selected.length,
              onDelete: _selected.isEmpty ? null : _bulkDelete,
              onWishlist: _selected.isEmpty ? null : _bulkWishlist,
            );
          }
          return _CheckoutCta(total: c.totals.total);
        },
      ),
    );
  }

  Widget _buildContent(UellowCart cart) {
    return SafeArea(bottom: false, child: CustomScrollView(slivers: [
      SliverList.builder(
        itemCount: cart.lines.length,
        itemBuilder: (_, i) => _LineCard(
          line: cart.lines[i],
          onUpdate: _updateLine, onRemove: _remove,
          selectMode: _selectMode,
          selected: _selected.contains(cart.lines[i].id),
          onSelectToggle: () => _toggleSelected(cart.lines[i].id),
        ),
      ),
      // Free-shipping progress stays — it's an incentive, not a method picker.
      if (cart.freeShipping != null)
        SliverToBoxAdapter(child: _DeliveryBar(info: cart.freeShipping!)),
      // Delivery method picker is moved to the checkout screen per spec.
      const SliverToBoxAdapter(child: _CouponsBrowseLink()),
      SliverToBoxAdapter(child: _CouponRow(
        controller: _couponCtrl, onApply: _applyCoupon,
      )),
      for (final code in cart.coupons)
        SliverToBoxAdapter(child: _AppliedCoupon(code: code, onRemove: _removeCoupon)),
      SliverToBoxAdapter(child: _Totals(totals: cart.totals)),
      const SliverToBoxAdapter(child: SizedBox(height: 110)),
    ]));
  }
}

// ─── Sub-widgets ───────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.lineCount});
  final int lineCount;
  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang.toLowerCase().startsWith('ar');
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: UellowColors.border)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(ar ? 'سلتي' : 'My Cart', style: UT.h1),
        const SizedBox(height: 2),
        Text(ar ? '$lineCount منتج · جاهز للدفع' : '$lineCount items · ready to checkout',
            style: UT.small),
      ]),
    );
  }
}

class _LineCard extends StatelessWidget {
  const _LineCard({
    required this.line,
    required this.onUpdate,
    required this.onRemove,
    this.selectMode = false,
    this.selected = false,
    this.onSelectToggle,
  });
  final UellowCartLine line;
  final void Function(int, int) onUpdate;
  final void Function(int) onRemove;
  final bool selectMode;
  final bool selected;
  final VoidCallback? onSelectToggle;
  @override
  Widget build(BuildContext context) {
    final lang = UellowApi.instance.lang;
    return GestureDetector(
      onTap: selectMode ? onSelectToggle : null,
      child: Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        border: selected
            ? Border.all(color: UellowColors.yellow, width: 2)
            : null,
        boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 4, offset: Offset(0, 1))],
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (selectMode) Padding(
          padding: const EdgeInsets.only(right: 10, top: 28),
          child: Icon(
            selected ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 22,
            color: selected ? UellowColors.darkBrown : UellowColors.muted,
          ),
        ),
        ClipRRect(
          borderRadius: const BorderRadius.all(Radius.circular(10)),
          child: CachedNetworkImage(
            imageUrl: line.image, width: 84, height: 84, fit: BoxFit.cover,
            placeholder: (_, __) => Container(color: UellowColors.border, width: 84, height: 84),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(line.name.current(lang), maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, height: 1.4, color: UellowColors.ink)),
          const SizedBox(height: 8),
          // Per-unit price — stays constant when qty changes
          Row(children: [
            Text(line.unitPrice.format(), style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w900, color: UellowColors.ink)),
            const SizedBox(width: 6),
            const Text('/ pc', style: TextStyle(
                fontSize: 10, color: UellowColors.muted)),
            const Spacer(),
            _QtyBox(qty: line.qty.toInt(), onChange: (n) => onUpdate(line.id, n)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            GestureDetector(
              onTap: () async {
                try {
                  await UellowApi.instance.wishlist.add(line.productId);
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(UellowApi.instance.lang == 'ar'
                              ? 'حُفظ في المفضلة' : 'Saved to wishlist'),
                          duration: const Duration(seconds: 1)));
                  onRemove(line.id);
                } on UellowApiException catch (e) {
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.message)));
                }
              },
              child: Row(children: [
                const Icon(Icons.favorite_border, size: 12, color: UellowColors.muted),
                const SizedBox(width: 4),
                Text(UellowApi.instance.lang == 'ar'
                    ? 'حفظ لوقت لاحق' : 'Save for later', style: UT.small),
              ]),
            ),
            const Spacer(),
            // Line subtotal (qty × price) — updates as qty changes
            Text(line.subtotal.format(), style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700,
                color: UellowColors.muted)),
            const SizedBox(width: 14),
            GestureDetector(
              onTap: () => onRemove(line.id),
              child: Text(UellowApi.instance.lang == 'ar' ? 'إزالة' : 'Remove',
                  style: const TextStyle(
                  fontSize: 11, color: UellowColors.danger, fontWeight: FontWeight.w700)),
            ),
          ]),
        ])),
      ]),
      ),
    );
  }
}

class _QtyBox extends StatelessWidget {
  const _QtyBox({required this.qty, required this.onChange});
  final int qty;
  final ValueChanged<int> onChange;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: const BoxDecoration(
        color: UellowColors.border,
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _btn('−', () => qty > 1 ? onChange(qty - 1) : null),
        SizedBox(width: 24, child: Text('$qty',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800))),
        _btn('+', () => onChange(qty + 1)),
      ]),
    );
  }

  Widget _btn(String s, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28, height: 28, alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.all(Radius.circular(6)),
        ),
        child: Text(s, style: const TextStyle(
            color: UellowColors.darkBrown, fontWeight: FontWeight.w900, fontSize: 14)),
      ),
    );
  }
}

class _DeliveryBar extends StatelessWidget {
  const _DeliveryBar({required this.info});
  final UellowFreeShipping info;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 14, 14, 0),
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: UellowColors.yellowSoft,
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // v2.1.15 — bilingual (the progress label was English-only).
        if (info.qualified) Text.rich(TextSpan(
          style: const TextStyle(fontSize: 12, color: UellowColors.text), children: [
            TextSpan(text: UellowApi.instance.lang == 'ar'
                ? '🎉 تأهلت للحصول على ' : '🎉 You qualified for '),
            TextSpan(text: UellowApi.instance.lang == 'ar'
                ? 'توصيل مجاني!' : 'FREE delivery!',
                style: const TextStyle(color: UellowColors.successDk,
                    fontWeight: FontWeight.w800)),
          ],
        )) else Text.rich(TextSpan(
          style: const TextStyle(fontSize: 12, color: UellowColors.text), children: [
            TextSpan(text: UellowApi.instance.lang == 'ar' ? 'أضف ' : 'Add '),
            TextSpan(text: info.remaining.format(), style: const TextStyle(
                color: UellowColors.darkBrown, fontWeight: FontWeight.w800)),
            TextSpan(text: UellowApi.instance.lang == 'ar'
                ? ' للحصول على ' : ' more for '),
            TextSpan(text: UellowApi.instance.lang == 'ar'
                ? 'توصيل مجاني' : 'FREE delivery',
                style: const TextStyle(color: UellowColors.darkBrown,
                    fontWeight: FontWeight.w800)),
          ],
        )),
        const SizedBox(height: 6),
        Container(
          height: 6,
          decoration: BoxDecoration(color: Colors.white,
              borderRadius: BorderRadius.circular(999)),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft, widthFactor: info.progress.clamp(0, 1),
            child: const DecoratedBox(decoration: BoxDecoration(
              gradient: LinearGradient(colors: [UellowColors.yellowLight, UellowColors.yellow]),
              borderRadius: BorderRadius.all(Radius.circular(999)),
            )),
          ),
        ),
      ]),
    );
  }
}

class _ShippingMethods extends StatelessWidget {
  const _ShippingMethods({required this.methods});
  final List<UellowDeliveryOption> methods;
  @override
  Widget build(BuildContext context) {
    final lang = UellowApi.instance.lang;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 14, 14, 0),
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.local_shipping_outlined, size: 16, color: UellowColors.darkBrown),
          const SizedBox(width: 6),
          Text(UellowApi.instance.lang == 'ar' ? 'خيارات التوصيل' : 'Delivery options',
              style: UT.h3),
        ]),
        const SizedBox(height: 10),
        for (final m in methods) Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: UellowColors.border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            const Icon(Icons.radio_button_unchecked, size: 18, color: UellowColors.muted),
            const SizedBox(width: 10),
            Expanded(child: Text(m.name.current(lang),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
            Text(m.isFree ? 'FREE' : (m.rate?.format() ?? '—'),
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: m.isFree ? UellowColors.successDk : UellowColors.darkBrown,
                )),
          ]),
        ),
      ]),
    );
  }
}

/// Sleek tappable row that takes the customer straight to the full
/// Coupons screen — useful when they don't have a code memorized.
class _CouponsBrowseLink extends StatelessWidget {
  const _CouponsBrowseLink();
  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.pushNamed(context, '/coupons'),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [Color(0xFFFFE066), UellowColors.yellow],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [BoxShadow(color: Color(0x14000000),
                  blurRadius: 6, offset: Offset(0, 2))],
            ),
            child: Row(children: [
              Container(
                width: 36, height: 36, alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: UellowColors.darkBrown, shape: BoxShape.circle),
                child: const Icon(Icons.card_giftcard,
                    color: UellowColors.yellowLight, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(ar ? 'تصفح كوبوناتي' : 'Browse my coupons',
                    style: const TextStyle(fontSize: 13.5,
                        fontWeight: FontWeight.w900, color: UellowColors.darkBrown)),
                Text(ar ? 'لا تنسَ تطبيق أحد عروضك المتاحة'
                        : "Don't miss your available offers",
                    style: const TextStyle(fontSize: 11.5,
                        color: Color(0xFF5B3C00), fontWeight: FontWeight.w600)),
              ])),
              const Icon(Icons.chevron_right, color: UellowColors.darkBrown),
            ]),
          ),
        ),
      ),
    );
  }
}

class _CouponRow extends StatelessWidget {
  const _CouponRow({required this.controller, required this.onApply});
  final TextEditingController controller;
  final VoidCallback onApply;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
      child: Row(children: [
        Expanded(child: TextField(
          controller: controller,
          decoration: InputDecoration(
            // v2.0.76 — localized placeholder (was English-only)
            hintText: UellowApi.instance.lang.toLowerCase().startsWith('ar')
                ? 'عندك كود خصم؟' : 'Got a promo code?',
            hintStyle: const TextStyle(color: UellowColors.muted),
            fillColor: Colors.white,
            filled: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFD6C79A), style: BorderStyle.solid),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFD6C79A)),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        )),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: onApply,
          style: ElevatedButton.styleFrom(
            backgroundColor: UellowColors.yellowLight,
            foregroundColor: UellowColors.darkBrown,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          ),
          child: Text(UellowApi.instance.lang == 'ar' ? 'تطبيق' : 'Apply',
              style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
      ]),
    );
  }
}

class _AppliedCoupon extends StatelessWidget {
  const _AppliedCoupon({required this.code, this.onRemove});
  final String code;
  final VoidCallback? onRemove;
  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 14, 14, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: UellowColors.yellowSoft,
        border: Border.all(color: UellowColors.yellow, width: 1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: const BoxDecoration(
            color: UellowColors.yellowLight,
            borderRadius: BorderRadius.all(Radius.circular(4)),
          ),
          child: Text(code, style: const TextStyle(
              color: UellowColors.darkBrown, fontWeight: FontWeight.w800, fontSize: 11)),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(ar ? 'تم تطبيق الكوبون' : 'Coupon applied',
            style: const TextStyle(fontSize: 12, color: UellowColors.text,
                fontWeight: FontWeight.w700))),
        const Icon(Icons.check_circle, size: 18, color: UellowColors.success),
        if (onRemove != null) ...[
          const SizedBox(width: 6),
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: 26, height: 26, alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: Colors.white, shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Color(0x14000000),
                    blurRadius: 3, offset: Offset(0, 1))],
              ),
              child: const Icon(Icons.close, size: 14, color: UellowColors.danger),
            ),
          ),
        ],
      ]),
    );
  }
}

class _BulkActionsBar extends StatelessWidget {
  const _BulkActionsBar({
    required this.count,
    this.onDelete,
    this.onWishlist,
  });
  final int count;
  final VoidCallback? onDelete;
  final VoidCallback? onWishlist;

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    final enabled = count > 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: UellowColors.border)),
        boxShadow: [BoxShadow(
            color: Color(0x14000000), blurRadius: 10, offset: Offset(0, -2))],
      ),
      child: SafeArea(
        top: false,
        child: Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: enabled ? onWishlist : null,
              icon: const Icon(Icons.favorite_border, size: 16),
              label: Text(ar ? 'إلى المفضّلة' : 'To wishlist',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: UellowColors.darkBrown,
                side: BorderSide(color: enabled ? UellowColors.darkBrown : UellowColors.border),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12))),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: enabled ? onDelete : null,
              icon: const Icon(Icons.delete_outline, size: 16),
              label: Text(
                  ar ? 'حذف ($count)' : 'Delete ($count)',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: UellowColors.danger,
                foregroundColor: Colors.white,
                disabledBackgroundColor: UellowColors.border,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12))),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({required this.totals});
  final UellowCartTotals totals;
  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      color: Colors.white,
      child: Column(children: [
        _row(ar ? 'الإجمالي قبل الخصم' : 'Subtotal', totals.subtotal.format()),
        _row(ar ? 'الشحن' : 'Delivery',
            ar ? 'يُحسب لاحقاً' : 'Calculated at checkout',
            valueColor: UellowColors.muted),
        if (totals.discount.amount != 0)
          _row(ar ? 'الخصم' : 'Discount',
              '− ${totals.discount.format()}', valueColor: UellowColors.successDk),
        const Divider(height: 24),
        _row(ar ? 'الإجمالي' : 'Total', totals.total.format(), big: true),
      ]),
    );
  }

  Widget _row(String label, String value, {Color? valueColor, bool big = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(label, style: big
            ? const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: UellowColors.darkBrown)
            : UT.body)),
        Text(value, style: big
            ? const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: UellowColors.darkBrown)
            : TextStyle(color: valueColor ?? UellowColors.text,
                fontWeight: FontWeight.w700, fontSize: 13)),
      ]),
    );
  }
}

class _CheckoutCta extends StatelessWidget {
  const _CheckoutCta({required this.total});
  final UellowMoney total;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: UellowColors.border)),
        boxShadow: [BoxShadow(
            color: Color(0x14000000), blurRadius: 10, offset: Offset(0, -2))],
      ),
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [UellowColors.yellowLight, UellowColors.yellow,
                       Color(0xFFE5A900)],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(
              color: UellowColors.yellow.withValues(alpha: 0.5),
              blurRadius: 16, offset: const Offset(0, 6),
            )],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => Navigator.of(context).pushNamed('/checkout'),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
                child: Row(children: [
                  const Icon(Icons.lock_outline, size: 18, color: UellowColors.darkBrown),
                  const SizedBox(width: 8),
                  Text(UellowApi.instance.lang == 'ar' ? 'إتمام الدفع الآمن' : 'Secure Checkout',
                      style: const TextStyle(
                      color: UellowColors.darkBrown,
                      fontSize: 15, fontWeight: FontWeight.w900,
                      letterSpacing: 0.2)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: UellowColors.darkBrown,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(children: [
                      Text(total.format(), style: const TextStyle(
                          color: UellowColors.yellowLight, fontSize: 14,
                          fontWeight: FontWeight.w900)),
                      const SizedBox(width: 6),
                      const Icon(Icons.arrow_forward, size: 16,
                          color: UellowColors.yellowLight),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyCart extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang.toLowerCase().startsWith('ar');
    return ListView(children: [
      const SizedBox(height: 100),
      const Center(child: Icon(Icons.shopping_cart_outlined,
          size: 80, color: UellowColors.muted)),
      const SizedBox(height: 18),
      Center(child: Text(ar ? 'سلتك فارغة' : 'Your cart is empty', style: UT.h2)),
      const SizedBox(height: 6),
      Center(child: Text(
          ar ? 'تصفّح أحدث العروض وأضفها إلى السلة' : 'Browse the latest deals and add to cart',
          textAlign: TextAlign.center, style: UT.body)),
      const SizedBox(height: 20),
      Center(child: ElevatedButton.icon(
        onPressed: () {
          // Always go to home — `Navigator.pop` could surface an /auth
          // screen left in the stack for signed-in users (the reported
          // "Continue shopping sent me to login" bug).
          Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
        },
        icon: const Icon(Icons.shopping_bag_outlined, size: 16),
        label: Text(UellowApi.instance.lang == 'ar'
            ? 'متابعة التسوق' : 'Continue shopping'),
      )),
    ]);
  }
}

class _ErrorPane extends StatelessWidget {
  const _ErrorPane({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    return Center(child: Padding(
      padding: const EdgeInsets.all(30),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.cloud_off_outlined, size: 56, color: UellowColors.muted),
        const SizedBox(height: 14),
        Text(message, textAlign: TextAlign.center, style: UT.body),
        const SizedBox(height: 16),
        ElevatedButton(onPressed: onRetry,
            child: Text(UellowApi.instance.lang == 'ar' ? 'إعادة المحاولة' : 'Retry')),
      ]),
    ));
  }
}
