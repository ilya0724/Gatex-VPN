import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../links.dart';
import '../state/app_state.dart';
import 'intro.dart';
import 'motion.dart';
import 'theme.dart';
import 'widgets.dart';

/// First screen: the user has no subscription yet.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key, required this.state});
  final AppState state;

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final _field = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      setState(
        () => _error = 'В буфере обмена пусто. Скопируйте ссылку в боте',
      );
      return;
    }
    _field.text = text;
    await _add();
  }

  Future<void> _add() async {
    final url = subscriptionUrlFromLink(_field.text) ?? _field.text.trim();
    setState(() => _error = null);
    final error = await widget.state.importSubscription(url);
    if (mounted && error != null) setState(() => _error = error);
  }

  @override
  Widget build(BuildContext context) {
    final busy = widget.state.refreshing;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _staggered([
                  Center(
                    child: ValueListenableBuilder<bool>(
                      valueListenable: IntroOverlay.finished,
                      builder: (context, done, _) => Opacity(
                        opacity: done ? 1 : 0,
                        child: Image.asset(
                          GX.mark,
                          key: IntroOverlay.markKeyIfFlying,
                          height: 64,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'Интернет без стен',
                    textAlign: TextAlign.center,
                    style: display(28),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Откройте бота GateX и нажмите «Открыть в приложении». '
                    'Или скопируйте ссылку подписки и вставьте её сюда.',
                    textAlign: TextAlign.center,
                    style: body(15, color: GX.muted),
                  ),
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed: busy ? null : () => openLink(Links.bot),
                    icon: const Icon(Icons.send_rounded),
                    label: const Text('Получить подписку в боте'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: busy ? null : _paste,
                    icon: const Icon(Icons.content_paste_rounded),
                    label: const Text('Вставить ссылку из буфера'),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _field,
                    enabled: !busy,
                    style: body(14),
                    decoration: const InputDecoration(
                      hintText: 'https://… ссылка подписки',
                    ),
                    onSubmitted: (_) => _add(),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: busy ? null : _add,
                    child: busy
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: GX.accent,
                            ),
                          )
                        : const Text('Добавить'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: body(14, color: GX.danger),
                    ),
                  ],
                  const SizedBox(height: 24),
                  TextButton(
                    onPressed: () => openLink(Links.support),
                    child: Text(
                      'Нужна помощь? @gatexvpn_support',
                      style: body(14, color: GX.muted),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  final Duration _base = IntroOverlay.wait;

  List<Widget> _staggered(List<Widget> children) => [
    for (var i = 0; i < children.length; i++)
      children[i] is SizedBox
          ? children[i]
          : FadeSlideIn.staggered(
              index: i ~/ 2,
              base: _base,
              child: children[i],
            ),
  ];
}
