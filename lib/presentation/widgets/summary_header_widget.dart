import 'package:flutter/material.dart';
import '../../core/utils/date_formatter.dart';

class SummaryHeaderWidget extends StatelessWidget {
  final int totalCount;
  final num totalAmount;
  final num totalDiscounts;

  const SummaryHeaderWidget({
    super.key,
    required this.totalCount,
    required this.totalAmount,
    required this.totalDiscounts,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [theme.colorScheme.primary, theme.colorScheme.secondary],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem('تعداد صورتحساب', '$totalCount عدد', Icons.receipt_long),
          Container(width: 1, height: 40, color: Colors.white30),
          _buildStatItem('مجموع مبالغ', '${DateFormatter.formatCurrency(totalAmount)} ریال', Icons.account_balance_wallet),
          Container(width: 1, height: 40, color: Colors.white30),
          _buildStatItem('تخفیف‌های محاسبه‌شده', '${DateFormatter.formatCurrency(totalDiscounts)} ریال', Icons.discount),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white70, size: 22),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
        ),
      ],
    );
  }
}
