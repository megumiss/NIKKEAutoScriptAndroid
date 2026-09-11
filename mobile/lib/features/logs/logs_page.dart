import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'dart:typed_data';
import 'package:share_plus/share_plus.dart';

import 'package:nkas_mobile/core/api/log_info.dart';
import 'package:nkas_mobile/core/connection/connection_controller.dart';
import 'package:nkas_mobile/core/widgets/field_select.dart';
import 'package:nkas_mobile/core/widgets/log_line.dart';
import 'package:nkas_mobile/core/widgets/page_inset.dart';
import 'package:nkas_mobile/core/widgets/page_subtitle.dart';
import 'package:nkas_mobile/core/widgets/surface.dart';
import 'package:nkas_mobile/theme.dart';

class LogsPage extends StatefulWidget {
  const LogsPage({required this.connectionController, super.key});

  final ConnectionController connectionController;

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  List<LogFileRef> files = const [];
  LogQueryResult? result;
  String date = '';
  String source = '';
  String level = 'info';
  bool loading = false;
  String? error;
  String? loadedBaseUrl;
  int querySequence = 0;
  bool sourceInitialized = false;

  @override
  void initState() {
    super.initState();
    widget.connectionController.addListener(_connectionChanged);
    _refresh();
  }

  @override
  void dispose() {
    widget.connectionController.removeListener(_connectionChanged);
    super.dispose();
  }

