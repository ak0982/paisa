import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/paisa_colors.dart';
import '../theme/paisa_theme.dart';
import 'neo_surface.dart';

/// Shared Paisa Coin chrome — the struck-disc visual language used by the day
/// coin (Paisa Coin) and the ledger coin (Stats).
///
/// A coin is a milled disc with a split OUT/IN gauge ring, a recessed centre
/// field carrying the headline amount, and legends struck along the rim.

/// OUT arc share of a coin gauge ring (`out / (out + income)`).
/// Returns `0` when there is no flow so the ring stays idle.
double paisaCoinOutShare(double out, double income) {
  final total = out + income;
  if (total <= 0) return 0.0;
  return out / total;
}

/// Fade + rise entrance shared by coin heroes and stamped rows.
class PaisaCoinRise extends StatelessWidget {
  const PaisaCoinRise({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 460),
    this.offsetY = 12,
  });

  final Widget child;
  final Duration duration;
  final double offsetY;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, t, inner) {
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, offsetY * (1 - t)),
            child: inner,
          ),
        );
      },
      child: child,
    );
  }
}

/// The struck disc: milled rim, split OUT/IN gauge that draws on, recessed
/// centre field holding [child], and embossed legends top ([topLegend]) and
/// bottom ([bottomLegend]).
class PaisaCoinFace extends StatelessWidget {
  const PaisaCoinFace({
    super.key,
    required this.child,
    required this.outShare,
    required this.hasFlow,
    required this.topLegend,
    this.bottomLegend = '• P A I S A •',
    this.maxDiameter = 288,
    this.fieldWidthFactor = 0.56,
  });

  final Widget child;

  /// 0–1 share of the ring taken by the OUT (white) arc; the remainder is IN.
  final double outShare;

  /// When false the ring stays an idle track (no money moved).
  final bool hasFlow;

  final String topLegend;
  final String bottomLegend;
  final double maxDiameter;

  /// Width of [child] as a fraction of the disc diameter.
  final double fieldWidthFactor;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxD =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 300.0;
        final d = math.min(maxD, maxDiameter);

        return SizedBox(
          width: d,
          height: d,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, p, inner) {
              return CustomPaint(
                painter: _CoinPainter(
                  progress: p,
                  outShare: outShare,
                  hasFlow: hasFlow,
                  topLegend: topLegend,
                  bottomLegend: bottomLegend,
                ),
                child: inner,
              );
            },
            child: Center(
              child: SizedBox(width: d * fieldWidthFactor, child: child),
            ),
          ),
        );
      },
    );
  }
}

class _CoinPainter extends CustomPainter {
  _CoinPainter({
    required this.progress,
    required this.outShare,
    required this.hasFlow,
    required this.topLegend,
    required this.bottomLegend,
  });

  final double progress;
  final double outShare;
  final bool hasFlow;
  final String topLegend;
  final String bottomLegend;

  static const _twoPi = math.pi * 2;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2 - 5;

    // Hard Neo-Vault shadow — offset solid disc, no blur.
    canvas.drawCircle(
      center.translate(6, 6),
      r,
      Paint()..color = const Color(0xFF000000),
    );

    // Raised rim field.
    canvas.drawCircle(center, r, Paint()..color = PaisaColors.cardElevated);
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..color = PaisaColors.inkOnAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    _paintMilledEdge(canvas, center, r);

    // Gauge ring.
    final gaugeR = r - 14;
    const stroke = 8.0;
    canvas.drawCircle(
      center,
      gaugeR,
      Paint()
        ..color = PaisaColors.border
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );

