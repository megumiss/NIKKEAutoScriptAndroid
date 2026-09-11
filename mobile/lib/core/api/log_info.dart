class LogFileRef {
  const LogFileRef({required this.date, required this.source});

  factory LogFileRef.fromJson(Map<String, dynamic> json) => LogFileRef(
    date: json['date']?.toString() ?? '',
    source: json['source']?.toString() ?? '',
  );

  final String date;
  final String source;
}

class LogRecord {
  const LogRecord({
    required this.time,
    required this.level,
    required this.rank,
    required this.source,
    required this.text,
    this.kind,
    this.traceback,
    this.tracebackCollapsed,
  });

  factory LogRecord.fromJson(Map<String, dynamic> json) => LogRecord(
    time: json['time']?.toString() ?? '',
    level: json['level']?.toString() ?? 'INFO',
    rank: (json['rank'] as num?)?.toInt() ?? 1,
    source: json['source']?.toString() ?? '',
    text: json['text']?.toString() ?? '',
    kind: json['kind']?.toString(),
    traceback: json['traceback']?.toString(),
    tracebackCollapsed: json['traceback_collapsed']?.toString(),
  );

  final String time;
  final String level;
  final int rank;
  final String source;
  final String text;
  final String? kind;
  final String? traceback;
  final String? tracebackCollapsed;
}

class LogQueryResult {
  const LogQueryResult({
    required this.records,
    required this.matched,
    required this.truncated,
  });

  factory LogQueryResult.fromJson(Map<String, dynamic> json) => LogQueryResult(
    records: (json['records'] is List ? json['records'] as List : const [])
        .whereType<Map<String, dynamic>>()
        .map(LogRecord.fromJson)
        .toList(growable: false),
    matched: (json['matched'] as num?)?.toInt() ?? 0,
    truncated: json['truncated'] == true,
  );

  final List<LogRecord> records;
  final int matched;
  final bool truncated;
}
