import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/db/isar_provider.dart';
import '../../core/money/money.dart';
import '../../core/platform/payment_notifications.dart';
import '../../data/models/app_settings.dart';
import '../../data/models/category.dart';
import '../../data/models/enums.dart';
import '../../data/repositories/account_repository.dart';
import '../../data/repositories/category_repository.dart';
import '../../data/repositories/merchant_rule_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../payments/card_account_rule.dart';
import '../payments/notification_parser.dart';
import '../payments/payment_ingest_service.dart';

/// Deriva los paquetes de origen (Wallet + las reglas de apps) y los sincroniza
/// con el servicio nativo. Se llama tras cualquier cambio en las reglas.
Future<void> _syncSources(SettingsRepository repo) async {
  final s = await repo.getOrCreate();
  final packages = <String>{NotificationRule.walletPackage};
  for (final raw in s.notificationAppRules) {
    final r = NotificationRule.tryDecode(raw);
    if (r != null) packages.add(r.package);
  }
  await PaymentNotifications.setSourcePackages(packages.toList());
}

/// Reglas de apps a mostrar: la de Google Wallet (built-in, si no hay override
/// guardado) primero y luego las apps personalizadas.
List<NotificationRule> _displayRules(List<String> raw) {
  final decoded = <NotificationRule>[];
  for (final r in raw) {
    final rule = NotificationRule.tryDecode(r);
    if (rule != null) decoded.add(rule);
  }
  final hasWallet =
      decoded.any((r) => r.package == NotificationRule.walletPackage);
  return [
    if (!hasWallet) NotificationRule.wallet(),
    ...decoded,
  ];
}

/// Ajustes de la lectura de notificaciones de pago (Google Wallet + apps
/// personalizadas). Todos los campos son **locales** de este dispositivo (no se
/// sincronizan ni se respaldan).
class PaymentSettingsScreen extends ConsumerStatefulWidget {
  const PaymentSettingsScreen({super.key});

  @override
  ConsumerState<PaymentSettingsScreen> createState() =>
      _PaymentSettingsScreenState();
}

