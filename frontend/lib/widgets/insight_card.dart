import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../core/theme.dart';
import '../data/models.dart';
import 'category_icon.dart';

Color insightColor(BuildContext context, InsightTone tone) => switch (tone) {
  InsightTone.positive => AppColors.income,
  InsightTone.negative => AppColors.expense,
  InsightTone.warning => AppColors.gold,
  InsightTone.neutral => const Color(0xFF0EA5E9),
};

class InsightCard extends StatelessWidget {
  const InsightCard({super.key, required this.insight, this.width});

  final Insight insight;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final color = insightColor(context, insight.tone);
    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.18), color.withValues(alpha: 0.06)],
        ),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(iconFor(insight.icon), color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  insight.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  insight.message,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Insight yang bisa digeser ke samping.
class InsightCarousel extends StatelessWidget {
  const InsightCarousel({super.key, required this.items});

  final List<Insight> items;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 124,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) => InsightCard(insight: items[i], width: 280)
            .animate(delay: (i * 90).ms)
            .fadeIn(duration: 350.ms)
            .moveX(begin: 30, end: 0, curve: Curves.easeOutCubic),
      ),
    );
  }
}
