import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gatex/core/config_builder.dart';
import 'package:gatex/subscription/share_link.dart';
import 'package:gatex/subscription/subscription.dart';

const realityLink =
    'vless://3f1b2c4d-1111-2222-3333-444455556666@de1.example.com:443'
    '?type=tcp&security=reality&pbk=Q8VgQkAaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrS'
    '&fp=chrome&sni=www.microsoft.com&sid=6ba85179e30d4fc2&spx=%2F'
    '&flow=xtls-rprx-vision&encryption=none#%F0%9F%87%A9%F0%9F%87%AA%20%D0%93%D0%B5%D1%80%D0%BC%D0%B0%D0%BD%D0%B8%D1%8F';
const xhttpLink =
    'vless://3f1b2c4d-1111-2222-3333-444455556666@cdn.example.com:443'
    '?type=xhttp&security=tls&sni=cdn.example.com&host=cdn.example.com'
    '&path=%2Fgx&mode=packet-up&alpn=h2%2Chttp%2F1.1&fp=chrome'
    '&extra=%7B%22xPaddingBytes%22%3A%22100-1000%22%7D#LTE%20CDN';
const wsLink =
    'vless://3f1b2c4d-1111-2222-3333-444455556666@ws.example.com:8443'
    '?type=ws&security=tls&sni=ws.example.com&path=%2Fws&host=ws.example.com#WS';
const grpcTrojan =
    'trojan://secret@tr.example.com:443?type=grpc&serviceName=gx&security=tls&sni=tr.example.com#Trojan';
const placeholder =
    'vless://00000000-0000-0000-0000-000000000000@0.0.0.0:1?type=tcp#%D0%9F%D0%BE%D0%B4%D0%BF%D0%B8%D1%81%D0%BA%D0%B0%20%D0%B8%D1%81%D1%82%D0%B5%D0%BA%D0%BB%D0%B0';

