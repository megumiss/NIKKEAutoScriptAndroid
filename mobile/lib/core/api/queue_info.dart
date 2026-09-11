class QueueItem {
  const QueueItem({
    required this.command,
    required this.nextRun,
    required this.name,
  });

  factory QueueItem.fromJson(Map<String, dynamic> json) => QueueItem(
    command: json['command']?.toString() ?? '',
    nextRun: json['next_run']?.toString() ?? '',
    name: json['name_i18n']?.toString() ?? json['command']?.toString() ?? '',
  );

  final String command;
  final String nextRun;
  final String name;
}

class QueueInfo {
  const QueueInfo({
    required this.running,
    required this.pending,
    required this.waiting,
  });

  factory QueueInfo.fromJson(Map<String, dynamic> json) {
    List<QueueItem> parse(Object? value) => value is List
        ? value
              .map((item) => QueueItem.fromJson(item as Map<String, dynamic>))
              .toList(growable: false)
        : const [];
    return QueueInfo(
      running: parse(json['running']),
      pending: parse(json['pending']),
      waiting: parse(json['waiting']),
    );
  }

  final List<QueueItem> running;
  final List<QueueItem> pending;
  final List<QueueItem> waiting;
}
