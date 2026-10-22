import 'dart:async';
import 'dart:math';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme.dart';

/// The launch animation. A burst of light, the GX mark sharpens into
/// view inside a ring that draws itself with orbiting sparks, a shine
/// runs across the letters, the name types in, and then the ring blows
/// outward while the mark flies into its place in the app's header.
class IntroOverlay extends StatefulWidget {
  const IntroOverlay({super.key});

  static const _total = Duration(milliseconds: 2300);

  /// When screens start their own entrance: as the mark takes off.
  static const handoff = Duration(milliseconds: 1500);
  static DateTime? _startedAt;

  /// No intro this time: the last one never reached its end (the app was
  /// killed or the phone could not draw it), so it must not be in the way.
  static bool skip = false;
  static SharedPreferences? _prefs;
  static const _pendingKey = 'intro.pending';

  static Future<void> prepare(SharedPreferences prefs) async {
    _prefs = prefs;
    skip = prefs.getBool(_pendingKey) ?? false;
    if (skip) {
      finished.value = true;
    } else {
      await prefs.setBool(_pendingKey, true);
    }
  }

  /// How long a screen built now should wait before animating in.
  static Duration get wait {
    if (skip) return Duration.zero;
    final start = _startedAt;
    if (start == null) return handoff + const Duration(milliseconds: 250);
    final left = handoff - DateTime.now().difference(start);
    return left.isNegative ? Duration.zero : left;
  }

  /// The header logo the mark lands on. Screens attach it while the intro
  /// runs (see [markKeyIfFlying]) and keep their logo hidden until then.
  static final markKey = GlobalKey(debugLabel: 'intro-mark');
  static final finished = ValueNotifier(false);

  static Key? get markKeyIfFlying => finished.value ? null : markKey;

  @override
  State<IntroOverlay> createState() => _IntroOverlayState();
}

