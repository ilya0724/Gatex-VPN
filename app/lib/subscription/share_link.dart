import 'dart:convert';

import 'server.dart';

/// Turns share links (vless://, trojan://, vmess://, ss://) into Xray
/// outbounds. Remnawave sends these when it has no Xray JSON template for
/// our User-Agent, so this is the path every subscription can take.
Server? parseShareLink(String line) {
  final link = line.trim();
  try {
    if (link.startsWith('vless://')) return _parseVless(link);
    if (link.startsWith('trojan://')) return _parseTrojan(link);
    if (link.startsWith('vmess://')) return _parseVmess(link);
    if (link.startsWith('ss://')) return _parseShadowsocks(link);
  } on FormatException {
    return null;
  }
  return null;
}

Server _parseVless(String link) {
  final uri = Uri.parse(link);
  final q = uri.queryParameters;
  final user = <String, dynamic>{
    'id': Uri.decodeComponent(uri.userInfo),
    'encryption': q['encryption']?.isNotEmpty == true
        ? q['encryption']
        : 'none',
  };
  final flow = q['flow'];
  if (flow != null && flow.isNotEmpty) user['flow'] = flow;

  final stream = _streamSettings(q, defaultSecurity: 'none');
  return _server(
    uri,
    protocol: 'vless',
    settings: {
      'vnext': [
        {
          'address': _host(uri),
          'port': uri.port,
          'users': [user],
        },
      ],
    },
    stream: stream,
  );
}

Server _parseTrojan(String link) {
  final uri = Uri.parse(link);
  final q = uri.queryParameters;
  final stream = _streamSettings(q, defaultSecurity: 'tls');
  return _server(
    uri,
    protocol: 'trojan',
    settings: {
      'servers': [
        {
          'address': _host(uri),
          'port': uri.port,
          'password': Uri.decodeComponent(uri.userInfo),
        },
      ],
    },
    stream: stream,
  );
}

Server _parseVmess(String link) {
  final json =
      jsonDecode(utf8.decode(decodeBase64Loose(link.substring(8)))) as Map;
  String s(String k) => '${json[k] ?? ''}';
  final net = s('net').isEmpty ? 'tcp' : s('net');
  final q = <String, String>{
    'type': net,
    'security': s('tls') == 'tls' ? 'tls' : 'none',
    'host': s('host'),
    'path': s('path'),
    'sni': s('sni'),
    'alpn': s('alpn'),
    'fp': s('fp'),
    'headerType': s('type'),
    // gRPC keeps its service name in "path" in vmess links.
    'serviceName': s('path'),
  };
  final port = int.parse(s('port'));
  final outbound = <String, dynamic>{
    'protocol': 'vmess',
    'settings': {
      'vnext': [
        {
          'address': s('add'),
          'port': port,
          'users': [
            {'id': s('id'), 'security': s('scy').isEmpty ? 'auto' : s('scy')},
          ],
        },
      ],
    },
    'streamSettings': _streamSettings(q, defaultSecurity: 'none'),
  };
  return Server(
    name: s('ps').isEmpty ? s('add') : s('ps'),
    address: s('add'),
    port: port,
    protocol: 'vmess',
    transport: _transportLabel(outbound['streamSettings']),
    outbound: outbound,
  );
}

Server _parseShadowsocks(String link) {
  var body = link.substring(5);
  var name = '';
  final hash = body.indexOf('#');
  if (hash >= 0) {
    name = Uri.decodeComponent(body.substring(hash + 1));
    body = body.substring(0, hash);
  }
  body = body.split('?').first;
  String userInfo;
  String hostPort;
  final at = body.lastIndexOf('@');
  if (at >= 0) {
    userInfo = body.substring(0, at);
    hostPort = body.substring(at + 1);
    if (!userInfo.contains(':')) {
      userInfo = utf8.decode(decodeBase64Loose(Uri.decodeComponent(userInfo)));
    } else {
      userInfo = Uri.decodeComponent(userInfo);
    }
  } else {
    // Legacy form: the whole method:pass@host:port is base64.
    final decoded = utf8.decode(decodeBase64Loose(body));
    final i = decoded.lastIndexOf('@');
    userInfo = decoded.substring(0, i);
    hostPort = decoded.substring(i + 1);
  }
  final colon = userInfo.indexOf(':');
  final method = userInfo.substring(0, colon);
  final password = userInfo.substring(colon + 1);
  final hp = Uri.parse('ss://$hostPort');
  final address = _host(hp);
  return Server(
    name: name.isEmpty ? address : name,
    address: address,
    port: hp.port,
    protocol: 'shadowsocks',
    transport: 'tcp',
    outbound: {
      'protocol': 'shadowsocks',
      'settings': {
        'servers': [
          {
            'address': address,
            'port': hp.port,
            'method': method,
            'password': password,
          },
        ],
      },
    },
  );
}

