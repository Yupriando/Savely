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
  'local_grocery_store': Icons.local_grocery_store_rounded,
  'checkroom': Icons.checkroom_rounded,
  'local_gas_station': Icons.local_gas_station_rounded,
  'local_parking': Icons.local_parking_rounded,
  'phone_android': Icons.phone_android_rounded,
  'subscriptions': Icons.subscriptions_rounded,
  'spa': Icons.spa_rounded,
  'child_care': Icons.child_care_rounded,
  'volunteer_activism': Icons.volunteer_activism_rounded,
  'build': Icons.build_rounded,
  'local_laundry_service': Icons.local_laundry_service_rounded,
  'celebration': Icons.celebration_rounded,
  'sports_soccer': Icons.sports_soccer_rounded,
  'storefront': Icons.storefront_rounded,
  'trending_up': Icons.trending_up_rounded,
  'attach_money': Icons.attach_money_rounded,
  // dompet
  'account_balance': Icons.account_balance_rounded,
  'account_balance_wallet': Icons.account_balance_wallet_rounded,
  'phone_iphone': Icons.phone_iphone_rounded,
  'credit_card': Icons.credit_card_rounded,
  // insight
  'report': Icons.report_rounded,
  'warning_amber': Icons.warning_amber_rounded,
  'trending_down': Icons.trending_down_rounded,
  'insights': Icons.insights_rounded,
  'query_stats': Icons.query_stats_rounded,
  'emoji_events': Icons.emoji_events_rounded,
  'event': Icons.event_rounded,
  'pie_chart': Icons.pie_chart_rounded,
  'lightbulb': Icons.lightbulb_rounded,
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
