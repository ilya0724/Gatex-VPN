import 'package:flutter/material.dart';

/// Colours from gatexx.ru, so the app, the site and the bot look the same.
abstract final class GX {
  static const bg = Color(0xFF06110E);
  static const bg2 = Color(0xFF0A1B16);
  static const text = Color(0xFFEAF5F0);
  static const muted = Color(0xFF8EA89F);
  static const accent = Color(0xFF2EE6A6);
  static const accent2 = Color(0xFF18B98A);
  static const accentInk = Color(0xFF03241A);
  static const glass = Color(0x0EFFFFFF);
  static const glassStrong = Color(0x17FFFFFF);
  static const line = Color(0x1FFFFFFF);
  static const warn = Color(0xFFFFB547);
  static const danger = Color(0xFFFF6B6B);

  static const radius = 20.0;
}

/// Manrope and Unbounded ship as variable fonts, so weight goes through
/// the wght axis.
TextStyle body(double size, {double weight = 500, Color color = GX.text}) =>
    TextStyle(
      fontFamily: 'Manrope',
      fontSize: size,
      color: color,
      fontVariations: [FontVariation.weight(weight)],
      fontWeight: _nearest(weight),
      height: 1.3,
    );

TextStyle display(double size, {double weight = 600, Color color = GX.text}) =>
    TextStyle(
      fontFamily: 'Unbounded',
      fontSize: size,
      color: color,
      fontVariations: [FontVariation.weight(weight)],
      fontWeight: _nearest(weight),
      height: 1.15,
    );

TextStyle mono(double size, {Color color = GX.text}) => TextStyle(
  fontFamily: 'Consolas',
  fontFamilyFallback: const ['Cascadia Mono', 'DejaVu Sans Mono', 'monospace'],
  fontSize: size,
  color: color,
  height: 1.45,
);

FontWeight _nearest(double w) =>
    FontWeight.values[((w / 100).round() - 1).clamp(0, 8)];

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: GX.accent,
    brightness: Brightness.dark,
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
        side: const BorderSide(color: GX.line),
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
        side: const BorderSide(color: GX.line),
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
        borderSide: const BorderSide(color: GX.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: GX.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: GX.accent),
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
class GlassCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(GX.radius),
      side: BorderSide(color: highlight ? GX.accent : GX.line),
    );
    return Material(
      color: highlight ? const Color(0x242EE6A6) : GX.glass,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
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
