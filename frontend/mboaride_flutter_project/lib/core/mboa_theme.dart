import 'package:flutter/material.dart';

/// Couleurs de la charte graphique MboaRide (docs/design), version douce : le vert de la
/// marque reste, les fonds sont sable et blanc, les traits et les textes secondaires sont
/// plus légers, le rouge et le jaune sont moins vifs.
class MboaColors {
  static const Color green = Color(0xFF0B6E4F);
  static const Color greenDeep = Color(0xFF085A40);
  static const Color greenSoft = Color(0xFFE4F2EC);
  static const Color sun = Color(0xFFF2B705);
  static const Color sunSoft = Color(0xFFFCF3D9);
  static const Color sunText = Color(0xFF7A5A00);
  static const Color night = Color(0xFF1D2A24);
  static const Color sand = Color(0xFFF6F4EF);
  static const Color surface = Colors.white;
  static const Color red = Color(0xFFC2483B);
  static const Color redSoft = Color(0xFFFBE7E4);
  static const Color redText = Color(0xFFA13A2E);
  static const Color neutralSoft = Color(0xFFF0EEE8);
  static const Color mutedText = Color(0xFF5E6B65);
  static const Color border = Color(0xFFDCE2DE);
  static const Color line = Color(0xFFEAE7E0);
  static const Color shadow = Color(0x141D2A24);
}

/// Formes et ombres communes : cartes arrondies posées sur le sable, ombre très légère.
class MboaDecor {
  static const double radius = 20;
  static const List<BoxShadow> softShadow = [
    BoxShadow(color: MboaColors.shadow, blurRadius: 18, offset: Offset(0, 6)),
    BoxShadow(color: Color(0x0A1D2A24), blurRadius: 2, offset: Offset(0, 1)),
  ];

  static BoxDecoration card({Color color = MboaColors.surface, double radius = radius}) => BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(radius),
    boxShadow: softShadow,
  );

  /// Bandeau vert de la marque, en dégradé léger.
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF13845F), MboaColors.green, MboaColors.greenDeep],
  );
}

/// Transition entre les écrans : fondu et léger glissement vers le haut, plus doux que le
/// zoom par défaut d'Android.
class SoftPageTransitionsBuilder extends PageTransitionsBuilder {
  const SoftPageTransitionsBuilder();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 320);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 260);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final entree = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    final sortie = CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0.6).animate(sortie),
      child: FadeTransition(
        opacity: entree,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.035), end: Offset.zero).animate(entree),
          child: child,
        ),
      ),
    );
  }
}

ThemeData buildMboaTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: MboaColors.green).copyWith(
    primary: MboaColors.green,
    onPrimary: Colors.white,
    primaryContainer: MboaColors.greenSoft,
    onPrimaryContainer: MboaColors.greenDeep,
    secondary: MboaColors.sun,
    onSecondary: MboaColors.night,
    secondaryContainer: MboaColors.sunSoft,
    onSecondaryContainer: MboaColors.sunText,
    error: MboaColors.red,
    errorContainer: MboaColors.redSoft,
    surface: MboaColors.sand,
    onSurface: MboaColors.night,
    onSurfaceVariant: MboaColors.mutedText,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: Colors.white,
    surfaceContainer: const Color(0xFFFBFAF7),
    surfaceContainerHigh: const Color(0xFFF2F0EA),
    outline: MboaColors.border,
    outlineVariant: MboaColors.line,
    shadow: MboaColors.shadow,
  );
  final champ = OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: const BorderSide(color: MboaColors.border),
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  final texte = base.textTheme.apply(bodyColor: MboaColors.night, displayColor: MboaColors.night);
  const pilule = StadiumBorder();
  const transitions = SoftPageTransitionsBuilder();

  return base.copyWith(
    scaffoldBackgroundColor: MboaColors.sand,
    textTheme: texte.copyWith(
      headlineSmall: texte.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
      titleLarge: texte.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
      titleMedium: texte.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      bodyMedium: texte.bodyMedium?.copyWith(height: 1.4),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: transitions,
        TargetPlatform.iOS: transitions,
        TargetPlatform.windows: transitions,
        TargetPlatform.linux: transitions,
        TargetPlatform.macOS: transitions,
      },
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: MboaColors.sand,
      foregroundColor: MboaColors.night,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0.6,
      shadowColor: MboaColors.shadow,
      centerTitle: false,
      iconTheme: IconThemeData(color: MboaColors.night),
      actionsIconTheme: IconThemeData(color: MboaColors.night),
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: MboaColors.night,
      ),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 1.5,
      shadowColor: MboaColors.shadow,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MboaDecor.radius)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: champ,
      enabledBorder: champ,
      focusedBorder: champ.copyWith(borderSide: const BorderSide(color: MboaColors.green, width: 1.6)),
      errorBorder: champ.copyWith(borderSide: const BorderSide(color: MboaColors.red)),
      focusedErrorBorder: champ.copyWith(borderSide: const BorderSide(color: MboaColors.red, width: 1.6)),
      labelStyle: const TextStyle(color: MboaColors.mutedText),
      floatingLabelStyle: const TextStyle(color: MboaColors.green, fontWeight: FontWeight.w600),
      hintStyle: const TextStyle(color: Color(0xFF8E9A94)),
      prefixIconColor: MboaColors.mutedText,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: pilule,
        elevation: 0,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        shape: pilule,
        elevation: 0,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: pilule,
        foregroundColor: MboaColors.green,
        side: const BorderSide(color: MboaColors.border),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: pilule, textStyle: const TextStyle(fontWeight: FontWeight.w600)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: MboaColors.green,
      foregroundColor: Colors.white,
      elevation: 2,
      highlightElevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      extendedTextStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: pilule,
      side: const BorderSide(color: MboaColors.border),
      backgroundColor: Colors.white,
      selectedColor: MboaColors.greenSoft,
      checkmarkColor: MboaColors.green,
      labelStyle: const TextStyle(color: MboaColors.night, fontWeight: FontWeight.w500),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: MboaColors.greenSoft,
        selectedForegroundColor: MboaColors.greenDeep,
        side: const BorderSide(color: MboaColors.border),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: MboaColors.night,
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14.5),
      actionTextColor: const Color(0xFF9FE3C6),
      elevation: 0,
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      titleTextStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: MboaColors.night),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: MboaColors.border,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 68,
      indicatorColor: MboaColors.greenSoft,
      shadowColor: MboaColors.shadow,
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
        color: s.contains(WidgetState.selected) ? MboaColors.green : MboaColors.mutedText,
      )),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
        fontSize: 12.5,
        fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
        color: s.contains(WidgetState.selected) ? MboaColors.green : MboaColors.mutedText,
      )),
    ),
    drawerTheme: const DrawerThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.horizontal(right: Radius.circular(28))),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: MboaColors.green,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : null),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? MboaColors.green : null),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.transparent : MboaColors.border,
      ),
    ),
    dividerTheme: const DividerThemeData(color: MboaColors.line, thickness: 1, space: 1),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: MboaColors.green,
      linearTrackColor: MboaColors.greenSoft,
      circularTrackColor: Colors.transparent,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: MboaColors.night, borderRadius: BorderRadius.circular(10)),
      textStyle: const TextStyle(color: Colors.white, fontSize: 13),
    ),
  );
}
