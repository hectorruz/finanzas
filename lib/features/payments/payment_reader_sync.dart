import '../../core/platform/payment_notifications.dart';
import '../../data/repositories/settings_repository.dart';
import 'notification_parser.dart';

/// Pone al día el servicio nativo con lo que dicen los ajustes (que viven en
/// Isar, invisible desde Kotlin): si el lector está activo y qué apps capturar.
///
/// Punto único a propósito: el flag es el gate que decide si un pago arranca el
/// engine de ingesta con la app cerrada, y se espeja **siempre**, también al
/// desactivar — si no, el nativo se quedaría creyendo que sigue activo y
/// arrancaría un engine por cada notificación para nada. Hay que llamarla en
/// cada arranque y tras cualquier cambio en los ajustes de pagos.
Future<void> syncPaymentReaderToNative(SettingsRepository repo) async {
  final s = await repo.getOrCreate();
  await PaymentNotifications.setReaderEnabled(s.paymentReaderEnabled);
  if (!s.paymentReaderEnabled) return;
  await PaymentNotifications.setSourcePackages(
      paymentSourcePackages(s.notificationAppRules));
}

/// Paquetes cuyas notificaciones hay que capturar: Wallet (regla implícita, no
/// se guarda en ajustes) más el de cada regla del usuario.
List<String> paymentSourcePackages(List<String> notificationAppRules) {
  final packages = <String>{NotificationRule.walletPackage};
  for (final raw in notificationAppRules) {
    final r = NotificationRule.tryDecode(raw);
    if (r != null) packages.add(r.package);
  }
  return packages.toList();
}
