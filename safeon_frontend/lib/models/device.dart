class SafeOnDevice {
  const SafeOnDevice({
    required this.id,
    required this.vendor,
    required this.ip,
    required this.macAddr,
    required this.discovered,
    required this.label,
    this.createdAt,
    this.linkedAt,
  });

  final String id;
  final String vendor;
  final String ip;
  final String macAddr;
  final bool discovered;
  final String label;
  final DateTime? createdAt;
  final DateTime? linkedAt;

  factory SafeOnDevice.fromDashboardJson(Map<String, dynamic> json) {
    return SafeOnDevice(
      id: json['id'] as String? ?? '',
      vendor: json['vendor'] as String? ?? 'Unknown vendor',
      ip: json['ip'] as String? ?? '—',
      macAddr: json['macAddr'] as String? ?? '—',
      discovered: json['discovered'] as bool? ?? false,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
      linkedAt: json['linkedAt'] != null
          ? DateTime.tryParse(json['linkedAt'] as String)
          : null,
      label: json['label'] as String? ?? 'SafeOn Device',
    );
  }

  String get displayName => label.isNotEmpty ? label : vendor;

  String get locationLabel => ip.isNotEmpty ? 'IP: $ip' : 'IP unavailable';

  String get status => linkedAt != null
      ? 'Linked'
      : discovered
          ? 'Discovered'
          : 'Pending';

  bool get isOnline => linkedAt != null || discovered;

  double get connectionStrength => isOnline ? 0.86 : 0.35;

  String get icon => linkedAt != null ? 'hub' : 'sensor';
}
