import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gatex/core/config_builder.dart';
import 'package:gatex/routing/routing_settings.dart';
import 'package:gatex/subscription/server.dart';
import 'package:gatex/subscription/subscription.dart';

const _link =
    'vless://3f1b2c4d-1111-2222-3333-444455556666@1.2.3.4:443?type=tcp&security=none#srv';

List<Map<String, dynamic>> _rules(
  RoutingSettings routing, {
  List<String> adDomains = const [],
  bool processRules = false,
  List<String> serverIps = const [],
  List<Server>? servers,
}) {
  final cfg = jsonDecode(
    buildConnectConfig(
      servers: servers ?? parseServers(_link),
      host: TunHost.windows,
      options: ConnectOptions(
        routing: routing,
        adDomains: adDomains,
        processRules: processRules,
        serverIps: serverIps,
      ),
    ),
  );
  return [
    for (final r in cfg['routing']['rules'] as List) r as Map<String, dynamic>,
  ];
}

bool _eq(Object? a, List<String> b) => jsonEncode(a) == jsonEncode(b);

void main() {
  test('defaults: RU direct, catch-all proxy, panel routing ignored', () {
    final server = serverFromXrayConfig({
      'remarks': 'x',
      'outbounds': [
        {
          'tag': 'proxy',
          'protocol': 'vless',
          'settings': {
            'vnext': [
              {'address': '5.6.7.8', 'port': 443, 'users': []},
            ],
          },
        },
      ],
      'routing': {
        'rules': [
          {
            'type': 'field',
            'domain': ['domain:panel.example'],
            'outboundTag': 'block',
          },
        ],
      },
    })!;
    final rules = _rules(RoutingSettings.defaults, servers: [server]);
    expect(rules.any((r) => _eq(r['domain'], russianDomains)), isTrue);
    expect(rules.any((r) => r.containsKey('process')), isFalse);
    expect(jsonEncode(rules), isNot(contains('panel.example')));
    expect(rules.last, {'network': 'tcp,udp', 'outboundTag': 'proxy'});
  });

  test('own rules keep order, disabled one is dropped, kinds map', () {
    final rules = _rules(
      const RoutingSettings(
        directRu: false,
        rules: [
          RoutingRule(
            kind: RuleKind.domain,
            value: 'a.com',
            action: RuleAction.direct,
          ),
          RoutingRule(
            kind: RuleKind.keyword,
            value: 'ads',
            action: RuleAction.block,
          ),
          RoutingRule(
            kind: RuleKind.ip,
            value: '8.8.8.0/24',
            action: RuleAction.proxy,
          ),
          RoutingRule(
            kind: RuleKind.domain,
            value: 'off.com',
            action: RuleAction.block,
            enabled: false,
          ),
        ],
      ),
    );
    expect(rules, [
      isA<Map>().having((r) => r['ip'], 'private', contains('10.0.0.0/8')),
      {
        'domain': ['domain:a.com'],
        'outboundTag': 'direct',
      },
      {
        'domain': ['keyword:ads'],
        'outboundTag': 'block',
      },
      {
        'ip': ['8.8.8.0/24'],
        'outboundTag': 'proxy',
      },
      {'network': 'tcp,udp', 'outboundTag': 'proxy'},
    ]);
  });

  test('own proxy rule targets the balancer with several servers', () {
    final servers = parseServers(
      '$_link\n${_link.replaceFirst('1.2.3.4', '5.6.7.8')}',
    );
    final rules = _rules(
      const RoutingSettings(
        directRu: false,
        rules: [
          RoutingRule(
            kind: RuleKind.domain,
            value: 'a.com',
            action: RuleAction.proxy,
          ),
        ],
      ),
      servers: servers,
    );
    expect(rules[1]['balancerTag'], 'auto');
    expect(rules.last['balancerTag'], 'auto');
  });

  test('ads block sits after own rules and before RU direct', () {
    final rules = _rules(
      const RoutingSettings(
        blockAds: true,
        rules: [
          RoutingRule(
            kind: RuleKind.domain,
            value: 'a.com',
            action: RuleAction.direct,
          ),
        ],
      ),
      adDomains: ['doubleclick.net'],
    );
    final own = rules.indexWhere((r) => _eq(r['domain'], ['domain:a.com']));
    final ads = rules.indexWhere(
      (r) => r['outboundTag'] == 'block' && r['domain'] != null,
    );
    final ru = rules.indexWhere((r) => _eq(r['domain'], russianDomains));
    expect(rules[ads], {
      'domain': ['domain:doubleclick.net'],
      'outboundTag': 'block',
    });
    expect(own < ads && ads < ru, isTrue);
  });

  test('no ads rule without domains', () {
    final rules = _rules(const RoutingSettings(blockAds: true));
    expect(rules.any((r) => r['outboundTag'] == 'block'), isFalse);
  });

  test('except mode: process direct rule right after private + server IPs', () {
    final rules = _rules(
      const RoutingSettings(appsMode: AppsMode.except, apps: ['steam.exe']),
      processRules: true,
      serverIps: ['1.2.3.4'],
    );
    expect(rules[2], {
      'process': ['steam.exe'],
      'outboundTag': 'direct',
    });
    expect(rules.last, {'network': 'tcp,udp', 'outboundTag': 'proxy'});
  });

  test('only mode: rules carry process, then proxy rule, then direct', () {
    final rules = _rules(
      const RoutingSettings(
        appsMode: AppsMode.only,
        apps: ['chrome.exe'],
        blockAds: true,
        rules: [
          RoutingRule(
            kind: RuleKind.domain,
            value: 'a.com',
            action: RuleAction.direct,
          ),
        ],
      ),
      adDomains: ['doubleclick.net'],
      processRules: true,
    );
    expect(rules[0].containsKey('process'), isFalse);
    final own = rules.firstWhere((r) => _eq(r['domain'], ['domain:a.com']));
    expect(own['process'], ['chrome.exe']);
    final ads = rules.firstWhere(
      (r) => _eq(r['domain'], ['domain:doubleclick.net']),
    );
    expect(ads['process'], ['chrome.exe']);
    final ru = rules.firstWhere((r) => _eq(r['domain'], russianDomains));
    expect(ru['process'], ['chrome.exe']);
    expect(rules[rules.length - 2], {
      'process': ['chrome.exe'],
      'outboundTag': 'proxy',
    });
    expect(rules.last, {'network': 'tcp,udp', 'outboundTag': 'direct'});
  });

  test('processRules false: no process field anywhere', () {
    final rules = _rules(
      const RoutingSettings(appsMode: AppsMode.only, apps: ['com.x']),
    );
    expect(jsonEncode(rules), isNot(contains('process')));
    expect(rules.last, {'network': 'tcp,udp', 'outboundTag': 'proxy'});
  });

  test('domainStrategy follows enabled own IP rules', () {
    String strategy(List<RoutingRule> rules) =>
        jsonDecode(
              buildConnectConfig(
                servers: parseServers(_link),
                host: TunHost.windows,
                options: ConnectOptions(routing: RoutingSettings(rules: rules)),
              ),
            )['routing']['domainStrategy']
            as String;
    const ip = RoutingRule(
      kind: RuleKind.ip,
      value: '8.8.8.0/24',
      action: RuleAction.direct,
    );
    const dom = RoutingRule(
      kind: RuleKind.domain,
      value: 'a.com',
      action: RuleAction.direct,
    );
    expect(strategy(const [dom]), 'AsIs');
    expect(strategy(const [dom, ip]), 'IPIfNonMatch');
    expect(strategy([ip.copyWith(enabled: false)]), 'AsIs');
  });
}
