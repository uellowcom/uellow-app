// =============================================================================
// UellowLogo — drop-in wordmark image. Use everywhere the "Uellow" name
// appears (splash, app bars, auth screen, headers, etc).
// =============================================================================
import 'package:flutter/material.dart';

class UellowLogo extends StatelessWidget {
  const UellowLogo({super.key, this.height = 28, this.color});

  /// Image height. Aspect ratio (~3.33:1) is preserved.
  final double height;

  /// Optional color tint. Pass `Colors.white` when the logo sits on a
  /// dark hero header, leave null to keep its native colors.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final img = Image.asset(
      'assets/images/logo.png',
      height: height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );
    if (color == null) return img;
    return ColorFiltered(
      colorFilter: ColorFilter.mode(color!, BlendMode.srcIn),
      child: img,
    );
  }
}
