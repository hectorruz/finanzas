import '../../data/models/enums.dart';

/// DTOs planos de la webapp de escritorio. **Desacoplados de Isar** a propósito
/// (no importan `isar_community`) para que compilen en el target web; reutilizan
/// solo los enums y `Money`, que son Dart puro.

class AccountDto {
  AccountDto({
    required this.id,
    required this.name,
    required this.type,
    required this.iconName,
    required this.colorValue,
    required this.balanceCents,
    required this.includeInTotal,
    this.parentId,
  });

  final int id;
  final String name;
  final AccountType type;
  final String iconName;
  final int colorValue;
  final int balanceCents;
  final bool includeInTotal;
  final int? parentId;

  static AccountDto fromJson(Map<String, dynamic> m) => AccountDto(
        id: m['id'] as int,
        name: m['name'] as String? ?? '',
        type: enumByName(AccountType.values, m['type'] as String?, AccountType.bank),
        iconName: m['iconName'] as String? ?? 'account_balance',
        colorValue: m['colorValue'] as int? ?? 0xFF2196F3,
        balanceCents: m['balanceCents'] as int? ?? 0,
        includeInTotal: m['includeInTotal'] as bool? ?? true,
        parentId: m['parentId'] as int?,
      );
}

class CategoryDto {
  CategoryDto({
    required this.id,
    required this.name,
    required this.kind,
    required this.iconName,
    required this.colorValue,
    this.parentId,
  });

  final int id;
  final String name;
  final CategoryKind kind;
  final String iconName;
  final int colorValue;
  final int? parentId;

  static CategoryDto fromJson(Map<String, dynamic> m) => CategoryDto(
        id: m['id'] as int,
        name: m['name'] as String? ?? '',
        kind: enumByName(
            CategoryKind.values, m['kind'] as String?, CategoryKind.expense),
        iconName: m['iconName'] as String? ?? 'category',
        colorValue: m['colorValue'] as int? ?? 0xFF9E9E9E,
        parentId: m['parentId'] as int?,
      );
}

class TransactionDto {
  TransactionDto({
    this.id,
    required this.type,
    required this.amountCents,
    required this.concept,
    required this.date,
    this.note = '',
    required this.accountId,
    this.toAccountId,
    this.categoryId,
  });

  final int? id;
  final TransactionType type;
  final int amountCents;
  final String concept;
  final DateTime date;
  final String note;
  final int accountId;
  final int? toAccountId;
  final int? categoryId;

  static TransactionDto fromJson(Map<String, dynamic> m) => TransactionDto(
        id: m['id'] as int?,
        type: enumByName(
            TransactionType.values, m['type'] as String?, TransactionType.expense),
        amountCents: m['amountCents'] as int? ?? 0,
        concept: m['concept'] as String? ?? '',
        date: DateTime.parse(m['date'] as String),
        note: m['note'] as String? ?? '',
        accountId: m['accountId'] as int? ?? 0,
        toAccountId: m['toAccountId'] as int?,
        categoryId: m['categoryId'] as int?,
      );

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'amountCents': amountCents,
        'concept': concept,
        'date': date.toIso8601String(),
        'note': note,
        'accountId': accountId,
        'toAccountId': toAccountId,
        'categoryId': categoryId,
      };

  /// Signo según el efecto sobre la cuenta propietaria (solo un ingreso suma).
  int get signedCents => type == TransactionType.income ? amountCents : -amountCents;
}
