import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config_builder.dart';
import '../core/vpn_core.dart';
import '../desktop/desktop_shell.dart';
import '../links.dart';
import '../subscription/fetcher.dart';
import '../subscription/server.dart';
import '../subscription/subscription.dart';
import '../ui/theme.dart' show GX;
import 'diagnose.dart';
import 'settings.dart';
import 'updates.dart';

/// Picks every live server and lets Xray keep the fastest one.
const autoServerId = 'auto';

class AppState extends ChangeNotifier {
  AppState({VpnCore? core}) : core = core ?? VpnCore.create();

  final VpnCore core;
  static const _app = MethodChannel('gatex/app');

  late SharedPreferences _prefs;
  late Settings settings;
  late DeviceInfo device;
  String appVersion = '';

  /// Folder for the core's log and the delay probes.
  late String _dataDir;
  String get coreLogPath => '$_dataDir${Platform.pathSeparator}core.log';

  /// What happened in the app, newest last, for the journal screen.
  final journal = <JournalEntry>[];

  RawSubscription? _raw;
  Subscription? subscription;
  String selectedId = autoServerId;

  VpnState vpnState = VpnState.disconnected;
  String? error;
  bool refreshing = false;

  /// Delay per server id in ms; null means no answer.
  final delays = <String, int?>{};

  /// Why a server failed its delay test, by server id.
  final delayErrors = <String, DelayFailure>{};
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

  /// What init is doing, shown if start-up hangs or fails.
  String initStep = 'запуск';

  /// Set when start-up failed; the app shows it instead of a blank screen.
  String? startupError;

  Future<T> _step<T>(String name, Future<T> Function() f) {
    initStep = name;
    return f().timeout(
      const Duration(seconds: 8),
      onTimeout: () => throw TimeoutException('$name: нет ответа 8 с'),
    );
  }

  Future<void> init(List<String> args) async {
    try {
      await _init(args);
    } catch (e, st) {
      startupError = '$initStep: $e\n$st';
      ready = true;
      notifyListeners();
    }
  }

