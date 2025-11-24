import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/alert.dart';
import '../models/dashboard_overview.dart';
import '../models/device.dart';
import '../models/user_profile.dart';

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
}