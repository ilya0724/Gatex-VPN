import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
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

  /// No safe, verifiable file: the banner opens the release page instead.
  bool get manual => sha256 == null;
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
    if (version == null) return null;
    if (compareVersions(version, currentVersion) <= 0) return null;
    final entry = m[platform];
    final url = entry is Map ? entry['url'] : null;
    final sha = entry is Map ? entry['sha256'] : null;
    final notes = (m['notes'] as String?) ?? '';
    final name = url is String
        ? trustedAssetName(url, platform, version)
        : null;
    if (name == null || sha is! String || !_hex64.hasMatch(sha)) {
      return _manual(version, notes);
    }
    return AppUpdate(
      version: version,
      url: url as String,
      notes: notes,
      fileName: name,
      sha256: sha.toLowerCase(),
    );
  } on Exception {
    return null;
  }
}

final _hex64 = RegExp(r'^[0-9a-fA-F]{64}$');
const _releaseDownloads = '/ilya0724/Gatex-VPN/releases/download/';

/// An update the app will not install by itself: opens the release page.
AppUpdate _manual(String version, String notes) =>
    AppUpdate(version: version, url: releasePage, notes: notes, fileName: '');

bool _assetNameOk(String platform, String name) => switch (platform) {
  'android' => name == 'GateX-arm64.apk' || name == 'GateX.apk',
  'windows' => name == 'GateX-Setup.exe',
  _ => RegExp(r'^gatex_[0-9A-Za-z.+~-]+_amd64\.deb$').hasMatch(name),
};

/// The file name of [url] when it is an https download from this repo's
/// releases and the name is one of the platform's assets; else null.
String? trustedAssetName(String url, String platform, String version) {
  final uri = Uri.tryParse(url);
  // An encoded slash or dot could walk out of the repo's path.
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host != 'github.com' ||
      uri.hasPort ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      uri.path.contains('%') ||
      !uri.path.startsWith(_releaseDownloads)) {
    return null;
  }
  final segs = uri.pathSegments;
  if (segs.length != 6) return null;
  // The tag is the update's own version: no other release, no downgrade.
  final tag = segs[4];
  if (!_tagOk.hasMatch(tag) || tag != 'v$version') return null;
  final name = segs.last;
  return _assetNameOk(platform, name) ? name : null;
}

final _tagOk = RegExp(r'^v[0-9]+(\.[0-9]+){1,3}([+-][0-9A-Za-z.-]+)?$');

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
  final notes = (j['body'] as String?) ?? '';
  final assets = j['assets'];
  if (assets is! List) return null;
  for (final a in assets) {
    if (a is! Map) continue;
    final name = a['name'];
    final url = a['browser_download_url'];
    if (name is! String ||
        url is! String ||
        !_assetNameOk(platform, name) ||
        (platform == 'android' &&
            name != (abi == 'arm64-v8a' ? 'GateX-arm64.apk' : 'GateX.apk'))) {
      continue;
    }
    final digest = a['digest'];
    final sha = digest is String && digest.startsWith('sha256:')
        ? digest.substring(7).toLowerCase()
        : null;
    final size = a['size'];
    // Never install what cannot be checked.
    if (sha == null ||
        !_hex64.hasMatch(sha) ||
        trustedAssetName(url, platform, version) != name) {
      return _manual(version, notes);
    }
    return AppUpdate(
      version: version,
      url: url,
      notes: notes,
      fileName: name,
      sha256: sha,
      size: size is int ? size : null,
    );
  }
  return null;
}

const _corrupt = 'Файл повреждён, попробуйте ещё раз';

/// True when [f] has the published digest (and size, when known). Without
/// a digest there is nothing to check it against, so [f] is not trusted.
Future<bool> _verified(File f, AppUpdate u) async {
  if (u.sha256 == null) return false;
  if (u.size != null && await f.length() != u.size) return false;
  final d = await sha256.bind(f.openRead()).first;
  return d.toString() == u.sha256;
}

const _failed = 'Не удалось скачать обновление';

