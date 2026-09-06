import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../theme/paisa_colors.dart';
import '../utils/formatters.dart';

/// Cartesian **Pulse Ribbon** of OUT spend.
///
/// X = time (bucket starts), Y = spend. A thick emerald heartbeat band whose
/// centerline traces spend and whose vertical thickness also swells with
/// amount — sound-wave / pulse, not coin columns or a plain thin line+area.
/// Soft glow on peaks, thin center stroke, faint axes, MAX callout.
class PulseRibbonChart extends StatefulWidget {
  const PulseRibbonChart({
    super.key,
    required this.series,
    this.height = 220,
    this.onBucketTap,
  });

  final List<(DateTime bucketStart, double spend)> series;
  final double height;

  /// Fired when the user taps a bucket that has spend > 0.
  final void Function(DateTime bucketStart, double spend)? onBucketTap;

  @override
  State<PulseRibbonChart> createState() => _PulseRibbonChartState();
}

class _PulseRibbonChartState extends State<PulseRibbonChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _draw;
  late Animation<double> _progress;

  @override
  void initState() {
    super.initState();
    _draw = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 780),
    );
    _progress = CurvedAnimation(parent: _draw, curve: Curves.easeOutCubic);
    _draw.forward();
  }

  @override
  void didUpdateWidget(covariant PulseRibbonChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameSeries(oldWidget.series, widget.series)) {
      _draw
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _draw.dispose();
    super.dispose();
  }

  static bool _sameSeries(
    List<(DateTime, double)> a,
    List<(DateTime, double)> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].$1 != b[i].$1 || a[i].$2 != b[i].$2) return false;
    }
    return true;
  }

  void _handleTap(Offset local, Size size) {
    final onTap = widget.onBucketTap;
    if (onTap == null) return;
    final n = widget.series.length;
    if (n == 0) return;

    const padL = PulseRibbonChartPainter.padL;
    const padR = PulseRibbonChartPainter.padR;
    const padT = PulseRibbonChartPainter.padT;
    const padB = PulseRibbonChartPainter.padB;
    final plot = Rect.fromLTRB(
      padL,
      padT,
      size.width - padR,
      size.height - padB,
    );
    if (!plot.contains(local)) return;

    final slot = plot.width / n;
    final i = ((local.dx - plot.left) / slot).floor().clamp(0, n - 1);
    final amount = widget.series[i].$2;
    if (amount <= 0) return;
    HapticFeedback.selectionClick();
    onTap(widget.series[i].$1, amount);
  }

  @override
  Widget build(BuildContext context) {
    final peak = widget.series.fold<double>(0, (m, e) => e.$2 > m ? e.$2 : m);
    final hasSpend = peak > 0;

    return Semantics(
      label: hasSpend ? 'Pulse ribbon spend chart' : 'No spend in this range',
      child: SizedBox(
        key: const Key('pulse_ribbon_chart'),
        width: double.infinity,
        height: widget.height,
        child: hasSpend
            ? LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(constraints.maxWidth, widget.height);
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) => _handleTap(d.localPosition, size),
                    child: AnimatedBuilder(
                      animation: _progress,
                      builder: (context, _) {
                        return CustomPaint(
                          painter: PulseRibbonChartPainter(
                            series: widget.series,
                            peak: peak,
                            progress: _progress.value,
                          ),
                        );
                      },
                    ),
                  );
                },
              )
            : const _PulseRibbonEmptyState(),
      ),
    );
  }
}

class _PulseRibbonEmptyState extends StatelessWidget {
  const _PulseRibbonEmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('pulse_ribbon_chart_empty'),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PaisaColors.border, width: 1.2),
        color: PaisaColors.card.withOpacity(0.55),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.monitor_heart_outlined,
            size: 28,
            color: PaisaColors.muted.withOpacity(0.85),
          ),
          const SizedBox(height: 10),
          Text(
            'No spend in this range',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: PaisaColors.mutedCaption.withOpacity(0.95),
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }
}

class PulseRibbonChartPainter extends CustomPainter {
  PulseRibbonChartPainter({
    required this.series,
    required this.peak,
    required this.progress,
  });

