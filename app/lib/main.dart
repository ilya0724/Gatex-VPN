import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  // The theme is needed for the very first frame, but nothing here may
  // keep that frame from being drawn.
  try {
    final prefs = await SharedPreferences.getInstance().timeout(
      const Duration(seconds: 2),
    );
    GX.use(prefs.getString('set.theme') ?? '');
    await IntroOverlay.prepare(prefs);
  } on Object {
    IntroOverlay.skip = true;
  }
  if (DesktopShell.supported) await DesktopShell.instance.init(args);
  final state = AppState();
  runApp(GateXApp(state: state));
  await state.init(args);
}

class GateXApp extends StatefulWidget {
  const GateXApp({super.key, required this.state});
  final AppState state;

  @override
  State<GateXApp> createState() => _GateXAppState();
}

class _GateXAppState extends State<GateXApp> {
  AppState get state => widget.state;
  String _palette = GX.p.id;

  /// The colour the screen had before a theme change, faded out on top.
  Color? _fadeFrom;

  @override
  void initState() {
    super.initState();
    state.addListener(_onState);
  }

  @override
  void dispose() {
    state.removeListener(_onState);
    super.dispose();
  }

  void _onState() {
    if (GX.p.id == _palette) return;
    setState(() {
      _fadeFrom = palettes.firstWhere((p) => p.id == _palette).bg;
      _palette = GX.p.id;
    });
    // Screens read GX directly, so every element rebuilds with the new
    // colours, without resetting navigation.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      void rebuild(Element e) {
        e.markNeedsBuild();
        e.visitChildren(rebuild);
      }

      if (mounted) (context as Element).visitChildren(rebuild);
    });
  }

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
            if (_fadeFrom != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: TweenAnimationBuilder<double>(
                    key: ValueKey(_palette),
                    tween: Tween(begin: 1, end: 0),
                    duration: const Duration(milliseconds: 520),
                    curve: Curves.easeOutCubic,
                    onEnd: () => setState(() => _fadeFrom = null),
                    builder: (_, v, _) =>
                        ColoredBox(color: _fadeFrom!.withValues(alpha: v)),
                  ),
                ),
              ),
            const Positioned.fill(child: IntroOverlay()),
          ],
        ),
      ),
      home: ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          if (!state.ready) return _Starting(state: state);
          if (state.startupError != null) {
            return _StartupError(text: state.startupError!);
          }
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

/// Empty while starting; if start-up hangs, says where.
class _Starting extends StatefulWidget {
  const _Starting({required this.state});
  final AppState state;

  @override
  State<_Starting> createState() => _StartingState();
}

class _StartingState extends State<_Starting> {
  Timer? _timer;
  bool _slow = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 7), () {
      if (mounted) setState(() => _slow = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: AnimatedOpacity(
          opacity: _slow ? 1 : 0,
          duration: const Duration(milliseconds: 400),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: GX.accent),
                const SizedBox(height: 20),
                Text(
                  'Запуск затянулся',
                  style: display(18),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Шаг: ${widget.state.initStep}',
                  style: body(14, color: GX.muted),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Start-up failed: show why, so it can go to support.
class _StartupError extends StatelessWidget {
  const _StartupError({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('GateX не запустился', style: display(20)),
              const SizedBox(height: 8),
              Text(
                'Скопируйте текст ниже и отправьте в поддержку.',
                style: body(14, color: GX.muted),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: SelectableText(text, style: mono(12)),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => Clipboard.setData(ClipboardData(text: text)),
                child: const Text('Скопировать'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
