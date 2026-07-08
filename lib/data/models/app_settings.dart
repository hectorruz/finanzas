import 'dart:convert';

import 'package:isar_community/isar.dart';

import 'enums.dart';

part 'app_settings.g.dart';

/// Un subtotal configurable del balance: un nombre y las cuentas/subcuentas
/// cuyos saldos suma. Se guarda serializado en [AppSettings.balanceSubtotals].
class BalanceSubtotal {
  const BalanceSubtotal({required this.name, required this.accountIds});

  final String name;
  final List<int> accountIds;

  String encode() => jsonEncode({'name': name, 'ids': accountIds});

  /// Decodifica una entrada; devuelve `null` si el JSON es inválido.
  static BalanceSubtotal? tryDecode(String raw) {
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return BalanceSubtotal(
        name: m['name'] as String? ?? '',
        accountIds:
            (m['ids'] as List<dynamic>? ?? const []).map((e) => e as int).toList(),
      );
    } catch (_) {
      return null;
    }
  }
}

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

  /// Ids de cuentas que se muestran en la tarjeta "Balance por cuentas".
  /// Vacío = se muestran todas las cuentas activas.
  List<int> accountsCardIds = [];

  /// Subtotales que aparecen bajo el balance total, cada uno serializado en
  /// JSON (nombre + ids de cuentas a sumar). Ver [subtotals].
  List<String> balanceSubtotals = [];

  // --- Barra inferior ---

  /// Mostrar siempre los títulos de la barra inferior (no solo el seleccionado).
  bool alwaysShowNavLabels = false;

  /// Ocultar los importes económicos en toda la app (modo privacidad).
  bool hideAmounts = false;

  /// Secciones visibles de la barra inferior, en orden, por nombre de
  /// [NavSection]. Ajustes se garantiza siempre presente (ver [sections]).
  List<String> navSections = [
    NavSection.dashboard.name,
    NavSection.movements.name,
    NavSection.receipts.name,
    NavSection.settings.name,
  ];

  // --- Bloqueo de la app ---

  /// Si está activo, la app pide la credencial del dispositivo (huella, rostro
  /// o el PIN/patrón/contraseña del teléfono) al abrirse y al volver de fondo.
  bool appLockEnabled = false;

  // --- Informe ---

  /// Configuración del generador de informes serializada en JSON (secciones,
  /// orden, filtros, gráficos). Ver `ReportConfig` en `report_service.dart`.
  /// El rango de fechas no se guarda aquí (es puntual en cada informe).
  String reportConfig = '';

  // --- Sincronización ---

  /// Identidad estable de **este** dispositivo para el sync (uuid generado una
  /// vez). No se sincroniza ni se incluye en el backup (identifica al aparato).
  String syncDeviceId = '';

  /// Si este dispositivo actúa como admin (árbitro) del sync. Es solo un toggle
  /// ("Hacer de este dispositivo el principal"): ambos guardan la BD completa.
  bool syncIsAdmin = false;

  /// Nombre legible de este dispositivo, mostrado al par al emparejar/sincronizar.
  String syncDeviceName = '';

  // --- Migraciones ---

  /// Versión del esquema de datos ya aplicada en esta BD. La usa el migrador
  /// (`MigrationService`) para hacer un backfill idempotente de los campos de
  /// sincronización (uuid/updatedAt) una sola vez. No se sincroniza (es local).
  int dataVersion = 0;

  AppSettings();

  // --- Acceso tipado seguro (directiva de calidad #2) ---

  /// El módulo de objetivos está siempre disponible: se muestra u oculta
  /// añadiéndolo o quitándolo de la barra inferior (no hay interruptor propio).
  @ignore
  bool get goalsEnabled => true;

  /// Subtotales del balance parseados de forma segura (descarta entradas
  /// corruptas). Para escribir, codifica con [BalanceSubtotal.encode].
  @ignore
  List<BalanceSubtotal> get subtotals {
    final result = <BalanceSubtotal>[];
    for (final raw in balanceSubtotals) {
      final s = BalanceSubtotal.tryDecode(raw);
      if (s != null) result.add(s);
    }
    return result;
  }

  /// Secciones de la barra inferior parseadas de forma segura. Garantiza que
  /// Ajustes esté siempre presente (y al final), para no perder el acceso.
  @ignore
  List<NavSection> get sections {
    final result = <NavSection>[];
    for (final name in navSections) {
      final s = enumByName(NavSection.values, name, NavSection.settings);
      if (s != NavSection.settings && !result.contains(s)) result.add(s);
    }
    result.add(NavSection.settings);
    return result;
  }

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
