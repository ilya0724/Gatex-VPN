import 'dart:math';

import 'package:flutter/material.dart';

import 'theme.dart';

/// The app's background: dark green with slow mint "aurora" light. It
/// brightens when the VPN is on, and stops animating while the window is
/// hidden so the app costs nothing in the tray.
class Aurora extends StatefulWidget {
  const Aurora({super.key, required this.active});
  final bool active;

  @override
  State<Aurora> createState() => _AuroraState();
}

class _AuroraState extends State<Aurora> with TickerProviderStateMixin {
  late final _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 28),
  )..repeat();
  late final _glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
    value: widget.active ? 1 : 0,
  );
  late final AppLifecycleListener _life;

  @override
  void initState() {
    super.initState();
    _life = AppLifecycleListener(
      onStateChange: (s) {
        if (s == AppLifecycleState.resumed || s == AppLifecycleState.inactive) {
          if (!_drift.isAnimating) _drift.repeat();
        } else {
          _drift.stop();
        }
      },
    );
  }

  @override
  void didUpdateWidget(Aurora old) {
    super.didUpdateWidget(old);
    if (widget.active != old.active) {
      widget.active ? _glow.forward() : _glow.reverse();
    }
  }

  @override
  void dispose() {
    _life.dispose();
    _drift.dispose();
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _AuroraPainter(
          _drift,
          CurvedAnimation(parent: _glow, curve: Curves.easeInOut),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter(this.drift, this.glow)
    : super(repaint: Listenable.merge([drift, glow]));
  final Animation<double> drift;
  final Animation<double> glow;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [GX.bg2, GX.bg],
        ).createShader(rect),
    );

    final t = drift.value * 2 * pi;
    final g = glow.value;
    final d = size.longestSide;
    void blob(Offset c, double r, Color color, double alpha) {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: alpha),
              color.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }

    final glowColors = GX.p.glow;
    final k = GX.p.light ? 2.4 : 1.0;
    blob(
      Offset(
        size.width * (0.15 + 0.12 * sin(t)),
        size.height * (0.02 + 0.06 * cos(t * 2)),
      ),
      d * (0.55 + 0.05 * sin(t * 3)),
      glowColors[0],
      (0.16 + 0.10 * g) * k,
    );
    blob(
      Offset(
        size.width * (0.95 + 0.08 * cos(t)),
        size.height * (0.38 + 0.08 * sin(t * 2)),
      ),
      d * 0.42,
      glowColors[1],
      (0.06 + 0.06 * g) * k,
    );
    blob(
      Offset(
        size.width * (0.35 + 0.15 * sin(t + 2)),
        size.height * (1.02 + 0.04 * cos(t)),
      ),
      d * 0.5,
      glowColors[2],
      (0.07 + 0.09 * g) * k,
    );

    // Slow specks of light drifting up, brighter while connected.
    final dot = Paint();
    for (final m in _motes) {
      final y = (m.y - drift.value * m.speed) % 1.0;
      final x = m.x + 0.012 * sin(t * 3 + m.phase);
      final twinkle = 0.5 + 0.5 * sin(t * 7 + m.phase);
      dot.color = GX.accent.withValues(
        alpha: (0.10 + 0.25 * g) * twinkle * (GX.p.light ? 0.8 : 1),
      );
      canvas.drawCircle(Offset(x * size.width, y * size.height), m.r, dot);
    }
  }

  static final _motes = () {
    final r = Random(7);
    return [
      for (var i = 0; i < 36; i++)
        (
          x: r.nextDouble(),
          y: r.nextDouble(),
          r: 0.6 + r.nextDouble() * 1.4,
          speed: 1.0 + r.nextInt(3).toDouble(),
          phase: r.nextDouble() * 2 * pi,
        ),
    ];
  }();

  @override
  bool shouldRepaint(_AuroraPainter old) => false;
}
