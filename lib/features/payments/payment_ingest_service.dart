import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:isar_community/isar.dart';

import '../../core/money/money.dart';
import '../../core/notifications/local_notifications.dart';
import '../../core/platform/payment_notifications.dart';
import '../../data/models/app_settings.dart';
import '../../data/models/enums.dart';
import '../../data/models/transaction.dart';
import '../../data/repositories/account_repository.dart';
import '../../data/repositories/category_repository.dart';
import '../../data/repositories/merchant_rule_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import '../receipts/duplicate_detector.dart';
import '../receipts/receipt_parser.dart';
import 'card_account_rule.dart';
import 'known_supermarkets.dart';
import 'notification_parser.dart';

/// Drena el buffer nativo de notificaciones de pago, interpreta cada pago con la
/// regla de su app (`notification_parser.dart`), resuelve categoría y cuenta y
/// **crea el gasto automáticamente** con detección de duplicados. Avisa con una
/// notificación tocable para editar/deshacer.
///
/// Se construye con la instancia cruda de Isar y se llama al abrir/reanudar la
/// app (el buffer nativo persiste con la app cerrada; se procesa al volver).
class PaymentIngestService {
  PaymentIngestService(this._isar);
  final Isar _isar;

  /// Base de id de notificación (disjunta de recurrentes —id de regla— y del
  /// recordatorio de sync —`900000000`—). Se le suma `txnId % 1000000`.
  static const _notifBase = 810000000;

  static const _channel = AndroidNotificationDetails(
    'payments',
    'Gastos por notificación',
    channelDescription:
        'Avisos de gastos detectados en las notificaciones de pago',
    importance: Importance.defaultImportance,
  );

  SettingsRepository get _settings => SettingsRepository(_isar);

  /// Procesa lo capturado desde la última vez. Devuelve cuántos gastos creó.
  /// No hace nada si el lector está desactivado.
  Future<int> drainAndProcess() async {
    final s = await _settings.getOrCreate();
    if (!s.paymentReaderEnabled) return 0;

    final captured = await PaymentNotifications.drainBuffer();
    if (captured.isEmpty) return 0;

    final rules = _decodeRules(s.notificationAppRules);
    final cardRules = _decodeCardRules(s.cardAccountRules);

    final processed = [...s.paymentProcessedHashes];
    var created = 0;
    for (final n in captured) {
      final parsed = parseWithRules(
        package: n.package,
        title: n.title,
        text: n.text,
        postedAt: n.postedAt,
        rules: rules,
      );
      if (parsed == null) continue;
      final hash = _hashOf(parsed);
      if (processed.contains(hash)) continue;
      processed.add(hash);
      if (await _ingest(parsed, s, cardRules)) created++;
    }

    // Poda las huellas a las últimas 300 para que no crezcan sin límite.
    final capped = processed.length > 300
        ? processed.sublist(processed.length - 300)
        : processed;
    await _settings.update((x) => x.paymentProcessedHashes = capped);
    return created;
  }

  Future<bool> _ingest(
      ParsedPayment p, AppSettings s, List<CardAccountRule> cardRules) async {
    final merchant = p.merchant;
    var concept = merchant.isEmpty ? 'Pago con tarjeta' : merchant;
    int? categoryId;
    var reliableCategory = false;

    // 1) Regla de usuario tienda → categoría (memoria compartida con el OCR).
    categoryId = await MerchantRuleRepository(_isar).categoryFor(merchant);
    if (categoryId != null) {
      reliableCategory = true;
    } else {
      // 2) Supermercado conocido → "Alimentación" + nombre canónico.
      final superName = canonicalSupermarket(merchant);
      if (superName != null) {
        concept = superName;
        categoryId = await _categoryIdByName(kAlimentacionCategory);
        reliableCategory = categoryId != null;
      } else {
        // 3) Sugerencia por palabras clave (la misma que el OCR de tickets).
        final suggested = ReceiptParser.suggestCategory(merchant);
        if (suggested != null) categoryId = await _categoryIdByName(suggested);
      }
    }

    // Evita el doble apunte (p. ej. si ya lo creó una recurrente o a mano).
    final day = DateTime(p.date.year, p.date.month, p.date.day);
    final candidates = await TransactionRepository(_isar).query(TransactionFilter(
      from: day.subtract(const Duration(days: 1)),
      to: p.date.add(const Duration(days: 2)),
    ));
    final dup = findPossibleDuplicate(candidates,
        cents: p.cents, date: p.date, merchant: merchant);
    if (dup != null) return false;

    final accountId = await _resolveAccountId(s, p.card, cardRules);
    if (accountId == null) return false; // sin cuenta no se puede imputar

    final txn = TransactionModel()
      ..type = TransactionType.expense
      ..amountCents = p.cents
      ..concept = concept
      ..note = p.card.isEmpty ? '' : 'Tarjeta ${p.card}'
      ..date = p.date
      ..accountId = accountId
      ..categoryId = categoryId;
    final id = await TransactionRepository(_isar).save(txn);

    // Refuerza la memoria tienda → categoría cuando la categoría es fiable.
    if (categoryId != null && reliableCategory && merchant.isNotEmpty) {
      await MerchantRuleRepository(_isar).remember(merchant, categoryId);
    }

    await _notify(id, p.cents, concept);
    return true;
  }

  List<NotificationRule> _decodeRules(List<String> raw) {
    final result = <NotificationRule>[];
    for (final r in raw) {
      final rule = NotificationRule.tryDecode(r);
      if (rule != null) result.add(rule);
    }
    return result;
  }

  List<CardAccountRule> _decodeCardRules(List<String> raw) {
    final result = <CardAccountRule>[];
    for (final r in raw) {
      final rule = CardAccountRule.tryDecode(r);
      if (rule != null) result.add(rule);
    }
    return result;
  }

  Future<int?> _categoryIdByName(String name) async {
    final cats = await CategoryRepository(_isar).byKind(CategoryKind.expense);
    for (final c in cats) {
      if (c.name.toLowerCase() == name.toLowerCase()) return c.id;
    }
    return null;
  }

  /// Cuenta destino: 1) la de la regla tarjeta → cuenta que case; 2) la
  /// configurada por defecto si sigue activa; 3) la primera cuenta activa.
  Future<int?> _resolveAccountId(
      AppSettings s, String card, List<CardAccountRule> cardRules) async {
    final repo = AccountRepository(_isar);
    if (card.isNotEmpty) {
      for (final r in cardRules) {
        if (r.matches(card)) {
          final acc = await repo.getById(r.accountId);
          if (acc != null && acc.deletedAt == null && !acc.archived) {
            return acc.id;
          }
        }
      }
    }
    if (s.paymentDefaultAccountId != 0) {
      final acc = await repo.getById(s.paymentDefaultAccountId);
      if (acc != null && acc.deletedAt == null && !acc.archived) return acc.id;
    }
    final active = await repo.all();
    return active.isEmpty ? null : active.first.id;
  }

  String _hashOf(ParsedPayment p) {
    final day = DateTime(p.date.year, p.date.month, p.date.day);
    return '${p.cents}|${p.merchant.toLowerCase().trim()}|'
        '${day.toIso8601String()}';
  }

  Future<void> _notify(int txnId, int cents, String concept) async {
    if (!await ensureNotificationsInitialized()) return;
    await localNotificationsPlugin.show(
      id: _notifBase + (txnId % 1000000),
      title: 'Gasto detectado',
      body: '${Money(cents).format()} · $concept',
      notificationDetails: const NotificationDetails(android: _channel),
      payload: 'payment:$txnId',
    );
  }
}
