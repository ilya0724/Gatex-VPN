import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gatex/core/android_core.dart';

void main() {
  test('parseInstalledApps sorts by label and keeps icons', () {
    final apps = parseInstalledApps([
      {
        'package': 'org.b',
        'label': 'banana',
        'icon': Uint8List.fromList([1, 2]),
      },
      {'package': 'org.a', 'label': 'Apple'},
    ]);
    expect(apps.map((a) => a.package), ['org.a', 'org.b']);
    expect(apps[0].icon, isNull);
    expect(apps[1].icon, [1, 2]);
  });

  test('parseInstalledApps drops entries without a package', () {
    final apps = parseInstalledApps([
      {'label': 'No package'},
      {'package': '', 'label': 'Empty'},
      'junk',
      null,
      {'package': 'org.x'},
    ]);
    expect(apps.length, 1);
    expect(apps.single.package, 'org.x');
    expect(apps.single.label, 'org.x');
  });
}
