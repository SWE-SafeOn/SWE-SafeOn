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
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: _buildLiveFeedCard(),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: _buildInsightsSection(),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: _buildControlsSection(),
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
              Container(
                height: 76,
                width: 76,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: const LinearGradient(
                    colors: [Color(0xFFEDF3FF), Color(0xFFD8E5FF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                foregroundDecoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: widget.device.isOnline ? Colors.transparent : Colors.black.withOpacity(0.45),
                ),
                child: Center(
                  child: Icon(
                    widget.device.isOnline ? Icons.videocam_outlined : Icons.wifi_off,
                    color: widget.device.isOnline ? SafeOnColors.primary : Colors.white,
                    size: 34,
                  ),
                ),
              ),
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
                          icon: widget.device.isOnline ? Icons.check_circle : Icons.error_outline,
                          color: widget.device.isOnline ? SafeOnColors.success : SafeOnColors.danger,
                        ),
                        const SizedBox(width: 8),
                        _buildSignalChip(widget.device.connectionStrength),
                        const SizedBox(width: 8),
                        _buildBadge(Icons.schedule, '지연 42ms'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildMetaItem(Icons.place_outlined, widget.device.locationLabel),
              _buildMetaItem(Icons.language, widget.device.ip),
              _buildMetaItem(Icons.qr_code_2, widget.device.macAddress),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildQuickAction(Icons.shield, widget.device.isOnline ? 'Arm' : 'Offline', onTap: () {}),
              const SizedBox(width: 12),
              _buildQuickAction(Icons.mic_none, 'Talk', onTap: () {}),
              const SizedBox(width: 12),
              _buildQuickAction(Icons.fiber_manual_record_outlined, 'Record', onTap: () {}),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLiveFeedCard() {
    final bool isOnline = widget.device.isOnline;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildBadge(Icons.videocam_outlined, '라이브 피드'),
              const Spacer(),
              _buildBadge(Icons.access_time, '최근 스냅샷 · 1분 전'),
            ],
          ),
          const SizedBox(height: 14),
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: 180,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: isOnline ? SafeOnColors.surface : Colors.grey.shade200,
            ),
            alignment: Alignment.center,
            child: isOnline
                ? const SizedBox.shrink()
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.wifi_off, size: 32, color: SafeOnColors.textSecondary),
                      SizedBox(height: 8),
                      Text('디바이스가 오프라인 상태입니다.', style: TextStyle(color: SafeOnColors.textSecondary)),
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: isOnline ? () {} : null,
                icon: const Icon(Icons.play_arrow),
                label: const Text('라이브 보기'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.view_list),
                label: const Text('로그 보기'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInsightsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('라이브 인사이트'),
        const SizedBox(height: 8),
        _buildInsightTile(
          icon: Icons.timeline,
          title: '활동 타임라인',
          description: '최근 24시간 모션 2회 감지 · 이상 징후 없음',
          actionLabel: '타임라인 열기',
        ),
        _buildInsightTile(
          icon: Icons.cloud_outlined,
          title: '클라우드 백업',
          description: '영상이 안전한 SafeOn 클라우드에 동기화 중',
          actionLabel: '스토리지 관리',
        ),
        _buildInsightTile(
          icon: Icons.sensors_outlined,
          title: '자동화 루틴',
          description: '“Night Guard”, “Weekend Away”에 참여 중',
          actionLabel: '루틴 편집',
        ),
      ],
    );
  }

  Widget _buildControlsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('디바이스 컨트롤'),
        const SizedBox(height: 8),
        _buildControlTile(
          title: 'Streaming',
          subtitle: _isStreamingEnabled ? 'Live feed enabled' : 'Live feed paused',
          trailing: Switch(
            value: _isStreamingEnabled,
            onChanged: (value) {
              setState(() => _isStreamingEnabled = value);
            },
            activeThumbColor: SafeOnColors.primary,
          ),
        ),
        _buildControlTile(
          title: 'Two-way audio',
          subtitle: _isTwoWayAudioEnabled ? 'Respond through device speaker' : 'Mic muted',
          trailing: Switch(
            value: _isTwoWayAudioEnabled,
            onChanged: (value) {
              setState(() => _isTwoWayAudioEnabled = value);
            },
            activeThumbColor: SafeOnColors.primary,
          ),
        ),
        _buildControlTile(
          title: 'Privacy shutter',
          subtitle: _isPrivacyShutterEnabled ? 'Closes when family arrives' : 'Shutter open',
          trailing: Switch(
            value: _isPrivacyShutterEnabled,
            onChanged: (value) {
              setState(() => _isPrivacyShutterEnabled = value);
            },
            activeThumbColor: SafeOnColors.primary,
          ),
        ),
        _buildControlTile(
          title: '재부팅 / 진단',
          subtitle: '장치 재시작 및 상태 점검',
          trailing: OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.restart_alt),
            label: const Text('실행'),
          ),
        ),
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
        _buildMetaRow(Icons.qr_code_2, 'MAC', widget.device.macAddress),
        _buildMetaRow(Icons.numbers, '시리얼', widget.device.id.isNotEmpty ? widget.device.id : '할당되지 않음'),
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
    if (_isRemoving) return;
    setState(() => _isRemoving = true);

    try {
      await widget.apiClient.deleteDevice(
        token: widget.token,
        deviceId: widget.device.id,
      );
      if (!mounted) return;
      Navigator.of(dialogContext).pop(); // close dialog
      Navigator.of(context).pop(true); // return success to previous screen
    } on ApiException catch (e) {
      if (!mounted) return;
      Navigator.of(dialogContext).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!mounted) return;
      Navigator.of(dialogContext).pop();
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
      decoration: _cardDecoration(),
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

  Widget _buildBadge(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: SafeOnColors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: SafeOnColors.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: SafeOnColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
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
