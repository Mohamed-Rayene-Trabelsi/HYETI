import 'package:material_ui/material_ui.dart';

/// The app's own palette, available as `context.colors`.
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.text,
    required this.textDim,
    required this.accent,
    required this.onAccent,
    required this.danger,
    required this.success,
    required this.warn,
    required this.scrim,
  });

  final Color background, surface, surfaceAlt, border, text, textDim;
  final Color accent, onAccent, danger, success, warn, scrim;

  /// The full colour set for one palette in light or dark.
  factory AppColors.of(Palette palette, Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final t = dark ? palette.dark : palette.light;
    return AppColors(
      background: t.background,
      surface: t.surface,
      surfaceAlt: t.surfaceAlt,
      border: t.border,
      text: dark ? const Color(0xFFF2F3F5) : const Color(0xFF111318),
      textDim: dark ? const Color(0xFF9BA1AC) : const Color(0xFF626976),
      accent: t.accent,
      // Whichever of near-black and white reads better on the accent.
      onAccent: t.accent.computeLuminance() > 0.4 ? const Color(0xFF0C0D10) : const Color(0xFFFFFFFF),
      danger: dark ? const Color(0xFFFF6B6B) : const Color(0xFFD93D3D),
      success: dark ? const Color(0xFF3DD68C) : const Color(0xFF1E9E61),
      warn: dark ? const Color(0xFFF5B94A) : const Color(0xFFB97A0A),
      scrim: dark ? const Color(0x99000000) : const Color(0x730A0C10),
    );
  }

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(AppColors? other, double t) => t < 0.5 || other == null ? this : other;
}

extension AppColorsContext on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}

/* ---------- Palettes ---------- */

/// The colours a palette decides; everything else is shared.
class Tones {
  const Tones({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.accent,
  });

  final Color background, surface, surfaceAlt, border, accent;
}

/// A named colour theme with a light and a dark version.
class Palette {
  const Palette(this.id, this.name, {required this.light, required this.dark});

  final String id;
  final String name;
  final Tones light;
  final Tones dark;
}

const _neutralLight = Tones(
  background: Color(0xFFF6F7F9),
  surface: Color(0xFFFFFFFF),
  surfaceAlt: Color(0xFFEEF0F4),
  border: Color(0xFFE2E5EA),
  accent: Color(0xFF3D63F0),
);

const _neutralDark = Tones(
  background: Color(0xFF0C0D10),
  surface: Color(0xFF15171C),
  surfaceAlt: Color(0xFF1E2128),
  border: Color(0xFF262A33),
  accent: Color(0xFF6C8CFF),
);

/// The built-in themes, in the order Settings shows them.
const palettes = [
  Palette('indigo', 'Indigo', light: _neutralLight, dark: _neutralDark),
  // Red on deep blue.
  Palette(
    'spider',
    'Web Slinger',
    light: Tones(
      background: Color(0xFFF3F6FC),
      surface: Color(0xFFFFFFFF),
      surfaceAlt: Color(0xFFE6ECF8),
      border: Color(0xFFD5DEF0),
      accent: Color(0xFFD42A2A),
    ),
    dark: Tones(
      background: Color(0xFF080D1C),
      surface: Color(0xFF101830),
      surfaceAlt: Color(0xFF1A2444),
      border: Color(0xFF26325A),
      accent: Color(0xFFFF4B4B),
    ),
  ),
  // Yellow on black.
  Palette(
    'bat',
    'Dark Knight',
    light: Tones(
      background: Color(0xFFF4F4F1),
      surface: Color(0xFFFFFFFF),
      surfaceAlt: Color(0xFFE9E9E4),
      border: Color(0xFFD8D8D1),
      accent: Color(0xFF22242A),
    ),
    dark: Tones(
      background: Color(0xFF070809),
      surface: Color(0xFF111214),
      surfaceAlt: Color(0xFF1B1D20),
      border: Color(0xFF2A2C31),
      accent: Color(0xFFF5C518),
    ),
  ),
  // Crimson on pitch black.
  Palette(
    'clover',
    'Five-Leaf Clover',
    light: Tones(
      background: Color(0xFFF7F4F0),
      surface: Color(0xFFFFFFFF),
      surfaceAlt: Color(0xFFEDE8E1),
      border: Color(0xFFDDD6CC),
      accent: Color(0xFFAE1228),
    ),
    dark: Tones(
      background: Color(0xFF050505),
      surface: Color(0xFF111010),
      surfaceAlt: Color(0xFF1C1A1A),
      border: Color(0xFF2C2828),
      accent: Color(0xFFE5243B),
    ),
  ),
  Palette(
    'forest',
    'Forest',
    light: Tones(
      background: Color(0xFFF3F7F3),
      surface: Color(0xFFFFFFFF),
      surfaceAlt: Color(0xFFE6EEE7),
      border: Color(0xFFD5E0D7),
      accent: Color(0xFF1F8A4C),
    ),
    dark: Tones(
      background: Color(0xFF080E0B),
      surface: Color(0xFF101814),
      surfaceAlt: Color(0xFF19241E),
      border: Color(0xFF25332B),
      accent: Color(0xFF4ADE80),
    ),
  ),
  Palette(
    'sunset',
    'Sunset',
    light: Tones(
      background: Color(0xFFFBF5F1),
      surface: Color(0xFFFFFFFF),
      surfaceAlt: Color(0xFFF3E8E1),
      border: Color(0xFFE6D7CD),
      accent: Color(0xFFD9541E),
    ),
    dark: Tones(
      background: Color(0xFF120B10),
      surface: Color(0xFF1C1219),
      surfaceAlt: Color(0xFF291B25),
      border: Color(0xFF3A2734),
      accent: Color(0xFFFF8A4C),
    ),
  ),
  Palette(
    'sakura',
    'Sakura',
    light: Tones(
      background: Color(0xFFFCF5F7),
      surface: Color(0xFFFFFFFF),
      surfaceAlt: Color(0xFFF5E6EB),
      border: Color(0xFFE9D3DB),
      accent: Color(0xFFD23C77),
    ),
    dark: Tones(
      background: Color(0xFF110A0E),
      surface: Color(0xFF1B1117),
      surfaceAlt: Color(0xFF281A22),
      border: Color(0xFF39262F),
      accent: Color(0xFFFF7EB0),
    ),
  ),
];

