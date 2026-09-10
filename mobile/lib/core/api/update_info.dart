class UpdateInfo {
  const UpdateInfo({
    required this.state,
    this.error,
    this.local,
    this.upstream,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) => UpdateInfo(
    state: json['state'],
    error: json['error']?.toString(),
    local: _commit(json['local']),
    upstream: _commit(json['upstream']),
  );

  final Object? state;
  final String? error;
  final List<Object?>? local;
  final List<Object?>? upstream;

  bool get checking => state == 'checking';
  bool get running =>
      state == 'start' || state == 'wait' || state == 'run update';
  bool get available => state == 1 || state == '1';

  String get stateLabel {
    if (checking) return '检查中';
    if (running) return '更新中';
    if (available) return '有新版本';
    if (state == 'failed') return '更新失败';
    return '已是最新';
  }

  static List<Object?>? _commit(Object? value) {
    return value is List ? List<Object?>.unmodifiable(value) : null;
  }
}
