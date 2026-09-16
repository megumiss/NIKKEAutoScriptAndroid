import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class NativeTouch {
  const NativeTouch(
    this.action,
    this.pointerId,
    this.x,
    this.y,
    this.width,
    this.height,
  );
  final int action;
  final int pointerId;
  final int x;
  final int y;
  final int width;
  final int height;
}

class NativeVideoSurface extends StatefulWidget {
  const NativeVideoSurface({
    required this.textureId,
    required this.width,
    required this.height,
    required this.onTouch,
    required this.onError,
    super.key,
  });
  final int textureId;
  final int width;
  final int height;
  final Future<void> Function(NativeTouch event) onTouch;
  final void Function(Object error) onError;

  @override
  State<NativeVideoSurface> createState() => _NativeVideoSurfaceState();
}

class _NativeVideoSurfaceState extends State<NativeVideoSurface>
    with WidgetsBindingObserver {
  final pending = <NativeTouch>[];
  late final send = widget.onTouch;
  int? pointer;
  NativeTouch? last;
  bool sending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant NativeVideoSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.width != widget.width ||
        oldWidget.height != widget.height ||
        oldWidget.textureId != widget.textureId) {
      _cancel();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _cancel();
  }

  @override
  void dispose() {
    _cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _enqueue(NativeTouch event) {
    if (event.action == 2 && pending.isNotEmpty && pending.last.action == 2) {
      pending[pending.length - 1] = event;
    } else {
      pending.add(event);
    }
    if (!sending) unawaited(_drain());
  }

  Future<void> _drain() async {
    sending = true;
    try {
      while (pending.isNotEmpty) {
        await send(pending.removeAt(0));
      }
    } catch (error) {
      pending.clear();
      pointer = null;
      last = null;
      if (mounted) widget.onError(error);
    } finally {
      sending = false;
    }
  }

  void _cancel() {
    final previous = last;
    if (pointer != null && previous != null) {
      _enqueue(
        NativeTouch(
          3,
          previous.pointerId,
          previous.x,
          previous.y,
          previous.width,
          previous.height,
        ),
      );
    }
    pointer = null;
    last = null;
  }

  void _touch(int action, PointerEvent event, Size size) {
    if (size.isEmpty || widget.width <= 0 || widget.height <= 0) return;
    if (action == 0) {
      if (pointer != null ||
          (event.kind == PointerDeviceKind.mouse &&
              (event.buttons & kPrimaryMouseButton) == 0)) {
        return;
      }
      pointer = event.pointer;
    } else if (pointer != event.pointer) {
      return;
    }
    final x = (event.localPosition.dx / size.width * widget.width)
        .floor()
        .clamp(0, widget.width - 1);
    final y = (event.localPosition.dy / size.height * widget.height)
        .floor()
        .clamp(0, widget.height - 1);
    final touch = NativeTouch(
      action,
      event.pointer,
      x,
      y,
      widget.width,
      widget.height,
    );
    last = touch;
    _enqueue(touch);
    if (action == 1) {
      pointer = null;
      last = null;
    }
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: '设备实时画面',
    hint: '支持点击、滑动和长按',
    child: LayoutBuilder(
      builder: (context, constraints) => RawGestureDetector(
        // 画面是控制区域：手指按下即认领手势（EagerGestureRecognizer），
        // 外层 ListView 失去竞争不会再响应滑动，避免页面与远端设备同时滚动
        gestures: {
          EagerGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
                EagerGestureRecognizer.new,
                (instance) {},
              ),
        },
        behavior: HitTestBehavior.opaque,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) => _touch(0, event, constraints.biggest),
          onPointerMove: (event) => _touch(2, event, constraints.biggest),
          onPointerUp: (event) => _touch(1, event, constraints.biggest),
          onPointerCancel: (_) => _cancel(),
          child: Texture(textureId: widget.textureId),
        ),
      ),
    ),
  );
}
