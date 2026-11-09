import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gatex/core/desktop_core.dart';
import 'package:gatex/core/vpn_core.dart';

/// A helper process that never says "started".
class _SilentProcess implements Process {
  final _exit = Completer<int>();
  bool killed = false;

  @override
  Stream<List<int>> get stdout => const Stream.empty();
  @override
  Stream<List<int>> get stderr => const Stream.empty();
  @override
  Future<int> get exitCode => _exit.future;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    if (!_exit.isCompleted) _exit.complete(-1);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('launch gives up when the helper never reports started', () async {
    final p = _SilentProcess();
    final core = DesktopCore(
      startProcess: (_, _) async => p,
      launchTimeout: const Duration(milliseconds: 50),
    );
    final states = <VpnState>[];
    core.status.listen((s) => states.add(s.state));
    final error = await core.launchForTest('x', const []);
    await Future<void>.delayed(Duration.zero);
    expect(error, 'Ядро не запустилось за 0 секунд');
    expect(p.killed, isTrue);
    expect(states, contains(VpnState.disconnected));
  });
}
