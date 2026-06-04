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
import 'package:shared_preferences/shared_preferences.dart';

import '../../api/uellow_api.dart';
import '../../api/uellow_models.dart';
import '../router/uellow_router.dart';
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
    _restorePhotos();   // v2.1.50 — saved photos come back automatically
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
    // v2.1.50 — persist: local paths survive restarts AND the photo is
    // saved on the body profile server-side (uploaded ONCE).
    _persistPhotos();
    _uploadPhotoToProfile(File(p.path));
  }

  Future<void> _persistPhotos() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
          'tryon_photos_v1', _photos.map((f) => f.path).toList());
    } catch (_) {}
  }

  Future<void> _restorePhotos() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final paths = prefs.getStringList('tryon_photos_v1') ?? const [];
      final files = paths.map(File.new).where((f) => f.existsSync()).toList();
      if (files.isNotEmpty && mounted) {
        setState(() => _photos.addAll(files));
      } else {
        // Nothing local — maybe saved on the profile from another
        // session/device: pull it back down once.
        final token = await UellowApi.instance.tokenStore.readToken();
        if (token == null) return;
        final r = await http.get(
          Uri.parse('${UellowApi.instance.baseUrl}/api/mobile/v2/tryon/photo'),
          headers: {'Accept': 'application/json',
                    'Authorization': 'Bearer $token'},
        ).timeout(const Duration(seconds: 8));
        final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
        final b64 = (j['data']?['photo'] as String?) ?? '';
        if (b64.isNotEmpty && mounted) {
          final dir = await SharedPreferences.getInstance();   // path anchor
          final f = File(
              '${Directory.systemTemp.path}/uellow_tryon_profile.jpg');
          await f.writeAsBytes(base64Decode(b64));
          if (mounted) setState(() => _photos.add(f));
          await dir.setStringList('tryon_photos_v1', [f.path]);
        }
      }
    } catch (_) {}
  }

  Future<void> _uploadPhotoToProfile(File f) async {
    try {
      final token = await UellowApi.instance.tokenStore.readToken();
      if (token == null) return;
      final b64 = base64Encode(await f.readAsBytes());
      await http.post(
        Uri.parse('${UellowApi.instance.baseUrl}/api/mobile/v2/tryon/photo'),
        headers: {'Content-Type': 'application/json',
                  'Authorization': 'Bearer $token'},
        body: jsonEncode({'image_base64': b64}),
      ).timeout(const Duration(seconds: 20));
    } catch (_) {/* best effort */}
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
      // v2.1.50 — proper mobile endpoint (Bearer auth). The old /tryon/*
      // session routes always failed from the app.
      final gen = await http.post(
        Uri.parse('${UellowApi.instance.baseUrl}/api/mobile/v2/tryon/generate'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'product_id': _product!.id,
          'color_index': _colorIdx,
          'size': _selectedSize,
        }),
      ).timeout(const Duration(seconds: 25));
      final j = jsonDecode(utf8.decode(gen.bodyBytes)) as Map<String, dynamic>;
      final data = (j['data'] as Map?)?.cast<String, dynamic>() ?? {};
      if (data['available'] == false) {
        // Provider not configured yet — friendly coming-soon, not an error.
        if (mounted) {
          setState(() => _generating = false);
          _showComingSoon();
        }
        return;
      }
      final url = (data['result_url'] ?? data['image_url'] ?? '').toString();
      if (url.isNotEmpty) {
        if (mounted) {
          setState(() { _generatedImageUrl = url; _generating = false; });
        }
        return;
      }
      // v2.1.52 — async generation: poll the status endpoint until the
      // image is ready (~2s interval, 2.5 min budget).
      final imageId = (data['image_id'] as num?)?.toInt();
      if (data['success'] == true && imageId != null) {
        for (var i = 0; i < 75; i++) {
          await Future.delayed(const Duration(seconds: 2));
          if (!mounted) return;
          try {
            final st = await http.get(
              Uri.parse('${UellowApi.instance.baseUrl}'
                  '/api/mobile/v2/tryon/status/$imageId'),
              headers: {'Accept': 'application/json',
                        if (token != null) 'Authorization': 'Bearer $token'},
            ).timeout(const Duration(seconds: 10));
            final sj = jsonDecode(utf8.decode(st.bodyBytes))
                as Map<String, dynamic>;
            final sd = (sj['data'] as Map?)?.cast<String, dynamic>() ?? {};
            final status = (sd['status'] ?? '').toString();
            final rUrl = (sd['result_url'] ?? '').toString();
            if (status == 'done' && rUrl.isNotEmpty) {
              setState(() {
                _generatedImageUrl = rUrl; _generating = false;
              });
              return;
            }
            if (status == 'failed') {
              setState(() {
                _generating = false;
                _error = ar ? 'فشل التوليد، جرّب صورة أوضح'
                            : 'Generation failed — try a clearer photo';
              });
              return;
            }
          } catch (_) {}
        }
        if (mounted) {
          setState(() {
            _generating = false;
            _error = ar ? 'انتهت المهلة، حاول مرة أخرى'
                        : 'Timed out, please try again';
          });
        }
        return;
      }
      if (mounted) {
        final err = (data['error'] ?? '').toString();
        // friendly messages for the engine's known rejections
        final msgs = {
          'no_photo': ar ? 'أضف صورتك أولاً' : 'Add your photo first',
          'price_below_min': ar ? 'هذا المنتج غير مؤهل للتجربة (سعر منخفض)'
                                : 'Product not eligible (price too low)',
          'category_not_eligible': ar ? 'هذه الفئة غير مدعومة للتجربة بعد'
                                      : 'This category is not supported yet',
          'product_image_missing': ar ? 'لا توجد صورة للمنتج'
                                      : 'Product has no image',
        };
        setState(() {
          _generating = false;
          _error = msgs[err]
              ?? (ar ? 'فشل التوليد، حاول لاحقاً' : 'Generation failed, try later');
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _generating = false);
        _showComingSoon();
      }
    }
  }

  // v2.1.50 — premium "coming soon" sheet instead of a raw error.
  void _showComingSoon() {
    final ar = UellowApi.instance.lang == 'ar';
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                  colors: [Color(0xFFFFD340), Color(0xFFE8A800)]),
              shape: BoxShape.circle,
            ),
            child: const Text('🪄', style: TextStyle(fontSize: 34)),
          ),
          const SizedBox(height: 14),
          Text(ar ? 'التجربة الافتراضية… قريباً جداً!'
                  : 'Virtual try-on… coming very soon!',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900,
                  color: UellowColors.darkBrown)),
          const SizedBox(height: 8),
          Text(ar
                  ? 'نجهّز محرك الذكاء الاصطناعي الذي سيُلبسك المنتج في ثوانٍ. صورتك ومقاساتك محفوظة وجاهزة — سنبلغك فور الإطلاق 🚀'
                  : 'We are finalizing the AI engine that dresses you in seconds. Your photo and measurements are saved and ready — we will notify you at launch 🚀',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, height: 1.6,
                  color: UellowColors.muted)),
          const SizedBox(height: 18),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: UellowColors.darkBrown,
              foregroundColor: UellowColors.yellowLight,
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
            child: Text(ar ? 'حسناً، بانتظارها!' : 'Great — can\'t wait!',
                style: const TextStyle(fontWeight: FontWeight.w900)),
          )),
        ]),
      ),
    );
  }

  Future<void> _addToCart() async {
    final ar = UellowApi.instance.lang == 'ar';
    if (_product == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ar ? 'اختر منتجاً أولاً' : 'Pick a product first')));
      return;
    }
    // v2.1.50 — size-aware: if the product has sizes and none is picked,
    // nudge (and auto-pick the recommended one when we have it).
    final sizes = _product!.attributes
        .where((l) => l.attributeName.en.toLowerCase().contains('size')
            || l.attributeName.ar.contains('مقاس'))
        .expand((l) => l.values)
        .toList();
    if (sizes.isNotEmpty && _selectedSize.isEmpty) {
      if ((_recommendedSize ?? '').isNotEmpty) {
        setState(() => _selectedSize = _recommendedSize!);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(ar ? 'اختر المقاس أولاً' : 'Pick a size first')));
        return;
      }
    }
    try {
      await UellowApi.instance.cart.add(productId: _product!.id, qty: 1);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ar
            ? 'تمت الإضافة إلى السلة${_selectedSize.isNotEmpty ? " · مقاس $_selectedSize" : ""}'
            : 'Added to cart${_selectedSize.isNotEmpty ? " · size $_selectedSize" : ""}'),
        action: SnackBarAction(
          label: ar ? 'عرض السلة' : 'View cart',
          textColor: UellowColors.yellow,
          onPressed: () => Navigator.pushNamed(context, Routes.cart),
        ),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  void _share() {
    final lang = UellowApi.instance.lang;
    final ar = lang == 'ar';
    final name = _product?.name.current(lang) ?? '';
    // v2.1.50 — share works at every stage: generated image → product
    // link → the app itself.
    if (_generatedImageUrl != null) {
      Share.share(ar
          ? 'شاهد كيف يبدو $name علي! $_generatedImageUrl'
          : 'Check how $name looks on me! $_generatedImageUrl');
    } else if (_product != null) {
      final slug = _product!.slug.isNotEmpty
          ? _product!.slug : 'p-${_product!.id}';
      Share.share(ar
          ? '$name — شاهده على يلو 🛍️\n${UellowApi.instance.baseUrl}/shop/$slug'
          : '$name — check it on Uellow 🛍️\n${UellowApi.instance.baseUrl}/shop/$slug');
    } else {
      Share.share(ar
          ? 'جرّب تطبيق يلو — تسوق أذكى 🛍️\n${UellowApi.instance.baseUrl}'
          : 'Try the Uellow app — smarter shopping 🛍️\n${UellowApi.instance.baseUrl}');
    }
  }

  // v2.1.50 — real specialists flow (was just a redirect to Beena):
  // lists online reviewers; Ask sends a review.request for the picked
  // product with an automatic question.
  Future<void> _askReviewers() async {
    final ar = UellowApi.instance.lang == 'ar';
    if (_product == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ar ? 'اختر منتجاً أولاً' : 'Pick a product first')));
      return;
    }
    List<Map<String, dynamic>> revs = const [];
    try {
      final r = await http.get(
        Uri.parse('${UellowApi.instance.baseUrl}/api/mobile/v2/reviewers/online'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 8));
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (j['success'] == true) {
        revs = ((j['data'] as List?) ?? const [])
            .cast<Map>().map((m) => m.cast<String, dynamic>()).toList();
      }
    } catch (_) {}
    if (!mounted) return;
    if (revs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          ar ? 'لا يوجد متخصصون متاحون حالياً' : 'No specialists online right now')));
      return;
    }
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.65,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 4),
            child: Row(children: [
              Text(ar ? '🎓 اسأل متخصصاً' : '🎓 Ask a specialist', style: UT.h2),
              const Spacer(),
              IconButton(icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(ctx)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
            child: Text(ar
                ? 'سيفحص المتخصص المنتج ويرد عليك برأي موثوق قبل الشراء'
                : 'A specialist reviews the product and replies with a trusted opinion',
                style: const TextStyle(fontSize: 11.5,
                    color: UellowColors.muted, height: 1.4)),
          ),
          Expanded(child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            itemCount: revs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final rv = revs[i];
              return Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  border: Border.all(color: UellowColors.border),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  Stack(children: [
                    CircleAvatar(radius: 20,
                        backgroundColor: const Color(0xFFE3EAF6),
                        backgroundImage: rv['avatar'] != null
                            ? CachedNetworkImageProvider(
                                rv['avatar'].toString()) : null,
                        child: rv['avatar'] == null
                            ? const Icon(Icons.person,
                                color: Color(0xFF1565C0)) : null),
                    if (rv['online'] == true) Positioned(
                        right: 0, bottom: 0,
                        child: Container(width: 11, height: 11,
                            decoration: BoxDecoration(
                              color: UellowColors.success,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: Colors.white, width: 2),
                            ))),
                  ]),
                  const SizedBox(width: 10),
                  Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text((rv['name'] ?? '').toString(),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800,
                            fontSize: 12.5)),
                    Text((rv['specialty'] ?? '').toString(),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10,
                            color: UellowColors.muted)),
                  ])),
                  ElevatedButton(
                    onPressed: () => _sendReviewerRequest(ctx, rv),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1565C0),
                      foregroundColor: Colors.white, elevation: 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 13, vertical: 7),
                    ),
                    child: Text(ar ? 'اطلب رأيه' : 'Ask', style:
                        const TextStyle(fontSize: 11,
                            fontWeight: FontWeight.w900)),
                  ),
                ]),
              );
            },
          )),
        ]),
      ),
    );
  }

  Future<void> _sendReviewerRequest(
      BuildContext ctx, Map<String, dynamic> rv) async {
    final ar = UellowApi.instance.lang == 'ar';
    final token = await UellowApi.instance.tokenStore.readToken();
    if (token == null || token.isEmpty) {
      if (ctx.mounted) Navigator.pop(ctx);
      if (mounted) Navigator.pushNamed(context, '/auth');
      return;
    }
    try {
      final r = await http.post(
        Uri.parse('${UellowApi.instance.baseUrl}/api/mobile/v2/reviewers/request'),
        headers: {'Content-Type': 'application/json',
                  'Authorization': 'Bearer $token'},
        body: jsonEncode({
          'reviewer_id': rv['id'],
          'product_id': _product!.id,
          'session_type': 'written',
          'note': ar
              ? 'أفكر بشراء هذا المنتج — ما رأيك به من ناحية الجودة والمقاس؟'
              : 'I am considering this product — your opinion on quality and sizing?',
        }),
      ).timeout(const Duration(seconds: 10));
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (ctx.mounted) Navigator.pop(ctx);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
            j['success'] == true
                ? (ar ? '✅ أُرسل طلبك — سيصلك رد المتخصص قريباً'
                      : '✅ Request sent — the specialist will reply soon')
                : (ar ? 'تعذر إرسال الطلب' : 'Could not send'))));
      }
    } catch (_) {}
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
        // v2.1.54 — specialist replies & votes for MY requests.
        _ReviewerRepliesCard(ar: ar),
        // v2.1.50 — measurements moved to the BOTTOM per request.
        _MeasurementsCard(
          profile: _profile, loading: _profileLoading, ar: ar,
          onEdit: _openEditMeasurements,
        ),
        // v2.1.54 — measurement history (what changed, when).
        if (((_profile?['history'] as List?) ?? const []).isNotEmpty)
          _MeasureHistoryCard(
              history: ((_profile?['history'] as List?) ?? const [])
                  .cast<Map>()
                  .map((m) => m.cast<String, dynamic>())
                  .toList(),
              ar: ar),
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

  static const _metrics = [
    ('height',      Icons.height,                  'Height',     'الطول',          'cm'),
    ('weight',      Icons.monitor_weight_outlined, 'Weight',     'الوزن',          'kg'),
    ('chest',       Icons.accessibility_new,       'Chest',      'الصدر',          'cm'),
    ('waist',       Icons.straighten,              'Waist',      'الخصر',          'cm'),
    ('shoulder',    Icons.open_in_full,            'Shoulder',   'الأكتاف',        'cm'),
    ('hip',         Icons.airline_seat_recline_normal, 'Hip',    'الورك',          'cm'),
    ('arm_length',  Icons.pan_tool_alt_outlined,   'Arm',        'طول الذراع',     'cm'),
    ('inseam',      Icons.airline_seat_legroom_extra, 'Inseam',  'الساق الداخلية', 'cm'),
    ('thigh',       Icons.linear_scale,            'Thigh',      'الفخذ',          'cm'),
    ('shoe_size_eu',Icons.do_not_step_outlined,    'Shoe EU',    'الحذاء EU',      ''),
  ];

  bool _has(dynamic v) =>
      v != null && v != false && v != '' && !(v is num && v == 0);

  String _fmtNum(dynamic v) {
    if (v is num) {
      return v == v.roundToDouble()
          ? v.toInt().toString() : v.toStringAsFixed(1);
    }
    return '$v';
  }

  @override
  Widget build(BuildContext context) {
    final pct = ((profile?['completion_pct'] as num?)?.toDouble() ?? 0)
        .clamp(0, 100).toDouble();
    final filled = profile == null ? 0 : _metrics
        .where((m) => _has(profile![m.$1])).length;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1ECE0)),
        boxShadow: const [BoxShadow(color: Color(0x0A000000),
            blurRadius: 10, offset: Offset(0, 3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── calm header: icon · title/subtitle · completion ring ──
        Row(children: [
          Container(
            width: 38, height: 38, alignment: Alignment.center,
            decoration: const BoxDecoration(
                color: Color(0xFFF7F3E8), shape: BoxShape.circle),
            child: const Icon(Icons.straighten,
                size: 18, color: UellowColors.darkBrown),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(ar ? 'مقاساتي' : 'My measurements',
                style: const TextStyle(fontSize: 15,
                    fontWeight: FontWeight.w900, color: UellowColors.ink)),
            Text(ar
                    ? 'محفوظة في حسابك وتُستخدم لاقتراح المقاس المناسب'
                    : 'Saved to your account — used for size advice',
                style: const TextStyle(fontSize: 10.5,
                    color: UellowColors.muted, height: 1.3)),
          ])),
          if (profile != null) SizedBox(
            width: 44, height: 44,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox(width: 44, height: 44,
                  child: CircularProgressIndicator(
                    value: pct / 100, strokeWidth: 4,
                    backgroundColor: const Color(0xFFF1ECE0),
                    color: pct >= 100
                        ? UellowColors.successDk : UellowColors.yellow,
                  )),
              Text('${pct.toInt()}%', style: const TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w900,
                  color: UellowColors.darkBrown)),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        if (loading)
          const Padding(padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator(
                  color: UellowColors.darkBrown)))
        else if (profile == null)
          _signedOut()
        else ...[
          // ── identity chips ──
          Wrap(spacing: 6, runSpacing: 6, children: [
            if (_has(profile!['gender']))
              _chip(profile!['gender'] == 'male'
                  ? (ar ? '👤 رجل' : '👤 Male')
                  : (ar ? '👤 امرأة' : '👤 Female')),
            if (_has(profile!['body_type']))
              _chip('${ar ? "الجسم: " : "Body: "}${profile!['body_type']}'),
            if (_has(profile!['preferred_fit']))
              _chip('${ar ? "القَصّة: " : "Fit: "}${profile!['preferred_fit']}'),
          ]),
          if (_has(profile!['gender']) || _has(profile!['body_type'])
              || _has(profile!['preferred_fit']))
            const SizedBox(height: 10),
          // ── measurement grid (always shows every slot — calm) ──
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8, crossAxisSpacing: 8,
            childAspectRatio: 1.55,
            children: [
              for (final m in _metrics) _tile(m),
            ],
          ),
          const SizedBox(height: 12),
          // ── single calm CTA ──
          SizedBox(width: double.infinity, child: OutlinedButton.icon(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 15),
            label: Text(
                filled == 0
                    ? (ar ? 'أضف مقاساتي' : 'Add my measurements')
                    : (ar ? 'تعديل المقاسات' : 'Edit measurements'),
                style: const TextStyle(fontWeight: FontWeight.w800,
                    fontSize: 12.5)),
            style: OutlinedButton.styleFrom(
              foregroundColor: UellowColors.darkBrown,
              side: const BorderSide(color: Color(0xFFE5DCC2)),
              padding: const EdgeInsets.symmetric(vertical: 11),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          )),
        ],
      ]),
    );
  }

  Widget _signedOut() => Column(children: [
    const Icon(Icons.lock_outline, size: 30, color: UellowColors.muted),
    const SizedBox(height: 8),
    Text(ar
            ? 'سجّل الدخول لعرض مقاساتك المحفوظة في حسابك'
            : 'Sign in to view the measurements saved on your account',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12, color: UellowColors.muted,
            height: 1.5)),
  ]);

  Widget _chip(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: const Color(0xFFF7F3E8),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(label, style: const TextStyle(fontSize: 10.5,
        fontWeight: FontWeight.w700, color: UellowColors.darkBrown)),
  );

  Widget _tile((String, IconData, String, String, String) m) {
    final v = profile![m.$1];
    final has = _has(v);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: has ? const Color(0xFFFDFBF4) : const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: has ? const Color(0xFFEFE6CC) : const Color(0xFFEFEFEF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(children: [
            Icon(m.$2, size: 12,
                color: has ? const Color(0xFFB8860B) : UellowColors.muted),
            const SizedBox(width: 4),
            Flexible(child: Text(ar ? m.$4 : m.$3,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: UellowColors.muted))),
          ]),
          const SizedBox(height: 3),
          Text(
              has
                  ? '${_fmtNum(v)}${m.$5.isEmpty ? '' : ' ${m.$5}'}'
                  : '—',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900,
                  color: has
                      ? UellowColors.ink : const Color(0xFFC9C2B2))),
        ],
      ),
    );
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
        // v2.1.54 — redesigned row: Ask-reviewers (blue, distinct) +
        // Add-to-cart (dark, distinct), one-line smaller labels;
        // Share shrank to an icon-only square. All always enabled.
        Row(children: [
          Expanded(child: ElevatedButton.icon(
            onPressed: onAskReviewers,
            icon: const Text('🎓', style: TextStyle(fontSize: 13)),
            label: Text(ar ? 'اسأل المراجعين' : 'Ask reviewers',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 11)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1565C0),
              foregroundColor: Colors.white, elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12))),
            ),
          )),
          const SizedBox(width: 8),
          Expanded(child: ElevatedButton.icon(
            onPressed: onAddToCart,
            icon: const Icon(Icons.add_shopping_cart, size: 14),
            label: Text(ar ? 'أضف للسلة' : 'Add to cart',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 11)),
            style: ElevatedButton.styleFrom(
              backgroundColor: UellowColors.darkBrown,
              foregroundColor: UellowColors.yellowLight, elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12))),
            ),
          )),
          const SizedBox(width: 8),
          // share — icon only
          SizedBox(width: 44, height: 44, child: OutlinedButton(
            onPressed: onShare,
            style: OutlinedButton.styleFrom(
              foregroundColor: UellowColors.darkBrown,
              side: const BorderSide(color: UellowColors.border, width: 1.5),
              padding: EdgeInsets.zero,
              shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12))),
            ),
            child: const Icon(Icons.share_outlined, size: 17),
          )),
        ]),
      ]),
    );
  }
}

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
                  ('regular', 'متوسط'), ('plus', 'ممتلئ'),
                ] : const [
                  ('slim', 'Slim'), ('athletic', 'Athletic'),
                  ('regular', 'Regular'), ('plus', 'Plus'),
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

// ─── Reviewer replies & votes (v2.1.54) ──────────────────────────────
// The customer's specialist requests: live status, the reviewer's
// verdict + quality/value scores, chat replies, and group-vote tallies.
class _ReviewerRepliesCard extends StatefulWidget {
  const _ReviewerRepliesCard({required this.ar});
  final bool ar;
  @override
  State<_ReviewerRepliesCard> createState() => _ReviewerRepliesCardState();
}

class _ReviewerRepliesCardState extends State<_ReviewerRepliesCard> {
  List<Map<String, dynamic>> _items = const [];
  bool _loaded = false;
  bool _expanded = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final token = await UellowApi.instance.tokenStore.readToken();
      if (token == null) { setState(() => _loaded = true); return; }
      final r = await http.get(
        Uri.parse('${UellowApi.instance.baseUrl}/api/mobile/v2/reviewers/my-requests'),
        headers: {'Accept': 'application/json',
                  'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 8));
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (mounted && j['success'] == true) {
        setState(() {
          _items = ((j['data']?['items'] as List?) ?? const [])
              .cast<Map>().map((m) => m.cast<String, dynamic>()).toList();
          _loaded = true;
        });
      } else if (mounted) {
        setState(() => _loaded = true);
      }
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Color _verdictColor(String v) => v == 'recommend'
      ? UellowColors.successDk
      : v == 'not_recommend' ? UellowColors.danger : const Color(0xFF1565C0);

  Color _stateColor(String s) => switch (s) {
    'completed' => UellowColors.successDk,
    'active' || 'accepted' => const Color(0xFF1565C0),
    'expired' || 'cancelled' => UellowColors.muted,
    _ => const Color(0xFFB45309),
  };

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _items.isEmpty) return const SizedBox.shrink();
    final ar = widget.ar;
    final shown = _expanded ? _items : _items.take(2).toList();
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFFF3F7FF), Colors.white],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3EAF6)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('🎓', style: TextStyle(fontSize: 15)),
          const SizedBox(width: 6),
          Expanded(child: Text(ar ? 'ردود المراجعين' : 'Reviewer replies',
              style: const TextStyle(fontSize: 13.5,
                  fontWeight: FontWeight.w900, color: UellowColors.ink))),
          IconButton(
            icon: const Icon(Icons.refresh, size: 17,
                color: UellowColors.muted),
            visualDensity: VisualDensity.compact,
            onPressed: _load,
          ),
        ]),
        for (final it in shown) _requestTile(it, ar),
        if (_items.length > 2) Center(child: TextButton(
          onPressed: () => setState(() => _expanded = !_expanded),
          child: Text(
              _expanded
                  ? (ar ? 'عرض أقل' : 'Show less')
                  : (ar ? 'عرض الكل (${_items.length})'
                        : 'Show all (${_items.length})'),
              style: const TextStyle(fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1565C0))),
        )),
      ]),
    );
  }

  Widget _requestTile(Map<String, dynamic> it, bool ar) {
    final rv = (it['reviewer'] as Map?)?.cast<String, dynamic>();
    final verdict = (it['verdict'] ?? '').toString();
    final votes = (it['votes'] as Map?)?.cast<String, dynamic>();
    final replies = ((it['replies'] as List?) ?? const [])
        .cast<Map>().map((m) => m.cast<String, dynamic>()).toList();
    final q = (it['quality'] as num?)?.toInt() ?? 0;
    final v = (it['value'] as num?)?.toInt() ?? 0;
    final state = (it['state'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE3EAF6)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: ((it['product'] as Map?)?['image'] ?? '').toString(),
              width: 36, height: 36, fit: BoxFit.cover,
              errorWidget: (_, __, ___) => Container(width: 36, height: 36,
                  color: const Color(0xFFF1F5F9),
                  child: const Icon(Icons.image_outlined, size: 16,
                      color: UellowColors.muted)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((((it['product'] as Map?)?['name'] as Map?)?[
                    ar ? 'ar' : 'en'] ?? '').toString(),
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.5,
                    fontWeight: FontWeight.w800, color: UellowColors.ink)),
            Text('${rv?['name'] ?? ''} · ${(it['date'] ?? '').toString()}',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 9,
                    color: UellowColors.muted)),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
            decoration: BoxDecoration(
              color: _stateColor(state).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
                (((it['state_label'] as Map?)?[ar ? 'ar' : 'en']) ?? '')
                    .toString(),
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900,
                    color: _stateColor(state))),
          ),
        ]),
        // verdict + scores
        if (verdict.isNotEmpty) Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: _verdictColor(verdict).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                  (((it['verdict_label'] as Map?)?[ar ? 'ar' : 'en'])
                      ?? '').toString(),
                  style: TextStyle(fontSize: 9.5,
                      fontWeight: FontWeight.w900,
                      color: _verdictColor(verdict))),
            ),
            if (q > 0) Padding(
              padding: const EdgeInsetsDirectional.only(start: 8),
              child: Text(ar ? 'الجودة $q/5' : 'Quality $q/5',
                  style: const TextStyle(fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: UellowColors.muted)),
            ),
            if (v > 0) Padding(
              padding: const EdgeInsetsDirectional.only(start: 8),
              child: Text(ar ? 'القيمة $v/5' : 'Value $v/5',
                  style: const TextStyle(fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: UellowColors.muted)),
            ),
          ]),
        ),
        // group votes tally
        if (votes != null && (votes['voted'] as num? ?? 0) > 0) Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(spacing: 6, children: [
            _voteChip('👍 ${votes['recommend']}',
                UellowColors.successDk),
            _voteChip('👎 ${votes['not_recommend']}',
                UellowColors.danger),
            _voteChip('😐 ${votes['neutral']}',
                const Color(0xFF1565C0)),
            Text(ar
                    ? '${votes['voted']}/${votes['total']} صوّتوا'
                    : '${votes['voted']}/${votes['total']} voted',
                style: const TextStyle(fontSize: 9,
                    color: UellowColors.muted,
                    fontWeight: FontWeight.w700)),
          ]),
        ),
        // reviewer notes / latest reply bubble
        if ((it['notes'] ?? '').toString().isNotEmpty) Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F7FF),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text((it['notes'] ?? '').toString(),
                maxLines: 3, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10.5, height: 1.45,
                    color: UellowColors.text)),
          ),
        )
        else if (replies.isNotEmpty) Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F7FF),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text('💬 ${replies.last['text']}',
                maxLines: 3, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10.5, height: 1.45,
                    color: UellowColors.text)),
          ),
        ),
      ]),
    );
  }

  Widget _voteChip(String label, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(label, style: TextStyle(fontSize: 9.5,
        fontWeight: FontWeight.w800, color: c)),
  );
}

