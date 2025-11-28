import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/alert.dart';
import '../theme/app_theme.dart';
import 'status_chip.dart';

class AlertTile extends StatelessWidget {
  const AlertTile({
    super.key,
    required this.alert,
    this.onTap,
    this.isAcknowledging = false,
  });

  final SafeOnAlert alert;
  final VoidCallback? onTap;
  final bool isAcknowledging;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRead = alert.read ?? false;
    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      color: isRead ? SafeOnColors.textSecondary : SafeOnColors.textPrimary,
      fontWeight: isRead ? FontWeight.w600 : FontWeight.w700,
    );
    final subtitleStyle = theme.textTheme.bodyMedium?.copyWith(
      color: isRead ? SafeOnColors.textSecondary : SafeOnColors.textPrimary,
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isRead
              ? SafeOnColors.surface.withValues(alpha: 0.8)
              : SafeOnColors.primary.withValues(alpha: 0.08),
          border: Border.all(
            color: isRead
                ? SafeOnColors.textSecondary.withValues(alpha: 0.14)
                : SafeOnColors.primary.withValues(alpha: 0.3),
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.security,
                  color: alert.severity.color,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    alert.reason,
                    style: titleStyle,
                  ),
                ),
                const SizedBox(width: 10),
                if (isAcknowledging)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  StatusChip(
                    label: isRead ? '읽음' : '새 알림',
                    icon: isRead ? Icons.mark_email_read : Icons.mark_email_unread,
                    color: isRead
                        ? SafeOnColors.textSecondary
                        : SafeOnColors.primary,
                  ),
              ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(
                Icons.schedule,
                color: SafeOnColors.textSecondary,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                _formatTimestamp(alert.timestamp),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: SafeOnColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    alert.subtitle,
                    style: subtitleStyle,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            AlertSeverityChip(alert: alert),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime? timestamp) {
    if (timestamp == null) {
      return '시간 정보 없음';
    }
    return DateFormat('yyyy-MM-dd HH:mm').format(timestamp.toLocal());
  }
}
