import 'package:characters/characters.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/alert.dart';
import '../models/device.dart';
import '../models/dashboard_overview.dart';
import '../models/user_profile.dart';
import '../models/user_session.dart';
import '../services/safeon_api.dart';
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
    required this.session,
    required this.apiClient,
  });

  final VoidCallback onLogout;
  final void Function(UserProfile updatedProfile) onProfileUpdated;
  final UserSession session;
  final SafeOnApiClient apiClient;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;
  late UserProfile _profile;
  DashboardOverview? _overview;
  List<SafeOnDevice> _devices = const [];
  List<SafeOnAlert> _alerts = const [];
  bool _isLoading = true;
  String? _errorMessage;
  bool _isNightlyAutoArmEnabled = true;
  bool _isHomeModeArmed = true;
  bool _isAutomationActive = true;
  MotionSensitivityLevel _motionSensitivityLevel = MotionSensitivityLevel.medium;
  bool _isPushnotificationsEnabled = true;
  

  @override
  void initState() {
    super.initState();
    _profile = widget.session.profile;
    _loadDashboard();
  }

  @override
  void didUpdateWidget(covariant DashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.profile != widget.session.profile) {
      _profile = widget.session.profile;
    }
  }

  String get _avatarLabel {
    final trimmed = _profile.name.trim();
    return trimmed.isNotEmpty ? trimmed.characters.first.toUpperCase() : 'S';
  }

  Future<void> _loadDashboard() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final token = widget.session.token;
      final overview = widget.apiClient.fetchDashboardOverview(token);
      final devices = widget.apiClient.fetchDashboardDevices(token);
      final alerts = widget.apiClient.fetchRecentAlerts(token, limit: 10);
      final results = await Future.wait([
        overview,
        devices,
        alerts,
      ]);

      if (!mounted) return;
      setState(() {
        _overview = results[0] as DashboardOverview;
        _devices = results[1] as List<SafeOnDevice>;
        _alerts = results[2] as List<SafeOnAlert>;
        _isLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '대시보드 데이터를 불러오지 못했습니다.';
        _isLoading = false;
      });
    }
  }

  Future<void> _openDiscoveredDevicesSheet() async {
    final claimedDevice = await showModalBottomSheet<SafeOnDevice>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: _DiscoveredDeviceSheet(
            apiClient: widget.apiClient,
            token: widget.session.token,
          ),
        );
      },
    );

    if (claimedDevice != null && mounted) {
      await _loadDashboard();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${claimedDevice.displayName} 기기를 등록했어요.'),
        ),
      );
    }
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
              'Welcome back, ${_profile.name}',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _openDiscoveredDevicesSheet,
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Add device',
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: CircleAvatar(
              radius: 18,
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
      body: RefreshIndicator(
        onRefresh: _loadDashboard,
        child: IndexedStack(
          index: _selectedIndex,
          children: [
            _buildHomeTab(context),
            _buildAlertsTab(context),
            _buildDevicesTab(context),
            _buildProfileTab(context),
          ],
        ),
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
    if (_isLoading) {
      return _buildLoadingPlaceholder();
    }

    if (_errorMessage != null) {
      return _buildErrorPlaceholder();
    }

    final overview = _overview;
    final totalDevices = overview?.totalDevices ?? 0;
    final onlineDevices = overview?.onlineDevices ?? 0;
    final alertCount = overview?.alertCount ?? 0;
    final lastAlertTime = overview?.lastAlertTime;
    final lastAlertLabel = lastAlertTime != null
        ? DateFormat('MM/dd HH:mm').format(lastAlertTime.toLocal())
        : 'No alerts yet';


    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
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
            children: [
              StatCard(
                title: '총 기기 수',
                value: '$totalDevices',
                delta: '$onlineDevices online',
                icon: Icons.podcasts,
              ),
              const StatCard(
                title: '네트워크 상태',
                value: '정상',
                delta: '모든 서비스 정상',
                icon: Icons.verified_user,
                color: SafeOnColors.success,
              ),
              StatCard(
                title: '누적 알림',
                value: '$alertCount',
                delta: '마지막: $lastAlertLabel',
                icon: Icons.warning_amber,
                color: SafeOnColors.accent,
              ),
              StatCard(
                title: '최근 알림 수집',
                value: '${_alerts.length}',
                delta: '최근 24h 기록',
                icon: Icons.wifi_tethering,
              ),
            ],
          ),
          const SizedBox(height: 32),
          SectionHeader(
            title: 'Featured Devices',
            actionLabel: 'View all',
            onActionTap: () => setState(() => _selectedIndex = 2),
          ),
          const SizedBox(height: 16),
          if (_devices.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: SafeOnColors.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text('연결된 기기가 없습니다. 허브에서 기기를 등록해주세요.'),
            )
          else
            ..._devices
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
          SectionHeader(
            title: 'Latest Alerts',
            actionLabel: 'See history',
            onActionTap: () => setState(() => _selectedIndex = 1),
          ),
          const SizedBox(height: 12),
          if (_alerts.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: SafeOnColors.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text('최근 알림이 없습니다.'),
            )
          else
            ..._alerts.map((alert) => AlertTile(alert: alert)).toList(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildAlertsTab(BuildContext context) {
    if (_isLoading) {
      return _buildLoadingPlaceholder();
    }
    if (_errorMessage != null) {
      return _buildErrorPlaceholder();
    }
    if (_alerts.isEmpty) {
      return _buildEmptyList('표시할 알림이 없습니다.');
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      itemCount: _alerts.length,
      itemBuilder: (context, index) => AlertTile(alert: _alerts[index]),
    );
  }

  Widget _buildDevicesTab(BuildContext context) {
    if (_isLoading) {
      return _buildLoadingPlaceholder();
    }
    if (_errorMessage != null) {
      return _buildErrorPlaceholder();
    }
    if (_devices.isEmpty) {
      return _buildEmptyList('등록된 디바이스가 없습니다.');
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      itemCount: _devices.length,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: DeviceCard(
          device: _devices[index],
          onTap: () => _openDeviceDetail(_devices[index]),
        ),
      ),
    );
  }

  Widget _buildProfileTab(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
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
                      Text(_profile.name, style: theme.textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Text(_profile.email, style: theme.textTheme.bodyMedium),
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

  Widget _buildLoadingPlaceholder() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: const [
        SizedBox(height: 240),
        Center(child: CircularProgressIndicator()),
        SizedBox(height: 240),
      ],
    );
  }

  Widget _buildErrorPlaceholder() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      children: [
        Column(
          children: [
            const Icon(Icons.error_outline, size: 48, color: SafeOnColors.danger),
            const SizedBox(height: 12),
            Text(
              _errorMessage ?? '데이터를 불러올 수 없습니다.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadDashboard,
              child: const Text('다시 시도'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEmptyList(String message) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: SafeOnColors.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(message),
        ),
      ],
    );
  }

  Future<void> _openProfileEditor() async {
    final result = await Navigator.of(context).push<ProfileDetails>(
      MaterialPageRoute(
        builder: (_) => ProfileEditScreen(
          initialEmail: _profile.email,
          initialName: _profile.name,
        ),
      ),
    );

    if (result == null) {
      return;
    }

    try {
      final updatedProfile = await widget.apiClient.updateProfile(
        token: widget.session.token,
        name: result.name,
        password: result.password,
      );
      if (!mounted) return;
      setState(() {
        _profile = updatedProfile;
      });
      widget.onProfileUpdated(updatedProfile);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('프로필이 업데이트되었습니다.')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('프로필 업데이트 중 오류가 발생했습니다.')),
      );
    }
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

class _DiscoveredDeviceSheet extends StatefulWidget {
  const _DiscoveredDeviceSheet({
    required this.apiClient,
    required this.token,
  });

  final SafeOnApiClient apiClient;
  final String token;

  @override
  State<_DiscoveredDeviceSheet> createState() => _DiscoveredDeviceSheetState();
}

class _DiscoveredDeviceSheetState extends State<_DiscoveredDeviceSheet> {
  late Future<List<SafeOnDevice>> _discoveredDevicesFuture;
  final Set<String> _claimingDeviceIds = {};

  @override
  void initState() {
    super.initState();
    _discoveredDevicesFuture =
        widget.apiClient.fetchDiscoveredDevices(widget.token);
  }

  void _retryFetch() {
    setState(() {
      _discoveredDevicesFuture =
          widget.apiClient.fetchDiscoveredDevices(widget.token);
    });
  }

  Future<void> _claimDevice(SafeOnDevice device) async {
    if (_claimingDeviceIds.contains(device.id)) return;

    setState(() {
      _claimingDeviceIds.add(device.id);
    });

    try {
      final claimed = await widget.apiClient.claimDevice(
        token: widget.token,
        deviceId: device.id,
      );
      if (!mounted) return;
      Navigator.of(context).pop(claimed);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('기기 등록에 실패했습니다. 다시 시도해주세요.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _claimingDeviceIds.remove(device.id);
        });
      }
    }
  }

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
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.7,
            child: Column(
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
                '새로 발견된 기기',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Hub Agent에서 감지된 기기를 선택해 등록하세요.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: SafeOnColors.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
                Expanded(
                  child: FutureBuilder<List<SafeOnDevice>>(
                    future: _discoveredDevicesFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState ==
                          ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      }

                      if (snapshot.hasError) {
                        return _DiscoveredDeviceError(
                          onRetry: _retryFetch,
                        );
                      }

                      final devices = snapshot.data ?? [];
                      if (devices.isEmpty) {
                        return _DiscoveredDeviceEmptyState(onRetry: _retryFetch);
                      }

                      return ListView.separated(
                        itemCount: devices.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 14),
                        itemBuilder: (context, index) {
                          final device = devices[index];
                          final isClaiming =
                              _claimingDeviceIds.contains(device.id);
                          return _DiscoveredDeviceTile(
                            device: device,
                            isClaiming: isClaiming,
                            onClaim: () => _claimDevice(device),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DiscoveredDeviceTile extends StatelessWidget {
  const _DiscoveredDeviceTile({
    required this.device,
    required this.onClaim,
    required this.isClaiming,
  });

  final SafeOnDevice device;
  final VoidCallback onClaim;
  final bool isClaiming;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: SafeOnColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: SafeOnColors.primary.withOpacity(0.12),
                  child: Icon(
                    Icons.sensors,
                    color: SafeOnColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.displayName,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Vendor: ${device.vendor}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: SafeOnColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _DeviceMetaChip(icon: Icons.language, label: device.ip),
                const SizedBox(width: 8),
                _DeviceMetaChip(icon: Icons.qr_code, label: device.macAddr),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isClaiming ? null : onClaim,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: isClaiming
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('등록하기'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiscoveredDeviceEmptyState extends StatelessWidget {
  const _DiscoveredDeviceEmptyState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: SafeOnColors.primary.withOpacity(0.08),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.hub,
            size: 32,
            color: SafeOnColors.primary,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '허브가 새로운 기기를 찾지 못했어요.',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(
          'Hub Agent가 새 기기를 감지하면 여기에 표시됩니다.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: SafeOnColors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('새로고침'),
        ),
      ],
    );
  }
}

class _DiscoveredDeviceError extends StatelessWidget {
  const _DiscoveredDeviceError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          Icons.error_outline,
          color: SafeOnColors.danger,
          size: 36,
        ),
        const SizedBox(height: 8),
        Text(
          '발견된 기기를 불러올 수 없습니다.',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          '네트워크 연결을 확인한 후 다시 시도해주세요.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: SafeOnColors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('다시 시도'),
        ),
      ],
    );
  }
}
class _DeviceMetaChip extends StatelessWidget {
  const _DeviceMetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: SafeOnColors.scaffold,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: SafeOnColors.textSecondary),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: SafeOnColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}