class _PaymentSettingsScreenState extends ConsumerState<PaymentSettingsScreen>
    with WidgetsBindingObserver {
  bool? _granted;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Al volver de la pantalla del sistema (conceder acceso), refrescar estado.
    if (state == AppLifecycleState.resumed) _refreshPermission();
  }

  Future<void> _refreshPermission() async {
    final granted = await PaymentNotifications.isPermissionGranted();
    if (mounted) setState(() => _granted = granted);
  }

  SettingsRepository get _repo => ref.read(settingsRepositoryProvider);

  Future<void> _update(void Function(AppSettings) mutate) async {
    await _repo.update(mutate);
    await _syncSources(_repo);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(currentSettingsProvider);
    final enabled = settings.paymentReaderEnabled;
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];
    final rules = _displayRules(settings.notificationAppRules);
    final granted = _granted;

    return Scaffold(
      appBar: AppBar(title: const Text('Notificaciones de pago')),
      body: ListView(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.notifications_active_outlined),
            title: const Text('Leer notificaciones de pago'),
            subtitle: const Text(
                'Al pagar con el móvil, crea el gasto automáticamente con su '
                'importe, comercio y tarjeta.'),
            value: enabled,
            onChanged: (v) async {
              await _update((s) => s.paymentReaderEnabled = v);
              if (v) await _refreshPermission();
            },
          ),
          const Divider(),
          const _Header('Permiso'),
          ListTile(
            enabled: enabled,
            leading: Icon(
              granted == true ? Icons.check_circle : Icons.error_outline,
              color: granted == true
                  ? Colors.green
                  : Theme.of(context).colorScheme.error,
            ),
            title: const Text('Acceso a las notificaciones'),
            subtitle: Text(granted == null
                ? 'Comprobando…'
                : granted
                    ? 'Concedido'
                    : 'No concedido: sin esto no se pueden leer los pagos'),
            trailing: const Icon(Icons.open_in_new),
            onTap: enabled ? PaymentNotifications.openListenerSettings : null,
          ),
          const Divider(),
          const _Header('Cuenta'),
          ListTile(
            enabled: enabled,
            leading: const Icon(Icons.account_balance),
            title: const Text('Cuenta por defecto'),
            subtitle: Text(_accountLabel(settings.paymentDefaultAccountId,
                {for (final a in accounts) a.id: a.name})),
            trailing: const Icon(Icons.edit_outlined),
            onTap: enabled
                ? () => _pickAccount(
                      context,
                      settings.paymentDefaultAccountId,
                      (id) => _update((s) => s.paymentDefaultAccountId = id),
                      withDefault: true,
                    )
                : null,
          ),
          const Divider(),
          const _Header('Reglas'),
          ListTile(
            enabled: enabled,
            leading: const Icon(Icons.apps),
            title: const Text('Apps y reglas de lectura'),
            subtitle: Text('${rules.length} app(s): dónde buscar importe, '
                'tienda y tarjeta'),
            trailing: const Icon(Icons.chevron_right),
            onTap: enabled
                ? () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const _AppRulesScreen()))
                : null,
          ),
          ListTile(
            enabled: enabled,
            leading: const Icon(Icons.storefront_outlined),
            title: const Text('Tienda → categoría'),
            subtitle: const Text(
                'Asigna la categoría por comercio (compartido con los tickets)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: enabled
                ? () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const _MerchantCategoryScreen()))
                : null,
          ),
          ListTile(
            enabled: enabled,
            leading: const Icon(Icons.credit_card),
            title: const Text('Tarjeta → cuenta'),
            subtitle: const Text('Imputa el gasto a una cuenta según la tarjeta'),
            trailing: const Icon(Icons.chevron_right),
            onTap: enabled
                ? () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const _CardAccountScreen()))
                : null,
          ),
          const Divider(),
          const _Header('Herramientas'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.sync),
                  label: const Text('Procesar ahora'),
                  onPressed: enabled ? () => _processNow(context) : null,
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('Ver notificaciones capturadas'),
                  onPressed: enabled
                      ? () => showCapturedSheet(context, rule: null)
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _processNow(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final n =
        await PaymentIngestService(ref.read(isarProvider)).drainAndProcess();
    messenger.showSnackBar(SnackBar(
      content: Text(n == 0
          ? 'No había pagos nuevos que procesar'
          : 'Creados $n gasto(s) desde notificaciones'),
    ));
  }

  static String _accountLabel(int id, Map<int, String> names) {
    if (id == 0) return 'Primera cuenta activa';
    return names[id] ?? 'Primera cuenta activa';
  }
}

/// Bottom sheet para elegir una cuenta. [withDefault] añade la opción "primera
/// cuenta activa" (id 0). Llama a [onPicked] con el id elegido.
Future<void> _pickAccount(
  BuildContext context,
  int current,
  void Function(int id) onPicked, {
  bool withDefault = false,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final accounts = container.read(accountsProvider).valueOrNull ?? const [];
  Widget option(int id, String label) => ListTile(
        leading: Icon(id == current
            ? Icons.radio_button_checked
            : Icons.radio_button_unchecked),
        title: Text(label),
        onTap: () {
          onPicked(id);
          Navigator.pop(context);
        },
      );
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => SafeArea(
      top: false,
      child: ListView(
        shrinkWrap: true,
        children: [
          if (withDefault) option(0, 'Primera cuenta activa'),
          for (final a in accounts) option(a.id, a.name),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Pantalla: apps y reglas de lectura
// ---------------------------------------------------------------------------

class _AppRulesScreen extends ConsumerWidget {
  const _AppRulesScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final rules = _displayRules(settings.notificationAppRules);

    return Scaffold(
      appBar: AppBar(title: const Text('Apps y reglas de lectura')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Añadir app'),
        onPressed: () => _openEditor(context, null),
      ),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
                'Google Wallet ya funciona sin configurar. Añade otras apps '
                'diciendo el paquete y dónde buscar cada dato (regex).'),
          ),
          for (final rule in rules)
            ListTile(
              leading: Icon(rule.package == NotificationRule.walletPackage
                  ? Icons.account_balance_wallet_outlined
                  : Icons.apps),
              title: Text(rule.label.isEmpty ? rule.package : rule.label),
              subtitle: Text(rule.package),
              trailing: rule.package == NotificationRule.walletPackage &&
                      !_isStored(settings.notificationAppRules, rule.package)
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _delete(ref, rule.package),
                    ),
              onTap: () => _openEditor(context, rule),
            ),
        ],
      ),
    );
  }

  static bool _isStored(List<String> raw, String package) => raw.any((r) =>
      NotificationRule.tryDecode(r)?.package == package);

  void _openEditor(BuildContext context, NotificationRule? rule) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _RuleEditorScreen(initial: rule),
    ));
  }

  Future<void> _delete(WidgetRef ref, String package) async {
    final repo = ref.read(settingsRepositoryProvider);
    await repo.update((s) {
      s.notificationAppRules = [
        for (final raw in s.notificationAppRules)
          if (NotificationRule.tryDecode(raw)?.package != package) raw,
      ];
    });
    await _syncSources(repo);
  }
}

