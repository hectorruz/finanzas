import 'package:isar_community/isar.dart';

import 'enums.dart';

part 'app_settings.g.dart';

/// Registro único (id fijo) con la configuración global de la app.
@Collection(accessor: 'settings')
class AppSettings {
  /// Id fijo: siempre hay como mucho un registro de ajustes.
  Id id = 0;

  /// 'system' | 'light' | 'dark' (nombre de [ThemeMode]).
  String themeMode = 'system';

  /// Sincronizar color con el sistema (Material You).
  bool dynamicColor = true;

  /// Tema oscuro AMOLED (negro puro).
  bool amoled = true;

  /// Color semilla de respaldo (ARGB) cuando no hay color dinámico.
  int seedColorValue = 0xFF2196F3;

  /// Módulos activos, almacenados por nombre de [AppModule].
  List<String> enabledModules = [AppModule.goals.name];

  /// Tarjetas del dashboard, en orden, por nombre de [DashboardCardType].
  List<String> dashboardCards = [
    DashboardCardType.totalBalance.name,
    DashboardCardType.quickAdd.name,
    DashboardCardType.monthComparison.name,
    DashboardCardType.accountsBalance.name,
    DashboardCardType.recentMovements.name,
    DashboardCardType.scanReceipt.name,
  ];

  /// Ids de cuentas que cuentan para el balance total. Vacío = todas las que
  /// tengan `includeInTotal`.
  List<int> totalBalanceAccountIds = [];

  // --- Bloqueo de la app ---

  /// Si está activo, la app pide la credencial del dispositivo (huella, rostro
  /// o el PIN/patrón/contraseña del teléfono) al abrirse y al volver de fondo.
  bool appLockEnabled = false;

  AppSettings();

  // --- Acceso tipado seguro (directiva de calidad #2) ---

  @ignore
  bool get goalsEnabled => enabledModules.contains(AppModule.goals.name);

  /// Lista de tarjetas parseada de forma segura (descarta nombres desconocidos).
  @ignore
  List<DashboardCardType> get cards {
    final result = <DashboardCardType>[];
    for (final name in dashboardCards) {
      for (final c in DashboardCardType.values) {
        if (c.name == name) {
          result.add(c);
          break;
        }
      }
    }
    return result;
  }
}
