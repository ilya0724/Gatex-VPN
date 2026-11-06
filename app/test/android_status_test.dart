import 'package:flutter_test/flutter_test.dart';
import 'package:gatex/core/android_core.dart';
import 'package:gatex/core/vpn_core.dart';

void main() {
  test('native restart is a reconnecting status', () {
    final s = AndroidCore.decodeStatus({
      'state': 'connecting',
      'error': null,
      'reconnecting': true,
    });
    expect(s.state, VpnState.connecting);
    expect(s.reconnecting, isTrue);
  });

  test('plain connecting, connected and disconnected are not reconnecting', () {
    for (final st in ['connecting', 'connected', 'disconnected']) {
      expect(AndroidCore.decodeStatus({'state': st}).reconnecting, isFalse);
    }
    expect(
      AndroidCore.decodeStatus({'state': 'connected', 'reconnecting': true})
          .reconnecting,
      isFalse,
    );
  });
}