/// Editor de una regla de app (paquete + regex por campo) con un probador en
/// vivo contra las notificaciones ya capturadas.
class _RuleEditorScreen extends ConsumerStatefulWidget {
  const _RuleEditorScreen({this.initial});
  final NotificationRule? initial;

  @override
  ConsumerState<_RuleEditorScreen> createState() => _RuleEditorScreenState();
}

class _RuleEditorScreenState extends ConsumerState<_RuleEditorScreen> {
  late final TextEditingController _package;
  late final TextEditingController _label;
  late final TextEditingController _merchantRegex;
  late final TextEditingController _amountRegex;
  late final TextEditingController _cardRegex;
  late bool _merchantFromTitle;

  @override
  void initState() {
    super.initState();
    final r = widget.initial;
    _package = TextEditingController(text: r?.package ?? '');
    _label = TextEditingController(text: r?.label ?? '');
    _merchantRegex = TextEditingController(text: r?.merchantRegex ?? '');
    _amountRegex = TextEditingController(text: r?.amountRegex ?? '');
    _cardRegex = TextEditingController(text: r?.cardRegex ?? '');
    _merchantFromTitle = r?.merchantFromTitle ?? false;
  }

  @override
  void dispose() {
    _package.dispose();
    _label.dispose();
    _merchantRegex.dispose();
    _amountRegex.dispose();
    _cardRegex.dispose();
    super.dispose();
  }

  NotificationRule _current() => NotificationRule(
        package: _package.text.trim(),
        label: _label.text.trim(),
        merchantFromTitle: _merchantFromTitle,
        merchantRegex: _merchantRegex.text.trim().isEmpty
            ? null
            : _merchantRegex.text.trim(),
        amountRegex:
            _amountRegex.text.trim().isEmpty ? null : _amountRegex.text.trim(),
        cardRegex:
            _cardRegex.text.trim().isEmpty ? null : _cardRegex.text.trim(),
      );

