import 'package:flutter/material.dart';

/// One of the app's colour themes. Green matches gatexx.ru; black is for
/// OLED screens; white is the light one.
class Palette {
  const Palette({
    required this.id,
    required this.name,
    required this.brightness,
    required this.bg,
    required this.bg2,
    required this.text,
    required this.muted,
    required this.accent,
    required this.accent2,
    required this.accentInk,
    required this.glass,
    required this.glassStrong,
    required this.line,
    required this.glow,
    required this.buttonOff,
    required this.mark,
  });

  final String id;
  final String name;
  final Brightness brightness;
  final Color bg, bg2, text, muted, accent, accent2, accentInk;
  final Color glass, glassStrong, line;

  /// Colours of the background's moving light.
  final List<Color> glow;

  /// The connect button's two gradient stops while off.
  final List<Color> buttonOff;

  /// The GX logo asset that reads on this background.
  final String mark;

  bool get light => brightness == Brightness.light;
}

const palettes = [
  Palette(
    id: 'green',
    name: 'Зелёная',
    brightness: Brightness.dark,
    bg: Color(0xFF06110E),
    bg2: Color(0xFF0A1B16),
    text: Color(0xFFEAF5F0),
    muted: Color(0xFF8EA89F),
    accent: Color(0xFF2EE6A6),
    accent2: Color(0xFF18B98A),
    accentInk: Color(0xFF03241A),
    glass: Color(0x0EFFFFFF),
    glassStrong: Color(0x17FFFFFF),
    line: Color(0x1FFFFFFF),
    glow: [Color(0xFF2EE6A6), Color(0xFF18B9C9), Color(0xFF18B98A)],
    buttonOff: [Color(0xFF13302A), Color(0xFF0B1E19)],
    mark: 'assets/images/mark.png',
  ),
  Palette(
    id: 'black',
    name: 'Чёрная',
    brightness: Brightness.dark,
    bg: Color(0xFF000000),
    bg2: Color(0xFF0B0D0C),
    text: Color(0xFFF2F4F3),
    muted: Color(0xFF8A918E),
    accent: Color(0xFF2EE6A6),
    accent2: Color(0xFF18B98A),
    accentInk: Color(0xFF03241A),
    glass: Color(0x0DFFFFFF),
    glassStrong: Color(0x17FFFFFF),
    line: Color(0x1AFFFFFF),
    glow: [Color(0xFF1C6B55), Color(0xFF203A50), Color(0xFF16503F)],
    buttonOff: [Color(0xFF161A19), Color(0xFF0A0C0B)],
    mark: 'assets/images/mark.png',
  ),
  Palette(
    id: 'white',
    name: 'Белая',
    brightness: Brightness.light,
    bg: Color(0xFFF3F7F5),
    bg2: Color(0xFFFFFFFF),
    text: Color(0xFF0D1F19),
    muted: Color(0xFF5F746C),
    accent: Color(0xFF0FB884),
    accent2: Color(0xFF0A9A6E),
    accentInk: Color(0xFFFFFFFF),
    glass: Color(0xB3FFFFFF),
    glassStrong: Color(0x14000000),
    line: Color(0x1A0D1F19),
    glow: [Color(0xFF7FF0C8), Color(0xFF9ED9F2), Color(0xFFB5F5DC)],
    buttonOff: [Color(0xFFFFFFFF), Color(0xFFE6F0EC)],
    mark: 'assets/images/mark_dark.png',
  ),
];

/// The active palette's colours. Screens read these on every build, so a
/// theme change only needs a rebuild (see GateXApp).
abstract final class GX {
  static Palette p = palettes.first;

  static Color get bg => p.bg;
  static Color get bg2 => p.bg2;
  static Color get text => p.text;
  static Color get muted => p.muted;
  static Color get accent => p.accent;
  static Color get accent2 => p.accent2;
  static Color get accentInk => p.accentInk;
  static Color get glass => p.glass;
  static Color get glassStrong => p.glassStrong;
  static Color get line => p.line;
  static Color get warn =>
      p.light ? const Color(0xFFD98A00) : const Color(0xFFFFB547);
  static Color get danger =>
      p.light ? const Color(0xFFE03E3E) : const Color(0xFFFF6B6B);
  static String get mark => p.mark;

  static const radius = 20.0;

  static void use(String id) =>
      p = palettes.firstWhere((x) => x.id == id, orElse: () => palettes.first);
}

