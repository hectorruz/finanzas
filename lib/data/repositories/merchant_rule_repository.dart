import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';

import '../../core/db/isar_provider.dart';
import '../models/merchant_rule.dart';

/// Memoria de correcciones del OCR: comercio → categoría elegida por el usuario.
/// Es el enganche previsto para el futuro motor de reglas de auto-categorización.
class MerchantRuleRepository {
  MerchantRuleRepository(this._isar);
  final Isar _isar;

  /// Categoría recordada para [merchant], o null si no hay memoria.
  Future<int?> categoryFor(String merchant) async {
    final key = MerchantRule.normalize(merchant);
    if (key.isEmpty) return null;
    final rule =
        await _isar.merchantRules.filter().merchantEqualTo(key).findFirst();
    return rule?.categoryId;
  }

  /// Recuerda (o refuerza) que [merchant] pertenece a [categoryId].
  Future<void> remember(String merchant, int categoryId) async {
    final key = MerchantRule.normalize(merchant);
    if (key.isEmpty) return;
    await _isar.writeTxn(() async {
      final existing =
          await _isar.merchantRules.filter().merchantEqualTo(key).findFirst();
      final rule = existing ?? (MerchantRule()..merchant = key);
      if (existing != null && existing.categoryId == categoryId) {
        rule.hits += 1; // refuerzo de una asociación ya conocida
      } else {
        rule
          ..categoryId = categoryId
          ..hits = 1; // corrección: la última elección del usuario manda
      }
      rule.updatedAt = DateTime.now();
      await _isar.merchantRules.put(rule);
    });
  }

  /// Olvida la asociación de un comercio (si el usuario quita la categoría).
  Future<void> forget(String merchant) async {
    final key = MerchantRule.normalize(merchant);
    if (key.isEmpty) return;
    await _isar.writeTxn(() async {
      await _isar.merchantRules.filter().merchantEqualTo(key).deleteAll();
    });
  }
}

final merchantRuleRepositoryProvider = Provider<MerchantRuleRepository>(
  (ref) => MerchantRuleRepository(ref.watch(isarProvider)),
);
