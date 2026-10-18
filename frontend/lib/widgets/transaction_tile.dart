import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import 'category_icon.dart';
import 'common.dart';

class TransactionTile extends StatelessWidget {
  const TransactionTile({super.key, required this.transaction, this.onTap, this.showDate = false});

  final Transaction transaction;
  final VoidCallback? onTap;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final t = transaction;
    final color = t.type.isIncome ? AppColors.income : AppColors.expense;
    final subtitle = [
      if (showDate) relativeDay(t.date),
      if (t.wallet != null) t.wallet!.name,
      if (t.note != null && t.note!.isNotEmpty) t.note!,
    ].join(' • ');

    return Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                CategoryIcon(icon: t.category.icon, color: t.category.color),
                // Belum terkirim ke server
                if (t.isPending)
                  Positioned(
                    right: -5,
                    bottom: -5,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: context.colors.surfaceContainerLow,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        t.syncError != null ? Icons.error_rounded : Icons.cloud_upload_rounded,
                        size: 16,
                        color: t.syncError != null ? AppColors.expense : AppColors.gold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.category.name,
                    style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (t.isPending)
                    Text(
                      t.syncError != null ? 'Gagal dikirim: ${t.syncError}' : 'Menunggu dikirim',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.labelSmall?.copyWith(
                        color: t.syncError != null ? AppColors.expense : AppColors.gold,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              signedRupiah(t.amount, isIncome: t.type.isIncome),
              style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
