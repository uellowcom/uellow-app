// =============================================================================
// TryOnScreen — virtual try-on with real Smart Fit profile, photo picker,
// product selection, generation, and post-generation actions
// (Add to cart / Ask reviewers / Share). All copy is bilingual.
//
// Backend touch points (uellow_smart_fit):
//   GET  /fit/profile                — fetch body measurements
//   POST /tryon/upload-photo         — upload source photo (base64)
//   POST /tryon/generate             — kick off generation
//   POST /tryon/status/<id>          — poll generation status
//   POST /fit/analyze                — recommend size for the picked product
// =============================================================================
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../../api/uellow_api.dart';
import '../../api/uellow_models.dart';
import '../theme/uellow_theme.dart';

class TryOnScreen extends StatefulWidget {
  const TryOnScreen({super.key, this.productId});
  final int? productId;
  @override
  State<TryOnScreen> createState() => _TryOnScreenState();
}

class _TryOnScreenState extends State<TryOnScreen> {
  // Body profile state from /fit/profile
  Map<String, dynamic>? _profile;
  bool _profileLoading = true;
  // Customer photos picked locally
  final List<File> _photos = [];
  // Selected product + variants
  UellowProductFull? _product;
  int _colorIdx = 0;
  String _selectedSize = '';
  String? _recommendedSize;
  // Generation state
  bool _generating = false;
  String? _generatedImageUrl;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    if (widget.productId != null) {
      _loadProduct(widget.productId!);
    }
  }

  Future<void> _loadProfile() async {
    try {
      final token = await UellowApi.instance.tokenStore.readToken();
      if (token == null) { setState(() => _profileLoading = false); return; }
      final r = await http.get(
        Uri.parse('${UellowApi.instance.baseUrl}/api/mobile/v2/fit/profile'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final body = jsonDecode(utf8.decode(r.bodyBytes));
      if (body is Map && body['success'] == true) {
        final d = body['data'] as Map?;
        if (d != null && d['profile'] is Map) {
          setState(() => _profile = Map<String, dynamic>.from(d['profile']));
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _profileLoading = false);
  }

  Future<void> _openEditMeasurements() async {
    final updated = await showModalBottomSheet<Map<String, dynamic>>(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MeasurementsEditor(profile: _profile ?? const {}),
    );
    if (updated != null && mounted) {
      setState(() => _profile = updated);
      if (_product != null) _runFit();
    }
  }

  Future<void> _loadProduct(int id) async {
    try {
      final p = await UellowApi.instance.products.detail(id);
      if (!mounted) return;
      setState(() {
        _product = p;
        _selectedSize = '';
      });
      _runFit();
    } catch (_) {}
  }

  Future<void> _runFit() async {
    if (_product == null) return;
    try {
      final token = await UellowApi.instance.tokenStore.readToken();
      if (token == null) return;
      final r = await http.post(
        Uri.parse('${UellowApi.instance.baseUrl}/fit/analyze'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'product_id': _product!.id}),
      );
      final body = jsonDecode(utf8.decode(r.bodyBytes));
      if (body is Map) {
        setState(() => _recommendedSize =
            (body['recommended_size'] as String?) ?? body['size'] as String?);
      }
    } catch (_) {}
  }

  Future<void> _pickProduct() async {
    final picked = await showModalBottomSheet<int>(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProductPickerSheet(),
    );
    if (picked != null) {
      _loadProduct(picked);
    }
  }

  Future<void> _addPhoto(ImageSource src) async {
    final picker = ImagePicker();
    final p = await picker.pickImage(source: src,
        maxWidth: 1280, maxHeight: 1280, imageQuality: 85);
    if (p == null || !mounted) return;
    setState(() => _photos.add(File(p.path)));
  }

  Future<void> _generate() async {
    final ar = UellowApi.instance.lang == 'ar';
    if (_product == null) {
      setState(() => _error = ar ? 'اختر منتج أولاً' : 'Pick a product first');
      return;
    }
    if (_photos.isEmpty) {
      setState(() => _error = ar ? 'حمّل صورة لك أولاً' : 'Add at least one photo');
      return;
    }
    setState(() { _generating = true; _error = null; });
    try {
      final token = await UellowApi.instance.tokenStore.readToken();
      // Upload first photo
      final bytes = await _photos.first.readAsBytes();
      final b64 = base64Encode(bytes);
      final upload = await http.post(
        Uri.parse('${UellowApi.instance.baseUrl}/tryon/upload-photo'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'image_base64': b64}),
      );
      // Best-effort: ignore upload response — backend stores into the
      // profile and the generate call will use the latest source photo.
      jsonDecode(utf8.decode(upload.bodyBytes));
      // Kick off generation
      final gen = await http.post(
        Uri.parse('${UellowApi.instance.baseUrl}/tryon/generate'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'product_id': _product!.id,
          'color_index': _colorIdx,
          'size': _selectedSize,
        }),
      );
      final genBody = jsonDecode(utf8.decode(gen.bodyBytes));
      final imageId = (genBody is Map ? genBody['image_id'] : null) as int?;
      if (imageId == null) {
        if (mounted) setState(() {
          _generating = false;
          _error = (genBody is Map ? genBody['error']?.toString() : null)
              ?? (ar ? 'فشل التوليد' : 'Generation failed');
        });
        return;
      }
      // Poll status (best effort — backend may return URL synchronously)
      for (var i = 0; i < 60; i++) {
        await Future.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        final st = await http.post(
          Uri.parse('${UellowApi.instance.baseUrl}/tryon/status/$imageId'),
          headers: {
            'Content-Type': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
          },
          body: '{}',
        );
        final stBody = jsonDecode(utf8.decode(st.bodyBytes));
        if (stBody is Map) {
          final status = stBody['status'] as String?;
          final url = (stBody['result_url'] ?? stBody['image_url']) as String?;
          if (url != null && url.isNotEmpty) {
            setState(() { _generatedImageUrl = url; _generating = false; });
            return;
          }
          if (status == 'failed') {
            setState(() {
              _generating = false;
              _error = (ar ? 'فشل التوليد' : 'Generation failed');
            });
            return;
          }
        }
      }
      if (mounted) setState(() {
        _generating = false;
        _error = (ar ? 'انتهت المهلة، حاول مرة أخرى'
                     : 'Timed out, please try again');
      });
    } catch (e) {
      if (mounted) setState(() {
        _generating = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _addToCart() async {
    if (_product == null) return;
    try {
      await UellowApi.instance.cart.add(productId: _product!.id, qty: 1);
      if (!mounted) return;
      final ar = UellowApi.instance.lang == 'ar';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ar ? 'تمت الإضافة إلى السلة' : 'Added to cart')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  void _share() {
    if (_generatedImageUrl == null) return;
    final lang = UellowApi.instance.lang;
    final name = _product?.name.current(lang) ?? '';
    Share.share(lang == 'ar'
        ? 'شاهد كيف يبدو $name علي! $_generatedImageUrl'
        : 'Check how $name looks on me! $_generatedImageUrl');
  }

  void _askReviewers() {
    Navigator.pushNamed(context, '/beena');
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return Scaffold(
      backgroundColor: UellowColors.bg,
      body: SafeArea(bottom: false, child: ListView(padding: EdgeInsets.zero, children: [
        _Header(ar: ar),
        _PreviewCard(
          generatedUrl: _generatedImageUrl,
          loading: _generating, error: _error,
          ar: ar,
        ),
        _PhotosCard(
          photos: _photos,
          onAdd: _addPhoto,
          onRemove: (i) => setState(() => _photos.removeAt(i)),
          ar: ar,
        ),
        _ProductCard(
          product: _product,
          colorIdx: _colorIdx,
          selectedSize: _selectedSize,
          recommendedSize: _recommendedSize,
          onPick: _pickProduct,
          onColor: (i) => setState(() => _colorIdx = i),
          onSize: (s) => setState(() => _selectedSize = s),
          ar: ar,
        ),
        _MeasurementsCard(
          profile: _profile, loading: _profileLoading, ar: ar,
          onEdit: _openEditMeasurements,
        ),
        _ActionsBar(
          ar: ar, generating: _generating,
          canGenerate: _product != null && _photos.isNotEmpty,
          hasGenerated: _generatedImageUrl != null,
          onGenerate: _generate, onAddToCart: _addToCart,
          onShare: _share, onAskReviewers: _askReviewers,
        ),
        const SizedBox(height: 28),
      ])),
    );
  }
}

// ─── Header ──────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.ar});
  final bool ar;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 18, 14),
      decoration: const BoxDecoration(gradient: UellowColors.heroWallet),
      child: Row(children: [
        IconButton(
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_ios_new, size: 18,
              color: UellowColors.yellowLight),
        ),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(ar ? '✨ التجربة الافتراضية' : '✨ Virtual Try-On',
              style: const TextStyle(color: UellowColors.yellowLight,
                  fontSize: 17, fontWeight: FontWeight.w900)),
          Text(ar ? 'شاهد كيف ستبدو عليك — بدعم الذكاء الاصطناعي'
                  : 'See how it looks on you — powered by AI',
              style: const TextStyle(color: Color(0xB3FFD340), fontSize: 11.5)),
        ])),
      ]),
    );
  }
}

