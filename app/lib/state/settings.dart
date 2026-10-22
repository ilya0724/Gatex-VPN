import 'package:shared_preferences/shared_preferences.dart';

/// A DNS choice from the settings screen.
class DnsPreset {
  const DnsPreset(this.id, this.label, this.note, this.servers);
  final String id;
  final String label;
  final String note;
  final List<String> servers;
}

const dnsPresets = [
  DnsPreset('cloudflare', 'Cloudflare', '1.1.1.1 · быстрый', [
    '1.1.1.1',
    '1.0.0.1',
  ]),
  DnsPreset('google', 'Google', '8.8.8.8', ['8.8.8.8', '8.8.4.4']),
  DnsPreset('quad9', 'Quad9', '9.9.9.9 · блокирует вредоносные сайты', [
    '9.9.9.9',
    '149.112.112.112',
  ]),
  DnsPreset('adguard', 'AdGuard', '94.140.14.14 · без рекламы', [
    '94.140.14.14',
    '94.140.15.15',
  ]),
];

/// The user's settings, stored in shared preferences one key each.
class Settings {
  Settings(this._prefs);
  final SharedPreferences _prefs;

  bool _flag(String key, bool fallback) => _prefs.getBool(key) ?? fallback;

  /// Connect as soon as the app starts.
  bool get autoConnect => _flag('set.autoConnect', false);
  set autoConnect(bool v) => _prefs.setBool('set.autoConnect', v);

  /// Desktop: start with the system (Windows Task Scheduler, Linux XDG
  /// autostart). The OS side is kept in sync by DesktopShell.
  bool get launchAtStartup => _flag('set.launchAtStartup', false);
  set launchAtStartup(bool v) => _prefs.setBool('set.launchAtStartup', v);

  /// Desktop: the close button hides the window to the tray, so the VPN
  /// keeps running.
  bool get closeToTray => _flag('set.closeToTray', true);
  set closeToTray(bool v) => _prefs.setBool('set.closeToTray', v);

  /// Russian sites go around the tunnel.
  bool get directRu => _flag('set.directRu', true);
  set directRu(bool v) => _prefs.setBool('set.directRu', v);

  bool get ipv6 => _flag('set.ipv6', true);
  set ipv6(bool v) => _prefs.setBool('set.ipv6', v);

  DnsPreset get dns {
    final id = _prefs.getString('set.dns');
    return dnsPresets.firstWhere(
      (p) => p.id == id,
      orElse: () => dnsPresets.first,
    );
  }

  set dns(DnsPreset v) => _prefs.setString('set.dns', v.id);

  /// Colour theme id: green, black or white.
  String get theme => _prefs.getString('set.theme') ?? 'green';
  set theme(String v) => _prefs.setString('set.theme', v);
}
