import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/alert.dart';
import '../models/device.dart';
import '../models/dashboard_overview.dart';
import '../models/daily_anomaly_count.dart';
import '../models/user_profile.dart';
import '../models/user_session.dart';
import '../services/safeon_api.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/alert_tile.dart';
import '../widgets/device_card.dart';
import '../widgets/section_header.dart';
import '../widgets/security_graph_card.dart';
import 'profile_edit_screen.dart';
import 'device_detail_screen.dart';

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
  List<DailyAnomalyCount> _dailyAnomalyCounts = const [];
  final Set<String> _knownAlertIds = {};
  bool _hasLoadedInitialAlerts = false;
  bool _isLoading = true;
  String? _errorMessage;
  bool _isNightlyAutoArmEnabled = true;
  bool _isHomeModeArmed = true;
  bool _isAutomationActive = true;
  bool _isPushnotificationsEnabled = true;
  bool _isUpdatingPushNotifications = false;
  bool _isUpdatingHomeMode = false;
  Timer? _alertPollingTimer;
  static const Duration _alertPollingInterval = Duration(seconds: 30);
  bool _isPollingAlerts = false;
  late DateTime _currentWeekStart;
  

  @override
  void initState() {
    super.initState();
    _profile = widget.session.profile;
    _currentWeekStart = _startOfWeek(DateTime.now());
    _loadDashboard();
    _startAlertPolling();
  }

  @override
  void didUpdateWidget(covariant DashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.profile != widget.session.profile) {
      _profile = widget.session.profile;
    }
  }

  @override
  void dispose() {
    _alertPollingTimer?.cancel();
    super.dispose();
  }

  String get _avatarLabel {
    final trimmed = _profile.name.trim();
    return trimmed.isNotEmpty ? trimmed.substring(0, 1).toUpperCase() : 'S';
  }

  Future<void> _loadDashboard() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final weekStart = _startOfWeek(DateTime.now());
      final weekEnd = weekStart.add(const Duration(days: 6));

      final token = widget.session.token;
      final overview = widget.apiClient.fetchDashboardOverview(token);
      final devices = widget.apiClient.fetchDashboardDevices(token);
      final alerts = widget.apiClient.fetchRecentAlerts(token, limit: 10);
      final anomalies = widget.apiClient
          .fetchDailyAnomalyCounts(
            token,
            startDate: weekStart,
            endDate: weekEnd,
          )
          .catchError((_) => <DailyAnomalyCount>[]);
      final results = await Future.wait([
        overview,
        devices,
        alerts,
        anomalies,
      ]);

      final fetchedAlerts = results[2] as List<SafeOnAlert>;
      final newAlerts = _computeNewAlerts(fetchedAlerts);

      if (!mounted) return;
      setState(() {
        _overview = results[0] as DashboardOverview;
        _devices = results[1] as List<SafeOnDevice>;
        _alerts = fetchedAlerts;
        _dailyAnomalyCounts = results[3] as List<DailyAnomalyCount>;
        _currentWeekStart = weekStart;
        _knownAlertIds
          ..clear()
          ..addAll(fetchedAlerts.map((alert) => alert.id));
        _hasLoadedInitialAlerts = true;
        _isLoading = false;
      });

      if (_isPushnotificationsEnabled && newAlerts.isNotEmpty) {
        for (final alert in newAlerts) {
          await NotificationService.showAlertNotification(alert);
        }
      }
      _startAlertPolling();
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

  void _startAlertPolling() {
    _alertPollingTimer?.cancel();
    _alertPollingTimer = Timer.periodic(
      _alertPollingInterval,
      (_) => _pollForNewAlerts(),
    );
  }

  Future<void> _pollForNewAlerts() async {
    if (!_hasLoadedInitialAlerts || _isPollingAlerts || !mounted) {
      return;
    }

    _isPollingAlerts = true;
    try {
      final alerts = await widget.apiClient
          .fetchRecentAlerts(widget.session.token, limit: 10);
      if (!mounted) return;

      final newAlerts = _computeNewAlerts(alerts);
      setState(() {
        _alerts = alerts;
        _knownAlertIds.addAll(alerts.map((alert) => alert.id));
      });

      if (_isPushnotificationsEnabled && newAlerts.isNotEmpty) {
        for (final alert in newAlerts) {
          await NotificationService.showAlertNotification(alert);
        }
      }
    } on ApiException {
      // Polling failures are ignored; the next cycle will retry.
    } catch (_) {
      // Swallow unexpected polling errors to avoid breaking the UI loop.
    } finally {
      _isPollingAlerts = false;
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

  List<SafeOnAlert> _computeNewAlerts(List<SafeOnAlert> fetchedAlerts) {
    if (!_hasLoadedInitialAlerts) {
      return const [];
    }

    return fetchedAlerts
        .where((alert) => !_knownAlertIds.contains(alert.id))
        .toList();
  }

  void _markAlertAsRead(SafeOnAlert alert) {
    if (alert.read == true) return;
    setState(() {
      _alerts = _alerts
          .map((item) => item.id == alert.id ? item.copyWith(read: true) : item)
          .toList();
    });
  }

  Future<void> _handleHomeModeToggle(bool enable) async {
    if (_isUpdatingHomeMode) return;

    setState(() {
      _isUpdatingHomeMode = true;
    });

    final previous = _isHomeModeArmed;
    setState(() => _isHomeModeArmed = enable);

    try {
      if (enable) {
        await widget.apiClient.enableMlModel(widget.session.token);
      } else {
        await widget.apiClient.disableMlModel(widget.session.token);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isHomeModeArmed = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isHomeModeArmed = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enable ? 'ML 모델을 켜지 못했어요. 다시 시도해주세요.' : 'ML 모델을 끄지 못했어요. 다시 시도해주세요.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingHomeMode = false;
        });
      }
    }
  }

  Future<void> _handlePushNotificationToggle(bool enable) async {
    if (_isUpdatingPushNotifications) return;

    setState(() {
      _isUpdatingPushNotifications = true;
    });

    try {
      if (enable) {
        final granted = await NotificationService.requestPermission();
        if (!mounted) return;

        if (granted) {
          setState(() => _isPushnotificationsEnabled = true);
        } else {
          setState(() => _isPushnotificationsEnabled = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('푸시 알림 권한이 거부되어 알림을 받을 수 없어요. 설정에서 허용해주세요.'),
            ),
          );
        }
      } else {
        await NotificationService.disableNotifications();
        if (!mounted) return;
        setState(() => _isPushnotificationsEnabled = false);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isPushnotificationsEnabled = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('푸시 알림 설정을 변경하지 못했어요. 다시 시도해주세요.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingPushNotifications = false;
        });
      }
    }
  }

  DateTime _startOfWeek(DateTime date) {
    final local = DateTime(date.year, date.month, date.day);
    return local.subtract(Duration(days: (local.weekday + 6) % 7));
  }

  List<int> get _weeklyAnomalySeries {
    final start = _currentWeekStart;
    final end = start.add(const Duration(days: 6));
    final countsByDay = <int, int>{};

    for (final entry in _dailyAnomalyCounts) {
      final day = DateTime(entry.date.year, entry.date.month, entry.date.day);
      if (day.isBefore(start) || day.isAfter(end)) continue;
      final index = day.difference(start).inDays;
      countsByDay[index] = (countsByDay[index] ?? 0) + entry.count;
    }

    return List<int>.generate(7, (index) => countsByDay[index] ?? 0);
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
              'Welcome, ${_profile.name}',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _openDiscoveredDevicesSheet,
            icon: const Icon(Icons.add_rounded),
            tooltip: '기기 추가',
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Tooltip(
              message: '프로필로 이동',
              child: InkWell(
                onTap: () => setState(() => _selectedIndex = 3),
                customBorder: const CircleBorder(),
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: SafeOnColors.primary.withValues(alpha: 0.2),
                  child: Text(
                    _avatarLabel,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: SafeOnColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
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
            label: '홈',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.warning_amber_rounded),
            label: '알림',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.devices_other_outlined),
            label: '디바이스',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: '프로필',
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
    final weeklyAnomalyCounts = _weeklyAnomalySeries;


    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SecurityGraphCard(
            name: _profile.name,
            alertCount: alertCount,
            onlineDevices: onlineDevices,
            weeklyCounts: weeklyAnomalyCounts,
            weekStartDate: _currentWeekStart,
          ),
          const SizedBox(height: 22),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              _InsightCard(
                title: '총 기기 수',
                value: '$totalDevices',
                caption: '온라인 $onlineDevices대',
                icon: Icons.podcasts,
                accent: SafeOnColors.primary,
                onTap: () => setState(() => _selectedIndex = 2),
              ),
              const _InsightCard(
                title: '네트워크 상태',
                value: '정상',
                caption: '모든 서비스 정상',
                icon: Icons.verified_user,
                accent: SafeOnColors.success,
              ),
              _InsightCard(
                title: '누적 알림',
                value: '$alertCount',
                caption: '마지막:$lastAlertLabel',
                icon: Icons.warning_amber,
                accent: SafeOnColors.accent,
                onTap: () => setState(() => _selectedIndex = 1),
              ),
              _InsightCard(
                title: '최근 알림 수집',
                value: '${_alerts.length}',
                caption: '최근 24시간 기록',
                icon: Icons.wifi_tethering,
                accent: SafeOnColors.primaryVariant,
              ),
            ],
          ),
          const SizedBox(height: 28),
          SectionHeader(
            title: '등록된 디바이스',
            actionLabel: '전체 보기',
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
            title: '최근 알림',
            actionLabel: '기록 보기',
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
                    child: AlertTile(
                      alert: alert,
                      onTap: () => _markAlertAsRead(alert),
                    ),
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
      itemBuilder: (context, index) => AlertTile(
        alert: _alerts[index],
        onTap: () => _markAlertAsRead(_alerts[index]),
      ),
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
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: SafeOnColors.primary.withValues(alpha: 0.2),
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
          Text('보안 설정', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          _buildSettingTile(
            icon: _isHomeModeArmed
                ? Icons.lock_outline
                : Icons.lock_open_outlined,
            title: '홈 모드',
            subtitle: _isHomeModeArmed
                ? '시스템이 활성화되어 감시 중'
                : '시스템이 해제되었습니다',
            trailing: Switch(
              value: _isHomeModeArmed,
              onChanged: _isUpdatingHomeMode ? null : _handleHomeModeToggle,
              activeColor: SafeOnColors.primary,
              activeThumbColor: SafeOnColors.primary,
              activeTrackColor: SafeOnColors.primary.withValues(alpha: 0.3),
            ),
          ),
          _buildSettingTile(
            icon: Icons.lock_clock,
            title: '매일 자동 활성화',
            subtitle: _isNightlyAutoArmEnabled
                ? 'SafeOn을 자동으로 켜요'
                : '자동 활성화 일시 중지',
            trailing: Switch(
              value: _isNightlyAutoArmEnabled,
              onChanged: (value) {
                setState(() {
                  _isNightlyAutoArmEnabled = value;
                });
              },
              activeThumbColor: SafeOnColors.primary,
              activeTrackColor: SafeOnColors.primary.withValues(alpha: 0.3),
            ),
          ),
          _buildSettingTile(
            icon:
                _isAutomationActive ? Icons.auto_mode : Icons.pause_circle_outline,
            title: '자동화 루틴',
            subtitle: _isAutomationActive
                ? '루틴이 일정대로 실행 중'
                : '자동화가 일시 중지',
            trailing: Switch(
              value: _isAutomationActive,
              onChanged: (value) {
                setState(() {
                  _isAutomationActive = value;
                });
              },
              activeThumbColor: SafeOnColors.primary,
              activeTrackColor: SafeOnColors.primary.withValues(alpha: 0.3),
            ),
          ),
          _buildSettingTile(
            icon: Icons.notifications_active_outlined,
            title: '푸시 알림',
            subtitle: _isPushnotificationsEnabled
                ? '알림 및 시스템 업데이트 수신'
                : '알림 및 시스템 알림 꺼짐',
            trailing: Switch(
              value: _isPushnotificationsEnabled,
              onChanged:
                  _isUpdatingPushNotifications ? null : _handlePushNotificationToggle,
              activeThumbColor: SafeOnColors.primary,
              activeTrackColor: SafeOnColors.primary.withValues(alpha: 0.3),
            ),
          ),
          const SizedBox(height: 32),
          Text('계정 관리', style: theme.textTheme.titleLarge),
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
              label: const Text('로그아웃'),
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
              color: SafeOnColors.primary.withValues(alpha: 0.08),
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
            color: Colors.black.withValues(alpha: 0.04),
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
              color: SafeOnColors.primary.withValues(alpha: 0.1),
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

  Future<void> _openDeviceDetail(SafeOnDevice device) async {
    final removed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => DeviceDetailScreen(
          device: device,
          apiClient: widget.apiClient,
          token: widget.session.token,
        ),
      ),
    );

    if (removed == true && mounted) {
      setState(() {
        _devices = _devices.where((d) => d.id != device.id).toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${device.displayName}" 디바이스가 제거되었습니다.')),
      );
      // 최신 데이터 동기화
      unawaited(_loadDashboard());
    }
  }

  Future<void> _onLogoutPressed() async {
    final shouldLogout = await showCupertinoDialog<bool>(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            title: const Text('SafeOn에서\n로그아웃하시겠어요?'),
            actions: [
              CupertinoDialogAction(
                isDefaultAction: true,
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('취소'),
              ),
              CupertinoDialogAction(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('로그아웃'),
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          splashColor: accent.withValues(alpha: 0.12),
          highlightColor: Colors.transparent,
          child: Ink(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: SafeOnColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: accent.withValues(alpha: 0.18)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
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
                    color: accent.withValues(alpha: 0.12),
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
  final Set<String> _blockingDeviceIds = {};

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

  Future<void> _confirmBlockDevice(SafeOnDevice device) async {
    if (device.id.isEmpty || device.macAddress.isEmpty || device.macAddress == '—') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('기기 정보가 부족해 차단할 수 없습니다.')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('디바이스 차단'),
        content: Text('"${device.displayName}"을(를) 차단할까요?'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('차단'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _blockDevice(device);
    }
  }

  Future<void> _blockDevice(SafeOnDevice device) async {
    if (_blockingDeviceIds.contains(device.id)) return;

    setState(() {
      _blockingDeviceIds.add(device.id);
    });

    try {
      await widget.apiClient.blockDevice(
        token: widget.token,
        deviceId: device.id,
        macAddress: device.macAddress,
        ip: device.ip == '—' ? null : device.ip,
        name: device.name,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${device.displayName} 차단 요청을 보냈어요.')),
      );
      _retryFetch();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('디바이스 차단 중 오류가 발생했습니다. 다시 시도해주세요.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _blockingDeviceIds.remove(device.id);
        });
      }
    }
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
            color: Colors.black.withValues(alpha: 0.08),
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
                      color: colorScheme.onSurface.withValues(alpha: 0.1),
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
                          final isBlocking =
                              _blockingDeviceIds.contains(device.id);
                          return _DiscoveredDeviceTile(
                            device: device,
                            isClaiming: isClaiming,
                            isBlocking: isBlocking,
                            onClaim: () => _claimDevice(device),
                            onBlock: () => _confirmBlockDevice(device),
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
    required this.onBlock,
    required this.isBlocking,
  });

  final SafeOnDevice device;
  final VoidCallback onClaim;
  final bool isClaiming;
  final VoidCallback onBlock;
  final bool isBlocking;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: SafeOnColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
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
                  backgroundColor: SafeOnColors.primary.withValues(alpha: 0.12),
                  child: const Icon(
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
                        'MAC 주소: ${device.macAddress}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: SafeOnColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: isBlocking ? null : onBlock,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    visualDensity: VisualDensity.compact,
                    minimumSize: Size.zero,
                    foregroundColor: SafeOnColors.danger,
                  ),
                  icon: isBlocking
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: SafeOnColors.danger),
                        )
                      : const Icon(Icons.block, size: 16),
                  label: const Text(
                    '차단하기',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
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
            color: SafeOnColors.primary.withValues(alpha: 0.08),
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
