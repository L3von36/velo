import 'package:flutter/material.dart';

/// ─────────────────────────────────────────────────────────────────────────
/// VELO DESIGN SYSTEM — "Emerald Pro"
/// Material 3, hand-tuned tonal palettes, bundled Inter + Noto Sans Ethiopic.
/// Kept visually light per PRD §4 (no blur/shader effects, low-end friendly).
/// ─────────────────────────────────────────────────────────────────────────
class AppTheme {
  AppTheme._();

  // ── Brand constants ────────────────────────────────────────────────────
  static const seed = Color(0xFF0E7A3D); // Ethiopian deep green
  static const gold = Color(0xFFE8A200); // accent gold
  static const fontFamily = 'Inter';
  static const ethiopicFamily = 'Noto Sans Ethiopic';
  static const fontFamilyFallback = [ethiopicFamily];

  // Semantic colors shared across screens.
  static const success = Color(0xFF16803C);
  static const successSoft = Color(0xFFDCFCE7);
  static const warning = Color(0xFFB45309);
  static const warningSoft = Color(0xFFFEF3C7);
  static const danger = Color(0xFFB3261E);
  static const dangerSoft = Color(0xFFFEE2E2);
  static const info = Color(0xFF1D4ED8);
  static const infoSoft = Color(0xFFDBEAFE);

