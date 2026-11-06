import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/vpn_core.dart';
import '../links.dart';
import '../routing/routing_settings.dart';
import '../state/app_state.dart';
import '../state/auto_pick.dart';
import '../subscription/server.dart';
import '../subscription/subscription.dart';
import 'flags.dart';
import 'intro.dart';
import 'motion.dart';
import 'servers_screen.dart';
import 'settings_screen.dart';
import 'theme.dart';
import 'widgets.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.state});
  final AppState state;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// Sections arrive one after another as the intro clears.
  final Duration _base = IntroOverlay.wait;

  /// From this width the button and the server list sit side by side. The
  /// desktop window's minimum (720) is already landscape.
  static const _wideFrom = 700.0;

  Widget _in(int i, Widget child) =>
      FadeSlideIn.staggered(index: i, base: _base, child: child);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) => Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, box) =>
                box.maxWidth >= _wideFrom ? _wide(context) : _narrow(context),
          ),
        ),
      ),
    );
  }

  Widget _narrow(BuildContext context) {
    final state = widget.state;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: RefreshIndicator(
          color: GX.accent,
          onRefresh: state.refresh,
          child: LayoutBuilder(
            builder: (context, box) => SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              // Everything fits; only a window too short for the minimum
              // scrolls.
              child: SizedBox(
                height: math.max(box.maxHeight, 520),
                child: Column(
                  children: [
                    _in(0, _TopBar(state: state)),
                    ..._notices(1),
                    Expanded(
                      child: _in(
                        2,
                        _Middle(state: state, minButton: 120, maxButton: 200),
                      ),
                    ),
                    if (state.error != null) ...[
                      _ErrorCard(state: state),
                      const SizedBox(height: 10),
                    ],
                    _in(3, _ServerTile(state: state)),
                    const SizedBox(height: 10),
                    _in(4, const _LinksRow()),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Wide windows: the button on the left, the server list on the right.
  Widget _wide(BuildContext context) {
    final state = widget.state;
    return LayoutBuilder(
      builder: (context, box) {
        final panel = (box.maxWidth * 0.40).clamp(300.0, 540.0);
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: LayoutBuilder(
                      builder: (context, inner) => SingleChildScrollView(
                        child: SizedBox(
                          height: math.max(inner.maxHeight, 440),
                          child: Column(
                            children: [
                              _in(0, _TopBar(state: state)),
                              ..._notices(1),
                              Expanded(
                                child: _in(
                                  2,
                                  _Middle(
                                    state: state,
                                    minButton: 150,
                                    maxButton: 240,
                                    showAuto: true,
                                  ),
                                ),
                              ),
                              if (state.error != null) ...[
                                _ErrorCard(state: state),
                                const SizedBox(height: 10),
                              ],
                              _in(3, const _LinksRow(compact: true)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 20),
              SizedBox(
                width: panel,
                child: FadeSlideIn(
                  delay: _base + const Duration(milliseconds: 180),
                  offset: const Offset(40, 0),
                  duration: const Duration(milliseconds: 700),
                  child: Container(
                    margin: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(
                      color: GX.glass,
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(color: GX.line),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 14, 16, 2),
                          child: Text('Серверы', style: display(18)),
                        ),
                        Expanded(child: ServerList(state: state)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _notices(int index) {
    final state = widget.state;
    final sub = state.subscription!;
    return [
      if (state.update != null) ...[
        _in(index, _UpdateBanner(state: state)),
        const SizedBox(height: 8),
      ],
      _in(index, _PlanCard(sub: sub)),
    ];
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: IntroOverlay.finished,
            builder: (context, done, _) => Opacity(
              opacity: done ? 1 : 0,
              child: Image.asset(
                GX.mark,
                key: IntroOverlay.markKeyIfFlying,
                height: 22,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text('GateX', style: display(19)),
          const Spacer(),
          AnimatedOpacity(
            opacity: state.refreshing ? 1 : 0,
            duration: const Duration(milliseconds: 250),
            child: Padding(
              padding: EdgeInsets.all(10),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: GX.accent,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Обновить подписку',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: state.refreshing ? null : state.refresh,
          ),
          IconButton(
            tooltip: 'Настройки',
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => SettingsScreen(state: state)),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.sub});
  final Subscription sub;

  @override
  Widget build(BuildContext context) {
    final days = sub.daysLeft;
    final soon = days != null && days <= 3;
    final expire = sub.expire;
    final alert = soon || sub.isExpired;
    final until = expire == null
        ? 'Без ограничения по сроку'
        : sub.isExpired
        ? 'Подписка закончилась'
        : 'Осталось ${_days(days!)} · до ${_date(expire)}';
    final used = sub.upload + sub.download;
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (alert ? GX.warn : GX.accent).withValues(alpha: 0.14),
                ),
                child: Icon(
                  alert
                      ? Icons.hourglass_bottom_rounded
                      : Icons.verified_rounded,
                  color: alert ? GX.warn : GX.accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sub.title ?? 'Подписка GateX',
                      style: body(15, weight: 700),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      until,
                      style: body(12.5, color: alert ? GX.warn : GX.muted),
                    ),
                    if (sub.tariff != null) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(
                            Icons.workspace_premium_rounded,
                            size: 14,
                            color: GX.accent,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              sub.tariff!,
                              style: body(12, weight: 700, color: GX.accent),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (alert)
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  onPressed: () => openLink(Links.cabinet),
                  child: const Text('Продлить'),
                ),
              // The panel's text lives behind this button, not on the home.
              if (sub.announce != null && sub.announce!.trim().isNotEmpty)
                IconButton(
                  tooltip: 'Информация о подписке',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.info_outline_rounded, color: GX.muted),
                  onPressed: () => _showAnnounce(context, sub.announce!),
                ),
            ],
          ),
          if (sub.total == 0 && used > 0) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.data_usage_rounded, size: 16, color: GX.muted),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Трафик: ${formatBytes(used)} · без лимита',
                    style: body(12, color: GX.muted),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          if (sub.total > 0) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (used / sub.total).clamp(0, 1).toDouble(),
                minHeight: 5,
                color: GX.accent,
                backgroundColor: GX.glassStrong,
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Трафик: ${formatBytes(used)} из ${formatBytes(sub.total)}',
                style: body(12, color: GX.muted),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// The panel's announcement as it was sent, in a sheet.
  static void _showAnnounce(BuildContext context, String text) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: GX.bg2,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (c) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(c).height * 0.7,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Информация о подписке', style: display(17)),
                const SizedBox(height: 12),
                SelectableText(text, style: body(14)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  static String _days(int n) {
    final m10 = n % 10, m100 = n % 100;
    final word = m10 == 1 && m100 != 11
        ? 'день'
        : m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)
        ? 'дня'
        : 'дней';
    return '$n $word';
  }
}

/// The space between the plan card and the server tile. The button takes
/// what is left after the status lines, so nothing needs to scroll; if even
/// the smallest button does not fit, the block scales down a little.
class _Middle extends StatelessWidget {
  const _Middle({
    required this.state,
    required this.minButton,
    required this.maxButton,
    this.showAuto = false,
  });
  final AppState state;
  final double minButton;
  final double maxButton;

  /// Wide layout: the server tile is not on this side, so the status line
  /// names the server «Авто» picked.
  final bool showAuto;

  @override
  Widget build(BuildContext context) {
    // Status + hint, the routing chip, the live stats: what sits under
    // the button.
    final chip = state.settings.routing.appsMode != AppsMode.all;
    final reserve = 46 + (chip ? 34 : 0) + (state.connected ? 66 : 0);
    return LayoutBuilder(
      builder: (context, box) {
        final size = (box.maxHeight - reserve - ConnectButton.margin - 8)
            .clamp(minButton, maxButton)
            .toDouble();
        return Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(
              width: box.maxWidth,
              child: _ConnectBlock(
                state: state,
                buttonSize: size,
                showAuto: showAuto,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The button with the status and the session timer under it.
class _ConnectBlock extends StatefulWidget {
  const _ConnectBlock({
    required this.state,
    this.buttonSize = 188,
    this.showAuto = false,
  });
  final AppState state;
  final double buttonSize;
  final bool showAuto;

  @override
  State<_ConnectBlock> createState() => _ConnectBlockState();
}

class _ConnectBlockState extends State<_ConnectBlock> {
  DateTime? _since;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_ConnectBlock old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final on = widget.state.vpnState == VpnState.connected;
    if (on && _since == null) {
      _since = DateTime.now();
      _tick = Timer.periodic(
        const Duration(seconds: 1),
        (_) => setState(() {}),
      );
    } else if (!on && _since != null) {
      _since = null;
      _tick?.cancel();
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final (text, color) = state.reconnecting
        ? ('Переподключение…', GX.text)
        : switch (state.vpnState) {
            VpnState.connected => ('Подключено', GX.accent),
            VpnState.connecting => ('Подключаемся…', GX.text),
            VpnState.disconnecting => ('Отключаемся…', GX.text),
            VpnState.disconnected => ('Не подключено', GX.muted),
          };
    final since = _since;
    String hint;
    if (since != null) {
      final d = DateTime.now().difference(since);
      String two(int n) => n.toString().padLeft(2, '0');
      hint =
          '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
      final now = widget.showAuto ? _autoNow(state) : null;
      if (now != null) hint += ' · Авто → ${now.title}';
    } else {
      hint = state.busy ? 'Секунду…' : 'Нажмите, чтобы подключиться';
    }
    final routing = state.settings.routing;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConnectButton(
          state: state.vpnState,
          onTap: state.toggle,
          size: widget.buttonSize,
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, a) => FadeTransition(
            opacity: a,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, 0.3),
                end: Offset.zero,
              ).animate(a),
              child: child,
            ),
          ),
          child: Text(
            text,
            key: ValueKey(text),
            style: display(20, color: color),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          hint,
          style: body(
            13.5,
            color: GX.muted,
            weight: since != null ? 700 : 500,
          ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          child: since == null
              ? const SizedBox(width: double.infinity)
              : _LiveInfo(state: state),
        ),
        if (routing.appsMode != AppsMode.all) ...[
          const SizedBox(height: 8),
          _RouteChip(routing: routing),
        ],
      ],
    );
  }
}

/// The server «Авто» is connected to right now, if any.
Server? _autoNow(AppState state) {
  if (state.selectedServer != null || !state.connected) return null;
  for (final c in state.servers) {
    if (c.id == state.autoCurrentId) return c;
  }
  return null;
}

/// Under the status when only some apps use the VPN.
class _RouteChip extends StatelessWidget {
  const _RouteChip({required this.routing});
  final RoutingSettings routing;

  @override
  Widget build(BuildContext context) {
    final label = routing.appsMode == AppsMode.only
        ? 'Только выбранные приложения'
        : 'Все, кроме выбранных';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: GX.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: GX.accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.alt_route_rounded, size: 14, color: GX.accent),
          const SizedBox(width: 6),
          Text(
            '$label · ${routing.apps.length}',
            style: body(12.5, weight: 600),
          ),
        ],
      ),
    );
  }
}

class _ServerTile extends StatelessWidget {
  const _ServerTile({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final s = state.selectedServer;
    final now = s == null ? _autoNow(state) : null;
    return GlassCard(
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => ServersScreen(state: state))),
      child: Row(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: s == null
                ? const AutoBadge(key: ValueKey('auto'))
                : FlagBadge(key: ValueKey(s.id), code: s.countryCode),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s?.title ?? (now == null ? 'Авто' : 'Авто → ${now.title}'),
                  style: body(16, weight: 700),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  s == null
                      ? 'Самый быстрый из ${_servers(autoCandidates(state.servers).length)}'
                      : s.isRussian
                      ? 'не входит в Авто'
                      : s.description ?? s.transport,
                  style: body(12.5, color: GX.muted),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (s != null)
            PingIndicator(
              tested: state.delays.containsKey(s.id),
              ms: state.delays[s.id],
            ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded, color: GX.muted),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return FadeSlideIn(
      key: ValueKey(state.error),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
        decoration: BoxDecoration(
          color: GX.danger.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(GX.radius),
          border: Border.all(color: GX.danger.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: GX.danger, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(state.error!, style: body(14))),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: state.clearError,
            ),
          ],
        ),
      ),
    );
  }
}

class _UpdateBanner extends StatelessWidget {
  const _UpdateBanner({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final u = state.update!;
    return GlassCard(
      highlight: true,
      onTap: () => openLink(u.url),
      child: Row(
        children: [
          Icon(Icons.system_update_rounded, color: GX.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Доступна версия ${u.version}. Нажмите, чтобы скачать',
              style: body(14, weight: 600),
            ),
          ),
        ],
      ),
    );
  }
}

class _LinksRow extends StatelessWidget {
  const _LinksRow({this.compact = false});

  /// Icon and label side by side, for the short wide window.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    Widget item(IconData icon, String label, String url) => Expanded(
      child: GlassCard(
        padding: EdgeInsets.symmetric(vertical: compact ? 11 : 10),
        onTap: () => openLink(url),
        child: compact
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: GX.accent, size: 18),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      style: body(12.5, weight: 600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              )
            : Column(
                children: [
                  Icon(icon, color: GX.accent, size: 20),
                  const SizedBox(height: 4),
                  Text(label, style: body(12.5, weight: 600)),
                ],
              ),
      ),
    );
    return Row(
      children: [
        item(Icons.person_outline_rounded, 'Кабинет', Links.cabinet),
        const SizedBox(width: 10),
        item(Icons.support_agent_rounded, 'Поддержка', Links.support),
        const SizedBox(width: 10),
        item(Icons.language_rounded, 'Сайт', Links.site),
      ],
    );
  }
}

String _servers(int n) =>
    n % 10 == 1 && n % 100 != 11 ? '$n сервера' : '$n серверов';

/// Under the timer while connected: speed both ways, traffic of this
/// session, and the address sites see.
class _LiveInfo extends StatelessWidget {
  const _LiveInfo({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final tabular = const [FontFeature.tabularFigures()];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: [
          ValueListenableBuilder(
            valueListenable: state.live,
            builder: (context, live, _) => Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                _Pill(
                  icon: Icons.south_rounded,
                  color: GX.accent,
                  text: '${formatBytes(live?.downSpeed ?? 0)}/с',
                  tabular: tabular,
                ),
                _Pill(
                  icon: Icons.north_rounded,
                  color: GX.accent2,
                  text: '${formatBytes(live?.upSpeed ?? 0)}/с',
                  tabular: tabular,
                ),
                _Pill(
                  icon: Icons.data_usage_rounded,
                  color: GX.muted,
                  text: formatBytes((live?.up ?? 0) + (live?.down ?? 0)),
                  tabular: tabular,
                ),
              ],
            ),
          ),
          ValueListenableBuilder(
            valueListenable: state.exit,
            builder: (context, exit, _) => AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: exit == null
                  ? const SizedBox(height: 4)
                  : Padding(
                      key: ValueKey(exit.ip),
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FlagBadge(code: exit.countryCode, size: 18),
                          const SizedBox(width: 8),
                          SelectableText(
                            '${exit.ip} · ${exit.country}',
                            style: body(12.5, color: GX.muted),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.color,
    required this.text,
    required this.tabular,
  });
  final IconData icon;
  final Color color;
  final String text;
  final List<FontFeature> tabular;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: GX.glass,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: GX.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: body(12.5, weight: 700).copyWith(fontFeatures: tabular),
          ),
        ],
      ),
    );
  }
}
