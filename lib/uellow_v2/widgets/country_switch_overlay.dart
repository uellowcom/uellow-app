// Professional full-screen "جاري التحويل" overlay shown while the app switches
// country (prices/products/website are per-country and re-fetch takes a moment).
// It lives on the ROOT overlay so it survives the cold-restart navigation, and
// is dismissed by the home screen ONLY once the NEW store finished loading.
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../api/uellow_api.dart';

class CountrySwitchOverlay {
  static OverlayEntry? _entry;
  static Timer? _safety;
  static bool get isShowing => _entry != null;

  /// Insert the overlay on the root overlay so it stays above route changes.
  /// [safety] auto-dismisses it if the switch never reports done (network dead).
  static void show(BuildContext context,
      {String? countryLabel, Duration safety = const Duration(seconds: 20)}) {
    if (_entry != null) return;
    final overlay = Overlay.of(context, rootOverlay: true);
    _entry = OverlayEntry(builder: (_) => _SwitchingView(countryLabel: countryLabel));
    overlay.insert(_entry!);
    _safety?.cancel();
    _safety = Timer(safety, hide);
  }

  static void hide() {
    _safety?.cancel();
    _safety = null;
    _entry?.remove();
    _entry = null;
  }
}

class _SwitchingView extends StatefulWidget {
  const _SwitchingView({this.countryLabel});
  final String? countryLabel;
  @override
  State<_SwitchingView> createState() => _SwitchingViewState();
}

class _SwitchingViewState extends State<_SwitchingView> with TickerProviderStateMixin {
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
  late final AnimationController _in =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 340))..forward();

  @override
  void dispose() {
    _spin.dispose();
    _pulse.dispose();
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang.startsWith('ar');
    const orange = Color(0xFFFB4E00);
    const orange2 = Color(0xFFFF8A00);
    const ink = Color(0xFF0B1220);
    return Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: FadeTransition(
        opacity: _in,
        child: Container(
          color: ink.withOpacity(0.66),
          child: Center(
            child: ScaleTransition(
              scale: Tween(begin: 0.92, end: 1.0)
                  .animate(CurvedAnimation(parent: _in, curve: Curves.easeOutCubic)),
              child: Container(
                width: 250,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.30), blurRadius: 44, offset: const Offset(0, 20)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // clean dual-ring loader with a bee in the middle
                    SizedBox(
                      width: 82,
                      height: 82,
                      child: AnimatedBuilder(
                        animation: Listenable.merge([_spin, _pulse]),
                        builder: (_, __) => Stack(
                          alignment: Alignment.center,
                          children: [
                            CustomPaint(
                              size: const Size(82, 82),
                              painter: _RingPainter(
                                t: _spin.value, color: orange, track: const Color(0xFFF1E9E2), stroke: 6),
                            ),
                            Container(
                              width: 54, height: 54,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(colors: [orange2, orange]),
                                boxShadow: [BoxShadow(color: orange.withOpacity(0.35), blurRadius: 16, offset: const Offset(0, 6))],
                              ),
                              child: Center(
                                child: Transform.scale(
                                  scale: 0.92 + _pulse.value * 0.16,
                                  child: const Text('🐝', style: TextStyle(fontSize: 24)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(ar ? 'جارٍ التحويل' : 'Switching',
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 19, color: ink)),
                    const SizedBox(height: 8),
                    Text(
                      widget.countryLabel != null
                          ? (ar ? 'يتم تجهيز متجر ${widget.countryLabel}' : 'Preparing the ${widget.countryLabel} store')
                          : (ar ? 'يتم تحديث المتجر والأسعار حسب بلدك' : 'Updating store & prices for your country'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12.5, height: 1.55, fontWeight: FontWeight.w600, color: Color(0xFF667085)),
                    ),
                    const SizedBox(height: 16),
                    // three subtle pulsing dots (no bar)
                    AnimatedBuilder(
                      animation: _spin,
                      builder: (_, __) {
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(3, (i) {
                            final phase = (_spin.value + i / 3) % 1.0;
                            final o = 0.3 + (0.7 * (0.5 + 0.5 * math.sin(phase * 2 * math.pi)));
                            return Container(
                              width: 7, height: 7,
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: orange.withOpacity(o.clamp(0.0, 1.0)),
                              ),
                            );
                          }),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A clean arc that sweeps around a faint track — premium, minimal.
class _RingPainter extends CustomPainter {
  _RingPainter({required this.t, required this.color, required this.track, required this.stroke});
  final double t;
  final Color color;
  final Color track;
  final double stroke;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke);
    final tp = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(rect, 0, 2 * math.pi, false, tp);
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke;
    final start = t * 2 * math.pi;
    canvas.drawArc(rect, start, 1.9, false, p);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.t != t || old.color != color;
}