  // Brand gradients (solid, GPU-cheap — no shaders).
  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0B5D30), Color(0xFF0E7A3D), Color(0xFF149A4E)],
  );
  static const authGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF0A4D28), Color(0xFF0E7A3D)],
  );

  // Corner-radius tokens.
  static const rSm = 10.0;
  static const rMd = 14.0;
  static const rLg = 20.0;
  static const rXl = 28.0;

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    // Hand-tuned M3 scheme — emerald primary, warm-gold tertiary,
    // slightly green-tinted neutrals so surfaces feel "branded", not gray.
    final scheme = ColorScheme(
      brightness: brightness,
      primary: isDark ? const Color(0xFF7EDCA4) : const Color(0xFF006D3C),
      onPrimary: isDark ? const Color(0xFF00391C) : Colors.white,
      primaryContainer: isDark ? const Color(0xFF00522A) : const Color(0xFF9BF6B8),
      onPrimaryContainer: isDark ? const Color(0xFF9BF6B8) : const Color(0xFF00210E),
      secondary: isDark ? const Color(0xFFB3CCBC) : const Color(0xFF4C6358),
      onSecondary: isDark ? const Color(0xFF1F352B) : Colors.white,
      secondaryContainer: isDark ? const Color(0xFF354B41) : const Color(0xFFCEE9D8),
      onSecondaryContainer: isDark ? const Color(0xFFCEE9D8) : const Color(0xFF082016),
      tertiary: isDark ? const Color(0xFFF5BE48) : const Color(0xFF7A5900),
      onTertiary: isDark ? const Color(0xFF3F2E00) : Colors.white,
      tertiaryContainer: isDark ? const Color(0xFF5B4300) : const Color(0xFFFFDF9E),
      onTertiaryContainer: isDark ? const Color(0xFFFFDF9E) : const Color(0xFF261A00),
      error: isDark ? const Color(0xFFFFB4AB) : const Color(0xFFB3261E),
      onError: isDark ? const Color(0xFF690005) : Colors.white,
      errorContainer: isDark ? const Color(0xFF93000A) : const Color(0xFFF9DEDC),
      onErrorContainer: isDark ? const Color(0xFFFFDAD6) : const Color(0xFF410E0B),
      surface: isDark ? const Color(0xFF101511) : const Color(0xFFF7FAF6),
      onSurface: isDark ? const Color(0xFFDDE4DD) : const Color(0xFF171D19),
      surfaceContainerLowest: isDark ? const Color(0xFF0B0F0C) : Colors.white,
      surfaceContainerLow: isDark ? const Color(0xFF181D19) : const Color(0xFFF1F5F0),
      surfaceContainer: isDark ? const Color(0xFF1C211D) : const Color(0xFFEBEFE9),
      surfaceContainerHigh: isDark ? const Color(0xFF262B27) : const Color(0xFFE5E9E3),
      surfaceContainerHighest: isDark ? const Color(0xFF313631) : const Color(0xFFDFE4DD),
      onSurfaceVariant: isDark ? const Color(0xFFBFC9BF) : const Color(0xFF414942),
      outline: isDark ? const Color(0xFF89938A) : const Color(0xFF71796F),
      outlineVariant: isDark ? const Color(0xFF3F473F) : const Color(0xFFC1C9BD),
      inverseSurface: isDark ? const Color(0xFFDDE4DD) : const Color(0xFF2C322D),
      onInverseSurface: isDark ? const Color(0xFF2C322D) : const Color(0xFFF0F2EC),
      inversePrimary: isDark ? const Color(0xFF006D3C) : const Color(0xFF7EDCA4),
      shadow: Colors.black,
      scrim: Colors.black,
      surfaceTint: isDark ? const Color(0xFF7EDCA4) : const Color(0xFF006D3C),
    );

    // ── Typography — Inter for Latin, Noto Sans Ethiopic for አማርኛ. ──────
    TextTheme textTheme(Brightness b) {
      final onSurface = b == Brightness.dark
          ? const Color(0xFFDDE4DD)
          : const Color(0xFF171D19);
      final onVar = b == Brightness.dark
          ? const Color(0xFFBFC9BF)
          : const Color(0xFF414942);
      // Instagram-compact scale: body ~13.5, titles ~17, labels tight.
      return TextTheme(
        displaySmall: TextStyle(
            fontSize: 29,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.9,
            color: onSurface,
            fontFamily: fontFamily,
            fontFamilyFallback: fontFamilyFallback),
        headlineMedium: TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: onSurface,
            fontFamily: fontFamily,
            fontFamilyFallback: fontFamilyFallback),
        headlineSmall: TextStyle(
            fontSize: 19.5,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            color: onSurface,
            fontFamily: fontFamily,
            fontFamilyFallback: fontFamilyFallback),
        titleLarge: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.25,
            color: onSurface,
            fontFamily: fontFamily,
            fontFamilyFallback: fontFamilyFallback),
        titleMedium: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
            color: onSurface,
            fontFamily: fontFamily,
            fontFamilyFallback: fontFamilyFallback),
        titleSmall: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: onSurface,
            fontFamily: fontFamily,
            fontFamilyFallback: fontFamilyFallback),
        bodyLarge: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w400,
            letterSpacing: 0.1,
            color: onSurface,
            fontFamily: fontFamily,
            fontFamilyFallback: fontFamilyFallback),
        bodyMedium: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w400,
            letterSpacing: 0.1,
            color: onSurface,
            fontFamily: fontFamily,
            fontFamilyFallback: fontFamilyFallback),
        bodySmall: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            letterSpacing: 0.15,
            color: onVar,
            fontFamily: fontFamily,
            fontFamilyFallback: fontFamilyFallback),
        labelLarge: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
            color: onSurface,
            fontFamily: fontFamily,
            fontFamilyFallback: fontFamilyFallback),
        labelMedium: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.25,
            color: onVar,
            fontFamily: fontFamily,
            fontFamilyFallback: fontFamilyFallback),
        labelSmall: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.35,
            color: onVar,
            fontFamily: fontFamily,
            fontFamilyFallback: fontFamilyFallback),
      );
    }

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
      textTheme: textTheme(brightness),
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: ZoomPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: ZoomPageTransitionsBuilder(),
        TargetPlatform.macOS: ZoomPageTransitionsBuilder(),
        TargetPlatform.linux: ZoomPageTransitionsBuilder(),
      }),
    );

    return base.copyWith(
      // ── AppBar ──────────────────────────────────────────────────────────
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        titleTextStyle: base.textTheme.titleLarge,
        toolbarHeight: 56,
        shape: Border(
          bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.45)),
        ),
      ),

      // ── Cards — soft elevation + hairline, the "premium" signature. ────
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLowest,
        shadowColor: scheme.shadow.withValues(alpha: 0.10),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rMd),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.55)),
        ),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
      ),

      // ── Buttons ─────────────────────────────────────────────────────────
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(rSm + 2)),
          textStyle: base.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700, fontFamilyFallback: fontFamilyFallback),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(rSm + 2)),
          side: BorderSide(color: scheme.outlineVariant),
          foregroundColor: scheme.onSurface,
          textStyle: base.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600, fontFamilyFallback: fontFamilyFallback),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 40),
          textStyle: base.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600, fontFamilyFallback: fontFamilyFallback),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          visualDensity: VisualDensity.comfortable,
        ),
      ),

      // ── Inputs — filled, generous, glowing focus. ───────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? scheme.surfaceContainerLow
            : scheme.surfaceContainerLowest,
        hintStyle: base.textTheme.bodyMedium
            ?.copyWith(color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
        labelStyle: base.textTheme.bodyMedium
            ?.copyWith(color: scheme.onSurfaceVariant),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rSm + 2),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rSm + 2),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rSm + 2),
          borderSide: BorderSide(color: scheme.primary, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rSm + 2),
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rSm + 2),
          borderSide: BorderSide(color: scheme.error, width: 1.8),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      ),

      // ── Chips ───────────────────────────────────────────────────────────
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        backgroundColor: scheme.surfaceContainerLowest,
        selectedColor: scheme.primaryContainer,
        showCheckmark: false,
        side: BorderSide(color: scheme.outlineVariant),
        labelStyle: base.textTheme.labelMedium
            ?.copyWith(fontFamilyFallback: fontFamilyFallback),
        secondaryLabelStyle: base.textTheme.labelMedium
            ?.copyWith(fontFamilyFallback: fontFamilyFallback),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),

      // ── Navigation ──────────────────────────────────────────────────────
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        elevation: 0,
        backgroundColor: isDark
            ? scheme.surfaceContainerLow
            : scheme.surfaceContainerLowest,
        indicatorColor: scheme.primaryContainer,
        surfaceTintColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        indicatorShape: const StadiumBorder(),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              size: 24,
              color: states.contains(WidgetState.selected)
                  ? scheme.onPrimaryContainer
                  : scheme.onSurfaceVariant,
            )),
        labelTextStyle: WidgetStateProperty.resolveWith((states) =>
            base.textTheme.labelSmall!.copyWith(
                fontFamilyFallback: fontFamilyFallback,
                fontWeight: states.contains(WidgetState.selected)
                    ? FontWeight.w700
                    : FontWeight.w500,
                color: states.contains(WidgetState.selected)
                    ? scheme.onSurface
                    : scheme.onSurfaceVariant)),
      ),
      navigationRailTheme: NavigationRailThemeData(
        elevation: 0,
        backgroundColor: isDark
            ? scheme.surfaceContainerLow
            : scheme.surfaceContainerLowest,
        indicatorColor: scheme.primaryContainer,
        selectedIconTheme: IconThemeData(color: scheme.onPrimaryContainer),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        selectedLabelTextStyle: base.textTheme.labelMedium!.copyWith(
            color: scheme.onSurface,
            fontWeight: FontWeight.w700,
            fontFamilyFallback: fontFamilyFallback),
        unselectedLabelTextStyle: base.textTheme.labelMedium!
            .copyWith(color: scheme.onSurfaceVariant, fontFamilyFallback: fontFamilyFallback),
        useIndicator: true,
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: Colors.transparent,
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        indicatorColor: scheme.primary,
        indicatorSize: TabBarIndicatorSize.tab,
        labelStyle: base.textTheme.labelLarge
            ?.copyWith(fontWeight: FontWeight.w700, fontFamilyFallback: fontFamilyFallback),
        unselectedLabelStyle: base.textTheme.labelLarge
            ?.copyWith(fontWeight: FontWeight.w500, fontFamilyFallback: fontFamilyFallback),
      ),

      // ── Containers: dialogs, sheets, menus ─────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: isDark
            ? scheme.surfaceContainerLow
            : scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rLg)),
        titleTextStyle: base.textTheme.titleLarge,
        contentTextStyle: base.textTheme.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark
            ? scheme.surfaceContainerLow
            : scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: isDark
            ? scheme.surfaceContainerLow
            : scheme.surfaceContainerLowest,
        showDragHandle: true,
        dragHandleColor: scheme.outlineVariant,
        dragHandleSize: const Size(40, 4),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(rXl)),
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(isDark
              ? scheme.surfaceContainerLow
              : scheme.surfaceContainerLowest),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(3),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(rSm))),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(isDark
              ? scheme.surfaceContainerLow
              : scheme.surfaceContainerLowest),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(rSm))),
        ),
      ),

      // ── Small parts ─────────────────────────────────────────────────────
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rMd + 2)),
        highlightElevation: 4,
        extendedPadding: const EdgeInsets.symmetric(horizontal: 20),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: base.textTheme.bodyMedium
            ?.copyWith(color: scheme.onInverseSurface, fontFamilyFallback: fontFamilyFallback),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rSm)),
        elevation: 3,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
        circularTrackColor: scheme.surfaceContainerHighest,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: base.textTheme.labelSmall
            ?.copyWith(color: scheme.onInverseSurface, fontFamilyFallback: fontFamilyFallback),
        waitDuration: const Duration(milliseconds: 400),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.6),
        thickness: 1,
        space: 1,
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rSm)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        titleTextStyle: base.textTheme.bodyLarge
            ?.copyWith(fontWeight: FontWeight.w600, fontFamilyFallback: fontFamilyFallback),
        subtitleTextStyle: base.textTheme.bodySmall?.copyWith(fontFamilyFallback: fontFamilyFallback),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? null : scheme.outline),
        trackOutlineColor:
            const WidgetStatePropertyAll(Colors.transparent),
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: scheme.error,
        textStyle: base.textTheme.labelSmall
            ?.copyWith(color: scheme.onError, fontSize: 10, fontFamilyFallback: fontFamilyFallback),
      ),
      scrollbarTheme: ScrollbarThemeData(
        radius: const Radius.circular(8),
        thickness: WidgetStatePropertyAll(isDark ? 6.0 : 5.0),
      ),
      extensions: <ThemeExtension<dynamic>>[
        VeloShadows(
          card: BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.05),
            blurRadius: 14,
            offset: const Offset(0, 3),
          ),
          raised: BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.38 : 0.09),
            blurRadius: 22,
            offset: const Offset(0, 6),
          ),
        ),
      ],
    );
  }
}

/// Brand shadow tokens, accessible via `Theme.of(context).extension<VeloShadows>()`.
class VeloShadows extends ThemeExtension<VeloShadows> {
  const VeloShadows({required this.card, required this.raised});
  final BoxShadow card;
  final BoxShadow raised;

  @override
  VeloShadows copyWith({BoxShadow? card, BoxShadow? raised}) =>
      VeloShadows(card: card ?? this.card, raised: raised ?? this.raised);

  @override
  VeloShadows lerp(VeloShadows? other, double t) {
    if (other == null) return this;
    return VeloShadows(
      card: BoxShadow.lerp(card, other.card, t)!,
      raised: BoxShadow.lerp(raised, other.raised, t)!,
    );
  }
}
