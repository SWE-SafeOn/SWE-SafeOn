import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/alert.dart';


class AlertStreamService {
  AlertStreamService({required this.baseUrl});

  final String baseUrl;
  http.Client? _client;
  StreamSubscription<String>? _subscription;

  Future<void> start({
    required String token,
    required void Function(SafeOnAlert alert) onAlert,
    void Function(Object error)? onError,
    void Function()? onDone,
  }) async {
    await stop();

    _client = http.Client();
    final request = http.Request(
      'GET',
      Uri.parse('$baseUrl/dashboard/stream'),
    )..headers.addAll({
        'Accept': 'text/event-stream',
        'Cache-Control': 'no-cache',
        'Authorization': 'Bearer $token',
      });

    final response = await _client!.send(request);
    _subscription = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
      (line) => _handleLine(line, onAlert),
      onError: onError,
      onDone: onDone,
      cancelOnError: false,
    );
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _client?.close();
    _client = null;
    _resetEventBuffer();
  }

  // --- SSE parsing state ---
  String? _currentEvent;
  final List<String> _dataLines = [];

  void _resetEventBuffer() {
    _currentEvent = null;
    _dataLines.clear();
  }

  void _handleLine(String line, void Function(SafeOnAlert alert) onAlert) {
    if (line.isEmpty) {
      _emitEvent(onAlert);
      return;
    }
    if (line.startsWith('event:')) {
      _currentEvent = line.substring(6).trim();
      return;
    }
    if (line.startsWith('data:')) {
      _dataLines.add(line.substring(5).trimLeft());
    }
  }

  void _emitEvent(void Function(SafeOnAlert alert) onAlert) {
    if (_dataLines.isEmpty) {
      _resetEventBuffer();
      return;
    }
    final eventName = _currentEvent?.isNotEmpty == true ? _currentEvent : 'message';
    final rawData = _dataLines.join('\n');
    _resetEventBuffer();

    if (eventName != 'alert') {
      return;
    }
    try {
      final decoded = jsonDecode(rawData);
      if (decoded is Map<String, dynamic>) {
        final alert = SafeOnAlert.fromJson(decoded);
        onAlert(alert);
      }
    } catch (_) {
      // Ignore malformed events.
    }
  }
}
