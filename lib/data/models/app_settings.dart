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

/// Configuración de un destino de copias en la nube. Se guarda serializada en
/// [AppSettings.backupProviderConfigs], **una entrada por proveedor**: así se
/// pueden tener Nextcloud y Drive configurados a la vez y alternar entre ellos
/// sin volver a teclear las credenciales.
///
/// Los campos que no usa un proveedor quedan vacíos (mismo pragmatismo que
/// `NotificationRule` con sus regex opcionales).
class BackupProviderConfig {
  const BackupProviderConfig({
    required this.provider,
    this.baseUrl = '',
    this.user = '',
    this.password = '',
    this.folder = 'Finanzas',
    this.account = '',
    this.folderId = '',
  });

  final BackupProvider provider;

  /// Nextcloud: URL de la instancia (p. ej. `https://cloud.example.com`).
  final String baseUrl;

  /// Nextcloud: usuario.
  final String user;

  /// Nextcloud: **contraseña de aplicación** (Ajustes → Seguridad en Nextcloud),
  /// no la contraseña de la cuenta.
  final String password;

  /// Carpeta donde se dejan las copias, en ambos proveedores.
  final String folder;

  /// Drive: correo de la cuenta conectada. Solo para mostrarlo en la UI; el
  /// token lo gestiona `google_sign_in` en su propio almacén.
  final String account;

  /// Drive: id de la carpeta creada por la app, cacheado para no buscarla en
  /// cada copia. Vacío = aún no se conoce (se busca o se crea).
  final String folderId;

  BackupProviderConfig copyWith({
    String? baseUrl,
    String? user,
    String? password,
    String? folder,
    String? account,
    String? folderId,
  }) =>
      BackupProviderConfig(
        provider: provider,
        baseUrl: baseUrl ?? this.baseUrl,
        user: user ?? this.user,
        password: password ?? this.password,
        folder: folder ?? this.folder,
        account: account ?? this.account,
        folderId: folderId ?? this.folderId,
      );

  String encode() => jsonEncode({
        'provider': provider.name,
        'baseUrl': baseUrl,
        'user': user,
        'password': password,
        'folder': folder,
        'account': account,
        'folderId': folderId,
      });