// ─── Measurement history (v2.1.54) ───────────────────────────────────
// Snapshots appended on every save — date + the values that changed.
class _MeasureHistoryCard extends StatelessWidget {
  const _MeasureHistoryCard({required this.history, required this.ar});
  final List<Map<String, dynamic>> history;
  final bool ar;

  static const _names = {
    'height': ('Height', 'الطول'), 'weight': ('Weight', 'الوزن'),
    'chest': ('Chest', 'الصدر'), 'waist': ('Waist', 'الخصر'),
    'shoulder': ('Shoulder', 'الأكتاف'), 'hip': ('Hip', 'الورك'),
    'arm_length': ('Arm', 'الذراع'), 'inseam': ('Inseam', 'الساق'),
    'thigh': ('Thigh', 'الفخذ'), 'shoe_size_eu': ('Shoe EU', 'الحذاء'),
    'shoe_size_us': ('Shoe US', 'الحذاء US'),
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF1ECE0)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.history, size: 16, color: UellowColors.darkBrown),
          const SizedBox(width: 6),
          Text(ar ? 'سجل القياسات' : 'Measurement history',
              style: const TextStyle(fontSize: 13,
                  fontWeight: FontWeight.w900, color: UellowColors.ink)),
        ]),
        const SizedBox(height: 4),
        for (final h in history.take(6)) Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Column(children: [
              Container(width: 8, height: 8, decoration: const BoxDecoration(
                  color: UellowColors.yellow, shape: BoxShape.circle)),
              Container(width: 2, height: 26,
                  color: const Color(0xFFF1ECE0)),
            ]),
            const SizedBox(width: 10),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text((h['date'] ?? '').toString(),
                  style: const TextStyle(fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: UellowColors.muted)),
              const SizedBox(height: 3),
              Wrap(spacing: 6, runSpacing: 4, children: [
                for (final e in ((h['values'] as Map?) ?? const {}).entries)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFDFBF4),
                      border: Border.all(color: const Color(0xFFEFE6CC)),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                        '${ar ? (_names[e.key]?.$2 ?? e.key) : (_names[e.key]?.$1 ?? e.key)}'
                        ': ${(e.value is num && (e.value as num) == (e.value as num).roundToDouble()) ? (e.value as num).toInt() : e.value}',
                        style: const TextStyle(fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: UellowColors.darkBrown)),
                  ),
              ]),
            ])),
          ]),
        ),
      ]),
    );
  }
}
