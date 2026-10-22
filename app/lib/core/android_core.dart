import 'dart:async';

import 'package:flutter/services.dart';

import 'config_builder.dart';
import 'vpn_core.dart';

/// Talks to GatexVpnService (android/app/src/main/kotlin), which owns the
/// TUN and runs Xray from the gatexcore library.
class AndroidCore implements VpnCore {
  static const _methods = MethodChannel('gatex/core');
  static const _events = EventChannel('gatex/core/status');

  @override
  TunHost get tunHost => TunHost.android;

  @override
  late final Stream<VpnStatus> status = _events
      .receiveBroadcastStream()
      .map((e) => _decode(e as Map))
      .asBroadcastStream();

  static VpnStatus _decode(Map e) {
    final state = switch (e['state']) {
      'connecting' => VpnState.connecting,
      'connected' => VpnState.connected,
      'disconnecting' => VpnState.disconnecting,
      _ => VpnState.disconnected,
    };
    return VpnStatus(state, e['error'] as String?);
  }

  @override
  Future<bool> prepare() async =>
      await _methods.invokeMethod<bool>('prepare') ?? false;

  @override
  Future<String?> start(String configJson) async {
    try {
      await _methods.invokeMethod('start', {'config': configJson});
      return null;
    } on PlatformException catch (e) {
      return e.message ?? e.code;
    }
  }

  @override
  Future<void> stop() => _methods.invokeMethod('stop');

  @override
  Future<int?> measureDelay(String configJson) async {
    final ms = await _methods.invokeMethod<int>('delay', {
      'config': configJson,
      'url': probeUrl,
      'timeout': 5000,
    });
    return ms == null || ms < 0 ? null : ms;
  }

  @override
  Future<String> coreVersion() async =>
      await _methods.invokeMethod<String>('version') ?? '';
}
