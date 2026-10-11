import 'package:flutter/material.dart';

enum ReaderTheme {
  light(
    'Light',
    'Clean paper and deep ink',
    Color(0xfffaf9f6),
    Color(0xff222b30),
    Color(0xff285c47),
    Brightness.light,
  ),
  dark(
    'Dark',
    'Soft charcoal for everyday reading',
    Color(0xff202427),
    Color(0xffe4e8e5),
    Color(0xffa6d5bc),
    Brightness.dark,
  ),
  solarized(
    'Solarized Dark',
    'Deep teal with warm text',
    Color(0xff002b36),
    Color(0xffc0cec9),
    Color(0xffedca79),
    Brightness.dark,
  ),
  kawaii(
    'Kawaii',
    'White pages and a touch of pink',
    Color(0xfffffbfd),
    Color(0xff492a3b),
    Color(0xff922756),
    Brightness.light,
  );

  const ReaderTheme(
    this.label,
    this.description,
    this.background,
    this.ink,
    this.accent,
    this.brightness,
  );
  final String label;
  final String description;
  final Color background;
  final Color ink;
  final Color accent;
  final Brightness brightness;

  ThemeData get data {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: accent,
          brightness: brightness,
        ).copyWith(
          surface: background,
          onSurface: ink,
          onSurfaceVariant: ink,
          primary: accent,
          onPrimary: background,
        );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      textTheme: ThemeData(brightness: brightness).textTheme
          .apply(bodyColor: ink, displayColor: ink),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: ink,
        elevation: 0,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(64, 52)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(minimumSize: const Size(64, 52)),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
    );
  }
}
