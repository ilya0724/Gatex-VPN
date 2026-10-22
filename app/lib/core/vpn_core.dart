import 'dart:async';
import 'dart:io';

import 'android_core.dart';
import 'config_builder.dart';
import 'desktop_core.dart';

enum VpnState { disconnected, connecting, connected, disconnecting }

class VpnStatus {
  const VpnStatus(this.state, [this.error]);
  final VpnState state;

  /// Set when the core stopped on its own or failed to start.
  final String? error;
}

/// A delay test result: the round trip in ms, or why it failed.
class DelayResult {
  const DelayResult.ok(int this.ms) : error = null;
  const DelayResult.failed(String this.error) : ms = null;
  final int? ms;
  final String? error;
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
  Future<String?> start(String configJson);

  Future<void> stop();

  /// Round trip through [configJson]'s proxy to [probeUrl].
  Future<DelayResult> measureDelay(String configJson, {int timeoutMs});

  Future<String> coreVersion();
}
