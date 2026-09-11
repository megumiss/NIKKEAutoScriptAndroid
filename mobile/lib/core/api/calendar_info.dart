class CalendarItem {
  const CalendarItem({
    required this.id,
    required this.category,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.startTime,
    required this.endTime,
    this.subtype,
    this.stageStartTime,
    this.stageEndTime,
    this.sourceOrder = 0,
    this.bannerMode = 'placeholder',
    this.bannerUrl,
    this.characterUrl,
    this.backgroundUrl,
  });

  factory CalendarItem.fromJson(Map<String, dynamic> json) => CalendarItem(
    id: json['id']?.toString() ?? '',
    category: json['category']?.toString() ?? '',
    type: json['type']?.toString() ?? '',
    title: json['title']?.toString() ?? '',
    subtitle: json['subtitle']?.toString() ?? '',
    startTime: (json['start_time'] as num?)?.toInt() ?? 0,
    endTime: (json['end_time'] as num?)?.toInt() ?? 0,
    subtype: json['subtype']?.toString(),
    stageStartTime: (json['stage_start_time'] as num?)?.toInt(),
    stageEndTime: (json['stage_end_time'] as num?)?.toInt(),
    sourceOrder: (json['source_order'] as num?)?.toInt() ?? 0,
    bannerMode: json['banner_mode']?.toString() ?? 'placeholder',
    bannerUrl: json['banner_url']?.toString(),
    characterUrl: json['character_url']?.toString(),
    backgroundUrl: json['background_url']?.toString(),
  );

  final String id;
  final String category;
  final String type;
  final String title;
  final String subtitle;
  final int startTime;
  final int endTime;
  final String? subtype;
  final int? stageStartTime;
  final int? stageEndTime;
  final int sourceOrder;
  final String bannerMode;
  final String? bannerUrl;
  final String? characterUrl;
  final String? backgroundUrl;
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
