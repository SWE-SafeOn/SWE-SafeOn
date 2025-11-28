import 'package:flutter/material.dart';

class SafeOnAlert {
  const SafeOnAlert({
    required this.id,
    required this.reason,
    required this.severity,
    this.timestamp,
    this.deviceId,
    this.status,
    this.deliveryStatus,
    this.read,
  });

  final String id;
  final String? deviceId;
  final String reason;
  final AlertSeverity severity;
  final DateTime? timestamp;
  final String? status;
  final String? deliveryStatus;
  final bool? read;

  SafeOnAlert copyWith({
    String? id,
    String? deviceId,
    String? reason,
    AlertSeverity? severity,
    DateTime? timestamp,
    String? status,
    String? deliveryStatus,
    bool? read,
  }) {
    return SafeOnAlert(
      id: id ?? this.id,
      deviceId: deviceId ?? this.deviceId,
      reason: reason ?? this.reason,
      severity: severity ?? this.severity,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
      deliveryStatus: deliveryStatus ?? this.deliveryStatus,
      read: read ?? this.read,
    );
  }

  factory SafeOnAlert.fromDashboardJson(Map<String, dynamic> json) {
    return SafeOnAlert(
      id: json['id'] as String? ?? '',
      deviceId: json['deviceId'] as String?,
      reason: json['reason'] as String? ?? '알림 사유를 불러오지 못했습니다.',
      severity: AlertSeverityExtension.fromString(json['severity'] as String?),
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'] as String)
          : null,
      status: json['status'] as String?,
      deliveryStatus: json['deliveryStatus'] as String?,
      read: json['read'] as bool?,
    );
  }

  String get subtitle {
    if (deviceId != null && deviceId!.isNotEmpty) {
      return '디바이스 $deviceId · ${status ?? '상태 확인 불가'}';
    }
    return status ?? '상태 확인 불가';
  }
}

enum AlertSeverity { low, medium, high }

extension AlertSeverityExtension on AlertSeverity {
  static AlertSeverity fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'high':
        return AlertSeverity.high;
      case 'medium':
        return AlertSeverity.medium;
      default:
        return AlertSeverity.low;
    }
  }

  Color get color {
    switch (this) {
      case AlertSeverity.low:
        return const Color(0xFF2ECC71);
      case AlertSeverity.medium:
        return const Color(0xFFF1C40F);
      case AlertSeverity.high:
        return const Color(0xFFE74C3C);
    }
  }

  String get label {
    switch (this) {
      case AlertSeverity.low:
        return '낮음';
      case AlertSeverity.medium:
        return '보통';
      case AlertSeverity.high:
        return '높음';
    }
  }
}
