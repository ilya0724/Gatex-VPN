import 'dart:io';

/// Собственные процессы GateX (в нижнем регистре): их нельзя выбирать
/// для маршрутизации.
const _own = {'gatex.exe', 'gatex-core.exe', 'gatex', 'gatex-core'};

/// Xray сравнивает имя процесса с учётом регистра, поэтому имена остаются
/// такими, как их сообщает система. Повторы отбрасываются без учёта
/// регистра: остаётся первое написание.
List<String> _clean(Iterable<String> names) {
  final seen = <String>{};
  final out = <String>[];
  for (final raw in names) {
    final n = raw.trim();
    final key = n.toLowerCase();
    if (n.isEmpty || _own.contains(key) || !seen.add(key)) continue;
    out.add(n);
  }
  return out..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
}

/// Варианты написания для поля `process` в Xray. Xray сравнивает имя
/// с учётом регистра, а Windows — нет: вписанное вручную `faceit.exe`
/// не совпало бы с `FACEIT.exe`. Поэтому к каждому имени добавляются
/// строчный, прописной и «Первая заглавная» варианты (без `.exe`, который
/// Xray всё равно отбрасывает). Смешанный регистр вроде `FaceIt` покрывает
/// только выбор из списка запущенных программ.
List<String> processSpellings(Iterable<String> names) {
  final out = <String>[];
  void add(String s) {
    if (s.isNotEmpty && !out.contains(s)) out.add(s);
  }

  for (final raw in names) {
    final n = raw.trim();
    final stem = n.toLowerCase().endsWith('.exe')
        ? n.substring(0, n.length - 4)
        : n;
    add(n);
    add(stem);
    add(stem.toLowerCase());
    add(stem.toUpperCase());
    if (stem.isNotEmpty) {
      add(stem[0].toUpperCase() + stem.substring(1).toLowerCase());
    }
  }
  return out;
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

/// Разбирает цели ссылок `/proc/<pid>/exe`: Xray сравнивает имя файла
/// программы (а не `comm`, который обрезан до 15 символов). Удалённый
/// после запуска файл ядро помечает суффиксом ` (deleted)`.
List<String> parseProcExe(Iterable<String> targets) => _clean([
  for (var t in targets)
    if ((t = t.trim()).isNotEmpty)
      (t.endsWith(' (deleted)')
              ? t.substring(0, t.length - ' (deleted)'.length)
              : t)
          .split('/')
          .last,
]);

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
          names.add(Link('${e.path}/exe').targetSync());
        } catch (_) {
          // процесс исчез, чужой или это поток ядра без exe
        }
      }
      return parseProcExe(names);
    }
  } catch (_) {}
  return [];
}
