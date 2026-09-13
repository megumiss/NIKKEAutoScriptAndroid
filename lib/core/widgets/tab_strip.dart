import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile/theme.dart';

/// 页面上方横向 tab 条（实例详情、任务页共用）：选中胶囊 accentSoft 底 +
/// primary 字，未选中 muted，超出可横向滚动
class NkasTabStrip<T> extends StatelessWidget {
  const NkasTabStrip({
    required this.tabs,
    required this.selected,
    required this.onSelect,
    super.key,
  });

  final List<(T, String)> tabs;
  final T selected;
  final ValueChanged<T> onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            _TabChip(
              label: tabs[i].$2,
              selected: selected == tabs[i].$1,
              onTap: () => onSelect(tabs[i].$1),
            ),
          ],
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = ShadTheme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? scheme.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? scheme.primary : scheme.mutedForeground,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            height: 1,
          ),
        ),
      ),
    );
  }
}
