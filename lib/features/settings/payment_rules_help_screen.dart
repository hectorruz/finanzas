import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../payments/regex_help.dart';

/// Tutorial de las reglas de lectura de notificaciones: cómo se lee una
/// notificación, qué es cada campo, un recetario de patrones para copiar y las
/// trampas que no se ven (un patrón inválido se ignora en silencio, un importe
/// que no casa descarta la notificación entera…).
///
/// Se abre desde Ajustes → Notificaciones de pago, desde la lista de apps y
/// desde el editor de una regla.
class PaymentRulesHelpScreen extends StatelessWidget {
  const PaymentRulesHelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cómo crear una regla')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const _Intro(),
          const _Step(
            number: '1',
            title: 'Averigua el paquete de la app',
            child: _PackageHelp(),
          ),
          const _Step(
            number: '2',
            title: 'Guarda la regla y paga una vez',
            child: Text(
              'Crea la app con su paquete y guarda, aunque aún no pongas ningún '
              'patrón. Hasta que no la guardas, la app no captura nada de ese '
              'programa: no tendrías notificaciones sobre las que probar.\n\n'
              'Después paga una vez y vuelve aquí. Con la detección automática '
              'puede que ya funcione: pruébalo antes de escribir ningún patrón.',
            ),
          ),
          const _Step(
            number: '3',
            title: 'Mira dónde está cada dato',
            child: _NotificationAnatomy(),
          ),
          const _Step(
            number: '4',
            title: 'Escribe el patrón',
            child: _GroupExplainer(),
          ),
          const SizedBox(height: 8),
          const _SectionTitle('Recetario', icon: Icons.menu_book_outlined),
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Text(
              'Copia el que se parezca a tu notificación y pégalo en el campo '
              'correspondiente. Luego usa "Probar contra capturadas" para ver si '
              'acierta.',
            ),
          ),
          for (final field in RegexField.values) _RecipeGroup(field: field),
          const SizedBox(height: 8),
          const _SectionTitle('Glosario', icon: Icons.abc),
          const _Glossary(),
          const SizedBox(height: 8),
          const _SectionTitle('Cuidado con esto',
              icon: Icons.warning_amber_outlined),
          const _Pitfalls(),
        ],
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.secondaryContainer,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.account_balance_wallet_outlined,
                    color: scheme.onSecondaryContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Google Wallet ya funciona sin tocar nada',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(color: scheme.onSecondaryContainer),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Esto solo hace falta para leer OTRA app: la de tu banco, por '
              'ejemplo. Una regla dice dos cosas: de qué app son las '
              'notificaciones y dónde está cada dato dentro del texto '
              '(el importe, la tienda y la tarjeta).',
              style: TextStyle(color: scheme.onSecondaryContainer),
            ),
          ],
        ),
      ),
    );
  }
}

class _PackageHelp extends StatelessWidget {
  const _PackageHelp();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'El paquete es el nombre técnico de la app. La forma más fácil de '
          'saberlo: busca la app en Google Play desde el navegador y míralo en '
          'la dirección, después de "id=".',
        ),
        const SizedBox(height: 8),
        const _Mono(
          'play.google.com/store/apps/details?id=com.banco.app\n'
          '                                     └──── el paquete ────┘',
        ),
        const SizedBox(height: 8),
        Text(
          'También sale en Ajustes de Android → Aplicaciones → (tu app) → '
          'Detalles de la app.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _NotificationAnatomy extends StatelessWidget {
  const _NotificationAnatomy();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Toca "Ver notificaciones capturadas" para ver el texto exacto que '
          'manda tu app. Una notificación tiene dos partes:',
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.circle, size: 10, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Compra realizada',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                  ),
                  _Tag('título', color: scheme.primary),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const SizedBox(width: 18),
                  const Expanded(
                      child: Text('Pago de 23,45 € en MERCADONA con '
                          'tarjeta ••1234')),
                  _Tag('texto', color: scheme.tertiary),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Importante: el patrón se busca en el título y el texto JUNTOS, uno '
          'debajo del otro, como si fueran un solo párrafo. Da igual en cuál de '
          'los dos esté el dato.',
        ),
        const SizedBox(height: 8),
        Text(
          'Si la tienda es justo el título entero (como en Wallet), no escribas '
          'ningún patrón: activa el interruptor "La tienda es el título".',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _GroupExplainer extends StatelessWidget {
  const _GroupExplainer();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Un patrón describe el texto que rodea al dato, y lo que pongas entre '
          'paréntesis es lo que se guarda. El resto solo sirve para encontrar el '
          'sitio.',
        ),
        const SizedBox(height: 12),
        const _Mono('Pago de 23,45 € en MERCADONA'),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(Icons.south, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text('con este patrón…',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            ],
          ),
        ),
        const _Mono(r'Pago de ([0-9]+[.,][0-9]{2}) €'),
        const SizedBox(height: 8),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'se guarda solo '),
              TextSpan(
                text: '23,45',
                style: TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    color: scheme.primary),
              ),
              const TextSpan(text: ', que es lo que va entre paréntesis.'),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Si no pones paréntesis se guarda todo lo que case. Las mayúsculas dan '
          'igual: "TARJETA" y "tarjeta" son lo mismo.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _RecipeGroup extends StatelessWidget {
  const _RecipeGroup({required this.field});
  final RegexField field;

  static const _labels = {
    RegexField.amount: 'Para el campo "Importe"',
    RegexField.merchant: 'Para el campo "Tienda"',
    RegexField.card: 'Para el campo "Tarjeta"',
  };

  @override
  Widget build(BuildContext context) {
    final recipes = kRegexRecipes.where((r) => r.field == field).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
          child: Text(
            _labels[field]!,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(color: Theme.of(context).colorScheme.primary),
          ),
        ),
        for (final r in recipes) _RecipeCard(recipe: r),
      ],
    );
  }
}

