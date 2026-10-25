import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Compact, polished loading spinner: a rounded arc that fades from
/// transparent into [color] (defaults to the theme's primary) with a soft
/// glowing head, rotating over a faint track. Always square at [size], so it
/// can't be stretched into an oval by a loosely constrained parent the way a
/// bare [CircularProgressIndicator] can.
class GradientSpinner extends StatefulWidget {
  final double size;
  final double strokeWidth;
  final Color? color;

  const GradientSpinner({
    super.key,
    this.size = 28,
    this.strokeWidth = 3,
    this.color,
  });

  @override
  State<GradientSpinner> createState() => _GradientSpinnerState();
}

class _GradientSpinnerState extends State<GradientSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;

    return Semantics(
      label: 'Loading',
      child: SizedBox.square(
        dimension: widget.size,
        child: RotationTransition(
          turns: _controller,
          child: CustomPaint(
            painter: _GradientSpinnerPainter(
              color: color,
              strokeWidth: widget.strokeWidth,
            ),
          ),
        ),
      ),
    );
  }
}

class _GradientSpinnerPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  // Arc length as a fraction of the full circle - long enough to read as a
  // sweeping tail, short enough to leave a visible gap.
  static const double _sweepFraction = 0.78;

  _GradientSpinnerPainter({required this.color, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = color.withValues(alpha: 0.12);
    canvas.drawCircle(center, radius, track);

    const startAngle = -math.pi / 2;
    final sweepAngle = 2 * math.pi * _sweepFraction;

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: sweepAngle,
        colors: [color.withValues(alpha: 0), color],
        transform: const GradientRotation(startAngle),
      ).createShader(rect);
    canvas.drawArc(rect, startAngle, sweepAngle, false, arc);

    // Glowing head at the leading end of the arc.
    final headAngle = startAngle + sweepAngle;
    final head = center +
        Offset(math.cos(headAngle), math.sin(headAngle)) * radius;
    canvas.drawCircle(
      head,
      strokeWidth * 1.3,
      Paint()
        ..color = color.withValues(alpha: 0.35)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, strokeWidth),
    );
    canvas.drawCircle(head, strokeWidth / 2, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_GradientSpinnerPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}
