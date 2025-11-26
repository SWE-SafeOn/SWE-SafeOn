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
        : 'None';


    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SecurityGraphCard(
            name: _profile.name,
            alertCount: alertCount,
            onlineDevices: onlineDevices,
          ),
          const SizedBox(height: 22),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              _InsightCard(
                title: '총 기기 수',
                value: '$totalDevices',
                caption: '$onlineDevices online',
                icon: Icons.podcasts,
                accent: SafeOnColors.primary,
                onTap: () => setState(() => _selectedIndex = 2),
              ),
              _InsightCard(
                title: '네트워크 상태',
                value: '정상',
                caption: '모든 서비스 정상',
                icon: Icons.verified_user,
                accent: SafeOnColors.success,
              ),
              _InsightCard(
                title: '누적 알림',
                value: '$alertCount',
                caption: '마지막: $lastAlertLabel',
                icon: Icons.warning_amber,
                accent: SafeOnColors.accent,
                onTap: () => setState(() => _selectedIndex = 1),
              ),
              _InsightCard(
                title: '최근 알림 수집',
                value: '${_alerts.length}',
                caption: '최근 24h 기록',
                icon: Icons.wifi_tethering,
                accent: SafeOnColors.primaryVariant,
              ),
            ],
          ),
          const SizedBox(height: 28),
          SectionHeader(
            title: 'Featured Devices',
            actionLabel: 'View all',
            onActionTap: () => setState(() => _selectedIndex = 2),
          ),
          const SizedBox(height: 14),
          if (_devices.isEmpty)
            _buildInlineEmptyState(
              context: context,
              icon: Icons.devices_other_outlined,
              title: '아직 연결된 기기가 없어요',
              description: '허브에서 기기를 등록하면 기기 상태를 빠르게 확인할 수 있어요.',
              actionLabel: '허브에서 등록하기',
              onActionTap: () => setState(() => _selectedIndex = 2),
            )
          else
            SizedBox(
              height: 210,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: _devices.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (context, index) {
                  final device = _devices[index];
                  return SizedBox(
                    width: 280,
                    child: DeviceCard(
                      device: device,
                      onTap: () => _openDeviceDetail(device),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 18),
          SectionHeader(
            title: 'Latest Alerts',
            actionLabel: 'See history',
            onActionTap: () => setState(() => _selectedIndex = 1),
          ),
          const SizedBox(height: 12),
          if (_alerts.isEmpty)
            _buildInlineEmptyState(
              context: context,
              icon: Icons.notifications_none_outlined,
              title: '최근 알림이 없어요',
              description: '새로운 알림이 들어오면 이곳에서 바로 확인할 수 있어요.',
              actionLabel: '알림 기록 보기',
              onActionTap: () => setState(() => _selectedIndex = 1),
            )
          else
            ..._alerts
                .map(
                  (alert) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AlertTile(alert: alert),
                  ),
                )
                .toList(),
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

  Widget _buildInlineEmptyState({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String description,
    String? actionLabel,
    VoidCallback? onActionTap,
  }) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SafeOnColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: SafeOnColors.primary.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: SafeOnColors.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: SafeOnColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: SafeOnColors.textSecondary,
                  ),
                ),
                if (actionLabel != null && onActionTap != null) ...[
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: onActionTap,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      foregroundColor: SafeOnColors.primary,
                    ),
                    child: Text(actionLabel),
                  ),
                ],
              ],
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

const _securityGraphCounts = <int>[24, 18, 32, 28, 36, 22, 14]; // Mon-Sun
const _weekdaySymbolsKo = ['월', '화', '수', '목', '금', '토', '일'];

class _WeekContext {
  _WeekContext({
    required this.month,
    required this.weekOfMonth,
    required this.dayLabels,
  });

  final int month;
  final int weekOfMonth;
  final List<String> dayLabels;

