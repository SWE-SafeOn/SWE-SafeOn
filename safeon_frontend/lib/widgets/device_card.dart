import 'package:flutter/material.dart';

import '../models/device.dart';
import '../theme/app_theme.dart';
import 'status_chip.dart';

class DeviceCard extends StatelessWidget {
  const DeviceCard({
    super.key,
    required this.device,
    this.onTap,
  });

  final SafeOnDevice device;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(
          color: SafeOnColors.surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: SafeOnColors.primary.withOpacity(0.1),
                    child: Icon(
                      _iconFromName(device.icon),
                      size: 32,
                      color: SafeOnColors.primary,
                    ),
                  ),
                  const Spacer(),
                  StatusChip(
                    label: device.status,
                    icon: Icons.shield_moon,
                    color: device.isOnline
                        ? SafeOnColors.success
                        : SafeOnColors.danger,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                device.displayName,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                device.locationLabel,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: LinearProgressIndicator(
                  value: device.connectionStrength,
                  minHeight: 8,
                  backgroundColor: SafeOnColors.scaffold,
                  color: SafeOnColors.primary,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Connection',
                    style: theme.textTheme.labelMedium,
                  ),
                  Text(
                    '${(device.connectionStrength * 100).round()}%',
                    style: theme.textTheme.labelMedium?.copyWith(
                          color: SafeOnColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

IconData _iconFromName(String name) {
  switch (name) {
    case 'camera':
      return Icons.videocam_outlined;
    case 'hub':
      return Icons.router_outlined;
    case 'lock':
      return Icons.lock_outline;
    case 'sensor':
      return Icons.sensors_outlined;
    default:
      return Icons.devices_other_outlined;
  }
}
