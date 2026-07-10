// Tests de la configuración de módulos (AppSettings).
//
// AppSettings es un objeto Dart puro (los getters de módulos no dependen de una
// instancia de Isar abierta), así que se puede probar sin inicializar la BD.

import 'package:flutter_test/flutter_test.dart';

import 'package:finanzas/data/models/app_settings.dart';
import 'package:finanzas/data/models/enums.dart';

void main() {
  group('AppSettings módulos', () {
    // El módulo de objetivos está SIEMPRE disponible (se muestra u oculta
    // añadiéndolo o quitándolo de la barra inferior, no con un interruptor
    // propio): `goalsEnabled` es true con independencia de `enabledModules`.
    test('por defecto: Objetivos activo', () {
      expect(AppSettings().goalsEnabled, isTrue);
    });

    test('Objetivos sigue activo aunque enabledModules esté vacío', () {
      final settings = AppSettings()..enabledModules = [];
      expect(settings.goalsEnabled, isTrue);
    });

    test('Objetivos activo con el módulo presente', () {
      final settings = AppSettings()..enabledModules = [AppModule.goals.name];
      expect(settings.goalsEnabled, isTrue);
    });
  });
}
