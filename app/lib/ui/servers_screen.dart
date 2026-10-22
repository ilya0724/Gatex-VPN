import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/app_state.dart';
import '../state/diagnose.dart';
import '../subscription/server.dart';
import 'flags.dart';
import 'motion.dart';
import 'theme.dart';
import 'widgets.dart';

class ServersScreen extends StatefulWidget {
  const ServersScreen({super.key, required this.state});
  final AppState state;

  @override
  State<ServersScreen> createState() => _ServersScreenState();
}

class _ServersScreenState extends State<ServersScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Серверы')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ServerList(
            state: widget.state,
            onPicked: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    );
  }
}

/// Авто plus every server, grouped by country, with LTE servers last.
/// Used as its own screen on phones and beside the button on wide windows.
class ServerList extends StatefulWidget {
  const ServerList({super.key, required this.state, this.onPicked});
  final AppState state;
  final VoidCallback? onPicked;

  @override
  State<ServerList> createState() => _ServerListState();
}

class _ServerListState extends State<ServerList> {
  bool _byPing = false;

  @override
  void initState() {
    super.initState();
    if (widget.state.delays.isEmpty) widget.state.testDelays();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        final state = widget.state;
        final items = <Widget>[
          _Toolbar(
            state: state,
            byPing: _byPing,
            onSort: (v) => setState(() => _byPing = v),
          ),
          const SizedBox(height: 12),
          _ServerCard(
            selected: state.selectedId == autoServerId,
            leading: const AutoBadge(),
            title: 'Авто',
            subtitle: Text(
              'Самый быстрый сервер, переключение при сбое',
              style: body(12, color: GX.muted),
            ),
            onTap: () => _pick(autoServerId),
          ),
        ];
        var i = 0;
        for (final (label, servers) in _groups(state)) {
          items.add(_GroupHeader(label));
          for (final s in servers) {
            items.add(
              FadeSlideIn.staggered(
                index: i++ ~/ 2,
                offset: const Offset(0, 10),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _tile(state, s),
                ),
              ),
            );
          }
        }
        return RefreshIndicator(
          color: GX.accent,
          onRefresh: state.refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: items,
          ),
        );
      },
    );
  }

  List<(String, List<Server>)> _groups(AppState state) {
    final servers = state.servers;
    if (_byPing) {
      final sorted = [...servers]
        ..sort((a, b) {
          final da = state.delays[a.id], db = state.delays[b.id];
          return (da ?? 1 << 30).compareTo(db ?? 1 << 30);
        });
      return [('По скорости', sorted)];
    }
    final byCountry = <String, List<Server>>{};
    final lte = <Server>[];
    for (final s in servers) {
      if (s.isLte) {
        lte.add(s);
      } else {
        byCountry.putIfAbsent(s.countryCode, () => []).add(s);
      }
    }
    return [
      for (final e in byCountry.entries)
        (countryNames[e.key] ?? (e.key.isEmpty ? 'Другие' : e.key), e.value),
      if (lte.isNotEmpty) ('Для мобильного интернета (LTE)', lte),
    ];
  }

  Widget _tile(AppState state, Server s) {
    final tested = state.delays.containsKey(s.id);
    final failure = state.delayErrors[s.id];
    return _ServerCard(
      selected: state.selectedId == s.id,
      leading: FlagBadge(code: s.countryCode),
      title: s.title,
      subtitle: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(s.transport, style: body(12, color: GX.muted)),
          if (s.isLte) TagChip('LTE', color: GX.warn),
          if (failure != null)
            Text(
              failure.summary,
              style: body(12, weight: 600, color: GX.danger),
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PingIndicator(
            tested: tested,
            ms: state.delays[s.id],
            testing: state.testingDelays,
          ),
          if (failure != null)
            IconButton(
              tooltip: 'Подробнее',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.info_outline_rounded, size: 18),
              color: GX.muted,
              onPressed: () => _showFailure(s, failure),
            ),
        ],
      ),
      onTap: () => _pick(s.id),
    );
  }

  void _pick(String id) {
    widget.state.select(id);
    widget.onPicked?.call();
  }

  void _showFailure(Server s, DelayFailure f) {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(s.title, style: display(17)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(f.summary, style: body(15, weight: 700, color: GX.danger)),
              const SizedBox(height: 4),
              Text(
                '${s.transport} · ${s.address}:${s.port}',
                style: body(12, color: GX.muted),
              ),
              const SizedBox(height: 12),
              SelectableText(f.detail, style: mono(12)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(
                ClipboardData(
                  text:
                      '${s.name} (${s.transport}, ${s.address}:${s.port})\n${f.summary}\n${f.detail}',
                ),
              );
              Navigator.pop(c);
            },
            child: const Text('Скопировать для поддержки'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.state,
    required this.byPing,
    required this.onSort,
  });
  final AppState state;
  final bool byPing;
  final ValueChanged<bool> onSort;

  @override
  Widget build(BuildContext context) {
    final failed = state.delays.values.where((d) => d == null).length;
    final ok = state.delays.length - failed;
    return Row(
      children: [
        Expanded(
          child: Text(
            state.testingDelays
                ? 'Проверяем серверы… ${state.delays.length} из ${state.servers.length}'
                : state.delays.isEmpty
                ? '${state.servers.length} серверов'
                : 'Отвечают $ok из ${state.servers.length}',
            style: body(13, color: GX.muted),
          ),
        ),
        FilterChip(
          label: Text('По пингу', style: body(12, weight: 600)),
          selected: byPing,
          onSelected: onSort,
          showCheckmark: false,
          selectedColor: GX.accent.withValues(alpha: 0.2),
          backgroundColor: GX.glass,
          side: BorderSide(color: byPing ? GX.accent : GX.line),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          visualDensity: VisualDensity.compact,
        ),
        const SizedBox(width: 6),
        IconButton.filledTonal(
          tooltip: 'Проверить скорость',
          onPressed: state.testingDelays ? null : state.testDelays,
          style: IconButton.styleFrom(backgroundColor: GX.glassStrong),
          icon: state.testingDelays
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: GX.accent,
                  ),
                )
              : Icon(Icons.speed_rounded, color: GX.accent),
        ),
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Text(
        label.toUpperCase(),
        style: body(
          11.5,
          weight: 800,
          color: GX.muted,
        ).copyWith(letterSpacing: 1.2),
      ),
    );
  }
}

class _ServerCard extends StatelessWidget {
  const _ServerCard({
    required this.selected,
    required this.leading,
    required this.title,
    required this.subtitle,
    this.trailing,
    required this.onTap,
  });
  final bool selected;
  final Widget leading;
  final String title;
  final Widget subtitle;
  final Widget? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      highlight: selected,
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: body(15, weight: 700),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                subtitle,
              ],
            ),
          ),
          ?trailing,
          AnimatedOpacity(
            opacity: selected ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: Padding(
              padding: EdgeInsets.only(left: 6),
              child: Icon(
                Icons.check_circle_rounded,
                color: GX.accent,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
