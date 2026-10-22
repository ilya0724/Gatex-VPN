import 'dart:convert';

import 'share_link.dart' show decodeBase64Loose;

/// One server from the subscription, already turned into Xray outbounds.
class Server {
  /// [name] may carry Happ's `Name?serverDescription=<base64>` form, which
  /// Remnawave uses for the host's description; it is split off here.
  Server({
    required String name,
    String? description,
    required this.address,
    required this.port,
    required this.protocol,
    required this.transport,
    required this.outbound,
    this.extraOutbounds = const [],
    this.routing,
    this.dns,
  }) : name = _splitDescription(name).$1,
       description = _nonEmpty(description) ?? _splitDescription(name).$2;

  static (String, String?) _splitDescription(String raw) {
    final i = raw.indexOf('?serverDescription=');
    if (i < 0) return (raw, null);
    final value = raw.substring(i + '?serverDescription='.length).trim();
    String? text;
    try {
      text = utf8.decode(decodeBase64Loose(Uri.decodeComponent(value)));
    } on Object {
      text = value;
    }
    return (raw.substring(0, i).trim(), _nonEmpty(text));
  }

  static String? _nonEmpty(String? s) =>
      s == null || s.trim().isEmpty ? null : s.trim();

  /// The host's description from the panel ("Для YouTube и игр"), shown
  /// under the name the way Happ shows it.
  final String? description;

  /// Display name, usually "🇩🇪 Германия" from the panel.
  final String name;
  final String address;
  final int port;

  /// vless, trojan, vmess, shadowsocks.
  final String protocol;

  /// raw, ws, grpc, xhttp... with the security layer, e.g. "raw · reality".
  final String transport;

  /// The proxy outbound itself. Its tag is rewritten when a config is built.
  final Map<String, dynamic> outbound;

  /// Helper outbounds the proxy dials through (fragment, chains), as the
  /// panel's Xray JSON template defines them.
  final List<Map<String, dynamic>> extraOutbounds;

  /// Routing and DNS from the panel's Xray JSON template, when it has them.
  final Map<String, dynamic>? routing;
  final Map<String, dynamic>? dns;

  /// Stable id for remembering the user's choice between refreshes.
  String get id => '$name|$address|$port';

  /// Remnawave sends entries such as "Подписка истекла" with a dummy
  /// address. They carry a message, not a server.
  bool get isPlaceholder {
    const dummy = {'0.0.0.0', '::', ''};
    return dummy.contains(address) || port <= 1;
  }

  /// The flag emoji the name starts with, if any.
  String get flag {
    final runes = name.runes.toList();
    if (runes.length >= 2 && _isRegional(runes[0]) && _isRegional(runes[1])) {
      return String.fromCharCodes(runes.sublist(0, 2));
    }
    return '';
  }

  /// The name without the leading flag, which the list draws as a badge.
  /// Other emoji stay: they are part of how the panel names the server.
  String get title {
    final f = flag;
    final rest = (f.isEmpty ? name : name.substring(f.length))
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
    return rest.isEmpty ? name.trim() : rest;
  }

  /// Two-letter country code from the flag emoji, or from the name when
  /// the panel wrote the country in words.
  String get countryCode {
    final f = flag;
    if (f.isNotEmpty) {
      return String.fromCharCodes(f.runes.map((r) => r - 0x1F1E6 + 0x41));
    }
    final lower = name.toLowerCase();
    for (final e in countryNames.entries) {
      // A stem, so "Германии" and "Германия" both match.
      final n = e.value.toLowerCase();
      if (lower.contains(n.length > 5 ? n.substring(0, n.length - 1) : n)) {
        return e.key;
      }
    }
    final code = RegExp(r'\b([A-Z]{2})\b').allMatches(name).map((m) => m[1]!);
    for (final c in code) {
      if (countryNames.containsKey(c)) return c;
    }
    return '';
  }

  /// Servers for mobile networks that throttle or whitelist traffic.
  bool get isLte => name.toUpperCase().contains('LTE');

  static bool _isRegional(int r) => r >= 0x1F1E6 && r <= 0x1F1FF;
}

/// Country names for the server list, by ISO code.
const countryNames = {
  'RU': 'Россия',
  'DE': 'Германия',
  'NL': 'Нидерланды',
  'FR': 'Франция',
  'PL': 'Польша',
  'FI': 'Финляндия',
  'SE': 'Швеция',
  'NO': 'Норвегия',
  'DK': 'Дания',
  'EE': 'Эстония',
  'LV': 'Латвия',
  'LT': 'Литва',
  'GB': 'Великобритания',
  'US': 'США',
  'CA': 'Канада',
  'TR': 'Турция',
  'KZ': 'Казахстан',
  'AM': 'Армения',
  'GE': 'Грузия',
  'AE': 'ОАЭ',
  'JP': 'Япония',
  'SG': 'Сингапур',
  'HK': 'Гонконг',
  'AT': 'Австрия',
  'CH': 'Швейцария',
  'IT': 'Италия',
  'ES': 'Испания',
  'CZ': 'Чехия',
  'RO': 'Румыния',
  'BG': 'Болгария',
  'HU': 'Венгрия',
  'UA': 'Украина',
  'BY': 'Беларусь',
  'MD': 'Молдова',
  'RS': 'Сербия',
  'IE': 'Ирландия',
  'BE': 'Бельгия',
  'LU': 'Люксембург',
  'IL': 'Израиль',
  'IN': 'Индия',
};