class _IntroOverlayState extends State<IntroOverlay>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: IntroOverlay._total,
  );
  bool _done = IntroOverlay.skip;
  Timer? _watchdog;

  /// The landing spot in this overlay's coordinates during the flight.
  Rect? _target;

  @override
  void initState() {
    super.initState();
    if (_done) return;
    _c.addListener(_maybeLockTarget);
    // Whatever happens to the animation, the app shows up.
    _watchdog = Timer(const Duration(seconds: 5), _finish);
    // Start once the window is up and drawing smoothly, not during the
    // first heavy frames, or the start of the animation is skipped.
    WidgetsBinding.instance.endOfFrame.then((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (!mounted) return;
      IntroOverlay._startedAt = DateTime.now();
      await _c.forward();
      // Played to the end, so it is safe to play next time too.
      unawaited(IntroOverlay._prefs?.setBool(IntroOverlay._pendingKey, false));
      _finish();
    });
  }

  void _finish() {
    _watchdog?.cancel();
    IntroOverlay.finished.value = true;
    if (mounted && !_done) setState(() => _done = true);
  }

  void _maybeLockTarget() {
    // Followed every frame: the header itself may still be sliding in.
    if (_c.value < _flightStart) return;
    final box =
        IntroOverlay.markKey.currentContext?.findRenderObject() as RenderBox?;
    final me = context.findRenderObject() as RenderBox?;
    if (box == null || me == null || !box.attached || !box.hasSize) return;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: me);
    _target = topLeft & box.size;
  }

  static const _flightStart = 0.64;

  Animation<double> _part(
    double a,
    double b, [
    Curve curve = Curves.easeOutCubic,
  ]) => CurvedAnimation(
    parent: _c,
    curve: Interval(a, b, curve: curve),
  );

  late final _burst = _part(0, 0.42, Curves.easeOutQuart);
  late final _logo = _part(0.04, 0.38, Curves.easeOutBack);
  late final _focus = _part(0.04, 0.34);
  late final _ring = _part(0.10, 0.52, Curves.easeInOutCubic);
  late final _shine = _part(0.34, 0.62, Curves.easeInOutSine);
  late final _word = _part(0.36, 0.62);
  late final _blast = _part(_flightStart, 0.92, Curves.easeOutCubic);
  late final _flight = _part(_flightStart, 0.96, Curves.easeInOutCubic);
  late final _fade = _part(0.70, 1, Curves.easeInOut);

  @override
  void dispose() {
    _watchdog?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return const SizedBox.shrink();
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, box) => AnimatedBuilder(
          animation: _c,
          builder: (context, _) => _frame(box.biggest),
        ),
      ),
    );
  }

  static const _logoWidth = 104.0;
  static const _ringSize = 176.0;

  Widget _frame(Size size) {
    final center = size.center(Offset.zero) - const Offset(0, 24);
    final fly = _flight.value;
    const logoHeight = _logoWidth * 261 / 600;

    // Where the mark is now: the centre of the screen, moving to the
    // header logo (or up and away when no screen is ready yet).
    final target = _target;
    final Offset logoCenter;
    final double logoScale;
    if (target != null) {
      logoCenter = Offset.lerp(center, target.center, fly)!;
      logoScale = 1 + (target.height / logoHeight - 1) * fly;
    } else {
      logoCenter = center - Offset(0, 80 * fly);
      logoScale = 1 - 0.3 * fly;
    }
    final logoOpacity =
        _logo.value.clamp(0.0, 1.0) * (target == null ? 1 - fly : 1);

    return Stack(
      children: [
        // The curtain: fades to show the app underneath.
        Positioned.fill(
          child: Opacity(
            opacity: 1 - _fade.value,
            child: ColoredBox(color: GX.bg),
          ),
        ),
        Positioned.fill(
          child: CustomPaint(
            painter: _BurstPainter(
              center: center,
              burst: _burst.value,
              ring: _ring.value,
              blast: _blast.value,
              fade: _fade.value,
              time: _c.value,
            ),
          ),
        ),
        // The name, under the mark.
        Positioned(
          left: 0,
          right: 0,
          top: center.dy + _ringSize / 2 + 14,
          child: Opacity(
            opacity: (1 - _blast.value * 1.6).clamp(0.0, 1.0),
            child: _Wordmark(progress: _word.value),
          ),
        ),
        Positioned(
          left: logoCenter.dx - _logoWidth / 2,
          top: logoCenter.dy - logoHeight / 2,
          width: _logoWidth,
          height: logoHeight,
          child: Transform.scale(
            scale: (0.55 + 0.45 * _logo.value) * logoScale,
            child: Opacity(
              opacity: logoOpacity.clamp(0.0, 1.0),
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(
                  sigmaX: 10 * (1 - _focus.value) + 0.001,
                  sigmaY: 10 * (1 - _focus.value) + 0.001,
                ),
                child: _Shine(
                  progress: _shine.value,
                  child: Image.asset(GX.mark, width: _logoWidth),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A band of light that sweeps across the logo once.
class _Shine extends StatelessWidget {
  const _Shine({required this.progress, required this.child});
  final double progress;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (progress <= 0 || progress >= 1) return child;
    return ShaderMask(
      blendMode: BlendMode.srcATop,
      shaderCallback: (rect) {
        final x = -0.5 + 2 * progress;
        return LinearGradient(
          begin: Alignment(-1 + 2 * (x - 0.25), -0.4),
          end: Alignment(-1 + 2 * (x + 0.25), 0.4),
          colors: const [
            Color(0x00FFFFFF),
            Color(0xCCFFFFFF),
            Color(0x00FFFFFF),
          ],
        ).createShader(rect);
      },
      child: child,
    );
  }
}

/// "GateX" with letters dropping in one by one, then the tagline.
class _Wordmark extends StatelessWidget {
  const _Wordmark({required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) {
    const word = 'GateX';
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < word.length; i++)
              Builder(
                builder: (context) {
                  final t = ((progress * 1.6 - i * 0.12) / 0.5).clamp(0.0, 1.0);
                  final e = Curves.easeOutBack.transform(t);
                  return Opacity(
                    opacity: t,
                    child: Transform.translate(
                      offset: Offset(0, 14 * (1 - e)),
                      child: Text(
                        word[i],
                        style: display(28, color: i == 4 ? GX.accent : GX.text),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
        const SizedBox(height: 8),
        Opacity(
          opacity: ((progress - 0.5) * 2).clamp(0.0, 1.0),
          child: Text(
            'Интернет без стен',
            style: body(13.5, color: GX.muted).copyWith(letterSpacing: 0.6),
          ),
        ),
      ],
    );
  }
}

/// The light burst, the ring with its sparks, and the shock ring on exit.
class _BurstPainter extends CustomPainter {
  _BurstPainter({
    required this.center,
    required this.burst,
    required this.ring,
    required this.blast,
    required this.fade,
    required this.time,
  });
  final Offset center;
  final double burst, ring, blast, fade, time;

  @override
  void paint(Canvas canvas, Size size) {
    final accent = GX.accent;
    final alive = 1 - fade;

    // Soft bloom behind the mark.
    final bloomR = 40 + 260 * burst;
    canvas.drawCircle(
      center,
      bloomR,
      Paint()
        ..shader = RadialGradient(
          colors: [
            accent.withValues(alpha: 0.30 * (1 - burst * 0.5) * alive),
            accent.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: bloomR)),
    );

    final r = _IntroOverlayState._ringSize / 2 + 70 * blast;
    final ringAlpha = (1 - blast).clamp(0.0, 1.0);
    if (ring > 0 && ringAlpha > 0) {
      final rect = Rect.fromCircle(center: center, radius: r);
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = GX.line.withValues(alpha: GX.line.a * ring * ringAlpha),
      );
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(-pi / 2);
      canvas.translate(-center.dx, -center.dy);
      canvas.drawArc(
        rect,
        0,
        2 * pi * ring,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 * (1 - blast * 0.7)
          ..strokeCap = StrokeCap.round
          ..shader = SweepGradient(
            colors: [
              accent.withValues(alpha: 0),
              accent.withValues(alpha: ringAlpha),
              const Color(0xFF9DFCE0).withValues(alpha: ringAlpha),
            ],
            stops: const [0, 0.75, 1],
          ).createShader(rect),
      );
      canvas.restore();

      // Three sparks riding the ring.
      for (var i = 0; i < 3; i++) {
        final a = -pi / 2 + 2 * pi * (time * 1.6 + i / 3);
        final p = center + Offset(cos(a), sin(a)) * r;
        final glow = Paint()
          ..color = accent.withValues(alpha: 0.9 * ring * ringAlpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
        canvas.drawCircle(p, 3.2, glow);
        canvas.drawCircle(
          p,
          1.6,
          Paint()..color = Colors.white.withValues(alpha: ring * ringAlpha),
        );
      }
    }

    // Shock wave when the mark takes off.
    if (blast > 0 && blast < 1) {
      canvas.drawCircle(
        center,
        _IntroOverlayState._ringSize / 2 + size.longestSide * 0.6 * blast,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 + 10 * (1 - blast)
          ..color = accent.withValues(alpha: 0.25 * (1 - blast)),
      );
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => true;
}
