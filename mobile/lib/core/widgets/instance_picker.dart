import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile/core/api/instance_info.dart';
import 'package:nkas_mobile/core/widgets/avatar.dart';

/// 实例切换弹窗：实例、画面、任务页共用的底部列表
Future<void> showInstancePicker(
  BuildContext context, {
  required List<InstanceInfo> instances,
  required String selected,
  required bool loading,
  required String? error,
  required String? Function(InstanceInfo item) avatarUrl,
  required ValueChanged<String> onSelect,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('切换实例', style: ShadTheme.of(context).textTheme.h3),
            const SizedBox(height: 8),
            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (instances.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Text(
                  error == null ? '暂无实例' : '实例加载失败，请检查后端连接',
                  style: ShadTheme.of(context).textTheme.muted,
                ),
              ),
            for (final item in instances)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Avatar(
                  text: item.name.characters.first,
                  imageUrl: avatarUrl(item),
                ),
                title: Text(item.name),
                trailing: Icon(
                  item.name == selected
                      ? LucideIcons.check
                      : LucideIcons.chevronRight,
                ),
                onTap: () {
                  onSelect(item.name);
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    ),
  );
}