  /// Decodifica una entrada; devuelve `null` si el JSON es inválido.
  static BackupProviderConfig? tryDecode(String raw) {
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return BackupProviderConfig(
        provider: enumByName(
          BackupProvider.values,
          m['provider'] as String?,
          BackupProvider.nextcloud,
        ),
        baseUrl: m['baseUrl'] as String? ?? '',
        user: m['user'] as String? ?? '',
        password: m['password'] as String? ?? '',
        folder: m['folder'] as String? ?? 'Finanzas',
        account: m['account'] as String? ?? '',
        folderId: m['folderId'] as String? ?? '',
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

  /// Privacidad estilo banca: oculta el contenido en la vista de tareas/recientes
  /// (`FLAG_SECURE`, que además bloquea las capturas de pantalla) y muestra un
  /// overlay difuminado al pasar a segundo plano. `null` = **activado** por
  /// defecto: un `bool` no-nullable nuevo se rellenaría con `false` en la fila de
  /// ajustes ya existente (hermano del sello `Int.MIN` de los int), y queremos que
  /// salga activado también en instalaciones previas. Leer con `?? true`.
  bool? secureScreenEnabled;

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

  // --- Lectura de notificaciones de pago (Google Wallet + apps personalizadas).
  //     Local: no se sincroniza ni se respalda (es permiso/preferencia de este
  //     dispositivo) ---

  /// Si se leen las notificaciones de pago para crear el gasto automáticamente.
  bool paymentReaderEnabled = false;

  /// Cuenta a la que se imputan los gastos detectados por defecto. `0` = primera
  /// cuenta activa. Una regla tarjeta → cuenta que case tiene prioridad.
  int paymentDefaultAccountId = 0;

  /// Huellas de las notificaciones ya procesadas (importe|comercio|día), para no
  /// crear dos veces el mismo gasto si una notificación se reentrega. Se poda a
  /// las últimas ~300.
  List<String> paymentProcessedHashes = [];

  /// Reglas de lectura de apps **extra** (además de Google Wallet, que es una
  /// regla built-in implícita), cada una serializada en JSON. Ver
  /// `NotificationRule`. Los paquetes de origen del servicio nativo se derivan
  /// de aquí (+ el de Wallet).
  List<String> notificationAppRules = [];

  /// Reglas tarjeta → cuenta, cada una serializada en JSON (`{card, accountId}`).
  /// Ver `CardAccountRule`.
  List<String> cardAccountRules = [];

  // --- Copias de seguridad en la nube.
  //     Local: no se sincroniza ni se respalda (son credenciales y preferencias
  //     de este dispositivo; además, meter el estado de las copias dentro de las
  //     propias copias no tendría sentido) ---

  /// Si se suben copias automáticas a la nube.
  bool backupEnabled = false;

  /// Proveedor activo, por nombre de [BackupProvider].
  String backupProvider = 'nextcloud';

  /// Cada cuánto se copia, por nombre de [BackupFrequency]. Combinado con
  /// [backupEvery]: trimestral = `monthly` + `backupEvery = 3`.
  String backupFrequency = 'weekly';

  /// Multiplicador de [backupFrequency] ("cada N"). Mínimo 1.
  int backupEvery = 1;

  /// Hora preferida de la copia (24h, hora local). Es orientativa: la copia se
  /// hace en el primer arranque/reanudación posterior a la hora, no a la hora
  /// exacta (ver `BackupSchedulerService`).
  int backupHour = 3;
  int backupMinute = 0;

  /// Ancla de la serie de ocurrencias. Todas las fechas se calculan **desde
  /// aquí**, nunca desde la última copia: anclar en la última copia haría que el
  /// recorte de fin de mes (31 → 28) se realimentara y el día se adelantara para
  /// siempre. `null` = aún no programado.
  DateTime? backupAnchorAt;

  /// Última copia **con éxito**. Es lo que decide si toca copia.
  DateTime? backupLastRunAt;

  /// Último **intento**, con éxito o sin él. Solo lo usa el backoff: sin esto,
  /// un fallo persistente (contraseña cambiada) reintentaría en cada
  /// reanudación, para siempre.
  DateTime? backupLastAttemptAt;

  /// Resultado legible del último intento, para mostrarlo en Ajustes.
  String backupLastResult = '';

  /// Fallos consecutivos. Alimenta el backoff exponencial y decide cuándo avisar.
  int backupConsecutiveFailures = 0;

  /// Cuántas copias se conservan en la nube; las más antiguas se borran. Ojo:
  /// esto es un número de copias, no de días — con frecuencia diaria, 10 copias
  /// son 10 días de historial (la UI lo traduce con `retentionHorizon`).
  int backupKeepLast = 10;

  /// Copiar solo con Wi-Fi. Por defecto `true`: subir varios MB por datos
  /// móviles sin avisar sería hostil.
  bool backupWifiOnly = true;

  /// Configuración de cada destino, serializada. Ver [BackupProviderConfig].
  List<String> backupProviderConfigs = [];

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

  /// Frecuencia de copia parseada de forma segura.
  @ignore
  BackupFrequency get backupFrequencyEnum => enumByName(
        BackupFrequency.values,
        backupFrequency,
        BackupFrequency.weekly,
      );

  /// Proveedor de copias activo, parseado de forma segura.
  @ignore
  BackupProvider get backupProviderEnum => enumByName(
        BackupProvider.values,
        backupProvider,
        BackupProvider.nextcloud,
      );

  /// Configuración de todos los destinos, parseada de forma segura (descarta
  /// entradas corruptas). Para escribir, codifica con
  /// [BackupProviderConfig.encode].
  @ignore
  List<BackupProviderConfig> get backupConfigs {
    final result = <BackupProviderConfig>[];
    for (final raw in backupProviderConfigs) {
      final c = BackupProviderConfig.tryDecode(raw);
      if (c != null) result.add(c);
    }
    return result;
  }

  /// Configuración de [provider], o una vacía si aún no se ha configurado.
  @ignore
  BackupProviderConfig configFor(BackupProvider provider) {
    for (final c in backupConfigs) {
      if (c.provider == provider) return c;
    }
    return BackupProviderConfig(provider: provider);
  }

  /// Configuración del destino activo.
  @ignore
  BackupProviderConfig get activeBackupConfig => configFor(backupProviderEnum);

  /// Devuelve las entradas serializadas con [config] insertada o reemplazando la
  /// del mismo proveedor. Para usar dentro de `SettingsRepository.update`.
  List<String> withBackupConfig(BackupProviderConfig config) {
    final result = <String>[];
    for (final c in backupConfigs) {
      if (c.provider != config.provider) result.add(c.encode());
    }
    result.add(config.encode());
    return result;
  }
}
