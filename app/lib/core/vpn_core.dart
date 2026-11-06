import 'dart:async';
import 'dart:io';

import 'android_core.dart';
import '../routing/routing_settings.dart';
import 'config_builder.dart';
import 'desktop_core.dart';

enum VpnState { disconnected, connecting, connected, disconnecting }

class VpnStatus {
  const VpnStatus(this.state, [this.error, this.reconnecting = false]);
  final VpnState state;

  /// Set when the core stopped on its own or failed to start.
  final String? error;

  /// Android: the service restarts the core after a network change.
  final bool reconnecting;
}

/// A delay test result: the round trip in ms, or why it failed.
class DelayResult {
  const DelayResult.ok(int this.ms) : error = null;
  const DelayResult.failed(String this.error) : ms = null;
  final int? ms;
  final String? error;
}

/// "up down" from the core's Traffic().
(int, int)? parseTraffic(String? text) {
  final parts = text?.trim().split(' ') ?? const [];
  if (parts.length != 2) return null;
  final up = int.tryParse(parts[0]), down = int.tryParse(parts[1]);
  return up == null || down == null ? null : (up, down);
}

/// The platform side that runs Xray: a library inside an Android
/// VpnService, or the gatex-core helper process on desktop.
abstract class VpnCore {
  static VpnCore create() => Platform.isAndroid ? AndroidCore() : DesktopCore();

  TunHost get tunHost;

  Stream<VpnStatus> get status;

  /// Asks the OS for permission to run a VPN where that is needed.
  /// Returns false when the user declines.
  Future<bool> prepare();

  /// Starts the tunnel. Returns the core's error text when it could not
  /// start, null otherwise. Later failures arrive through [status].
  ///
  /// [mode] and [apps] (package names) are the Android per-app VPN; desktop
  /// ignores them, its per-app rules are process rules in the config.
  Future<String?> start(
    String configJson, {
    AppsMode mode = AppsMode.all,
    List<String> apps = const [],
  });

  Future<void> stop();

  /// Round trip through [configJson]'s proxy to [probeUrl].
  Future<DelayResult> measureDelay(String configJson, {int timeoutMs});

  Future<String> coreVersion();

  /// Bytes up and down through the tunnel since it started, null when off.
  Future<(int, int)?> traffic();

  /// GETs [url] the way the tunnel routes it. Null when that fails.
  Future<String?> fetch(String url);
}