/// Accent colours offered for the custom theme.
const accentSwatches = [
  Color(0xFF6C8CFF),
  Color(0xFF38BDF8),
  Color(0xFF2DD4BF),
  Color(0xFF4ADE80),
  Color(0xFFA3E635),
  Color(0xFFF5C518),
  Color(0xFFFF8A4C),
  Color(0xFFFF4B4B),
  Color(0xFFE5243B),
  Color(0xFFFF7EB0),
  Color(0xFFC084FC),
  Color(0xFF8B5CF6),
];

/// Backgrounds offered for the custom theme: value → label.
const customBases = {'neutral': 'Charcoal', 'navy': 'Midnight', 'black': 'Pitch black'};

/// A theme made from one accent colour and a background style.
Palette customPalette(Color accent, String base) {
  final dark = switch (base) {
    'navy' => const Tones(
      background: Color(0xFF080D1C),
      surface: Color(0xFF101830),
      surfaceAlt: Color(0xFF1A2444),
      border: Color(0xFF26325A),
      accent: Color(0xFF000000),
    ),
    'black' => const Tones(
      background: Color(0xFF000000),
      surface: Color(0xFF0E0E0F),
      surfaceAlt: Color(0xFF1A1A1C),
      border: Color(0xFF2A2A2D),
      accent: Color(0xFF000000),
    ),
    _ => _neutralDark,
  };
  // On white, a bright accent is deepened so text and buttons in it stay readable.
  final onLight = accent.computeLuminance() > 0.35 ? Color.lerp(accent, const Color(0xFF000000), 0.35)! : accent;
  // The light version takes a faint tint of the accent so it does not look like the default.
  Color tint(Color neutral, double amount) => Color.lerp(neutral, accent, amount)!;
  return Palette(
    'custom',
    'Custom',
    light: Tones(
      background: tint(_neutralLight.background, 0.04),
      surface: _neutralLight.surface,
      surfaceAlt: tint(_neutralLight.surfaceAlt, 0.06),
      border: tint(_neutralLight.border, 0.08),
      accent: onLight,
    ),
    dark: Tones(
      background: dark.background,
      surface: dark.surface,
      surfaceAlt: dark.surfaceAlt,
      border: dark.border,
      accent: accent,
    ),
  );
}

/// The palette for a saved choice; unknown ids fall back to the default.
Palette paletteFor(String id, {int? customAccent, String customBase = 'neutral'}) {
  if (id == 'custom') return customPalette(Color(customAccent ?? accentSwatches.first.toARGB32()), customBase);
  return palettes.firstWhere((p) => p.id == id, orElse: () => palettes.first);
}

ThemeData buildTheme(Brightness brightness, [Palette? palette]) {
  final c = AppColors.of(palette ?? palettes.first, brightness);
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: c.background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: c.accent,
      brightness: brightness,
    ).copyWith(primary: c.accent, onPrimary: c.onAccent, surface: c.surface, onSurface: c.text, error: c.danger),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c.accent,
      selectionColor: c.accent.withValues(alpha: 0.3),
      selectionHandleColor: c.accent,
    ),
    splashFactory: InkSparkle.splashFactory,
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.text,
      contentTextStyle: TextStyle(color: c.background, fontSize: 14),
      actionTextColor: c.background,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {TargetPlatform.android: FadeForwardsPageTransitionsBuilder()},
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: c.accent.withValues(alpha: 0.16),
      height: 64,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: states.contains(WidgetState.selected) ? c.accent : c.textDim,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(size: 22, color: states.contains(WidgetState.selected) ? c.accent : c.textDim),
      ),
    ),
    extensions: [c],
  );
}

/// Calendar block categories. The colour is the same in every theme.
class Category {
  const Category(this.key, this.label, this.color);
  final String key;
  final String label;
  final Color color;
}

const categories = [
  Category('gym', 'Gym', Color(0xFFFF7A59)),
  Category('food', 'Food break', Color(0xFF3DBE7F)),
  Category('work', 'Work', Color(0xFF6C8CFF)),
  Category('game', 'Gaming', Color(0xFFB57BFF)),
  Category('watch', 'Watch', Color(0xFFFF6FAE)),
  Category('other', 'Other', Color(0xFF8C93A0)),
];

Category categoryOf(String key) => categories.firstWhere((c) => c.key == key, orElse: () => categories.last);

abstract final class Spacing {
  static const double xs = 4, sm = 8, md = 12, lg = 16, xl = 24, xxl = 32;
}

abstract final class Radii {
  static const double sm = 8, md = 12, lg = 16, pill = 999;

  /// Every button, chip, toggle and input: a rectangle with slightly rounded corners.
  static const double button = 10;
}

const double maxContentWidth = 560;