class _RecipeCard extends StatelessWidget {
  const _RecipeCard({required this.recipe});
  final RegexRecipe recipe;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(recipe.title,
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_outlined),
                  tooltip: 'Copiar el patrón',
                  onPressed: () => _copy(context),
                ),
              ],
            ),
            _Mono(recipe.pattern),
            const SizedBox(height: 8),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${recipe.example}\n',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  const TextSpan(text: 'saca '),
                  TextSpan(
                    text: recipe.extracts,
                    style: TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        color: scheme.primary),
                  ),
                ],
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  void _copy(BuildContext context) {
    Clipboard.setData(ClipboardData(text: recipe.pattern));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Patrón copiado')),
    );
  }
}

class _Glossary extends StatelessWidget {
  const _Glossary();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            for (final entry in kRegexGlossary)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 56,
                      child: Text(
                        entry.token,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(entry.meaning,
                          style: Theme.of(context).textTheme.bodySmall),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Pitfalls extends StatelessWidget {
  const _Pitfalls();

  static const _items = [
    (
      title: 'Un patrón mal escrito no avisa… salvo aquí',
      body: 'Si un patrón no es válido, la app lo ignora y vuelve a la '
          'detección automática, así que parece que funciona pero tu regla no '
          'se usa. Por eso el editor te marca el campo en rojo: si no hay '
          'error, el patrón es válido.',
    ),
    (
      title: 'Si el importe no casa, se descarta la notificación entera',
      body: 'Con la tienda y la tarjeta, un patrón que no case solo deja el '
          'dato vacío. Con el importe no: la notificación se ignora por '
          'completo. Puedes usarlo a tu favor — si tu banco te notifica muchas '
          'cosas que no son pagos, un patrón de importe exigente hace de '
          'filtro y evita gastos falsos.',
    ),
    (
      title: 'El patrón de tienda manda sobre el interruptor',
      body: 'Si escribes un patrón de tienda, "La tienda es el título" se '
          'ignora. Usa uno u otro, no los dos.',
    ),
    (
      title: 'Un campo vacío no es un error',
      body: 'Vacío significa "búscalo tú". La detección automática acierta con '
          'muchas apps: empieza sin nada y añade patrones solo donde falle.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final item in _items)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title,
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(item.body,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// --- Piezas de presentación ---

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.title, required this.child});
  final String number;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 13,
                backgroundColor: scheme.primary,
                child: Text(
                  number,
                  style: TextStyle(
                      color: scheme.onPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(36, 8, 0, 0),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {required this.icon});
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(text, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

/// Bloque de texto en monoespaciado que se puede desplazar en horizontal (los
/// patrones son largos y no deben desbordar la pantalla).
class _Mono extends StatelessWidget {
  const _Mono(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text(
          text,
          style: TextStyle(
              fontFamily: 'monospace', fontSize: 13, color: scheme.onSurface),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Text(text, style: TextStyle(fontSize: 11, color: color)),
    );
  }
}
