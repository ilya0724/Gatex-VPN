import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Color, Size;

import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../core/vpn_core.dart';
import '../state/app_state.dart';

/// Window, tray and autostart on Windows and Linux.
///
/// The window has no system frame (the app draws its own title bar), the
/// close button hides it to the tray while the VPN keeps running, and a
/// second launch only brings this window back (see windows/runner).
class DesktopShell with WindowListener, TrayListener {
  DesktopShell._();
  static final instance = DesktopShell._();

  static bool get supported => Platform.isWindows || Platform.isLinux;

  /// Started by the system at logon: stay in the tray.
  static bool startedHidden(List<String> args) => args.contains('--hidden');

  static const _minSize = Size(380, 640);
  static const _defaultSize = Size(460, 820);

  AppState? _state;
  late SharedPreferences _prefs;
  bool _quitting = false;
  Timer? _saveBounds;

  Future<void> init(List<String> args) async {
    try {
      await _init(args);
    } on Object {
      // Never leave the user with an invisible window.
      await windowManager.show();
    }
  }

  Future<void> _init(List<String> args) async {
    await windowManager.ensureInitialized();
    _prefs = await SharedPreferences.getInstance();
    final w = _prefs.getDouble('win.w'), h = _prefs.getDouble('win.h');
    final options = WindowOptions(
      size: w != null && h != null
          ? Size(w.clamp(_minSize.width, 1600), h.clamp(_minSize.height, 1400))
          : _defaultSize,
      minimumSize: _minSize,
      center: true,
      title: 'GateX VPN',
      titleBarStyle: TitleBarStyle.hidden,
      backgroundColor: const Color(0xFF06110E),
    );
    final hidden = startedHidden(args);
    await windowManager.waitUntilReadyToShow(options, () async {
      if (!hidden) {
        await windowManager.show();
        await windowManager.focus();
      }
    });
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);
  }

  /// Hooks the tray to the app state. Called once the state is ready.
  Future<void> attach(AppState state) async {
    _state = state;
    trayManager.addListener(this);
    state.addListener(_syncTray);
    await _syncTray();
    // After an update to another folder the task would point at the old
    // exe; re-create it then, and leave it alone otherwise.
    if (state.settings.launchAtStartup &&
        _prefs.getString('autostart.exe') != Platform.resolvedExecutable) {
      await syncAutostart(true);
    }
  }

  VpnState? _trayState;
  String? _trayServer;

  Future<void> _syncTray() async {
    final s = _state!;
    final server = s.selectedServer?.title ?? 'Авто';
    if (_trayState == s.vpnState && _trayServer == server) return;
    _trayState = s.vpnState;
    _trayServer = server;
    final on = s.connected;
    try {
      await trayManager.setIcon(
        Platform.isWindows
            ? 'assets/tray/${on ? 'tray_on' : 'tray_off'}.ico'
            : 'assets/tray/${on ? 'tray_on' : 'tray_off'}.png',
      );
      final status = switch (s.vpnState) {
        VpnState.connected => 'Подключено · $server',
        VpnState.connecting => 'Подключаемся…',
        VpnState.disconnecting => 'Отключаемся…',
        VpnState.disconnected => 'Не подключено',
      };
      if (!Platform.isLinux) await trayManager.setToolTip('GateX VPN\n$status');
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: 'status', label: status, disabled: true),
            MenuItem.separator(),
            MenuItem(
              key: 'toggle',
              label: on ? 'Отключить' : 'Подключить',
              disabled: s.busy || !s.hasSubscription,
            ),
            MenuItem(key: 'show', label: 'Открыть GateX'),
            MenuItem.separator(),
            MenuItem(key: 'quit', label: 'Выйти'),
          ],
        ),
      );
    } on Object {
      // No tray on this desktop (some Linux sessions); the window still works.
    }
  }

  Future<void> show() async {
    await windowManager.show();
    if (await windowManager.isMinimized()) await windowManager.restore();
    await windowManager.focus();
  }

  Future<void> hide() => windowManager.hide();

  Future<void> minimize() => windowManager.minimize();

  /// The close button: to the tray, or quit when the user turned that off.
  Future<void> close() async {
    final s = _state;
    if (s != null && s.settings.closeToTray && !_quitting) {
      await hide();
    } else {
      await quit();
    }
  }

  Future<void> quit() async {
    _quitting = true;
    final s = _state;
    if (s != null && (s.connected || s.busy)) await s.core.stop();
    await trayManager.destroy();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  /// A second copy of the app was started (the runner forwards its
  /// command line here): show this window and take a gatex:// link.
  Future<void> onActivate(String commandLine) async {
    final link = RegExp(r'gatex://\S+').firstMatch(commandLine)?.group(0);
    if (link != null) {
      await _state?.handleLink(link.replaceAll('"', ''));
    }
    if (!commandLine.contains('--hidden')) await show();
  }

  @override
  void onWindowClose() => unawaited(close());

  @override
  void onWindowResized() {
    _saveBounds?.cancel();
    _saveBounds = Timer(const Duration(milliseconds: 600), () async {
      final size = await windowManager.getSize();
      await _prefs.setDouble('win.w', size.width);
      await _prefs.setDouble('win.h', size.height);
    });
  }

  @override
  void onTrayIconMouseDown() => unawaited(show());

  @override
  void onTrayIconRightMouseDown() => unawaited(trayManager.popUpContextMenu());

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'toggle':
        unawaited(_state?.toggle());
      case 'show':
        unawaited(show());
      case 'quit':
        unawaited(quit());
    }
  }

  // Autostart. Windows: a Task Scheduler task at logon with highest rights,
  // so the elevated app starts without a UAC prompt. Linux: XDG autostart.

  static const _taskName = 'GateX VPN';

  Future<String?> syncAutostart(bool enabled) async {
    try {
      String? error;
      if (Platform.isWindows) error = await _windowsAutostart(enabled);
      if (Platform.isLinux) await _linuxAutostart(enabled);
      if (error == null) {
        await _prefs.setString(
          'autostart.exe',
          enabled ? Platform.resolvedExecutable : '',
        );
      }
      return error;
    } on Object catch (e) {
      return '$e';
    }
  }

  Future<String?> _windowsAutostart(bool enabled) async {
    if (!enabled) {
      final q = await Process.run('schtasks', ['/Query', '/TN', _taskName]);
      if (q.exitCode != 0) return null;
      final r = await Process.run('schtasks', [
        '/Delete',
        '/TN',
        _taskName,
        '/F',
      ]);
      return r.exitCode == 0 ? null : '${r.stderr}${r.stdout}'.trim();
    }
    final env = Platform.environment;
    final user = '${env['USERDOMAIN'] ?? '.'}\\${env['USERNAME'] ?? ''}';
    String esc(String s) => const HtmlEscape().convert(s);
    final xml =
        '''
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo><Description>Запуск GateX VPN при входе в Windows</Description></RegistrationInfo>
  <Triggers>
    <LogonTrigger><Enabled>true</Enabled><UserId>${esc(user)}</UserId><Delay>PT5S</Delay></LogonTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>${esc(user)}</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <Priority>5</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>${esc(Platform.resolvedExecutable)}</Command>
      <Arguments>--hidden</Arguments>
    </Exec>
  </Actions>
</Task>
''';
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}gatex-task.xml',
    );
    // Task Scheduler wants UTF-16 LE with a BOM.
    final bytes = <int>[0xFF, 0xFE];
    for (final unit in xml.trimLeft().codeUnits) {
      bytes
        ..add(unit & 0xFF)
        ..add(unit >> 8);
    }
    await file.writeAsBytes(bytes);
    try {
      final r = await Process.run('schtasks', [
        '/Create',
        '/TN',
        _taskName,
        '/XML',
        file.path,
        '/F',
      ]);
      return r.exitCode == 0 ? null : '${r.stderr}${r.stdout}'.trim();
    } finally {
      if (file.existsSync()) file.deleteSync();
    }
  }

  Future<void> _linuxAutostart(bool enabled) async {
    final home = Platform.environment['HOME'];
    if (home == null) return;
    final config = Platform.environment['XDG_CONFIG_HOME'] ?? '$home/.config';
    final file = File('$config/autostart/gatex.desktop');
    if (!enabled) {
      if (file.existsSync()) file.deleteSync();
      return;
    }
    await file.parent.create(recursive: true);
    await file.writeAsString('''
[Desktop Entry]
Type=Application
Name=GateX VPN
Exec="${Platform.resolvedExecutable}" --hidden
Icon=gatex
X-GNOME-Autostart-enabled=true
''');
  }
}