/// Downloads to `<dir>/updates/<fileName>.part`, yielding 0..1, checks
/// size and sha256 and renames to the final name. A body that stays silent
/// for [idle] ends the download.
Stream<double> downloadUpdate(
  AppUpdate u,
  String dir, {
  http.Client? client,
  Duration idle = const Duration(seconds: 30),
}) async* {
  // The name becomes a path: nothing but a plain file name goes through.
  if (u.sha256 == null ||
      !RegExp(r'^[A-Za-z0-9._+~-]+$').hasMatch(u.fileName)) {
    throw UpdateException(_failed);
  }
  if (u.fileName.contains('..')) throw UpdateException(_failed);
  final c = client ?? http.Client();
  File? part;
  try {
    final folder = Directory('$dir${Platform.pathSeparator}updates');
    await folder.create(recursive: true);
    final target = File('${folder.path}${Platform.pathSeparator}${u.fileName}');
    part = File('${target.path}.part');
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
    final req = http.Request('GET', Uri.parse(u.url))
      ..headers['User-Agent'] = 'GateX/${u.version}';
    final resp = await c.send(req).timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) {
      throw UpdateException('$_failed (${resp.statusCode})');
    }
    final total = u.size ?? resp.contentLength ?? 0;
    final out = part.openWrite();
    var got = 0;
    try {
      yield 0.0;
      final body = resp.stream.timeout(
        idle,
        onTimeout: (sink) {
          sink.addError(
            UpdateException('Загрузка прервалась, попробуйте ещё раз'),
          );
          sink.close();
        },
      );
      await for (final chunk in body) {
        out.add(chunk);
        got += chunk.length;
        if (total > 0) yield (got / total).clamp(0.0, 1.0);
      }
    } finally {
      await out.close();
    }
    if (!await _verified(part, u)) throw UpdateException(_corrupt);
    await part.rename(target.path);
    yield 1.0;
  } on UpdateException {
    if (part != null) _drop(part);
    rethrow;
  } on Exception {
    if (part != null) _drop(part);
    throw UpdateException(_failed);
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

/// Checks the file once more right before it runs: it sat on disk since
/// the download. A changed file is deleted.
Future<void> verifyForInstall(String path, AppUpdate u) async {
  final f = File(path);
  bool ok;
  try {
    ok = f.existsSync() && await _verified(f, u);
  } on Exception {
    ok = false;
  }
  if (!ok) {
    _drop(f);
    throw UpdateException(_corrupt);
  }
}

/// Hands the downloaded file to the system. Android shows the package
/// installer. Windows and Linux replace the app, then [quit] runs (the
/// caller stops the core there); without it the process exits.
Future<void> installUpdate(
  String path,
  AppUpdate update, {
  Future<void> Function()? quit,
}) async {
  await verifyForInstall(path, update);
  if (Platform.isAndroid) {
    final r = await _app.invokeMethod<String>('installApk', {'path': path});
    if (r == 'permission') {
      throw UpdateException(
        'Разрешите установку из GateX в настройках и нажмите «Установить» снова',
      );
    }
    if (r == 'signature') {
      throw UpdateException(
        'Эта версия подписана новым ключом. Удалите GateX и установите '
        'его заново с gatexx.ru — один раз, дальше обновления пойдут сами',
      );
    }
    return;
  }
  if (Platform.isWindows) {
    // Ask for admin rights from this process while its window is still in
    // front, so the UAC prompt shows on top. A hidden helper started after
    // the window closed got a prompt in the background or none at all, and
    // GateX quit without installing anything.
    final code = await Isolate.run(
      () => _runElevated(path, windowsInstallerArgs),
    );
    if (code == _errorCancelled || code == _seErrAccessDenied) {
      throw UpdateException(
        'Установка отменена: Windows не дал прав администратора',
      );
    }
    if (code <= 32) {
      throw UpdateException('Не удалось запустить установщик ($code)');
    }
    // The installer runs; it closes whatever is left of GateX and starts
    // the new version when it is done.
    await _leave(quit);
    return;
  }
  var installed = false;
  try {
    installed = (await Process.run('dpkg', ['-s', 'gatex'])).exitCode == 0;
  } on ProcessException {
    // Not a Debian system.
  }
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

/// Inno Setup switches for an update: no wizard, no questions, close the
/// running app, start it again at the end (the [Run] entry for silent mode).
const windowsInstallerArgs =
    '/SILENT /SUPPRESSMSGBOXES /NORESTART /CLOSEAPPLICATIONS';

const _seErrAccessDenied = 5;
const _errorCancelled = 1223;

typedef _ShellExecuteNative = IntPtr Function(
  IntPtr hwnd,
  Pointer<Utf16> verb,
  Pointer<Utf16> file,
  Pointer<Utf16> params,
  Pointer<Utf16> dir,
  Int32 show,
);
typedef _ShellExecuteDart = int Function(
  int hwnd,
  Pointer<Utf16> verb,
  Pointer<Utf16> file,
  Pointer<Utf16> params,
  Pointer<Utf16> dir,
  int show,
);

/// ShellExecuteW with the "runas" verb: shows the UAC prompt and returns
/// once the user answered. Above 32 the program started; 5 means declined.
/// Runs in its own isolate so the window keeps painting meanwhile.
int _runElevated(String file, String params) {
  final user32 = DynamicLibrary.open('user32.dll');
  final shell32 = DynamicLibrary.open('shell32.dll');
  final ole32 = DynamicLibrary.open('ole32.dll');
  final foreground = user32.lookupFunction<IntPtr Function(), int Function()>(
    'GetForegroundWindow',
  );
  final coInit = ole32
      .lookupFunction<
        Int32 Function(Pointer<Void>, Uint32),
        int Function(Pointer<Void>, int)
      >('CoInitializeEx');
  final shellExecute = shell32
      .lookupFunction<_ShellExecuteNative, _ShellExecuteDart>('ShellExecuteW');
  // COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE, as ShellExecute asks.
  coInit(nullptr, 0x2 | 0x4);
  final verb = 'runas'.toNativeUtf16();
  final f = file.toNativeUtf16();
  final p = params.toNativeUtf16();
  try {
    // SW_SHOWNORMAL: the installer's progress window is visible.
    return shellExecute(foreground(), verb, f, p, nullptr, 1);
  } finally {
    calloc.free(verb);
    calloc.free(f);
    calloc.free(p);
  }
}
