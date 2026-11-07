import 'package:flutter_test/flutter_test.dart';

import 'dart:async';

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

  test('a Russian server named without the flag is no candidate', () {
    final ruByName = _s('Россия | X', address: '6.6.6.6');
    expect(ruByName.isRussian, isTrue);
    expect(autoCandidates([ruByName, de]), [de]);
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

  group('tiers', () {
    final main = _s('🇩🇪 Германия', address: '7.7.7.1');
    final main2 = _s('🇳🇱 Нидерланды', address: '7.7.7.2');
    final lte = _s('🏳 LTE Антиглушилка 1', address: '7.7.7.3');
    final lte2 = _s('🏳 LTE Антиглушилка 2', address: '7.7.7.4');

    test('main wins over faster LTE', () {
      final d = {main.id: 120, lte.id: 30};
      expect(pickAuto([lte, main], d), main);
      expect(pickAuto([lte, main], d, currentId: lte.id), main);
    });
    test('LTE only when no main delay is known', () {
      expect(pickAuto([main, lte, lte2], {lte.id: 40, lte2.id: 20}), lte2);
      expect(
        pickAuto(
          [main, lte, lte2],
          {lte.id: 40, lte2.id: 50},
          currentId: lte2.id,
        ),
        lte2,
      );
    });
    test('nothing known: first main, else first LTE', () {
      expect(pickAuto([lte, main, main2], const {}), main);
      expect(pickAuto([lte, lte2], const {}), lte);
    });
    test('sticky inside main still works', () {
      final d = {main.id: 100, main2.id: 40, lte.id: 5};
      expect(pickAuto([main, main2, lte], d, currentId: main2.id), main2);
      expect(pickAuto([main, main2, lte], d, currentId: main.id), main2);
    });

    test('measureAutoTiers does not probe LTE when a main answers', () async {
      final probed = <String>[];
      final logs = <String>[];
      final delays = <String, int?>{};
      await measureAutoTiers([main, main2, lte], delays, (s, n) async {
        probed.add(s.id);
        return s.id == main.id ? 50 : null;
      }, logs.add);
      expect(probed, unorderedEquals([main.id, main2.id]));
      expect(delays[main.id], 50);
      expect(logs, ['Авто: проверка основных серверов (2)']);
    });
    test('measureAutoTiers probes LTE when no main answers', () async {
      final probed = <String>[];
      final logs = <String>[];
      final delays = <String, int?>{};
      await measureAutoTiers([main, lte, lte2], delays, (s, n) async {
        probed.add(s.id);
        return s.id == lte2.id ? 70 : null;
      }, logs.add);
      expect(probed, unorderedEquals([main.id, lte.id, lte2.id]));
      expect(logs.last, 'Авто: основные не ответили, проверяем LTE (2)');
      expect(pickAuto([main, lte, lte2], delays), lte2);
    });

    test('remembered server is used without probing', () async {
      var probes = 0;
      final q = await autoQuickPick(
        [main, main2, lte],
        lastId: main2.id,
        probe: (s) async {
          probes++;
          return 10;
        },
      );
      expect(q.server, main2);
      expect(q.fromLast, isTrue);
      expect(probes, 0);
    });
    test('remembered server that is no candidate is ignored', () async {
      final q = await autoQuickPick(
        [main],
        lastId: 'gone',
        probe: (s) async => 10,
      );
      expect(q.server, main);
      expect(q.fromLast, isFalse);
    });
    test(
      'race picks the first responder, not the fastest list order',
      () async {
        final seen = <String>[];
        final q = await autoQuickPick(
          [main, main2],
          probe: (s) async {
            await Future<void>.delayed(
              Duration(milliseconds: s.id == main.id ? 80 : 10),
            );
            return 1;
          },
          onResult: (s, ms) => seen.add(s.id),
        );
        expect(q.server, main2);
        // The slower probe is still running and reports later.
        expect(seen, [main2.id]);
        await Future<void>.delayed(const Duration(milliseconds: 120));
        expect(seen, [main2.id, main.id]);
      },
    );
    test('race skips main servers that fail', () async {
      final q = await autoQuickPick(
        [main, main2],
        probe: (s) async {
          if (s.id == main.id) return null;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return 5;
        },
      );
      expect(q.server, main2);
    });
    test('LTE race only when every main fails', () async {
      final probed = <String>[];
      final q = await autoQuickPick(
        [main, main2, lte, lte2],
        probe: (s) async {
          probed.add(s.id);
          return s.id == lte2.id ? 30 : null;
        },
      );
      expect(q.server, lte2);
      expect(probed.take(2), unorderedEquals([main.id, main2.id]));

      probed.clear();
      final q2 = await autoQuickPick(
        [main, lte],
        probe: (s) async {
          probed.add(s.id);
          return 30;
        },
      );
      expect(q2.server, main);
      expect(probed, [main.id]);
    });
    test('nothing answers: first main', () async {
      final q = await autoQuickPick([
        lte,
        main,
        main2,
      ], probe: (s) async => null);
      expect(q.server, main);
    });
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

  test('SingleFlight coalesces calls into one trailing run', () async {
    final f = SingleFlight();
    final gate = Completer<void>();
    var runs = 0;
    Future<void> job() async {
      runs++;
      if (runs == 1) await gate.future;
    }

    final a = f.run(job);
    final b = f.run(job);
    final c = f.run(job);
    expect(f.running, isTrue);
    var done = 0;
    for (final x in [a, b, c]) {
      x.then((_) => done++);
    }
    await Future<void>.delayed(Duration.zero);
    expect(done, 0);
    gate.complete();
    await Future.wait([a, b, c]);
    expect(runs, 2);
    expect(f.running, isFalse);
    await f.run(job);
    expect(runs, 3);
  });

  test('SingleFlight keeps the trailing run after a run threw', () async {
    final f = SingleFlight();
    final gate = Completer<void>();
    var runs = 0;
    Future<void> job() async {
      runs++;
      if (runs == 1) {
        await gate.future;
        throw StateError('first');
      }
    }

    final a = f.run(job);
    final b = f.run(job);
    final errors = <Object>[];
    for (final x in [a, b]) {
      x.catchError((Object e) => errors.add(e));
    }
    gate.complete();
    await Future.wait([a, b]).catchError((_) => <void>[]);
    expect(runs, 2);
    expect(errors, hasLength(2));
    expect(errors.every((e) => e is StateError), isTrue);
    expect(f.running, isFalse);
    await f.run(job);
    expect(runs, 3);
  });
}
