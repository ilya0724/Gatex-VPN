import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/vpn_core.dart';
import 'theme.dart';

Future<void> openLink(String url) =>
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

/// Country flag. Windows has no flag emoji, so desktop shows the code.
class FlagBadge extends StatelessWidget {
  const FlagBadge({super.key, required this.flag, this.size = 40});
  final String flag;
  final double size;

  @override
  Widget build(BuildContext context) {
    final code = String.fromCharCodes(
      flag.runes.map((r) => r - 0x1F1E6 + 0x41),
    );
    final emoji = Platform.isAndroid && flag.isNotEmpty;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: GX.glassStrong,
        borderRadius: BorderRadius.circular(size / 2),
        border: Border.all(color: GX.line),
      ),
      child: emoji
          ? Text(flag, style: TextStyle(fontSize: size * 0.5))
          : flag.isEmpty
          ? Icon(Icons.public, size: size * 0.5, color: GX.muted)
          : Text(code, style: body(size * 0.32, weight: 800, color: GX.accent)),
    );
  }
}

class DelayChip extends StatelessWidget {
  const DelayChip({super.key, required this.tested, this.ms});
  final bool tested;
  final int? ms;

  @override
  Widget build(BuildContext context) {
    if (!tested) return const SizedBox.shrink();
    final color = ms == null
        ? GX.danger
        : ms! < 300
        ? GX.accent
        : ms! < 800
        ? GX.warn
        : GX.danger;
    return Text(
      ms == null ? 'нет ответа' : '$ms мс',
      style: body(13, weight: 700, color: color),
    );
  }
}

/// The big round button in the middle of the home screen.
class ConnectButton extends StatefulWidget {
  const ConnectButton({super.key, required this.state, required this.onTap});
  final VpnState state;
  final VoidCallback onTap;

  @override
  State<ConnectButton> createState() => _ConnectButtonState();
}

class _ConnectButtonState extends State<ConnectButton>
    with SingleTickerProviderStateMixin {
  late final _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  bool get _busy =>
      widget.state == VpnState.connecting ||
      widget.state == VpnState.disconnecting;

  @override
  void initState() {
    super.initState();
    if (_busy) _spin.repeat();
  }

  @override
  void didUpdateWidget(ConnectButton old) {
    super.didUpdateWidget(old);
    if (_busy && !_spin.isAnimating) _spin.repeat();
    if (!_busy && _spin.isAnimating) _spin.stop();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final on = widget.state == VpnState.connected;
    const size = 196.0;
    return Semantics(
      button: true,
      label: on ? 'Отключить VPN' : 'Подключить VPN',
      child: GestureDetector(
        onTap: widget.onTap,
        child: SizedBox(
          width: size + 48,
          height: size + 48,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                width: size + 40,
                height: size + 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: GX.accent.withValues(alpha: on ? 0.35 : 0.08),
                      blurRadius: on ? 60 : 30,
                      spreadRadius: on ? 6 : 0,
                    ),
                  ],
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: on
                      ? const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF6DFACB), GX.accent2],
                        )
                      : null,
                  color: on ? null : GX.glass,
                  border: Border.all(
                    color: on
                        ? Colors.transparent
                        : GX.accent.withValues(alpha: 0.5),
                    width: 2,
                  ),
                ),
                child: Icon(
                  Icons.power_settings_new_rounded,
                  size: 72,
                  color: on ? GX.accentInk : GX.accent,
                ),
              ),
              if (_busy)
                AnimatedBuilder(
                  animation: _spin,
                  builder: (_, _) => Transform.rotate(
                    angle: _spin.value * 2 * pi,
                    child: SizedBox(
                      width: size + 20,
                      height: size + 20,
                      child: const CircularProgressIndicator(
                        value: 0.28,
                        strokeWidth: 3,
                        strokeCap: StrokeCap.round,
                        color: GX.accent,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
