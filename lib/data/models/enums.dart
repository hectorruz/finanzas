/// Enumeraciones compartidas por los modelos de datos.
///
/// IMPORTANTE: en Isar se persisten **por nombre** (`@Enumerated(EnumType.name)`),
/// nunca por índice, para no corromper la base de datos si se reordenan o se
/// añaden valores en el futuro. El parseo seguro desde texto se hace con
/// [enumByName], que aplica un fallback en lugar de lanzar excepción.

enum AccountType { bank, cash, investment }

enum TransactionType { income, expense, transfer }

enum CategoryKind { income, expense }

enum RecurringFrequency { daily, weekly, monthly, yearly }

enum AppModule { goals }

/// Secciones disponibles en la barra inferior de navegación.
enum NavSection { dashboard, movements, receipts, goals, settings }

/// Cada cuánto se sube una copia de seguridad a la nube.
///
/// No hay valor `quarterly` a propósito: "trimestral" es `monthly` con
/// `AppSettings.backupEvery == 3`, igual que [RecurringFrequency] se combina con
/// `RecurringRule.interval`. Dos representaciones del mismo periodo
/// (`quarterly×1` y `monthly×3`) obligarían a normalizar en cada comparación.
enum BackupFrequency { daily, weekly, monthly }

/// Dónde se suben las copias de seguridad.
enum BackupProvider { nextcloud, googleDrive }

/// Tarjetas disponibles en el dashboard configurable.
enum DashboardCardType {
  totalBalance,
  accountsBalance,
  monthComparison,
  recentMovements,
  quickAdd,
  scanReceipt,
  goals,
}

/// Parseo seguro de un enum por su nombre, con valor de [fallback] si el nombre
/// almacenado ya no existe (compatibilidad hacia adelante).
T enumByName<T extends Enum>(List<T> values, String? name, T fallback) {
  if (name == null) return fallback;
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}
