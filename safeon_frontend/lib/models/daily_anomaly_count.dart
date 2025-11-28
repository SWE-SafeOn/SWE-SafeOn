class DailyAnomalyCount {
  const DailyAnomalyCount({
    required this.date,
    required this.count,
  });

  final DateTime date;
  final int count;

  factory DailyAnomalyCount.fromJson(Map<String, dynamic> json) {
    final rawDate = json['date'] as String?;
    return DailyAnomalyCount(
      date: rawDate != null
          ? (DateTime.tryParse(rawDate) ?? DateTime.fromMillisecondsSinceEpoch(0))
          : DateTime.fromMillisecondsSinceEpoch(0),
      count: (json['count'] as num?)?.toInt() ?? 0,
    );
  }
}