// ─── Preview card (generated image / placeholder / loading) ───────────

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
      required this.generatedUrl, required this.loading,
      required this.error, required this.ar});
  final String? generatedUrl;
  final bool loading;
  final String? error;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.circular(16)),
        boxShadow: [BoxShadow(color: Color(0x0F000000), blurRadius: 14, offset: Offset(0, 4))],
      ),
      clipBehavior: Clip.antiAlias,
      child: AspectRatio(
        aspectRatio: 3/4,
        child: Stack(children: [
          if (generatedUrl != null) Positioned.fill(child:
              CachedNetworkImage(imageUrl: generatedUrl!, fit: BoxFit.cover))
          else Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: const Alignment(-1, -1), end: const Alignment(1, 1),
              colors: List.generate(8, (i) => i.isEven
                  ? UellowColors.yellowSoft : UellowColors.warnBg),
              stops: List.generate(8, (i) => i / 7),
              tileMode: TileMode.repeated,
            ),
          ))),
          if (loading) Positioned.fill(child: Container(
            color: Colors.black.withValues(alpha: 0.45),
            alignment: Alignment.center,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(width: 56, height: 56, child: CircularProgressIndicator(
                  color: UellowColors.yellowLight, strokeWidth: 4)),
              const SizedBox(height: 14),
              Text(ar ? 'جارٍ التوليد بالذكاء الاصطناعي…'
                      : 'AI is generating your preview…',
                  style: const TextStyle(color: UellowColors.yellowLight,
                      fontWeight: FontWeight.w800, fontSize: 13)),
            ]),
          )) else if (generatedUrl == null) Positioned.fill(child: Center(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('✨', style: TextStyle(fontSize: 56,
                  color: Colors.black.withValues(alpha: 0.6))),
              const SizedBox(height: 8),
              Text(ar ? 'ستظهر معاينتك هنا' : 'Your preview will appear here',
                  style: const TextStyle(fontSize: 12,
                      color: UellowColors.darkBrown, fontWeight: FontWeight.w700)),
            ]),
          )),
          if (generatedUrl != null) Positioned(top: 14, left: 14, child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [UellowColors.yellowLight, UellowColors.yellow]),
              borderRadius: BorderRadius.all(Radius.circular(999)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.auto_awesome, size: 12, color: UellowColors.darkBrown),
              const SizedBox(width: 4),
              Text(ar ? 'مولّد بالذكاء الاصطناعي' : 'AI Generated',
                  style: const TextStyle(color: UellowColors.darkBrown,
                      fontWeight: FontWeight.w800, fontSize: 11)),
            ]),
          )),
          if (error != null) Positioned(bottom: 0, left: 0, right: 0, child: Container(
            color: UellowColors.danger.withValues(alpha: 0.92),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Text(error!, style: const TextStyle(
                color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
          )),
        ]),
      ),
    );
  }
}

