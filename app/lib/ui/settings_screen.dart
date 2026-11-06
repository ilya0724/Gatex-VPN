import 'dart:io';

import 'package:flutter/material.dart';

import '../desktop/desktop_shell.dart';
import '../core/android_core.dart';
import '../links.dart';
import '../routing/processes.dart';
import '../state/app_state.dart';
import '../state/settings.dart';
import 'journal_screen.dart';
import 'routing_screen.dart';
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

  /// Windows and wide tablets: a nav on the left, the page on the right.
  static const _wideFrom = 860.0;

  _Page _page = _Page.settings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => LayoutBuilder(
        builder: (context, box) =>
            box.maxWidth >= _wideFrom ? _wide() : _narrow(),
      ),
    );
  }

  Widget _stagger(int i, Widget child) =>
      FadeSlideIn.staggered(index: i, child: child);

  Widget _theme(int i) => _stagger(
    i,
    _ThemePicker(current: state.settings.theme, onPick: state.setTheme),
  );

  Widget _connection(int i, {required bool routingRow}) {
    final s = state.settings;
    return _stagger(
      i,
      _Section(
        title: 'Подключение',
        children: [
          _SwitchRow(
            icon: Icons.flash_on_rounded,
            title: 'Подключаться при запуске',
            subtitle: 'GateX сам включит VPN, когда откроется',
            value: s.autoConnect,
            onChanged: (v) => _change((s) => s.autoConnect = v),
          ),
          if (routingRow)
            _NavRow(
              icon: Icons.alt_route_rounded,
              title: 'Маршрутизация',
              subtitle: 'Приложения, сайты, российские сайты напрямую',
              onTap: _openRouting,
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
            onChanged: (v) => _change((s) => s.ipv6 = v, tunnel: true),
          ),
        ],
      ),
    );
  }

  Widget _appSection(int i) {
    final s = state.settings;
    final os = Platform.isWindows ? 'Windows' : 'системой';
    return _stagger(
      i,
      _Section(
        title: 'Приложение',
        children: [
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
            subtitle: 'VPN продолжит работать, иконка будет у часов',
            value: s.closeToTray,
            onChanged: (v) => _change((s) => s.closeToTray = v),
          ),
        ],
      ),
    );
  }

  Widget _subscription(int i) => _stagger(
    i,
    _Section(
      title: 'Подписка',
      children: [
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
      ],
    ),
  );

  Widget _help(int i, {required bool journalRow}) => _stagger(
    i,
    _Section(
      title: 'Помощь',
      children: [
        if (journalRow)
          _NavRow(
            icon: Icons.receipt_long_rounded,
            title: 'Журнал',
            value: 'для поддержки',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => JournalScreen(state: state)),
            ),
          ),
        _NavRow(
          icon: Icons.support_agent_rounded,
          title: 'Поддержка',
          value: '@gatexvpn_support',
          onTap: () => openLink(Links.support),
        ),
        _NavRow(
          icon: Icons.campaign_rounded,
          title: 'Канал GateX',
          onTap: () => openLink(Links.channel),
        ),
        _NavRow(
          icon: Icons.language_rounded,
          title: 'Сайт',
          value: 'gatexx.ru',
          onTap: () => openLink(Links.site),
        ),
      ],
    ),
  );

  Widget _footer() => Center(
    child: Text(
      'GateX ${state.appVersion}${_coreVersion.isEmpty ? '' : ' · Xray $_coreVersion'}',
      style: body(12, color: GX.muted),
    ),
  );

  Widget _narrow() {
    final desktop = DesktopShell.supported;
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            children: [
              _theme(0),
              _connection(1, routingRow: true),
              if (desktop) _appSection(2),
              _subscription(3),
              _help(4, journalRow: true),
              const SizedBox(height: 8),
              _footer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _wide() {
    final desktop = DesktopShell.supported;
    final Widget pane = switch (_page) {
      _Page.settings => Scaffold(
        appBar: AppBar(
          title: const Text('Настройки'),
          automaticallyImplyLeading: false,
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 940),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            _theme(0),
                            _connection(1, routingRow: false),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          children: [
                            if (desktop) _appSection(2),
                            _subscription(3),
                            _help(4, journalRow: false),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _footer(),
                ],
              ),
            ),
          ),
        ),
      ),
      _Page.routing => _routingScreen(embedded: true),
      _Page.journal => JournalScreen(state: state, embedded: true),
    };
    return Scaffold(
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 220,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SideItem(
                      icon: Icons.arrow_back_rounded,
                      label: 'Назад',
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(height: 10),
                    for (final (page, icon, label) in const [
                      (_Page.settings, Icons.tune_rounded, 'Настройки'),
                      (_Page.routing, Icons.alt_route_rounded, 'Маршрутизация'),
                      (_Page.journal, Icons.receipt_long_rounded, 'Журнал'),
                    ])
                      _SideItem(
                        icon: icon,
                        label: label,
                        selected: _page == page,
                        onTap: () => setState(() => _page = page),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: KeyedSubtree(key: ValueKey(_page), child: pane),
            ),
          ],
        ),
      ),
    );
  }

  Widget _routingScreen({bool embedded = false}) {
    final core = state.core;
    return RoutingScreen(
      routing: state.settings.routing,
      onSave: state.updateRouting,
      android: core is AndroidCore,
      loadApps: core is AndroidCore ? core.installedApps : null,
      loadProcesses: runningProcesses,
      embedded: embedded,
    );
  }

  void _openRouting() =>
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => _routingScreen()));

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