  void _connectionChanged() {
    final connection = widget.connectionController.state;
    if (connection.phase == ConnectionPhase.connected &&
        loadedBaseUrl != connection.baseUrl &&
        !loading) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    if (!mounted ||
        widget.connectionController.state.phase != ConnectionPhase.connected) {
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final baseUrl = widget.connectionController.state.baseUrl;
      final nextFiles = await widget.connectionController.fetchLogFiles();
      if (!mounted || widget.connectionController.state.baseUrl != baseUrl) {
        return;
      }
      final dates = nextFiles.map((file) => file.date).toSet();
      final nextDate = dates.contains(date)
          ? date
          : (nextFiles.isEmpty ? '' : nextFiles.first.date);
      final sources = nextFiles
          .where((file) => file.date == nextDate)
          .map((file) => file.source)
          .toSet();
      final nextSource = !sourceInitialized
          ? (sources.isEmpty ? '' : sources.first)
          : (source.isEmpty || sources.contains(source) ? source : '');
      setState(() {
        files = nextFiles;
        date = nextDate;
        source = nextSource;
        loadedBaseUrl = baseUrl;
        sourceInitialized = true;
      });
      await _query();
    } catch (exception) {
      if (mounted) setState(() => error = exception.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _query() async {
    final sequence = ++querySequence;
    if (date.isEmpty ||
        widget.connectionController.state.phase != ConnectionPhase.connected) {
      if (mounted) {
        setState(() {
          result = null;
          loading = false;
        });
      }
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final nextResult = await widget.connectionController.fetchLogs(
        date: date,
        source: source,
        level: level,
      );
      if (mounted && sequence == querySequence) {
        setState(() {
          result = nextResult;
          error = null;
        });
      }
    } catch (exception) {
      if (mounted && sequence == querySequence) {
        setState(() => error = exception.toString());
      }
    } finally {
      if (mounted && sequence == querySequence) {
        setState(() => loading = false);
      }
    }
  }

  List<String> get dates => files.map((file) => file.date).toSet().toList();

  List<String> get sources => files
      .where((file) => file.date == date)
      .map((file) => file.source)
      .toSet()
      .toList();

  @override
  Widget build(BuildContext context) {
    final inset = nkasPageInset(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(inset, 5, inset, 88),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageSubtitle('查看 log 目录下的日志文件'),
          Expanded(
            child: LogCard(
              title: '日志文件',
              showActions: true,
              fill: true,
              loading: loading,
              error: error,
              date: date,
              matched: result?.matched ?? 0,
              truncated: result?.truncated ?? false,
              onRefresh: _refresh,
              onExport: source.isEmpty || date.isEmpty ? null : _export,
              filters: Row(
                children: [
                  Expanded(
                    flex: 10,
                    child: FieldSelect(
                      dense: true,
                      label: '日期',
                      value: date.isEmpty ? '暂无' : date,
                      options: [
                        for (final item in dates) FieldSelectOption(item, item),
                      ],
                      onChanged: (value) async {
                        setState(() {
                          date = value;
                          source = '';
                        });
                        await _query();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 7,
                    child: FieldSelect(
                      dense: true,
                      label: '类型',
                      value: source.isEmpty ? '全部' : source,
                      options: [
                        const FieldSelectOption('', '全部'),
                        for (final item in sources)
                          FieldSelectOption(item, item),
                      ],
                      onChanged: (value) async {
                        setState(() => source = value);
                        await _query();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 7,
                    child: FieldSelect(
                      dense: true,
                      label: '级别',
                      value: _levelLabel(level),
                      options: const [
                        FieldSelectOption('debug', 'DEBUG'),
                        FieldSelectOption('info', 'INFO'),
                        FieldSelectOption('warn', 'WARN'),
                        FieldSelectOption('err', 'ERROR'),
                      ],
                      onChanged: (value) async {
                        setState(() => level = value);
                        await _query();
                      },
                    ),
                  ),
                ],
              ),
              rows: [
                for (final item in result?.records ?? const <LogRecord>[])
                  LogRowData(
                    time: item.time,
                    level: item.level,
                    source: source.isEmpty ? item.source : null,
                    message: item.text,
                    kind: _logKind(item.rank),
                    traceback: item.traceback,
                    tracebackCollapsed: item.tracebackCollapsed,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _export() async {
    try {
      final bytes = await widget.connectionController.downloadLog(
        date: date,
        source: source,
      );
      final safeDate = date.replaceAll(RegExp(r'[^0-9-]'), '');
      final safeSource = source.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final filename =
          'nkas-$safeDate${safeSource.isEmpty ? '' : '-$safeSource'}.log';
      await Share.shareXFiles([
        XFile.fromData(
          Uint8List.fromList(bytes),
          mimeType: 'text/plain',
          name: filename,
        ),
      ], subject: filename);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('导出日志失败：$error')));
      }
    }
  }

  static String _levelLabel(String value) => switch (value) {
    'debug' => 'DEBUG',
    'warn' => 'WARN',
    'err' => 'ERROR',
    _ => 'INFO',
  };

  static LogKind _logKind(int rank) => switch (rank) {
    >= 3 => LogKind.error,
    2 => LogKind.warn,
    _ => LogKind.info,
  };
}

class LogRowData {
  const LogRowData({
    required this.time,
    required this.level,
    required this.source,
    required this.message,
    required this.kind,
    this.traceback,
    this.tracebackCollapsed,
  });

  final String time;
  final String level;
  final String? source;
  final String message;
  final LogKind kind;
  final String? traceback;
  final String? tracebackCollapsed;
}

class LogCard extends StatelessWidget {
  const LogCard({
    super.key,
    required this.title,
    required this.rows,
    this.showActions = false,
    this.fill = false,
    this.loading = false,
    this.error,
    this.date,
    this.matched = 0,
    this.truncated = false,
    this.onRefresh,
    this.onExport,
    this.filters,
  });
  final String title;
  final bool showActions;
  final bool fill;
  final bool loading;
  final String? error;
  final String? date;
  final int matched;
  final bool truncated;
  final Future<void> Function()? onRefresh;
  final Future<void> Function()? onExport;
  final Widget? filters;
  final List<LogRowData> rows;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final scheme = theme.colorScheme;
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
                    _LogAction(
                      icon: LucideIcons.refreshCw,
                      tooltip: '刷新日志',
                      onTap: onRefresh,
                    ),
                    _LogAction(
                      icon: LucideIcons.download,
                      tooltip: '导出日志',
                      onTap: onExport,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (filters != null) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
              child: filters,
            ),
          ],
          const Divider(height: 1),
          if (fill)
            Expanded(
              child: Container(
                width: double.infinity,
                color: scheme.logBodyBg,
                child: loading && rows.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : error != null && rows.isEmpty
                    ? Center(
                        child: Text('日志加载失败', style: theme.textTheme.muted),
                      )
                    : rows.isEmpty
                    ? Center(
                        child: Text('没有匹配的日志', style: theme.textTheme.muted),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: rows.length,
                        itemBuilder: (context, index) {
                          final row = rows[index];
                          return LogLine(
                            time: row.time,
                            level: row.level,
                            source: row.source,
                            message: row.message,
                            kind: row.kind,
                            traceback: row.traceback,
                            tracebackCollapsed: row.tracebackCollapsed,
                          );
                        },
                      ),
              ),
            )
          else
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 220),
              color: scheme.logBodyBg,
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  for (final row in rows)
                    LogLine(
                      time: row.time,
                      level: row.level,
                      source: row.source,
                      message: row.message,
                      kind: row.kind,
                      traceback: row.traceback,
                      tracebackCollapsed: row.tracebackCollapsed,
                    ),
                ],
              ),
            ),
          if (showActions) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: [
                  Text(
                    truncated
                        ? '共匹配 $matched 条，仅显示最近 ${rows.length} 条'
                        : '共 $matched 条',
                    style: TextStyle(
                      color: scheme.mutedForeground,
                      fontSize: 11,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    date ?? '',
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
  const _LogAction({required this.icon, required this.tooltip, this.onTap});
  final IconData icon;
  final String tooltip;
  final Future<void> Function()? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = ShadTheme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap == null ? null : () => onTap!(),
        borderRadius: BorderRadius.circular(9),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: Icon(
              icon,
              size: 17,
              color: onTap == null
                  ? scheme.mutedForeground.withValues(alpha: .4)
                  : scheme.mutedForeground,
            ),
          ),
        ),
      ),
    );
  }
}