  factory _WeekContext.fromDate(DateTime date) {
    final local = DateTime(date.year, date.month, date.day);
    final startOfWeek = local.subtract(Duration(days: (local.weekday + 6) % 7)); // Monday as 0
    final days = List.generate(7, (i) => startOfWeek.add(Duration(days: i)));

    final firstOfMonth = DateTime(local.year, local.month, 1);
    final firstWeekdayOffset = (firstOfMonth.weekday + 6) % 7; // 0-based, Monday start
    final dayIndex = local.day + firstWeekdayOffset - 1;
    final weekOfMonth = (dayIndex / 7).floor() + 1;

    return _WeekContext(
      month: local.month,
      weekOfMonth: weekOfMonth,
      dayLabels: days.map((d) => _weekdaySymbolsKo[(d.weekday + 6) % 7]).toList(),
    );
  }
}

class _SecurityGraphCard extends StatefulWidget {
  const _SecurityGraphCard({
    required this.name,
    required this.alertCount,
    required this.onlineDevices,
  });

  final String name;
  final int alertCount;
  final int onlineDevices;

  @override
  State<_SecurityGraphCard> createState() => _SecurityGraphCardState();
}

class _SecurityGraphCardState extends State<_SecurityGraphCard> {
  int? _hoveredIndex;
  double? _hoverDx;
  _WeekContext? _cachedWeekContext;

  _WeekContext get _weekContext =>
      _cachedWeekContext ??= _WeekContext.fromDate(DateTime.now());

  void _updateHover(double dx, double width) {
    final step = width / (_securityGraphCounts.length - 1);
    final index = (dx / step).round().clamp(0, _securityGraphCounts.length - 1);

    setState(() {
      _hoveredIndex = index;
      _hoverDx = dx.clamp(0, width);
    });
  }

