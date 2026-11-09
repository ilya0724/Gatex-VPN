import 'dart:async';

import '../subscription/server.dart';

/// Id of the app's own «Авто» entry in the server list.
const autoServerId = 'auto';

/// Servers «Авто» may use: real, not Russian, not the panel's own «Авто».
List<Server> autoCandidates(List<Server> all) => [
  for (final s in all)
    if (!s.isPlaceholder && !s.isRussian && !s.isPanelAuto) s,
];

/// «Авто» goes tier by tier: main servers first, LTE only when no main
/// server has a known delay.
List<Server> autoMain(List<Server> candidates) => [
  for (final s in candidates)
    if (!s.isLte) s,
];

List<Server> autoLte(List<Server> candidates) => [
  for (final s in candidates)
    if (s.isLte) s,
];

/// True when [delays] already tell where «Авто» should go: some main server
/// has a known delay, or no main one has and some LTE one has.
bool autoDelaysKnown(List<Server> candidates, Map<String, int?> delays) =>
    candidates.any((s) => delays[s.id] != null);

/// The fastest candidate by [delays] (ms; null or missing means unknown and
/// ranks last). Main servers win over LTE ones whenever any main server
/// answered. The [currentId] server stays when it answers and is not much
/// slower than the best of its tier, so the exit does not flip on every
/// measurement.
Server? pickAuto(
  List<Server> candidates,
  Map<String, int?> delays, {
  String? currentId,
}) {
  if (candidates.isEmpty) return null;
  final main = autoMain(candidates);
  final lte = autoLte(candidates);
  final fromMain = _pickTier(main, delays, currentId);
  if (fromMain != null) return fromMain;
  final fromLte = _pickTier(lte, delays, currentId);
  if (fromLte != null) return fromLte;
  // Nothing answered: any main candidate is as good as another.
  return main.isNotEmpty ? main.first : lte.first;
}

/// Best known server of one tier, sticky to [currentId]; null when no server
/// of the tier has a known delay.
Server? _pickTier(
  List<Server> tier,
  Map<String, int?> delays,
  String? currentId,
) {
  Server? best;
  for (final s in tier) {
    final d = delays[s.id];
    if (d == null) continue;
    final b = best == null ? null : delays[best.id];
    if (b == null || d < b) best = s;
  }
  if (best == null) return null;
  if (currentId != null) {
    for (final s in tier) {
      final d = delays[s.id];
      if (s.id == currentId && d != null && d <= delays[best.id]! * 1.5 + 30) {
        return s;
      }
    }
  }
  return best;
}

/// The remembered «Авто» server to connect to at once, or null when it must
/// not be used: it is no candidate any more; fresh delays ([fresh]) mark it
/// unreachable; or it is an LTE server while a main server has a fresh delay.
Server? usableRemembered(
  List<Server> candidates,
  Map<String, int?> delays,
  String? lastId, {
  required bool fresh,
}) {
  if (lastId == null) return null;
  for (final s in candidates) {
    if (s.id != lastId) continue;
    if (fresh) {
      if (delays.containsKey(s.id) && delays[s.id] == null) return null;
      if (s.isLte && autoMain(candidates).any((m) => delays[m.id] != null)) {
        return null;
      }
    }
    return s;
  }
  return null;
}

/// Probes [tier] at once and completes with the first server that answers,
/// without waiting for the others; null when none does. The probes that are
/// still running when it completes keep going and report through [onResult]
/// (every probe does, answered or not).
Future<Server?> raceFirst(
  List<Server> tier,
  Future<int?> Function(Server s) probe, {
  void Function(Server s, int? ms)? onResult,
}) {
  if (tier.isEmpty) return Future.value(null);
  final first = Completer<Server?>();
  var pending = tier.length;
  void settle(Server s, int? ms) {
    onResult?.call(s, ms);
    if (ms != null && !first.isCompleted) first.complete(s);
    if (--pending == 0 && !first.isCompleted) first.complete(null);
  }

  for (final s in tier) {
    probe(s)
        .then((ms) => settle(s, ms), onError: (Object _) => settle(s, null));
  }
  return first.future;
}

/// The server «Авто» connects to at once. A remembered [lastId] that is
/// still a candidate is taken without any probe (`fromLast`). Otherwise main
/// candidates race and the first answer wins; LTE candidates race only when
/// no main one answered. When nothing answers, the pick falls back to the
/// first candidate so the connect still has a target.
Future<({Server? server, bool fromLast})> autoQuickPick(
  List<Server> candidates, {
  String? lastId,
  required Future<int?> Function(Server s) probe,
  void Function(Server s, int? ms)? onResult,
  void Function(String)? log,
}) async {
  if (candidates.isEmpty) return (server: null, fromLast: false);
  if (lastId != null) {
    for (final s in candidates) {
      if (s.id == lastId) return (server: s, fromLast: true);
    }
  }
  final main = autoMain(candidates);
  final lte = autoLte(candidates);
  log?.call('Авто: проверка основных серверов (${main.length})');
  var found = await raceFirst(main, probe, onResult: onResult);
  if (found == null && lte.isNotEmpty) {
    log?.call('Авто: основные не ответили, проверяем LTE (${lte.length})');
    found = await raceFirst(lte, probe, onResult: onResult);
  }
  return (
    server: found ?? (main.isNotEmpty ? main.first : lte.first),
    fromLast: false,
  );
}

/// Measures [candidates] for «Авто»: main servers first, all at once. LTE
/// servers are probed only when no main server answered. [probe] gets the
/// server and a unique number; results go into [delays].
Future<void> measureAutoTiers(
  List<Server> candidates,
  Map<String, int?> delays,
  Future<int?> Function(Server s, int n) probe,
  void Function(String) log,
) async {
  var n = 0;
  Future<void> run(List<Server> tier) => Future.wait([
    for (final s in tier) probe(s, n++).then((ms) => delays[s.id] = ms),
  ]);
  final main = autoMain(candidates);
  final lte = autoLte(candidates);
  log('Авто: проверка основных серверов (${main.length})');
  await run(main);
  if (main.any((s) => delays[s.id] != null) || lte.isEmpty) return;
  log('Авто: основные не ответили, проверяем LTE (${lte.length})');
  await run(lte);
}

/// Runs one job at a time. A call while one runs does not start another
/// but asks for exactly one more run after it (any number of calls coalesce),
/// so the last request always sees fresh state. All callers get the same
/// Future, which completes after the final run. A run that throws does not
/// cancel the requested one after it; the Future then fails with the last
/// error once everything has run.
class SingleFlight {
  Future<void>? _running;
  Future<void> Function()? _job;
  bool _again = false;
  bool get running => _running != null;

  Future<void> run(Future<void> Function() job) {
    _job = job;
    final r = _running;
    if (r != null) {
      _again = true;
      return r;
    }
    return _running = _drain();
  }

  Future<void> _drain() async {
    Object? error;
    StackTrace? stack;
    try {
      do {
        _again = false;
        try {
          await _job!();
        } catch (e, s) {
          error = e;
          stack = s;
        }
      } while (_again);
    } finally {
      _running = null;
    }
    if (error != null) Error.throwWithStackTrace(error, stack!);
  }
}

/// What `connect()` should do once the «Авто» pick is back. The user may
/// have chosen a server or cancelled while the candidates were measured.
/// Returns null to abort, otherwise the server to connect to.
Server? settleAutoConnect({
  required bool cancelled,
  required String selectedId,
  required Server? selected,
  required Server? picked,
}) {
  if (cancelled) return null;
  if (selectedId != autoServerId) return selected;
  return picked;
}
