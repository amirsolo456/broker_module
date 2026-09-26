import 'package:flutter/material.dart';

class StatusBadge extends StatelessWidget {
  final bool isCompleted;
  final int score;

  const StatusBadge({
    super.key,
    required this.isCompleted,
    required this.score,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isCompleted ? Colors.green.shade100 : Colors.orange.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isCompleted ? Colors.green.shade400 : Colors.orange.shade400),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isCompleted ? Icons.check_circle : Icons.hourglass_top,
            size: 13,
            color: isCompleted ? Colors.green.shade800 : Colors.orange.shade900,
          ),
          const SizedBox(width: 4),
          Text(
            isCompleted ? 'کامل (تایید خودکار)' : 'پندینگ (نمره: $score٪)',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: isCompleted ? Colors.green.shade900 : Colors.orange.shade900,
            ),
          ),
        ],
      ),
    );
  }
}
