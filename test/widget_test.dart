// Tests de la configuración de módulos (AppSettings).
//
// AppSettings es un objeto Dart puro (los getters de módulos no dependen de una
// instancia de Isar abierta), así que se puede probar sin inicializar la BD.

import 'package:flutter_test/flutter_test.dart';

import 'package:finanzas/data/models/app_settings.dart';
import 'package:finanzas/data/models/enums.dart';

void main() {
  group('AppSettings módulos', () {
    test('por defecto: Objetivos activo', () {
      final settings = AppSettings();
      expect(settings.goalsEnabled, isTrue);
    });

    test('desactivar Objetivos lo refleja en el getter', () {
      final settings = AppSettings()..enabledModules = [];
      expect(settings.goalsEnabled, isFalse);
    });

    test('activar Objetivos lo refleja en el getter', () {
      final settings = AppSettings()
        ..enabledModules = [AppModule.goals.name];
      expect(settings.goalsEnabled, isTrue);
    });
  });
}