  Future<void> _init(List<String> args) async {
    _prefs = await _step('настройки', SharedPreferences.getInstance);
    settings = Settings(_prefs);
    final dir = await _step('папка данных', getApplicationSupportDirectory);
    await dir.create(recursive: true);
    _dataDir = dir.path;
    final info = await _step('версия', PackageInfo.fromPlatform);
    appVersion = info.version;
    device = DeviceInfo(
      appVersion: appVersion,
      hwid: _hwid(),
      model: await _step('модель устройства', _deviceModel),
    );
    initStep = 'подписка';
    _restore();
    initStep = 'ядро';
    core.status.listen(
      _onStatus,
      onError: (Object e) => log('$e', error: true),
    );
    _app.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'link':
          await handleLink('${call.arguments}');
        case 'activate':
          await DesktopShell.instance.onActivate('${call.arguments}');
      }
    });
    ready = true;
    log('GateX $appVersion, ${Platform.operatingSystem}');
    notifyListeners();
    if (DesktopShell.supported) await DesktopShell.instance.attach(this);

    final initial = Platform.isAndroid
        ? await _app
              .invokeMethod<String>('initialLink')
              .timeout(const Duration(seconds: 5), onTimeout: () => null)
        : args.firstWhere((a) => a.startsWith('gatex://'), orElse: () => '');
    if (initial != null && initial.isNotEmpty) {
      await handleLink(initial);
    } else if (subscription?.isStale ?? false) {
      await refresh(quiet: true);
    }
    if (hasSubscription &&
        !connected &&
        (settings.autoConnect || DesktopShell.startedHidden(args))) {
      log('Автоподключение при запуске');
      unawaited(connect());
    }
    unawaited(_checkUpdate());
  }

  void log(String text, {bool error = false}) {
    journal.add(JournalEntry(DateTime.now(), text, error: error));
    if (journal.length > 400) journal.removeRange(0, journal.length - 400);
  }

  /// The last lines of the core's own log, for the journal screen.
  Future<String> readCoreLog({int maxBytes = 64 * 1024}) async {
    final f = File(coreLogPath);
    if (!f.existsSync()) return '';
    final len = await f.length();
    final raf = await f.open();
    try {
      final start = len > maxBytes ? len - maxBytes : 0;
      await raf.setPosition(start);
      return utf8.decode(await raf.read(len - start), allowMalformed: true);
    } finally {
      await raf.close();
    }
  }

  /// Saves a settings change and applies it to a running tunnel.
  void setTheme(String id) {
    settings.theme = id;
    GX.use(id);
    log('Тема: $id');
    notifyListeners();
  }

  Future<void> updateSettings(
    void Function(Settings s) change, {
    bool reconnect = false,
  }) async {
    change(settings);
    notifyListeners();
    if (reconnect && connected) await _reconnect();
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
    final logFile = File(coreLogPath);
    // A fresh log per connection keeps the journal about this session.
    if (logFile.existsSync()) logFile.deleteSync();
    final serverIps = await _resolveServers();
    String config({required bool ipv6}) => buildConnectConfig(
      servers: chosen != null ? [chosen] : servers,
      host: core.tunHost,
      options: ConnectOptions(
        ipv6: ipv6,
        directRu: settings.directRu,
        dns: settings.dns.servers,
        logFile: coreLogPath,
        serverIps: serverIps,
      ),
    );
    vpnState = VpnState.connecting;
    notifyListeners();
    log('Подключение: ${chosen?.name ?? 'Авто (${servers.length})'}');
    final ipv6 = settings.ipv6 && _ipv6;
    var failure = await core.start(config(ipv6: ipv6));
    if (failure != null && ipv6 && failure.contains('fdfe:')) {
      _ipv6 = false;
      log('IPv6 недоступен в системе, подключаемся только по IPv4');
      failure = await core.start(config(ipv6: false));
    }
    if (failure != null) {
      vpnState = VpnState.disconnected;
      error = _humanError(failure);
      log('Ошибка подключения: $failure', error: true);
      notifyListeners();
    }
  }

  /// IPs of every server, looked up before the tunnel is up. Android
  /// skips this: the app's own traffic is outside its VPN anyway.
  Future<List<String>> _resolveServers() async {
    if (Platform.isAndroid) return const [];
    final ips = <String>{};
    await Future.wait([
      for (final host in {for (final s in servers) s.address})
        InternetAddress.lookup(host)
            .timeout(const Duration(seconds: 3))
            .then((list) => ips.addAll(list.map((a) => a.address)))
            .catchError((_) => ips),
    ]);
    return ips.toList();
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
    if (s.state != vpnState) {
      if (s.state == VpnState.connected) log('Подключено');
      if (s.state == VpnState.disconnected) log('Отключено');
    }
    vpnState = s.state;
    _syncLive();
    if (s.error != null) {
      error = _humanError(s.error!);
      log('Ядро остановилось: ${s.error}', error: true);
    }
    notifyListeners();
  }

  /// Speed and traffic of the running tunnel, updated every second.
  final live = ValueNotifier<LiveStats?>(null);

  /// The address sites see while connected, and its country.
  final exit = ValueNotifier<ExitInfo?>(null);
  Timer? _liveTimer;
  (int, int)? _lastTraffic;

  void _syncLive() {
    if (connected && _liveTimer == null) {
      _lastTraffic = null;
      _liveTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
      unawaited(_lookupExit());
    } else if (!connected && _liveTimer != null) {
      _liveTimer?.cancel();
      _liveTimer = null;
      live.value = null;
      exit.value = null;
    }
  }

  Future<void> _tick() async {
    final t = await core.traffic();
    if (t == null || !connected) return;
    final last = _lastTraffic;
    _lastTraffic = t;
    live.value = LiveStats(
      up: t.$1,
      down: t.$2,
      upSpeed: last == null ? 0 : max(0, t.$1 - last.$1),
      downSpeed: last == null ? 0 : max(0, t.$2 - last.$2),
    );
  }

  Future<void> _lookupExit() async {
    for (var i = 0; i < 3 && connected; i++) {
      await Future<void>.delayed(Duration(seconds: 1 + i * 3));
      final body = await core.fetch(
        'http://ip-api.com/json/?fields=status,query,country,countryCode&lang=ru',
      );
      try {
        final j = jsonDecode(body ?? '') as Map<String, dynamic>;
        if (j['status'] == 'success' && connected) {
          exit.value = ExitInfo(
            ip: j['query'] as String,
            countryCode: j['countryCode'] as String? ?? '',
            country: j['country'] as String? ?? '',
          );
          return;
        }
      } on Object {
        // Try again: the tunnel may still be settling.
      }
    }
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

  /// Servers whose delay test is running right now.
  final probing = <String>{};

  Future<void> testDelays() async {
    if (testingDelays || servers.isEmpty) return;
    testingDelays = true;
    delays.clear();
    delayErrors.clear();
    notifyListeners();
    log('Проверка серверов: ${servers.length}');
    final queue = [...servers];
    var n = 0;
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final s = queue.removeAt(0);
        probing.add(s.id);
        notifyListeners();
        final logPath = '$_dataDir${Platform.pathSeparator}probe-${n++}.log';
        var r = await _probe(s, logPath, 6000);
        // A slow LTE route can miss the first window; give it one more go.
        if (r.ms == null) r = await _probe(s, logPath, 10000);
        probing.remove(s.id);
        delays[s.id] = r.ms;
        if (r.ms == null) {
          final failure = DelayFailure.from(r.error ?? '');
          delayErrors[s.id] = failure;
          log('${s.name}: ${failure.summary}\n${failure.detail}', error: true);
        }
        notifyListeners();
      }
    }

    await Future.wait(List.generate(min(4, queue.length), (_) => worker()));
    testingDelays = false;
    notifyListeners();
  }

  /// One delay test. Xray's own log for the probe says why it failed,
  /// which the HTTP error alone ("EOF") does not.
  Future<DelayResult> _probe(Server s, String logPath, int timeoutMs) async {
    final logFile = File(logPath);
    if (logFile.existsSync()) logFile.deleteSync();
    // On Android the probes share one process (and Xray's global logger)
    // with the tunnel, so only the desktop helper gets a probe log.
    final r = await core.measureDelay(
      buildProbeConfig(s, logFile: Platform.isAndroid ? null : logPath),
      timeoutMs: timeoutMs,
    );
    String coreLog = '';
    try {
      if (logFile.existsSync()) {
        coreLog = logFile.readAsStringSync();
        logFile.deleteSync();
      }
    } on FileSystemException {
      // The core may still hold the file on Windows; the reason is optional.
    }
    if (r.ms != null) return r;
    final lines = coreLog
        .split('\n')
        .where((l) => l.contains('failed') || l.contains('[Error]'))
        // Drop the timestamp and the repeated package prefix.
        .map((l) => l.replaceFirst(RegExp(r'^\S+ \S+ \[\w+\] '), ''))
        .toList();
    final tail = lines.length > 3 ? lines.sublist(lines.length - 3) : lines;
    return DelayResult.failed([r.error ?? '', ...tail].join('\n').trim());
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

class LiveStats {
  const LiveStats({
    required this.up,
    required this.down,
    required this.upSpeed,
    required this.downSpeed,
  });

  /// Bytes since connecting, and bytes in the last second.
  final int up, down, upSpeed, downSpeed;
}

class ExitInfo {
  const ExitInfo({
    required this.ip,
    required this.countryCode,
    required this.country,
  });
  final String ip, countryCode, country;
}
