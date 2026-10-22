import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config_builder.dart';
import '../core/vpn_core.dart';
import '../links.dart';
import '../subscription/fetcher.dart';
import '../subscription/server.dart';
import '../subscription/subscription.dart';
import 'updates.dart';

/// Picks every live server and lets Xray keep the fastest one.
const autoServerId = 'auto';

class AppState extends ChangeNotifier {
  AppState({VpnCore? core}) : core = core ?? VpnCore.create();

  final VpnCore core;
  static const _app = MethodChannel('gatex/app');

  late SharedPreferences _prefs;
  late DeviceInfo device;
  String appVersion = '';

  RawSubscription? _raw;
  Subscription? subscription;
  String selectedId = autoServerId;

  VpnState vpnState = VpnState.disconnected;
  String? error;
  bool refreshing = false;

  /// Delay per server id in ms; null means no answer.
  final delays = <String, int?>{};
  bool testingDelays = false;

  AppUpdate? update;
  bool ready = false;

  bool get hasSubscription => subscription != null;
  bool get connected => vpnState == VpnState.connected;
  bool get busy =>
      vpnState == VpnState.connecting || vpnState == VpnState.disconnecting;

  List<Server> get servers => subscription?.servers ?? const [];

  Server? get selectedServer {
    if (selectedId == autoServerId) return null;
    for (final s in servers) {
      if (s.id == selectedId) return s;
    }
    return null;
  }

  Future<void> init(List<String> args) async {
    _prefs = await SharedPreferences.getInstance();
    final info = await PackageInfo.fromPlatform();
    appVersion = info.version;
    device = DeviceInfo(
      appVersion: appVersion,
      hwid: _hwid(),
      model: await _deviceModel(),
    );
    _restore();
    core.status.listen(_onStatus);
    _app.setMethodCallHandler((call) async {
      if (call.method == 'link') await handleLink('${call.arguments}');
    });
    ready = true;
    notifyListeners();

    final initial = Platform.isAndroid
        ? await _app.invokeMethod<String>('initialLink')
        : args.firstWhere((a) => a.startsWith('gatex://'), orElse: () => '');
    if (initial != null && initial.isNotEmpty) {
      await handleLink(initial);
    } else if (subscription?.isStale ?? false) {
      unawaited(refresh(quiet: true));
    }
    unawaited(_checkUpdate());
  }

