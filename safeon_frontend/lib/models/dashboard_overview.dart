class DashboardOverview {
  const DashboardOverview({
    required this.totalDevices,
    required this.onlineDevices,
    required this.alertCount,
    required this.lastAlertTime,
  });

  final int totalDevices;
  final int onlineDevices;
  final int alertCount;
  final DateTime? lastAlertTime;

  factory DashboardOverview.fromJson(Map<String, dynamic> json) {
    return DashboardOverview(
      totalDevices: json['totalDevices'] as int? ?? 0,
      onlineDevices: json['onlineDevices'] as int? ?? 0,
      alertCount: (json['alertCount'] as num?)?.toInt() ?? 0,
      lastAlertTime: json['lastAlertTime'] != null
          ? DateTime.tryParse(json['lastAlertTime'] as String)
          : null,
    );
  }
}