    if (hasFlow) {
      const gap = 0.10; // radians of breathing room at both meeting points
      const usable = _twoPi - gap * 2;
      final outSweep = usable * outShare * progress;
      final inSweep = usable * (1 - outShare) * progress;
      final rect = Rect.fromCircle(center: center, radius: gaugeR);
      const top = -math.pi / 2;

      if (outSweep > 0.001) {
        canvas.drawArc(
          rect,
          top + gap / 2,
          outSweep,
          false,
          Paint()
            ..color = PaisaColors.ink
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke
            ..strokeCap = StrokeCap.round,
        );
      }
      if (inSweep > 0.001) {
        canvas.drawArc(
          rect,
          top - gap / 2,
          -inSweep,
          false,
          Paint()
            ..color = PaisaColors.primary
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    // Recessed centre field with its own thin ring.
    final fieldR = r * 0.70;
    canvas.drawCircle(center, fieldR, Paint()..color = PaisaColors.card);
    canvas.drawCircle(
      center,
      fieldR,
      Paint()
        ..color = PaisaColors.border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Struck legends between the gauge and the field.
    final legendR = (gaugeR + fieldR) / 2 - 2;
    _paintArcText(
      canvas,
      center,
      topLegend,
      radius: legendR,
      centerAngle: -math.pi / 2,
      outward: true,
      style: _embossed(
        PaisaTheme.sora(
          size: 11,
          weight: FontWeight.w800,
          color: PaisaColors.mutedCaption,
          letterSpacing: 1,
        ),
      ),
    );
    _paintArcText(
      canvas,
      center,
      bottomLegend,
      radius: legendR,
      centerAngle: math.pi / 2,
      outward: false,
      style: _embossed(
        PaisaTheme.sora(
          size: 9,
          weight: FontWeight.w800,
          color: PaisaColors.muted,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  /// Hard 1px drop under each glyph so legends read as struck into the metal.
  static TextStyle _embossed(TextStyle style) => style.copyWith(
        shadows: const [
          Shadow(color: Color(0xFF000000), offset: Offset(0, 1.2)),
        ],
      );

  void _paintMilledEdge(Canvas canvas, Offset center, double r) {
    final paint = Paint()
      ..color = PaisaColors.muted.withOpacity(0.45)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    const ticks = 72;
    for (var i = 0; i < ticks; i++) {
      final a = _twoPi * i / ticks;
      final c = math.cos(a);
      final s = math.sin(a);
      canvas.drawLine(
        Offset(center.dx + c * (r - 2.5), center.dy + s * (r - 2.5)),
        Offset(center.dx + c * (r - 6.5), center.dy + s * (r - 6.5)),
        paint,
      );
    }
  }

  /// Draws [text] along a circle. [outward] keeps letter tops facing away from
  /// the centre (top legends); otherwise they face in (bottom legends).
  void _paintArcText(
    Canvas canvas,
    Offset center,
    String text, {
    required double radius,
    required double centerAngle,
    required bool outward,
    required TextStyle style,
  }) {
    if (text.isEmpty || radius <= 0) return;

    final painters = <TextPainter>[];
    var arcLength = 0.0;
    for (final rune in text.runes) {
      final tp = TextPainter(
        text: TextSpan(text: String.fromCharCode(rune), style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      painters.add(tp);
      arcLength += tp.width;
    }
    final totalAngle = arcLength / radius;
    if (totalAngle >= _twoPi) return;

    final dir = outward ? 1.0 : -1.0;
    var angle = centerAngle - dir * totalAngle / 2;

    for (final tp in painters) {
      final step = (tp.width / radius) * dir;
      final mid = angle + step / 2;
      canvas.save();
      canvas.translate(
        center.dx + math.cos(mid) * radius,
        center.dy + math.sin(mid) * radius,
      );
      canvas.rotate(mid + (outward ? math.pi / 2 : -math.pi / 2));
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
      angle += step;
    }
  }

  @override
  bool shouldRepaint(covariant _CoinPainter old) =>
      old.progress != progress ||
      old.outShare != outShare ||
      old.hasFlow != hasFlow ||
      old.topLegend != topLegend ||
      old.bottomLegend != bottomLegend;
}

/// Miniature struck coin: milled rim + a ring that fills with [fill] of the
/// whole. Used as the leading token on coin-stamped list rows.
class PaisaCoinToken extends StatelessWidget {
  const PaisaCoinToken({
    super.key,
    required this.color,
    required this.fill,
    this.dashed = false,
    this.size = 34,
    this.glyph = '₹',
    this.glyphSize = 13,
  });

  final Color color;
  final double fill;
  final bool dashed;
  final double size;
  final String glyph;
  final double glyphSize;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _TokenPainter(color: color, fill: fill, dashed: dashed),
        child: Center(
          child: Text(
            glyph,
            style: PaisaTheme.sora(
              size: glyphSize,
              weight: FontWeight.w800,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

class _TokenPainter extends CustomPainter {
  _TokenPainter({
    required this.color,
    required this.fill,
    required this.dashed,
  });

  final Color color;
  final double fill;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2 - 1;

    canvas.drawCircle(center, r, Paint()..color = PaisaColors.cardElevated);
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..color = PaisaColors.border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    // Milled edge.
    final milled = Paint()
      ..color = PaisaColors.muted.withOpacity(0.4)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    const ticks = 20;
    for (var i = 0; i < ticks; i++) {
      final a = math.pi * 2 * i / ticks;
      final c = math.cos(a);
      final s = math.sin(a);
      canvas.drawLine(
        Offset(center.dx + c * (r - 1.5), center.dy + s * (r - 1.5)),
        Offset(center.dx + c * (r - 3.5), center.dy + s * (r - 3.5)),
        milled,
      );
    }

    final rect = Rect.fromCircle(center: center, radius: r - 2.2);
    final sweep = math.pi * 2 * fill.clamp(0.0, 1.0);
    const start = -math.pi / 2;
    final arc = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;

    if (dashed) {
      const segments = 9;
      final segSweep = sweep / segments;
      for (var i = 0; i < segments; i++) {
        canvas.drawArc(
          rect,
          start + i * segSweep,
          segSweep * 0.55,
          false,
          arc,
        );
      }
    } else {
      canvas.drawArc(rect, start, sweep, false, arc);
    }
  }

  @override
  bool shouldRepaint(covariant _TokenPainter old) =>
      old.color != color || old.fill != fill || old.dashed != dashed;
}

/// Square chrome button used in coin-screen headers.
class PaisaChromeIconButton extends StatelessWidget {
  const PaisaChromeIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.accent = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final child = GestureDetector(
      onTap: onTap,
      child: NeoSurface(
        width: 36,
        height: 36,
        radius: 10,
        borderWidth: 1.5,
        borderColor: accent
            ? PaisaColors.primary.withOpacity(0.45)
            : PaisaColors.border,
        padding: EdgeInsets.zero,
        shadow: accent,
        shadowOffset: 2,
        child: Icon(
          icon,
          size: 20,
          color: accent ? PaisaColors.primary : PaisaColors.ink,
        ),
      ),
    );
    if (tooltip == null) return child;
    return Tooltip(message: tooltip!, child: child);
  }
}

/// `PAISA <suffix>` header wordmark, e.g. `PAISA COIN` / `PAISA STATS`.
class PaisaCoinWordmark extends StatelessWidget {
  const PaisaCoinWordmark({super.key, required this.suffix});

  final String suffix;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'PAISA',
          style: PaisaTheme.label(
            size: 11,
            color: PaisaColors.primary,
            letterSpacing: 3,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          suffix,
          style: PaisaTheme.label(
            size: 11,
            color: PaisaColors.muted,
            letterSpacing: 3,
          ),
        ),
      ],
    );
  }
}
