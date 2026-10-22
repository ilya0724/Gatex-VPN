import 'package:flutter/material.dart';

import 'state/app_state.dart';
import 'ui/home_screen.dart';
import 'ui/import_screen.dart';
import 'ui/theme.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
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
      home: ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          if (!state.ready) {
            return const Scaffold(body: Backdrop(child: SizedBox.expand()));
          }
          return state.hasSubscription
              ? HomeScreen(state: state)
              : ImportScreen(state: state);
        },
      ),
    );
  }
}
