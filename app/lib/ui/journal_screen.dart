import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/app_state.dart';
import 'theme.dart';

/// What the app and the core logged, to copy and send to support.
class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key, required this.state});
  final AppState state;

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  String _core = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final text = await widget.state.readCoreLog();
    if (mounted) setState(() => _core = text);
  }

  String get _app => widget.state.journal.join('\n');

  Future<void> _copy() async {
    final s = widget.state;
    await Clipboard.setData(
      ClipboardData(
        text:
            'GateX ${s.appVersion} · ${Platform.operatingSystem} '
            '${Platform.operatingSystemVersion}\n\n'
            '== Приложение ==\n$_app\n\n== Ядро ==\n$_core',
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Журнал скопирован. Отправьте его в поддержку'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Журнал'),
          actions: [
            IconButton(
              tooltip: 'Обновить',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () {
                setState(() {});
                _load();
              },
            ),
            IconButton(
              tooltip: 'Скопировать всё',
              icon: const Icon(Icons.copy_rounded),
              onPressed: _copy,
            ),
          ],
          bottom: TabBar(
            indicatorColor: GX.accent,
            labelColor: GX.text,
            unselectedLabelColor: GX.muted,
            labelStyle: body(14, weight: 700),
            dividerColor: GX.line,
            tabs: const [
              Tab(text: 'Приложение'),
              Tab(text: 'Ядро Xray'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _LogView(text: _app, empty: 'Пока пусто'),
            _LogView(
              text: _core,
              empty: 'Ядро ещё ничего не записало. Подключитесь, и здесь появятся его сообщения',
            ),
          ],
        ),
      ),
    );
  }
}

class _LogView extends StatelessWidget {
  const _LogView({required this.text, required this.empty});
  final String text;
  final String empty;

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            empty,
            textAlign: TextAlign.center,
            style: body(14, color: GX.muted),
          ),
        ),
      );
    }
    return SingleChildScrollView(
      reverse: true,
      padding: const EdgeInsets.all(16),
      child: SelectableText(text, style: mono(12, color: GX.text)),
    );
  }
}