  Future<void> _save() async {
    final rule = _current();
    if (rule.package.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Indica el paquete de la app')),
      );
      return;
    }
    final repo = ref.read(settingsRepositoryProvider);
    await repo.update((s) {
      final list = [...s.notificationAppRules];
      final idx = list.indexWhere(
          (raw) => NotificationRule.tryDecode(raw)?.package == rule.package);
      if (idx >= 0) {
        list[idx] = rule.encode();
      } else {
        list.add(rule.encode());
      }
      s.notificationAppRules = list;
    });
    await _syncSources(repo);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initial == null ? 'Nueva app' : 'Editar app'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: 'Guardar',
            onPressed: _save,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          TextField(
            controller: _package,
            enabled: widget.initial == null,
            decoration: const InputDecoration(
              labelText: 'Paquete de la app',
              hintText: 'com.google.android.apps.walletnfcrel',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _label,
            decoration: const InputDecoration(
              labelText: 'Nombre (para mostrar)',
              hintText: 'Google Wallet',
            ),
          ),
          const SizedBox(height: 20),
          Text('Dónde buscar', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('La tienda es el título'),
            subtitle: const Text(
                'El título de la notificación es el comercio (si no, usa el '
                'regex de abajo)'),
            value: _merchantFromTitle,
            onChanged: (v) => setState(() => _merchantFromTitle = v),
          ),
          _RegexField(
            controller: _merchantRegex,
            label: 'Regex de la tienda (opcional)',
            hint: r'Compra en (.+?) por',
          ),
          _RegexField(
            controller: _amountRegex,
            label: 'Regex del importe (opcional)',
            hint: r'([0-9]+[.,][0-9]{2})\s*€',
          ),
          _RegexField(
            controller: _cardRegex,
            label: 'Regex de la tarjeta (opcional)',
            hint: r'tarjeta\s+\S+\s+(\d{4})',
          ),
          const SizedBox(height: 8),
          const Text(
            'Si dejas un regex vacío se usa la detección automática. El grupo '
            '(entre paréntesis) es el valor que se extrae.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: const Text('Probar contra capturadas'),
            onPressed: () => showCapturedSheet(context, rule: _current()),
          ),
        ],
      ),
    );
  }
}

class _RegexField extends StatelessWidget {
  const _RegexField(
      {required this.controller, required this.label, required this.hint});
  final TextEditingController controller;
  final String label;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TextField(
        controller: controller,
        style: const TextStyle(fontFamily: 'monospace'),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

/// Muestra las notificaciones capturadas y, si se pasa una [rule], el resultado
/// de aplicarla a cada una (probador en vivo). Sin [rule], usa la regla de
/// Wallet / la del paquete de cada notificación como referencia.
Future<void> showCapturedSheet(BuildContext context,
    {required NotificationRule? rule}) async {
  final captured = await PaymentNotifications.peekBuffer();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (_, controller) {
        if (captured.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                  'Sin notificaciones capturadas todavía.\nPaga con la app y '
                  'vuelve a mirar aquí (la app debe estar en la lista de '
                  'reglas para capturarse).',
                  textAlign: TextAlign.center),
            ),
          );
        }
        final df = DateFormat('d MMM, HH:mm', 'es_ES');
        return ListView.separated(
          controller: controller,
          itemCount: captured.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final c = captured[captured.length - 1 - i]; // recientes arriba
            final parsed = rule != null
                ? applyRule(rule,
                    title: c.title, text: c.text, postedAt: c.postedAt)
                : parseWithRules(
                    package: c.package,
                    title: c.title,
                    text: c.text,
                    postedAt: c.postedAt,
                    rules: const []);
            return ListTile(
              title: Text(c.title.isEmpty ? '(sin título)' : c.title),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.text),
                  const SizedBox(height: 2),
                  Text(
                    parsed == null
                        ? '❔ No parece un pago'
                        : '✅ ${Money(parsed.cents).format()} · '
                            '${parsed.merchant.isEmpty ? "(sin tienda)" : parsed.merchant}'
                            '${parsed.card.isEmpty ? "" : " · ${parsed.card}"}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              trailing: Text(df.format(c.postedAt),
                  style: Theme.of(context).textTheme.bodySmall),
              isThreeLine: true,
            );
          },
        );
      },
    ),
  );
}

// ---------------------------------------------------------------------------
// Pantalla: tienda → categoría (memoria compartida con el OCR de tickets)
// ---------------------------------------------------------------------------

class _MerchantCategoryScreen extends ConsumerStatefulWidget {
  const _MerchantCategoryScreen();

  @override
  ConsumerState<_MerchantCategoryScreen> createState() =>
      _MerchantCategoryScreenState();
}

