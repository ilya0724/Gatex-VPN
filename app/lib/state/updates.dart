import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../links.dart';

/// A newer build for this platform.
class AppUpdate {
  AppUpdate({
    required this.version,
    required this.url,
    required this.notes,
    required this.fileName,
    this.sha256,
    this.size,
  });
  final String version;
  final String url;
  final String notes;

  /// Name of the downloaded file, as in the release.
  final String fileName;

  /// Lower-case hex, when the release publishes a digest.
  final String? sha256;
  final int? size;
}

/// A problem the user can read: shown in the banner as is.
class UpdateException implements Exception {
  UpdateException(this.message);
  final String message;
  @override
  String toString() => message;
}

const releasesApi =
    'https://api.github.com/repos/ilya0724/Gatex-VPN/releases/latest';
const releasePage = 'https://github.com/ilya0724/Gatex-VPN/releases/latest';
const _app = MethodChannel('gatex/app');

String _platformName() => Platform.isAndroid
    ? 'android'
    : Platform.isWindows
    ? 'windows'
    : 'linux';

/// Looks at GitHub's latest release (the site manifest if GitHub does not
/// answer) and returns a newer build for this platform, or null.
Future<AppUpdate?> checkForUpdate(
  String currentVersion, {
  http.Client? client,
  String? platform,
  String? abi,
}) async {
  final c = client ?? http.Client();
  try {
    final plat = platform ?? _platformName();
    var cpu = abi;
    if (cpu == null && plat == 'android') {
      try {
        cpu = await _app.invokeMethod<String>('abi');
      } on Exception {
        cpu = null;
      }
    }
    final headers = {
      'Accept': 'application/vnd.github+json',
      'User-Agent': 'GateX/$currentVersion',
    };
    try {
      final resp = await c
          .get(Uri.parse(releasesApi), headers: headers)
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final j = jsonDecode(utf8.decode(resp.bodyBytes));
        if (j is Map) {
          return parseGithubRelease(
            j,
            currentVersion,
            platform: plat,
            abi: cpu,
          );
        }
      }
    } on Exception {
      // Fall through to the manifest on the site.
    }
    return await _checkManifest(c, currentVersion, plat, headers);
  } on Exception {
    return null;
  } finally {
    if (client == null) c.close();
  }
}

Future<AppUpdate?> _checkManifest(
  http.Client c,
  String currentVersion,
  String platform,
  Map<String, String> headers,
) async {
  try {
    final resp = await c
        .get(Uri.parse(Links.updateManifest), headers: headers)
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return null;
    final m = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final version = m['version'] as String?;
    final url = (m[platform] as Map?)?['url'] as String?;
    if (version == null || url == null) return null;
    if (compareVersions(version, currentVersion) <= 0) return null;
    final segments = Uri.tryParse(url)?.pathSegments ?? const <String>[];
    final name = segments.isEmpty ? '' : segments.last;
    return AppUpdate(
      version: version,
      url: url,
      notes: (m['notes'] as String?) ?? '',
      fileName: name.isEmpty ? 'GateX-update' : name,
    );
  } on Exception {
    return null;
  }
}

/// A GitHub release as `releases/latest` returns it. [platform] is
/// `android`, `windows` or `linux`; [abi] the device's first ABI.
AppUpdate? parseGithubRelease(
  Map j,
  String current, {
  required String platform,
  String? abi,
}) {
  final tag = j['tag_name'];
  if (tag is! String) return null;
  final version = tag.startsWith('v') ? tag.substring(1) : tag;
  if (compareVersions(version, current) <= 0) return null;
  bool matches(String n) => switch (platform) {
    'android' => n == (abi == 'arm64-v8a' ? 'GateX-arm64.apk' : 'GateX.apk'),
    'windows' => n == 'GateX-Setup.exe',
    _ => RegExp(r'^gatex_.*_amd64\.deb$').hasMatch(n),
  };
  final assets = j['assets'];
  if (assets is! List) return null;
  for (final a in assets) {
    if (a is! Map) continue;
    final name = a['name'];
    final url = a['browser_download_url'];
    if (name is! String || url is! String || !matches(name)) continue;
    final digest = a['digest'];
    final size = a['size'];
    return AppUpdate(
      version: version,
      url: url,
      notes: (j['body'] as String?) ?? '',
      fileName: name,
      sha256: digest is String && digest.startsWith('sha256:')
          ? digest.substring(7).toLowerCase()
          : null,
      size: size is int ? size : null,
    );
  }
  return null;
}

const _corrupt = 'Файл повреждён, попробуйте ещё раз';

