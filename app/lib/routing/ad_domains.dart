import 'package:flutter/services.dart';

const adDomainsAsset = 'assets/routing/ads.txt';

// One domain per line. Comments, regexp:/keyword: entries are dropped;
// domain:/full: prefixes and @attr suffixes are stripped; result is
// lower-case and de-duplicated, in first-seen order.
List<String> parseAdDomains(String text) {
  final seen = <String>{};
  for (var line in text.split('\n')) {
    final hash = line.indexOf('#');
    if (hash >= 0) line = line.substring(0, hash);
    line = line.trim().toLowerCase();
    if (line.isEmpty) continue;
    if (line.startsWith('regexp:') || line.startsWith('keyword:')) continue;
    if (line.startsWith('include:')) continue;
    if (line.startsWith('domain:')) line = line.substring(7);
    if (line.startsWith('full:')) line = line.substring(5);
    final at = line.indexOf('@');
    if (at >= 0) line = line.substring(0, at);
    line = line.trim().toLowerCase();
    if (line.isEmpty) continue;
    seen.add(line);
  }
  return seen.toList();
}

Future<List<String>> loadAdDomains(AssetBundle bundle) async =>
    parseAdDomains(await bundle.loadString(adDomainsAsset));
