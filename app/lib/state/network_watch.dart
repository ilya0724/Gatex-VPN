import 'dart:async';
import 'dart:io';

/// Names of the VPN's own TUN interfaces (see config_builder.dart); their
/// addresses change with every connect and must not count as a network change.
const _tunNames = {'tun0', 'gatex', 'gatex0'};

/// Windows' own IPv6 transition tunnels. Their addresses come and go by
/// themselves (Teredo re-qualifies when the routes change, e.g. when the
/// GateX TUN comes up), so watching them made a reconnect loop.
const _systemTunnels = ['teredo', 'isatap', '6to4', 'ip-https'];

/// One snapshot entry per interface: its IPv4 addresses, or only the fact
/// that it has IPv6. Switching networks always changes IPv4; IPv6 privacy
/// addresses rotate on their own and must not look like a new network.
Set<String> networkSnapshot(Iterable<(String, List<InternetAddress>)> ifaces) {
  final out = <String>{};
  for (final (rawName, addrs) in ifaces) {
    final name = rawName.toLowerCase();
    if (_tunNames.contains(name) || name.startsWith('gatex')) continue;
    if (_systemTunnels.any(name.contains)) continue;
    var v6 = false;
    for (final a in addrs) {
      if (a.isLoopback || a.isLinkLocal) continue;
      if (a.type == InternetAddressType.IPv4) {
        if (_isOwnTun(a)) continue;
        out.add('$rawName|${a.address}');
      } else if (a.type == InternetAddressType.IPv6) {
        v6 = true;
      }
    }
    if (v6) out.add('$rawName|v6');
  }
  return out;
}

/// The GateX TUN's own subnet (gateway 172.19.0.1/30 in config_builder.dart),
/// whatever name Windows gives the adapter ("GateX 2" after a stale one).
bool _isOwnTun(InternetAddress a) {
  final b = a.rawAddress;
  return b.length == 4 && b[0] == 172 && b[1] == 19 && b[2] == 0 && b[3] < 4;
}

/// Desktop only: polls the addresses of the network interfaces and emits when
/// they change (Wi-Fi <-> cable, another Wi-Fi, network lost and back).
/// Several changes within [debounce] give one event.
class NetworkWatch {
  NetworkWatch({
    this.interval = const Duration(seconds: 3),
    this.debounce = const Duration(seconds: 2),
    Future<Set<String>> Function()? snapshot,
  }) : _snapshot = snapshot ?? _systemSnapshot;

  final Duration interval;
  final Duration debounce;
  final Future<Set<String>> Function() _snapshot;

  final _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;

  Timer? _poll;
  Timer? _settle;
  Set<String>? _last;
  var _busy = false;
  var _gen = 0;

  bool get running => _poll != null;

  void start() {
    if (_poll != null) return;
    final gen = ++_gen;
    _last = null;
    _poll = Timer.periodic(interval, (_) => unawaited(_check(gen)));
    // The first snapshot is the baseline, not a change.
    unawaited(_check(gen));
  }

  void stop() {
    _gen++;
    _poll?.cancel();
    _poll = null;
    _settle?.cancel();
    _settle = null;
    _last = null;
    _busy = false;
  }

  Future<void> _check(int gen) async {
    if (_busy) return;
    _busy = true;
    try {
      final now = await _snapshot();
      if (gen != _gen) return;
      final before = _last;
      _last = now;
      if (before == null || _same(before, now)) return;
      _settle?.cancel();
      _settle = Timer(debounce, () {
        _settle = null;
        if (gen == _gen && !_changes.isClosed) _changes.add(null);
      });
    } catch (_) {
      // A failed read is not a network change; try again next tick.
    } finally {
      if (gen == _gen) _busy = false;
    }
  }

  static bool _same(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  static Future<Set<String>> _systemSnapshot() async {
    // Loopback and link-local (fe80::/10, 169.254.0.0/16) are left out so
    // they cannot cause false events.
    final list = await NetworkInterface.list(
      includeLoopback: false,
      includeLinkLocal: false,
    );
    return networkSnapshot([for (final i in list) (i.name, i.addresses)]);
  }
}
