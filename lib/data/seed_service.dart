import 'package:isar_community/isar.dart';

import 'models/account.dart';
import 'models/category.dart';
import 'models/enums.dart';

/// Crea los datos por defecto la primera vez que se abre la app: cuentas
/// "Banco" y "Efectivo" y un conjunto de categorías editables.
class SeedService {
  SeedService(this._isar);
  final Isar _isar;

  Future<void> seedIfEmpty() async {
    final hasAccounts = await _isar.accounts.count() > 0;
    final hasCategories = await _isar.categories.count() > 0;

    await _isar.writeTxn(() async {
      if (!hasAccounts) {
        await _isar.accounts.putAll(_defaultAccounts());
      }
      if (!hasCategories) {
        await _isar.categories.putAll(_defaultCategories());
      }
    });
  }

  List<Account> _defaultAccounts() => [
        Account()
          ..name = 'Banco'
          ..type = AccountType.bank
          ..iconName = 'account_balance'
          ..colorValue = 0xFF1976D2
          ..includeInTotal = true
          ..sortOrder = 0,
        Account()
          ..name = 'Efectivo'
          ..type = AccountType.cash
          ..iconName = 'payments'
          ..colorValue = 0xFF388E3C
          ..includeInTotal = true
          ..sortOrder = 1,
      ];

  List<Category> _defaultCategories() {
    const expenses = <(String, String, int)>[
      ('Alimentación', 'restaurant', 0xFFEF5350),
      ('Transporte', 'directions_car', 0xFF42A5F5),
      ('Vivienda', 'home', 0xFF8D6E63),
      ('Ocio', 'sports_esports', 0xFFAB47BC),
      ('Salud', 'local_hospital', 0xFF26A69A),
      ('Compras', 'shopping_bag', 0xFFFF7043),
      ('Suscripciones', 'subscriptions', 0xFF5C6BC0),
      ('Otros gastos', 'more_horiz', 0xFF78909C),
    ];
    const incomes = <(String, String, int)>[
      ('Sueldo', 'work', 0xFF66BB6A),
      ('Regalos', 'card_giftcard', 0xFFEC407A),
      ('Otros ingresos', 'more_horiz', 0xFF9CCC65),
    ];

    final list = <Category>[];
    var order = 0;
    for (final (name, icon, color) in expenses) {
      list.add(Category()
        ..name = name
        ..kind = CategoryKind.expense
        ..iconName = icon
        ..colorValue = color
        ..isDefault = true
        ..sortOrder = order++);
    }
    for (final (name, icon, color) in incomes) {
      list.add(Category()
        ..name = name
        ..kind = CategoryKind.income
        ..iconName = icon
        ..colorValue = color
        ..isDefault = true
        ..sortOrder = order++);
    }
    return list;
  }
}
