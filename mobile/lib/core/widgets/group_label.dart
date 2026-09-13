import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// 分组标签（设置、关于、控制连接、部署、任务配置共用）：
/// muted 小字，左 3px、下 8px 间距，置于分组 Surface 上方
class GroupLabel extends StatelessWidget {
  const GroupLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 3, bottom: 8),
    child: Text(label, style: ShadTheme.of(context).textTheme.muted),
  );
}
