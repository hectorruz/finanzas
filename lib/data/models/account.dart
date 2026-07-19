import 'package:isar_community/isar.dart';

import '../../core/sync/syncable.dart';
import 'enums.dart';

part 'account.g.dart';

/// Una cuenta del usuario (banco, efectivo o contenedor de inversiones).
///
/// El saldo se calcula a partir de [initialBalanceCents] más los movimientos
/// asociados; aquí solo se guarda el saldo inicial.
@Collection(accessor: 'accounts')
class Account implements Syncable {
  Id id = Isar.autoIncrement;

  /// Metadatos de sincronización (ver [Syncable]).
  @override
  @Index()
  String uuid = '';
  @override
  DateTime updatedAt = DateTime.fromMillisecondsSinceEpoch(0);
  @override
  DateTime? deletedAt;

  late String name;

  /// Tipo de cuenta. Se persiste por nombre para tolerar cambios en el enum.
  @Enumerated(EnumType.name)
  AccountType type = AccountType.bank;

  /// Saldo inicial en céntimos.
  int initialBalanceCents = 0;

  String currency = 'EUR';

  /// Nombre del icono de Material (ver [iconData] en la capa de presentación).
  String iconName = 'account_balance';

  /// Color asociado (valor ARGB de [Color.value]).
  int colorValue = 0xFF2196F3;

  /// Observaciones libres de la cuenta (igual que la nota de un movimiento).
  String note = '';

  /// Si está archivada no se muestra en listados activos pero se conserva.
  bool archived = false;

  /// Si suma en el cálculo del balance total del dashboard.
  bool includeInTotal = true;

  /// Id de la cuenta padre si es una subcuenta; `null` si es de primer nivel.
  /// El anidamiento es ilimitado (una subcuenta puede tener subcuentas).
  int? parentId;

  /// Orden de aparición en listados.
  int sortOrder = 0;

  /// Banco/cuenta donde está suscrito el depósito o la Letra del Tesoro, cuando
  /// **no** es subcuenta (si lo es, el banco es su [parentId]). El interés neto
  /// (depósito) o la ganancia (letra) se suman al saldo de esa cuenta. `null` =
  /// sin asociar. Solo relevante para depósitos y letras.
  int? bankAccountId;

  // --- Depósito a plazo (solo relevante si [type] == AccountType.deposit) ---

  /// TAE en puntos básicos (1 % = 100 bps; 3,75 % = 375). Entero para no perder
  /// precisión con dobles. `null` = sin definir.
  int? depositRateBps;

  /// Fecha de apertura del depósito.
  DateTime? depositStartDate;

  /// Fecha de vencimiento del depósito.
  DateTime? depositEndDate;

  /// Cómo se liquidan los intereses. Se persiste por nombre.
  @Enumerated(EnumType.name)
  DepositPayout depositPayout = DepositPayout.atMaturity;

  /// Si el depósito se renueva automáticamente al vencer.
  bool depositAutoRenew = false;

  // --- Letra del Tesoro (solo relevante si [type] == AccountType.treasuryBill) ---
  // Las letras van a descuento: se reutiliza [initialBalanceCents] como precio de
  // compra, [depositStartDate] como fecha de compra y [depositEndDate] como
  // vencimiento.

  /// Importe nominal a cobrar al vencimiento (en céntimos). La ganancia bruta es
  /// `nominalCents - initialBalanceCents`. `null` = sin definir.
  int? nominalCents;

  Account();

  /// ¿Es una subcuenta (cuelga de otra)?
  @ignore
  bool get isSubaccount => parentId != null;

  /// Banco efectivo donde está el depósito/letra: si es subcuenta, su padre; si
  /// no, el [bankAccountId] elegido a mano. `null` si no hay ninguno.
  @ignore
  int? get holdingBankId => isSubaccount ? parentId : bankAccountId;
}
