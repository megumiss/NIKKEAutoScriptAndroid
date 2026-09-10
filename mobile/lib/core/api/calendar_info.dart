class CalendarItem {
  const CalendarItem({
    required this.category,
    required this.title,
    required this.subtitle,
    required this.startTime,
    required this.endTime,
    this.subtype,
    this.bannerUrl,
  });

  factory CalendarItem.fromJson(Map<String, dynamic> json) => CalendarItem(
    category: json['category']?.toString() ?? '',
    title: json['title']?.toString() ?? '',
    subtitle: json['subtitle']?.toString() ?? '',
    startTime: (json['start_time'] as num?)?.toInt() ?? 0,
    endTime: (json['end_time'] as num?)?.toInt() ?? 0,
    subtype: json['subtype']?.toString(),
    bannerUrl: json['banner_url']?.toString(),
  );

  final String category;
  final String title;
  final String subtitle;
  final int startTime;
  final int endTime;
  final String? subtype;
  final String? bannerUrl;
}

class CalendarInfo {
  const CalendarInfo({required this.updatedAt, required this.items});

  factory CalendarInfo.fromJson(Map<String, dynamic> json) => CalendarInfo(
    updatedAt: (json['updated_at'] as num?)?.toInt() ?? 0,
    items: (json['items'] is List ? json['items'] as List : const [])
        .whereType<Map<String, dynamic>>()
        .map(CalendarItem.fromJson)
        .toList(growable: false),
  );

  final int updatedAt;
  final List<CalendarItem> items;
}
