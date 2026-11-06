import 'package:flutter/material.dart';

import '../core/android_core.dart';
import 'theme.dart';

/// Picks the apps (Android) or programs (desktop) the routing mode applies to.
class AppPickerScreen extends StatefulWidget {
  const AppPickerScreen({
    super.key,
    required this.apps,
    required this.android,
    required this.onChanged,
    this.loadApps,
    this.loadProcesses,
  });

  /// Chosen package names (Android) or process names (desktop).
  final List<String> apps;
  final bool android;

  /// Saves the new choice; returns a message when it was refused.
  final Future<String?> Function(List<String> apps) onChanged;
  final Future<List<InstalledApp>> Function()? loadApps;
  final Future<List<String>> Function()? loadProcesses;

  @override
  State<AppPickerScreen> createState() => _AppPickerScreenState();
}

class _AppPickerScreenState extends State<AppPickerScreen> {
  late List<String> _chosen = [...widget.apps];
  List<InstalledApp>? _installed;
  List<String>? _running;
  final _search = TextEditingController();
  final _name = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.android) {
      _load<InstalledApp>(widget.loadApps, (v) => _installed = v);
    } else {
      _load<String>(widget.loadProcesses, (v) => _running = v);
    }
  }

  /// Runs [loader]; a missing or failing loader gives an empty list.
  Future<void> _load<T>(
    Future<List<T>> Function()? loader,
    void Function(List<T>) assign,
  ) async {
    var list = <T>[];
    try {
      list = await (loader?.call() ?? Future.value(<T>[]));
    } catch (_) {}
    if (mounted) setState(() => assign(list));
  }

  @override
  void dispose() {
    _search.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _set(List<String> next) async {
    // Shown at once; the parent validates and saves without a long wait.
    final prev = _chosen;
    setState(() => _chosen = next);
    final error = await widget.onChanged(next);
    if (error != null && mounted) {
      setState(() => _chosen = prev);
    }
  }

  void _toggle(String id, bool on) =>
      _set(on ? [..._chosen, id] : _chosen.where((a) => a != id).toList());

  void _addByName() {
    final n = _name.text.trim().toLowerCase();
    if (n.isEmpty) return;
    _name.clear();
    if (!_chosen.contains(n)) _set([..._chosen, n]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.android ? 'Приложения' : 'Программы')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: widget.android ? _android() : _desktop(),
        ),
      ),
    );
  }

  Widget _android() {
    final apps = _installed;
    if (apps == null) {
      return Center(child: CircularProgressIndicator(color: GX.accent));
    }
    final q = _search.text.trim().toLowerCase();
    final shown = [
      for (final a in apps)
        if (q.isEmpty ||
            a.label.toLowerCase().contains(q) ||
            a.package.toLowerCase().contains(q))
          a,
    ];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Поиск',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
            itemCount: shown.length,
            itemBuilder: (_, i) {
              final a = shown[i];
              return CheckboxListTile(
                value: _chosen.contains(a.package),
                onChanged: (v) => _toggle(a.package, v ?? false),
                activeColor: GX.accent,
                controlAffinity: ListTileControlAffinity.trailing,
                secondary: SizedBox(
                  width: 40,
                  height: 40,
                  child: a.icon == null
                      ? Icon(Icons.android_rounded, color: GX.muted)
                      : Image.memory(a.icon!, gaplessPlayback: true),
                ),
                title: Text(a.label, style: body(15, weight: 600)),
                subtitle: Text(a.package, style: body(11.5, color: GX.muted)),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _desktop() {
    final running = _running;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        _head('Выбранные'),
        if (_chosen.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
            child: Text('Ничего не выбрано', style: body(13, color: GX.muted)),
          )
        else
          GlassCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final p in _chosen)
                  ListTile(
                    title: Text(p, style: mono(14)),
                    trailing: IconButton(
                      icon: const Icon(Icons.close_rounded),
                      color: GX.muted,
                      onPressed: () => _toggle(p, false),
                    ),
                  ),
              ],
            ),
          ),
        _head('Запущено сейчас'),
        if (running == null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator(color: GX.accent)),
          )
        else if (running.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
            child: Text('Список недоступен', style: body(13, color: GX.muted)),
          )
        else
          GlassCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final p in running)
                  CheckboxListTile(
                    value: _chosen.contains(p),
                    onChanged: (v) => _toggle(p, v ?? false),
                    activeColor: GX.accent,
                    controlAffinity: ListTileControlAffinity.trailing,
                    title: Text(p, style: mono(14)),
                  ),
              ],
            ),
          ),
        _head('Добавить программу по имени'),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _name,
                autocorrect: false,
                style: mono(15),
                decoration: const InputDecoration(hintText: 'chrome.exe'),
                onSubmitted: (_) => _addByName(),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton(onPressed: _addByName, child: const Text('Добавить')),
          ],
        ),
      ],
    );
  }

  Widget _head(String t) => Padding(
    padding: const EdgeInsets.fromLTRB(6, 18, 6, 8),
    child: Text(
      t.toUpperCase(),
      style: body(
        11.5,
        weight: 800,
        color: GX.muted,
      ).copyWith(letterSpacing: 1.2),
    ),
  );
}
