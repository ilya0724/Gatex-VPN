import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'config_builder.dart';
import 'vpn_core.dart';

/// Runs the gatex-core helper that ships next to the app executable.
///
/// The helper creates the TUN and the system routes itself, which needs
/// admin rights: on Windows the whole app runs elevated (see the runner
/// manifest), on Linux the helper has CAP_NET_ADMIN from the package, or
/// we ask through pkexec. The helper watches its stdin, so it shuts down
/// and removes its routes whenever the app exits, even after a crash.
class DesktopCore implements VpnCore {
  final _status = StreamController<VpnStatus>.broadcast();
  Process? _process;
  bool _stopping = false;

  @override
  TunHost get tunHost => Platform.isWindows ? TunHost.windows : TunHost.linux;

  @override
  Stream<VpnStatus> get status => _status.stream;

  String get _corePath {
    final dir = File(Platform.resolvedExecutable).parent.path;
    return '$dir${Platform.pathSeparator}gatex-core${Platform.isWindows ? '.exe' : ''}';
  }

  Future<File> _writeTemp(String name, String content) async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return File('${dir.path}${Platform.pathSeparator}$name')
      ..writeAsStringSync(content);
  }

  @override
  Future<bool> prepare() async => File(_corePath).existsSync();

  @override
  Future<String?> start(String configJson) async {
    if (_process != null) return null;
    _status.add(const VpnStatus(VpnState.connecting));
    final config = await _writeTemp('config.json', configJson);
    final args = ['run', '-c', config.path, '-watch-stdin'];

    var error = await _launch(_corePath, args);
    if (error != null && Platform.isLinux && _isPermissionError(error)) {
      error = await _launch('pkexec', [_corePath, ...args]);
    }
    return error;
  }

  /// The helper's own "error: ..." line first; wintun logs harmless
  /// lines such as "Failed to find matching adapter name" before it
  /// creates the adapter, and those hid the real reason.
  static String _reason(String stderr) {
    final lines = stderr
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    final own = lines.where((l) => l.startsWith('error:')).toList();
    if (own.isEmpty) return lines.join('\n');
    final rest = lines.where((l) => !l.startsWith('error:'));
    return [
      own.last.replaceFirst(RegExp(r'^error:\s*'), ''),
      ...rest,
    ].join('\n');
  }

  /// Starts the helper and waits until it reports "started". Returns null
  /// on success, or the helper's error text.
  Future<String?> _launch(String exe, List<String> args) async {
    final Process p;
    try {
      p = await Process.start(exe, args);
    } on ProcessException catch (e) {
      return e.message;
    }
    final started = Completer<String?>();
    final errors = StringBuffer();
    p.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((
      line,
    ) {
      if (line.trim() == 'started' && !started.isCompleted) {
        started.complete(null);
      }
    });
    p.stderr.transform(utf8.decoder).listen(errors.write);
    p.exitCode.then((code) {
      final text = _reason(errors.toString());
      if (!started.isCompleted) {
        started.complete(text.isEmpty ? 'gatex-core exited with $code' : text);
        return;
      }
      _process = null;
      final requested = _stopping;
      _stopping = false;
      _status.add(
        VpnStatus(
          VpnState.disconnected,
          requested || text.isEmpty ? null : text,
        ),
      );
    });

    final error = await started.future;
    if (error == null) {
      _process = p;
      _status.add(const VpnStatus(VpnState.connected));
    }
    return error;
  }

  static bool _isPermissionError(String text) {
    final t = text.toLowerCase();
    return t.contains('operation not permitted') ||
        t.contains('permission denied');
  }

  @override
  Future<void> stop() async {
    final p = _process;
    if (p == null) return;
    _stopping = true;
    _status.add(const VpnStatus(VpnState.disconnecting));
    await p.stdin.close();
    final code = await p.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        p.kill();
        return -1;
      },
    );
    if (code == -1) _process = null;
  }

  @override
  Future<DelayResult> measureDelay(
    String configJson, {
    int timeoutMs = 6000,
  }) async {
    final file = await _writeTemp(
      'probe-${DateTime.now().microsecondsSinceEpoch}.json',
      configJson,
    );
    try {
      final r = await Process.run(_corePath, [
        'delay',
        '-c',
        file.path,
        '-url',
        probeUrl,
        '-timeout',
        '$timeoutMs',
      ]);
      // Xray prints notices (e.g. "WebSocket is deprecated") to stdout
      // before its log settings apply, so the delay is the last bare number.
      final numbers = RegExp(
        r'^\s*(\d+)\s*$',
        multiLine: true,
      ).allMatches('${r.stdout}').toList();
      final ms = numbers.isEmpty ? null : int.parse(numbers.last[1]!);
      if (r.exitCode == 0 && ms != null) return DelayResult.ok(ms);
      final err = '${r.stderr}\n${r.stdout}'.trim().replaceFirst(
        RegExp(r'^error:\s*'),
        '',
      );
      return DelayResult.failed(err.isEmpty ? 'exit ${r.exitCode}' : err);
    } on ProcessException catch (e) {
      return DelayResult.failed(e.message);
    } finally {
      file.deleteSync();
    }
  }

  @override
  Future<String> coreVersion() async {
    try {
      final r = await Process.run(_corePath, ['version']);
      return '${r.stdout}'.trim();
    } on ProcessException {
      return '';
    }
  }
}
