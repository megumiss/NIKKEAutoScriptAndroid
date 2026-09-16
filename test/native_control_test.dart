import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nkas_mobile/core/api/instance_info.dart';
import 'package:nkas_mobile/core/platform/nkas_platform.dart';
import 'package:nkas_mobile/core/widgets/floating_action.dart';
import 'package:nkas_mobile/features/screen/native_video_surface.dart';
import 'package:nkas_mobile/features/screen/screen_page.dart';
import 'package:nkas_mobile/features/settings/native_control_page.dart';
import 'package:nkas_mobile/theme.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

Widget host(Widget child) => ShadApp(
  theme: nkasThemeData(Brightness.light),
  materialThemeBuilder: nkasMaterialTheme,
  home: Scaffold(body: child),
);

/// 拖动必须分多次 move：单次 move 只够让拖拽识别器越过 slop 并认领手势，
/// 位移会被当成 drag start 丢掉，滚动量恒为 0，会让回归测试假通过。
/// 返回拖动后的滚动偏移。
Future<double> dragToScroll(
  WidgetTester tester,
  Offset start, {
  int steps = 12,
}) async {
  final position = tester
      .state<ScrollableState>(find.byType(Scrollable).first)
      .position;
  final gesture = await tester.startGesture(start);
  for (var i = 0; i < steps; i++) {
    await gesture.moveBy(const Offset(0, -20));
    await tester.pump();
  }
  await gesture.up();
  await tester.pump();
  return position.pixels;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('press stays down through a long hold and cancel releases it', (
    tester,
  ) async {
    final touches = <NativeTouch>[];
    await tester.pumpWidget(
      host(
        Center(
          child: SizedBox(
            width: 200,
            height: 100,
            child: NativeVideoSurface(
              textureId: 1,
              width: 1920,
              height: 1080,
              onTouch: (value) async => touches.add(value),
              onError: (error) => fail('$error'),
            ),
          ),
        ),
      ),
    );
    final region = tester.getRect(find.byType(NativeVideoSurface));
    final gesture = await tester.startGesture(region.center);
    await tester.pump(const Duration(seconds: 1));
    expect(touches.map((e) => e.action), [0]);
    await gesture.moveTo(region.bottomRight + const Offset(20, 20));
    await tester.pump();
    expect(touches.last.x, 1919);
    expect(touches.last.y, 1079);
    await gesture.cancel();
    await tester.pump();
    expect(touches.map((e) => e.action), [0, 2, 3]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('slow input coalesces moves while keeping down and up ordered', (
    tester,
  ) async {
    final touches = <NativeTouch>[];
    final ack = Completer<void>();
    await tester.pumpWidget(
      host(
        SizedBox(
          width: 200,
          height: 100,
          child: NativeVideoSurface(
            textureId: 1,
            width: 1920,
            height: 1080,
            onTouch: (value) async {
              touches.add(value);
              if (value.action == 0) await ack.future;
            },
            onError: (error) => fail('$error'),
          ),
        ),
      ),
    );
    final region = tester.getRect(find.byType(NativeVideoSurface));
    final gesture = await tester.startGesture(region.center);
    for (var i = 1; i <= 20; i++) {
      await gesture.moveBy(const Offset(1, 1));
    }
    await gesture.up();
    expect(touches.map((e) => e.action), [0]);
    ack.complete();
    await tester.pump();
    expect(touches.map((e) => e.action), [0, 2, 1]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'dragging the video claims the gesture so the page does not scroll',
    (tester) async {
      final touches = <NativeTouch>[];
      await tester.pumpWidget(
        host(
          ListView(
            children: [
              SizedBox(
                height: 300,
                child: NativeVideoSurface(
                  textureId: 1,
                  width: 100,
                  height: 100,
                  onTouch: (value) async => touches.add(value),
                  onError: (error) => fail('$error'),
                ),
              ),
              const SizedBox(height: 1200),
            ],
          ),
        ),
      );
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position;
      expect(position.maxScrollExtent, greaterThan(0));

      // 对照：同样的拖动落在画面之外的空白处，页面必须真的滚起来；
      // 否则「画面拖动不滚」只能说明拖动本身没生效
      final onBlank = await dragToScroll(
        tester,
        tester.getCenter(find.byType(NativeVideoSurface)) + const Offset(0, 400),
      );
      expect(onBlank, greaterThan(0));
      position.jumpTo(0);
      await tester.pump();

      final onVideo = await dragToScroll(
        tester,
        tester.getCenter(find.byType(NativeVideoSurface)),
      );
      expect(onVideo, 0);
      expect(touches.first.action, 0);
      expect(touches.any((e) => e.action == 2), isTrue);
      expect(touches.last.action, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('video fills the card width for a portrait stream', (
    tester,
  ) async {
    final events = StreamController<NkasPlatformEvent>.broadcast();
    final platform = NkasPlatform.testing(events: events.stream);
    final calls = <MethodCall>[];
    _mockPlatform(calls);
    await tester.pumpWidget(
      host(
        SingleChildScrollView(
          child: ScreenPanel(
            platform: platform,
            accessGranted: true,
            loadScreenshot: () async => null,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('连接设备'));
    await tester.pump();
    final id =
        (calls.lastWhere((c) => c.method == 'nativeScrcpyStart').arguments
                as Map)['requestId']
            as String;

    // 竖屏视频（NIKKE 竖屏）：高度按宽度推导，超出视口时整页滚动而不是压缩宽度
    events.add(
      ScrcpyVideoEvent(
        state: 'started',
        requestId: id,
        textureId: 9,
        width: 1080,
        height: 2400,
      ),
    );
    await tester.pump();
    final cardWidth = tester.getSize(find.byType(ScreenPanel)).width;
    final size = tester.getSize(find.byType(Texture));
    expect(size.width, cardWidth - 2);
    expect(size.height, closeTo((cardWidth - 2) * 2400 / 1080, 0.01));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await events.close();
  });

  testWidgets('first frame enables texture; failure resumes screenshot polling', (
    tester,
  ) async {
    final events = StreamController<NkasPlatformEvent>.broadcast();
    final platform = NkasPlatform.testing(events: events.stream);
    final calls = <MethodCall>[];
    _mockPlatform(calls);
    var captures = 0;
    await tester.pumpWidget(
      host(
        SingleChildScrollView(
          child: ScreenPanel(
            platform: platform,
            accessGranted: true,
            loadScreenshot: () async {
              captures++;
              return null;
            },
          ),
        ),
      ),
    );
    await tester.pump();
    // 打开画面页不自动开启控制，需手动连接
    expect(calls.where((c) => c.method == 'nativeScrcpyStart'), isEmpty);
    await tester.tap(find.byTooltip('连接设备'));
    await tester.pump();
    final id =
        (calls.firstWhere((c) => c.method == 'nativeScrcpyStart').arguments
                as Map)['requestId']
            as String;
    expect(find.byType(Texture), findsNothing);
    events.add(
      ScrcpyVideoEvent(
        state: 'started',
        requestId: id,
        textureId: 9,
        width: 1920,
        height: 1080,
      ),
    );
    await tester.pump();
    expect(find.byType(Texture), findsOneWidget);
    expect(
      tester.widget<AspectRatio>(find.byType(AspectRatio)).aspectRatio,
      1920 / 1080,
    );
    final previousCaptures = captures;
    await tester.pump(const Duration(seconds: 3));
    expect(captures, previousCaptures);
    events.add(
      ScrcpyVideoEvent(state: 'failed', requestId: id, error: 'disconnected'),
    );
    // Deliver the event, then paint the frame it schedules after the idle period.
    await tester.pump();
    await tester.pump();
    expect(find.byType(Texture), findsNothing);
    expect(captures, greaterThan(previousCaptures));
    final resumedCaptures = captures;
    await tester.pump(const Duration(seconds: 2));
    expect(captures, greaterThan(resumedCaptures));
    await tester.pumpWidget(const SizedBox.shrink());
    await events.close();
  });

  testWidgets('fullscreen shows live video and exits when the session ends', (
    tester,
  ) async {
    final events = StreamController<NkasPlatformEvent>.broadcast();
    final platform = NkasPlatform.testing(events: events.stream);
    final calls = <MethodCall>[];
    _mockPlatform(calls);
    await tester.pumpWidget(
      host(
        SingleChildScrollView(
          child: ScreenPanel(
            platform: platform,
            accessGranted: true,
            loadScreenshot: () async => null,
          ),
        ),
      ),
    );
    await tester.pump();
    // 无画面时全屏不可用
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, LucideIcons.maximize),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byTooltip('连接设备'));
    await tester.pump();
    final id =
        (calls.firstWhere((c) => c.method == 'nativeScrcpyStart').arguments
                as Map)['requestId']
            as String;
    events.add(
      ScrcpyVideoEvent(
        state: 'started',
        requestId: id,
        textureId: 9,
        width: 720,
        height: 1280,
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('全屏'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('退出全屏'), findsOneWidget);
    // 画面页与全屏页同时挂载同一纹理（下层路由离屏），720x1280 竖屏宽高比一致
    expect(find.byType(Texture, skipOffstage: false), findsNWidgets(2));
    expect(
      tester.widget<AspectRatio>(find.byType(AspectRatio)).aspectRatio,
      720 / 1280,
    );

    // 会话结束自动退出全屏，回到截图回退
    events.add(
      ScrcpyVideoEvent(state: 'failed', requestId: id, error: 'disconnected'),
    );
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byTooltip('退出全屏'), findsNothing);
    expect(find.byType(Texture), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await events.close();
  });

  testWidgets('keyboard opening on a built page pins the save button below', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final calls = <MethodCall>[];
    _mockPlatform(calls);
    final platform = NkasPlatform.testing(events: const Stream.empty());
    await tester.pumpWidget(host(NativeControlPage(platform: platform)));
    await tester.pumpAndSettle();

    // 键盘在页面构建之后弹出：按钮必须从悬浮切换为固定在列表下方。
    // 悬浮分支中列表占满按钮所在区域，固定分支中列表底部即按钮顶部
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    await tester.pumpAndSettle();
    expect(
      tester.getBottomLeft(find.byType(ListView)).dy,
      lessThanOrEqualTo(tester.getTopLeft(find.byType(NkasFloatingAction)).dy),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('control page lists instances and saves per-instance overrides', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    _mockPlatform(calls);
    final platform = NkasPlatform.testing(events: const Stream.empty());
    await tester.pumpWidget(
      host(
        NativeControlPage(
          platform: platform,
          instances: const [
            InstanceInfo(name: 'nkas', state: 1, mod: 'nkas'),
            InstanceInfo(name: 'nkas2', state: 2, mod: 'nkas'),
          ],
          resolveBackendSerial: (name) async =>
              name == 'nkas' ? '10.0.0.1:5555' : null,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 后端 Serial 到达后行摘要展示来源；多实例时不再有全局共用地址框
    expect(find.text('默认控制地址'), findsNothing);
    expect(find.text('跟随后端：10.0.0.1:5555'), findsOneWidget);
    expect(find.text('未配置'), findsOneWidget);

    // 展开 nkas2 行填写覆盖地址，行摘要即时刷新
    await tester.tap(find.text('nkas2'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('control-endpoint-nkas2')),
      '10.0.0.2:5555',
    );
    await tester.pump();
    expect(find.text('10.0.0.2:5555'), findsWidgets);

    // 展开 nkas 行也填写覆盖地址后保存
    await tester.ensureVisible(find.text('nkas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('nkas'));
    await tester.pumpAndSettle();
    expect(find.text('默认使用后端 Serial：10.0.0.1:5555'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('control-endpoint-nkas')),
      '10.0.0.3:5555',
    );
    // mock 默认启用 Tailscale 且未保存身份，关掉后 AuthKey 校验才不拦截保存
    await tester.ensureVisible(find.text('通过 Tailscale 连接'));
    await tester.tap(find.text('通过 Tailscale 连接'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    final save = calls.singleWhere(
      (call) => call.method == 'saveNativeControlSettings',
    );
    expect((save.arguments as Map)['endpoints'], {
      'nkas': '10.0.0.3:5555',
      'nkas2': '10.0.0.2:5555',
    });
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'connect uses the resolved endpoint and flags a missing address',
    (tester) async {
      final calls = <MethodCall>[];
      _mockPlatform(calls);
      final platform = NkasPlatform.testing(events: const Stream.empty());
      Widget panel(Future<String?> Function() resolver) => host(
        SingleChildScrollView(
          child: ScreenPanel(
            platform: platform,
            accessGranted: true,
            loadScreenshot: () async => null,
            resolveEndpoint: resolver,
          ),
        ),
      );

      // 解析结果优先于设置里的全局地址（mock 的全局地址是 redroid:5555）
      await tester.pumpWidget(panel(() async => 'adb://10.0.0.9:5555'));
      await tester.pump();
      await tester.tap(find.byTooltip('连接设备'));
      await tester.pump();
      final start = calls.singleWhere(
        (call) => call.method == 'nativeScrcpyStart',
      );
      expect((start.arguments as Map)['endpoint'], 'adb://10.0.0.9:5555');
      expect(find.text('控制目标：adb://10.0.0.9:5555'), findsOneWidget);

      // 解析为空：不发起连接，提示配置控制地址
      await tester.pumpWidget(const SizedBox.shrink());
      calls.clear();
      await tester.pumpWidget(panel(() async => null));
      await tester.pump();
      await tester.tap(find.byTooltip('连接设备'));
      await tester.pump();
      expect(
        calls.where((call) => call.method == 'nativeScrcpyStart'),
        isEmpty,
      );
      expect(find.textContaining('未配置控制地址'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('fullscreen closes from its own button', (tester) async {
    final events = StreamController<NkasPlatformEvent>.broadcast();
    final platform = NkasPlatform.testing(events: events.stream);
    final calls = <MethodCall>[];
    _mockPlatform(calls);
    await tester.pumpWidget(
      host(
        SingleChildScrollView(
          child: ScreenPanel(
            platform: platform,
            accessGranted: true,
            loadScreenshot: () async => null,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('连接设备'));
    await tester.pump();
    final id =
        (calls.firstWhere((c) => c.method == 'nativeScrcpyStart').arguments
                as Map)['requestId']
            as String;
    events.add(
      ScrcpyVideoEvent(
        state: 'started',
        requestId: id,
        textureId: 9,
        width: 720,
        height: 1280,
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('全屏'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('退出全屏'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('退出全屏'), findsNothing);
    // 退出全屏不影响控制会话
    expect(find.byType(Texture), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await events.close();
  });

  testWidgets(
    'connection page fits a small keyboard viewport and cancels pending registration',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      addTearDown(tester.view.reset);
      final calls = <MethodCall>[];
      final connection = Completer<Object?>();
      _mockPlatform(calls, connection: connection);
      final platform = NkasPlatform.testing(events: const Stream.empty());
      await tester.pumpWidget(host(NativeControlPage(platform: platform)));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      // 键盘弹出后列表视口变矮，AuthKey 字段尚未构建，先滚动构建再输入
      await tester.scrollUntilVisible(
        find.text('Tailscale AuthKey'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(
        find.byType(TextFormField).last,
        'test-registration-key',
      );
      await tester.ensureVisible(find.text('验证连接'));
      await tester.pumpAndSettle();
      // 键盘弹出时保存按钮固定在列表下方，不再悬浮遮挡输入框
      expect(
        tester.getBottomLeft(find.byType(TextFormField).last).dy,
        lessThan(tester.getTopLeft(find.text('保存')).dy),
      );
      await tester.tap(find.text('验证连接'));
      await tester.pump();
      await tester.pump();
      expect(
        calls.where((call) => call.method == 'tsnetConnect'),
        hasLength(1),
      );
      expect(find.text('test-registration-key'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('取消连接'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('取消连接'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('取消连接'));
      await tester.pumpAndSettle();
      expect(find.text('连接已取消'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('connection page saves and closes; leaving keeps edits unsaved', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    _mockPlatform(calls);
    final platform = NkasPlatform.testing(events: const Stream.empty());
    var closed = 0;
    Widget page() =>
        host(NativeControlPage(platform: platform, onClose: () => closed++));
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).first,
      'adb://192.168.31.219:5555',
    );
    await tester.tap(find.text('通过 Tailscale 连接'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(closed, 1);
    final save = calls.singleWhere(
      (call) => call.method == 'saveNativeControlSettings',
    );
    expect((save.arguments as Map)['endpoint'], 'adb://192.168.31.219:5555');
    expect((save.arguments as Map)['tailscaleEnabled'], isFalse);
    expect(calls.where((call) => call.method == 'tsnetConnect'), isEmpty);

    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'unsaved:5555');
    await tester.pumpWidget(const SizedBox.shrink());
    expect(closed, 1);
    expect(
      calls.where((call) => call.method == 'saveNativeControlSettings'),
      hasLength(1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'connection page shows the registered node until identity clears',
    (tester) async {
      final calls = <MethodCall>[];
      final status = <String, Object?>{
        'phase': 'closed',
        'hostname': 'registered-phone',
        'hasPersistedLogin': true,
      };
      _mockPlatform(calls, status: status);
      await tester.pumpWidget(
        host(
          NativeControlPage(
            platform: NkasPlatform.testing(events: const Stream.empty()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('清除身份'));
      // 连接状态单独展示：已验证 + 节点名，AuthKey 输入框显示占位符
      expect(find.text('连接状态'), findsOneWidget);
      expect(find.text('已验证'), findsOneWidget);
      expect(find.textContaining('registered-phone'), findsOneWidget);
      expect(find.text('••••••••（已保存）'), findsOneWidget);

      final nameField = find.byType(TextFormField).at(1);
      await tester.ensureVisible(nameField);
      await tester.enterText(nameField, 'unsaved-phone');
      await tester.pump();
      expect(find.textContaining('registered-phone'), findsOneWidget);

      status['hasPersistedLogin'] = false;
      await tester.ensureVisible(find.text('清除身份'));
      await tester.tap(find.text('清除身份'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('清除'));
      await tester.pumpAndSettle();
      expect(
        calls.where((call) => call.method == 'tsnetClearState'),
        hasLength(1),
      );
      expect(find.textContaining('registered-phone'), findsNothing);
      expect(find.text('未验证'), findsOneWidget);
      expect(find.text('••••••••（已保存）'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('connection page surfaces tsnet errors in the status row', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    _mockPlatform(
      calls,
      status: const {
        'phase': 'error',
        'hostname': '',
        'hasPersistedLogin': false,
        'error': 'auth key expired',
      },
    );
    await tester.pumpWidget(
      host(
        NativeControlPage(
          platform: NkasPlatform.testing(events: const Stream.empty()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('连接状态'));
    expect(find.text('连接出错'), findsOneWidget);
    expect(find.text('auth key expired'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('screen stops control when leaving and reconnects manually', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    _mockPlatform(calls);
    final platform = NkasPlatform.testing(events: const Stream.empty());
    var opened = 0;
    Widget screen() => host(
      SingleChildScrollView(
        child: ScreenPanel(
          platform: platform,
          accessGranted: true,
          loadScreenshot: () async => null,
          onOpenNativeControl: () => opened++,
        ),
      ),
    );
    await tester.pumpWidget(screen());
    await tester.pump();
    await tester.tap(find.byTooltip('连接设备'));
    await tester.pump();
    final firstStart = calls.singleWhere(
      (call) => call.method == 'nativeScrcpyStart',
    );
    final firstId = (firstStart.arguments as Map)['requestId'];
    await tester.tap(find.byTooltip('控制连接设置'));
    await tester.pump();
    expect(opened, 1);
    expect(
      calls.where((call) => call.method == 'nativeScrcpyStart'),
      hasLength(1),
    );

    // shell 切页会销毁画面页：当前控制会话随之停止
    await tester.pumpWidget(host(NativeControlPage(platform: platform)));
    await tester.pumpAndSettle();
    final stop = calls.singleWhere((call) => call.method == 'nativeScrcpyStop');
    expect((stop.arguments as Map)['requestId'], firstId);

    // 返回画面页不自动重连，手动连接后按当前配置开始新会话
    await tester.pumpWidget(screen());
    await tester.pump();
    expect(
      calls.where((call) => call.method == 'nativeScrcpyStart'),
      hasLength(1),
    );
    await tester.tap(find.byTooltip('连接设备'));
    await tester.pump();
    final starts = calls
        .where((call) => call.method == 'nativeScrcpyStart')
        .toList();
    expect(starts, hasLength(2));
    expect((starts.last.arguments as Map)['requestId'], isNot(firstId));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'authorization restoration starts again and rejects stale session events',
    (tester) async {
      final events = StreamController<NkasPlatformEvent>.broadcast();
      final platform = NkasPlatform.testing(events: events.stream);
      final calls = <MethodCall>[];
      _mockPlatform(calls);
      Widget screen(bool access) => host(
        SingleChildScrollView(
          child: ScreenPanel(
            key: const ValueKey('screen'),
            platform: platform,
            accessGranted: access,
            loadScreenshot: () async => null,
          ),
        ),
      );
      await tester.pumpWidget(screen(true));
      await tester.pump();
      await tester.tap(find.byTooltip('连接设备'));
      await tester.pump();
      final first =
          (calls.firstWhere((c) => c.method == 'nativeScrcpyStart').arguments
                  as Map)['requestId']
              as String;
      await tester.pumpWidget(screen(false));
      await tester.pump();
      await tester.pumpWidget(screen(true));
      await tester.pump();
      await tester.tap(find.byTooltip('连接设备'));
      await tester.pump();
      final starts = calls
          .where((c) => c.method == 'nativeScrcpyStart')
          .toList();
      expect(starts, hasLength(2));
      events.add(
        ScrcpyVideoEvent(
          state: 'started',
          requestId: first,
          textureId: 1,
          width: 100,
          height: 100,
        ),
      );
      await tester.pump();
      expect(find.byType(Texture), findsNothing);
      final current = (starts.last.arguments as Map)['requestId'] as String;
      events.add(
        ScrcpyVideoEvent(
          state: 'started',
          requestId: current,
          textureId: 2,
          width: 100,
          height: 100,
        ),
      );
      await tester.pump();
      expect(tester.widget<Texture>(find.byType(Texture)).textureId, 2);
      await tester.pumpWidget(const SizedBox.shrink());
      await events.close();
    },
  );

  testWidgets('dragging the live control surface does not scroll the page', (
    tester,
  ) async {
    final events = StreamController<NkasPlatformEvent>.broadcast();
    final platform = NkasPlatform.testing(events: events.stream);
    final calls = <MethodCall>[];
    _mockPlatform(calls);
    await tester.pumpWidget(
      host(
        SingleChildScrollView(
          child: ScreenPanel(
            platform: platform,
            accessGranted: true,
            loadScreenshot: () async => null,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('连接设备'));
    await tester.pump();
    final id =
        (calls.firstWhere((c) => c.method == 'nativeScrcpyStart').arguments
                as Map)['requestId']
            as String;
    // 竖屏流让画面高度超出视口，页面本身可滚动，才可能暴露双滑
    events.add(
      ScrcpyVideoEvent(
        state: 'started',
        requestId: id,
        textureId: 9,
        width: 1080,
        height: 2400,
      ),
    );
    await tester.pump();
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    expect(position.maxScrollExtent, greaterThan(0));

    // 对照：落在卡片顶部的状态栏上拖动，页面必须滚起来
    final onBar = await dragToScroll(
      tester,
      tester.getTopLeft(find.byType(ScreenPanel)) + const Offset(60, 20),
    );
    expect(onBar, greaterThan(0));
    position.jumpTo(0);
    await tester.pump();

    // 画面可见区域内的拖动交给设备，页面不动
    final video = tester.getRect(find.byType(Texture));
    final viewport =
        Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;
    final onVideo = await dragToScroll(
      tester,
      video.intersect(viewport).center,
    );
    expect(onVideo, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await events.close();
  });
}

void _mockPlatform(
  List<MethodCall> calls, {
  Completer<Object?>? connection,
  Map<String, Object?> status = const {'hasPersistedLogin': false},
}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('com.megumiss.nkas/platform'),
        (call) async {
          calls.add(call);
          if (call.method == 'getNativeControlSettings') {
            return {
              'mode': 'remote_adb',
              'endpoint': 'redroid:5555',
              'tailscaleEnabled': true,
              'hostname': 'test-phone',
            };
          }
          if (call.method == 'nativeScrcpyStart') {
            return {'scid': 1, 'textureId': 9, 'video': true, 'control': true};
          }
          if (call.method == 'tsnetStatus') return status;
          if (call.method == 'tsnetConnect' && connection != null) {
            return connection.future;
          }
          if (call.method == 'tsnetClose' &&
              connection != null &&
              !connection.isCompleted) {
            connection.completeError(
              PlatformException(code: 'cancelled', message: '连接已取消'),
            );
          }
          return true;
        },
      );
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.megumiss.nkas/platform'),
          null,
        ),
  );
}