// ─── Photos picker card ──────────────────────────────────────────────

class _PhotosCard extends StatelessWidget {
  const _PhotosCard({required this.photos,
      required this.onAdd, required this.onRemove, required this.ar});
  final List<File> photos;
  final void Function(ImageSource) onAdd;
  final ValueChanged<int> onRemove;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: UellowColors.warnBg, width: 2),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.photo_library_outlined, size: 16,
              color: UellowColors.darkBrown),
          const SizedBox(width: 6),
          Expanded(child: Text(ar ? 'صورك' : 'Your photos', style: UT.h3)),
          Text('${photos.length}', style: const TextStyle(
              fontSize: 12, color: UellowColors.muted, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 6),
        Text(ar
            ? 'حمّل صورة واضحة من الأمام أو أكثر للحصول على معاينة دقيقة.'
            : 'Add one or more front-facing photos for an accurate preview.',
            style: UT.small),
        const SizedBox(height: 12),
        SizedBox(height: 92, child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: photos.length + 1,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            if (i == photos.length) {
              return _addTile(context);
            }
            return Stack(children: [
              ClipRRect(borderRadius: BorderRadius.circular(10),
                  child: Image.file(photos[i], width: 90, height: 90, fit: BoxFit.cover)),
              Positioned(top: 2, right: 2, child: GestureDetector(
                onTap: () => onRemove(i),
                child: Container(
                  width: 22, height: 22, alignment: Alignment.center,
                  decoration: const BoxDecoration(
                      color: Colors.black54, shape: BoxShape.circle),
                  child: const Icon(Icons.close, size: 13, color: Colors.white),
                ),
              )),
            ]);
          },
        )),
      ]),
    );
  }

  Widget _addTile(BuildContext context) {
    return GestureDetector(
      onTap: () => showModalBottomSheet(context: context, builder: (_) =>
          SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: Text(ar ? 'التقط صورة' : 'Take photo'),
              onTap: () { Navigator.pop(context); onAdd(ImageSource.camera); }),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(ar ? 'من المعرض' : 'From gallery'),
              onTap: () { Navigator.pop(context); onAdd(ImageSource.gallery); }),
          ]))),
      child: Container(
        width: 90, height: 90,
        decoration: BoxDecoration(
          color: UellowColors.yellowFaint,
          border: Border.all(color: UellowColors.warnBg, width: 1.5,
              strokeAlign: BorderSide.strokeAlignInside),
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.add_a_photo_outlined, size: 24,
              color: UellowColors.darkBrown),
          const SizedBox(height: 4),
          Text(ar ? 'إضافة' : 'Add',
              style: const TextStyle(fontSize: 10,
                  fontWeight: FontWeight.w800, color: UellowColors.darkBrown)),
        ]),
      ),
    );
  }
}

