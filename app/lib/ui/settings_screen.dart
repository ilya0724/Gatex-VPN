import 'dart:io';

import 'package:flutter/material.dart';

import '../desktop/desktop_shell.dart';
import '../links.dart';
import '../state/app_state.dart';
import '../state/settings.dart';
import 'journal_screen.dart';
import 'motion.dart';
import 'theme.dart';
import 'widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.state});
  final AppState state;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _coreVersion = '';

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    state.core.coreVersion().then((v) {
      if (mounted) setState(() => _coreVersion = v);
    });
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  /// Changes that alter the tunnel's config apply on the next connect, or
  /// right away with a quick reconnect when the VPN is on.
  Future<void> _change(
    void Function(Settings s) f, {
    bool tunnel = false,
  }) async {
    await state.updateSettings(f, reconnect: tunnel);
    if (tunnel && state.connected && mounted) {
      _snack('Переподключились с новыми настройками');
    }
  }

  @override
  Widget build(BuildContext context) {
    final desktop = DesktopShell.supported;
    final os = Platform.isWindows ? 'Windows' : 'системой';
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final s = state.settings;
        var i = 0;
        Widget section(String title, List<Widget> rows) =>
            FadeSlideIn.staggered(
              index: i++,
              child: _Section(title: title, children: rows),
            );
        return Scaffold(
          appBar: AppBar(title: const Text('Настройки')),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  section('Подключение', [
                    _SwitchRow(
                      icon: Icons.flash_on_rounded,
                      title: 'Подключаться при запуске',
                      subtitle: 'GateX сам включит VPN, когда откроется',
                      value: s.autoConnect,
                      onChanged: (v) => _change((s) => s.autoConnect = v),
                    ),
                    _SwitchRow(
                      icon: Icons.alt_route_rounded,
                      title: 'Российские сайты напрямую',
                      subtitle: 'Банки, Госуслуги, Яндекс и VK работают без VPN и быстрее',
                      value: s.directRu,
                      onChanged: (v) =>
                          _change((s) => s.directRu = v, tunnel: true),
                    ),
                    _NavRow(
                      icon: Icons.dns_rounded,
                      title: 'DNS',
                      value: s.dns.label,
                      onTap: _pickDns,
                    ),
                    _SwitchRow(
                      icon: Icons.lan_rounded,
                      title: 'IPv6',
                      subtitle: 'Выключите, если сайты открываются медленно',
                      value: s.ipv6,
                      onChanged: (v) =>
                          _change((s) => s.ipv6 = v, tunnel: true),
                    ),
                  ]),
                  if (desktop)
                    section('Приложение', [
                      _SwitchRow(
                        icon: Icons.power_rounded,
                        title: 'Запускать вместе с $os',
                        subtitle: Platform.isWindows
                            ? 'Без запроса прав администратора, сразу в трей'
                            : 'Сразу в трей',
                        value: s.launchAtStartup,
                        onChanged: _setAutostart,
                      ),
                      _SwitchRow(
                        icon: Icons.move_to_inbox_rounded,
                        title: 'Сворачивать в трей при закрытии',
                        subtitle:
                            'VPN продолжит работать, иконка будет у часов',
                        value: s.closeToTray,
                        onChanged: (v) => _change((s) => s.closeToTray = v),
                      ),
                    ]),
                  section('Подписка', [
                    _NavRow(
                      icon: Icons.refresh_rounded,
                      title: 'Обновить подписку',
                      onTap: () {
                        state.refresh();
                        _snack('Обновляем подписку');
                      },
                    ),
                    _NavRow(
                      icon: Icons.person_outline_rounded,
                      title: 'Личный кабинет',
                      onTap: () => openLink(Links.cabinet),
                    ),
                    _NavRow(
                      icon: Icons.logout_rounded,
                      title: 'Удалить подписку с устройства',
                      danger: true,
                      onTap: _removeSubscription,
                    ),
                  ]),
                  section('Помощь', [
                    _NavRow(
                      icon: Icons.receipt_long_rounded,
                      title: 'Журнал',
                      value: 'для поддержки',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => JournalScreen(state: state),
                        ),
                      ),
                    ),
                    _NavRow(
                      icon: Icons.support_agent_rounded,
                      title: 'Поддержка',
                      value: '@gatexvpn_support',
                      onTap: () => openLink(Links.support),
                    ),
                    _NavRow(
                      icon: Icons.campaign_outlined,
                      title: 'Канал GateX',
                      onTap: () => openLink(Links.channel),
                    ),
                    _NavRow(
                      icon: Icons.language_rounded,
                      title: 'Сайт',
                      value: 'gatexx.ru',
                      onTap: () => openLink(Links.site),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      'GateX ${state.appVersion}${_coreVersion.isEmpty ? '' : ' · Xray $_coreVersion'}',
                      style: body(12, color: GX.muted),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _setAutostart(bool v) async {
    final error = await DesktopShell.instance.syncAutostart(v);
    if (error != null) {
      _snack('Не получилось: $error');
      state.log('Автозапуск: $error', error: true);
      return;
    }
    await _change((s) => s.launchAtStartup = v);
  }

  Future<void> _pickDns() async {
    final current = state.settings.dns;
    final picked = await showModalBottomSheet<DnsPreset>(
      context: context,
      backgroundColor: GX.bg2,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: RadioGroup<String>(
          groupValue: current.id,
          onChanged: (id) =>
              Navigator.pop(c, dnsPresets.firstWhere((p) => p.id == id)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final p in dnsPresets)
                RadioListTile<String>(
                  value: p.id,
                  activeColor: GX.accent,
                  title: Text(p.label, style: body(15, weight: 700)),
                  subtitle: Text(p.note, style: body(12.5, color: GX.muted)),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (picked != null && picked.id != current.id) {
      await _change((s) => s.dns = picked, tunnel: true);
    }
  }

  Future<void> _removeSubscription() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
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
            child: Text(
              'Удалить',
              style: body(14, weight: 700, color: GX.danger),
            ),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      Navigator.of(context).popUntil((r) => r.isFirst);
      await state.removeSubscription();
    }
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
            child: Text(
              title.toUpperCase(),
              style: body(
                11.5,
                weight: 800,
                color: GX.muted,
              ).copyWith(letterSpacing: 1.2),
            ),
          ),
          GlassCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0)
                    const Divider(height: 1, indent: 56, color: GX.line),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            Icon(icon, color: GX.accent, size: 22),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: body(15, weight: 600)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: body(12.5, color: GX.muted)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.value,
    this.danger = false,
  });
  final IconData icon;
  final String title;
  final String? value;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? GX.danger : GX.text;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 15, 12, 15),
        child: Row(
          children: [
            Icon(icon, color: danger ? GX.danger : GX.accent, size: 22),
            const SizedBox(width: 18),
            Expanded(
              child: Text(title, style: body(15, weight: 600, color: color)),
            ),
            if (value != null) Text(value!, style: body(13, color: GX.muted)),
            if (!danger)
              const Icon(Icons.chevron_right_rounded, color: GX.muted),
          ],
        ),
      ),
    );
  }
}
