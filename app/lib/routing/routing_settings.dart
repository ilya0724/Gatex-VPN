import 'dart:convert';

/// Which apps go through the VPN.
enum AppsMode { all, only, except }

enum RuleKind { domain, keyword, ip }

enum RuleAction { proxy, direct, block }

/// One own routing rule: a domain, keyword or address and what to do with it.
class RoutingRule {
  const RoutingRule({
    required this.kind,
    required this.value,
    required this.action,
    this.enabled = true,
  });

  final RuleKind kind;
  final String value;
  final RuleAction action;
  final bool enabled;

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'value': value,
    'action': action.name,
    'enabled': enabled,
  };

  factory RoutingRule.fromJson(Map<String, dynamic> j) => RoutingRule(
    kind: RuleKind.values.firstWhere(
      (e) => e.name == j['kind'],
      orElse: () => RuleKind.domain,
    ),
    value: (j['value'] as String?) ?? '',
    action: RuleAction.values.firstWhere(
      (e) => e.name == j['action'],
      orElse: () => RuleAction.proxy,
    ),
    enabled: (j['enabled'] as bool?) ?? true,
  );

  RoutingRule copyWith({
    RuleKind? kind,
    String? value,
    RuleAction? action,
    bool? enabled,
  }) => RoutingRule(
    kind: kind ?? this.kind,
    value: value ?? this.value,
    action: action ?? this.action,
    enabled: enabled ?? this.enabled,
  );
}

/// Routing choices of the user. [apps] holds Android package names or
/// desktop process names (lower-case, e.g. `chrome.exe`).
class RoutingSettings {
  const RoutingSettings({
    this.appsMode = AppsMode.all,
    this.apps = const [],
    this.rules = const [],
    this.directRu = true,
    this.blockAds = false,
  });

  final AppsMode appsMode;
  final List<String> apps;
  final List<RoutingRule> rules;
  final bool directRu;
  final bool blockAds;

  static const defaults = RoutingSettings();

  static const _prefix = 'gatex-routing:1:';

  Map<String, dynamic> toJson() => {
    'appsMode': appsMode.name,
    'apps': apps,
    'rules': [for (final r in rules) r.toJson()],
    'directRu': directRu,
    'blockAds': blockAds,
  };

  factory RoutingSettings.fromJson(Map<String, dynamic> j) => RoutingSettings(
    appsMode: AppsMode.values.firstWhere(
      (e) => e.name == j['appsMode'],
      orElse: () => AppsMode.all,
    ),
    apps: [for (final a in (j['apps'] as List?) ?? const []) a as String],
    rules: [
      for (final r in (j['rules'] as List?) ?? const [])
        RoutingRule.fromJson(r as Map<String, dynamic>),
    ],
    directRu: (j['directRu'] as bool?) ?? true,
    blockAds: (j['blockAds'] as bool?) ?? false,
  );

  /// Text to share: `gatex-routing:1:` + base64url of the JSON.
  String export() =>
      _prefix + base64Url.encode(utf8.encode(jsonEncode(toJson())));

  /// Reads text made by [export]. Throws [FormatException] on anything else.
  static RoutingSettings import(String text) {
    const bad = FormatException('Это не настройки GateX');
    final t = text.trim();
    if (!t.startsWith(_prefix)) throw bad;
    try {
      final body = base64Url.normalize(t.substring(_prefix.length).trim());
      final j = jsonDecode(utf8.decode(base64Url.decode(body)));
      if (j is! Map<String, dynamic>) throw bad;
      return RoutingSettings.fromJson(j);
    } catch (_) {
      throw bad;
    }
  }

  /// A message for the user when the settings cannot be applied, else null.
  String? validate() {
    if (appsMode == AppsMode.only && apps.isEmpty) {
      return 'Выберите хотя бы одно приложение';
    }
    for (final r in rules) {
      final v = r.value.trim();
      if (v.isEmpty) return 'Пустое правило';
      if (r.kind == RuleKind.ip && !_isIpOrCidr(v)) {
        return 'Неверный адрес: ${r.value}';
      }
    }
    return null;
  }

  RoutingSettings copyWith({
    AppsMode? appsMode,
    List<String>? apps,
    List<RoutingRule>? rules,
    bool? directRu,
    bool? blockAds,
  }) => RoutingSettings(
    appsMode: appsMode ?? this.appsMode,
    apps: apps ?? this.apps,
    rules: rules ?? this.rules,
    directRu: directRu ?? this.directRu,
    blockAds: blockAds ?? this.blockAds,
  );
}

bool _isIpOrCidr(String v) {
  final parts = v.split('/');
  if (parts.length > 2) return false;
  final addr = parts[0];
  final v6 = addr.contains(':');
  if (v6) {
    try {
      Uri.parseIPv6Address(addr);
    } on FormatException {
      return false;
    }
  } else {
    final o = addr.split('.');
    if (o.length != 4) return false;
    for (final p in o) {
      if (!RegExp(r'^\d{1,3}$').hasMatch(p) || int.parse(p) > 255) return false;
    }
  }
  if (parts.length == 2) {
    if (!RegExp(r'^\d{1,3}$').hasMatch(parts[1])) return false;
    if (int.parse(parts[1]) > (v6 ? 128 : 32)) return false;
  }
  return true;
}
