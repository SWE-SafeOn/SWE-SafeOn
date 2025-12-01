import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/alert.dart';
import 'package:intl/intl.dart';

import '../models/dashboard_overview.dart';
import '../models/device.dart';
import '../models/device_traffic_point.dart';
import '../models/user_profile.dart';
import '../models/daily_anomaly_count.dart';

class ApiException implements Exception {
  ApiException(this.message, [this.statusCode]);

  final String message;
  final int? statusCode;

  @override
  String toString() => 'ApiException(statusCode: $statusCode, message: $message)';
}

class SafeOnApiClient {
  SafeOnApiClient({
    http.Client? httpClient,
    String? baseUrl,
  })  : baseUrl = _resolveBaseUrl(baseUrl),
        _httpClient = httpClient ?? http.Client();

  final String baseUrl;
  final http.Client _httpClient;

  Uri _uri(String path, [Map<String, dynamic>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  Uri _wsUri(String path, [Map<String, dynamic>? query]) {
    final httpUri = _uri(path, query);
    final scheme = httpUri.scheme == 'https' ? 'wss' : 'ws';
    return httpUri.replace(scheme: scheme);
  }

  Map<String, String> _jsonHeaders({String? token}) {
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static String _resolveBaseUrl(String? override) {
    if (override != null && override.isNotEmpty) {
      return override;
    }

    // Android 에뮬레이터에서는 호스트의 localhost를 10.0.2.2로 접근해야 한다.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8080';
    }

    return 'http://localhost:8080';
  }

  Future<String> login({required String email, required String password}) async {
    final response = await _httpClient.post(
      _uri('/auth/login'),
      headers: _jsonHeaders(),
      body: jsonEncode({'email': email, 'password': password}),
    );

    final body = _decode(response);
    if (response.statusCode == 200 && body['data'] != null) {
      final token = body['data']['accessToken'] as String?;
      if (token == null || token.isEmpty) {
        throw ApiException('로그인 토큰을 받아오지 못했습니다.', response.statusCode);
      }
      return token;
    }

    throw ApiException(_extractError(body) ?? '로그인에 실패했습니다.', response.statusCode);
  }

  Future<void> signup({
    required String email,
    required String password,
    required String name,
  }) async {
    final response = await _httpClient.post(
      _uri('/auth/signup'),
      headers: _jsonHeaders(),
      body: jsonEncode({'email': email, 'password': password, 'name': name}),
    );

    if (response.statusCode != 201) {
      final body = _decode(response);
      throw ApiException(_extractError(body) ?? '회원가입 요청이 실패했습니다.',
          response.statusCode);
    }
  }

  Future<List<DeviceTrafficPoint>> fetchDeviceTraffic({
    required String token,
    required String deviceId,
    int limit = 50,
  }) async {
    final response = await _httpClient.get(
      _uri('/devices/$deviceId/traffic', {'limit': '$limit'}),
      headers: _jsonHeaders(token: token),
    );

    final body = _decode(response);
    if (response.statusCode == 200 && body['data'] != null) {
      final dynamic data = body['data'];
      final List<dynamic> rows;

      if (data is List) {
        rows = data;
      } else if (data is Map<String, dynamic>) {
        rows = data['items'] as List? ??
            data['traffic'] as List? ??
            data['values'] as List? ??
            <dynamic>[];
      } else {
        rows = <dynamic>[];
      }

      return rows
          .whereType<Map<String, dynamic>>()
          .map(DeviceTrafficPoint.fromJson)
          .toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    }

    throw ApiException(
      _extractError(body) ?? '트래픽 데이터를 불러올 수 없습니다.',
      response.statusCode,
    );
  }

  Uri deviceTrafficWebSocketUri({
    required String deviceId,
    required String token,
  }) {
    return _wsUri('/ws/devices/$deviceId/traffic', {'token': token});
  }

  Future<UserProfile> fetchProfile(String token) async {
    final response = await _httpClient.get(
      _uri('/mypage'),
      headers: _jsonHeaders(token: token),
    );

    final body = _decode(response);
    if (response.statusCode == 200 && body['data'] != null) {
      return UserProfile.fromJson(body['data'] as Map<String, dynamic>);
    }
    throw ApiException(
      _extractError(body) ?? '프로필 정보를 불러올 수 없습니다.',
      response.statusCode,
    );
  }

  Future<UserProfile> updateProfile({
    required String token,
    required String name,
    String? password,
  }) async {
    final response = await _httpClient.patch(
      _uri('/mypage'),
      headers: _jsonHeaders(token: token),
      body: jsonEncode({
        'name': name,
        if (password != null && password.isNotEmpty) 'password': password,
      }),
    );

    final body = _decode(response);
    if (response.statusCode == 200 && body['data'] != null) {
      return UserProfile.fromJson(body['data'] as Map<String, dynamic>);
    }

    throw ApiException(
      _extractError(body) ?? '프로필 업데이트에 실패했습니다.',
      response.statusCode,
    );
  }

  Future<DashboardOverview> fetchDashboardOverview(String token) async {
    final response = await _httpClient.get(
      _uri('/dashboard/overview'),
      headers: _jsonHeaders(token: token),
    );

    final body = _decode(response);
    if (response.statusCode == 200 && body['data'] != null) {
      return DashboardOverview.fromJson(body['data'] as Map<String, dynamic>);
    }

    throw ApiException(
      _extractError(body) ?? '대시보드 요약을 불러오지 못했습니다.',
      response.statusCode,
    );
  }

  Future<List<SafeOnDevice>> fetchDashboardDevices(String token) async {
    final response = await _httpClient.get(
      _uri('/dashboard/devices'),
      headers: _jsonHeaders(token: token),
    );

    final body = _decode(response);
    if (response.statusCode == 200 && body['data'] != null) {
      final data = body['data'] as Map<String, dynamic>;
      final devices = data['devices'] as List<dynamic>? ?? [];
      return devices
          .map((item) => SafeOnDevice.fromDashboardJson(
              item as Map<String, dynamic>))
          .toList();
    }

    throw ApiException(
      _extractError(body) ?? '디바이스 목록을 불러올 수 없습니다.',
      response.statusCode,
    );
  }

  Future<List<SafeOnDevice>> fetchDiscoveredDevices(String token) async {
    final response = await _httpClient.get(
      _uri('/devices', {'discovered': 'false'}),
      headers: _jsonHeaders(token: token),
    );

    final body = _decode(response);
    if (response.statusCode == 200 && body['data'] != null) {
      final devices = body['data'] as List<dynamic>? ?? [];
      return devices
          .map((item) =>
              SafeOnDevice.fromDashboardJson(item as Map<String, dynamic>))
          .toList();
    }

    throw ApiException(
      _extractError(body) ?? '발견된 기기 목록을 불러올 수 없습니다.',
      response.statusCode,
    );
  }

  Future<SafeOnDevice> claimDevice({
    required String token,
    required SafeOnDevice device,
  }) async {
    final response = await _httpClient.post(
      _uri('/devices/${device.id}/claim'),
      headers: _jsonHeaders(token: token),
      body: jsonEncode({
        'macAddress': device.macAddress,
        'name': device.name,
        'ip': device.ip,
      }),
    );

    final body = _decode(response);
    if (response.statusCode == 200 && body['data'] != null) {
      return SafeOnDevice.fromDashboardJson(
          body['data'] as Map<String, dynamic>);
    }

    throw ApiException(
      _extractError(body) ?? '기기 등록에 실패했습니다.',
      response.statusCode,
    );
  }

  Future<void> deleteDevice({
    required String token,
    required String deviceId,
  }) async {
    // 일부 백엔드 구현은 /dashboard/devices/:id 를 사용하므로, 기본 경로 실패 시 보조 경로를 시도한다.
    final primary = await _httpClient.delete(
      _uri('/devices/$deviceId'),
      headers: _jsonHeaders(token: token),
    );

    if (primary.statusCode == 200 || primary.statusCode == 204) {
      return;
    }

    if (primary.statusCode == 404 || primary.statusCode == 405) {
      final fallback = await _httpClient.delete(
        _uri('/dashboard/devices/$deviceId'),
        headers: _jsonHeaders(token: token),
      );
      if (fallback.statusCode == 200 || fallback.statusCode == 204) {
        return;
      }
      final body = _decode(fallback);
      throw ApiException(
        _extractError(body) ?? '디바이스 삭제에 실패했습니다.',
        fallback.statusCode,
      );
    }

    final body = _decode(primary);
    throw ApiException(
      _extractError(body) ?? '디바이스 삭제에 실패했습니다.',
      primary.statusCode,
    );
  }

  Future<void> blockDevice({
    required String token,
    required String deviceId,
    required String macAddress,
    String? ip,
    String? name,
  }) async {
    final response = await _httpClient.post(
      _uri('/devices/block'),
      headers: _jsonHeaders(token: token),
      body: jsonEncode({
        'deviceId': deviceId,
        'macAddress': macAddress,
        if (ip != null && ip.isNotEmpty) 'ip': ip,
        if (name != null && name.isNotEmpty) 'name': name,
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 204) {
      return;
    }

    final body = _decode(response);
    throw ApiException(
      _extractError(body) ?? '디바이스 차단에 실패했습니다.',
      response.statusCode,
    );
  }

  Future<List<SafeOnAlert>> fetchRecentAlerts(String token, {int? limit}) async {
    final response = await _httpClient.get(
      _uri('/dashboard/alerts', limit != null ? {'limit': '$limit'} : null),
      headers: _jsonHeaders(token: token),
    );

    final body = _decode(response);
    if (response.statusCode == 200 && body['data'] != null) {
      final data = body['data'] as Map<String, dynamic>;
      final alerts = data['alerts'] as List<dynamic>? ?? [];
      return alerts
          .map((item) =>
              SafeOnAlert.fromDashboardJson(item as Map<String, dynamic>))
          .toList();
    }

    throw ApiException(
      _extractError(body) ?? '최근 알림을 불러올 수 없습니다.',
      response.statusCode,
    );
  }

  Future<void> acknowledgeAlert({
    required String token,
    required String alertId,
  }) async {
    final response = await _httpClient.post(
      _uri('/alerts/$alertId/ack'),
      headers: _jsonHeaders(token: token),
    );

    if (response.statusCode == 200 || response.statusCode == 204) {
      return;
    }

    final body = _decode(response);
    throw ApiException(
      _extractError(body) ?? '알림을 읽음 처리하지 못했습니다.',
      response.statusCode,
    );
  }

  Future<void> enableMlModel(String token) async {
    final response = await _httpClient.post(
      _uri('/ml/enable'),
      headers: _jsonHeaders(token: token),
    );

    if (response.statusCode == 200 || response.statusCode == 204) {
      return;
    }

    final body = _decode(response);
    throw ApiException(
      _extractError(body) ?? 'ML 모델을 활성화하지 못했습니다.',
      response.statusCode,
    );
  }

  Future<void> disableMlModel(String token) async {
    final response = await _httpClient.post(
      _uri('/ml/disable'),
      headers: _jsonHeaders(token: token),
    );

    if (response.statusCode == 200 || response.statusCode == 204) {
      return;
    }

    final body = _decode(response);
    throw ApiException(
      _extractError(body) ?? 'ML 모델을 비활성화하지 못했습니다.',
      response.statusCode,
    );
  }

  Map<String, dynamic> _decode(http.Response response) {
    try {
      return jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  String? _extractError(Map<String, dynamic> body) {
    final data = body['data'];
    if (data is Map<String, dynamic>) {
      return data['message'] as String? ?? data['error'] as String?;
    }
    return null;
  }

  Future<List<DailyAnomalyCount>> fetchDailyAnomalyCounts(
    String token, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final formatter = DateFormat('yyyy-MM-dd');
    final query = <String, dynamic>{
      if (startDate != null) 'startDate': formatter.format(startDate),
      if (endDate != null) 'endDate': formatter.format(endDate),
    };

    final response = await _httpClient.get(
      _uri('/dashboard/anomalies/daily', query.isEmpty ? null : query),
      headers: _jsonHeaders(token: token),
    );

    final body = _decode(response);
    if (response.statusCode == 200 && body['data'] != null) {
      final data = body['data'] as Map<String, dynamic>;
      final items = data['data'] as List<dynamic>? ?? [];
      return items
          .map((item) =>
              DailyAnomalyCount.fromJson(item as Map<String, dynamic>))
          .toList();
    }

    throw ApiException(
      _extractError(body) ?? '이상 탐지 집계를 불러올 수 없습니다.',
      response.statusCode,
    );
  }
}