void main() {
  test('base64 subscription with Remnawave headers', () {
    final body = base64.encode(
      utf8.encode(
        [realityLink, xhttpLink, wsLink, grpcTrojan, placeholder].join('\n'),
      ),
    );
    final sub = parseSubscription(
      url: 'https://sub.example.com/abc',
      headers: {
        'profile-title':
            'base64:${base64.encode(utf8.encode('Тариф: Стандарт (LTE)'))}',
        'subscription-userinfo':
            'upload=100; download=2000; total=0; expire=4102444800',
        'profile-update-interval': '6',
        'support-url': 'https://t.me/gatexvpn_support',
      },
      body: body,
    );
    expect(sub.title, 'Тариф: Стандарт (LTE)');
    expect(sub.servers, hasLength(4));
    expect(sub.notices, ['Подписка истекла']);
    expect(sub.updateInterval, const Duration(hours: 6));
    expect(sub.expire!.year, 2100);
    final de = sub.servers.first;
    expect(de.flag, '🇩🇪');
    expect(de.title, 'Германия');
    expect(de.transport, 'raw · reality');
    final reality = de.outbound['streamSettings']['realitySettings'];
    expect(reality['publicKey'], startsWith('Q8Vg'));
    expect(reality['spiderX'], '/');
    final x = sub.servers[1].outbound['streamSettings'];
    expect(x['xhttpSettings']['mode'], 'packet-up');
    expect(x['xhttpSettings']['extra']['xPaddingBytes'], '100-1000');
    expect(x['tlsSettings']['alpn'], ['h2', 'http/1.1']);
  });

  test('Xray JSON subscription keeps dialer chains and panel rules', () {
    final configs = [
      {
        'remarks': '🇳🇱 Нидерланды',
        'dns': {
          'servers': ['1.1.1.1'],
        },
        'outbounds': [
          {
            'tag': 'proxy',
            'protocol': 'vless',
            'settings': {
              'vnext': [
                {
                  'address': 'nl.example.com',
                  'port': 443,
                  'users': [
                    {
                      'id': '3f1b2c4d-1111-2222-3333-444455556666',
                      'encryption': 'none',
                    },
                  ],
                },
              ],
            },
            'streamSettings': {
              'network': 'raw',
              'security': 'tls',
              'tlsSettings': {'serverName': 'nl.example.com'},
              'sockopt': {'dialerProxy': 'fragment'},
            },
          },
          {
            'tag': 'fragment',
            'protocol': 'freedom',
            'settings': {
              'fragment': {
                'packets': 'tlshello',
                'length': '100-200',
                'interval': '10-20',
              },
            },
          },
          {'tag': 'direct', 'protocol': 'freedom'},
          {'tag': 'block', 'protocol': 'blackhole'},
        ],
        'routing': {
          'domainStrategy': 'IPIfNonMatch',
          'rules': [
            {
              'type': 'field',
              'domain': ['domain:gatexx.ru'],
              'outboundTag': 'direct',
            },
            {
              'type': 'field',
              'domain': ['geosite:category-ads-all'],
              'outboundTag': 'block',
            },
            {
              'type': 'field',
              'inboundTag': ['socks'],
              'outboundTag': 'proxy',
            },
          ],
        },
      },
    ];
    final servers = parseServers(jsonEncode(configs));
    expect(servers, hasLength(1));
    expect(servers.first.extraOutbounds.single['tag'], 'fragment');

    final cfg = jsonDecode(
      buildConnectConfig(
        servers: [servers.first, parseServers(realityLink).single],
        host: TunHost.android,
        options: const ConnectOptions(directRu: false),
      ),
    );
    final tags = [for (final o in cfg['outbounds']) o['tag']];
    expect(tags, ['proxy-0', 's0-fragment', 'proxy-1', 'direct', 'block']);
    expect(
      cfg['outbounds'][0]['streamSettings']['sockopt']['dialerProxy'],
      's0-fragment',
    );
    final rules = cfg['routing']['rules'] as List;
    expect(rules[1]['domain'], ['domain:gatexx.ru']);
    expect(
      rules,
      hasLength(3),
      reason: 'geosite and inboundTag rules are dropped',
    );
    expect(rules.last['balancerTag'], 'auto');
    expect(cfg['routing']['domainStrategy'], 'IPIfNonMatch');
  });

  test('alpn is fixed up per transport', () {
    Map tls(String link, [String query = '']) =>
        parseServers(link.replaceFirst('#', '$query#'))
            .single
            .outbound['streamSettings']['tlsSettings'];
    expect(tls(wsLink, '&alpn=h2,http/1.1')['alpn'], ['http/1.1']);
    expect(tls(wsLink, '&alpn=h2').containsKey('alpn'), isFalse);
    expect(tls(grpcTrojan, '&alpn=http/1.1')['alpn'], ['h2', 'http/1.1']);
    expect(tls(xhttpLink)['alpn'], ['h2', 'http/1.1']);
  });

  test('Happ server descriptions are split off the name', () {
    final desc = base64.encode(utf8.encode('Для YouTube'));
    final link =
        'vless://3f1b2c4d-1111-2222-3333-444455556666@1.2.3.4:443?type=tcp&security=none'
        '#${Uri.encodeComponent('🇫🇷 ✨ Франция №1')}?serverDescription=$desc';
    final s = parseShareLink(link)!;
    expect(s.name, '🇫🇷 ✨ Франция №1');
    expect(s.title, '✨ Франция №1');
    expect(s.description, 'Для YouTube');
    expect(s.countryCode, 'FR');

    final json = serverFromXrayConfig({
      'remarks': '🇩🇪 Германия',
      'meta': {'serverDescription': 'Быстрый'},
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
    })!;
    expect(json.description, 'Быстрый');
  });

  test('generated configs pass the real Xray core', () async {
    final core = Platform.environment['GATEX_CORE'];
    if (core == null) {
      markTestSkipped('set GATEX_CORE to the gatex-core binary to run');
      return;
    }
    final servers = parseServers(
      [realityLink, xhttpLink, wsLink, grpcTrojan].join('\n'),
    );
    final dir = await Directory.systemTemp.createTemp('gatex');
    final cases = {
      for (final h in TunHost.values)
        'auto-${h.name}': buildConnectConfig(servers: servers, host: h),
      for (final h in TunHost.values)
        'single-${h.name}': buildConnectConfig(
          servers: [servers.first],
          host: h,
          options: const ConnectOptions(
            ipv6: false,
            directRu: false,
            dns: ['9.9.9.9'],
            logFile: 'core.log',
            serverIps: ['1.2.3.4', '2001:db8::1'],
          ),
        ),
      for (var i = 0; i < servers.length; i++)
        'probe-$i': buildProbeConfig(servers[i]),
      'probe-log': buildProbeConfig(servers.first, logFile: 'probe.log'),
    };
    for (final e in cases.entries) {
      final f = File('${dir.path}/${e.key}.json')..writeAsStringSync(e.value);
      final r = await Process.run(core, ['check', '-c', f.path]);
      expect(r.exitCode, 0, reason: '${e.key}: ${r.stderr}');
    }
  });
}
