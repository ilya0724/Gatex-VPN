import 'package:flutter/material.dart';

import '../links.dart';
import '../state/app_state.dart';
import 'theme.dart';
import 'widgets.dart';

Future<void> showSettingsSheet(BuildContext context, AppState state) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: GX.bg2,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => _SettingsSheet(state: state),
  );
}

class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet({required this.state});
  final AppState state;

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  String _coreVersion = '';

  @override
  void initState() {
    super.initState();
    widget.state.core.coreVersion().then((v) {
      if (mounted) setState(() => _coreVersion = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    Widget row(
      IconData icon,
      String title,
      VoidCallback onTap, {
      Color? color,
    }) => ListTile(
      leading: Icon(icon, color: color ?? GX.accent),
      title: Text(title, style: body(15, weight: 600, color: color ?? GX.text)),
      onTap: onTap,
    );
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          row(Icons.refresh_rounded, 'Обновить подписку', () {
            Navigator.pop(context);
            state.refresh();
          }),
          row(
            Icons.person_outline_rounded,
            'Личный кабинет',
            () => openLink(Links.cabinet),
          ),
          row(
            Icons.support_agent_rounded,
            'Поддержка',
            () => openLink(Links.support),
          ),
          row(
            Icons.campaign_outlined,
            'Канал GateX',
            () => openLink(Links.channel),
          ),
          row(Icons.logout_rounded, 'Удалить подписку с устройства', () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                backgroundColor: GX.bg2,
                title: Text('Удалить подписку?', style: display(18)),
                content: Text(
                  'VPN отключится. Подписка останется в боте, её можно добавить снова.',
                  style: body(14, color: GX.muted),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('Отмена'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: const Text('Удалить'),
                  ),
                ],
              ),
            );
            if (ok == true && context.mounted) {
              Navigator.pop(context);
              await state.removeSubscription();
            }
          }, color: GX.danger),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Text(
              'GateX ${state.appVersion}${_coreVersion.isEmpty ? '' : ' · Xray $_coreVersion'}',
              style: body(12, color: GX.muted),
            ),
          ),
        ],
      ),
    );
  }
}
