import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';

import '../routing/routing_settings.dart';
import 'config_builder.dart';
import 'vpn_core.dart';

/// An installed app that can be picked for per-app VPN.
class InstalledApp {
  const InstalledApp({required this.package, required this.label, this.icon});
  final String package;
  final String label;

  /// PNG bytes, null when the app has no icon we could draw.
  final Uint8List? icon;
}

/// The `apps` channel answer: maps of package, label and icon. Entries
/// without a package are dropped; the rest are sorted by label.
List<InstalledApp> parseInstalledApps(List<Object?> raw) {
  final apps = <InstalledApp>[];
  for (final e in raw) {
    if (e is! Map) continue;
    final package = e['package'];
    if (package is! String || package.isEmpty) continue;
    final label = e['label'];
    final icon = e['icon'];
    apps.add(
      InstalledApp(
        package: package,
        label: label is String && label.isNotEmpty ? label : package,
        icon: icon is Uint8List
            ? icon
            : icon is List
            ? Uint8List.fromList(icon.cast<int>())
            : null,
      ),
    );
  }
  apps.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
  return apps;
}

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
      .map((e) => decodeStatus(e as Map))
      .asBroadcastStream();

  @visibleForTesting
  static VpnStatus decodeStatus(Map e) {
    final state = switch (e['state']) {
      'connecting' => VpnState.connecting,
      'connected' => VpnState.connected,
      'disconnecting' => VpnState.disconnecting,
      _ => VpnState.disconnected,
    };
    return VpnStatus(
      state,
      e['error'] as String?,
      state == VpnState.connecting && e['reconnecting'] == true,
    );
  }

  @override
  Future<bool> prepare() async =>
      await _methods.invokeMethod<bool>('prepare') ?? false;

  @override
  Future<String?> start(
    String configJson, {
    AppsMode mode = AppsMode.all,
    List<String> apps = const [],
  }) async {
    try {
      await _methods.invokeMethod('start', {
        'config': configJson,
        'apps_mode': mode.name,
        'apps': apps,
      });
      return null;
    } on PlatformException catch (e) {
      return e.message ?? e.code;
    }
  }

  /// Launchable apps except GateX itself, sorted by label.
  Future<List<InstalledApp>> installedApps() async => parseInstalledApps(
    await _methods.invokeListMethod<Object?>('apps') ?? [],
  );

  @override
  Future<void> stop() => _methods.invokeMethod('stop');

  @override
  Future<DelayResult> measureDelay(
    String configJson, {
    int timeoutMs = 6000,
  }) async {
    final r = await _methods.invokeMapMethod<String, Object?>('delay', {
      'config': configJson,
      'url': probeUrl,
      'timeout': timeoutMs,
    });
    final ms = r?['ms'] as int? ?? -1;
    return ms >= 0
        ? DelayResult.ok(ms)
        : DelayResult.failed(r?['error'] as String? ?? 'no answer');
  }

  @override
  Future<String> coreVersion() async =>
      await _methods.invokeMethod<String>('version') ?? '';

  @override
  Future<(int, int)?> traffic() async {
    try {
      return parseTraffic(await _methods.invokeMethod<String>('traffic'));
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<String?> fetch(String url) async {
    try {
      return await _methods.invokeMethod<String>('fetch', {
        'url': url,
        'timeout': 8000,
      });
    } on PlatformException {
      return null;
    }
  }
}
