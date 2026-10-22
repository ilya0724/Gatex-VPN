import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../links.dart';

class AppUpdate {
  AppUpdate(this.version, this.url, this.notes);
  final String version;
  final String url;
  final String notes;
}

/// Reads the manifest on the site and returns a newer build for this
/// platform, or null.
Future<AppUpdate?> checkForUpdate(String currentVersion) async {
  try {
    final resp = await http
        .get(Uri.parse(Links.updateManifest))
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return null;
    final m = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final version = m['version'] as String?;
    final key = Platform.isAndroid
        ? 'android'
        : Platform.isWindows
        ? 'windows'
        : 'linux';
    final url = (m[key] as Map?)?['url'] as String?;
    if (version == null || url == null) return null;
    if (compareVersions(version, currentVersion) <= 0) return null;
    return AppUpdate(version, url, (m['notes'] as String?) ?? '');
  } on Exception {
    return null;
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
