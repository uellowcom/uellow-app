// Professional full-screen "جاري التحويل" overlay shown while the app switches
// country (prices/products/website are per-country and re-fetch takes a moment).
// It lives on the ROOT overlay so it survives the cold-restart navigation, and
// is dismissed by the splash once the new store is ready.
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../api/uellow_api.dart';

class CountrySwitchOverlay {
  static OverlayEntry? _entry;
  static bool get isShowing => _entry != null;

  /// Insert the overlay on the root overlay so it stays above route changes.
  static void show(BuildContext context, {String? countryLabel}) {
    if (_entry != null) return;
    final overlay = Overlay.of(context, rootOverlay: true);
    _entry = OverlayEntry(
      builder: (_) => _SwitchingView(countryLabel: countryLabel),
    );
    overlay.insert(_entry!);
  }

  static void hide() {
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

class _SwitchingViewState extends State<_SwitchingView>
    with TickerProviderStateMixin {
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))
        ..repeat();
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat(reverse: true);
  late final AnimationController _in =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 350))
        ..forward();

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
    const yellow = Color(0xFFFBBF00);
    const orange = Color(0xFFF26A2E);
    const ink = Color(0xFF0B1220);
    return Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: FadeTransition(
        opacity: _in,
        child: Container(
          color: ink.withOpacity(0.72),
          child: BackdropFilterSafe(
            child: Center(
              child: ScaleTransition(
                scale: Tween(begin: 0.9, end: 1.0).animate(
                    CurvedAnimation(parent: _in, curve: Curves.easeOutBack)),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 30),
                  margin: const EdgeInsets.symmetric(horizontal: 40),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.28),
                          blurRadius: 40,
                          offset: const Offset(0, 18)),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // animated rings + bee
                      SizedBox(
                        width: 96,
                        height: 96,
                        child: AnimatedBuilder(
                          animation: Listenable.merge([_spin, _pulse]),
                          builder: (_, __) {
                            return Stack(
                              alignment: Alignment.center,
                              children: [
                                Transform.rotate(
                                  angle: _spin.value * 2 * math.pi,
                                  child: CustomPaint(
                                    size: const Size(96, 96),
                                    painter: _ArcPainter(
                                        color: orange, sweep: 1.1, stroke: 5),
                                  ),
                                ),
                                Transform.rotate(
                                  angle: -_spin.value * 2 * math.pi,
                                  child: CustomPaint(
                                    size: const Size(72, 72),
                                    painter: _ArcPainter(
                                        color: yellow, sweep: 1.4, stroke: 5),
                                  ),
                                ),
                                Transform.scale(
                                  scale: 0.9 + _pulse.value * 0.18,
                                  child: const Text('🐝',
                                      style: TextStyle(fontSize: 30)),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        ar ? 'جارٍ التحويل…' : 'Switching…',
                        style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 19,
                            color: ink),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.countryLabel != null
                            ? (ar
                                ? 'يتم تحديث المتجر حسب ${widget.countryLabel}'
                                : 'Updating the store for ${widget.countryLabel}')
                            : (ar
                                ? 'يتم تحديث المتجر والأسعار حسب بلدك'
                                : 'Updating store & prices for your country'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 13,
                            height: 1.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF667085)),
                      ),
                      const SizedBox(height: 16),
                      // shimmering progress bar
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox(
                          width: 180,
                          height: 6,
                          child: AnimatedBuilder(
                            animation: _spin,
                            builder: (_, __) {
                              return CustomPaint(
                                painter: _BarPainter(
                                    t: _spin.value,
                                    c1: yellow,
                                    c2: orange),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// BackdropFilter that degrades gracefully if unsupported.
class BackdropFilterSafe extends StatelessWidget {
  const BackdropFilterSafe({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}

class _ArcPainter extends CustomPainter {
  _ArcPainter({required this.color, required this.sweep, required this.stroke});
  final Color color;
  final double sweep;
  final double stroke;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke;
    final rect = Offset.zero & size;
    canvas.drawArc(rect.deflate(stroke), 0, sweep, false, p);
  }

  @override
  bool shouldRepaint(covariant _ArcPainter old) =>
      old.color != color || old.sweep != sweep;
}

class _BarPainter extends CustomPainter {
  _BarPainter({required this.t, required this.c1, required this.c2});
  final double t;
  final Color c1;
  final Color c2;
  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0xFFF0F2F5);
    canvas.drawRect(Offset.zero & size, bg);
    final w = size.width * 0.4;
    final x = (t * (size.width + w)) - w;
    final grad = LinearGradient(colors: [c1, c2]);
    final p = Paint()
      ..shader = grad.createShader(Rect.fromLTWH(x, 0, w, size.height));
    canvas.drawRect(Rect.fromLTWH(x, 0, w, size.height), p);
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) => old.t != t;
}
