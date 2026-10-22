import 'dart:async';

import 'package:flutter/material.dart';

import '../core/vpn_core.dart';
import '../links.dart';
import '../state/app_state.dart';
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
                box.maxWidth >= 860 ? _wide(context) : _narrow(context),
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
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: box.maxHeight),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      children: [
                        _in(0, _TopBar(state: state)),
                        ..._notices(1),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: _in(2, _ConnectBlock(state: state)),
                    ),
                    Column(
                      children: [
                        if (state.error != null) ...[
                          _ErrorCard(state: state),
                          const SizedBox(height: 12),
                        ],
                        _in(3, _ServerTile(state: state)),
                        const SizedBox(height: 12),
                        _in(4, const _LinksRow()),
                        const SizedBox(height: 16),
                      ],
                    ),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _in(0, _TopBar(state: state)),
                  ..._notices(1),
                  const SizedBox(height: 24),
                  _in(2, _ConnectBlock(state: state)),
                  const SizedBox(height: 16),
                  if (state.error != null) ...[
                    _ErrorCard(state: state),
                    const SizedBox(height: 12),
                  ],
                  _in(3, const _LinksRow()),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 420,
            child: _in(
              2,
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 16, 4),
                    child: Text('Серверы', style: display(18)),
                  ),
                  Expanded(child: ServerList(state: state)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _notices(int index) {
    final state = widget.state;
    final sub = state.subscription!;
    return [
      if (state.update != null) ...[
        _in(index, _UpdateBanner(state: state)),
        const SizedBox(height: 12),
      ],
      _in(index, _PlanCard(sub: sub)),
      if (sub.announce != null) ...[
        const SizedBox(height: 12),
        _in(
          index,
          GlassCard(
            child: Row(
              children: [
                const Icon(Icons.campaign_outlined, color: GX.accent),
                const SizedBox(width: 12),
                Expanded(child: Text(sub.announce!, style: body(14))),
              ],
            ),
          ),
        ),
      ],
    ];
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Image.asset('assets/images/mark.png', height: 24),
          const SizedBox(width: 10),
          Text('GateX', style: display(19)),
          const Spacer(),
          AnimatedOpacity(
            opacity: state.refreshing ? 1 : 0,
            duration: const Duration(milliseconds: 250),
            child: const Padding(
              padding: EdgeInsets.all(12),
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
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (alert ? GX.warn : GX.accent).withValues(alpha: 0.14),
                ),
                child: Icon(
                  alert
                      ? Icons.hourglass_bottom_rounded
                      : Icons.verified_rounded,
                  color: alert ? GX.warn : GX.accent,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
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
                  ],
                ),
              ),
              if (alert)
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 38),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  onPressed: () => openLink(Links.cabinet),
                  child: const Text('Продлить'),
                ),
            ],
          ),
          if (sub.total > 0) ...[
            const SizedBox(height: 12),
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
                'Трафик: ${_gb(used)} из ${_gb(sub.total)}',
                style: body(12, color: GX.muted),
              ),
            ),
          ],
        ],
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

  static String _gb(int bytes) =>
      '${(bytes / (1 << 30)).toStringAsFixed(1)} ГБ';
}

/// The button with the status and the session timer under it.
class _ConnectBlock extends StatefulWidget {
  const _ConnectBlock({required this.state});
  final AppState state;

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
    final (text, color) = switch (state.vpnState) {
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
    } else {
      hint = state.busy ? 'Секунду…' : 'Нажмите, чтобы подключиться';
    }
    return Column(
      children: [
        ConnectButton(state: state.vpnState, onTap: state.toggle),
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
        const SizedBox(height: 6),
        Text(
          hint,
          style: body(
            13.5,
            color: GX.muted,
            weight: since != null ? 700 : 500,
          ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
        ),
      ],
    );
  }
}

class _ServerTile extends StatelessWidget {
  const _ServerTile({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final s = state.selectedServer;
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
                  s?.title ?? 'Авто',
                  style: body(16, weight: 700),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  s == null
                      ? 'Самый быстрый из ${_servers(state.servers.length)}'
                      : s.transport,
                  style: body(12.5, color: GX.muted),
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
          const Icon(Icons.chevron_right_rounded, color: GX.muted),
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
            const Icon(Icons.error_outline_rounded, color: GX.danger, size: 20),
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
          const Icon(Icons.system_update_rounded, color: GX.accent),
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
  const _LinksRow();

  @override
  Widget build(BuildContext context) {
    Widget item(IconData icon, String label, String url) => Expanded(
      child: GlassCard(
        padding: const EdgeInsets.symmetric(vertical: 14),
        onTap: () => openLink(url),
        child: Column(
          children: [
            Icon(icon, color: GX.accent, size: 22),
            const SizedBox(height: 6),
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