enum _Page { settings, routing, journal }

/// One entry of the left nav on wide windows.
class _SideItem extends StatelessWidget {
  const _SideItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected
            ? GX.accent.withValues(alpha: 0.14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(icon, size: 20, color: selected ? GX.accent : GX.muted),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: body(
                      14,
                      weight: selected ? 700 : 600,
                      color: selected ? GX.text : GX.muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
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
                  if (i > 0) Divider(height: 1, indent: 56, color: GX.line),
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
        padding: const EdgeInsets.fromLTRB(16, 9, 12, 9),
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
    this.subtitle,
    this.danger = false,
  });
  final IconData icon;
  final String title;
  final String? value;
  final String? subtitle;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? GX.danger : GX.text;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            Icon(icon, color: danger ? GX.danger : GX.accent, size: 22),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: body(15, weight: 600, color: color)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: body(12.5, color: GX.muted)),
                  ],
                ],
              ),
            ),
            if (value != null) Text(value!, style: body(13, color: GX.muted)),
            if (!danger) Icon(Icons.chevron_right_rounded, color: GX.muted),
          ],
        ),
      ),
    );
  }
}

/// Three cards that preview each colour theme.
class _ThemePicker extends StatelessWidget {
  const _ThemePicker({required this.current, required this.onPick});
  final String current;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
            child: Text(
              'ОФОРМЛЕНИЕ',
              style: body(
                11.5,
                weight: 800,
                color: GX.muted,
              ).copyWith(letterSpacing: 1.2),
            ),
          ),
          Row(
            children: [
              for (final p in palettes) ...[
                if (p != palettes.first) const SizedBox(width: 10),
                Expanded(
                  child: _Swatch(
                    palette: p,
                    selected: p.id == current,
                    onTap: () => onPick(p.id),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.palette,
    required this.selected,
    required this.onTap,
  });
  final Palette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return PressScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        height: 96,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? GX.accent : GX.line,
            width: selected ? 2 : 1,
          ),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [p.bg2, p.bg],
          ),
          boxShadow: [
            if (selected)
              BoxShadow(
                color: GX.accent.withValues(alpha: 0.25),
                blurRadius: 18,
              ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              left: -20,
              top: -30,
              child: Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      p.glow[0].withValues(alpha: p.light ? 0.5 : 0.35),
                      p.glow[0].withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            Align(
              alignment: const Alignment(0, -0.25),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [p.accent, p.accent2]),
                ),
                child: Icon(
                  Icons.power_settings_new_rounded,
                  size: 20,
                  color: p.accentInk,
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 12,
              child: Text(
                p.name,
                textAlign: TextAlign.center,
                style: body(13, weight: 700, color: p.text),
              ),
            ),
            if (selected)
              Positioned(
                right: 8,
                top: 8,
                child: Icon(
                  Icons.check_circle_rounded,
                  size: 18,
                  color: p.accent,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