class _MerchantCategoryScreenState
    extends ConsumerState<_MerchantCategoryScreen> {
  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(merchantRuleRepositoryProvider);
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const [];
    final names = {for (final c in categories) c.id: c.name};

    return Scaffold(
      appBar: AppBar(title: const Text('Tienda → categoría')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Añadir'),
        onPressed: () => _addRule(context, categories),
      ),
      body: FutureBuilder(
        future: repo.all(),
        builder: (context, snapshot) {
          final rules = snapshot.data ?? const [];
          if (rules.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                    'Aún no hay reglas. Cuando categorizas un ticket o un pago, '
                    'se recuerda el comercio aquí.',
                    textAlign: TextAlign.center),
              ),
            );
          }
          return ListView(
            children: [
              for (final r in rules)
                ListTile(
                  leading: const Icon(Icons.storefront_outlined),
                  title: Text(r.merchant),
                  subtitle: Text(names[r.categoryId] ?? '(categoría borrada)'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      await repo.forget(r.merchant);
                      setState(() {});
                    },
                  ),
                  onTap: () => _editRule(context, r.merchant, categories),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _addRule(BuildContext context, List<Category> categories) async {
    final controller = TextEditingController();
    final merchant = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Comercio'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Mercadona'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Siguiente'),
          ),
        ],
      ),
    );
    if (merchant == null || merchant.isEmpty || !context.mounted) return;
    await _editRule(context, merchant, categories);
  }

  Future<void> _editRule(BuildContext context, String merchant,
      List<Category> categories) async {
    final expense =
        categories.where((c) => c.kind == CategoryKind.expense).toList();
    final categoryId = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, controller) => ListView(
          controller: controller,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Categoría para "$merchant"',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            for (final c in expense)
              ListTile(
                leading: const Icon(Icons.category_outlined),
                title: Text(c.name),
                onTap: () => Navigator.pop(context, c.id),
              ),
          ],
        ),
      ),
    );
    if (categoryId == null) return;
    await ref
        .read(merchantRuleRepositoryProvider)
        .remember(merchant, categoryId);
    if (mounted) setState(() {});
  }
}

// ---------------------------------------------------------------------------
// Pantalla: tarjeta → cuenta
// ---------------------------------------------------------------------------

class _CardAccountScreen extends ConsumerWidget {
  const _CardAccountScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];
    final names = {for (final a in accounts) a.id: a.name};
    final rules = <CardAccountRule>[];
    for (final raw in settings.cardAccountRules) {
      final r = CardAccountRule.tryDecode(raw);
      if (r != null) rules.add(r);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Tarjeta → cuenta')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Añadir'),
        onPressed: () => _addRule(context, ref),
      ),
      body: rules.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                    'Sin reglas. El gasto irá a la cuenta por defecto. Añade una '
                    'regla para que cada tarjeta impute a su cuenta.',
                    textAlign: TextAlign.center),
              ),
            )
          : ListView(
              children: [
                for (final r in rules)
                  ListTile(
                    leading: const Icon(Icons.credit_card),
                    title: Text(r.card),
                    subtitle: Text(names[r.accountId] ?? '(cuenta borrada)'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _delete(ref, r.card),
                    ),
                  ),
              ],
            ),
    );
  }

  Future<void> _addRule(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final card = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tarjeta'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '••1234',
            helperText: 'Tal como aparece en la notificación',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Siguiente'),
          ),
        ],
      ),
    );
    if (card == null || card.isEmpty || !context.mounted) return;
    await _pickAccount(context, 0, (accountId) async {
      final repo = ref.read(settingsRepositoryProvider);
      await repo.update((s) {
        final rule = CardAccountRule(card: card, accountId: accountId);
        s.cardAccountRules = [
          for (final raw in s.cardAccountRules)
            if (CardAccountRule.tryDecode(raw)?.card != card) raw,
          rule.encode(),
        ];
      });
    });
  }

  Future<void> _delete(WidgetRef ref, String card) async {
    await ref.read(settingsRepositoryProvider).update((s) {
      s.cardAccountRules = [
        for (final raw in s.cardAccountRules)
          if (CardAccountRule.tryDecode(raw)?.card != card) raw,
      ];
    });
  }
}

class _Header extends StatelessWidget {
  const _Header(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
