// =============================================================================
// CartScreen — list cart lines + delivery progress + coupon + totals + CTA.
// Pulls live data from /api/mobile/v2/cart. Supports guest cart (token in
// X-Cart-Token header is auto-managed by UellowApi).
// =============================================================================
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/uellow_api.dart';
import '../../api/uellow_models.dart';
import '../router/uellow_router.dart';
import '../theme/uellow_theme.dart';
import '../widgets/product_card.dart';
import '../widgets/updating_pane.dart';

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

  Future<void> _removeCoupon(String code) async {
    // v2.1.56 — removes ONLY the tapped coupon (× used to wipe them all).
    try {
      final c = await UellowApi.instance.cart.removeCoupon(code);
      setState(() => _future = Future.value(c));
      _snack(UellowApi.instance.lang == 'ar' ? 'تم حذف الكوبون' : 'Coupon removed');
    } on UellowApiException catch (e) {
      _snack(e.message);
    }
  }

  // ── v2.1.66 — QR share dialog ──────────────────────────────────────
  // QR (scan → cart opens on the friend's app) + readable serial +
  // WhatsApp / copy link / generic share.
  Future<void> _shareCartDialog() async {
    final ar = UellowApi.instance.lang == 'ar';
    Map<String, dynamic> d;
    try {
      d = await UellowApi.instance.cart.shareDetails();
    } on UellowApiException catch (e) {
      _snack(e.message);
      return;
    } catch (_) {
      _snack(ar ? 'تعذّر مشاركة السلة' : 'Could not share cart');
      return;
    }
    final url = (d['url'] as String?) ?? '';
    final serial = (d['serial_display'] as String?)
        ?? (d['serial'] as String?) ?? '';
    if (url.isEmpty || !mounted) return;
    final msg = ar
        ? 'شاهد سلتي في يلو 🛒\n$url\nأو أدخل الرمز في التطبيق: $serial'
        : 'Check out my Uellow cart 🛒\n$url\nOr enter this code in the app: $serial';
    await showDialog(
      context: context,
      builder: (dctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              const Icon(Icons.shopping_cart_outlined,
                  color: UellowColors.darkBrown, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(ar ? 'مشاركة سلتي' : 'Share my cart',
                  style: const TextStyle(fontWeight: FontWeight.w900,
                      fontSize: 15, color: UellowColors.ink))),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => Navigator.of(dctx).pop(),
                icon: const Icon(Icons.close, size: 20,
                    color: UellowColors.muted),
              ),
            ]),
            const SizedBox(height: 10),
            // QR — a friend scans it from the cart's import button
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: UellowColors.yellow, width: 2),
              ),
              child: QrImageView(
                data: url, size: 180,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: UellowColors.darkBrown),
                dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: UellowColors.darkBrown),
              ),
            ),
            const SizedBox(height: 10),
            Text(ar ? 'أو أدخل الرمز يدوياً' : 'or enter this code',
                style: UT.small),
            const SizedBox(height: 4),
            // Serial — tap to copy
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: serial));
                if (dctx.mounted) {
                  ScaffoldMessenger.of(dctx).showSnackBar(SnackBar(
                      content: Text(ar ? 'تم نسخ الرمز' : 'Code copied')));
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: UellowColors.yellowFaint,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: UellowColors.yellow.withValues(alpha: .6)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(serial, style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w900,
                      letterSpacing: 2, color: UellowColors.darkBrown)),
                  const SizedBox(width: 8),
                  const Icon(Icons.copy, size: 16,
                      color: UellowColors.darkBrown),
                ]),
              ),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: _shareAction(
                icon: Icons.chat, color: const Color(0xFF25D366),
                label: ar ? 'واتساب' : 'WhatsApp',
                onTap: () async {
                  final wa = Uri.parse(
                      'https://wa.me/?text=${Uri.encodeComponent(msg)}');
                  try {
                    await launchUrl(wa,
                        mode: LaunchMode.externalApplication);
                  } catch (_) {}
                },
              )),
              const SizedBox(width: 8),
              Expanded(child: _shareAction(
                icon: Icons.link, color: UellowColors.darkBrown,
                label: ar ? 'نسخ الرابط' : 'Copy link',
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: url));
                  if (dctx.mounted) {
                    ScaffoldMessenger.of(dctx).showSnackBar(SnackBar(
                        content: Text(ar ? 'تم نسخ الرابط' : 'Link copied')));
                  }
                },
              )),
              const SizedBox(width: 8),
              Expanded(child: _shareAction(
                icon: Icons.share_outlined, color: UellowColors.darkBrown,
                label: ar ? 'مشاركة' : 'Share',
                onTap: () async {
                  try {
                    await Share.share(msg,
                        subject: ar ? 'سلتي' : 'My Uellow cart');
                  } catch (_) {}
                },
              )),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _shareAction({required IconData icon, required Color color,
      required String label, required VoidCallback onTap}) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: .5)),
        padding: const EdgeInsets.symmetric(vertical: 9),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 18),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(
            fontSize: 10, fontWeight: FontWeight.w800)),
      ]),
    );
  }

  // ── v2.1.66 — import a friend's cart: scan its QR or type the code ─
  Future<void> _importCartSheet() async {
    final ar = UellowApi.instance.lang == 'ar';
    final ctrl = TextEditingController();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            18, 16, 18, 16 + MediaQuery.of(sctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(ar ? 'استيراد سلة صديق 🛒' : "Import a friend's cart 🛒",
              style: const TextStyle(fontWeight: FontWeight.w900,
                  fontSize: 15.5, color: UellowColors.ink)),
          const SizedBox(height: 4),
          Text(ar
              ? 'امسح رمز QR الخاص بسلة صديقك أو أدخل رمزها — تُضاف منتجاتها إلى سلتك.'
              : "Scan your friend's cart QR or type its code — the items get added to your cart.",
              style: UT.small),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                Navigator.of(sctx).pop();
                final code = await Navigator.of(context).pushNamed(
                    '/scan', arguments: {'return_raw': true});
                if (code is String && code.isNotEmpty) {
                  await _doImport(code);
                }
              },
              icon: const Icon(Icons.qr_code_scanner, size: 19),
              label: Text(ar ? 'مسح رمز QR' : 'Scan QR code',
                  style: const TextStyle(fontWeight: FontWeight.w900)),
              style: ElevatedButton.styleFrom(
                backgroundColor: UellowColors.yellow,
                foregroundColor: UellowColors.darkBrown,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(ar ? 'أو' : 'or', style: UT.small),
            ),
            const Expanded(child: Divider()),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              hintText: ar ? 'أدخل رمز السلة (مثال K7F2-9Q4D)'
                           : 'Enter cart code (e.g. K7F2-9Q4D)',
              hintStyle: const TextStyle(fontSize: 12.5),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () async {
                final code = ctrl.text.trim();
                if (code.isEmpty) return;
                Navigator.of(sctx).pop();
                await _doImport(code);
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: UellowColors.darkBrown,
                side: const BorderSide(color: UellowColors.darkBrown),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13)),
              ),
              child: Text(ar ? 'إضافة إلى سلتي' : 'Add to my cart',
                  style: const TextStyle(fontWeight: FontWeight.w900)),
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _doImport(String code) async {
    final ar = UellowApi.instance.lang == 'ar';
    try {
      final (cart, added) = await UellowApi.instance.cart.importShared(code);
      if (!mounted) return;
      setState(() => _future = Future.value(cart));
      _snack(ar ? 'أُضيف $added منتج إلى سلتك ✅'
                : '$added item(s) added to your cart ✅');
    } on UellowApiException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack(ar ? 'تعذّر استيراد السلة' : 'Could not import cart');
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

  /// Selective checkout (v2.1.65) — pay for ONLY the checked lines; the
  /// rest stays in the cart (the backend splits the order at confirm).
  Future<void> _checkoutSelected() async {
    if (_selected.isEmpty) return;
    await Navigator.of(context).pushNamed('/checkout',
        arguments: {'line_ids': _selected.toList()});
    if (!mounted) return;
    // Back from checkout: the ordered lines are gone from the cart —
    // refetch and drop the selection.
    setState(() {
      _future = UellowApi.instance.cart.get();
      _selected.clear();
      _selectMode = false;
    });
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang.toLowerCase().startsWith('ar');
    // v2.1.23 — explicit RTL for the header in Arabic: back button sits on
    // the RIGHT, select + share flow to the LEFT. arrow_back auto-mirrors
    // under RTL so the manual arrow_forward hack is gone.
    return Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
      backgroundColor: UellowColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: Icon(_selectMode ? Icons.close : Icons.arrow_back,
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
              if (_selectMode && hasLines) {
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
                if (hasLines) IconButton(
                  icon: const Icon(Icons.checklist_rtl,
                      color: UellowColors.darkBrown, size: 22),
                  tooltip: UellowApi.instance.lang == 'ar' ? 'تحديد' : 'Select',
                  onPressed: _toggleSelectMode,
                ),
                // v2.1.66 — import a friend's cart (works on empty carts too)
                IconButton(
                  icon: const Icon(Icons.qr_code_scanner,
                      color: UellowColors.darkBrown, size: 22),
                  tooltip: UellowApi.instance.lang == 'ar'
                      ? 'استيراد سلة' : 'Import cart',
                  onPressed: _importCartSheet,
                ),
                if (hasLines) IconButton(
                  icon: const Icon(Icons.share_outlined,
                      color: UellowColors.darkBrown, size: 22),
                  tooltip: UellowApi.instance.lang == 'ar' ? 'مشاركة' : 'Share',
                  onPressed: _shareCartDialog,
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
            // v2.1.56 — bottom bar shows the total of the SELECTED items
            // only (used to keep showing the whole-cart total).
            final sel = c.lines.where((l) => _selected.contains(l.id));
            final selSum = sel.fold<double>(0, (s, l) => s + l.subtotal.amount);
            final ref = c.totals.total;
            return _BulkActionsBar(
              count: _selected.length,
              selectedTotal: UellowMoney(
                  amount: selSum, currency: ref.currency,
                  symbol: ref.symbol, digits: ref.digits).format(),
              onDelete: _selected.isEmpty ? null : _bulkDelete,
              onWishlist: _selected.isEmpty ? null : _bulkWishlist,
              onCheckout: _selected.isEmpty ? null : _checkoutSelected,
            );
          }
          return _CheckoutCta(total: c.totals.total);
        },
      ),
    ));
  }

  Widget _buildContent(UellowCart cart) {
    return SafeArea(bottom: false, child: CustomScrollView(slivers: [
      // v2.1.57 — targeted announcement strip (admin-controlled).
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
        SliverToBoxAdapter(child: _AppliedCoupon(
            code: code, onRemove: () => _removeCoupon(code))),
      SliverToBoxAdapter(child: _Totals(totals: cart.totals)),
      // v2.1.59 — was 110: a big dead band under the totals.
      const SliverToBoxAdapter(child: SizedBox(height: 24)),
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
      // v2.1.34 — tapping a cart line opens its product page.
      onTap: selectMode
          ? onSelectToggle
          : () => UellowRouter.goProduct(context, line.productId),
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
          // v2.1.69 — directional (was right:) so RTL doesn't squeeze the
          // row into the image.
          padding: const EdgeInsetsDirectional.only(end: 10, top: 28),
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
            // v2.1.69 — smaller in select mode: the checkbox narrows the
            // row and the 15px price collided with the image.
            Flexible(child: Text(line.unitPrice.format(),
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: selectMode ? 12 : 15,
                    fontWeight: FontWeight.w900, color: UellowColors.ink))),
            const SizedBox(width: 6),
            // v2.1.34 — "pc" was English-only; bilingual now.
            Text(lang == 'ar' ? '/ قطعة' : '/ pc', style: const TextStyle(
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
        // v2.1.57 — flagged-product / coupon orders show WHY it's free.
        if (info.qualified) Text.rich(TextSpan(
          style: const TextStyle(fontSize: 12, color: UellowColors.text), children: [
            TextSpan(text: UellowApi.instance.lang == 'ar'
                ? '🎉 تأهلت للحصول على ' : '🎉 You qualified for '),
            TextSpan(text: UellowApi.instance.lang == 'ar'
                ? 'توصيل مجاني!' : 'FREE delivery!',
                style: const TextStyle(color: UellowColors.successDk,
                    fontWeight: FontWeight.w800)),
            if (info.reason == 'product') TextSpan(
                text: UellowApi.instance.lang == 'ar'
                    ? ' · منتجاتك بشحن مجاني' : ' · free-ship items',
                style: const TextStyle(fontSize: 10,
                    color: UellowColors.muted)),
            if (info.reason == 'coupon') TextSpan(
                text: UellowApi.instance.lang == 'ar'
                    ? ' · كوبون شحن مجاني' : ' · free-ship coupon',
                style: const TextStyle(fontSize: 10,
                    color: UellowColors.muted)),
          ],
        ), maxLines: 1, overflow: TextOverflow.ellipsis) else Text.rich(TextSpan(
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
        const SizedBox(height: 8),
        // v2.1.56 — the light-green "remaining" track is now unmistakable:
        // taller bar, stronger light-green + hairline border, and the fill
        // starts from the reading direction (right in Arabic).
        // v2.1.67 — the bar was ZERO-width: the Column doesn't stretch its
        // children and FractionallySizedBox has no intrinsic width, so the
        // light-green track never rendered. width:infinity fixes it.
        Container(
          height: 10,
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFFBFE8CC),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFF9BD9B0), width: 0.8),
          ),
          clipBehavior: Clip.antiAlias,
          child: FractionallySizedBox(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: info.progress.clamp(0, 1),
            child: const DecoratedBox(decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF34D399), UellowColors.success]),
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
            Text(m.isFree
                    ? (lang == 'ar' ? '🚚 شحن مجاني' : '🚚 FREE')
                    : (m.rate?.format() ?? '—'),
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
          onTap: () async {
            // v2.1.59 — guests got a raw AUTH error inside the coupons
            // screen; show a clean sign-in prompt instead.
            final tok = await UellowApi.instance.tokenStore.readToken();
            if (!context.mounted) return;
            if (tok == null || tok.isEmpty) {
              final ar2 = UellowApi.instance.lang == 'ar';
              showDialog(context: context, builder: (ctx) => AlertDialog(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                title: Text(ar2 ? '🎟️ كوبوناتك بانتظارك'
                                : '🎟️ Your coupons await',
                    style: const TextStyle(fontWeight: FontWeight.w900,
                        fontSize: 16)),
                content: Text(ar2
                    ? 'سجّل دخولك لعرض كوبوناتك المتاحة وتطبيقها على سلتك'
                    : 'Sign in to see and apply your available coupons',
                    style: const TextStyle(fontSize: 13)),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(ar2 ? 'لاحقاً' : 'Later'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.pushNamed(context, '/auth');
                    },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: UellowColors.yellow,
                        foregroundColor: UellowColors.darkBrown),
                    child: Text(ar2 ? 'تسجيل الدخول' : 'Sign in',
                        style: const TextStyle(
                            fontWeight: FontWeight.w900)),
                  ),
                ],
              ));
              return;
            }
            Navigator.pushNamed(context, '/coupons');
          },
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
    this.selectedTotal,
    this.onDelete,
    this.onWishlist,
    this.onCheckout,
  });
  final int count;
  final String? selectedTotal;
  final VoidCallback? onDelete;
  final VoidCallback? onWishlist;
  final VoidCallback? onCheckout;

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
        child: Column(mainAxisSize: MainAxisSize.min, children: [
        // v2.1.56 — live total of the SELECTED products only.
        if (enabled && selectedTotal != null) Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Text(ar ? 'إجمالي المحدّد ($count)' : 'Selected total ($count)',
                style: const TextStyle(fontSize: 12.5,
                    fontWeight: FontWeight.w700, color: UellowColors.muted)),
            const Spacer(),
            Text(selectedTotal!, style: const TextStyle(fontSize: 16,
                fontWeight: FontWeight.w900, color: UellowColors.darkBrown)),
          ]),
        ),
        // v2.1.65 — selective checkout: pay for the checked items only;
        // everything else stays safely in the cart.
        if (onCheckout != null || enabled) Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SizedBox(
            width: double.infinity,
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [UellowColors.yellowLight, UellowColors.yellow,
                           Color(0xFFE5A900)],
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: enabled ? [BoxShadow(
                  color: UellowColors.yellow.withValues(alpha: 0.45),
                  blurRadius: 12, offset: const Offset(0, 4),
                )] : null,
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: enabled ? onCheckout : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                      const Icon(Icons.shopping_cart_checkout,
                          size: 17, color: UellowColors.darkBrown),
                      const SizedBox(width: 8),
                      Text(
                        ar ? 'الدفع للمحدّد فقط ($count)'
                           : 'Checkout selected only ($count)',
                        style: const TextStyle(
                            color: UellowColors.darkBrown, fontSize: 13.5,
                            fontWeight: FontWeight.w900),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
        Row(children: [
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
      const SizedBox(height: 60),
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
      // v2.1.56 — coupons strip + «مختارة لك» suggestions so the empty
      // cart still sells (the reference design the user sent).
      const SizedBox(height: 24),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => Navigator.pushNamed(context, '/coupons'),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              decoration: BoxDecoration(
                color: UellowColors.darkBrown,
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [BoxShadow(color: Color(0x33412402),
                    blurRadius: 10, offset: Offset(0, 4))],
              ),
              child: Row(children: [
                const Text('🎟️', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Expanded(child: Text(
                    ar ? 'عندك كوبونات بانتظارك — لا تفوّتها!'
                       : 'You have coupons waiting — don\'t miss them!',
                    style: const TextStyle(color: Colors.white,
                        fontSize: 12.5, fontWeight: FontWeight.w800))),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [
                        UellowColors.yellowLight, UellowColors.yellow]),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(ar ? 'احصل عليها' : 'Get',
                      style: const TextStyle(color: UellowColors.darkBrown,
                          fontSize: 11.5, fontWeight: FontWeight.w900)),
                ),
              ]),
            ),
          ),
        ),
      ),
      const SizedBox(height: 18),
      const _JustForYou(),
      const SizedBox(height: 30),
    ]);
  }
}

