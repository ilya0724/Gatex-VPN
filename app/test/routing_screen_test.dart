import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gatex/routing/routing_settings.dart';
import 'package:gatex/ui/routing_screen.dart';

void main() {
  late List<RoutingSettings> saved;

  Future<void> pump(WidgetTester t, {RoutingSettings? start}) async {
    saved = [];
    t.view.physicalSize = const Size(900, 3000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        home: RoutingScreen(
          routing: start ?? RoutingSettings.defaults,
          android: false,
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
}