// ─── Product picker card ─────────────────────────────────────────────

class _ProductCard extends StatelessWidget {
  const _ProductCard({
      required this.product, required this.colorIdx,
      required this.selectedSize, required this.recommendedSize,
      required this.onPick, required this.onColor,
      required this.onSize, required this.ar});
  final UellowProductFull? product;
  final int colorIdx;
  final String selectedSize;
  final String? recommendedSize;
  final VoidCallback onPick;
  final ValueChanged<int> onColor;
  final ValueChanged<String> onSize;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    final lang = ar ? 'ar' : 'en';
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      padding: const EdgeInsets.all(14),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.checkroom_outlined, size: 16, color: UellowColors.darkBrown),
          const SizedBox(width: 6),
          Expanded(child: Text(ar ? 'المنتج' : 'Product', style: UT.h3)),
          ElevatedButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.search, size: 14),
            label: Text(product == null
                ? (ar ? 'اختر منتج' : 'Select a product')
                : (ar ? 'تغيير' : 'Change')),
            style: ElevatedButton.styleFrom(
              backgroundColor: UellowColors.yellow,
              foregroundColor: UellowColors.darkBrown,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(10))),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        if (product == null) Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(ar
              ? 'اختر منتج أولاً لاستعراض الألوان والمقاسات والمعاينة بصورتك.'
              : 'Pick a product to see its colors, sizes and try it on with your photo.',
              style: UT.subtitle),
        ) else _productBody(lang),
      ]),
    );
  }

  Widget _productBody(String lang) {
    final p = product!;
    final colorLine = p.attributes.where((a) {
      final n = a.attributeName.current(lang).toLowerCase();
      return n.contains('color') || n.contains('لون');
    }).firstOrNull;
    final sizeLine = p.attributes.where((a) {
      final n = a.attributeName.current(lang).toLowerCase();
      return n.contains('size') || n.contains('مقاس');
    }).firstOrNull;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(borderRadius: BorderRadius.circular(10),
          child: CachedNetworkImage(
            imageUrl: p.images.isNotEmpty ? p.images.first : '',
            width: 64, height: 64, fit: BoxFit.cover,
            errorWidget: (_, __, ___) => Container(width: 64, height: 64,
              color: UellowColors.yellowSoft,
              alignment: Alignment.center,
              child: const Icon(Icons.image_outlined, color: UellowColors.muted)))),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(p.name.current(lang), maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800,
                  fontSize: 13, color: UellowColors.ink)),
          const SizedBox(height: 4),
          Text(p.price.format(), style: const TextStyle(fontSize: 13,
              fontWeight: FontWeight.w900, color: UellowColors.darkBrown)),
        ])),
      ]),
      if (colorLine != null) ...[
        const SizedBox(height: 14),
        Text(ar ? 'الألوان' : 'Colors',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                color: UellowColors.muted, letterSpacing: 0.5)),
        const SizedBox(height: 6),
        SizedBox(height: 60, child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: colorLine.values.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final v = colorLine.values[i];
            final on = i == colorIdx;
            return GestureDetector(
              onTap: () => onColor(i),
              child: Container(
                width: 50,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  border: Border.all(
                      color: on ? UellowColors.yellow : Colors.transparent, width: 2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(borderRadius: BorderRadius.circular(6),
                  child: (v.image != null && v.image!.isNotEmpty)
                    ? CachedNetworkImage(imageUrl: v.image!,
                        width: 44, height: 44, fit: BoxFit.cover)
                    : Container(width: 44, height: 44,
                        color: _parseColor(v.htmlColor))),
              ),
            );
          },
        )),
      ],
      if (sizeLine != null) ...[
        const SizedBox(height: 12),
        Row(children: [
          Text(ar ? 'المقاسات' : 'Sizes',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                  color: UellowColors.muted, letterSpacing: 0.5)),
          if (recommendedSize != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: UellowColors.successBg,
                  borderRadius: BorderRadius.circular(4)),
              child: Text(ar
                  ? 'الموصى به: $recommendedSize'
                  : 'Recommended: $recommendedSize',
                  style: const TextStyle(color: UellowColors.successDk,
                      fontSize: 10, fontWeight: FontWeight.w900)),
            ),
          ],
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final v in sizeLine.values)
            _sizeChip(v.name.current(lang)),
        ]),
      ],
    ]);
  }

  Widget _sizeChip(String s) {
    final on = s == selectedSize;
    final rec = recommendedSize == s;
    return GestureDetector(
      onTap: () => onSize(s),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: on ? UellowColors.darkBrown : Colors.white,
          border: Border.all(color: on ? UellowColors.darkBrown
              : (rec ? UellowColors.success : UellowColors.border),
              width: rec ? 1.8 : 1.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(s, style: TextStyle(
          fontWeight: FontWeight.w800, fontSize: 12,
          color: on ? UellowColors.yellowLight
              : (rec ? UellowColors.successDk : UellowColors.text))),
      ),
    );
  }

  static Color _parseColor(String hex) {
    final h = hex.replaceAll('#', '');
    if (h.length == 6) {
      try { return Color(int.parse('ff$h', radix: 16)); } catch (_) {}
    }
    return UellowColors.darkBrown;
  }
}

