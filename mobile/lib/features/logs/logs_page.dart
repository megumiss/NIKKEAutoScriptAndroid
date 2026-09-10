import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile_preview/core/widgets/field_select.dart';
import 'package:nkas_mobile_preview/core/widgets/log_line.dart';
import 'package:nkas_mobile_preview/core/widgets/page_inset.dart';
import 'package:nkas_mobile_preview/core/widgets/page_subtitle.dart';
import 'package:nkas_mobile_preview/core/widgets/surface.dart';
import 'package:nkas_mobile_preview/theme.dart';

class LogsPage extends StatelessWidget {
  const LogsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final inset = nkasPageInset(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(inset, 5, inset, 88),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageSubtitle('查看 log 目录下的日志文件'),
          Surface(
            padding: EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  flex: 10,
                  child: FieldSelect(label: '日期', value: '2026-09-10'),
                ),
                SizedBox(width: 8),
                Expanded(
                  flex: 7,
                  child: FieldSelect(label: '类型', value: '全部'),
                ),
                SizedBox(width: 8),
                Expanded(
                  flex: 7,
                  child: FieldSelect(label: '级别', value: '全部'),
                ),
              ],
            ),
          ),
          SizedBox(height: 12),
          Expanded(
            child: LogCard(
              title: '日志文件',
              showActions: true,
              fill: true,
              rows: [
                ('09:24:42', 'INFO', '主账号', '读取任务配置并加入调度队列', LogKind.info),
                ('09:24:24', 'INFO', '小号', '检测设备连接状态正常', LogKind.info),
                ('09:23:42', 'WARN', '服务', '等待游戏窗口响应，稍后重试', LogKind.warn),
                ('09:23:24', 'INFO', '主账号', '同步实例运行状态', LogKind.info),
                ('09:22:42', 'ERROR', '测试账号', '任务执行失败，等待下一次调度', LogKind.error),
                ('09:22:24', 'INFO', '主账号', '读取任务配置并加入调度队列', LogKind.info),
                ('09:21:42', 'INFO', '小号', '检测设备连接状态正常', LogKind.info),
                ('09:20:42', 'WARN', '服务', '等待游戏窗口响应，稍后重试', LogKind.warn),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class LogCard extends StatelessWidget {
  const LogCard({
    super.key,
    required this.title,
    required this.rows,
    this.showActions = false,
    this.fill = false,
  });
  final String title;
  final bool showActions;

  /// true 时日志体用 Expanded 填满剩余高度并内部滚动（日志页）；
  /// false 时固定 min-height，随外层列表滚动（实例实时日志）。
  final bool fill;
  final List<(String, String, String?, String, LogKind)> rows;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final scheme = theme.colorScheme;
    final lines = [
      for (final row in rows)
        LogLine(
          time: row.$1,
          level: row.$2,
          source: row.$3,
          message: row.$4,
          kind: row.$5,
        ),
    ];
    return Surface(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 2, 8, 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (showActions) ...[
                    _LogAction(icon: LucideIcons.refreshCw, tooltip: '刷新日志'),
                    _LogAction(icon: LucideIcons.download, tooltip: '导出日志'),
                  ],
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          if (fill)
            Expanded(
              child: Container(
                width: double.infinity,
                color: scheme.logBodyBg,
                child: ListView(
                  padding: const EdgeInsets.all(8),
                  children: lines,
                ),
              ),
            )
          else
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 220),
              color: scheme.logBodyBg,
              padding: const EdgeInsets.all(8),
              child: Column(children: lines),
            ),
          if (showActions) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: [
                  Text(
                    '31 条记录',
                    style: TextStyle(
                      color: scheme.mutedForeground,
                      fontSize: 11,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '2026-09-10',
                    style: TextStyle(
                      color: scheme.mutedForeground,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LogAction extends StatelessWidget {
  const _LogAction({required this.icon, required this.tooltip});
  final IconData icon;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = ShadTheme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(9),
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(icon, size: 17, color: scheme.mutedForeground),
        ),
      ),
    );
  }
}
