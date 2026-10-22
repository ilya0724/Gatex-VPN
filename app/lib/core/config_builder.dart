import 'dart:convert';

import '../subscription/server.dart';
import '../subscription/subscription.dart' show dialTargets;

/// Where the TUN comes from, which decides the inbound settings.
enum TunHost { android, windows, linux }

const probeUrl = 'https://www.gstatic.com/generate_204';
const tunMtu = 1500;

/// Private and link-local ranges stay outside the tunnel.
const _privateCidrs = [
  '10.0.0.0/8',
  '100.64.0.0/10',
  '127.0.0.0/8',
  '169.254.0.0/16',
  '172.16.0.0/12',
  '192.168.0.0/16',
  '224.0.0.0/4',
  'fc00::/7',
  'fe80::/10',
];

/// What the user picked in settings that changes the config.
class ConnectOptions {
  const ConnectOptions({
    this.ipv6 = true,
    this.directRu = true,
    this.dns = const ['1.1.1.1', '8.8.8.8'],
    this.logFile,
    this.logLevel = 'warning',
    this.serverIps = const [],
  });

  final bool ipv6;

  /// Russian sites go around the tunnel: banks and Госуслуги often refuse
  /// foreign IPs, and they are not blocked anyway.
  final bool directRu;
  final List<String> dns;

  /// Where Xray writes its error log, shown in the app's journal.
  final String? logFile;
  final String logLevel;

  /// The servers' own IPs. Traffic to them from other programs (the delay
  /// test) goes direct, so a test while connected measures the server and
  /// not a detour through the current tunnel.
  final List<String> serverIps;
}

/// Domains of Russian services, matched with their subdomains. Most sit
/// under .ru/.рф/.su; the rest are the big ones on other zones.
const russianDomains = [
  'domain:ru',
  'domain:xn--p1ai',
  'domain:su',
  'domain:yandex.net',
  'domain:yandex.com',
  'domain:yastatic.net',
  'domain:vk.com',
  'domain:vk.me',
  'domain:userapi.com',
  'domain:vkuser.net',
  'domain:mycdn.me',
  'domain:avito.st',
  'domain:2gis.com',
];

/// Builds the full Xray config to connect with. With one server all
/// traffic goes to it; with several, Xray's balancer keeps the fastest
/// live one (leastPing over the observatory) and moves off a dead one.
String buildConnectConfig({
  required List<Server> servers,
  required TunHost host,
  ConnectOptions options = const ConnectOptions(),
}) {
  if (servers.isEmpty) throw ArgumentError('no servers');
  final auto = servers.length > 1;
  final outbounds = <Map<String, dynamic>>[];
  for (var i = 0; i < servers.length; i++) {
    outbounds.addAll(
      _serverOutbounds(servers[i], auto ? 'proxy-$i' : 'proxy', 's$i-'),
    );
  }
  outbounds.addAll([
    {'tag': 'direct', 'protocol': 'freedom'},
    {'tag': 'block', 'protocol': 'blackhole'},
  ]);

  final target = auto ? {'balancerTag': 'auto'} : {'outboundTag': 'proxy'};
  final rules = <Map<String, dynamic>>[
    {'ip': _privateCidrs, 'outboundTag': 'direct'},
    if (options.serverIps.isNotEmpty)
      {'ip': options.serverIps, 'outboundTag': 'direct'},
    if (options.directRu) {'domain': russianDomains, 'outboundTag': 'direct'},
    ..._panelRules(servers.first.routing, target),
    {'network': 'tcp,udp', ...target},
  ];

  final config = <String, dynamic>{
    'log': {'loglevel': options.logLevel, 'error': ?options.logFile},
    'dns': _dns(servers.first.dns, options.dns),
    'inbounds': [_tunInbound(host, ipv6: options.ipv6, dns: options.dns)],
    'outbounds': outbounds,
    // Counters for the TUN inbound only: the speed and traffic on screen.
    'stats': <String, dynamic>{},
    'policy': {
      'system': {'statsInboundUplink': true, 'statsInboundDownlink': true},
    },
    'routing': {
      'domainStrategy':
          (servers.first.routing?['domainStrategy'] as String?) ?? 'AsIs',
      'rules': rules,
      if (auto)
        'balancers': [
          {
            'tag': 'auto',
            'selector': ['proxy-'],
            'strategy': {'type': 'leastPing'},
            'fallbackTag': 'proxy-0',
          },
        ],
    },
    if (auto)
      'observatory': {
        'subjectSelector': ['proxy-'],
        'probeUrl': probeUrl,
        'probeInterval': '1m',
        'enableConcurrency': true,
      },
  };
  return const JsonEncoder.withIndent('  ').convert(config);
}

