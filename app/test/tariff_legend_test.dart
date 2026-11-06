import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gatex/core/vpn_core.dart';
import 'package:gatex/state/app_state.dart';
import 'package:gatex/state/settings.dart';
import 'package:gatex/subscription/subscription.dart';
import 'package:gatex/ui/home_screen.dart';
import 'package:gatex/ui/servers_screen.dart';
import 'package:gatex/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeCore extends Fake implements VpnCore {
  @override
  Future<String> coreVersion() async => '25.0';
}

const _announce =
    'Тариф: Стандарт (LTE)\n➡️shaneeeer⬅️\n1054316062\n'
    'Ваша подписка ✅ Активна\n\n'
    '🏳️ - Обход Белых Списков\n'
    '💫 — работает Gemini\n'
    '✨ - YouTube без рекламы\n'
    'Дней осталось: 352\nПоддержка @gatexvpn_bot\n'
    'Всего трафика: 475.71 GiB';

Future<AppState> _state(String? announce) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final state = AppState(core: _FakeCore());
  state.settings = Settings(prefs);
  state.delays['x'] = 10; // skip the automatic delay test
  state.subscription = Subscription(
    url: 'https://example.test/sub',
    servers: const [],
    fetchedAt: DateTime.now(),
    title: 'GateX VPN',
    expire: DateTime.now().add(const Duration(days: 352)),
    announce: announce,
  );
  return state;
}

void main() {
  group('parseTariff', () {
    test('first Тариф line', () {
      expect(parseTariff('Тариф: Стандарт (LTE)\n➡️x⬅️'), 'Стандарт (LTE)');
    });
    test('none', () {
      expect(parseTariff('Ваша подписка'), isNull);
      expect(parseTariff(null), isNull);
    });
    test('empty Тариф line does not take the next line', () {
      expect(parseTariff('Тариф:\nВаша подписка ✅ Активна'), isNull);
      expect(parseTariff('Тариф: \t\nДругая строка'), isNull);
    });
    test('CRLF announce', () {
      expect(parseTariff('Тариф: Стандарт\r\nx'), 'Стандарт');
    });
  });

  group('parseEmojiLegend', () {
    test('real announce', () {
      expect(parseEmojiLegend(_announce), [
        ('🏳', 'Обход Белых Списков'),
        ('💫', 'работает Gemini'),
        ('✨', 'YouTube без рекламы'),
      ]);
    });
    test('drops duplicates, empty on none', () {
      expect(parseEmojiLegend('💫 - a\n💫 - b'), [('💫', 'a')]);
      expect(parseEmojiLegend(null), isEmpty);
      expect(parseEmojiLegend('hello'), isEmpty);
      expect(parseEmojiLegend('💫\n- not a legend'), isEmpty);
    });
    test('Subscription exposes both', () async {
      final s = (await _state(_announce)).subscription!;
      expect(s.tariff, 'Стандарт (LTE)');
      expect(s.emojiLegend.length, 3);
    });
  });

  testWidgets('plan card shows the tariff', (t) async {
    final state = await _state(_announce);
    t.view.physicalSize = const Size(360, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: HomeScreen(state: state),
      ),
    );
    await t.pump(const Duration(seconds: 6));
    expect(find.text('Стандарт (LTE)'), findsOneWidget);
    expect(find.byIcon(Icons.workspace_premium_rounded), findsOneWidget);
  });

  testWidgets('servers screen shows the legend', (t) async {
    final state = await _state(_announce);
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: ServersScreen(state: state),
      ),
    );
    await t.pump(const Duration(seconds: 2));
    expect(find.text('💫 — работает Gemini'), findsOneWidget);
    expect(find.text('🏳 — Обход Белых Списков'), findsOneWidget);
  });

  testWidgets('no legend without entries', (t) async {
    final state = await _state('Тариф: Базовый');
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: ServersScreen(state: state),
      ),
    );
    await t.pump(const Duration(seconds: 2));
    expect(find.textContaining(' — '), findsNothing);
  });
}
