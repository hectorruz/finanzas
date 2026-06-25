import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

/// Construye los temas claro/oscuro de la app a partir de un [ColorScheme].
///
/// - [light]/[dark] provienen del color dinámico del sistema (Material You) si
///   está disponible; si no, se generan con `ColorScheme.fromSeed`.
/// - Cuando [amoled] está activo, el tema oscuro se lleva a negro puro
///   (#000000) en fondos y superficies para pantallas OLED.
class AppTheme {
  static ThemeData light(ColorScheme scheme) {
    return _base(scheme.harmonized());
  }

  static ThemeData dark(ColorScheme scheme, {bool amoled = false}) {
    var dark = scheme.harmonized();
    if (amoled) {
      dark = dark.copyWith(
        surface: Colors.black,
        surfaceContainerLowest: Colors.black,
        surfaceContainerLow: const Color(0xFF0A0A0A),
        surfaceContainer: const Color(0xFF111111),
        surfaceContainerHigh: const Color(0xFF161616),
        surfaceContainerHighest: const Color(0xFF1C1C1C),
      );
    }
    final theme = _base(dark);
    if (amoled) {
      return theme.copyWith(
        scaffoldBackgroundColor: Colors.black,
        canvasColor: Colors.black,
      );
    }
    return theme;
  }

  static ThemeData _base(ColorScheme scheme) {
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        elevation: 0,
        scrolledUnderElevation: 2,
        centerTitle: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        elevation: 3,
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        filled: true,
      ),
      listTileTheme: const ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
    );
  }
}
