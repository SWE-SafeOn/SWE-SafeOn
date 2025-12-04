import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/alert.dart';
import '../services/safeon_api.dart';
import '../theme/app_theme.dart';

class AlertDetailScreen extends StatefulWidget {
  const AlertDetailScreen({
    super.key,
    required this.alertId,
    required this.apiClient,
    required this.token,
    this.initialAlert,
  });

  final String alertId;
  final SafeOnApiClient apiClient;
  final String token;
  final SafeOnAlert? initialAlert;

  @override
  State<AlertDetailScreen> createState() => _AlertDetailScreenState();
}

class _AlertDetailScreenState extends State<AlertDetailScreen> {
  late Future<SafeOnAlert> _detailFuture;
  bool _isBlocking = false;

  @override
  void initState() {
    super.initState();
    _detailFuture = _fetchDetail();
  }

  Future<SafeOnAlert> _fetchDetail() async {
    return widget.apiClient.fetchAlertDetail(
      token: widget.token,
      alertId: widget.alertId,
    );
  }

  Future<void> _handleBlockDevice(SafeOnAlert alert) async {
    if (_isBlocking) return;
    if ((alert.deviceId ?? '').isEmpty || (alert.deviceMac ?? '').isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('차단에 필요한 디바이스 정보가 없습니다.')),
      );
      return;
    }

    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('디바이스 차단'),
        content: Text(
          '${alert.deviceName ?? alert.deviceMac ?? alert.deviceId} 기기를 네트워크에서 차단할까요?',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            isDefaultAction: true,
            child: const Text('취소'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('차단'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _isBlocking = true);
    try {
      await widget.apiClient.blockDevice(
        token: widget.token,
        deviceId: alert.deviceId!,
        macAddress: alert.deviceMac!,
        ip: alert.deviceIp,
        name: alert.deviceName,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('디바이스를 차단했어요.')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('디바이스를 차단하지 못했어요. 잠시 후 다시 시도해주세요.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isBlocking = false);
      }
    }
  }

  double _severityValue(AlertSeverity severity) {
    switch (severity) {
      case AlertSeverity.low:
        return 0.35;
      case AlertSeverity.medium:
        return 0.6;
      case AlertSeverity.high:
        return 0.9;
    }
  }

  Widget _buildMetaChip({
    required IconData icon,
    required String label,
    Color color = Colors.white,
    Color? background,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: background ?? Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.1,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String label,
    required String value,
    Color? iconColor,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
      decoration: BoxDecoration(
        color: SafeOnColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.03)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  (iconColor ?? SafeOnColors.primary).withValues(alpha: 0.16),
                  (iconColor ?? SafeOnColors.primary).withValues(alpha: 0.08),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              size: 18,
              color: iconColor ?? SafeOnColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: SafeOnColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: SafeOnColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEvidenceCard(String? evidence) {
    final textTheme = Theme.of(context).textTheme;
    final hasEvidence = evidence?.isNotEmpty == true;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
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
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: SafeOnColors.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.insert_drive_file_rounded,
                  color: SafeOnColors.primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '증거 정보',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: SafeOnColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: SafeOnColors.scaffold,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              hasEvidence ? evidence! : '증거 정보를 불러올 수 없습니다.',
              style: textTheme.bodyLarge?.copyWith(
                color: hasEvidence
                    ? SafeOnColors.textSecondary
                    : SafeOnColors.textSecondary.withValues(alpha: 0.8),
                height: 1.5,
                fontWeight: hasEvidence ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime? timestamp) {
    if (timestamp == null) {
      return '시간 정보 없음';
    }
    return DateFormat('yyyy.MM.dd a h:mm', 'ko').format(timestamp.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final initial = widget.initialAlert;
    return Scaffold(
      appBar: AppBar(
        title: const Text('알림 상세'),
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: Container(
        decoration: const BoxDecoration(color: SafeOnColors.scaffold),
        child: FutureBuilder<SafeOnAlert>(
          future: _detailFuture,
          initialData: initial,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                snapshot.data == null) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('알림 상세를 불러오지 못했어요.'),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _detailFuture = _fetchDetail();
                        });
                      },
                      child: const Text('다시 시도'),
                    ),
                  ],
                ),
              );
            }

            final alert = snapshot.data ?? initial;
            if (alert == null) {
              return const Center(child: Text('표시할 알림이 없습니다.'));
            }

            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        border: Border.all(
                          color: alert.severity.color.withValues(alpha: 0.16),
                        ),
                        borderRadius: BorderRadius.circular(26),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 28,
                            offset: const Offset(0, 14),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      alert.severity.color.withValues(alpha: 0.95),
                                      alert.severity.color.withValues(alpha: 0.65),
                                    ],
                                  ),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: alert.severity.color.withValues(alpha: 0.35),
                                      blurRadius: 24,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.security_rounded,
                                  color: Colors.white,
                                  size: 26,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      alert.reason,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                            color: Colors.white,
                                            height: 1.2,
                                            letterSpacing: -0.2,
                                          ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      _formatTimestamp(alert.timestamp),
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                            color: Colors.white.withValues(alpha: 0.72),
                                          ),
                                    ),
                                    const SizedBox(height: 12),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(14),
                                      child: LinearProgressIndicator(
                                        value: _severityValue(alert.severity),
                                        minHeight: 6,
                                        backgroundColor:
                                            Colors.white.withValues(alpha: 0.12),
                                        valueColor: AlwaysStoppedAnimation(
                                          alert.severity.color,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              _buildMetaChip(
                                icon: Icons.emergency_rounded,
                                label: alert.severity.label,
                                color: Colors.white,
                                background:
                                    Colors.white.withValues(alpha: 0.12),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              _buildMetaChip(
                                icon: Icons.badge_rounded,
                                label: (alert.status ?? '미확인').toUpperCase(),
                              ),
                              _buildMetaChip(
                                icon: Icons.calendar_today_outlined,
                                label: DateFormat('M월 d일 a h:mm', 'ko')
                                    .format(alert.timestamp?.toLocal() ??
                                        DateTime.now()),
                              ),
                              if ((alert.deviceName ?? '').isNotEmpty)
                                _buildMetaChip(
                                  icon: Icons.devices_other_rounded,
                                  label: alert.deviceName!,
                                ),
                              if ((alert.deviceIp ?? '').isNotEmpty)
                                _buildMetaChip(
                                  icon: Icons.router_rounded,
                                  label: alert.deviceIp!,
                                ),
                              if ((alert.deliveryStatus ?? '').isNotEmpty)
                                _buildMetaChip(
                                  icon: Icons.send_rounded,
                                  label: alert.deliveryStatus!,
                                ),
                              if ((alert.deviceMac ?? '').isNotEmpty)
                                _buildMetaChip(
                                  icon: Icons.qr_code_rounded,
                                  label: alert.deviceMac!,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      '상세 정보',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: SafeOnColors.textPrimary,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.black.withValues(alpha: 0.03)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 18,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final isWide = constraints.maxWidth > 420;
                          final itemWidth =
                              isWide ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth;
                          return Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              SizedBox(
                                width: itemWidth,
                                child: _buildInfoCard(
                                  icon: Icons.warning_amber_rounded,
                                  label: '위험도',
                                  value: alert.severity.label,
                                  iconColor: alert.severity.color,
                                ),
                              ),
                              SizedBox(
                                width: itemWidth,
                                child: _buildInfoCard(
                                  icon: Icons.badge_outlined,
                                  label: '알림 상태',
                                  value: alert.status ?? '상태 정보 없음',
                                ),
                              ),
                              SizedBox(
                                width: itemWidth,
                                child: _buildInfoCard(
                                  icon: Icons.qr_code_rounded,
                                  label: 'MAC 주소',
                                  value: alert.deviceMac ?? 'MAC 정보 없음',
                                ),
                              ),
                              SizedBox(
                                width: itemWidth,
                                child: _buildInfoCard(
                                  icon: Icons.label_important_outline,
                                  label: '디바이스 이름',
                                  value: alert.deviceName ?? '알 수 없음',
                                ),
                              ),
                              SizedBox(
                                width: itemWidth,
                                child: _buildInfoCard(
                                  icon: Icons.router_outlined,
                                  label: '디바이스 IP',
                                  value: alert.deviceIp ?? 'IP 정보 없음',
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 18),
                    _buildEvidenceCard(alert.evidence),
                    const SizedBox(height: 18),
                    GestureDetector(
                      onTap: _isBlocking ? null : () => _handleBlockDevice(alert),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 180),
                        opacity: _isBlocking ? 0.7 : 1,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Colors.red.shade100),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_isBlocking) ...[
                                const CupertinoActivityIndicator(color: SafeOnColors.danger),
                                const SizedBox(width: 8),
                              ] else ...[
                                const Icon(Icons.no_accounts_rounded,
                                    color: SafeOnColors.danger),
                                const SizedBox(width: 8),
                              ],
                              const Text(
                                '디바이스 차단',
                                style: TextStyle(
                                  color: SafeOnColors.danger,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
