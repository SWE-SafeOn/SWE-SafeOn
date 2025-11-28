import 'package:flutter/material.dart';

import '../models/device.dart';
import '../services/safeon_api.dart';
import '../theme/app_theme.dart';
import '../widgets/status_chip.dart';

class DeviceDetailScreen extends StatefulWidget {
  const DeviceDetailScreen({
    super.key,
    required this.device,
    required this.apiClient,
    required this.token,
  });

  final SafeOnDevice device;
  final SafeOnApiClient apiClient;
  final String token;

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  bool _isStreamingEnabled = true;
  bool _isTwoWayAudioEnabled = false;
  bool _isPrivacyShutterEnabled = true;
  bool _isRemoving = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.device.displayName),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF6F9FF), Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: _buildHeroHeader(context),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: _buildQuickActionsSection(),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: _buildMetaSection(),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                child: _buildDangerZone(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroHeader(BuildContext context) {
    final theme = Theme.of(context);
    final isOnline = widget.device.isOnline;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
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
              _buildDeviceAvatar(),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.device.displayName, style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        StatusChip(
                          label: widget.device.status,
                          icon: isOnline ? Icons.check_circle : Icons.error_outline,
                          color: isOnline ? SafeOnColors.success : SafeOnColors.danger,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                _buildMetaItem(Icons.place_outlined, widget.device.locationLabel),
                const SizedBox(width: 12),
                _buildMetaItem(Icons.language, widget.device.ip),
                const SizedBox(width: 12),
                _buildMetaItem(Icons.qr_code_2, widget.device.macAddress),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildSignalChip(widget.device.connectionStrength),
              const SizedBox(width: 8),
              _buildBadge(
                isOnline ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                isOnline ? '안정 연결' : '연결 확인 필요',
                color: isOnline ? SafeOnColors.success : SafeOnColors.danger,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionsSection() {
    return Row(
      children: [
        _buildQuickAction(Icons.play_circle_filled_rounded, '라이브 보기', onTap: () => _showComingSoon('라이브 보기')),
        const SizedBox(width: 12),
        _buildQuickAction(Icons.history_rounded, '이벤트 로그', onTap: () => _showComingSoon('이벤트 로그')),
        const SizedBox(width: 12),
        _buildQuickAction(Icons.cloud_upload_outlined, '스토리지', onTap: () => _showComingSoon('스토리지 관리')),
      ],
    );
  }

  Widget _buildMetaSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('디바이스 정보'),
        const SizedBox(height: 8),
        _buildMetaRow(Icons.wifi, '신호 강도', '${(widget.device.connectionStrength * 100).round()}%'),
        _buildMetaRow(Icons.system_update, '마지막 펌웨어 체크', '오늘 09:12'),
        _buildMetaRow(Icons.language, 'IP 주소', widget.device.ip),
        _buildMetaRow(Icons.qr_code_2, 'MAC 주소', widget.device.macAddress),
        _buildMetaRow(Icons.numbers, '시리얼 번호', widget.device.id.isNotEmpty ? widget.device.id : '할당되지 않음'),
      ],
    );
  }

  Widget _buildDangerZone() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration().copyWith(color: Colors.red.shade50),
      child: Row(
        children: [
          const Icon(Icons.delete_forever, color: Colors.red),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              '디바이스 제거',
              style: TextStyle(fontWeight: FontWeight.w600, color: Colors.red),
            ),
          ),
          TextButton(
            onPressed: _isRemoving ? null : _confirmRemoveDevice,
            child: _isRemoving
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.red),
                  )
                : const Text('제거', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature 기능이 곧 제공됩니다.')),
    );
  }

  void _confirmRemoveDevice() {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('디바이스 제거'),
          content: Text('"${widget.device.displayName}" 를 정말 제거하시겠습니까?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('취소')),
            FilledButton(
              onPressed: _isRemoving
                  ? null
                  : () async {
                      await _removeDevice(context);
                    },
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: _isRemoving
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('제거'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _removeDevice(BuildContext dialogContext) async {
    if (widget.device.id.isEmpty) {
      Navigator.of(dialogContext).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('디바이스 ID를 확인할 수 없어 제거할 수 없습니다.')),
      );
      return;
    }

    if (_isRemoving) return;
    setState(() => _isRemoving = true);

    try {
      await widget.apiClient.deleteDevice(
        token: widget.token,
        deviceId: widget.device.id,
      );
      if (!mounted) return;
      Navigator.of(dialogContext, rootNavigator: true).pop(); // close dialog
      Navigator.of(context).pop(true); // return success to previous screen
    } on ApiException catch (e) {
      if (!mounted) return;
      Navigator.of(dialogContext, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!mounted) return;
      Navigator.of(dialogContext, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('디바이스 제거 중 오류가 발생했습니다. 다시 시도해주세요.')),
      );
    } finally {
      if (mounted) {
        setState(() => _isRemoving = false);
      }
    }
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
      decoration: _cardDecoration(),
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
                onPressed: () => _showComingSoon(actionLabel),
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
    required IconData icon,
    required Widget trailing,
    Color? iconColor,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (iconColor ?? SafeOnColors.primary).withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              icon,
              color: iconColor ?? SafeOnColors.primary,
            ),
          ),
          const SizedBox(width: 14),
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

  Widget _buildMetaRow(IconData icon, String label, String value) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          Icon(icon, color: SafeOnColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(color: SafeOnColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        title,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildQuickAction(IconData icon, String label, {VoidCallback? onTap}) {
    return Expanded(
      child: ElevatedButton.icon(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          backgroundColor: SafeOnColors.primary.withOpacity(0.1),
          foregroundColor: SafeOnColors.primary,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        icon: Icon(icon),
        label: Text(label),
      ),
    );
  }

  Widget _buildMetaItem(IconData icon, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: SafeOnColors.textSecondary),
        const SizedBox(width: 6),
        Text(
          value,
          style: const TextStyle(color: SafeOnColors.textSecondary, fontSize: 13),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildDeviceAvatar() {
    final isOnline = widget.device.isOnline;
    final typeIcon = _iconFromName(widget.device.icon);
    final typeLabel = _deviceTypeLabel(widget.device.icon);
    final gradient = isOnline
        ? const [Color(0xFF1F6FEB), Color(0xFF4F8BFF)]
        : const [Color(0xFFCBD5E1), Color(0xFFE2E8F0)];

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: gradient.first.withOpacity(0.22),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Container(
            height: 82,
            width: 82,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(
                color: isOnline ? SafeOnColors.primary.withOpacity(0.15) : SafeOnColors.textSecondary.withOpacity(0.15),
                width: 2,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  typeIcon,
                  color: isOnline ? SafeOnColors.primary : SafeOnColors.textSecondary,
                  size: 34,
                ),
                const SizedBox(height: 6),
                Text(
                  typeLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isOnline ? SafeOnColors.textPrimary : SafeOnColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSignalChip(double strength) {
    final percent = (strength * 100).round();
    IconData icon;
    if (percent > 80) {
      icon = Icons.wifi;
    } else if (percent > 50) {
      icon = Icons.wifi_2_bar;
    } else {
      icon = Icons.wifi_1_bar;
    }
    return _buildBadge(icon, '신호 $percent%');
  }

  Widget _buildBadge(IconData icon, String label, {Color? color}) {
    final badgeColor = color ?? SafeOnColors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: badgeColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: badgeColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
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

  String _deviceTypeLabel(String name) {
    switch (name) {
      case 'camera':
        return '카메라';
      case 'hub':
        return '허브';
      case 'lock':
        return '도어락';
      case 'sensor':
        return '센서';
      default:
        return '디바이스';
    }
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: SafeOnColors.surface,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 16,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }
}
