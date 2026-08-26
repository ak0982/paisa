import 'package:flutter/material.dart';

import '../theme/paisa_colors.dart';

/// Trailing chevron for rows / legends that navigate or open detail.
///
/// Matches Reports income/merchant rows, Profile settings, and Day Strip teaser:
/// muted caption ink, rounded chevron — not a new accent language.
class PaisaNavChevron extends StatelessWidget {
  const PaisaNavChevron({
    super.key,
    this.size = 18,
    this.color,
  });

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.chevron_right_rounded,
      size: size,
      color: color ?? PaisaColors.mutedCaption,
    );
  }
}
