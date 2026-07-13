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
        accountIds: (m['ids'] as List<dynamic>? ?? const [])
            .map((e) => e as int)
            .toList(),
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

  /// Tarjetas del panel de la **webapp de escritorio**, en orden y solo las
  /// visibles (por clave, ver `kWebDashboardCatalog`). Es independiente de
  /// [dashboardCards] (que es el inicio del móvil): la web tiene más tipos de
  /// tarjeta. Vacío = layout por defecto de la web. Viaja por la API `/api/settings`
  /// pero el móvil no la usa para su propio inicio.
  List<String> webDashboardCards = [];

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

  // --- Ajustes del servidor (local: no se sincroniza ni se respalda) ---

  /// Puerto en el que escucha el servidor del admin. 0/ inválido → puerto por
  /// defecto (`SyncProtocol.defaultPort`, 8422).
  int syncPort = 8422;

  /// Si el emparejamiento exige el PIN de 6 dígitos. Si es `false`, cualquiera
  /// en la misma Wi-Fi puede emparejar sin código (solo en red de confianza).
  bool syncRequirePin = true;

  /// PIN de emparejamiento fijo (6 dígitos). Vacío = se genera uno aleatorio en
  /// cada arranque del servidor.
  String syncFixedPin = '';

  /// Mantener el servidor vivo en segundo plano con un servicio en primer plano
  /// (notificación persistente), para que siga respondiendo con la pantalla
  /// apagada o la app en segundo plano.
  bool syncKeepAliveInBackground = false;

  /// Arrancar el servidor automáticamente al abrir la app (si este dispositivo
  /// es el principal).
  bool syncAutoStartServer = false;

  /// El dispositivo vinculado intenta sincronizar solo (silencioso) al abrir o
  /// reanudar la app y al conectarse a una Wi-Fi. Si es `false`, solo sincroniza
  /// cuando la persona entra a propósito a la pantalla de sync.
  bool syncLinkedAutoSyncEnabled = true;

  /// Aviso local (recordatorio) para revisar la sincronización a una hora fija.
  /// Solo tiene efecto en el admin (es quien revisa). Local: no se sincroniza
  /// ni se incluye en el backup (es preferencia de este dispositivo).
  bool syncReminderEnabled = false;

  /// Hora/minuto del aviso (24h, hora local del dispositivo).
  int syncReminderHour = 20;
  int syncReminderMinute = 0;

  /// Días de la semana en que suena el aviso (`DateTime.monday`..`DateTime.sunday`,
  /// 1-7). Vacío = todos los días.
  List<int> syncReminderWeekdays = [];

  // --- Copias de seguridad automáticas (local: no se sincroniza ni se respalda) ---

  /// Si están activas las copias de seguridad automáticas programadas. Es una
  /// preferencia de **este** dispositivo (dónde y cada cuánto guarda su propia
  /// copia), por eso no se sincroniza ni se incluye en el backup.
  bool backupEnabled = false;

  /// Frecuencia de la copia, por nombre de [BackupFrequency].
  String backupFrequency = 'weekly';

  /// Destino de la copia, por nombre de [BackupDestination].
  String backupDestination = 'localFile';

  /// Hora/minuto preferidos para la copia (24h, hora local del dispositivo).
  int backupHour = 3;
  int backupMinute = 0;

  /// Momento de la última copia realizada con éxito. Lo usa el planificador
  /// (`backup_planner.dart`) para decidir si toca una copia nueva.
  DateTime? backupLastRunAt;

  /// Resultado/estado legible de la última copia (para mostrarlo en Ajustes).
  String backupLastResult = '';

  /// Cuántas copias conservar en el destino (rotación; borra las más antiguas).
  int backupKeepLast = 10;

  // --- Nextcloud (destino de copia; local: no se sincroniza ni se respalda) ---

  /// URL base del servidor Nextcloud (p. ej. `https://nube.ejemplo.com`).
  String nextcloudBaseUrl = '';

  /// Usuario de Nextcloud.
  String nextcloudUser = '';

  /// Contraseña de aplicación de Nextcloud (mejor una *app password*, no la
  /// principal). Local: nunca se sincroniza ni se exporta.
  String nextcloudPassword = '';

  /// Carpeta remota donde se suben las copias.
  String nextcloudFolder = 'Finanzas';

  // --- Google Drive (destino de copia; local) ---

  /// Email de la cuenta de Google conectada (solo para mostrar). El token lo
  /// gestiona/cachea `google_sign_in`; no se persiste aquí ni se exporta.
  String googleDriveAccountEmail = '';

  // --- Lectura de notificaciones de Google Wallet (local: no se sincroniza ni
  //     se respalda; es una preferencia/permiso de este dispositivo) ---

  /// Si se leen las notificaciones de pago de Google Wallet para crear el gasto
  /// automáticamente.
  bool walletReaderEnabled = false;

  /// Cuenta a la que se imputan los gastos detectados. `0` = primera cuenta
  /// activa (por defecto).
  int walletDefaultAccountId = 0;

  /// Paquetes de las apps cuyas notificaciones se leen (por defecto, Google
  /// Wallet). Se envían al servicio nativo como filtro de origen.
  List<String> walletSourcePackages = ['com.google.android.apps.walletnfcrel'];

  /// Huellas de las notificaciones ya procesadas (importe|comercio|día), para no
  /// crear dos veces el mismo gasto si una notificación se reentrega. Se poda a
  /// las últimas ~300.
  List<String> walletProcessedHashes = [];

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

  /// Frecuencia de copia parseada de forma segura (fallback semanal).
  @ignore
  BackupFrequency get backupFrequencyEnum => enumByName(
      BackupFrequency.values, backupFrequency, BackupFrequency.weekly);

  /// Destino de copia parseado de forma segura (fallback archivo local).
  @ignore
  BackupDestination get backupDestinationEnum => enumByName(
      BackupDestination.values, backupDestination, BackupDestination.localFile);

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
