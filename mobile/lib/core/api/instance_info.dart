import 'package:nkas_mobile_preview/core/widgets/status.dart';

class InstanceInfo {
  const InstanceInfo({
    required this.name,
    required this.state,
    required this.mod,
    this.currentTask,
    this.nextTask,
    this.remark = '',
    this.avatar = '',
  });

  factory InstanceInfo.fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    final state = json['state'];
    if (name is! String || state is! int) {
      throw const FormatException('实例数据缺少 name 或 state');
    }
    return InstanceInfo(
      name: name,
      state: state,
      mod: json['mod']?.toString() ?? '',
      currentTask: json['current_task']?.toString(),
      nextTask: json['next_task']?.toString(),
      remark: json['remark']?.toString() ?? '',
      avatar: json['avatar']?.toString() ?? '',
    );
  }

  final String name;
  final int state;
  final String mod;
  final String? currentTask;
  final String? nextTask;
  final String remark;
  final String avatar;

  String get detail {
    if (currentTask != null && currentTask!.isNotEmpty) {
      return '正在执行 · $currentTask';
    }
    if (nextTask != null && nextTask!.isNotEmpty) {
      return '下一任务 · $nextTask';
    }
    return remark.isNotEmpty ? remark : '暂无运行任务';
  }

  bool get isRunning => state == 1;

  InstanceStatus get status => InstanceStatus.fromCode(state);

  InstanceInfo copyWith({int? state}) => InstanceInfo(
    name: name,
    state: state ?? this.state,
    mod: mod,
    currentTask: currentTask,
    nextTask: nextTask,
    remark: remark,
    avatar: avatar,
  );
}
