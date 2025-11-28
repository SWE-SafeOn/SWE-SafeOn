import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/device_traffic_point.dart';
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
  bool _isLoadingTraffic = false;
  String? _trafficError;
  List<DeviceTrafficPoint> _trafficPoints = [];

  @override
  void initState() {
    super.initState();
    _loadTraffic();
  }

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
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: _buildMetaSection(),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                child: _buildTrafficSection(),
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
            color: Colors.black.withValues(alpha: 0.05),
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
        ],
      ),
    );
  }

  Widget _buildMetaSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('디바이스 정보'),
        const SizedBox(height: 8),
        _buildMetaRow(Icons.system_update, '마지막 펌웨어 체크', '오늘 09:12'),
        _buildMetaRow(Icons.language, 'IP 주소', widget.device.ip),
        _buildMetaRow(Icons.qr_code_2, 'MAC 주소', widget.device.macAddress),
        _buildMetaRow(Icons.numbers, '시리얼 번호', widget.device.id.isNotEmpty ? widget.device.id : '할당되지 않음'),
      ],
    );
  }

  Widget _buildTrafficSection() {
    Widget content;
    if (_isLoadingTraffic) {
      content = const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: CircularProgressIndicator(),
        ),
      );
    } else if (_trafficError != null) {
      content = Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_trafficError!, style: const TextStyle(color: SafeOnColors.danger)),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _loadTraffic,
              child: const Text('다시 불러오기'),
            ),
          ],
        ),
      );
    } else if (_trafficPoints.isEmpty) {
      content = Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '트래픽 데이터가 아직 없습니다.',
              style: TextStyle(color: SafeOnColors.textSecondary),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _loadTraffic,
              child: const Text('새로고침'),
            ),
          ],
        ),
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 6),
          SizedBox(
            height: 240,
            child: _buildLineChart(),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('트래픽 추이'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: _cardDecoration(),
          child: content,
        ),
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
    showCupertinoDialog<void>(
      context: context,
      builder: (context) {
        return CupertinoAlertDialog(
          title: const Text('디바이스 제거'),
          content: Text('"${widget.device.displayName}" 를 정말 제거하시겠습니까?'),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('취소'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () async {
                if (_isRemoving) return;
                await _removeDevice(context);
              },
              child: _isRemoving
                  ? const CupertinoActivityIndicator()
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

  Future<void> _loadTraffic() async {
    if (widget.device.id.isEmpty) {
      setState(() {
        _trafficPoints = [];
        _trafficError = '디바이스 ID가 없어 트래픽을 불러올 수 없습니다.';
      });
      return;
    }

    setState(() {
      _isLoadingTraffic = true;
      _trafficError = null;
    });

    try {
      final data = await widget.apiClient.fetchDeviceTraffic(
        token: widget.token,
        deviceId: widget.device.id,
        limit: 50,
      );
      if (!mounted) return;
      setState(() {
        _trafficPoints = data;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _trafficError = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _trafficError = '트래픽 데이터를 불러오지 못했습니다. (${e.toString()})';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingTraffic = false;
        });
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
                  color: SafeOnColors.primary.withValues(alpha: 0.12),
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
              color: (iconColor ?? SafeOnColors.primary).withValues(alpha: 0.1),
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
          backgroundColor: SafeOnColors.primary.withValues(alpha: 0.1),
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
                color: gradient.first.withValues(alpha: 0.22),
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
                color: isOnline ? SafeOnColors.primary.withValues(alpha: 0.15) : SafeOnColors.textSecondary.withValues(alpha: 0.15),
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

  Widget _buildLineChart() {
    final spotsPps = _trafficPoints
        .map((point) => FlSpot(
              point.timestamp.millisecondsSinceEpoch.toDouble(),
              point.pps,
            ))
        .toList();
    final spotsBps = _trafficPoints
        .map((point) => FlSpot(
              point.timestamp.millisecondsSinceEpoch.toDouble(),
              point.bps,
            ))
        .toList();

    final minX = spotsPps.map((e) => e.x).fold<double>(spotsPps.first.x, math.min);
    final maxX = spotsPps.map((e) => e.x).fold<double>(spotsPps.first.x, math.max);
    final maxY = [
      ...spotsPps.map((e) => e.y),
      ...spotsBps.map((e) => e.y),
    ].fold<double>(0, math.max);

    String formatTs(double x) {
      final dt = DateTime.fromMillisecondsSinceEpoch(x.toInt());
      return DateFormat('HH:mm').format(dt);
    }

    return LineChart(
      LineChartData(
        minX: minX,
        maxX: maxX,
        minY: 0,
        maxY: maxY == 0 ? 1 : maxY * 1.2,
        gridData: FlGridData(
          show: true,
          horizontalInterval:
              ((maxY == 0 ? 1 : maxY / 4).clamp(0.1, double.infinity)).toDouble(),
          getDrawingHorizontalLine: (value) => FlLine(
            color: Colors.grey.shade200,
            strokeWidth: 1,
          ),
          drawVerticalLine: false,
        ),
        borderData: FlBorderData(
          show: true,
          border: Border.all(color: Colors.grey.shade300),
        ),
        titlesData: FlTitlesData(
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 42,
              getTitlesWidget: (value, _) => Text(
                value.toStringAsFixed(0),
                style: const TextStyle(fontSize: 11, color: SafeOnColors.textSecondary),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: ((maxX - minX) / 4).clamp(1, double.infinity),
              reservedSize: 30,
              getTitlesWidget: (value, _) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  formatTs(value),
                  style: const TextStyle(fontSize: 11, color: SafeOnColors.textSecondary),
                ),
              ),
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spotsPps,
            color: SafeOnColors.primary,
            barWidth: 3,
            isCurved: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: SafeOnColors.primary.withValues(alpha: 0.12),
            ),
          ),
          LineChartBarData(
            spots: spotsBps,
            color: SafeOnColors.accent,
            barWidth: 3,
            isCurved: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: SafeOnColors.accent.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(IconData icon, String label, {Color? color}) {
    final badgeColor = color ?? SafeOnColors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.08),
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
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 16,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }
}
