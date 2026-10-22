import 'dart:math';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/vpn_core.dart';
import 'motion.dart';
import 'theme.dart';

Future<void> openLink(String url) =>
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

/// 950 Б, 12,4 КБ, 3,1 МБ, 1,25 ГБ.
String formatBytes(num bytes) {
  const units = ['Б', 'КБ', 'МБ', 'ГБ', 'ТБ'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  final digits = i == 0 || v >= 100 ? 0 : (v >= 10 ? 1 : 2);
  return '${v.toStringAsFixed(digits).replaceAll('.', ',')} ${units[i]}';
}

Color delayColor(int ms) => ms < 300
    ? GX.accent
    : ms < 800
    ? GX.warn
    : Color(0xFFFF8A5B);

/// Signal-style bars plus the delay in ms, or a red "no answer".
class PingIndicator extends StatelessWidget {
  const PingIndicator({
    super.key,
    required this.tested,
    this.ms,
    this.testing = false,
    this.queued = false,
  });
  final bool tested;
  final int? ms;

  /// This server is being tested now / waits for its turn.
  final bool testing;
  final bool queued;

  @override
  Widget build(BuildContext context) {
    if (!tested) {
      if (testing) {
        return SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2, color: GX.muted),
        );
      }
      return queued
          ? Text('в очереди', style: body(12, color: GX.muted))
          : SizedBox.shrink();
    }
    final value = ms;
    final color = value == null ? GX.danger : delayColor(value);
    final level = value == null
        ? 0
        : value < 300
        ? 4
        : value < 600
        ? 3
        : value < 1200
        ? 2
        : 1;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value == null ? 'нет ответа' : '$value мс',
          style: body(
            12.5,
            weight: 700,
            color: color,
          ).copyWith(fontFeatures: [FontFeature.tabularFigures()]),
        ),
        SizedBox(width: 8),
        for (var i = 0; i < 4; i++)
          AnimatedContainer(
            duration: Duration(milliseconds: 250 + i * 60),
            margin: EdgeInsets.only(left: 2),
            width: 3.5,
            height: 5.0 + i * 3,
            decoration: BoxDecoration(
              color: i < level ? color : GX.line,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
      ],
    );
  }
}

class TagChip extends StatelessWidget {
  const TagChip(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? GX.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(text, style: body(10.5, weight: 800, color: color)),
    );
  }
}

/// The "Авто" icon: a bolt in a mint circle.
class AutoBadge extends StatelessWidget {
  const AutoBadge({super.key, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            GX.accent.withValues(alpha: 0.33),
            GX.accent2.withValues(alpha: 0.08),
          ],
        ),
        border: Border.all(color: GX.accent.withValues(alpha: 0.4)),
      ),
      child: Icon(Icons.bolt_rounded, color: GX.accent, size: size * 0.55),
    );
  }
}

/// The big round button in the middle of the home screen. Rings ripple
/// out while connected; an arc runs around it while connecting.
class ConnectButton extends StatefulWidget {
  const ConnectButton({
    super.key,
    required this.state,
    required this.onTap,
    this.size = 188,
  });
  final VpnState state;
  final VoidCallback onTap;
  final double size;

  @override
  State<ConnectButton> createState() => _ConnectButtonState();
}

class _ConnectButtonState extends State<ConnectButton>
    with TickerProviderStateMixin {
  late final _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  late final _ripple = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  );
  late final _on = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );

  /// One flash of light the moment the tunnel comes up.
  late final _flash = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  bool _wasConnected = false;

  bool get _busy =>
      widget.state == VpnState.connecting ||
      widget.state == VpnState.disconnecting;
  bool get _connected => widget.state == VpnState.connected;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(ConnectButton old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (_busy) {
      if (!_spin.isAnimating) _spin.repeat();
    } else {
      _spin.stop();
    }
    if (_connected && !_wasConnected) _flash.forward(from: 0);
    _wasConnected = _connected;
    if (_connected) {
      if (!_ripple.isAnimating) _ripple.repeat();
      _on.forward();
    } else {
      _ripple.stop();
      _ripple.value = 0;
      _on.reverse();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    _ripple.dispose();
    _on.dispose();
    _flash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final on = CurvedAnimation(parent: _on, curve: Curves.easeInOutCubic);
    return Semantics(
      button: true,
      label: _connected ? 'Отключить VPN' : 'Подключить VPN',
      child: PressScale(
        onTap: widget.onTap,
        child: SizedBox(
          width: size + 120,
          height: size + 120,
          child: AnimatedBuilder(
            animation: Listenable.merge([_spin, _ripple, on, _flash]),
            builder: (context, _) {
              final t = on.value;
              return CustomPaint(
                painter: _RingsPainter(
                  core: size / 2,
                  ripple: _ripple.value,
                  ripplesOn: _connected,
                  spin: _busy ? _spin.value : null,
                  on: t,
                  flash: _flash.isAnimating ? _flash.value : 0,
                ),
                child: Center(
                  child: Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color.lerp(
                            GX.p.buttonOff[0],
                            GX.p.light
                                ? const Color(0xFF3FE0AE)
                                : const Color(0xFF7CFBD2),
                            t,
                          )!,
                          Color.lerp(GX.p.buttonOff[1], GX.accent2, t)!,
                        ],
                      ),
                      border: Border.all(
                        color: Color.lerp(
                          GX.accent.withValues(alpha: 0.45),
                          const Color(0x66FFFFFF),
                          t,
                        )!,
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: GX.accent.withValues(alpha: 0.12 + 0.33 * t),
                          blurRadius: 30 + 40 * t,
                          spreadRadius: 2 + 6 * t,
                        ),
                        BoxShadow(
                          color: GX.p.light
                              ? const Color(0x1F0D1F19)
                              : const Color(0x66000000),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.power_settings_new_rounded,
                      size: size * 0.36,
                      color: Color.lerp(GX.accent, GX.accentInk, t),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  _RingsPainter({
    required this.core,
    required this.ripple,
    required this.ripplesOn,
    required this.spin,
    required this.on,
    this.flash = 0,
  });
  final double flash;
  final double core;
  final double ripple;
  final bool ripplesOn;
  final double? spin;
  final double on;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final track = core + 16;

    if (flash > 0) {
      final e = Curves.easeOutCubic.transform(flash);
      final r = core + 120 * e;
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [
              GX.accent.withValues(alpha: 0.45 * (1 - flash)),
              GX.accent.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
      canvas.drawCircle(
        c,
        core + 8 + 90 * e,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 * (1 - flash) + 0.5
          ..color = GX.accent.withValues(alpha: 0.8 * (1 - flash)),
      );
    }

    if (ripplesOn) {
      for (var i = 0; i < 3; i++) {
        final p = (ripple + i / 3) % 1;
        final r = core + 6 + p * 54;
        canvas.drawCircle(
          c,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..color = GX.accent.withValues(alpha: 0.45 * (1 - p) * on),
        );
      }
    }

    canvas.drawCircle(
      c,
      track,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Color.lerp(GX.line, GX.accent.withValues(alpha: 0.5), on)!,
    );

    final s = spin;
    if (s != null) {
      final rect = Rect.fromCircle(center: c, radius: track);
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(s * 2 * pi);
      canvas.translate(-c.dx, -c.dy);
      canvas.drawArc(
        rect,
        0,
        pi * 0.9,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5
          ..strokeCap = StrokeCap.round
          ..shader = SweepGradient(
            endAngle: pi * 0.9,
            colors: [GX.accent.withValues(alpha: 0), GX.accent],
          ).createShader(rect),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) => true;
}
