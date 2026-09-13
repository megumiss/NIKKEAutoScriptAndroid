import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile/core/widgets/icon_box.dart';
import 'package:nkas_mobile/core/widgets/tag.dart';

/// 队列任务行：图标 + 名称/命令 + 时间标签，实例详情与任务页共用
class QueueRow extends StatelessWidget {
  const QueueRow({
    required this.name,
    required this.detail,
    required this.time,
    required this.color,
    required this.icon,
    required this.onTap,
    super.key,
  });
  final String name;
  final String detail;
  final String time;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
          child: Row(
            children: [
              IconBox(icon: icon, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(detail, style: theme.textTheme.muted),
                  ],
                ),
              ),
              Tag(label: time, color: color),
              const SizedBox(width: 5),
              Icon(
                LucideIcons.chevronRight,
                size: 15,
                color: theme.colorScheme.mutedForeground,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
