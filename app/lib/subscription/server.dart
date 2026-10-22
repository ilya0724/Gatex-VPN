/// One server from the subscription, already turned into Xray outbounds.
class Server {
  Server({
    required this.name,
    required this.address,
    required this.port,
    required this.protocol,
    required this.transport,
    required this.outbound,
    this.extraOutbounds = const [],
    this.routing,
    this.dns,
  });

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

  /// The name without the leading flag.
  String get title {
    final f = flag;
    return f.isEmpty ? name.trim() : name.substring(f.length).trim();
  }

  static bool _isRegional(int r) => r >= 0x1F1E6 && r <= 0x1F1FF;
}
