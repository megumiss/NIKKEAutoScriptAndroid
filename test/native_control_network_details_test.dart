import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nkas_mobile/core/platform/nkas_platform.dart';
import 'package:nkas_mobile/core/widgets/form_field.dart';
import 'package:nkas_mobile/features/settings/native_control_page.dart';
import 'package:nkas_mobile/theme.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

// The network details only render while `status.phase == 'connected'`, but the
// forwarder teardown that follows every connection clears `phase`, `addresses`
// and `magicDNS`. Reading the status after closing it therefore yields an empty
// payload and *nothing* is displayed, on both platforms.
//
// These tests drive the real "验证连接" flow through the method channel and
// assert on the rendered text, so a regression in the ordering fails here
// rather than silently showing an empty card.

const _channel = MethodChannel('com.megumiss.nkas/platform');

/// The status a connected forwarder reports before teardown.
const _connected = <String, Object?>{
  'phase': 'connected',
  'hostname': 'nkas-ios',
  'addresses': ['100.64.0.1', 'fd7a:115c:a1e0::1'],
  'magicDNS': 'nkas.tailnet.ts.net',
  'forwardCount': 0,
  'hasPersistedLogin': true,
  'error': '',
};

/// What the same forwarder reports once it has been closed.
const _closed = <String, Object?>{
  'phase': 'closed',
  'hostname': 'nkas-ios',
  'addresses': <String>[],
  'magicDNS': '',
  'forwardCount': 0,
  'hasPersistedLogin': true,
  'error': '',
};

Widget _host(Widget child) => ShadApp(
  theme: nkasThemeData(Brightness.light),
  materialThemeBuilder: nkasMaterialTheme,
  home: Scaffold(body: child),
);

/// Mock the native side, tracking whether the forwarder is currently up.
///
/// `tsnetStatus` deliberately answers with the *closed* payload after
/// `tsnetClose`, which is what the real forwarder does.
void _mockPlatform(List<MethodCall> calls, {required bool Function() isOpen}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) async {
        calls.add(call);
        switch (call.method) {
          case 'getNativeControlSettings':
            return {
              'mode': 'remote_adb',
              // Required by the page's endpoint validator when no instances are
              // supplied, so the save action can actually run.
              'endpoint': 'redroid:5555',
              'tailscaleEnabled': true,
              'hostname': 'nkas-ios',
              'endpoints': <String, String>{},
            };
          case 'tsnetConfigure':
          case 'tsnetConnect':
            return isOpen() ? _connected : _closed;
          case 'tsnetClose':
            return true;
          case 'tsnetStatus':
            return isOpen() ? _connected : _closed;
        }
        return true;
      });
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('keeps MagicDNS and both addresses after the connection closes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final calls = <MethodCall>[];
    // The forwarder reports connected until tsnetClose is observed.
    var open = true;
    _mockPlatform(
      calls,
      isOpen: () {
        if (calls.any((call) => call.method == 'tsnetClose')) open = false;
        return open;
      },
    );

    final platform = NkasPlatform.testing(events: const Stream.empty());
    await tester.pumpWidget(_host(NativeControlPage(platform: platform)));
    await tester.pumpAndSettle();

    // The AuthKey is required to trigger a registration attempt.
    await tester.enterText(
      find.widgetWithText(NkasTextField, 'Tailscale AuthKey'),
      'tskey-auth-example',
    );
    await tester.tap(find.text('验证连接'));
    await tester.pumpAndSettle();

    // The real assertion: the rows are on screen despite the teardown.
    expect(find.text('MagicDNS'), findsOneWidget);
    expect(find.text('nkas.tailnet.ts.net'), findsOneWidget);
    expect(find.text('Tailscale IPv4'), findsOneWidget);
    expect(find.text('100.64.0.1'), findsOneWidget);
    expect(find.text('Tailscale IPv6'), findsOneWidget);
    expect(find.text('fd7a:115c:a1e0::1'), findsOneWidget);

    // And the teardown really did happen, so this is not passing by luck.
    expect(calls.map((call) => call.method), contains('tsnetClose'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows no network rows before any connection', (tester) async {
    final calls = <MethodCall>[];
    var open = false;
    _mockPlatform(calls, isOpen: () => open);

    final platform = NkasPlatform.testing(events: const Stream.empty());
    await tester.pumpWidget(_host(NativeControlPage(platform: platform)));
    await tester.pumpAndSettle();
    open = false;

    expect(find.text('MagicDNS'), findsNothing);
    expect(find.text('Tailscale IPv4'), findsNothing);
    expect(find.text('Tailscale IPv6'), findsNothing);
  });

  testWidgets('drops the remembered addresses when the identity is cleared', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final calls = <MethodCall>[];
    var open = true;
    _mockPlatform(
      calls,
      isOpen: () {
        if (calls.any(
          (call) =>
              call.method == 'tsnetClose' || call.method == 'tsnetClearState',
        )) {
          open = false;
        }
        return open;
      },
    );

    final platform = NkasPlatform.testing(events: const Stream.empty());
    await tester.pumpWidget(_host(NativeControlPage(platform: platform)));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(NkasTextField, 'Tailscale AuthKey'),
      'tskey-auth-example',
    );
    await tester.tap(find.text('验证连接'));
    await tester.pumpAndSettle();
    expect(find.text('MagicDNS'), findsOneWidget);

    // Clearing the identity must not leave stale addresses on screen.
    await tester.tap(find.text('清除身份'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清除'));
    await tester.pumpAndSettle();

    expect(find.text('MagicDNS'), findsNothing);
    expect(find.text('100.64.0.1'), findsNothing);
  });
}
