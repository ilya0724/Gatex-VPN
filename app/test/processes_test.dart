import 'package:flutter_test/flutter_test.dart';
import 'package:gatex/routing/processes.dart';

void main() {
  test('parseTasklistCsv takes first quoted field, dedups, drops own', () {
    final out = parseTasklistCsv(
      '"Chrome.exe","1234","Console","1","123 456 K"\r\n'
      '\r\n'
      '"chrome.exe","99","Console","1","10 K"\r\n'
      '"GateX.exe","5","Console","1","1 K"\r\n'
      '"gatex-core.exe","6","Console","1","1 K"\r\n'
      '"Code.exe","7","Console","1","1 K"\r\n',
    );
    // Xray compares process names case-sensitively: keep the OS spelling,
    // the first one wins when two differ only in case.
    expect(out, ['Chrome.exe', 'Code.exe']);
  });

  test('parseTasklistCsv keeps Telegram.exe as the OS reports it', () {
    final out = parseTasklistCsv('"Telegram.exe","42","Console","1","9 K"\r\n');
    expect(out, ['Telegram.exe']);
  });

  test('parseProcExe takes basename of the exe link, drops (deleted), own', () {
    final out = parseProcExe([
      '/usr/lib/firefox/firefox',
      '/usr/bin/bash',
      '/usr/lib/firefox/firefox (deleted)',
      '/opt/Telegram/Telegram',
      '',
      '/opt/gatex/gatex',
      '/opt/gatex/lib/GateX-Core',
      '/usr/share/discord/Discord (deleted)',
    ]);
    expect(out, ['bash', 'Discord', 'firefox', 'Telegram']);
  });
}
