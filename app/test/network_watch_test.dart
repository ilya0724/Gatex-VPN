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
}
