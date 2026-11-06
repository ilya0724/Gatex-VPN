import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gatex/core/vpn_core.dart';
import 'package:gatex/desktop/desktop_shell.dart';
import 'package:gatex/routing/routing_settings.dart';
import 'package:gatex/state/app_state.dart';
import 'package:gatex/state/settings.dart';
import 'package:gatex/subscription/subscription.dart';
import 'package:gatex/ui/home_screen.dart';
import 'package:gatex/ui/settings_screen.dart';
import 'package:gatex/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Only what the home screen touches is real; any other call fails loudly.
class _FakeCore extends Fake implements VpnCore {
  @override
  Future<String> coreVersion() async => '25.0';
}

final _announce = [
  'Тариф: Стандарт (LTE)',
  for (var i = 1; i <= 10; i++) 'Строка объявления номер $i',
].join('\n');

Future<AppState> _state({RoutingSettings? routing}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final state = AppState(core: _FakeCore());
  state.settings = Settings(prefs);
  if (routing != null) state.settings.routing = routing;
  state.subscription = Subscription(
    url: 'https://example.test/sub',
    servers: const [],
    fetchedAt: DateTime.now(),
    title: 'GateX VPN',
    expire: DateTime.now().add(const Duration(days: 352)),
    download: 500 * 1024 * 1024 * 1024,
    announce: _announce,
  );
  return state;
}

Future<void> _pump(WidgetTester t, AppState state, Size size) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: buildTheme(),
      home: HomeScreen(state: state),
    ),
  );
  await t.pump(const Duration(seconds: 6));
}

void _expectNoScroll(WidgetTester t) {
  expect(t.takeException(), isNull);
  final scrollables = t.stateList<ScrollableState>(find.byType(Scrollable));
  expect(scrollables, isNotEmpty);
  for (final s in scrollables) {
    expect(s.position.maxScrollExtent, 0);
  }
}

void main() {
  for (final size in const [Size(360, 640), Size(720, 520)]) {
    testWidgets('home fits ${size.width.toInt()}x${size.height.toInt()}', (
      t,
    ) async {
      await _pump(t, await _state(), size);
      _expectNoScroll(t);
      expect(find.text('Строка объявления номер 1'), findsNothing);
    });

    testWidgets('routing chip does not break ${size.width.toInt()}', (t) async {
      final state = await _state(
        routing: const RoutingSettings(
          appsMode: AppsMode.only,
          apps: ['a', 'b', 'c'],
        ),
      );
      await _pump(t, state, size);
      _expectNoScroll(t);
      expect(find.text('Только выбранные приложения · 3'), findsOneWidget);
    });
  }

  for (final size in const [Size(360, 640), Size(720, 520)]) {
    testWidgets('connected with a chip fits ${size.width.toInt()}', (t) async {
      final state = await _state(
        routing: const RoutingSettings(
          appsMode: AppsMode.except,
          apps: ['a', 'b'],
        ),
      );
      state.vpnState = VpnState.connected;
      await _pump(t, state, size);
      _expectNoScroll(t);
      expect(find.text('Подключено'), findsOneWidget);
      // Stop the session timer.
      await t.pumpWidget(const SizedBox());
    });
  }

  testWidgets('no chip when every app goes through the VPN', (t) async {
    await _pump(t, await _state(), const Size(360, 640));
    expect(find.byIcon(Icons.alt_route_rounded), findsNothing);
  });

  testWidgets('except mode chip', (t) async {
    final state = await _state(
      routing: const RoutingSettings(
        appsMode: AppsMode.except,
        apps: ['a', 'b'],
      ),
    );
    await _pump(t, state, const Size(360, 640));
    expect(find.text('Все, кроме выбранных · 2'), findsOneWidget);
  });

  testWidgets('info button opens the announce in a sheet', (t) async {
    await _pump(t, await _state(), const Size(360, 640));
    await t.tap(find.byIcon(Icons.info_outline_rounded));
    await t.pump(const Duration(seconds: 1));
    expect(find.text('Информация о подписке'), findsOneWidget);
    expect(find.textContaining('Строка объявления номер 10'), findsOneWidget);
  });

  testWidgets('plan card keeps the unlimited traffic line', (t) async {
    await _pump(t, await _state(), const Size(360, 640));
    expect(find.textContaining('без лимита'), findsOneWidget);
  });

  group('settings', () {
    Future<void> pumpSettings(WidgetTester t, Size size) async {
      final state = await _state();
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: SettingsScreen(state: state),
        ),
      );
      await t.pump(const Duration(seconds: 2));
    }

    testWidgets('wide: left nav switches the right pane', (t) async {
      await pumpSettings(t, const Size(920, 580));
      expect(t.takeException(), isNull);
      for (final label in ['Назад', 'Настройки', 'Маршрутизация', 'Журнал']) {
        expect(find.text(label), findsWidgets);
      }
      // Two columns of the settings pane, no routing row inside it.
      expect(find.text('Оформление'.toUpperCase()), findsOneWidget);
      expect(find.text('Помощь'.toUpperCase()), findsOneWidget);
      expect(
        find.text('Приложения, сайты, российские сайты напрямую'),
        findsNothing,
      );
      await t.tap(find.text('Маршрутизация'));
      await t.pump(const Duration(seconds: 1));
      expect(find.text('Готовые наборы'.toUpperCase()), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('narrow stays a single list with the routing row', (t) async {
      await pumpSettings(t, const Size(400, 800));
      expect(t.takeException(), isNull);
      expect(
        find.text('Приложения, сайты, российские сайты напрямую'),
        findsOneWidget,
      );
      expect(find.text('Назад'), findsNothing);
    });
  });

  group('window size', () {
    test('first launch uses the landscape default', () {
      expect(
        DesktopShell.windowSizeFor(null, null, migrated: false),
        const Size(920, 580),
      );
    });
    test('a portrait size from 1.3.0 is replaced once', () {
      expect(
        DesktopShell.windowSizeFor(460, 820, migrated: false),
        const Size(920, 580),
      );
    });
    test('a portrait size chosen after the migration is kept', () {
      expect(
        DesktopShell.windowSizeFor(760, 900, migrated: true),
        const Size(760, 900),
      );
    });
    test('a landscape size is kept and clamped to the minimum', () {
      expect(
        DesktopShell.windowSizeFor(1000, 700, migrated: false),
        const Size(1000, 700),
      );
      expect(
        DesktopShell.windowSizeFor(600, 400, migrated: true),
        const Size(720, 520),
      );
    });
  });
}
