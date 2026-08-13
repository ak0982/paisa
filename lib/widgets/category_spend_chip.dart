import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../models/category_info.dart';
import '../theme/paisa_colors.dart';
import '../theme/paisa_theme.dart';
import '../utils/formatters.dart';

/// Rank stamp on Stats / Reports category stickers.
enum ShareBadgeKind { top, mid, low }

class CategorySpendChip extends StatelessWidget {
  const CategorySpendChip({
    super.key,
    required this.info,
    required this.amount,
    this.share,
    this.emphasize = false,
    this.badgeKind,
    this.onTap,
    this.rotate = false,
    this.angle = -0.035,
    this.expanded = false,
  });

  final CategoryInfo info;
  final double amount;

  /// Spend share of the total (0–1). When set, a thin rim arc shows the
  /// proportion (Stats / Reports). Home chips leave this null.
  final double? share;

  /// Top category: thicker border and lime hard shadow.
  final bool emphasize;

  /// When [share] is set, which stamp to show. Null → no badge (Home).
  final ShareBadgeKind? badgeKind;

  final VoidCallback? onTap;
  final bool rotate;
  final double angle;

  /// Stretch to the parent width (Stats / Reports 2-col grid).
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final labelColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          info.label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: PaisaTheme.manrope(
            size: 9,
            weight: FontWeight.w700,
            color: PaisaColors.mutedCaption,
            letterSpacing: 1,
          ),
        ),
        Text(
          formatInr(amount),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: PaisaTheme.sora(
            size: 12.5,
            weight: FontWeight.w800,
            color: PaisaColors.ink,
          ),
        ),
      ],
    );

    final fill = share?.clamp(0.0, 1.0);
    final borderRadius = BorderRadius.circular(13);
    final radius = 13.0;
    final borderWidth = emphasize ? 2.75 : 2.0;
    final showArc = fill != null && fill > 0;
    final pctLabel = fill == null ? '' : formatSharePercent(fill);
    final showBadge = pctLabel.isNotEmpty && badgeKind != null;

    final inner = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
          children: [
            Text(info.emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 8),
            if (expanded) Expanded(child: labelColumn) else labelColumn,
          ],
        ),
      ),
    );

    Widget chip = Material(
      color: PaisaColors.cardElevated,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: borderRadius,
        side: BorderSide(color: info.iconColor, width: borderWidth),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap != null
          ? InkWell(
              onTap: onTap,
              borderRadius: borderRadius,
              child: inner,
            )
          : inner,
    );

    if (showArc || showBadge) {
      chip = Stack(
        clipBehavior: Clip.none,
        children: [
          chip,
          if (showArc)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _ShareRimArcPainter(
                    share: fill,
                    color: info.iconColor,
                    cornerRadius: radius,
                    strokeWidth: emphasize ? 3.0 : 2.25,
                  ),
                ),
              ),
            ),
          if (showBadge)
            Positioned(
              top: -8,
              right: 6,
              child: IgnorePointer(
                child: _ShareBadge(
                  kind: badgeKind!,
                  percentLabel: pctLabel,
                  accent: info.iconColor,
                ),
              ),
            ),
        ],
      );
    }

    if (emphasize) {
      chip = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: PaisaColors.hardShadow(
            color: PaisaColors.primary,
            offset: 3,
          ),
        ),
        child: chip,
      );
    }

    if (rotate) {
      chip = Transform.rotate(angle: angle, child: chip);
    }
    return chip;
  }
}

/// Compact stamp: TOP · N% / N% / LOW · N%.
class _ShareBadge extends StatelessWidget {
  const _ShareBadge({
    required this.kind,
    required this.percentLabel,
    required this.accent,
  });

  final ShareBadgeKind kind;

  /// Pre-formatted share, e.g. `32%`, `0.4%`, `<0.01%`.
  final String percentLabel;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final isTop = kind == ShareBadgeKind.top;
    final label = switch (kind) {
      ShareBadgeKind.top => 'TOP · $percentLabel',
      ShareBadgeKind.low => 'LOW · $percentLabel',
      ShareBadgeKind.mid => percentLabel,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isTop ? PaisaColors.primary : accent,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: isTop ? PaisaColors.inkOnAccent : PaisaColors.cardElevated,
          width: 1.5,
        ),
      ),
      child: Text(
        label,
        style: PaisaTheme.manrope(
          size: 8,
          weight: FontWeight.w800,
          color: isTop ? PaisaColors.inkOnAccent : PaisaColors.ink,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

/// Thin stroke along the chip rim; length = [share] of the perimeter.
class _ShareRimArcPainter extends CustomPainter {
  _ShareRimArcPainter({
    required this.share,
    required this.color,
    required this.cornerRadius,
    this.strokeWidth = 2.25,
  });

  final double share;
  final Color color;
  final double cornerRadius;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (share <= 0 || size.isEmpty) return;

    final inset = strokeWidth / 2;
    final rect = Rect.fromLTWH(
      inset,
      inset,
      math.max(0, size.width - strokeWidth),
      math.max(0, size.height - strokeWidth),
    );
    final r = math.min(cornerRadius, math.min(rect.width, rect.height) / 2);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(r));

    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics().first;
    final length = metrics.length * share.clamp(0.0, 1.0);
    // Start near top-center so the arc grows clockwise along the rim.
    final start = metrics.length * 0.75;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    if (start + length <= metrics.length) {
      canvas.drawPath(metrics.extractPath(start, start + length), paint);
    } else {
      final first = metrics.length - start;
      canvas.drawPath(metrics.extractPath(start, metrics.length), paint);
      canvas.drawPath(metrics.extractPath(0, length - first), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ShareRimArcPainter oldDelegate) =>
      oldDelegate.share != share ||
      oldDelegate.color != color ||
      oldDelegate.cornerRadius != cornerRadius ||
      oldDelegate.strokeWidth != strokeWidth;
}

/// Home-style stickers in a 2-column wrap for Stats / Reports.
class CategorySpendStickerGrid extends StatelessWidget {
  const CategorySpendStickerGrid({
    super.key,
    required this.tiles,
  });

  final List<CategorySpendTile> tiles;

  static ShareBadgeKind badgeKindForIndex(int i, int length) {
    if (i == 0) return ShareBadgeKind.top;
    if (length > 1 && i == length - 1) return ShareBadgeKind.low;
    return ShareBadgeKind.mid;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final tileWidth = (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: 12,
          children: [
            for (var i = 0; i < tiles.length; i++)
              SizedBox(
                width: tileWidth,
                child: CategorySpendChip(
                  info: CategoryInfo.forCategory(tiles[i].category),
                  amount: tiles[i].amount,
                  share: tiles[i].share,
                  emphasize: tiles[i].emphasize,
                  badgeKind: tiles[i].share != null
                      ? badgeKindForIndex(i, tiles.length)
                      : null,
                  onTap: tiles[i].onTap,
                  expanded: true,
                  rotate: true,
                  angle: i.isEven ? -0.035 : 0.035,
                ),
              ),
          ],
        );
      },
    );
  }
}

class CategorySpendTile {
  const CategorySpendTile({
    required this.category,
    required this.amount,
    this.share,
    this.emphasize = false,
    this.onTap,
  });

  final SpendCategory category;
  final double amount;

  /// Spend share of the total (0–1) for the rim arc + percent badge.
  final double? share;

  /// Highest-share tile — thicker border, lime shadow.
  final bool emphasize;

  final VoidCallback? onTap;
}
