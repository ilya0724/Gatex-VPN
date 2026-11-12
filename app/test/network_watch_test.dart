import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gatex/state/network_watch.dart';

void main() {
  test('change gives one event after the debounce', () {
    fakeAsync((async) {
      var snap = {'wlan0|10.0.0.2'};
      final w = NetworkWatch(snapshot: () async => snap);
      var events = 0;
      w.changes.listen((_) => events++);
      w.start();
      async.elapse(const Duration(seconds: 4));
      expect(events, 0);
      snap = {'wlan0|192.168.1.5'};
      async.elapse(const Duration(seconds: 3));
      expect(events, 0); // still inside the debounce
      async.elapse(const Duration(seconds: 3));
      expect(events, 1);
      w.stop();
    });
  });

  test('two changes within 1 s give one event', () {
    fakeAsync((async) {
      var snap = {'a|1'};
      final w = NetworkWatch(
        interval: const Duration(milliseconds: 500),
        snapshot: () async => snap,
      );
      var events = 0;
      w.changes.listen((_) => events++);
      w.start();
      async.elapse(const Duration(seconds: 1));
      snap = {'a|2'};
      async.elapse(const Duration(milliseconds: 500));
      snap = {'a|3'};
      async.elapse(const Duration(seconds: 5));
      expect(events, 1);
      w.stop();
    });
  });

  test('no change gives no event', () {
    fakeAsync((async) {
      final w = NetworkWatch(snapshot: () async => {'a|1'});
      var events = 0;
      w.changes.listen((_) => events++);
      w.start();
      async.elapse(const Duration(seconds: 30));
      expect(events, 0);
      w.stop();
    });
  });

  group('networkSnapshot', () {
    InternetAddress ip(String a) => InternetAddress(a);

    test('Teredo and other Windows tunnels are ignored', () {
      final a = networkSnapshot([
        ('Ethernet', [ip('192.168.0.101')]),
        ('Teredo Tunneling Pseudo-Interface', [ip('2001:0:2851:782c::1')]),
      ]);
      final b = networkSnapshot([
        ('Ethernet', [ip('192.168.0.101')]),
        ('Teredo Tunneling Pseudo-Interface', <InternetAddress>[]),
        ('isatap.{1234}', [ip('10.9.9.9')]),
        ('6to4 Adapter', [ip('2002:c0a8:6501::1')]),
      ]);
      expect(a, b);
    });

    test('rotating IPv6 privacy addresses are not a change', () {
      final a = networkSnapshot([
        ('Wi-Fi', [ip('192.168.1.5'), ip('2a02:6b8::1111')]),
      ]);
      final b = networkSnapshot([
        ('Wi-Fi', [ip('192.168.1.5'), ip('2a02:6b8::2222')]),
      ]);
      expect(a, b);
      expect(a, {'Wi-Fi|192.168.1.5', 'Wi-Fi|v6'});
    });

    test('own TUN is ignored by name and by subnet', () {
      final s = networkSnapshot([
        ('GateX', [ip('172.19.0.1')]),
        ('GateX 2', [ip('172.19.0.1')]),
        ('Ethernet 3', [ip('172.19.0.2')]),
        ('Ethernet', [ip('10.0.0.7')]),
      ]);
      expect(s, {'Ethernet|10.0.0.7'});
    });

    test('a new IPv4 network is a change', () {
      final a = networkSnapshot([
        ('Wi-Fi', [ip('192.168.1.5')]),
      ]);
      final b = networkSnapshot([
        ('Wi-Fi', [ip('10.20.30.4')]),
      ]);
      expect(a == b, isFalse);
    });

    test('an IPv6-only interface counts once, not per address', () {
      expect(
        networkSnapshot([
          ('lte', [ip('2a00::1'), ip('2a00::2')]),
        ]),
        {'lte|v6'},
      );
    });
  });
}