  void _clearHover() {
    if (_hoveredIndex != null || _hoverDx != null) {
      setState(() {
        _hoveredIndex = null;
        _hoverDx = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final points = _securityGraphCounts;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF0B1224)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.22),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: SafeOnColors.accent,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: SafeOnColors.accent.withOpacity(0.5),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Live security pulse',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                'Hello, ${widget.name}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white70,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '${_weekContext.month}월 ${_weekContext.weekOfMonth}주차',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '이번주 안전 탐지 현황',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white70,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 190,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final graphWidth = constraints.maxWidth;

                return MouseRegion(
                  onHover: (event) => _updateHover(event.localPosition.dx, graphWidth),
                  onExit: (_) => _clearHover(),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (details) => _updateHover(details.localPosition.dx, graphWidth),
                    onPanUpdate: (details) => _updateHover(details.localPosition.dx, graphWidth),
                    onPanEnd: (_) => _clearHover(),
                    child: Stack(
                      children: [
                        CustomPaint(
                          painter: _SecurityLinePainter(
                            points: points.map((point) => point.toDouble()).toList(),
                            strokeColor: SafeOnColors.primary,
                            fillColor: SafeOnColors.primary.withOpacity(0.24),
                            highlightIndex: _hoveredIndex,
                          ),
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                            alignment: Alignment.bottomLeft,
                            child: Text(
                              'SafeOn Detection Count',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: Colors.white70,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                        if (_hoveredIndex != null && _hoverDx != null)
                          Positioned(
                            left: (_hoverDx! - 48)
                                .clamp(0, graphWidth > 96 ? graphWidth - 96 : 0),
                            top: 12,
                            child: _GraphTooltip(
                              label:
                                  '${_weekContext.dayLabels[_hoveredIndex!]} • ${points[_hoveredIndex!]}',
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          _WeekLegend(
            labels: _weekContext.dayLabels,
            counts: points,
            highlightIndex: _hoveredIndex,
          ),
          const SizedBox(height: 14),
          Column(
            children: [
              _GraphStat(
                label: 'Active devices',
                value: '${widget.onlineDevices}',
                chipColor: SafeOnColors.success,
              ),
              const SizedBox(height: 8),
              _GraphStat(
                label: 'Alerts today',
                value: '${widget.alertCount}',
                chipColor: SafeOnColors.accent,
              ),
              const SizedBox(height: 8),
              _GraphStat(
                label: 'Feed status',
                value: 'Simulated',
                chipColor: colorScheme.secondary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GraphStat extends StatelessWidget {
  const _GraphStat({
    required this.label,
    required this.value,
    required this.chipColor,
  });

  final String label;
  final String value;
  final Color chipColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: chipColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: Colors.white70,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _GraphTooltip extends StatelessWidget {
  const _GraphTooltip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.96),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(color: SafeOnColors.primary.withOpacity(0.25)),
      ),
      child: Text(
        label,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: SafeOnColors.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _WeekLegend extends StatelessWidget {
  const _WeekLegend({
    required this.labels,
    required this.counts,
    required this.highlightIndex,
  });

  final List<String> labels;
  final List<int> counts;
  final int? highlightIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(labels.length, (index) {
        final isActive = highlightIndex == index;
        return Expanded(
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: isActive ? Colors.white.withOpacity(0.14) : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.white.withOpacity(isActive ? 0.3 : 0.12),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      labels[index],
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: Colors.white70,
                        fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${counts[index]}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _SecurityLinePainter extends CustomPainter {
  _SecurityLinePainter({
    required this.points,
    required this.strokeColor,
    required this.fillColor,
    this.highlightIndex,
  });

  final List<double> points;
  final Color strokeColor;
  final Color fillColor;
  final int? highlightIndex;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final path = Path();
    final fillPath = Path();
    final maxPoint = points
        .reduce((a, b) => a > b ? a : b)
        .clamp(0.01, double.infinity)
        .toDouble();

    final dx = size.width / (points.length - 1);
    final firstY = size.height - (points.first / maxPoint) * size.height;
    final offsets = <Offset>[];

    path.moveTo(0, firstY);
    fillPath.moveTo(0, size.height);
    fillPath.lineTo(0, firstY);
    offsets.add(Offset(0, firstY));

    for (var i = 1; i < points.length; i++) {
      final x = dx * i;
      final y = size.height - (points[i] / maxPoint) * size.height;
      path.lineTo(x, y);
      fillPath.lineTo(x, y);
      offsets.add(Offset(x, y));
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        colors: [fillColor, Colors.transparent],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = strokeColor
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 0.8);

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, strokePaint);

    if (highlightIndex != null &&
        highlightIndex! >= 0 &&
        highlightIndex! < offsets.length) {
      final point = offsets[highlightIndex!];

      final glowPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = strokeColor.withOpacity(0.28);

      final dotPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = Colors.white;

      final innerDotPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = strokeColor;

      canvas.drawCircle(point, 10, glowPaint);
      canvas.drawCircle(point, 5.5, dotPaint);
      canvas.drawCircle(point, 3.6, innerDotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SecurityLinePainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.strokeColor != strokeColor ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.highlightIndex != highlightIndex;
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({
    required this.title,
    required this.value,
    required this.caption,
    required this.icon,
    required this.accent,
    this.onTap,
  });

  final String title;
  final String value;
  final String caption;
  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: (MediaQuery.of(context).size.width - 24 * 2 - 14) / 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: SafeOnColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: accent.withOpacity(0.18)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 16,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accent, size: 22),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: SafeOnColors.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: SafeOnColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                caption,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: SafeOnColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
        device: device,
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
                        return Center(
                          child: _DiscoveredDeviceError(
                            onRetry: _retryFetch,
                          )
                        );
                      }

                      final devices = snapshot.data ?? [];
                      if (devices.isEmpty) {
                        return Center(
                          child:
                              _DiscoveredDeviceEmptyState(onRetry: _retryFetch),
                        );
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
                        'MAC: ${device.macAddress}',
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
                _DeviceMetaChip(icon: Icons.qr_code, label: device.macAddress),
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
      crossAxisAlignment: CrossAxisAlignment.center,
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
          textAlign: TextAlign.center,
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
      crossAxisAlignment: CrossAxisAlignment.center,
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