/// A config with just one server and no inbounds, for the delay test.
/// With [logFile] Xray writes why the server failed, for the journal.
String buildProbeConfig(Server server, {String? logFile}) {
  return jsonEncode({
    'log': logFile == null
        ? {'loglevel': 'none'}
        // The outbound's dial errors are logged at info level.
        : {'loglevel': 'info', 'error': logFile, 'access': 'none'},
    'outbounds': _serverOutbounds(server, 'proxy', 'p-'),
  });
}

Map<String, dynamic> _tunInbound(
  TunHost host, {
  required bool ipv6,
  required List<String> dns,
}) {
  final settings = <String, dynamic>{'mtu': tunMtu};
  // Without IPv6 on the machine the v6 address cannot be added and the
  // whole TUN fails, so the app retries with IPv4 only.
  final gateway = ['172.19.0.1/30', if (ipv6) 'fdfe:dcba:9876::1/126'];
  final routes = ['0.0.0.0/0', if (ipv6) '::/0'];
  switch (host) {
    case TunHost.android:
      // The fd comes from VpnService. A fixed name keeps Xray from listing
      // interfaces, which Android 11+ forbids to apps.
      settings['name'] = 'tun0';
    case TunHost.windows:
      settings.addAll({
        'name': 'GateX',
        'desc': 'GateX',
        'gateway': gateway,
        'dns': dns,
        'autoSystemRoutingTable': routes,
        'autoOutboundsInterface': 'auto',
        'autoSystemWfpBlockLeak': ['dns'],
      });
    case TunHost.linux:
      settings.addAll({
        'name': 'gatex0',
        'gateway': gateway,
        'autoSystemRoutingTable': routes,
        'autoOutboundsInterface': 'auto',
      });
  }
  return {
    'tag': 'tun-in',
    'protocol': 'tun',
    'settings': settings,
    'sniffing': {
      'enabled': true,
      'destOverride': ['http', 'tls', 'quic'],
      'routeOnly': true,
    },
  };
}

/// Copies the server's outbounds with tags made unique per server, so many
/// servers fit in one config.
List<Map<String, dynamic>> _serverOutbounds(
  Server server,
  String mainTag,
  String prefix,
) {
  final rename = <String, String>{};
  final mainOld = server.outbound['tag'];
  if (mainOld is String) rename[mainOld] = mainTag;
  for (final o in server.extraOutbounds) {
    final t = o['tag'];
    if (t is String) rename[t] = '$prefix$t';
  }

  Map<String, dynamic> copy(Map<String, dynamic> o, String tag) {
    final c = jsonDecode(jsonEncode(o)) as Map<String, dynamic>;
    c['tag'] = tag;
    for (final old in dialTargets(o)) {
      final renamed = rename[old];
      if (renamed == null) continue;
      final sockopt = (c['streamSettings'] as Map?)?['sockopt'] as Map?;
      if (sockopt?['dialerProxy'] == old) sockopt!['dialerProxy'] = renamed;
      final ps = c['proxySettings'] as Map?;
      if (ps?['tag'] == old) ps!['tag'] = renamed;
    }
    return c;
  }

  return [
    copy(server.outbound, mainTag),
    for (final o in server.extraOutbounds) copy(o, rename[o['tag']]!),
  ];
}

/// Keeps the panel's rules that point at proxy, direct or block, so the
/// panel decides what goes direct. Rules need geo files we do not ship
/// yet, and rules bound to the panel's own inbounds, are left out.
List<Map<String, dynamic>> _panelRules(
  Map<String, dynamic>? routing,
  Map<String, String> proxyTarget,
) {
  final rules = routing?['rules'];
  if (rules is! List) return const [];
  final out = <Map<String, dynamic>>[];
  for (final r in rules) {
    if (r is! Map<String, dynamic>) continue;
    if (r.containsKey('inboundTag') || r.containsKey('balancerTag')) continue;
    if (jsonEncode(r).contains(RegExp(r'geo(ip|site):|ext:'))) continue;
    final tag = r['outboundTag'];
    final rule = Map<String, dynamic>.of(r)..remove('ruleTag');
    if (tag == 'proxy') {
      rule.remove('outboundTag');
      rule.addAll(proxyTarget);
    } else if (tag != 'direct' && tag != 'block') {
      continue;
    }
    out.add(rule);
  }
  return out;
}

Map<String, dynamic> _dns(Map<String, dynamic>? panel, List<String> servers) {
  if (panel != null && !jsonEncode(panel).contains(RegExp(r'geo(ip|site):'))) {
    return panel;
  }
  return {'servers': servers, 'queryStrategy': 'UseIP'};
}
