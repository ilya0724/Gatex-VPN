import 'package:flutter_test/flutter_test.dart';
import 'package:gatex/routing/routing_settings.dart';
import 'package:gatex/state/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('defaults', () {
    const d = RoutingSettings.defaults;
    expect(d.appsMode, AppsMode.all);
    expect(d.apps, isEmpty);
    expect(d.rules, isEmpty);
    expect(d.directRu, true);
    expect(d.blockAds, false);
  });

  RoutingSettings sample() => const RoutingSettings(
    appsMode: AppsMode.except,
    apps: ['chrome.exe', 'com.example.app'],
    rules: [
      RoutingRule(
        kind: RuleKind.domain,
        value: 'a.com',
        action: RuleAction.direct,
      ),
      RoutingRule(
        kind: RuleKind.ip,
        value: '10.0.0.0/8',
        action: RuleAction.block,
        enabled: false,
      ),
      RoutingRule(
        kind: RuleKind.keyword,
        value: 'ads',
        action: RuleAction.proxy,
      ),
    ],
    directRu: false,
    blockAds: true,
  );

  void same(RoutingSettings a, RoutingSettings b) {
    expect(b.appsMode, a.appsMode);
    expect(b.apps, a.apps);
    expect(b.directRu, a.directRu);
    expect(b.blockAds, a.blockAds);
    expect(b.rules.length, a.rules.length);
    for (var i = 0; i < a.rules.length; i++) {
      expect(b.rules[i].kind, a.rules[i].kind);
      expect(b.rules[i].value, a.rules[i].value);
      expect(b.rules[i].action, a.rules[i].action);
      expect(b.rules[i].enabled, a.rules[i].enabled);
    }
  }

  test('json round trip', () {
    final s = sample();
    same(s, RoutingSettings.fromJson(s.toJson()));
  });

  test('export/import round trip', () {
    final s = sample();
    final text = s.export();
    expect(text.startsWith('gatex-routing:1:'), true);
    same(s, RoutingSettings.import(text));
    same(s, RoutingSettings.import('  $text\n'));
    final body = text.substring('gatex-routing:1:'.length);
    final unpadded = body.replaceAll('=', '');
    same(s, RoutingSettings.import('gatex-routing:1:$unpadded'));
    expect(
      () => RoutingSettings.import('hello'),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => RoutingSettings.import('gatex-routing:1:@@@'),
      throwsA(isA<FormatException>()),
    );
  });

  test('validate', () {
    expect(
      const RoutingSettings(appsMode: AppsMode.only).validate(),
      'Выберите хотя бы одно приложение',
    );
    const bad = RoutingRule(
      kind: RuleKind.ip,
      value: '10.0.0.0/33',
      action: RuleAction.block,
    );
    expect(
      const RoutingSettings(rules: [bad]).validate(),
      startsWith('Неверный адрес'),
    );
    const empty = RoutingRule(
      kind: RuleKind.domain,
      value: '',
      action: RuleAction.block,
    );
    expect(const RoutingSettings(rules: [empty]).validate(), 'Пустое правило');
    const v6 = RoutingRule(
      kind: RuleKind.ip,
      value: '2001:db8::/32',
      action: RuleAction.direct,
    );
    const v4 = RoutingRule(
      kind: RuleKind.ip,
      value: '1.2.3.4',
      action: RuleAction.direct,
    );
    expect(const RoutingSettings(rules: [v6, v4]).validate(), isNull);
    expect(sample().validate(), isNull);
  });

  test('migration', () async {
    SharedPreferences.setMockInitialValues({'set.directRu': false});
    final prefs = await SharedPreferences.getInstance();
    final settings = Settings(prefs);
    expect(settings.routing.directRu, false);
    settings.routing = sample();
    expect(prefs.getString('set.routing'), isNotNull);
    same(sample(), settings.routing);
    settings.routing = settings.routing.copyWith(directRu: true);
    expect(settings.routing.directRu, true);
    expect(settings.routing.blockAds, true);
  });
}
