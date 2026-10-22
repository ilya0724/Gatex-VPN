/// Addresses the app points users to.
abstract final class Links {
  static const bot = 'https://t.me/gatexvpn_bot';
  static const cabinet = 'https://t.me/gatexvpn_bot?startapp';
  static const support = 'https://t.me/gatexvpn_support';
  static const channel = 'https://t.me/gaatex_vpn';
  static const site = 'https://gatexx.ru';

  /// {"version": "1.0.1", "notes": "...", "android": {"url": ...}, ...}
  static const updateManifest = 'https://gatexx.ru/app/version.json';
}

/// Pulls a subscription URL out of an incoming link:
/// `gatex://import?url=<encoded>`, `gatex://add/<url>`, or the URL itself.
String? subscriptionUrlFromLink(String link) {
  final text = link.trim();
  if (text.startsWith('http://') || text.startsWith('https://')) return text;
  final uri = Uri.tryParse(text);
  if (uri == null || uri.scheme != 'gatex') return null;
  final param = uri.queryParameters['url'];
  if (param != null && param.isNotEmpty) return param;
  final add = text.indexOf('://add/');
  if (add >= 0) {
    final rest = Uri.decodeComponent(text.substring(add + 7));
    if (rest.startsWith('http')) return rest;
  }
  return null;
}
