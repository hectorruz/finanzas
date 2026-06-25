import 'package:flutter/material.dart';

/// Mapa estático nombre -> [IconData].
///
/// Se usa un mapa con constantes (en vez de `IconData(...)` dinámico) para no
/// romper el *tree-shaking* de iconos de Flutter en release.
const Map<String, IconData> kAppIcons = {
  'account_balance': Icons.account_balance,
  'payments': Icons.payments,
  'savings': Icons.savings,
  'credit_card': Icons.credit_card,
  'wallet': Icons.wallet,
  'trending_up': Icons.trending_up,
  'restaurant': Icons.restaurant,
  'directions_car': Icons.directions_car,
  'home': Icons.home,
  'sports_esports': Icons.sports_esports,
  'local_hospital': Icons.local_hospital,
  'shopping_bag': Icons.shopping_bag,
  'subscriptions': Icons.subscriptions,
  'work': Icons.work,
  'card_giftcard': Icons.card_giftcard,
  'flag': Icons.flag,
  'category': Icons.category,
  'more_horiz': Icons.more_horiz,
  'school': Icons.school,
  'pets': Icons.pets,
  'flight': Icons.flight,
  'fitness_center': Icons.fitness_center,
  'phone_android': Icons.phone_android,
  'bolt': Icons.bolt,
  'water_drop': Icons.water_drop,
  'local_cafe': Icons.local_cafe,
  'receipt_long': Icons.receipt_long,
};

/// Lista de nombres disponibles para selectores de icono.
const List<String> kAppIconNames = [
  'account_balance', 'payments', 'savings', 'credit_card', 'wallet',
  'trending_up', 'restaurant', 'directions_car', 'home', 'sports_esports',
  'local_hospital', 'shopping_bag', 'subscriptions', 'work', 'card_giftcard',
  'flag', 'category', 'more_horiz', 'school', 'pets', 'flight',
  'fitness_center', 'phone_android', 'bolt', 'water_drop', 'local_cafe',
  'receipt_long',
];

IconData iconByName(String name) => kAppIcons[name] ?? Icons.category;
