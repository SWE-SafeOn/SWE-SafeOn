import 'package:characters/characters.dart';
import 'package:flutter/material.dart';

import '../models/alert.dart';
import '../models/device.dart';
import '../theme/app_theme.dart';
import '../widgets/alert_tile.dart';
import '../widgets/device_card.dart';
import '../widgets/section_header.dart';
import '../widgets/stat_card.dart';
import '../widgets/status_chip.dart';
import 'profile_edit_screen.dart';
import 'device_detail_screen.dart';

enum MotionSensitivityLevel { low, medium, high }

extension MotionSensitivityLevelX on MotionSensitivityLevel {
  String get label {
    switch (this) {
      case MotionSensitivityLevel.low:
        return 'Low';
      case MotionSensitivityLevel.medium:
        return 'Medium';
      case MotionSensitivityLevel.high:
        return 'High';
    }
  }

  String get description =>
      '$label sensitivity configured for all indoor sensors';

  Color get color {
    switch (this) {
      case MotionSensitivityLevel.low:
        return SafeOnColors.success;
      case MotionSensitivityLevel.medium:
        return SafeOnColors.warning;
      case MotionSensitivityLevel.high:
        return SafeOnColors.danger;
    }
  }

  Color get selectedTextColor {
    switch (this) {
      case MotionSensitivityLevel.medium:
        return SafeOnColors.textPrimary;
      case MotionSensitivityLevel.low:
        return SafeOnColors.textPrimary;
      case MotionSensitivityLevel.high:
        return SafeOnColors.textPrimary;
    }
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.onLogout,
    required this.onProfileUpdated,
    required this.userEmail,
    required this.userNickname,
    required this.userPassword,
  });

  final VoidCallback onLogout;
  final void Function(String email, String password, String nickname)
      onProfileUpdated;
  final String userEmail;
  final String userNickname;
  final String userPassword;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;
  late String _email;
  late String _nickname;
  late String _password;
  bool _isNightlyAutoArmEnabled = true;
  bool _isHomeModeArmed = true;
  bool _isAutomationActive = true;
  MotionSensitivityLevel _motionSensitivityLevel = MotionSensitivityLevel.medium;
  bool _isPushnotificationsEnabled = true;
  

  @override
  void initState() {
    super.initState();
    _email = widget.userEmail;
    _nickname = widget.userNickname;
    _password = widget.userPassword;
  }

  @override
  void didUpdateWidget(covariant DashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userEmail != widget.userEmail ||
        oldWidget.userNickname != widget.userNickname ||
        oldWidget.userPassword != widget.userPassword) {
      _email = widget.userEmail;
      _nickname = widget.userNickname;
      _password = widget.userPassword;
    }
  }

  String get _avatarLabel {
    final trimmed = _nickname.trim();
    return trimmed.isNotEmpty ? trimmed.characters.first.toUpperCase() : 'S';
  }

  final List<SafeOnDevice> devices = [
    const SafeOnDevice(
      name: 'Front Door Camera',
      location: 'Entrance Hall',
      status: 'Secure',
      connectionStrength: 0.82,
      isOnline: true,
      icon: 'camera',
    ),
    const SafeOnDevice(
      name: 'Living Room Hub',
      location: 'Living Area',
      status: 'Monitoring',
      connectionStrength: 0.67,
      isOnline: true,
      icon: 'hub',
    ),
  ];

  final List<SafeOnAlert> alerts = [
    SafeOnAlert(
      title: 'Unrecognized motion detected',
      description:
          'Motion detected near the backyard door at 10:14 PM. Reviewing footage now.',
      timestamp: DateTime.now().subtract(const Duration(minutes: 8)),
      severity: AlertSeverity.high,
    ),
    SafeOnAlert(
      title: 'Device health warning',
      description: 'Battery level low on Garage Sensor. Consider replacing soon.',
      timestamp: DateTime.now().subtract(const Duration(hours: 3, minutes: 22)),
      severity: AlertSeverity.medium,
    ),
  ];

  Future<void> _openQrAddDeviceSheet() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: _QrAddDeviceSheet(
            onStartScan: () {
              Navigator.of(sheetContext).pop();
              scaffoldMessenger.showSnackBar(
                const SnackBar(
                  content: Text(
                    'QR 기반 디바이스 추가 기능을 곧 제공할 예정입니다.',
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SafeOn Home',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 2),
            Text(
              'Welcome back, $_nickname',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _openQrAddDeviceSheet,
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Add device',
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: CircleAvatar(
              radius: 18,
              // ignore: deprecated_member_use
              backgroundColor: SafeOnColors.primary.withOpacity(0.2),
              child: Text(
                _avatarLabel,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: SafeOnColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildHomeTab(context),
          _buildAlertsTab(context),
          _buildDevicesTab(context),
          _buildProfileTab(context),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.warning_amber_rounded),
            label: 'Alerts',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.devices_other_outlined),
            label: 'Devices',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  Widget _buildHomeTab(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                StatusChip(
                  label: _isHomeModeArmed
                      ? 'Home Mode: Armed'
                      : 'Home Mode: Disarmed',
                  icon: _isHomeModeArmed
                      ? Icons.lock_outline
                      : Icons.lock_open_outlined,
                  color: _isHomeModeArmed
                      ? SafeOnColors.primary
                      : SafeOnColors.warning,
                ),
                const SizedBox(width: 12),
                StatusChip(
                  label: _isAutomationActive
                      ? 'Automation Active'
                      : 'Automation Paused',
                  icon: _isAutomationActive
                      ? Icons.auto_mode
                      : Icons.pause_circle_outline,
                  color: _isAutomationActive
                      ? SafeOnColors.primary
                      : SafeOnColors.danger,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 0.96,
            children: const [
              StatCard(
                title: 'Active Devices',
                value: '12',
                delta: '+2 online',
                icon: Icons.podcasts,
              ),
              StatCard(
                title: 'Incidents Resolved',
                value: '28',
                delta: '98% success',
                icon: Icons.verified_user,
                color: SafeOnColors.success,
              ),
              StatCard(
                title: 'Energy Usage',
                value: '64%',
                delta: '-6% today',
                icon: Icons.energy_savings_leaf,
                color: SafeOnColors.accent,
              ),
              StatCard(
                title: 'Network Health',
                value: 'Excellent',
                delta: 'All systems',
                icon: Icons.wifi_tethering,
              ),
            ],
          ),
          const SizedBox(height: 32),
          const SectionHeader(title: 'Featured Devices', actionLabel: 'View all'),
          const SizedBox(height: 16),
          ...devices
              .map(
                (device) => Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: DeviceCard(
                    device: device,
                    onTap: () => _openDeviceDetail(device),
                  ),
                ),
              )
              .toList(),
          const SizedBox(height: 12),
          const SectionHeader(title: 'Latest Alerts', actionLabel: 'See history'),
          const SizedBox(height: 12),
          ...alerts.map((alert) => AlertTile(alert: alert)).toList(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildAlertsTab(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      itemCount: alerts.length,
      itemBuilder: (context, index) => AlertTile(alert: alerts[index]),
    );
  }

  Widget _buildDevicesTab(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      itemCount: devices.length,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: DeviceCard(
          device: devices[index],
          onTap: () => _openDeviceDetail(devices[index]),
        ),
      ),
    );
  }

  Widget _buildProfileTab(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
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
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: SafeOnColors.primary.withOpacity(0.2),
                  child: Text(
                    _avatarLabel,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: SafeOnColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_nickname, style: theme.textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Text(_email, style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _openProfileEditor,
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('Security preferences', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          _buildSettingTile(
            icon: _isHomeModeArmed
                ? Icons.lock_outline
                : Icons.lock_open_outlined,
            title: 'Home mode',
            subtitle: _isHomeModeArmed
                ? 'System armed and monitoring'
                : 'System disarmed',
            trailing: Switch(
              value: _isHomeModeArmed,
              onChanged: (value) {
                setState(() {
                  _isHomeModeArmed = value;
                });
              },
              activeColor: SafeOnColors.primary,
              activeTrackColor: SafeOnColors.primary.withOpacity(0.3),
            ),
          ),
          _buildSettingTile(
            icon: Icons.lock_clock,
            title: 'Daily auto-arm',
            subtitle: _isNightlyAutoArmEnabled
                ? 'Arms SafeOn everyday'
                : 'Auto-arm schedule paused',
            trailing: Switch(
              value: _isNightlyAutoArmEnabled,
              onChanged: (value) {
                setState(() {
                  _isNightlyAutoArmEnabled = value;
                });
              },
              activeColor: SafeOnColors.primary,
              activeTrackColor: SafeOnColors.primary.withOpacity(0.3),
            ),
          ),
          _buildSettingTile(
            icon: Icons.sensors,
            title: 'Motion sensitivity',
            subtitle: _motionSensitivityLevel.description,
            trailing: _MotionSensitivitySelector(
              selectedLevel: _motionSensitivityLevel,
              onChanged: (level) {
                setState(() {
                  _motionSensitivityLevel = level;
                });
              },
            ),
          ),
          _buildSettingTile(
            icon:
                _isAutomationActive ? Icons.auto_mode : Icons.pause_circle_outline,
            title: 'Automation routines',
            subtitle: _isAutomationActive
                ? 'Routines running as scheduled'
                : 'Automation temporarily paused',
            trailing: Switch(
              value: _isAutomationActive,
              onChanged: (value) {
                setState(() {
                  _isAutomationActive = value;
                });
              },
              activeColor: SafeOnColors.primary,
              activeTrackColor: SafeOnColors.primary.withOpacity(0.3),
            ),
          ),
          _buildSettingTile(
            icon: Icons.notifications_active_outlined,
            title: 'Push notifications',
            subtitle: _isPushnotificationsEnabled
                ? 'Alerts and system updates'
                : 'Alerts and system turned off',
            trailing: Switch(
              value: _isPushnotificationsEnabled,
              onChanged: (value) {
                setState((){
                  _isPushnotificationsEnabled = value;
                });
              },
              activeColor: SafeOnColors.primary,
              activeTrackColor: SafeOnColors.primary.withOpacity(0.3),
            ),
          ),
          const SizedBox(height: 32),
          Text('Account Management', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _onLogoutPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: SafeOnColors.danger,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.logout),
              label: const Text('Log out'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openProfileEditor() async {
    final result = await Navigator.of(context).push<ProfileDetails>(
      MaterialPageRoute(
        builder: (_) => ProfileEditScreen(
          initialEmail: _email,
          initialPassword: _password,
          initialNickname: _nickname,
        ),
      ),
    );

    if (result == null) {
      return;
    }

    setState(() {
      _email = result.email;
      _password = result.password;
      _nickname = result.nickname;
    });

    widget.onProfileUpdated(result.email, result.password, result.nickname);
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget trailing,
  }) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      decoration: BoxDecoration(
        color: SafeOnColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: SafeOnColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: SafeOnColors.primary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }

  void _openDeviceDetail(SafeOnDevice device) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => DeviceDetailScreen(device: device),
      ),
    );
  }

  Future<void> _onLogoutPressed() async {
    final shouldLogout = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Log Out?'),
            content: const Text('Once logged out, you will need to complete the onboarding process again.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: SafeOnColors.danger,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Log out'),
              ),
            ],
          ),
        ) ??
        false;

    if (shouldLogout) {
      widget.onLogout();
    }
  }
}