  String _hwid() {
    var id = _prefs.getString('hwid');
    if (id == null) {
      final r = Random.secure();
      id = List.generate(
        16,
        (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      _prefs.setString('hwid', id);
    }
    return id;
  }

  Future<String> _deviceModel() async {
    if (Platform.isAndroid) {
      return await _app.invokeMethod<String>('deviceModel') ?? 'Android';
    }
    return Platform.localHostname;
  }

  void _restore() {
    selectedId = _prefs.getString('selected') ?? autoServerId;
    final saved = _prefs.getString('subscription');
    if (saved == null) return;
    try {
      final m = jsonDecode(saved) as Map<String, dynamic>;
      _raw = RawSubscription(
        m['url'] as String,
        Map<String, String>.from(m['headers'] as Map),
        m['body'] as String,
        DateTime.parse(m['fetchedAt'] as String),
      );
      subscription = _raw!.parse();
    } on Object {
      _prefs.remove('subscription');
    }
  }

  void _save(RawSubscription raw) {
    _prefs.setString(
      'subscription',
      jsonEncode({
        'url': raw.url,
        'headers': raw.headers,
        'body': raw.body,
        'fetchedAt': raw.fetchedAt.toIso8601String(),
      }),
    );
  }

  /// Handles gatex:// links from the bot and the cabinet.
  Future<void> handleLink(String link) async {
    final url = subscriptionUrlFromLink(link);
    if (url != null) await importSubscription(url);
  }

  /// Loads a subscription from a link the user gave. Returns an error
  /// message for the import screen, or null on success.
  Future<String?> importSubscription(String url) async {
    refreshing = true;
    notifyListeners();
    try {
      final raw = await fetchSubscription(url, device);
      _apply(raw);
      return null;
    } on SubscriptionException catch (e) {
      return e.message;
    } finally {
      refreshing = false;
      notifyListeners();
    }
  }

  Future<void> refresh({bool quiet = false}) async {
    final url = _raw?.url;
    if (url == null || refreshing) return;
    refreshing = true;
    notifyListeners();
    try {
      _apply(await fetchSubscription(url, device));
      if (connected) await _reconnect();
    } on SubscriptionException catch (e) {
      if (!quiet) error = e.message;
    } finally {
      refreshing = false;
      notifyListeners();
    }
  }

  void _apply(RawSubscription raw) {
    _raw = raw;
    subscription = raw.parse();
    _save(raw);
    delays.removeWhere((id, _) => !servers.any((s) => s.id == id));
    if (selectedId != autoServerId && selectedServer == null) {
      select(autoServerId);
    }
    error = null;
  }

  Future<void> removeSubscription() async {
    if (connected) await core.stop();
    _raw = null;
    subscription = null;
    delays.clear();
    await _prefs.remove('subscription');
    notifyListeners();
  }

  Future<void> select(String id) async {
    selectedId = id;
    await _prefs.setString('selected', id);
    notifyListeners();
    if (connected) await _reconnect();
  }

  Future<void> toggle() async {
    if (busy) return;
    if (connected) {
      await core.stop();
    } else {
      await connect();
    }
  }

  Future<void> connect() async {
    error = null;
    final sub = subscription;
    if (sub == null) return;
    if (sub.servers.isEmpty) {
      error = sub.notices.isNotEmpty
          ? sub.notices.first
          : 'В подписке нет серверов';
      notifyListeners();
      return;
    }
    if (!await core.prepare()) {
      error = Platform.isAndroid
          ? 'Нужно разрешить GateX создавать VPN'
          : 'Не найден модуль gatex-core. Переустановите приложение';
      notifyListeners();
      return;
    }
    final chosen = selectedServer;
    String config({required bool ipv6}) => buildConnectConfig(
      servers: chosen != null ? [chosen] : servers,
      host: core.tunHost,
      ipv6: ipv6,
    );
    vpnState = VpnState.connecting;
    notifyListeners();
    var failure = await core.start(config(ipv6: _ipv6));
    if (failure != null && _ipv6 && failure.contains('fdfe:')) {
      _ipv6 = false;
      failure = await core.start(config(ipv6: false));
    }
    if (failure != null) {
      vpnState = VpnState.disconnected;
      error = _humanError(failure);
      notifyListeners();
    }
  }

  /// Turned off for the session once the system refuses an IPv6 address.
  bool _ipv6 = true;

  Future<void> _reconnect() async {
    // Listen before stopping so the disconnect event cannot slip past.
    final down = core.status
        .firstWhere((s) => s.state == VpnState.disconnected)
        .timeout(
          const Duration(seconds: 6),
          onTimeout: () => const VpnStatus(VpnState.disconnected),
        );
    await core.stop();
    await down;
    await connect();
  }

  void _onStatus(VpnStatus s) {
    vpnState = s.state;
    if (s.error != null) error = _humanError(s.error!);
    notifyListeners();
  }

  String _humanError(String raw) {
    final t = raw.toLowerCase();
    if (t.contains('wintun') || t.contains('access is denied')) {
      return 'Не хватает прав администратора. Запустите GateX от имени администратора';
    }
    if (t.contains('not permitted') || t.contains('dismissed')) {
      return 'Не удалось получить права для VPN';
    }
    return 'Не удалось подключиться: ${raw.split('\n').first}';
  }

  Future<void> testDelays() async {
    if (testingDelays || servers.isEmpty) return;
    testingDelays = true;
    delays.clear();
    notifyListeners();
    final queue = [...servers];
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final s = queue.removeAt(0);
        delays[s.id] = await core.measureDelay(buildProbeConfig(s));
        notifyListeners();
      }
    }

    await Future.wait(List.generate(min(4, queue.length), (_) => worker()));
    testingDelays = false;
    notifyListeners();
  }

  Future<void> _checkUpdate() async {
    update = await checkForUpdate(appVersion);
    if (update != null) notifyListeners();
  }

  void clearError() {
    error = null;
    notifyListeners();
  }
}
