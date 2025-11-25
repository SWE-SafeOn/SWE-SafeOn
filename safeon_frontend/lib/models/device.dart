class SafeOnDevice {
  const SafeOnDevice({
    required this.id,
    required this.name,
    required this.ip,
    required this.macAddress,
    required this.discovered,
    required this.label,
    this.createdAt,
    this.linkedAt,
  });

  final String id;
  final String name;
  final String ip;
  final String macAddress;
  final bool discovered;
  final String label;
  final DateTime? createdAt;
  final DateTime? linkedAt;

  factory SafeOnDevice.fromDashboardJson(Map<String, dynamic> json) {
    final String? mac =
        json['macAddress'] as String? ?? json['macAddr'] as String?;
    final String? deviceName = json['name'] as String? ??
        json['label'] as String? ??
        json['vendor'] as String?;

    return SafeOnDevice(
      id: json['id'] as String? ?? '',
      name: deviceName ?? 'SafeOn Device',
      ip: json['ip'] as String? ?? '—',
      macAddress: mac ?? '—',
      discovered: json['discovered'] as bool? ?? false,
      label: json['label'] as String? ?? deviceName ?? 'SafeOn Device',
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
      linkedAt: json['linkedAt'] != null
          ? DateTime.tryParse(json['linkedAt'] as String)
          : null,
    );
  }

  String get displayName => name.isNotEmpty ? name : 'SafeOn Device';

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