// ─── Measurements card (live profile from /fit/profile) ──────────────

class _MeasurementsCard extends StatelessWidget {
  const _MeasurementsCard({required this.profile,
      required this.loading, required this.ar, required this.onEdit});
  final Map<String, dynamic>? profile;
  final bool loading;
  final bool ar;
  final VoidCallback onEdit;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      padding: const EdgeInsets.all(14),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.straighten, size: 16, color: UellowColors.darkBrown),
          const SizedBox(width: 6),
          Expanded(child: Text(ar ? 'مقاساتك' : 'Your measurements',
              style: UT.h3)),
          TextButton.icon(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 14),
            label: Text(ar ? 'تعديل' : 'Edit',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            style: TextButton.styleFrom(foregroundColor: UellowColors.darkBrown),
          ),
        ]),
        const SizedBox(height: 6),
        if (loading) const Padding(padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator(
                color: UellowColors.darkBrown)))
        else if (profile == null) Text(ar
            ? 'سجّل الدخول وحدّث ملف القياسات الخاص بك للحصول على توصيات أدق.'
            : 'Sign in and complete your body profile for accurate recommendations.',
            style: UT.subtitle)
        else Wrap(spacing: 12, runSpacing: 10, children: _rows(ar)),
      ]),
    );
  }

  List<Widget> _rows(bool ar) {
    final p = profile!;
    final pairs = <(String, String, String)>[];
    void add(String key, String en, String arl) {
      final v = p[key];
      if (v == null || (v is num && v == 0) || v == false || v == '') return;
      pairs.add((ar ? arl : en, '$v', _unitFor(key)));
    }
    add('height',     'Height',       'الطول');
    add('weight',     'Weight',       'الوزن');
    add('chest',      'Chest',        'الصدر');
    add('waist',      'Waist',        'الخصر');
    add('shoulder',   'Shoulder',     'الأكتاف');
    add('hip',        'Hip',          'الورك');
    add('arm_length', 'Arm length',   'طول الذراع');
    add('inseam',     'Inseam',       'الساق الداخلية');
    add('thigh',      'Thigh',        'الفخذ');
    add('shoe_size_eu', 'Shoe (EU)',  'مقاس الحذاء EU');
    add('shoe_size_us', 'Shoe (US)',  'مقاس الحذاء US');
    add('body_type',    'Body type',  'نوع الجسم');
    add('preferred_fit','Preferred fit', 'القَصّة المفضلة');
    if (pairs.isEmpty) {
      return [Text(ar ? 'لم تتم إضافة قياسات بعد.' : 'No measurements yet.',
          style: UT.subtitle)];
    }
    return pairs.map((t) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: UellowColors.yellowFaint,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: UellowColors.warnBg),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('${t.$1} ', style: const TextStyle(fontSize: 10.5,
            fontWeight: FontWeight.w700, color: UellowColors.muted)),
        Text(t.$2, style: const TextStyle(fontWeight: FontWeight.w900,
            color: UellowColors.darkBrown)),
        if (t.$3.isNotEmpty) Padding(padding: const EdgeInsets.only(left: 3),
            child: Text(t.$3, style: const TextStyle(fontSize: 10,
                color: UellowColors.muted, fontWeight: FontWeight.w700))),
      ]),
    )).toList();
  }

  String _unitFor(String key) {
    if (key.startsWith('shoe')) return '';
    if (key == 'weight') return 'kg';
    if (['body_type', 'preferred_fit', 'gender', 'age_range'].contains(key)) return '';
    return 'cm';
  }
}

