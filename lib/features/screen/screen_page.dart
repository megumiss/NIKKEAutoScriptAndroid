import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile/core/api/instance_info.dart';
import 'package:nkas_mobile/core/api/screenshot_frame.dart';
import 'package:nkas_mobile/core/platform/nkas_platform.dart';
import 'package:nkas_mobile/core/platform/native_control_settings.dart';
import 'package:nkas_mobile/features/screen/native_video_surface.dart';
import 'package:nkas_mobile/core/widgets/avatar.dart';
import 'package:nkas_mobile/core/widgets/buttons.dart';
import 'package:nkas_mobile/core/widgets/form_field.dart';
import 'package:nkas_mobile/core/widgets/instance_picker.dart';
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
    required this.accessGranted,
    required this.onOpenNativeControl,
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
  final bool accessGranted;
  final VoidCallback onOpenNativeControl;

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
          child: PageSubtitle(
            NkasPlatform.instance.supported
                ? '连接设备后查看实时画面并操作'
                : '查看实例实时画面，每 2 秒自动刷新',
          ),
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
                  onPressed: () => showInstancePicker(
                    context,
                    instances: instances,
                    selected: selected,
                    loading: loading,
                    error: error,
                    avatarUrl: avatarUrl,
                    onSelect: onSelectInstance,
                  ),
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
                accessGranted: accessGranted,
                onOpenNativeControl: onOpenNativeControl,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class ScreenPanel extends StatefulWidget {
  const ScreenPanel({
    required this.loadScreenshot,
    required this.accessGranted,
    this.onOpenNativeControl,
    this.platform,
    super.key,
  });
  final Future<ScreenshotFrame?> Function() loadScreenshot;
  final bool accessGranted;
  final VoidCallback? onOpenNativeControl;
  final NkasPlatform? platform;
  @override
  State<ScreenPanel> createState() => _ScreenPanelState();
}

class _ScreenPanelState extends State<ScreenPanel> {
  static int nextRequest = 0;
  NkasPlatform get platform => widget.platform ?? NkasPlatform.instance;
  ScreenshotFrame? frame;
  bool loading = false;
  String? error;
  Timer? timer;
  StreamSubscription<NkasPlatformEvent>? platformEvents;
  int? textureId;
  int videoWidth = 0;
  int videoHeight = 0;
  String? nativeError;
  String nativeState = 'idle';
  String? requestId;
  String? controlTarget;

  @override
  void initState() {
    super.initState();
    if (platform.supported) {
      platformEvents = platform.events.listen(
        _onEvent,
        onError: _nativeFailure,
      );
    }
    if (widget.accessGranted) {
      _startPolling();
      unawaited(_load());
    }
  }

  @override
  void didUpdateWidget(covariant ScreenPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accessGranted == widget.accessGranted) return;
    if (widget.accessGranted) {
      _startPolling();
      unawaited(_load());
    } else {
      timer?.cancel();
      timer = null;
      unawaited(_stopNative());
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    unawaited(platformEvents?.cancel());
    final id = requestId;
    requestId = null;
    if (id != null) {
      unawaited(
        platform.nativeScrcpyStop(requestId: id).catchError((Object _) {}),
      );
    }
    super.dispose();
  }

  void _onEvent(NkasPlatformEvent event) {
    if (!mounted ||
        !widget.accessGranted ||
        event is! ScrcpyVideoEvent ||
        event.requestId != requestId ||
        requestId == null) {
      return;
    }
    if (event.state == 'size') {
      if ((event.width ?? 0) > 0 && (event.height ?? 0) > 0) {
        setState(() {
          videoWidth = event.width!;
          videoHeight = event.height!;
        });
      }
      return;
    }
    if (event.state == 'started' && event.textureId != null) {
      timer?.cancel();
      timer = null;
      setState(() {
        textureId = event.textureId;
        nativeState = 'started';
        nativeError = null;
        videoWidth = event.width ?? videoWidth;
        videoHeight = event.height ?? videoHeight;
      });
      return;
    }
    setState(() {
      textureId = null;
      nativeState = event.state;
      if (event.state == 'failed' || event.state == 'error') {
        nativeError = event.error ?? '控制连接已断开';
      }
    });
    _startPolling();
    unawaited(_load());
  }

