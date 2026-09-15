class UpdateCommit {
  const UpdateCommit({this.sha, this.author, this.date, this.message});

  /// 后端提交记录是 4 元素数组 [sha, author, isotime, message]，
  /// 失败时是 [null, null, null, null]，返回 null 表示无效
  static UpdateCommit? fromArray(Object? value) {
    if (value is! List || value.isEmpty || value[0] == null) return null;
    String? at(int index) =>
        index < value.length ? value[index]?.toString() : null;
    return UpdateCommit(sha: at(0), author: at(1), date: at(2), message: at(3));
  }

  final String? sha;
  final String? author;
  final String? date;
  final String? message;

  String get dateLabel {
    final value = date ?? '';
    return value.length > 10 ? value.substring(0, 10) : value;
  }
}

class UpdateInfo {
  const UpdateInfo({
    required this.state,
    this.error,
    this.local,
    this.upstream,
    this.history = const [],
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) => UpdateInfo(
    state: json['state'],
    error: json['error']?.toString(),
    local: _commit(json['local']),
    upstream: _commit(json['upstream']),
    history: _history(json['history']),
  );

  final Object? state;
  final String? error;
  final List<Object?>? local;
  final List<Object?>? upstream;
  final List<UpdateCommit> history;

  String? get localSha =>
      local != null && local!.isNotEmpty ? local![0]?.toString() : null;

  bool get checking => state == 'checking';
  bool get running =>
      state == 'start' || state == 'wait' || state == 'run update';
  bool get available => state == 1 || state == '1';

  /// 有更新：后端状态为 1；后端未检查或状态陈旧时用提交记录兜底，
  /// 本地提交在记录中不是最新一条即视为落后，避免误显示已是最新
  bool get updateAvailable {
    if (available) return true;
    final sha = localSha;
    if (sha == null) return false;
    return history.indexWhere((commit) => commit.sha == sha) > 0;
  }

  String get stateLabel {
    if (checking) return '检查中';
    if (running) return '更新中';
    if (state == 'failed') return '更新失败';
    if (updateAvailable) return '有新版本';
    return '已是最新';
  }

  static List<Object?>? _commit(Object? value) {
    return value is List ? List<Object?>.unmodifiable(value) : null;
  }

  static List<UpdateCommit> _history(Object? value) {
    if (value is! List) return const [];
    final commits = <UpdateCommit>[];
    for (final item in value) {
      final commit = UpdateCommit.fromArray(item);
      if (commit != null) commits.add(commit);
    }
    return List<UpdateCommit>.unmodifiable(commits);
  }
}
