class ScheduleTask {
  const ScheduleTask({
    required this.command,
    required this.name,
    required this.enabled,
    required this.locked,
    required this.enableLocked,
    required this.cadence,
    required this.cadenceLocked,
    required this.nextRun,
    required this.dailyTimes,
    required this.weeklyDays,
    required this.weeklyTime,
    required this.monthlyDay,
    required this.monthlyTime,
  });

  factory ScheduleTask.fromJson(Map<String, dynamic> json) => ScheduleTask(
    command: json['command']?.toString() ?? '',
    name: json['name_i18n']?.toString() ?? json['command']?.toString() ?? '',
    enabled: json['enabled'] == true,
    locked: json['locked'] == true,
    enableLocked: json['enable_locked'] == true,
    cadence: json['cadence']?.toString() ?? 'daily',
    cadenceLocked: json['cadence_locked'] == true,
    nextRun: json['next_run']?.toString() ?? '',
    dailyTimes: json['daily_times']?.toString() ?? '04:00',
    weeklyDays: json['weekly_days']?.toString() ?? '2',
    weeklyTime: json['weekly_time']?.toString() ?? '04:00',
    monthlyDay: json['monthly_day']?.toString() ?? '1',
    monthlyTime: json['monthly_time']?.toString() ?? '04:00',
  );

  final String command;
  final String name;
  final bool enabled;
  final bool locked;
  final bool enableLocked;
  final String cadence;
  final bool cadenceLocked;
  final String nextRun;
  final String dailyTimes;
  final String weeklyDays;
  final String weeklyTime;
  final String monthlyDay;
  final String monthlyTime;

  String get activeTime => switch (cadence) {
    'weekly' => weeklyTime,
    'monthly' => monthlyTime,
    _ => dailyTimes,
  };
}
