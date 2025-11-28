class DailyAnomalyCount {
  const DailyAnomalyCount({
    required this.date,
    required this.count,
  });

  final DateTime date;
  final int count;

  factory DailyAnomalyCount.fromJson(Map<String, dynamic> json) {
    final rawDate = json['date'] as String?;
    final rawTs = json['ts'] ?? json['timestamp'];
    final parsedDate = _parseDate(rawDate) ?? _parseTimestamp(rawTs);

    // If server already aggregated, use provided count; otherwise fall back to is_anom flag.
    final isAnom = (json['is_anom'] ?? json['isAnom']) == true;
    final int count = (json['count'] as num?)?.toInt() ?? (isAnom ? 1 : 0);

    return DailyAnomalyCount(
      date: parsedDate ?? DateTime.fromMillisecondsSinceEpoch(0),
      count: count,
    );
  }

  static DateTime? _parseDate(String? raw) {
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  static DateTime? _parseTimestamp(dynamic raw) {
    if (raw == null) return null;
    if (raw is String) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return parsed.toLocal();
    } else if (raw is int) {
      return DateTime.fromMillisecondsSinceEpoch(raw).toLocal();
    } else if (raw is double) {
      return DateTime.fromMillisecondsSinceEpoch(raw.toInt()).toLocal();
    }
    return null;
  }
}