  final List<(DateTime bucketStart, double spend)> series;
  final double peak;
  final double progress;

  static const padL = 44.0;
  static const padR = 12.0;
  static const padT = 22.0;
  static const padB = 28.0;

  /// Half-thickness of the ribbon at peak spend (px).
  static const _maxHalf = 14.0;
  static const _minHalf = 2.2;

  @override
  void paint(Canvas canvas, Size size) {
    final n = series.length;
    if (n == 0 || peak <= 0) return;

    final plot = Rect.fromLTRB(
      padL,
      padT,
      size.width - padR,
      size.height - padB,
    );
    if (plot.width <= 0 || plot.height <= 0) return;

    final yMax = _niceMax(peak);
    _drawAxes(canvas, plot);
    _drawYLabels(canvas, plot, yMax);
    _drawXLabels(canvas, plot, size);

    final t = progress.clamp(0.0, 1.0);
    if (t < 0.02) return;

    final slot = plot.width / n;
    final centers = <Offset>[];
    final halves = <double>[];
    var maxIdx = 0;

    for (var i = 0; i < n; i++) {
      final amount = series[i].$2;
      if (amount > series[maxIdx].$2) maxIdx = i;
      final cx = plot.left + (i + 0.5) * slot;
      final ratio = (amount / yMax).clamp(0.0, 1.0);
      // Leave headroom so ribbon thickness doesn't clip the top.
      final usableH = plot.height - _maxHalf * 2;
      final cy = plot.bottom - ratio * usableH * t - _minHalf;
      centers.add(Offset(cx, cy));
      final half = amount <= 0
          ? _minHalf * 0.4 * t
          : (_minHalf + (ratio * (_maxHalf - _minHalf))) * t;
      halves.add(half);
    }

    _drawRibbonBand(canvas, centers, halves, t);
    _drawCenterStroke(canvas, centers, t);

    if (t > 0.55) {
      final markerAlpha = ((t - 0.55) / 0.45).clamp(0.0, 1.0);
      _drawPeakGlow(canvas, centers[maxIdx], markerAlpha);
      _drawMaxCallout(
        canvas,
        size,
        plot,
        centers[maxIdx],
        series[maxIdx].$2,
        markerAlpha,
      );
    }
  }

  void _drawRibbonBand(
    Canvas canvas,
    List<Offset> centers,
    List<double> halves,
    double t,
  ) {
    final n = centers.length;
    if (n == 0) return;

    final top = <Offset>[];
    final bot = <Offset>[];
    for (var i = 0; i < n; i++) {
      top.add(Offset(centers[i].dx, centers[i].dy - halves[i]));
      bot.add(Offset(centers[i].dx, centers[i].dy + halves[i]));
    }

    final band = Path()..moveTo(top.first.dx, top.first.dy);
    _smoothThrough(band, top);
    band.lineTo(bot.last.dx, bot.last.dy);
    for (var i = n - 2; i >= 0; i--) {
      final p0 = bot[i + 1];
      final p1 = bot[i];
      final mid = Offset((p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2);
      band.quadraticBezierTo(p0.dx, p0.dy, mid.dx, mid.dy);
    }
    band.close();

    // Soft under-glow.
    canvas.drawPath(
      band,
      Paint()
        ..style = PaintingStyle.fill
        ..color = PaisaColors.safe.withOpacity(0.14 * t)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );

    final bounds = band.getBounds();
    canvas.drawPath(
      band,
      Paint()
        ..style = PaintingStyle.fill
        ..shader = ui.Gradient.linear(
          Offset(bounds.center.dx, bounds.top),
          Offset(bounds.center.dx, bounds.bottom),
          [
            PaisaColors.primary.withOpacity(0.55 * t),
            Color.lerp(PaisaColors.safe, PaisaColors.primary, 0.45)!
                .withOpacity(0.38 * t),
            PaisaColors.safe.withOpacity(0.18 * t),
          ],
          const [0.0, 0.45, 1.0],
        ),
    );

    // Brighter emerald bloom on high-spend peaks.
    for (var i = 0; i < n; i++) {
      final intensity = (series[i].$2 / peak).clamp(0.0, 1.0);
      if (intensity < 0.5 || halves[i] < 3) continue;
      canvas.drawOval(
        Rect.fromCenter(
          center: centers[i],
          width: halves[i] * 3.2,
          height: halves[i] * 2.4,
        ),
        Paint()
          ..color = PaisaColors.primary.withOpacity(0.10 + 0.28 * intensity * t)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 5 + 6 * intensity),
      );
    }

    canvas.drawPath(
      band,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..strokeJoin = StrokeJoin.round
        ..color = Color.lerp(PaisaColors.safe, PaisaColors.primary, 0.4)!
            .withOpacity(0.6 * t),
    );
  }

