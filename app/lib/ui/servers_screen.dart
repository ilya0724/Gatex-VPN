import 'package:flutter/material.dart';

import '../state/app_state.dart';
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
        return Scaffold(
          appBar: AppBar(
            title: const Text('Серверы'),
            actions: [
              state.testingDelays
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: GX.accent,
                        ),
                      ),
                    )
                  : IconButton(
                      tooltip: 'Проверить скорость',
                      icon: const Icon(Icons.speed_rounded),
                      onPressed: state.testDelays,
                    ),
            ],
          ),
          body: Backdrop(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: RefreshIndicator(
                  color: GX.accent,
                  onRefresh: state.refresh,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _tile(
                        selected: state.selectedId == autoServerId,
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: const BoxDecoration(
                            color: Color(0x242EE6A6),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.bolt_rounded,
                            color: GX.accent,
                          ),
                        ),
                        title: 'Авто',
                        subtitle: 'Самый быстрый сервер, переключение при сбое',
                        onTap: () => _pick(autoServerId),
                      ),
                      const SizedBox(height: 16),
                      for (final s in state.servers) ...[
                        _tile(
                          selected: state.selectedId == s.id,
                          leading: FlagBadge(flag: s.flag),
                          title: s.title,
                          subtitle: s.transport,
                          trailing: DelayChip(
                            tested: state.delays.containsKey(s.id),
                            ms: state.delays[s.id],
                          ),
                          onTap: () => _pick(s.id),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _pick(String id) {
    widget.state.select(id);
    Navigator.of(context).pop();
  }

  Widget _tile({
    required bool selected,
    required Widget leading,
    required String title,
    required String subtitle,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    return GlassCard(
      highlight: selected,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: body(15, weight: 700)),
                Text(subtitle, style: body(12, color: GX.muted)),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