  Future<void> _startNativeVideo() async {
    if (!platform.supported || !widget.accessGranted) return;
    final previous = requestId;
    final id = '${DateTime.now().microsecondsSinceEpoch}-${++nextRequest}';
    requestId = id;
    setState(() {
      textureId = null;
      nativeError = null;
      nativeState = 'connecting';
    });
    try {
      if (previous != null) {
        await platform.nativeScrcpyStop(requestId: previous);
      }
      final settings = await platform.nativeControlSettings();
      if (!mounted || requestId != id || !widget.accessGranted) return;
      setState(() {
        controlTarget = settings.mode == NativeControlMode.localVirtualDisplay
            ? '本机虚拟屏幕'
            : settings.endpoint.isEmpty
            ? null
            : settings.endpoint;
      });
      if (settings.mode == NativeControlMode.remoteAdb &&
          settings.endpoint.isEmpty) {
        setState(() {
          nativeState = 'idle';
          requestId = null;
        });
        return;
      }
      await platform.nativeScrcpyStart(
        settings.mode == NativeControlMode.remoteAdb ? settings.endpoint : '',
        mode: settings.modeName,
        useTailscale:
            settings.tailscaleEnabled &&
            settings.mode == NativeControlMode.remoteAdb,
        requestId: id,
        maxSize: 1920,
        videoBitRate: 8_000_000,
      );
      // A texture can be allocated before a decodable frame exists. Only the started event enables it.
    } catch (exception) {
      if (mounted && requestId == id) _nativeFailure(exception);
    }
  }

  Future<void> _stopNative() async {
    final id = requestId;
    requestId = null;
    if (mounted) {
      setState(() {
        textureId = null;
        nativeState = 'idle';
        nativeError = null;
      });
    }
    try {
      if (id != null) await platform.nativeScrcpyStop(requestId: id);
    } catch (exception) {
      if (mounted) setState(() => nativeError = _message(exception));
    }
    if (mounted) {
      _startPolling();
      unawaited(_load());
    }
  }

  void _nativeFailure(Object exception) {
    if (!mounted) return;
    setState(() {
      textureId = null;
      nativeState = 'failed';
      nativeError = _message(exception);
    });
    _startPolling();
    unawaited(_load());
  }

