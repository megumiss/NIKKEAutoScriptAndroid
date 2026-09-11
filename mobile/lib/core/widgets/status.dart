import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile_preview/theme.dart';

enum InstanceStatus {
  running('运行中'),
  idle('空闲'),
  error('异常'),
  updating('更新中');

  const InstanceStatus(this.label);
  final String label;

  static InstanceStatus fromCode(int code) => switch (code) {
    1 => InstanceStatus.running,
    3 => InstanceStatus.error,
    4 => InstanceStatus.updating,
    _ => InstanceStatus.idle,
  };
}

class Status extends StatelessWidget {
  const Status({super.key, required this.status});
  final InstanceStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final color = switch (status) {
      InstanceStatus.running => theme.colorScheme.success,
      InstanceStatus.idle => theme.colorScheme.warning,
      InstanceStatus.error => theme.colorScheme.destructive,
      InstanceStatus.updating => theme.colorScheme.primary,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Dot(color: color),
        const SizedBox(width: 5),
        Text(
          status.label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class Dot extends StatelessWidget {
  const Dot({super.key, required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 7,
    height: 7,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}