// ─── Bottom actions bar ──────────────────────────────────────────────

class _ActionsBar extends StatelessWidget {
  const _ActionsBar({
      required this.ar, required this.generating,
      required this.canGenerate, required this.hasGenerated,
      required this.onGenerate, required this.onAddToCart,
      required this.onShare, required this.onAskReviewers});
  final bool ar, generating, canGenerate, hasGenerated;
  final VoidCallback onGenerate, onAddToCart, onShare, onAskReviewers;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 14, 14, 0),
      padding: const EdgeInsets.all(14),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
      child: Column(children: [
        SizedBox(width: double.infinity, child: ElevatedButton.icon(
          onPressed: (!canGenerate || generating) ? null : onGenerate,
          icon: generating
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2,
                      color: UellowColors.darkBrown))
              : const Icon(Icons.auto_awesome, size: 18),
          label: Text(generating
              ? (ar ? 'جارٍ التوليد…' : 'Generating…')
              : (ar ? 'توليد المعاينة' : 'Generate preview'),
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          style: ElevatedButton.styleFrom(
            backgroundColor: UellowColors.yellow,
            foregroundColor: UellowColors.darkBrown,
            disabledBackgroundColor: UellowColors.yellowSoft,
            disabledForegroundColor: UellowColors.muted,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(14))),
            elevation: hasGenerated ? 0 : 2,
          ),
        )),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: OutlinedButton.icon(
            onPressed: hasGenerated ? onShare : null,
            icon: const Icon(Icons.share_outlined, size: 16),
            label: Text(ar ? 'مشاركة' : 'Share',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            style: OutlinedButton.styleFrom(
              foregroundColor: UellowColors.darkBrown,
              side: const BorderSide(color: UellowColors.border, width: 1.5),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12))),
            ),
          )),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(
            onPressed: hasGenerated ? onAskReviewers : null,
            icon: const Icon(Icons.forum_outlined, size: 16),
            label: Text(ar ? 'اسأل المراجعين' : 'Ask reviewers',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            style: OutlinedButton.styleFrom(
              foregroundColor: UellowColors.darkBrown,
              side: const BorderSide(color: UellowColors.border, width: 1.5),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12))),
            ),
          )),
          const SizedBox(width: 8),
          Expanded(child: ElevatedButton.icon(
            onPressed: canGenerate ? onAddToCart : null,
            icon: const Icon(Icons.add_shopping_cart, size: 16),
            label: Text(ar ? 'أضف للسلة' : 'Add to cart',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            style: ElevatedButton.styleFrom(
              backgroundColor: UellowColors.darkBrown,
              foregroundColor: UellowColors.yellowLight,
              disabledBackgroundColor: const Color(0x55412402),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12))),
            ),
          )),
        ]),
      ]),
    );
  }
}

// ─── Product picker sheet (search products) ──────────────────────────

class _ProductPickerSheet extends StatefulWidget {
  @override
  State<_ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<_ProductPickerSheet> {
  final _ctrl = TextEditingController();
  Future<List<UellowProductCard>>? _future;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _future = _search('');
  }

  Future<List<UellowProductCard>> _search(String q) async {
    if (q.isEmpty) {
      final page = await UellowApi.instance.products.list(perPage: 20);
      return page.items;
    }
    final res = await UellowApi.instance.search.search(q, perPage: 20);
    return res.products;
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return DraggableScrollableSheet(
      expand: false, initialChildSize: 0.85, minChildSize: 0.5, maxChildSize: 0.95,
      builder: (_, scroll) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(children: [
          Container(width: 40, height: 4, margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(color: UellowColors.border,
                  borderRadius: BorderRadius.circular(2))),
          Padding(padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
              child: Row(children: [
                Expanded(child: Text(ar ? 'اختر منتج' : 'Select a product',
                    style: UT.h2)),
                IconButton(onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: UellowColors.muted)),
              ])),
          Padding(padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
              child: TextField(
                controller: _ctrl,
                onChanged: (v) {
                  setState(() {
                    _q = v;
                    _future = _search(v);
                  });
                },
                decoration: InputDecoration(
                  hintText: ar ? 'ابحث عن منتج…' : 'Search products…',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                ),
              )),
          Expanded(child: FutureBuilder<List<UellowProductCard>>(
            future: _future,
            builder: (_, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator(
                    color: UellowColors.darkBrown));
              }
              final items = snap.data ?? const <UellowProductCard>[];
              if (items.isEmpty) {
                return Padding(padding: const EdgeInsets.all(40),
                    child: Center(child: Text(ar
                        ? 'لا توجد نتائج' : 'No results found',
                        style: UT.subtitle)));
              }
              final lang = ar ? 'ar' : 'en';
              return ListView.separated(
                controller: scroll,
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(
                    height: 1, color: UellowColors.border),
                itemBuilder: (_, i) {
                  final p = items[i];
                  return ListTile(
                    leading: ClipRRect(borderRadius: BorderRadius.circular(8),
                        child: CachedNetworkImage(imageUrl: p.image,
                            width: 50, height: 50, fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Container(width: 50, height: 50,
                                color: UellowColors.yellowSoft))),
                    title: Text(p.name.current(lang),
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700,
                            color: UellowColors.ink, fontSize: 13)),
                    subtitle: Text(p.price.format(),
                        style: const TextStyle(fontWeight: FontWeight.w800,
                            color: UellowColors.darkBrown)),
                    onTap: () => Navigator.pop(context, p.id),
                  );
                },
              );
            },
          )),
        ]),
      ),
    );
  }
}

