import 'dart:async';

import 'package:flutter/material.dart';

import '../core/vpn_core.dart';
import '../links.dart';
import '../state/app_state.dart';
import '../subscription/subscription.dart';
import 'servers_screen.dart';
import 'settings_sheet.dart';
import 'theme.dart';
import 'widgets.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final sub = state.subscription!;
    return Scaffold(
      body: Backdrop(
        child: SafeArea(
          child: Center(
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
                        children: [
                          _TopBar(state: state),
                          if (state.update != null) ...[
                            _UpdateBanner(state: state),
                            const SizedBox(height: 12),
                          ],
                          _PlanCard(sub: sub),
                          if (sub.announce != null) ...[
                            const SizedBox(height: 12),
                            GlassCard(
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.campaign_outlined,
                                    color: GX.accent,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(sub.announce!, style: body(14)),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),
                          ConnectButton(
                            state: state.vpnState,
                            onTap: state.toggle,
                          ),
                          const SizedBox(height: 8),
                          _StatusLine(state: state),
                          const SizedBox(height: 24),
                          if (state.error != null) ...[
                            _ErrorCard(state: state),
                            const SizedBox(height: 12),
                          ],
                          _ServerTile(state: state),
                          const SizedBox(height: 12),
                          const _LinksRow(),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Image.asset('assets/images/mark.png', height: 26),
          const SizedBox(width: 10),
          Text('GateX', style: display(18)),
          const Spacer(),
          if (state.refreshing)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: GX.accent,
                ),
              ),
            ),
          IconButton(
            tooltip: 'Настройки',
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => showSettingsSheet(context, state),
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
    final until = expire == null
        ? 'Без ограничения по сроку'
        : sub.isExpired
        ? 'Подписка закончилась'
        : 'До ${_date(expire)} · осталось ${_days(days!)}';
    return GlassCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sub.title ?? 'Подписка GateX',
                  style: body(16, weight: 700),
                ),
                const SizedBox(height: 4),
                Text(
                  until,
                  style: body(
                    13,
                    color: soon || sub.isExpired ? GX.warn : GX.muted,
                  ),
                ),
                if (sub.total > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Трафик: ${_gb(sub.upload + sub.download)} из ${_gb(sub.total)}',
                    style: body(13, color: GX.muted),
                  ),
                ],
              ],
            ),
          ),
          if (soon || sub.isExpired)
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              onPressed: () => openLink(Links.cabinet),
              child: const Text('Продлить'),
            ),
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

class _StatusLine extends StatefulWidget {
  const _StatusLine({required this.state});
  final AppState state;

  @override
  State<_StatusLine> createState() => _StatusLineState();
}

class _StatusLineState extends State<_StatusLine> {
  DateTime? _since;
  Timer? _tick;

  @override
  void didUpdateWidget(_StatusLine old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void initState() {
    super.initState();
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
    final (text, color) = switch (widget.state.vpnState) {
      VpnState.connected => ('Подключено', GX.accent),
      VpnState.connecting => ('Подключаемся…', GX.text),
      VpnState.disconnecting => ('Отключаемся…', GX.text),
      VpnState.disconnected => ('Не подключено', GX.muted),
    };
    final since = _since;
    String? elapsed;
    if (since != null) {
      final d = DateTime.now().difference(since);
      String two(int n) => n.toString().padLeft(2, '0');
      elapsed =
          '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
    }
    return Column(
      children: [
        Text(text, style: display(18, color: color)),
        const SizedBox(height: 4),
        Text(
          elapsed ?? 'Нажмите, чтобы подключиться',
          style: body(
            13,
            color: GX.muted,
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
          s == null
              ? Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: Color(0x242EE6A6),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.bolt_rounded, color: GX.accent),
                )
              : FlagBadge(flag: s.flag),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s?.title ?? 'Авто', style: body(16, weight: 700)),
                Text(
                  s == null
                      ? 'Самый быстрый из ${_servers(state.servers.length)}'
                      : 'Выбран вручную',
                  style: body(13, color: GX.muted),
                ),
              ],
            ),
          ),
          if (s != null)
            DelayChip(
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
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
      decoration: BoxDecoration(
        color: GX.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(GX.radius),
        border: Border.all(color: GX.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Expanded(child: Text(state.error!, style: body(14))),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: state.clearError,
          ),
        ],
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
            Icon(icon, color: GX.accent),
            const SizedBox(height: 6),
            Text(label, style: body(13, weight: 600)),
          ],
        ),
      ),
    );
    return Row(
      children: [
        item(Icons.person_outline_rounded, 'Кабинет', Links.cabinet),
        const SizedBox(width: 12),
        item(Icons.support_agent_rounded, 'Поддержка', Links.support),
        const SizedBox(width: 12),
        item(Icons.language_rounded, 'Сайт', Links.site),
      ],
    );
  }
}

String _servers(int n) =>
    n % 10 == 1 && n % 100 != 11 ? '$n сервера' : '$n серверов';
