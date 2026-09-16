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
import 'package:nkas_mobile/core/widgets/form_field.dart';
import 'package:nkas_mobile/core/widgets/instance_select.dart';
import 'package:nkas_mobile/core/widgets/page_inset.dart';
import 'package:nkas_mobile/core/widgets/page_subtitle.dart';
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
    this.resolveEndpoint,
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

  /// 解析实例的生效控制地址：实例覆盖 → 全局手填 → 后端 Serial
  final Future<String?> Function(String instance)? resolveEndpoint;

  @override
  Widget build(BuildContext context) {
    final inset = nkasPageInset(context);
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
          child: InstanceSelect(
            instances: instances,
            selected: selected,
            selectedInstance: selectedInstance,
            loading: loading,
            error: error,
            avatarUrl: avatarUrl,
            onSelect: onSelectInstance,
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(inset, 8, inset, 88),
            child: ScreenPanel(
              key: ValueKey(selected),
              loadScreenshot: loadScreenshot,
              accessGranted: accessGranted,
              onOpenNativeControl: onOpenNativeControl,
              resolveEndpoint: resolveEndpoint == null
                  ? null
                  : () => resolveEndpoint!(selected),
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
    this.resolveEndpoint,
    super.key,
  });
  final Future<ScreenshotFrame?> Function() loadScreenshot;
  final bool accessGranted;
  final VoidCallback? onOpenNativeControl;
  final NkasPlatform? platform;

  /// 解析当前实例的生效控制地址；为空时回退到设置中的全局地址
  final Future<String?> Function()? resolveEndpoint;
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
  bool _fullscreenOpen = false;
  NavigatorState? _rootNavigator;

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
    _closeFullscreen();
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
    // 会话结束后全屏画面不再更新，退出全屏回到截图回退
    _closeFullscreen();
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
      var endpoint = settings.endpoint;
      final resolver = widget.resolveEndpoint;
      if (settings.mode == NativeControlMode.remoteAdb && resolver != null) {
        endpoint = (await resolver())?.trim() ?? '';
      }
      if (!mounted || requestId != id || !widget.accessGranted) return;
      setState(() {
        controlTarget = settings.mode == NativeControlMode.localVirtualDisplay
            ? '本机虚拟屏幕'
            : endpoint.isEmpty
            ? null
            : endpoint;
      });
      if (settings.mode == NativeControlMode.remoteAdb && endpoint.isEmpty) {
        setState(() {
          nativeState = 'idle';
          nativeError = '未配置控制地址，请在控制连接中设置，或在实例 Emulator 配置中填写 Serial';
          requestId = null;
        });
        return;
      }
      await platform.nativeScrcpyStart(
        settings.mode == NativeControlMode.remoteAdb ? endpoint : '',
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
    _closeFullscreen();
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
    _closeFullscreen();
    _startPolling();
    unawaited(_load());
  }

  /// 抽出触摸转发，画面内嵌与全屏共用同一套坐标映射与压力规则
  Future<void> _sendTouch(String id, NativeTouch touch) =>
      platform.nativeScrcpyTouch(
        action: touch.action,
        pointerId: touch.pointerId,
        x: touch.x,
        y: touch.y,
        screenWidth: touch.width,
        screenHeight: touch.height,
        pressure: touch.action == 1 || touch.action == 3 ? 0 : 1,
        requestId: id,
      );

  void _openFullscreen() {
    final id = requestId;
    final texture = textureId;
    final image = frame;
    final live = texture != null && id != null;
    if (!live && image == null) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    _rootNavigator = navigator;
    _fullscreenOpen = true;
    unawaited(
      navigator
          .push(
            PageRouteBuilder<void>(
              transitionDuration: const Duration(milliseconds: 160),
              pageBuilder: (context, _, _) => _FullscreenVideoPage(
                textureId: live ? texture : null,
                width: videoWidth,
                height: videoHeight,
                frame: live ? null : image,
                onTouch: live ? (touch) => _sendTouch(id, touch) : null,
                onError: live ? _nativeFailure : null,
                onBack: live ? () => _key(4) : null,
                onHome: live ? () => _key(3) : null,
                onText: live ? _text : null,
              ),
            ),
          )
          .then((_) => _fullscreenOpen = false),
    );
  }

  void _closeFullscreen() {
    if (!_fullscreenOpen) return;
    _fullscreenOpen = false;
    final navigator = _rootNavigator;
    // 面板可能正在销毁，异步退出避免在 dispose 中同步 pop
    if (navigator != null && navigator.mounted) {
      unawaited(Future(() => navigator.pop()));
    }
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
    final status = live
        ? '实时控制'
        : connecting
        ? '正在连接设备…'
        : frame != null
        ? '截图预览 · 2s'
        : '未连接';
    // 连接与控制过程中的提示与状态同栏展示，画面区域完整留给画面
    final message = nativeError;
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
                    message ?? status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: message == null
                          ? foreground
                          : NkasColors.darkDanger,
                      fontSize: 12,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '全屏',
                  icon: const Icon(LucideIcons.maximize, size: 20),
                  color: foreground,
                  disabledColor: foreground.withValues(alpha: .38),
                  onPressed: !widget.accessGranted || !(live || frame != null)
                      ? null
                      : _openFullscreen,
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
                    color: connecting || live
                        ? NkasColors.darkDanger
                        : NkasColors.darkAccent,
                    onPressed: !widget.accessGranted
                        ? null
                        : connecting || live
                        ? _stopNative
                        : _startNativeVideo,
                  ),
                ] else
                  TextButton(
                    style: NkasActionStyle.compactButton.merge(
                      TextButton.styleFrom(
                        foregroundColor: foreground,
                        disabledForegroundColor: foreground.withValues(
                          alpha: .38,
                        ),
                      ),
                    ),
                    onPressed: loading || !widget.accessGranted ? null : _load,
                    child: const Text('刷新画面'),
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
          // 画面宽度铺满卡片，高度按视频比例推导；竖屏视频超出视口时整页滚动，
          // 不再用卡片剩余高度限制画面宽度
          if (live && id != null)
            AspectRatio(
              aspectRatio: videoWidth / videoHeight,
              child: NativeVideoSurface(
                key: ValueKey('$id:$textureId'),
                textureId: textureId!,
                width: videoWidth,
                height: videoHeight,
                onTouch: (touch) => _sendTouch(id, touch),
                onError: _nativeFailure,
              ),
            )
          else if (frame != null)
            Image.memory(
              frame!.bytes,
              width: double.infinity,
              fit: BoxFit.contain,
              gaplessPlayback: true,
            )
          else
            SizedBox(
              height: 240,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 提示统一由顶部状态栏呈现，空态只描述画面本身
                      Text(
                        error != null
                            ? '画面加载失败'
                            : loading
                            ? '正在获取画面…'
                            : '暂无画面',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: NkasColors.screenText),
                      ),
                      if (platform.supported && error == null && !loading) ...[
                        const SizedBox(height: 8),
                        const Text(
                          '点击右上角插头按钮连接设备，开始实时控制',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: NkasColors.screenText,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
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

/// 全屏画面：隐藏系统栏沉浸式展示，触摸映射与画面内嵌一致；
/// 会话结束或离开画面页时由 [ScreenPanel] 负责退出
class _FullscreenVideoPage extends StatefulWidget {
  const _FullscreenVideoPage({
    required this.textureId,
    required this.width,
    required this.height,
    required this.frame,
    required this.onTouch,
    required this.onError,
    this.onBack,
    this.onHome,
    this.onText,
  });

  final int? textureId;
  final int width;
  final int height;
  final ScreenshotFrame? frame;
  final Future<void> Function(NativeTouch touch)? onTouch;
  final void Function(Object error)? onError;

  /// 控制中的系统操作，与内嵌画面共用同一套按键与文本转发
  final VoidCallback? onBack;
  final VoidCallback? onHome;
  final VoidCallback? onText;

  @override
  State<_FullscreenVideoPage> createState() => _FullscreenVideoPageState();
}

class _FullscreenVideoPageState extends State<_FullscreenVideoPage> {
  static const foreground = Color(0xFFD6E3EA);

  @override
  void initState() {
    super.initState();
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
  }

  @override
  void dispose() {
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textureId = widget.textureId;
    final frame = widget.frame;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child:
                        textureId != null &&
                            widget.width > 0 &&
                            widget.height > 0
                        ? AspectRatio(
                            aspectRatio: widget.width / widget.height,
                            child: NativeVideoSurface(
                              textureId: textureId,
                              width: widget.width,
                              height: widget.height,
                              onTouch: widget.onTouch ?? (_) async {},
                              onError: widget.onError ?? (_) {},
                            ),
                          )
                        : frame != null
                        ? Image.memory(
                            frame.bytes,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
                if (widget.onBack != null) _controlBar(),
              ],
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 6,
            right: 6,
            child: IconButton(
              tooltip: '退出全屏',
              style: IconButton.styleFrom(
                backgroundColor: const Color(0x80101D25),
                foregroundColor: foreground,
              ),
              icon: const Icon(LucideIcons.minimize, size: 20),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }

  /// 控制栏随画面一起进入全屏，沉浸式下补足手势条安全区
  Widget _controlBar() => Container(
    color: const Color(0xE0101D25),
    child: SafeArea(
      top: false,
      child: Row(
        children: [
          Expanded(
            child: TextButton.icon(
              onPressed: widget.onBack,
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
              onPressed: widget.onHome,
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
              onPressed: widget.onText,
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
  );
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
        style: TextButton.styleFrom(
          foregroundColor: ShadTheme.of(context).colorScheme.primary,
        ),
        onPressed: bytes == 0 || bytes > 300
            ? null
            : () => Navigator.pop(context, controller.text),
        child: const Text('发送'),
      ),
    ],
  );
}
