// =============================================================================
// UpdatingPane (v2.1.66) — friendly full-area error state shown instead of
// raw exceptions (e.g. UellowApiException(TIMEOUT)). Most such failures
// happen during server deploy windows, so the message says the app is
// being updated and invites a retry, with an animated update icon.
// =============================================================================
import 'package:flutter/material.dart';

import '../../api/uellow_api.dart';
import '../theme/uellow_theme.dart';

class UpdatingPane extends StatefulWidget {
  const UpdatingPane({super.key, required this.onRetry});
  final VoidCallback onRetry;

  @override
  State<UpdatingPane> createState() => _UpdatingPaneState();
}

class _UpdatingPaneState extends State<UpdatingPane>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
      vsync: this, duration: const Duration(seconds: 2))..repeat();

  @override
  void dispose() { _spin.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    return Center(child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Animated update badge — rotating sync ring + fixed bolt
        SizedBox(width: 86, height: 86, child: Stack(
            alignment: Alignment.center, children: [
          Container(
            width: 86, height: 86,
            decoration: BoxDecoration(
              color: UellowColors.yellowFaint,
              shape: BoxShape.circle,
              border: Border.all(
                  color: UellowColors.yellow.withValues(alpha: .5)),
            ),
          ),
          RotationTransition(
            turns: _spin,
            child: const Icon(Icons.sync, size: 46,
                color: UellowColors.darkBrown),
          ),
        ])),
        const SizedBox(height: 18),
        Text(ar ? 'التطبيق يخضع للتحديث الآن ✨'
                : 'The app is being updated right now ✨',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15.5,
                fontWeight: FontWeight.w900, color: UellowColors.ink)),
        const SizedBox(height: 6),
        Text(ar ? 'نجهّز لك تجربة أفضل — حاول مرة أخرى بعد ثوانٍ'
                : "We're preparing a better experience — try again in a few seconds",
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, height: 1.5,
                color: UellowColors.muted)),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: widget.onRetry,
          icon: const Icon(Icons.refresh, size: 18),
          label: Text(ar ? 'إعادة المحاولة' : 'Retry',
              style: const TextStyle(fontWeight: FontWeight.w900)),
          style: ElevatedButton.styleFrom(
            backgroundColor: UellowColors.yellow,
            foregroundColor: UellowColors.darkBrown,
            elevation: 0,
            padding: const EdgeInsets.symmetric(
                horizontal: 28, vertical: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ]),
    ));
  }
}