// ─── Measurements editor sheet ───────────────────────────────────────

class _MeasurementsEditor extends StatefulWidget {
  const _MeasurementsEditor({required this.profile});
  final Map<String, dynamic> profile;
  @override
  State<_MeasurementsEditor> createState() => _MeasurementsEditorState();
}

class _MeasurementsEditorState extends State<_MeasurementsEditor> {
  late final Map<String, TextEditingController> _ctrls;
  String? _gender;
  String? _bodyType;
  String? _preferredFit;
  bool _busy = false;
  String? _error;

  static const _numFields = [
    ('height',       'cm'),
    ('weight',       'kg'),
    ('shoulder',     'cm'),
    ('chest',        'cm'),
    ('waist',        'cm'),
    ('hip',          'cm'),
    ('arm_length',   'cm'),
    ('inseam',       'cm'),
    ('thigh',        'cm'),
    ('shoe_size_eu', 'EU'),
    ('shoe_size_us', 'US'),
  ];

  @override
  void initState() {
    super.initState();
    _ctrls = { for (final f in _numFields) f.$1: TextEditingController(
      text: _initial(widget.profile[f.$1])) };
    _gender       = widget.profile['gender']?.toString();
    _bodyType     = widget.profile['body_type']?.toString();
    _preferredFit = widget.profile['preferred_fit']?.toString();
  }