/// Manrope and Unbounded ship as variable fonts, so weight goes through
/// the wght axis.
TextStyle body(double size, {double weight = 500, Color? color}) => TextStyle(
  fontFamily: 'Manrope',
  fontSize: size,
  color: color ?? GX.text,
  fontVariations: [FontVariation.weight(weight)],
  fontWeight: _nearest(weight),
  height: 1.3,
);

TextStyle display(double size, {double weight = 600, Color? color}) =>
    TextStyle(
      fontFamily: 'Unbounded',
      fontSize: size,
      color: color ?? GX.text,
      fontVariations: [FontVariation.weight(weight)],
      fontWeight: _nearest(weight),
      height: 1.15,
    );

TextStyle mono(double size, {Color? color}) => TextStyle(
  fontFamily: 'Consolas',
  fontFamilyFallback: const ['Cascadia Mono', 'DejaVu Sans Mono', 'monospace'],
  fontSize: size,
  color: color ?? GX.text,
  height: 1.45,
);

FontWeight _nearest(double w) =>
    FontWeight.values[((w / 100).round() - 1).clamp(0, 8)];

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: GX.accent,
    brightness: GX.p.brightness,
    primary: GX.accent,
    onPrimary: GX.accentInk,
    surface: GX.bg2,
  );
  return ThemeData(
    colorScheme: scheme,
    // The animated background sits behind every screen (see main.dart).
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: GX.bg2,
    fontFamily: 'Manrope',
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {
        for (final p in TargetPlatform.values) p: const _SlideFadeTransitions(),
      },
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? GX.accentInk : GX.muted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? GX.accent : GX.glassStrong,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? GX.accent : GX.line,
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: GX.bg2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: GX.line),
      ),
      textStyle: body(12),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: GX.bg2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GX.radius),
        side: BorderSide(color: GX.line),
      ),
    ),
    textTheme: TextTheme(
      bodyMedium: body(15),
      bodyLarge: body(16),
      titleMedium: body(16, weight: 700),
      titleLarge: display(20),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: display(18),
      foregroundColor: GX.text,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: GX.accent,
        foregroundColor: GX.accentInk,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: body(16, weight: 700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: GX.text,
        side: BorderSide(color: GX.line),
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: body(15, weight: 600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: GX.glass,
      hintStyle: body(15, color: GX.muted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: GX.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: GX.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: GX.accent),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: GX.bg2,
      contentTextStyle: body(14),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

/// A frosted card like the ones on the site.
class GlassCard extends StatefulWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.highlight = false,
  });
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final bool highlight;

  @override
  State<GlassCard> createState() => _GlassCardState();
}

/// Tappable cards lift a little and light their edge under the mouse.
class _GlassCardState extends State<GlassCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final hl = widget.highlight;
    final hover = _hover && widget.onTap != null;
    final border = hl
        ? GX.accent
        : hover
        ? GX.accent.withValues(alpha: 0.45)
        : GX.line;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, hover ? -1.5 : 0, 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(GX.radius),
          boxShadow: [
            if (hover || hl)
              BoxShadow(
                color: GX.accent.withValues(alpha: hl ? 0.14 : 0.10),
                blurRadius: 22,
                offset: const Offset(0, 6),
              ),
          ],
        ),
        child: Material(
          color: hl
              ? GX.accent.withValues(alpha: 0.14)
              : hover
              ? Color.alphaBlend(GX.accent.withValues(alpha: 0.04), GX.glass)
              : GX.glass,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(GX.radius),
            side: BorderSide(color: border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            splashColor: GX.accent.withValues(alpha: 0.12),
            highlightColor: GX.accent.withValues(alpha: 0.06),
            child: Padding(padding: widget.padding, child: widget.child),
          ),
        ),
      ),
    );
  }
}

/// Screens share one background, so a new page slides in a little and the
/// old one fades out instead of the pages overlapping.
class _SlideFadeTransitions extends PageTransitionsBuilder {
  const _SlideFadeTransitions();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final enter = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final leave = CurvedAnimation(
      parent: secondaryAnimation,
      curve: const Interval(0, 0.6, curve: Curves.easeOut),
    );
    return FadeTransition(
      opacity: ReverseAnimation(leave),
      child: FadeTransition(
        opacity: enter,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0.06, 0),
            end: Offset.zero,
          ).animate(enter),
          child: child,
        ),
      ),
    );
  }
}
