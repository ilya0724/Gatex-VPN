import 'dart:math';

import 'package:flutter/material.dart';

import 'theme.dart';

/// The launch animation: the GX mark grows in, a mint ring draws around
/// it, the name appears, and the whole thing lifts away to the app.
class IntroOverlay extends StatefulWidget {
  const IntroOverlay({super.key});

  /// When screens start their own entrance: as the intro clears.
  static const handoff = Duration(milliseconds: 1250);
  static DateTime? _startedAt;

  /// How long a screen built now should wait before animating in.
  static Duration get wait {
    final start = _startedAt;
    if (start == null) return handoff + const Duration(milliseconds: 250);
    final left = handoff - DateTime.now().difference(start);
    return left.isNegative ? Duration.zero : left;
  }

  @override
  State<IntroOverlay> createState() => _IntroOverlayState();
}

class _IntroOverlayState extends State<IntroOverlay>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  );
  bool _done = false;

  @override
  void initState() {
    super.initState();
    // Start once the window is up and drawing smoothly, not during the
    // first heavy frames, or the start of the animation is skipped.
    WidgetsBinding.instance.endOfFrame.then((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (!mounted) return;
      IntroOverlay._startedAt = DateTime.now();
      await _c.forward();
      if (mounted) setState(() => _done = true);
    });
  }

  Animation<double> _part(
    double a,
    double b, [
    Curve curve = Curves.easeOutCubic,
  ]) => CurvedAnimation(
    parent: _c,
    curve: Interval(a, b, curve: curve),
  );

  late final _logo = _part(0, 0.42, Curves.easeOutBack);
  late final _ring = _part(0.12, 0.62, Curves.easeInOutCubic);
  late final _word = _part(0.38, 0.62);
  late final _out = _part(0.72, 1, Curves.easeInCubic);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return const SizedBox.shrink();
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final out = _out.value;
          return Opacity(
            opacity: 1 - out,
            child: ColoredBox(
              color: GX.bg,
              child: Center(
                child: Transform.scale(
                  scale: 1 + 0.12 * out,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 168,
                        height: 168,
                        child: CustomPaint(
                          painter: _RingPainter(_ring.value),
                          child: Center(
                            child: Opacity(
                              opacity: _logo.value.clamp(0, 1),
                              child: Transform.scale(
                                scale: 0.6 + 0.4 * _logo.value,
                                child: Container(
                                  decoration: BoxDecoration(
                                    boxShadow: [
                                      BoxShadow(
                                        color: GX.accent.withValues(
                                          alpha: 0.35 * _ring.value,
                                        ),
                                        blurRadius: 50,
                                        spreadRadius: 4,
                                      ),
                                    ],
                                  ),
                                  child: Image.asset(
                                    'assets/images/mark.png',
                                    width: 96,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Opacity(
                        opacity: _word.value,
                        child: Transform.translate(
                          offset: Offset(0, 10 * (1 - _word.value)),
                          child: Column(
                            children: [
                              Text('GateX', style: display(26)),
                              const SizedBox(height: 6),
                              Text(
                                'Интернет без стен',
                                style: body(13, color: GX.muted),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0) return;
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 4;
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = GX.line.withValues(alpha: 0.12 * t),
    );
    canvas.drawArc(
      rect,
      -pi / 2,
      2 * pi * t,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          colors: const [Color(0x002EE6A6), GX.accent, Color(0xFF7CFBD2)],
          stops: const [0, 0.7, 1],
          transform: const GradientRotation(-pi / 2),
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.t != t;
}
