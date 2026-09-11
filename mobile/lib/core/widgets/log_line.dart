import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile_preview/theme.dart';

enum LogKind { info, warn, error }

class LogLine extends StatefulWidget {
  const LogLine({
    super.key,
    required this.time,
    required this.level,
    required this.message,
    required this.kind,
    this.source,
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

  @override
  State<LogLine> createState() => _LogLineState();
}

class _LogLineState extends State<LogLine> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = ShadTheme.of(context).colorScheme;
    const mono = TextStyle(
      fontFamily: kDefaultFontFamilyMono,
      fontSize: 10.5,
      height: 1.75,
    );
    final (badgeColor, badgeBg, lineBg) = switch (widget.kind) {
      LogKind.info => (
        scheme.logInfoText,
        scheme.accentSoft,
        Colors.transparent,
      ),
      LogKind.warn => (
        scheme.warning,
        scheme.logWarnBadgeBg,
        scheme.logWarnLineBg,
      ),
      LogKind.error => (
        scheme.destructive,
        scheme.logErrorBadgeBg,
        scheme.logErrorLineBg,
      ),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      decoration: BoxDecoration(
        color: lineBg,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 58,
                child: Text(
                  widget.time,
                  style: mono.copyWith(color: scheme.logTime),
                ),
              ),
              const SizedBox(width: 5),
              SizedBox(
                width: 43,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      widget.level,
                      textAlign: TextAlign.center,
                      style: mono.copyWith(
                        color: badgeColor,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              if (widget.source != null) ...[
                const SizedBox(width: 5),
                SizedBox(
                  width: 48,
                  child: Text(
                    widget.source!,
                    overflow: TextOverflow.ellipsis,
                    style: mono.copyWith(color: scheme.logSource),
                  ),
                ),
              ],
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  widget.message,
                  style: mono.copyWith(
                    color: widget.kind == LogKind.info
                        ? scheme.logText
                        : badgeColor,
                  ),
                ),
              ),
            ],
          ),
          if (widget.traceback != null && widget.traceback!.isNotEmpty) ...[
            if (widget.tracebackCollapsed != null &&
                widget.tracebackCollapsed!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 111, top: 2),
                child: InkWell(
                  onTap: () => setState(() => expanded = !expanded),
                  child: Text(
                    expanded ? '收起详细信息' : '详细信息',
                    style: mono.copyWith(color: scheme.primary),
                  ),
                ),
              ),
            if (expanded &&
                widget.tracebackCollapsed != null &&
                widget.tracebackCollapsed!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 111, top: 3),
                child: SelectableText(
                  widget.tracebackCollapsed!,
                  style: mono.copyWith(color: scheme.logText),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(left: 111, top: 3),
              child: Text(
                widget.traceback!,
                style: mono.copyWith(color: badgeColor),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
