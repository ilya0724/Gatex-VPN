import '../subscription/server.dart';

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
