import 'package:flutter/material.dart';

import 'desktop/desktop_shell.dart';
import 'state/app_state.dart';
import 'ui/background.dart';
import 'ui/home_screen.dart';
import 'ui/import_screen.dart';
import 'ui/intro.dart';
import 'ui/theme.dart';
import 'ui/title_bar.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (DesktopShell.supported) await DesktopShell.instance.init(args);
  final state = AppState();
  runApp(GateXApp(state: state));
  await state.init(args);
}

class GateXApp extends StatelessWidget {
  const GateXApp({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GateX VPN',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      // One background, title bar and intro for every screen.
      builder: (context, child) => Material(
        color: GX.bg,
        child: Stack(
          children: [
            Positioned.fill(
              child: ListenableBuilder(
                listenable: state,
                builder: (_, _) => Aurora(active: state.connected),
              ),
            ),
            Column(
              children: [
                if (DesktopShell.supported) const TitleBar(),
                Expanded(child: child!),
              ],
            ),
            const Positioned.fill(child: IntroOverlay()),
          ],
        ),
      ),
      home: ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          if (!state.ready) return const Scaffold();
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 450),
            child: state.hasSubscription
                ? HomeScreen(key: const ValueKey('home'), state: state)
                : ImportScreen(key: const ValueKey('import'), state: state),
          );
        },
      ),
    );
  }
}