  String _initial(dynamic v) {
    if (v == null || v == false || v == 0 || v == 0.0) return '';
    return v.toString();
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) { c.dispose(); }
    super.dispose();
  }

  Future<void> _save() async {
    final ar = UellowApi.instance.lang == 'ar';
    setState(() { _busy = true; _error = null; });
    try {
      final body = <String, dynamic>{};
      for (final e in _ctrls.entries) {
        final v = e.value.text.trim();
        if (v.isNotEmpty) {
          final n = double.tryParse(v);
          if (n != null) body[e.key] = n;
        }
      }
      if ((_gender ?? '').isNotEmpty)       body['gender']        = _gender;
      if ((_bodyType ?? '').isNotEmpty)     body['body_type']     = _bodyType;
      if ((_preferredFit ?? '').isNotEmpty) body['preferred_fit'] = _preferredFit;

      final token = await UellowApi.instance.tokenStore.readToken();
      final r = await http.post(
        Uri.parse('${UellowApi.instance.baseUrl}/api/mobile/v2/fit/profile/save'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (j['success'] == true) {
        final d = j['data'] as Map<String, dynamic>;
        final prof = Map<String, dynamic>.from(d['profile'] as Map);
        if (!mounted) return;
        Navigator.pop(context, prof);
      } else {
        setState(() {
          _busy = false;
          _error = (j['error'] ?? (ar ? 'فشل الحفظ' : 'Failed to save')).toString();
        });
      }
    } catch (e) {
      if (mounted) setState(() { _busy = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    final labels = {
      'height':       (en: 'Height',     ar: 'الطول'),
      'weight':       (en: 'Weight',     ar: 'الوزن'),
      'shoulder':     (en: 'Shoulder',   ar: 'الأكتاف'),
      'chest':        (en: 'Chest',      ar: 'الصدر'),
      'waist':        (en: 'Waist',      ar: 'الخصر'),
      'hip':          (en: 'Hip',        ar: 'الورك'),
      'arm_length':   (en: 'Arm length', ar: 'طول الذراع'),
      'inseam':       (en: 'Inseam',     ar: 'الساق الداخلية'),
      'thigh':        (en: 'Thigh',      ar: 'الفخذ'),
      'shoe_size_eu': (en: 'Shoe (EU)',  ar: 'الحذاء EU'),
      'shoe_size_us': (en: 'Shoe (US)',  ar: 'الحذاء US'),
    };
    return DraggableScrollableSheet(
      expand: false, initialChildSize: 0.92, minChildSize: 0.5, maxChildSize: 0.96,
      builder: (_, scroll) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(children: [
          Container(width: 40, height: 4, margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(color: UellowColors.border,
                  borderRadius: BorderRadius.circular(2))),
          Padding(padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
              child: Row(children: [
                Expanded(child: Text(ar ? 'تعديل مقاساتي' : 'My measurements',
                    style: UT.h2)),
                IconButton(onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: UellowColors.muted)),
              ])),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Text(ar
                ? 'املأ ما تعرفه — كلما زادت البيانات كانت توصيات المقاس أدق.'
                : 'Fill what you know — the more accurate, the better the size recommendations.',
                style: UT.subtitle)),
          const SizedBox(height: 12),
          Expanded(child: ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            children: [
              _SegRow(
                label: ar ? 'الجنس' : 'Gender',
                value: _gender,
                options: [('male', ar ? 'ذكر' : 'Male'),
                          ('female', ar ? 'أنثى' : 'Female')],
                onChanged: (v) => setState(() => _gender = v),
              ),
              _SegRow(
                label: ar ? 'نوع الجسم' : 'Body type',
                value: _bodyType,
                options: ar ? const [
                  ('slim', 'نحيف'), ('athletic', 'رياضي'),
                  ('average', 'متوسط'), ('plus', 'ممتلئ'),
                ] : const [
                  ('slim', 'Slim'), ('athletic', 'Athletic'),
                  ('average', 'Average'), ('plus', 'Plus'),
                ],
                onChanged: (v) => setState(() => _bodyType = v),
              ),
              _SegRow(
                label: ar ? 'القَصّة المفضلة' : 'Preferred fit',
                value: _preferredFit,
                options: ar ? const [
                  ('tight', 'ضيق'), ('regular', 'عادي'),
                  ('loose', 'فضفاض'),
                ] : const [
                  ('tight', 'Tight'), ('regular', 'Regular'),
                  ('loose', 'Loose'),
                ],
                onChanged: (v) => setState(() => _preferredFit = v),
              ),
              const SizedBox(height: 8),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                childAspectRatio: 3.2,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                children: [
                  for (final f in _numFields) _NumField(
                    label: ar ? labels[f.$1]!.ar : labels[f.$1]!.en,
                    unit: f.$2,
                    controller: _ctrls[f.$1]!,
                  ),
                ],
              ),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: UellowColors.dangerBg,
                        borderRadius: BorderRadius.circular(8)),
                    child: Text(_error!, style: const TextStyle(
                        color: UellowColors.dangerDk,
                        fontWeight: FontWeight.w800)),
                  )),
              const SizedBox(height: 14),
              SizedBox(width: double.infinity, child: ElevatedButton.icon(
                onPressed: _busy ? null : _save,
                icon: _busy
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2,
                            color: UellowColors.darkBrown))
                    : const Icon(Icons.save, size: 18),
                label: Text(_busy
                    ? (ar ? 'جارٍ الحفظ…' : 'Saving…')
                    : (ar ? 'حفظ المقاسات' : 'Save measurements'),
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: UellowColors.yellow,
                  foregroundColor: UellowColors.darkBrown,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(14))),
                ),
              )),
            ],
          )),
        ]),
      ),
    );
  }
}

class _NumField extends StatelessWidget {
  const _NumField({required this.label, required this.unit,
      required this.controller});
  final String label, unit;
  final TextEditingController controller;
  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        suffixText: unit,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      ),
    );
  }
}

class _SegRow extends StatelessWidget {
  const _SegRow({required this.label, required this.value,
      required this.options, required this.onChanged});
  final String label;
  final String? value;
  final List<(String, String)> options;
  final ValueChanged<String?> onChanged;
  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 12,
            fontWeight: FontWeight.w800, color: UellowColors.muted,
            letterSpacing: 0.5)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: options.map((o) {
          final on = value == o.$1;
          return GestureDetector(
            onTap: () => onChanged(o.$1),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: on ? UellowColors.darkBrown : Colors.white,
                border: Border.all(color: on ? UellowColors.darkBrown : UellowColors.border, width: 1.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(o.$2, style: TextStyle(fontWeight: FontWeight.w800,
                  fontSize: 12, color: on ? UellowColors.yellowLight : UellowColors.text)),
            ),
          );
        }).toList()),
      ]),
    );
  }
}

