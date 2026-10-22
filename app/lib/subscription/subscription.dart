import 'dart:convert';

import 'server.dart';
import 'share_link.dart';

/// A fetched subscription: what Remnawave says about the user plus servers.
class Subscription {
  Subscription({
    required this.url,
    required this.servers,
    required this.fetchedAt,
    this.title,
    this.expire,
    this.upload = 0,
    this.download = 0,
    this.total = 0,
    this.updateInterval = const Duration(hours: 12),
    this.supportUrl,
    this.webPageUrl,
    this.announce,
    this.notices = const [],
  });

  final String url;
  final List<Server> servers;
  final DateTime fetchedAt;

  /// From profile-title, e.g. "Тариф: Стандарт (LTE)".
  final String? title;

  /// From subscription-userinfo. Null means no end date.
  final DateTime? expire;
  final int upload;
  final int download;

  /// Traffic limit in bytes, 0 means unlimited.
  final int total;
  final Duration updateInterval;
  final String? supportUrl;
  final String? webPageUrl;
  final String? announce;

  /// Names of placeholder entries ("Подписка истекла" and similar).
  final List<String> notices;

  bool get isExpired => expire != null && expire!.isBefore(DateTime.now());

  int? get daysLeft {
    if (expire == null) return null;
    final left = expire!.difference(DateTime.now());
    if (left.isNegative) return 0;
    return (left.inHours / 24).ceil();
  }

  bool get isStale => DateTime.now().difference(fetchedAt) > updateInterval;
}

/// Builds a [Subscription] from a raw HTTP response. Headers must be keyed
/// in lower case, as package:http gives them.
Subscription parseSubscription({
  required String url,
  required Map<String, String> headers,
  required String body,
  DateTime? fetchedAt,
}) {
  final parsed = parseServers(body);
  final servers = parsed.where((s) => !s.isPlaceholder).toList();
  final notices = parsed.where((s) => s.isPlaceholder).map((s) => s.name);

  final info = _parseUserInfo(headers['subscription-userinfo']);
  final expireSec = info['expire'] ?? 0;
  final interval = int.tryParse(headers['profile-update-interval'] ?? '');

  return Subscription(
    url: url,
    servers: servers,
    fetchedAt: fetchedAt ?? DateTime.now(),
    title: _maybeBase64(headers['profile-title']),
    expire: expireSec > 0
        ? DateTime.fromMillisecondsSinceEpoch(expireSec * 1000)
        : null,
    upload: info['upload'] ?? 0,
    download: info['download'] ?? 0,
    total: info['total'] ?? 0,
    updateInterval: Duration(
      hours: interval != null && interval > 0 ? interval : 12,
    ),
    supportUrl: _nonEmpty(headers['support-url']),
    webPageUrl: _nonEmpty(headers['profile-web-page-url']),
    announce: _maybeBase64(headers['announce']),
    notices: notices.toList(),
  );
}

/// Accepts Xray JSON (an array of full configs or one config), a base64
/// blob of share links, or plain share links one per line.
List<Server> parseServers(String body) {
  final text = body.trim();
  if (text.isEmpty) return [];

  if (text.startsWith('[') || text.startsWith('{')) {
    final decoded = jsonDecode(text);
    final configs = decoded is List ? decoded : [decoded];
    return [
      for (final c in configs)
        if (c is Map<String, dynamic>) ?serverFromXrayConfig(c),
    ];
  }

  var lines = text;
  if (!text.contains('://')) {
    try {
      lines = utf8.decode(decodeBase64Loose(text));
    } on FormatException {
      return [];
    }
  }
  return [
    for (final line in const LineSplitter().convert(lines))
      if (line.trim().isNotEmpty) ?parseShareLink(line),
  ];
}

const _proxyProtocols = {
  'vless',
  'vmess',
  'trojan',
  'shadowsocks',
  'hysteria',
  'hysteria2',
  'wireguard',
  'socks',
  'http',
};

/// Picks the proxy outbound out of one Xray JSON config from the panel and
/// keeps the helper outbounds it dials through.
Server? serverFromXrayConfig(Map<String, dynamic> config) {
  final outbounds = [
    for (final o in (config['outbounds'] as List? ?? const []))
      if (o is Map<String, dynamic>) o,
  ];
  if (outbounds.isEmpty) return null;
  final main = outbounds.firstWhere(
    (o) => o['tag'] == 'proxy',
    orElse: () => outbounds.firstWhere(
      (o) => _proxyProtocols.contains(o['protocol']),
      orElse: () => const {},
    ),
  );
  if (main.isEmpty) return null;

  final byTag = {
    for (final o in outbounds)
      if (o['tag'] is String) o['tag'] as String: o,
  };
  final extras = <Map<String, dynamic>>[];
  final seen = <String>{if (main['tag'] is String) main['tag'] as String};
  void follow(Map<String, dynamic> o) {
    for (final tag in dialTargets(o)) {
      if (seen.add(tag) && byTag[tag] != null) {
        extras.add(byTag[tag]!);
        follow(byTag[tag]!);
      }
    }
  }

  follow(main);

  final (address, port) = _endpoint(main);
  final stream = main['streamSettings'] as Map<String, dynamic>? ?? const {};
  final network = stream['network'] ?? 'raw';
  final security = stream['security'] ?? 'none';
  return Server(
    name: (config['remarks'] as String?) ?? address,
    description: (config['meta'] as Map?)?['serverDescription'] as String?,
    address: address,
    port: port,
    protocol: main['protocol'] as String,
    transport: security == 'none' ? '$network' : '$network · $security',
    outbound: main,
    extraOutbounds: extras,
    routing: config['routing'] as Map<String, dynamic>?,
    dns: config['dns'] as Map<String, dynamic>?,
  );
}

/// Tags an outbound dials through: sockopt.dialerProxy and proxySettings.
List<String> dialTargets(Map<String, dynamic> o) {
  final out = <String>[];
  final sockopt = (o['streamSettings'] as Map?)?['sockopt'] as Map?;
  final dialer = sockopt?['dialerProxy'];
  if (dialer is String && dialer.isNotEmpty) out.add(dialer);
  final proxyTag = (o['proxySettings'] as Map?)?['tag'];
  if (proxyTag is String && proxyTag.isNotEmpty) out.add(proxyTag);
  return out;
}

(String, int) _endpoint(Map<String, dynamic> outbound) {
  final settings = outbound['settings'] as Map<String, dynamic>? ?? const {};
  Map? first(String key) {
    final list = settings[key];
    return list is List && list.isNotEmpty && list.first is Map
        ? list.first as Map
        : null;
  }

  final entry = first('vnext') ?? first('servers') ?? settings;
  final port = entry['port'];
  return (
    '${entry['address'] ?? ''}',
    port is int ? port : int.tryParse('$port') ?? 0,
  );
}

Map<String, int> _parseUserInfo(String? header) {
  final out = <String, int>{};
  if (header == null) return out;
  for (final part in header.split(';')) {
    final kv = part.split('=');
    if (kv.length != 2) continue;
    final value = num.tryParse(kv[1].trim());
    if (value != null) out[kv[0].trim().toLowerCase()] = value.toInt();
  }
  return out;
}

String? _maybeBase64(String? value) {
  final v = _nonEmpty(value);
  if (v == null || !v.startsWith('base64:')) return v;
  try {
    return utf8.decode(decodeBase64Loose(v.substring(7)));
  } on FormatException {
    return v;
  }
}

String? _nonEmpty(String? v) => v == null || v.trim().isEmpty ? null : v.trim();
