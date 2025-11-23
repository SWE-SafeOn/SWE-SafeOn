import 'package:flutter/material.dart';

import '../models/device.dart';
import '../theme/app_theme.dart';
import '../widgets/status_chip.dart';

class DeviceDetailScreen extends StatefulWidget {
  const DeviceDetailScreen({super.key, required this.device});

  final SafeOnDevice device;

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  bool _isStreamingEnabled = true;
  bool _isTwoWayAudioEnabled = false;
  bool _isPrivacyShutterEnabled = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.device.displayName),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: SafeOnColors.surface,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 36,
                        backgroundColor: SafeOnColors.primary.withOpacity(0.12),
                        child: const Icon(Icons.videocam_outlined, size: 36, color: SafeOnColors.primary),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.device.locationLabel, style: theme.textTheme.bodyMedium),
                            const SizedBox(height: 4),
                            Text(
                              widget.device.displayName,
                              style: theme.textTheme.headlineSmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  StatusChip(
                    label: widget.device.status,
                    icon: Icons.verified_user,
                    color: widget.device.isOnline ? SafeOnColors.success : SafeOnColors.danger,
                  ),
                  const SizedBox(height: 18),
                  Text('Connection Strength', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: LinearProgressIndicator(
                      value: widget.device.connectionStrength,
                      minHeight: 10,
                      backgroundColor: SafeOnColors.scaffold,
                      color: SafeOnColors.primary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${(widget.device.connectionStrength * 100).round()}% connected',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Text('Live insights', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            _buildInsightTile(
              icon: Icons.timeline,
              title: 'Activity timeline',
              description: 'No unusual activity in the last 24 hours. Motion captured twice today.',
              actionLabel: 'View logs',
            ),
            _buildInsightTile(
              icon: Icons.cloud_outlined,
              title: 'Cloud backup',
              description: 'Video footage automatically synced to secure SafeOn cloud vault.',
              actionLabel: 'Manage storage',
            ),
            _buildInsightTile(
              icon: Icons.sensors_outlined,
              title: 'Automation routines',
              description: 'Camera is part of "Night Guard" and "Weekend Away" routines.',
              actionLabel: 'Edit routines',
            ),
            const SizedBox(height: 32),
            Text('Device controls', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            _buildControlTile(
              title: 'Streaming',
              subtitle: 'Live feed enabled',
              trailing: Switch(
                  value: _isStreamingEnabled,
                  onChanged: (value) {
                    setState(() {
                      _isStreamingEnabled = value;
                  });
                },
                activeThumbColor: SafeOnColors.primary,
              ),
            ),
            _buildControlTile(
              title: 'Two-way audio',
              subtitle: 'Respond instantly through built-in speaker',
              trailing: Switch(
                value: _isTwoWayAudioEnabled,
                onChanged: (value) {
                  setState(() {
                    _isTwoWayAudioEnabled = value;
                  });
                },
                activeThumbColor: SafeOnColors.primary,
              ),
            ),
            _buildControlTile(
              title: 'Privacy shutter',
              subtitle: 'Auto closes when family arrives home',
              trailing: Switch(
                value: _isPrivacyShutterEnabled,
                onChanged: (value) {
                  setState(() {
                    _isPrivacyShutterEnabled = value;
                  });
                },
                activeThumbColor: SafeOnColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInsightTile({
    required IconData icon,
    required String title,
    required String description,
    required String actionLabel,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: SafeOnColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: SafeOnColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: SafeOnColors.primary),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                onPressed: () {},
                child: Text(actionLabel),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            description,
            style: const TextStyle(fontSize: 15, color: SafeOnColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildControlTile({
    required String title,
    required String subtitle,
    required Widget trailing,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: SafeOnColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: SafeOnColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 15,
                    color: SafeOnColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}