  void _drawCenterStroke(Canvas canvas, List<Offset> centers, double t) {
    if (centers.length < 2) return;
    final stroke = Path()..moveTo(centers.first.dx, centers.first.dy);
    _smoothThrough(stroke, centers);

    canvas.drawPath(
      stroke,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = PaisaColors.ink.withOpacity(0.2 * t),
    );
    canvas.drawPath(
      stroke,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Color.lerp(PaisaColors.primary, PaisaColors.ink, 0.15)!
            .withOpacity(0.65 + 0.3 * t),
    );
  }

  static void _smoothThrough(Path path, List<Offset> pts) {
    if (pts.length < 2) return;
    if (pts.length == 2) {
      path.lineTo(pts[1].dx, pts[1].dy);
      return;
    }
    for (var i = 0; i < pts.length - 1; i++) {
      final p0 = pts[i];
      final p1 = pts[i + 1];
      final mid = Offset((p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2);
      if (i == 0) {
        path.lineTo(mid.dx, mid.dy);
      } else {
        path.quadraticBezierTo(p0.dx, p0.dy, mid.dx, mid.dy);
      }
    }
    path.lineTo(pts.last.dx, pts.last.dy);
  }

  void _drawAxes(Canvas canvas, Rect plot) {
    const hLines = 4;
    for (var i = 0; i <= hLines; i++) {
      final y = plot.bottom - (i / hLines) * plot.height;
      final isBase = i == 0;
      canvas.drawLine(
        Offset(plot.left, y),
        Offset(plot.right, y),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isBase ? 1.25 : 0.75
          ..color = PaisaColors.ink.withOpacity(isBase ? 0.4 : 0.1),
      );
    }

    canvas.drawLine(
      Offset(plot.left, plot.top),
      Offset(plot.left, plot.bottom),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.25
        ..color = PaisaColors.ink.withOpacity(0.5),
    );
  }

  void _drawYLabels(Canvas canvas, Rect plot, double yMax) {
    const ticks = 4;
    for (var i = 0; i <= ticks; i++) {
      final value = yMax * (i / ticks);
      final y = plot.bottom - (i / ticks) * plot.height;
      final tp = TextPainter(
        text: TextSpan(
          text: _shortInr(value),
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            color: PaisaColors.mutedCaption.withOpacity(0.95),
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout(maxWidth: padL - 6);
      tp.paint(
        canvas,
        Offset(plot.left - tp.width - 6, y - tp.height / 2),
      );
    }
  }

  void _drawXLabels(Canvas canvas, Rect plot, Size size) {
    final n = series.length;
    if (n == 0) return;

    final indices = _xLabelIndices(n);
    final daySpan = series.last.$1.difference(series.first.$1).inDays.abs();
    final fmt = _xDateFormat(daySpan, n);
    final slot = plot.width / n;

    for (final i in indices) {
      final x = plot.left + (i + 0.5) * slot;
      final label = fmt.format(series[i].$1);
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            color: PaisaColors.mutedCaption.withOpacity(0.95),
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      var ox = x - tp.width / 2;
      ox = ox.clamp(2.0, size.width - tp.width - 2);
      tp.paint(canvas, Offset(ox, plot.bottom + 8));
    }
  }

  static List<int> _xLabelIndices(int n) {
    if (n <= 1) return [0];
    if (n == 2) return [0, 1];
    if (n <= 5) return List.generate(n, (i) => i);
    if (n <= 12) {
      return [0, n ~/ 3, (2 * n) ~/ 3, n - 1];
    }
    return [0, n ~/ 4, n ~/ 2, (3 * n) ~/ 4, n - 1];
  }

  static DateFormat _xDateFormat(int daySpan, int n) {
    if (daySpan <= 62 || n <= 62) {
      return DateFormat('d MMM');
    }
    if (daySpan <= 400) {
      return DateFormat('d MMM');
    }
    return DateFormat('MMM yy');
  }

  static double _niceMax(double peak) {
    if (peak <= 0) return 1;
    final exp = (math.log(peak) / math.ln10).floor();
    final mag = math.pow(10.0, exp).toDouble();
    final norm = peak / mag;
    double nice;
    if (norm <= 1) {
      nice = 1;
    } else if (norm <= 2) {
      nice = 2;
    } else if (norm <= 5) {
      nice = 5;
    } else {
      nice = 10;
    }
    return nice * mag;
  }

  void _drawPeakGlow(
    Canvas canvas,
    Offset at,
    double alpha,
  ) {
    canvas.drawCircle(
      at,
      11,
      Paint()
        ..color = PaisaColors.primary.withOpacity(0.2 * alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
    );
    canvas.drawCircle(
      at,
      4.4,
      Paint()..color = PaisaColors.primary.withOpacity(0.95 * alpha),
    );
    canvas.drawCircle(
      at,
      4.4,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = PaisaColors.ink.withOpacity(0.5 * alpha),
    );
    canvas.drawCircle(
      at,
      1.5,
      Paint()..color = PaisaColors.inkOnAccent.withOpacity(0.7 * alpha),
    );
  }

  void _drawMaxCallout(
    Canvas canvas,
    Size size,
    Rect plot,
    Offset at,
    double amount,
    double alpha,
  ) {
    final label = 'MAX ${_shortInr(amount)}';
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontFamily: 'Sora',
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
          color: PaisaColors.primary.withOpacity(0.95 * alpha),
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();

    const pad = Offset(6, 4);
    final boxSize = Size(tp.width + pad.dx * 2, tp.height + pad.dy * 2);
    var origin = at + Offset(8, -boxSize.height - 10);
    if (origin.dy < plot.top - 4) {
      origin = at + const Offset(8, 12);
    }
    origin = Offset(
      origin.dx.clamp(2.0, math.max(2.0, size.width - boxSize.width - 2)),
      origin.dy.clamp(2.0, math.max(2.0, size.height - boxSize.height - 2)),
    );

    final rrect = RRect.fromRectAndRadius(
      origin & boxSize,
      const Radius.circular(6),
    );
    canvas.drawRRect(
      rrect,
      Paint()..color = PaisaColors.cardElevated.withOpacity(0.92 * alpha),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = PaisaColors.primary.withOpacity(0.35 * alpha),
    );
    tp.paint(canvas, origin + pad);
  }

  static String _shortInr(double amount) {
    final a = amount.abs();
    if (a >= 10000000) {
      return '₹${(a / 10000000).toStringAsFixed(a >= 100000000 ? 0 : 1)}Cr';
    }
    if (a >= 100000) {
      return '₹${(a / 100000).toStringAsFixed(a >= 1000000 ? 0 : 1)}L';
    }
    if (a >= 1000) {
      return '₹${(a / 1000).toStringAsFixed(a >= 10000 ? 0 : 1)}k';
    }
    if (a == 0) return '₹0';
    if (a == a.roundToDouble()) return '₹${a.toInt()}';
    return formatInr(amount);
  }

  @override
  bool shouldRepaint(covariant PulseRibbonChartPainter oldDelegate) {
    return oldDelegate.peak != peak ||
        oldDelegate.progress != progress ||
        oldDelegate.series.length != series.length ||
        !_sameSeries(oldDelegate.series, series);
  }

  static bool _sameSeries(
    List<(DateTime, double)> a,
    List<(DateTime, double)> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].$1 != b[i].$1 || a[i].$2 != b[i].$2) return false;
    }
    return true;
  }
}
