import 'package:flutter_test/flutter_test.dart';

import 'dart:async';

import 'package:gatex/state/app_state.dart' show autoServerId;
import 'package:gatex/state/auto_pick.dart';
import 'package:gatex/subscription/server.dart';

Server _s(String name, {String address = '1.2.3.4', int port = 443}) => Server(
  name: name,
  address: address,
  port: port,
  protocol: 'vless',
  transport: 'raw',
  outbound: const {},
);

void main() {
  final de = _s('🇩🇪 Германия', address: '1.1.1.1');
  final nl = _s('🇳🇱 Нидерланды', address: '2.2.2.2');
  final fi = _s('🇫🇮 Финляндия', address: '3.3.3.3');
  final ru = _s('🇷🇺 Россия', address: '4.4.4.4');
  final panelAuto = _s('🏳 Авто', address: '5.5.5.5');
  final placeholder = _s('Подписка истекла', address: '0.0.0.0', port: 1);

  test('candidates drop Russian, panel Авто and placeholders', () {
    final c = autoCandidates([de, ru, panelAuto, placeholder, nl]);
    expect(c, [de, nl]);
  });

  test('server getters', () {
    expect(ru.isRussian, isTrue);
    expect(de.isRussian, isFalse);
    expect(panelAuto.isPanelAuto, isTrue);
    expect(de.isPanelAuto, isFalse);
  });

  test('picks the lowest known delay', () {
    final p = pickAuto([de, nl, fi], {de.id: 120, nl.id: 40, fi.id: null});
    expect(p, nl);
  });

  test('sticky keeps current within 1.5x + 30 ms', () {
    final d = {de.id: 100, nl.id: 40, fi.id: 90};
    // limit = 40 * 1.5 + 30 = 90
    expect(pickAuto([de, nl, fi], d, currentId: fi.id), fi);
    expect(pickAuto([de, nl, fi], d, currentId: de.id), nl);
  });

  test('sticky switches when current has no known delay', () {
    final d = {de.id: null, nl.id: 40};
    expect(pickAuto([de, nl], d, currentId: de.id), nl);
    expect(pickAuto([de, nl], {nl.id: 40}, currentId: de.id), nl);
  });

  test('sticky ignores a current id that is not a candidate', () {
    expect(pickAuto([de, nl], {de.id: 50, nl.id: 40}, currentId: ru.id), nl);
  });

  test('all unknown picks the first candidate', () {
    expect(pickAuto([de, nl], {de.id: null}), de);
    expect(pickAuto([de, nl], const {}), de);
  });

  test('empty gives null', () {
    expect(pickAuto(const [], const {}), isNull);
  });

  group('settleAutoConnect', () {
    test('cancelled aborts', () {
      expect(
        settleAutoConnect(
          cancelled: true,
          selectedId: autoServerId,
          selected: null,
          picked: de,
        ),
        isNull,
      );
    });
    test('still Авто uses the pick', () {
      expect(
        settleAutoConnect(
          cancelled: false,
          selectedId: autoServerId,
          selected: null,
          picked: de,
        ),
        de,
      );
    });
    test('server chosen meanwhile wins over the pick', () {
      expect(
        settleAutoConnect(
          cancelled: false,
          selectedId: nl.id,
          selected: nl,
          picked: de,
        ),
        nl,
      );
    });
  });

  test('SingleFlight joins a running job', () async {
    final f = SingleFlight();
    final gate = Completer<void>();
    var runs = 0;
    final a = f.run(() async {
      runs++;
      await gate.future;
    });
    final b = f.run(() async => runs++);
    expect(f.running, isTrue);
    expect(identical(a, b), isTrue);
    gate.complete();
    await a;
    expect(runs, 1);
    expect(f.running, isFalse);
    await f.run(() async => runs++);
    expect(runs, 2);
  });
}
