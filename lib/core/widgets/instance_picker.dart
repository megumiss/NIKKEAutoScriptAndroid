import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile/core/api/instance_info.dart';
import 'package:nkas_mobile/core/widgets/avatar.dart';
import 'package:nkas_mobile/theme.dart';

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
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .75,
        ),
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
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final item in instances)
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                          ),
                          shape: const RoundedRectangleBorder(
                            borderRadius: NkasInputStyle.radius,
                          ),
                          selected: item.name == selected,
                          selectedTileColor: ShadTheme.of(
                            context,
                          ).colorScheme.accentSoft,
                          leading: Avatar(
                            text: item.name.characters.first,
                            imageUrl: avatarUrl(item),
                          ),
                          title: Text(
                            item.name,
                            style: ShadTheme.of(context).textTheme.p,
                          ),
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
            ],
          ),
        ),
      ),
    ),
  );
}
