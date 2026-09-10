import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// 页面标题下单行说明：13px muted、省略号截断、min-height 19、下间距 14
class PageSubtitle extends StatelessWidget {
  const PageSubtitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        constraints: const BoxConstraints(minHeight: 19),
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: theme.colorScheme.mutedForeground,
            fontSize: 13,
            height: 19 / 13,
          ),
        ),
      ),
    );
  }
}
