import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nkas_mobile/core/platform/nkas_platform.dart';
import 'package:nkas_mobile/features/screen/native_video_surface.dart';
import 'package:nkas_mobile/features/screen/screen_page.dart';
import 'package:nkas_mobile/features/settings/native_control_sheet.dart';
import 'package:nkas_mobile/theme.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

Widget host(Widget child) => ShadApp(
  theme: nkasThemeData(Brightness.light),
  home: Scaffold(body: child),
);

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
        ScreenPanel(
          platform: platform,
          accessGranted: true,
          loadScreenshot: () async {
            captures++;
            return null;
          },
        ),
      ),
    );
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

  testWidgets(
    'connection settings fit a small keyboard viewport and cancel pending registration',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      addTearDown(tester.view.reset);
      final calls = <MethodCall>[];
      final connection = Completer<Object?>();
      _mockPlatform(calls, connection: connection);
      final platform = NkasPlatform.testing(events: const Stream.empty());
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showNativeControlSettings(context, platform: platform),
              child: const Text('设置'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).last,
        'test-registration-key',
      );
      await tester.ensureVisible(find.text('验证连接'));
      await tester.tap(find.text('验证连接'));
      await tester.pump();
      await tester.pump();
      expect(
        calls.where((call) => call.method == 'tsnetConnect'),
        hasLength(1),
      );
      expect(find.text('test-registration-key'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('控制连接'), findsOneWidget);
      await tester.ensureVisible(find.text('取消连接'));
      await tester.tap(find.text('取消连接'));
      await tester.pumpAndSettle();
      expect(find.text('连接已取消'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('关闭'));
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(find.text('控制连接'), findsNothing);
    },
  );

  testWidgets(
    'authorization restoration starts again and rejects stale session events',
    (tester) async {
      final events = StreamController<NkasPlatformEvent>.broadcast();
      final platform = NkasPlatform.testing(events: events.stream);
      final calls = <MethodCall>[];
      _mockPlatform(calls);
      Widget screen(bool access) => host(
        ScreenPanel(
          key: const ValueKey('screen'),
          platform: platform,
          accessGranted: access,
          loadScreenshot: () async => null,
        ),
      );
      await tester.pumpWidget(screen(true));
      await tester.pump();
      final first =
          (calls.firstWhere((c) => c.method == 'nativeScrcpyStart').arguments
                  as Map)['requestId']
              as String;
      await tester.pumpWidget(screen(false));
      await tester.pump();
      await tester.pumpWidget(screen(true));
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
}

void _mockPlatform(List<MethodCall> calls, {Completer<Object?>? connection}) {
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
          if (call.method == 'tsnetStatus') return {'hasPersistedLogin': false};
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
