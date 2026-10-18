import 'package:flutter/material.dart';

/// Nama ikon dari database -> IconData Flutter.
const Map<String, IconData> categoryIcons = {
  'restaurant': Icons.restaurant_rounded,
  'bolt': Icons.bolt_rounded,
  'water_drop': Icons.water_drop_rounded,
  'wifi': Icons.wifi_rounded,
  'directions_car': Icons.directions_car_rounded,
  'shopping_bag': Icons.shopping_bag_rounded,
  'local_hospital': Icons.local_hospital_rounded,
  'school': Icons.school_rounded,
  'movie': Icons.movie_rounded,
  'receipt_long': Icons.receipt_long_rounded,
  'more_horiz': Icons.more_horiz_rounded,
  'payments': Icons.payments_rounded,
  'redeem': Icons.redeem_rounded,
  'work': Icons.work_rounded,
  'card_giftcard': Icons.card_giftcard_rounded,
  'local_cafe': Icons.local_cafe_rounded,
  'home': Icons.home_rounded,
  'pets': Icons.pets_rounded,
  'sports_esports': Icons.sports_esports_rounded,
  'flight': Icons.flight_rounded,
  'fitness_center': Icons.fitness_center_rounded,
  'savings': Icons.savings_rounded,
  'apartment': Icons.apartment_rounded,
  'family_restroom': Icons.family_restroom_rounded,
  'category': Icons.category_rounded,
};

IconData iconFor(String name) => categoryIcons[name] ?? Icons.category_rounded;

class CategoryIcon extends StatelessWidget {
  const CategoryIcon({super.key, required this.icon, required this.color, this.size = 44});

  final String icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(iconFor(icon), color: color, size: size * 0.5),
    );
  }
}
