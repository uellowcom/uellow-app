// =============================================================================
// NetworkErrorView (v2.2.29) — a professional, friendly error state with an
// animated icon. Replaces raw "UellowApiException(network_error,0) connection
// reset by peer" dumps. Use in any FutureBuilder error branch.
// =============================================================================
import 'package:flutter/material.dart';

import '../../api/uellow_api.dart';
import '../theme/uellow_theme.dart';

class NetworkErrorView extends StatefulWidget {
  const NetworkErrorView({super.key, this.error, this.onRetry, this.compact = false});
  final Object? error;
  final VoidCallback? onRetry;
  final bool compact;

  /// True when the error looks like a connectivity problem.
  static bool isNetwork(Object? e) {
    if (e is UellowApiException) return e.isNetwork || e.code == 'TIMEOUT';
    final s = (e?.toString() ?? '').toLowerCase();
    return s.contains('socket') || s.contains('network') ||
        s.contains('connection') || s.contains('reset by peer') ||
        s.contains('failed host lookup') || s.contains('timed out');
  }

  /// True specifically when the server is just slow (a timeout), as opposed
  /// to being fully offline — drives the calmer "Just a moment" state.
  static bool isTimeout(Object? e) {
    if (e is UellowApiException) return e.code == 'TIMEOUT';
    final s = (e?.toString() ?? '').toLowerCase();
    return s.contains('timed out') || s.contains('timeout');
  }

  @override
  State<NetworkErrorView> createState() => _NetworkErrorViewState();
}

class _NetworkErrorViewState extends State<NetworkErrorView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
        ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    // v2.2.40 — a slow response (TIMEOUT) is NOT "no connection". Give it a
    // calm, reassuring state of its own so we don't alarm the customer when
    // the app is merely a little slow.
    final timeout = NetworkErrorView.isTimeout(widget.error);
    final net = !timeout && NetworkErrorView.isNetwork(widget.error);
    final title = timeout
        ? (ar ? 'لحظة من فضلك' : 'Just a moment')
        : net
            ? (ar ? 'لا يوجد اتصال' : 'No connection')
            : (ar ? 'حدث خطأ ما' : 'Something went wrong');
    final body = timeout
        ? (ar
            ? 'الاتصال أبطأ قليلاً من المعتاد — جارٍ التحميل. يمكنك التحديث للمحاولة مجدداً.'
            : 'Things are a little slower than usual — still loading. You can refresh to try again.')
        : net
            ? (ar
                ? 'تعذّر الوصول للإنترنت. تأكد من اتصالك وحاول مرة أخرى.'
                : "We can't reach the internet right now. Check your connection and try again.")
            : (ar
                ? 'واجهتنا مشكلة مؤقتة. حاول مرة أخرى.'
                : 'We hit a temporary issue. Please try again.');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // animated icon
          AnimatedBuilder(
            animation: _c,
            builder: (_, __) {
              final t = Curves.easeInOut.transform(_c.value);
              return SizedBox(
                width: widget.compact ? 84 : 116,
                height: widget.compact ? 84 : 116,
                child: Stack(alignment: Alignment.center, children: [
                  // expanding soft ring
                  Transform.scale(
                    scale: 0.7 + t * 0.5,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: UellowColors.yellow
                            .withValues(alpha: 0.18 * (1 - t)),
                      ),
                    ),
                  ),
                  Container(
                    width: widget.compact ? 58 : 76,
                    height: widget.compact ? 58 : 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                        colors: [Color(0xFFFFF3CC), Color(0xFFFFE08A)]),
                    ),
                    child: Transform.translate(
                      offset: Offset(0, -2 + t * 4),
                      child: Icon(
                        timeout
                            ? Icons.hourglass_top_rounded
                            : net
                                ? Icons.wifi_off_rounded
                                : Icons.error_outline_rounded,
                        size: widget.compact ? 30 : 40,
                        color: UellowColors.darkBrown),
                    ),
                  ),
                ]),
              );
            },
          ),
          SizedBox(height: widget.compact ? 12 : 18),
          Text(title, textAlign: TextAlign.center,
              style: TextStyle(fontSize: widget.compact ? 15 : 18,
                  fontWeight: FontWeight.w900, color: UellowColors.darkBrown)),
          const SizedBox(height: 6),
          Text(body, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, height: 1.4,
                  color: UellowColors.muted)),
          if (widget.onRetry != null) ...[
            SizedBox(height: widget.compact ? 14 : 20),
            ElevatedButton.icon(
              onPressed: widget.onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(timeout ? (ar ? 'تحديث' : 'Refresh')
                      : (ar ? 'إعادة المحاولة' : 'Try again'),
                  style: const TextStyle(fontWeight: FontWeight.w900)),
              style: ElevatedButton.styleFrom(
                backgroundColor: UellowColors.yellow,
                foregroundColor: UellowColors.darkBrown,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999)),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}
