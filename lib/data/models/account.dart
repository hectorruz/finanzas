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

  Account();

  /// ¿Es una subcuenta (cuelga de otra)?
  @ignore
  bool get isSubaccount => parentId != null;
}
