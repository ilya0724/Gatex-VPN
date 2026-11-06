import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/android_core.dart';
import '../routing/routing_settings.dart';
import 'app_picker_screen.dart';
import 'rule_sheet.dart';
import 'theme.dart';
import 'widgets.dart';

/// Saves the routing; returns a message for the user when it was refused.
typedef SaveRouting = Future<String?> Function(RoutingSettings r);

/// «Маршрутизация»: which apps use the VPN, ready-made sets, own rules.
class RoutingScreen extends StatefulWidget {
  const RoutingScreen({
    super.key,
    required this.routing,
    required this.onSave,
    required this.android,
    this.loadApps,
    this.loadProcesses,
  });

  final RoutingSettings routing;
  final SaveRouting onSave;

  /// Android picks installed apps; desktop picks programs by process name.
  final bool android;
  final Future<List<InstalledApp>> Function()? loadApps;
  final Future<List<String>> Function()? loadProcesses;

  @override
  State<RoutingScreen> createState() => _RoutingScreenState();
}

class _RoutingScreenState extends State<RoutingScreen> {
  late RoutingSettings _r = widget.routing;

  void _snack(String text) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(text)));

  /// Applies [next] once it is accepted; otherwise shows why and keeps [_r].
  Future<String?> _save(RoutingSettings next) async {
    final error = await widget.onSave(next);
    if (!mounted) return error;
    if (error != null) {
      _snack(error);
    } else {
      setState(() => _r = next);
    }
    return error;
  }

  Future<void> _addRule() async {
    final rule = await showRuleSheet(context);
    if (rule != null) await _save(_r.copyWith(rules: [..._r.rules, rule]));
  }

  void _replaceRule(int i, RoutingRule? rule) {
    final rules = [..._r.rules];
    if (rule == null) {
      rules.removeAt(i);
    } else {
      rules[i] = rule;
    }
    _save(_r.copyWith(rules: rules));
  }

  void _moveRule(int i, int by) {
    final j = i + by;
    if (j < 0 || j >= _r.rules.length) return;
    final rules = [..._r.rules];
    final r = rules.removeAt(i);
    rules.insert(j, r);
    _save(_r.copyWith(rules: rules));
  }

  Future<void> _export() async {
    await Clipboard.setData(ClipboardData(text: _r.export()));
    if (mounted) _snack('Скопировано');
  }

  Future<void> _import() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    try {
      final imported = RoutingSettings.import(data?.text ?? '');
      await _save(imported);
    } on FormatException catch (e) {
      if (mounted) _snack(e.message);
    }
  }

  void _pickApps() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AppPickerScreen(
          apps: _r.apps,
          android: widget.android,
          loadApps: widget.loadApps,
          loadProcesses: widget.loadProcesses,
          onChanged: (apps) => _save(_r.copyWith(apps: apps)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final android = widget.android;
    final what = android ? 'Приложения' : 'Программы';
    return Scaffold(
      appBar: AppBar(title: const Text('Маршрутизация')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              _Section(
                title: what,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: SegmentedPick<AppsMode>(
                      options: const [
                        (AppsMode.all, 'Все'),
                        (AppsMode.only, 'Только выбранные'),
                        (AppsMode.except, 'Кроме выбранных'),
                      ],
                      value: _r.appsMode,
                      onChanged: (m) => _save(_r.copyWith(appsMode: m)),
                    ),
                  ),
                  _NavRow(
                    icon: android
                        ? Icons.apps_rounded
                        : Icons.desktop_windows_rounded,
                    title: android ? 'Выбрать приложения' : 'Выбрать программы',
                    value: _r.apps.isEmpty ? null : '${_r.apps.length}',
                    onTap: _pickApps,
                  ),
                ],
              ),
              if (!android)
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
                  child: Text(
                    'Программы мимо VPN всегда идут напрямую, правила для сайтов действуют только внутри VPN.',
                    style: body(12.5, color: GX.muted),
                  ),
                ),
              _Section(
                title: 'Готовые наборы',
                children: [
                  _SwitchRow(
                    icon: Icons.flag_rounded,
                    title: 'Российские сайты напрямую',
                    subtitle: 'Банки, Госуслуги, Яндекс и VK без VPN',
                    value: _r.directRu,
                    onChanged: (v) => _save(_r.copyWith(directRu: v)),
                  ),
                  _SwitchRow(
                    icon: Icons.block_rounded,
                    title: 'Блокировать рекламу',
                    subtitle: 'Трекеры и рекламные сети',
                    value: _r.blockAds,
                    onChanged: (v) => _save(_r.copyWith(blockAds: v)),
                  ),
                ],
              ),
              _Section(
                title: 'Свои правила',
                children: [
                  for (var i = 0; i < _r.rules.length; i++)
                    _RuleRow(
                      rule: _r.rules[i],
                      first: i == 0,
                      last: i == _r.rules.length - 1,
                      onToggle: (v) =>
                          _replaceRule(i, _r.rules[i].copyWith(enabled: v)),
                      onUp: () => _moveRule(i, -1),
                      onDown: () => _moveRule(i, 1),
                      onDelete: () => _replaceRule(i, null),
                    ),
                  _NavRow(
                    icon: Icons.add_rounded,
                    title: 'Добавить правило',
                    onTap: _addRule,
                  ),
                ],
              ),
              _Section(
                title: 'Импорт и экспорт',
                children: [
                  _NavRow(
                    icon: Icons.upload_rounded,
                    title: 'Экспорт в буфер обмена',
                    onTap: _export,
                  ),
                  _NavRow(
                    icon: Icons.download_rounded,
                    title: 'Импорт из буфера обмена',
                    onTap: _import,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({
    required this.rule,
    required this.first,
    required this.last,
    required this.onToggle,
    required this.onUp,
    required this.onDown,
    required this.onDelete,
  });
  final RoutingRule rule;
  final bool first;
  final bool last;
  final ValueChanged<bool> onToggle;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final (tag, color) = switch (rule.action) {
      RuleAction.proxy => ('VPN', GX.accent),
      RuleAction.direct => ('НАПРЯМУЮ', GX.muted),
      RuleAction.block => ('БЛОК', GX.danger),
    };
    final kind = switch (rule.kind) {
      RuleKind.domain => 'Домен',
      RuleKind.keyword => 'Ключевое слово',
      RuleKind.ip => 'IP / подсеть',
    };
    Widget small(IconData icon, VoidCallback? onTap) => IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 20),
      color: GX.muted,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 34, height: 34),
      padding: EdgeInsets.zero,
    );
    return Opacity(
      opacity: rule.enabled ? 1 : 0.5,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        child: Row(
          children: [
            Switch(value: rule.enabled, onChanged: onToggle),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rule.value,
                    style: mono(14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      TagChip(tag, color: color),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          kind,
                          style: body(12, color: GX.muted),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            small(Icons.keyboard_arrow_up_rounded, first ? null : onUp),
            small(Icons.keyboard_arrow_down_rounded, last ? null : onDown),
            small(Icons.delete_outline_rounded, onDelete),
          ],
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
                  if (i > 0) Divider(height: 1, indent: 16, color: GX.line),
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
  });
  final IconData icon;
  final String title;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 15, 12, 15),
        child: Row(
          children: [
            Icon(icon, color: GX.accent, size: 22),
            const SizedBox(width: 18),
            Expanded(child: Text(title, style: body(15, weight: 600))),
            if (value != null) Text(value!, style: body(13, color: GX.muted)),
            Icon(Icons.chevron_right_rounded, color: GX.muted),
          ],
        ),
      ),
    );
  }
}
