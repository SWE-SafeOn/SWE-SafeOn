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
    final mac = json['macAddress'] ?? json['macAddr'];
    final deviceName = json['name'] ?? json['label'] ?? json['vendor'];
    
    return SafeOnDevice(
      id: json['id'] as String? ?? '',
      name: deviceName as String? ?? 'SafeOn Device',
      ip: json['ip'] as String? ?? '—',
      macAddress: mac as String? ?? '—',
      discovered: json['discovered'] as bool? ?? false,
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