Server _server(
  Uri uri, {
  required String protocol,
  required Map<String, dynamic> settings,
  required Map<String, dynamic> stream,
}) {
  final name = uri.fragment.isEmpty
      ? _host(uri)
      : Uri.decodeComponent(uri.fragment);
  return Server(
    name: name,
    address: _host(uri),
    port: uri.port,
    protocol: protocol,
    transport: _transportLabel(stream),
    outbound: {
      'protocol': protocol,
      'settings': settings,
      'streamSettings': stream,
    },
  );
}

/// Uri keeps IPv6 hosts without brackets already; this only guards empty.
String _host(Uri uri) {
  if (uri.host.isEmpty) throw const FormatException('no host');
  return uri.host;
}

Map<String, dynamic> _streamSettings(
  Map<String, String> q, {
  required String defaultSecurity,
}) {
  var network = (q['type'] ?? 'tcp').toLowerCase();
  if (network == 'tcp') network = 'raw';
  if (network == 'splithttp') network = 'xhttp';
  final security = (q['security'] ?? defaultSecurity).toLowerCase();
  final stream = <String, dynamic>{'network': network, 'security': security};

  String? v(String key) {
    final value = q[key];
    return value == null || value.isEmpty ? null : value;
  }

  final host = v('host');
  final path = v('path');

  switch (network) {
    case 'raw':
      if (v('headerType') == 'http') {
        stream['rawSettings'] = {
          'header': {
            'type': 'http',
            'request': {
              'path': [path ?? '/'],
              if (host != null) 'headers': {'Host': host.split(',')},
            },
          },
        };
      }
    case 'ws':
      stream['wsSettings'] = {'path': ?path, 'host': ?host};
    case 'httpupgrade':
      stream['httpupgradeSettings'] = {'path': ?path, 'host': ?host};
    case 'grpc':
      stream['grpcSettings'] = {
        'serviceName': v('serviceName') ?? '',
        'authority': ?v('authority'),
        if (v('mode') == 'multi') 'multiMode': true,
      };
    case 'xhttp':
      final extra = v('extra');
      stream['xhttpSettings'] = {
        'path': ?path,
        'host': ?host,
        'mode': v('mode') ?? 'auto',
        if (extra != null) 'extra': jsonDecode(extra),
      };
    case 'kcp':
      stream['kcpSettings'] = {
        if (v('headerType') != null) 'header': {'type': v('headerType')},
        'seed': ?v('seed'),
      };
  }

  final sni = v('sni') ?? v('peer');
  final fp = v('fp');
  final alpn = v('alpn')?.split(',');
  if (security == 'tls') {
    stream['tlsSettings'] = {
      'serverName': sni ?? host,
      'fingerprint': ?fp,
      'alpn': ?alpn,
      if (v('allowInsecure') == '1' || v('insecure') == '1')
        'allowInsecure': true,
    };
  } else if (security == 'reality') {
    stream['realitySettings'] = {
      'serverName': sni ?? '',
      'fingerprint': fp ?? 'chrome',
      'publicKey': v('pbk') ?? '',
      'shortId': v('sid') ?? '',
      'spiderX': v('spx') ?? '',
      'mldsa65Verify': ?v('pqv'),
    };
  }
  return stream;
}

String _transportLabel(Map<String, dynamic> stream) {
  final network = stream['network'] ?? 'raw';
  final security = stream['security'] ?? 'none';
  return security == 'none' ? '$network' : '$network · $security';
}

/// Decodes standard or URL-safe base64, with or without padding.
List<int> decodeBase64Loose(String input) {
  var s = input.trim().replaceAll(RegExp(r'\s'), '');
  s = s.replaceAll('-', '+').replaceAll('_', '/');
  final pad = s.length % 4;
  if (pad > 0) s += '=' * (4 - pad);
  return base64.decode(s);
}
