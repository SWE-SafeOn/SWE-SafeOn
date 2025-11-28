import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/alert.dart';
import '../theme/app_theme.dart';

class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.icon,
    this.color,
  });

  final String label;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: (color ?? SafeOnColors.primary).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color ?? SafeOnColors.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: color ?? SafeOnColors.primary,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

class AlertSeverityChip extends StatelessWidget {
  const AlertSeverityChip({
    super.key,
    required this.alert,
  });

  final SafeOnAlert alert;

  @override
  Widget build(BuildContext context) {
    return StatusChip(
      label: '${alert.severity.label} • ${_formatTimestamp(alert.timestamp)}',
      icon: Icons.warning_amber_rounded,
      color: alert.severity.color,
    );
  }

  String _formatTimestamp(DateTime? timestamp) {
    if (timestamp == null) {
      return '시간 정보 없음';
    }

    return DateFormat('MMM d, h:mm a').format(timestamp.toLocal());
  }
}