/// True when [f] has the published size and digest. Without either there
/// is nothing to check it against, so [f] is not trusted.
Future<bool> _verified(File f, AppUpdate u) async {
  if (u.size == null && u.sha256 == null) return false;
  if (u.size != null && await f.length() != u.size) return false;
  if (u.sha256 != null) {
    final d = await sha256.bind(f.openRead()).first;
    if (d.toString() != u.sha256) return false;
  }
  return true;
}

/// Downloads to `<dir>/updates/<fileName>.part`, yielding 0..1, checks
/// size and sha256 (when known) and renames to the final name.
Stream<double> downloadUpdate(
  AppUpdate u,
  String dir, {
  http.Client? client,
}) async* {
  final folder = Directory('$dir${Platform.pathSeparator}updates');
  await folder.create(recursive: true);
  final target = File('${folder.path}${Platform.pathSeparator}${u.fileName}');
  final part = File('${target.path}.part');
  // Older downloads are of no use.
  for (final e in folder.listSync()) {
    if (e is File && e.path != target.path) _drop(e);
  }
  if (target.existsSync()) {
    if (await _verified(target, u)) {
      yield 1.0;
      return;
    }
    _drop(target);
  }
  final c = client ?? http.Client();
  try {
    final req = http.Request('GET', Uri.parse(u.url))
      ..headers['User-Agent'] = 'GateX/${u.version}';
    final resp = await c.send(req).timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) {
      throw UpdateException(
        'Не удалось скачать обновление (${resp.statusCode})',
      );
    }
    final total = u.size ?? resp.contentLength ?? 0;
    final out = part.openWrite();
    var got = 0;
    try {
      yield 0.0;
      await for (final chunk in resp.stream) {
        out.add(chunk);
        got += chunk.length;
        if (total > 0) yield (got / total).clamp(0.0, 1.0);
      }
    } finally {
      await out.close();
    }
    if ((u.size != null || u.sha256 != null) && !await _verified(part, u)) {
      throw UpdateException(_corrupt);
    }
    await part.rename(target.path);
    yield 1.0;
  } on UpdateException {
    _drop(part);
    rethrow;
  } on Exception {
    _drop(part);
    throw UpdateException('Не удалось скачать обновление');
  } finally {
    if (client == null) c.close();
  }
}

void _drop(File f) {
  try {
    if (f.existsSync()) f.deleteSync();
  } on FileSystemException {
    // Still open somewhere; it is only disk space.
  }
}

/// Hands the downloaded file to the system. Android shows the package
/// installer. Windows and Linux replace the app, then [quit] runs (the
/// caller stops the core there); without it the process exits.
Future<void> installUpdate(String path, {Future<void> Function()? quit}) async {
  if (Platform.isAndroid) {
    final r = await _app.invokeMethod<String>('installApk', {'path': path});
    if (r == 'permission') {
      throw UpdateException(
        'Разрешите установку из GateX в настройках и нажмите «Установить» снова',
      );
    }
    return;
  }
  if (Platform.isWindows) {
    // The installer asks for admin rights; PowerShell can elevate, a plain
    // CreateProcess cannot.
    final file = "'${path.replaceAll("'", "''")}'";
    await Process.start('powershell', [
      '-NoProfile',
      '-WindowStyle',
      'Hidden',
      '-Command',
      'Start-Process -FilePath $file -Verb RunAs -ArgumentList '
          "'/SILENT','/SUPPRESSMSGBOXES','/NORESTART','/CLOSEAPPLICATIONS'",
    ], mode: ProcessStartMode.detached);
    await _leave(quit);
    return;
  }
  final installed = (await Process.run('dpkg', ['-s', 'gatex'])).exitCode == 0;
  if (!installed) {
    await launchUrl(
      Uri.parse(releasePage),
      mode: LaunchMode.externalApplication,
    );
    return;
  }
  final r = await Process.run('pkexec', ['apt-get', 'install', '-y', path]);
  if (r.exitCode != 0) {
    throw UpdateException('Не удалось установить обновление (${r.exitCode})');
  }
  final exe = File('/usr/bin/gatex').existsSync()
      ? '/usr/bin/gatex'
      : Platform.resolvedExecutable;
  // Wait for this window to go, or the new one would only wake this one.
  await Process.start('sh', [
    '-c',
    'sleep 2; exec "\$0"',
    exe,
  ], mode: ProcessStartMode.detached);
  await _leave(quit);
}

Future<void> _leave(Future<void> Function()? quit) async {
  if (quit != null) {
    await quit();
  } else {
    exit(0);
  }
}

/// Compares dotted versions numerically: 1.10.0 > 1.9.3.
int compareVersions(String a, String b) {
  List<int> parts(String v) =>
      v.split('+').first.split('.').map((p) => int.tryParse(p) ?? 0).toList();
  final pa = parts(a), pb = parts(b);
  for (var i = 0; i < 3; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}