// «مختارة لك» — live recommended products under the empty-cart state.
class _JustForYou extends StatefulWidget {
  const _JustForYou();
  @override
  State<_JustForYou> createState() => _JustForYouState();
}

class _JustForYouState extends State<_JustForYou> {
  List<UellowProductCard>? _items;

  @override
  void initState() {
    super.initState();
    UellowApi.instance.products.recommended().then((v) {
      if (mounted) setState(() => _items = v);
    }).catchError((_) {
      if (mounted) setState(() => _items = const []);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    final items = _items;
    if (items == null || items.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Row(children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(ar ? '✨ مختارة لك' : '✨ Just for you',
                style: const TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: UellowColors.darkBrown)),
          ),
          const Expanded(child: Divider()),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2, mainAxisSpacing: 8, crossAxisSpacing: 8,
            childAspectRatio: 0.585,
          ),
          itemCount: items.length.clamp(0, 6),
          itemBuilder: (_, i) => ProductCard(rich: true, product: items[i]),
        ),
      ),
    ]);
  }
}

class _ErrorPane extends StatelessWidget {
  // v2.1.66 — raw exception text replaced with the friendly "app is
  // being updated" pane (animated icon + retry).
  const _ErrorPane({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => UpdatingPane(onRetry: onRetry);
}
