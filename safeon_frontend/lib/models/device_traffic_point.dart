class DeviceTrafficPoint {
  const DeviceTrafficPoint({
    required this.timestamp,
    required this.pps,
    required this.bps,
  });

  final DateTime timestamp;
  final double pps;
  final double bps;

  factory DeviceTrafficPoint.fromJson(Map<String, dynamic> json) {
    final dynamic ts =
        json['timestamp'] ?? json['ts'] ?? json['time'] ?? json['startTime'] ?? json['start_time'];
    final DateTime resolvedTs = _parseTimestamp(ts);

    final double pps = (json['pps'] as num?)?.toDouble() ?? 0.0;
    final double bps = (json['bps'] as num?)?.toDouble() ?? 0.0;

    return DeviceTrafficPoint(
      timestamp: resolvedTs,
      pps: pps,
      bps: bps,
    );
  }

  static DateTime _parseTimestamp(dynamic raw) {
    if (raw == null) return DateTime.now();
    if (raw is int) {
      return DateTime.fromMillisecondsSinceEpoch(raw);
    }
    if (raw is double) {
      return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
    }
    if (raw is String) {
      return DateTime.tryParse(raw) ?? DateTime.now();
    }
    return DateTime.now();
  }
}
