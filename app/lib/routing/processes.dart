import 'dart:io';

/// Собственные процессы GateX: их нельзя выбирать для маршрутизации.
const _own = {'gatex.exe', 'gatex-core.exe', 'gatex', 'gatex-core'};

List<String> _clean(Iterable<String> names) {
  final set = <String>{};
  for (final raw in names) {
    final n = raw.trim().toLowerCase();
    if (n.isNotEmpty && !_own.contains(n)) set.add(n);
  }
  return set.toList()..sort();
}

/// Разбирает вывод `tasklist /fo csv /nh`: имя — первое поле в кавычках.
List<String> parseTasklistCsv(String out) {
  final names = <String>[];
  for (final line in out.split('\n')) {
    final t = line.trim();
    if (!t.startsWith('"')) continue;
    final end = t.indexOf('"', 1);
    if (end > 1) names.add(t.substring(1, end));
  }
  return _clean(names);
}

/// Разбирает содержимое `/proc/<pid>/comm` (с завершающим переводом строки).
List<String> parseProcComm(Iterable<String> names) => _clean(names);

/// Имена запущенных программ (то, с чем сравнивает поле `process` в Xray).
/// На Android и других платформах — пустой список.
Future<List<String>> runningProcesses() async {
  try {
    if (Platform.isWindows) {
      final r = await Process.run('tasklist', ['/fo', 'csv', '/nh']);
      if (r.exitCode != 0) return [];
      return parseTasklistCsv(r.stdout.toString());
    }
    if (Platform.isLinux) {
      final names = <String>[];
      await for (final e in Directory('/proc').list(followLinks: false)) {
        final pid = e.path.split('/').last;
        if (int.tryParse(pid) == null) continue;
        try {
          names.add(await File('${e.path}/comm').readAsString());
        } catch (_) {
          // процесс исчез или недоступен
        }
      }
      return parseProcComm(names);
    }
  } catch (_) {}
  return [];
}
