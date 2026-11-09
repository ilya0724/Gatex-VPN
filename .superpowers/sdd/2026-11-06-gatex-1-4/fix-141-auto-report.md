# Fix 1.4.1 Auto report

Implemented (brief + owner amendment):
- auto_pick.dart: tiers (autoMain/autoLte), pickAuto tier-by-tier with sticky per tier, autoDelaysKnown, raceFirst (first responder wins, rest report via onResult), autoQuickPick (remembered -> main race -> LTE race -> first main), measureAutoTiers (background measuring; LTE only if no main answered).
- app_state.dart: `_pickAutoInner` has no testDelays wait. Order: remembered `auto.last` (no probe, background `_measureAuto`) -> fresh (<5 min) delays via pickAuto -> race. Remembered saved (`auto.last`, `auto.last.at`) after successful core.start in Auto. Failed core.start of remembered server -> forget + connect(skipLast: true) (race). Health: LTE current -> probe main tier each tick; any answer -> forget remembered + _reconnectShowing. 2-failure path forgets remembered before reconnect. Gen cancel, SingleFlight, Linux gate untouched.
- servers_screen.dart subtitle: «Сначала основные серверы, LTE — если они недоступны». Home subtitle («Самый быстрый из N серверов») left as is (not the quoted string).
- tariff_legend_test.dart: its "no legend" check used textContaining(' — '), which matched the new subtitle; narrowed to the legend phrases.

Rules: remembered LTE is only ever stored when LTE was the connect target (fallback), and it is a candidate only while still in autoCandidates. No switching for a faster main server (sticky); health switches on 2 failures or LTE->main.

Tests: new tests in app/test/auto_pick_test.dart (tiers, sticky, measureAutoTiers no LTE probe, remembered no probe, first-responder race, LTE race only when all main fail). RED not captured separately (helpers written together with tests); GREEN: `GATEX_CORE=/d/dev/gatex-core.exe flutter test` -> 120 passed; `flutter analyze` no issues.

Not testable/compiled: AppState wiring (connect retry, prefs, health LTE->main) has no unit test (needs fake core); verified by analyze and review only. No Android/desktop build.

## Fix round 1
1. Remembered server verified: `usableRemembered` (pure, tested) skips it when fresh delays mark it null, or when it is LTE and a main has a fresh delay. After a remembered connect `_verifyRemembered` probes it (3 s + 1 retry); on failure forget + `_reconnectShowing()` (gated by `_autoReconnectAllowed()`), pick then races. On Linux the remembered server is probed BEFORE connecting (blind connect removed; no post-connect verify).
2. Retry-on-start-failure removed (and the `skipLast` param).
3. `_probeSeq` used for all probe log names (`_probeAuto`); `_probe` log delete wrapped in try.
4. `_pickAuto`/`_pickAutoInner` return `({server, fromLast})`; shared flag removed.
5. DesktopCore: `launchTimeout` (20 s) + injectable `startProcess`; on timeout kills process, emits disconnected, returns «Ядро не запустилось за 20 секунд». Test: test/desktop_core_test.dart (fake process). Note: with pkexec, kill ends pkexec, not necessarily the elevated child.
Tests: `GATEX_CORE=/d/dev/gatex-core.exe flutter test` 124 passed; analyze clean. RED not captured (tests written with implementation). AppState verify/Linux pre-probe wiring has no unit test (needs fake core).
