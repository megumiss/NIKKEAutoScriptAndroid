import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile/core/api/instance_info.dart';
import 'package:nkas_mobile/core/api/screenshot_frame.dart';
import 'package:nkas_mobile/core/widgets/avatar.dart';
import 'package:nkas_mobile/core/widgets/buttons.dart';
import 'package:nkas_mobile/core/widgets/page_inset.dart';
import 'package:nkas_mobile/core/widgets/page_subtitle.dart';
import 'package:nkas_mobile/core/widgets/status.dart';
import 'package:nkas_mobile/core/widgets/surface.dart';
import 'package:nkas_mobile/theme.dart';

class ScreenPage extends StatelessWidget {
  const ScreenPage({
    required this.instances,
    required this.selected,
    required this.selectedInstance,
    required this.avatarUrl,
    required this.loading,
    required this.error,
    required this.onSelectInstance,
    required this.loadScreenshot,
    required this.onOpenControl,
    required this.accessGranted,
    super.key,
  });
  final List<InstanceInfo> instances;
  final String selected;
  final InstanceInfo? selectedInstance;
  final String? Function(InstanceInfo item) avatarUrl;
  final bool loading;
  final String? error;
  final ValueChanged<String> onSelectInstance;
  final Future<ScreenshotFrame?> Function() loadScreenshot;
  final VoidCallback onOpenControl;
  final bool accessGranted;

  @override
  Widget build(BuildContext context) {
    final scheme = ShadTheme.of(context).colorScheme;
    final inset = nkasPageInset(context);
    final displayName =
        selectedInstance?.name ??
        (loading
            ? '加载中…'
            : error == null
            ? '暂无实例'
            : '实例加载失败');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(inset, 5, inset, 0),
          child: const PageSubtitle('查看实例实时画面，每 2 秒自动刷新'),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: inset),
          child: Surface(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                Avatar(
                  text: selectedInstance?.name.characters.first ?? '实',
                  size: 38,
                  fontSize: 15,
                  background: scheme.accentSoft,
                  foreground: scheme.configIconText,
                  imageUrl: selectedInstance == null
                      ? null
                      : avatarUrl(selectedInstance!),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          displayName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (selectedInstance != null) ...[
                        const SizedBox(width: 7),
                        Status(status: selectedInstance!.status),
                      ],
                    ],
                  ),
                ),
                CompactButton(
                  icon: LucideIcons.layers3,
                  label: '切换',
                  onPressed: () => _showInstancePicker(context),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(inset, 8, inset, 88),
            child: SizedBox.expand(
              child: ScreenPanel(
                key: ValueKey(selected),
                loadScreenshot: loadScreenshot,
                onOpenControl: onOpenControl,
                accessGranted: accessGranted,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showInstancePicker(BuildContext context) {
    showModalBottomSheet<void>(
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
                    onSelectInstance(item.name);
                    Navigator.pop(context);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class ScreenPanel extends StatefulWidget {
  const ScreenPanel({
    required this.loadScreenshot,
    required this.onOpenControl,
    required this.accessGranted,
    super.key,
  });

  final Future<ScreenshotFrame?> Function() loadScreenshot;
  final VoidCallback onOpenControl;
  final bool accessGranted;

  @override
  State<ScreenPanel> createState() => _ScreenPanelState();
}

class _ScreenPanelState extends State<ScreenPanel> {
  ScreenshotFrame? frame;
  bool loading = false;
  String? error;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    if (widget.accessGranted) {
      _load();
      _startPolling();
    }
  }

  @override
  void didUpdateWidget(covariant ScreenPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accessGranted == widget.accessGranted) return;
    if (widget.accessGranted) {
      _startPolling();
      _load();
    } else {
      timer?.cancel();
      timer = null;
    }
  }

  void _startPolling() {
    if (!widget.accessGranted || timer != null) return;
    timer = Timer.periodic(const Duration(seconds: 2), (_) => _load());
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (loading || !widget.accessGranted) return;
    setState(() => loading = true);
    try {
      final value = await widget.loadScreenshot();
      if (!mounted) return;
      setState(() {
        frame = value;
        error = null;
      });
    } catch (exception) {
      if (mounted) setState(() => error = exception.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controlLabel = frame == null ? '刷新画面' : '进入控制';
    return Surface(
      padding: EdgeInsets.zero,
      color: NkasColors.screenBg,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: 9 / 16,
              child: frame == null
                  ? Center(
                      child: Text(
                        error == null
                            ? (loading ? '正在获取画面…' : '暂无画面')
                            : '画面加载失败',
                        style: const TextStyle(color: NkasColors.screenText),
                      ),
                    )
                  : Image.memory(
                      frame!.bytes,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                    ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              constraints: const BoxConstraints(minHeight: 58),
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              color: const Color(0xE0101D25),
              child: Row(
                children: [
                  Text(
                    frame == null ? '未连接' : _captureLabel(frame!.capturedAt),
                    style: const TextStyle(
                      color: Color(0xFFD6E3EA),
                      fontSize: 11,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: loading || !widget.accessGranted
                        ? null
                        : frame == null
                        ? _load
                        : widget.onOpenControl,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 30),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      backgroundColor: const Color(0xFF2E4653),
                      foregroundColor: const Color(0xFFD6E3EA),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(7),
                      ),
                    ),
                    child: Text(
                      controlLabel,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _captureLabel(double? timestamp) {
    if (timestamp == null) return '实时 · 2s';
    final date = DateTime.fromMillisecondsSinceEpoch(
      (timestamp * 1000).round(),
    ).toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '捕获于 ${two(date.hour)}:${two(date.minute)}:${two(date.second)}';
  }
}
