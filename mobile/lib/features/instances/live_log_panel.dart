import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile/core/connection/instance_log_socket.dart';
import 'package:nkas_mobile/core/widgets/log_line.dart';
import 'package:nkas_mobile/core/widgets/surface.dart';
import 'package:nkas_mobile/theme.dart';

class LiveLogPanel extends StatefulWidget {
  const LiveLogPanel({
    required this.running,
    required this.uri,
    required this.accessGranted,
    super.key,
  });

  final bool running;
  final Uri uri;
  final bool accessGranted;

  @override
  State<LiveLogPanel> createState() => _LiveLogPanelState();
}

class _LiveLogPanelState extends State<LiveLogPanel> {
  String level = 'INFO';
  bool autoScroll = true;
  final scrollController = ScrollController();
  final lines = <_LiveLogLine>[];
  InstanceLogSocket? socket;
  Timer? reconnectTimer;
  bool connected = false;
  String? error;

  @override
  void initState() {
    super.initState();
    unawaited(_connect());
  }

  @override
  void didUpdateWidget(covariant LiveLogPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accessGranted != widget.accessGranted) {
      if (widget.accessGranted) {
        unawaited(_connect());
      } else {
        unawaited(_disconnect());
      }
    } else if (widget.accessGranted && oldWidget.uri != widget.uri) {
      unawaited(_connect());
    }
  }

  @override
  void dispose() {
    reconnectTimer?.cancel();
    unawaited(socket?.close());
    scrollController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (!mounted || !widget.accessGranted) return;
    reconnectTimer?.cancel();
    final previous = socket;
    socket = null;
    await previous?.close();
    if (!mounted || !widget.accessGranted) {
      return;
    }
    setState(() {
      connected = false;
      error = null;
      lines.clear();
    });
    final next = InstanceLogSocket(uri: widget.uri);
    socket = next;
    final connectedNow = await next.connect(
      onLog: _receive,
      onError: (_) {
        if (mounted) {
          setState(() {
            connected = false;
            error = '日志连接中断';
          });
        }
        _scheduleReconnect(next);
      },
      onClosed: () {
        if (mounted) setState(() => connected = false);
        _scheduleReconnect(next);
      },
    );
    if (mounted && widget.accessGranted && socket == next && connectedNow) {
      setState(() => connected = true);
    }
  }

  Future<void> _disconnect() async {
    reconnectTimer?.cancel();
    reconnectTimer = null;
    final previous = socket;
    socket = null;
    await previous?.close();
    if (!mounted) return;
    setState(() {
      connected = false;
      error = null;
      lines.clear();
    });
  }

  void _scheduleReconnect(InstanceLogSocket source) {
    if (!mounted || !widget.accessGranted || socket != source) return;
    reconnectTimer?.cancel();
    reconnectTimer = Timer(
      const Duration(seconds: 3),
      () => unawaited(_connect()),
    );
  }

  void _receive(InstanceLogEvent event) {
    if (!mounted || !widget.accessGranted) return;
    final parsed = event.html.expand(_parseFragment).toList(growable: false);
    if (parsed.isEmpty) return;
    setState(() {
      lines.addAll(parsed);
      if (lines.length > 500) lines.removeRange(0, lines.length - 500);
    });
    if (autoScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && scrollController.hasClients) {
          scrollController.jumpTo(scrollController.position.maxScrollExtent);
        }
      });
    }
  }

  Iterable<_LiveLogLine> _parseFragment(String fragment) sync* {
    final pattern = RegExp(
      r'<div class="log-line([^>]*)">([\s\S]*?)</div>(?:<div class="log-traceback">([\s\S]*?)</div>)?',
    );
    final matches = pattern.allMatches(fragment).toList(growable: false);
    if (matches.isEmpty) {
      final line = _parseLine(fragment, '', null);
      if (line != null) yield line;
      return;
    }
    for (final lineMatch in matches) {
      final line = _parseLine(
        lineMatch.group(2) ?? '',
        lineMatch.group(1) ?? '',
        lineMatch.group(3),
      );
      if (line != null) yield line;
    }
  }

  _LiveLogLine? _parseLine(
    String content,
    String classes,
    String? rawTraceback,
  ) {
    final timestamp = _text(
      RegExp(
        r'<span class="ts">([\s\S]*?)</span>',
      ).firstMatch(content)?.group(1),
    );
    final levelText = _text(
      RegExp(
        r'<span class="lv-chip[^>]*>([\s\S]*?)</span>',
      ).firstMatch(content)?.group(1),
    );
    final message = _text(
      RegExp(
        r'<span class="log-message[^>]*>([\s\S]*?)</span>',
      ).firstMatch(content)?.group(1),
    ).trim();
    final fallback = _text(content).trim();
    final traceback = _text(rawTraceback).trim();
    final value = message.isEmpty ? fallback : message;
    if (value.isEmpty) return null;
    final kind =
        classes.contains('lv-err') ||
            levelText == 'ERROR' ||
            levelText == 'CRITICAL'
        ? LogKind.error
        : classes.contains('lv-warn') || levelText == 'WARNING'
        ? LogKind.warn
        : LogKind.info;
    return _LiveLogLine(
      time: timestamp,
      level: levelText.isEmpty ? 'INFO' : levelText,
      message: value,
      kind: kind,
      traceback: traceback.isEmpty ? null : traceback,
    );
  }

  String _text(String? value) {
    if (value == null) return '';
    return value
        .replaceAll(RegExp(r'<br\s*/?>'), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&#x27;', "'");
  }

  bool _visible(_LiveLogLine line) {
    const ranks = {
      'DEBUG': 0,
      'INFO': 1,
      'WARNING': 2,
      'WARN': 2,
      'ERROR': 3,
      'CRITICAL': 3,
    };
    final selected = ranks[level] ?? 1;
    return (ranks[line.level] ?? 1) >= selected;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final scheme = theme.colorScheme;
    return Surface(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: scheme.card,
              border: Border(bottom: BorderSide(color: scheme.border)),
            ),
            child: Row(
              children: [
                Icon(
                  widget.running ? LucideIcons.radio : LucideIcons.pauseCircle,
                  size: 16,
                  color: widget.running
                      ? scheme.success
                      : scheme.mutedForeground,
                ),
                const SizedBox(width: 7),
                Text(
                  widget.running ? '实时日志' : '日志已暂停',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                PopupMenuButton<String>(
                  initialValue: level,
                  tooltip: '实时日志级别',
                  onSelected: (value) => setState(() => level = value),
                  itemBuilder: (context) => [
                    for (final item in const ['DEBUG', 'INFO', 'WARN', 'ERROR'])
                      PopupMenuItem(value: item, child: Text(item)),
                  ],
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                    decoration: BoxDecoration(
                      color: scheme.secondary,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(level, style: const TextStyle(fontSize: 11)),
                        const SizedBox(width: 4),
                        const Icon(LucideIcons.chevronDown, size: 14),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                _LiveToggle(
                  value: autoScroll,
                  onChanged: (value) => setState(() => autoScroll = value),
                ),
                const SizedBox(width: 6),
                Semantics(
                  label: connected ? '日志已连接' : '日志未连接',
                  child: Icon(
                    connected ? LucideIcons.wifi : LucideIcons.wifiOff,
                    size: 15,
                    color: connected ? scheme.success : scheme.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              width: double.infinity,
              color: scheme.logBodyBg,
              padding: const EdgeInsets.all(8),
              child: !connected && lines.isEmpty
                  ? Center(
                      child: Text(
                        error ?? '正在连接实时日志…',
                        style: theme.textTheme.muted,
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      padding: EdgeInsets.zero,
                      itemCount: lines.where(_visible).length,
                      itemBuilder: (context, index) {
                        final visible = lines
                            .where(_visible)
                            .toList(growable: false);
                        final line = visible[index];
                        return LogLine(
                          time: line.time,
                          level: line.level,
                          message: line.message,
                          kind: line.kind,
                          traceback: line.traceback,
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveLogLine {
  const _LiveLogLine({
    required this.time,
    required this.level,
    required this.message,
    required this.kind,
    this.traceback,
  });

  final String time;
  final String level;
  final String message;
  final LogKind kind;
  final String? traceback;
}

class _LiveToggle extends StatelessWidget {
  const _LiveToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = ShadTheme.of(context).colorScheme;
    return Tooltip(
      message: '自动滚动',
      child: Semantics(
        button: true,
        toggled: value,
        label: '自动滚动',
        child: GestureDetector(
          onTap: () => onChanged(!value),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: Container(
                width: 42,
                height: 24,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: value ? scheme.primary : scheme.border,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 150),
                  alignment: value
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: Color(0x24000000), blurRadius: 3),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
