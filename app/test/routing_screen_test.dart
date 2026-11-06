import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gatex/routing/routing_settings.dart';
import 'package:gatex/ui/routing_screen.dart';

void main() {
  late List<RoutingSettings> saved;

  Future<void> pump(
    WidgetTester t, {
    RoutingSettings? start,
    double width = 900,
    bool android = false,
  }) async {
    saved = [];
    t.view.physicalSize = Size(width, 3000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        home: RoutingScreen(
          routing: start ?? RoutingSettings.defaults,
          android: android,
          loadProcesses: () async => ['chrome.exe'],
          onSave: (r) async {
            final e = r.validate();
            if (e != null) return e;
            saved.add(r);
            return null;
          },
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('toggling the Russian preset saves directRu false', (t) async {
    await pump(t);
    await t.tap(find.text('Российские сайты напрямую'));
    await t.pumpAndSettle();
    expect(saved, hasLength(1));
    expect(saved.single.directRu, isFalse);
  });

  testWidgets('only-selected with no apps shows the error and saves nothing', (
    t,
  ) async {
    await pump(t);
    await t.tap(find.text('Только выбранные'));
    await t.pumpAndSettle();
    expect(find.text('Выберите хотя бы одно приложение'), findsOneWidget);
    expect(saved, isEmpty);
  });

  testWidgets('a new rule shows up in the list with its tag', (t) async {
    await pump(t);
    await t.tap(find.text('Добавить правило'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'openai.com');
    await t.pump();
    await t.tap(find.text('Добавить'));
    await t.pumpAndSettle();
    expect(find.text('openai.com'), findsOneWidget);
    expect(find.text('VPN'), findsOneWidget);
    expect(saved.single.rules.single.value, 'openai.com');
    expect(saved.single.rules.single.action, RuleAction.proxy);
  });

  testWidgets('two quick edits during a slow save both survive', (t) async {
    t.view.physicalSize = const Size(900, 3000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final saves = <RoutingSettings>[];
    final gate = Completer<String?>();
    await t.pumpWidget(
      MaterialApp(
        home: RoutingScreen(
          routing: RoutingSettings.defaults,
          android: false,
          onSave: (r) {
            saves.add(r);
            return gate.future;
          },
        ),
      ),
    );
    await t.tap(find.text('Российские сайты напрямую'));
    await t.pump();
    await t.tap(find.text('Блокировать рекламу'));
    await t.pump();
    expect(saves, hasLength(2));
    expect(saves.last.directRu, isFalse);
    expect(saves.last.blockAds, isTrue);
    gate.complete(null);
    await t.pumpAndSettle();
  });

  testWidgets('import and export live behind one row', (t) async {
    await pump(t);
    expect(find.text('Импорт и экспорт правил'), findsOneWidget);
    // A single row needs no section title of its own.
    expect(find.text('ОБМЕН'), findsNothing);
  });

  double left(WidgetTester t, String text) =>
      t.getTopLeft(find.text(text.toUpperCase())).dx;

  testWidgets('wide desktop: presets and own rules in two columns', (t) async {
    await pump(t, width: 1000);
    expect(left(t, 'Свои правила'), greaterThan(left(t, 'Готовые наборы')));
  });

  for (final (width, android) in [(700.0, false), (1000.0, true)]) {
    testWidgets('one column at $width (android: $android)', (t) async {
      await pump(t, width: width, android: android);
      expect(left(t, 'Свои правила'), left(t, 'Готовые наборы'));
    });
  }
}