class _MotionSensitivitySelector extends StatelessWidget {
  const _MotionSensitivitySelector({
    required this.selectedLevel,
    required this.onChanged,
  });

  final MotionSensitivityLevel selectedLevel;
  final ValueChanged<MotionSensitivityLevel> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backgroundColor = selectedLevel.color.withOpacity(0.24);
    final borderColor = selectedLevel.color.withOpacity(0.5);
    final textStyle = theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w600,
      color: selectedLevel.selectedTextColor,
    );

    return PopupMenuButton<MotionSensitivityLevel>(
      initialValue: selectedLevel,
      onSelected: onChanged,
      tooltip: 'Change motion sensitivity',
      itemBuilder: (context) {
        return MotionSensitivityLevel.values.map((level) {
          final isCurrent = level == selectedLevel;
          return PopupMenuItem<MotionSensitivityLevel>(
            value: level,
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: level.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    level.label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight:
                          isCurrent ? FontWeight.w700 : FontWeight.w500,
                      color: isCurrent
                          ? SafeOnColors.textPrimary
                          : SafeOnColors.textSecondary,
                    ),
                  ),
                ),
                if (isCurrent)
                  const Icon(
                    Icons.check,
                    size: 18,
                    color: SafeOnColors.textSecondary,
                  ),
              ],
            ),
          );
        }).toList();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(selectedLevel.label, style: textStyle),
            const SizedBox(width: 6),
            Icon(
              Icons.keyboard_arrow_down,
              color: selectedLevel.selectedTextColor,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _QrAddDeviceSheet extends StatelessWidget {
  const _QrAddDeviceSheet({
    required this.onStartScan,
  });

  final VoidCallback onStartScan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 24,
            offset: const Offset(0, -12),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 48,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.onSurface.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Scan QR code',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Place the device\'s QR code inside the frame to begin pairing.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: SafeOnColors.textSecondary,
                ),
              ),
              const SizedBox(height: 24),
              const _QrInstructionTile(
                icon: Icons.qr_code_scanner,
                title: 'Find the pairing label',
                description:
                    'Look for the SafeOn QR code sticker on the device or packaging.',
              ),
              const SizedBox(height: 16),
              const _QrInstructionTile(
                icon: Icons.light_mode_outlined,
                title: 'Ensure good lighting',
                description:
                    'Bright, glare-free lighting helps the camera read the code quickly.',
              ),
              const SizedBox(height: 16),
              const _QrInstructionTile(
                icon: Icons.wifi,
                title: 'Stay near your hub',
                description:
                    'Remain close to your SafeOn hub for a seamless hand-off.',
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onStartScan,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Start QR scan'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QrInstructionTile extends StatelessWidget {
  const _QrInstructionTile({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 44,
          width: 44,
          decoration: BoxDecoration(
            color: SafeOnColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: SafeOnColors.primary),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: SafeOnColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}