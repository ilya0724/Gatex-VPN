import '../subscription/server.dart';

/// Id of the app's own «Авто» entry in the server list.
const autoServerId = 'auto';

/// Servers «Авто» may use: real, not Russian, not the panel's own «Авто».
List<Server> autoCandidates(List<Server> all) => [
  for (final s in all)
    if (!s.isPlaceholder && !s.isRussian && !s.isPanelAuto) s,
];

/// The fastest candidate by [delays] (ms; null or missing means unknown and
/// ranks last). The [currentId] server stays when it answers and is not much
/// slower than the best, so the exit does not flip on every measurement.
Server? pickAuto(
  List<Server> candidates,
  Map<String, int?> delays, {
  String? currentId,
}) {
  if (candidates.isEmpty) return null;
  Server? best;
  for (final s in candidates) {
    final d = delays[s.id];
    if (d == null) continue;
    final b = best == null ? null : delays[best.id];
    if (b == null || d < b) best = s;
  }
  // Nothing answered: any candidate is as good as another.
  if (best == null) return candidates.first;
  if (currentId != null) {
    for (final s in candidates) {
      final d = delays[s.id];
      if (s.id == currentId && d != null && d <= delays[best.id]! * 1.5 + 30) {
        return s;
      }
    }
  }
  return best;
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