  void _startPolling() {
    if (!widget.accessGranted || timer != null || textureId != null) return;
    timer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_load()),
    );
  }

  Future<void> _load() async {
    if (loading || !widget.accessGranted || textureId != null) return;
    setState(() => loading = true);
    try {
      final value = await widget.loadScreenshot();
      if (mounted && widget.accessGranted) {
        setState(() {
          frame = value;
          error = null;
        });
      }
    } catch (exception) {
      if (mounted) setState(() => error = _message(exception));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _configure() => widget.onOpenNativeControl?.call();

  Future<void> _key(int code) async {
    final id = requestId;
    if (id == null || textureId == null) return;
    try {
      await platform.nativeScrcpyKeycode(
        action: 0,
        keycode: code,
        requestId: id,
      );
      await platform.nativeScrcpyKeycode(
        action: 1,
        keycode: code,
        requestId: id,
      );
    } catch (exception) {
      if (mounted) _nativeFailure(exception);
    }
  }

  Future<void> _text() async {
    final id = requestId;
    if (id == null) return;
    final value = await showDialog<String>(
      context: context,
      builder: (_) => const _NativeTextDialog(),
    );
    if (value == null || value.isEmpty || !mounted || requestId != id) return;
    try {
      await platform.nativeScrcpyText(value, requestId: id);
    } catch (exception) {
      if (mounted) setState(() => nativeError = _message(exception));
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = requestId;
    final live = textureId != null && videoWidth > 0 && videoHeight > 0;
    final connecting =
        nativeState == 'connecting' ||
        nativeState == 'reconnecting' ||
        nativeState == 'waiting';
    final label = live
        ? '实时控制'
        : connecting
        ? '正在连接设备…'
        : frame != null
        ? '截图预览 · 2s'
        : '未连接';
    const foreground = Color(0xFFD6E3EA);
    return Surface(
      padding: EdgeInsets.zero,
      color: NkasColors.screenBg,
      child: Column(
        children: [
          Container(
            color: const Color(0xE0101D25),
            padding: const EdgeInsets.only(left: 12, right: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(color: foreground, fontSize: 12),
                  ),
                ),
                if (platform.supported) ...[
                  IconButton(
                    tooltip: '控制连接设置',
                    icon: const Icon(LucideIcons.settings, size: 20),
                    color: foreground,
                    onPressed: widget.accessGranted ? _configure : null,
                  ),
                  IconButton(
                    tooltip: connecting || live ? '断开控制' : '连接设备',
                    icon: Icon(
                      connecting || live
                          ? LucideIcons.unplug
                          : LucideIcons.plug,
                      size: 20,
                    ),
                    color: foreground,
                    onPressed: !widget.accessGranted
                        ? null
                        : connecting || live
                        ? _stopNative
                        : _startNativeVideo,
                  ),
                ] else
                  TextButton(
                    style: NkasActionStyle.compactButton,
                    onPressed: loading || !widget.accessGranted ? null : _load,
                    child: const Text(
                      '刷新画面',
                      style: TextStyle(color: foreground),
                    ),
                  ),
              ],
            ),
          ),
          if (controlTarget != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Text(
                '控制目标：$controlTarget',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: foreground, fontSize: 12),
              ),
            ),
          Expanded(
            child: Center(
              child: live && id != null
                  ? AspectRatio(
                      aspectRatio: videoWidth / videoHeight,
                      child: NativeVideoSurface(
                        key: ValueKey('$id:$textureId'),
                        textureId: textureId!,
                        width: videoWidth,
                        height: videoHeight,
                        onTouch: (touch) => platform.nativeScrcpyTouch(
                          action: touch.action,
                          pointerId: touch.pointerId,
                          x: touch.x,
                          y: touch.y,
                          screenWidth: touch.width,
                          screenHeight: touch.height,
                          pressure: touch.action == 1 || touch.action == 3
                              ? 0
                              : 1,
                          requestId: id,
                        ),
                        onError: _nativeFailure,
                      ),
                    )
                  : frame != null
                  ? Image.memory(
                      frame!.bytes,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                    )
                  : Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        nativeError ??
                            (error != null
                                ? '画面加载失败'
                                : loading
                                ? '正在获取画面…'
                                : '暂无画面'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: NkasColors.screenText),
                      ),
                    ),
            ),
          ),
          if (nativeError != null && (frame != null || live))
            Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                nativeError!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: NkasColors.screenText,
                  fontSize: 12,
                ),
              ),
            ),
          if (live)
            Container(
              color: const Color(0xE0101D25),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => _key(4),
                      icon: const Icon(LucideIcons.cornerUpLeft, size: 18),
                      style: TextButton.styleFrom(
                        foregroundColor: foreground,
                        minimumSize: const Size(0, 48),
                      ),
                      label: const Text('返回'),
                    ),
                  ),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => _key(3),
                      icon: const Icon(LucideIcons.house, size: 18),
                      style: TextButton.styleFrom(
                        foregroundColor: foreground,
                        minimumSize: const Size(0, 48),
                      ),
                      label: const Text('主页'),
                    ),
                  ),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: _text,
                      icon: const Icon(LucideIcons.keyboard, size: 18),
                      style: TextButton.styleFrom(
                        foregroundColor: foreground,
                        minimumSize: const Size(0, 48),
                      ),
                      label: const Text('文本'),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _message(Object error) =>
      error is PlatformException ? error.message ?? '原生连接失败' : error.toString();
}

class _NativeTextDialog extends StatefulWidget {
  const _NativeTextDialog();
  @override
  State<_NativeTextDialog> createState() => _NativeTextDialogState();
}

class _NativeTextDialogState extends State<_NativeTextDialog> {
  final controller = TextEditingController();
  int bytes = 0;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('发送文本'),
    content: NkasTextField(
      label: '文本内容',
      controller: controller,
      autofocus: true,
      maxLines: 3,
      onChanged: (value) => setState(() => bytes = utf8.encode(value).length),
      hintText: '输入要发送的文本',
      helperText: '$bytes / 300 UTF-8 字节',
      errorText: bytes > 300 ? '文本超过 300 个 UTF-8 字节' : null,
    ),
    actions: [
      TextButton(
        style: NkasActionStyle.compactButton,
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      TextButton(
        onPressed: bytes == 0 || bytes > 300
            ? null
            : () => Navigator.pop(context, controller.text),
        child: const Text('发送'),
      ),
    ],
  );
}
