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
    expect(out, ['chrome.exe', 'code.exe']);
  });

  test('parseProcComm trims, lower-cases, dedups, drops own', () {
    final out = parseProcComm(
      ['firefox\n', 'Bash\n', 'firefox', '', 'gatex\n', 'gatex-core\n'],
    );
    expect(out, ['bash', 'firefox']);
  });
}
