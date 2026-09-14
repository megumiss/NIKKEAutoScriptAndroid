import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nkas_mobile/core/platform/nkas_platform.dart';
import 'package:nkas_mobile/core/widgets/floating_action.dart';
import 'package:nkas_mobile/features/settings/setup_page.dart';
import 'package:nkas_mobile/theme.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

const _timeout = SetupOutputEvent(
  'Termux 外部命令等待超时，请确认 Termux 已完全重启且 allow-external-apps=true。',
  exitCode: -2,
);

SetupStatus _status({bool complete = false}) => SetupStatus(
  authorized: true,
  termuxInstalled: true,
  runCommandPermission: true,
  wirelessDebug: true,
  serial: '',
  commandExitCode: 0,
  artifacts: {
    'termux_setting': true,
    'adb_device': true,
    'tools': complete,
    'source': complete,
    'config': complete,
    'container': complete,
    'service': complete,
  },
);

class _SetupPlatform extends NkasPlatform {
  _SetupPlatform(Stream<NkasPlatformEvent> events)
    : super.testing(events: events);

  SetupStatus status = _status();
  int statusChecks = 0;
  int starts = 0;

  @override
  Future<SetupStatus> setupStatus() async {
    statusChecks++;
    return status;
  }

  @override
  Future<bool> initialNoticeShown() async => true;

  @override
  Future<void> startSetup() async {
    starts++;
  }
}

Future<void> _startSetup(WidgetTester tester, _SetupPlatform platform) async {
  await tester.pumpWidget(
    ShadApp(
      theme: nkasThemeData(Brightness.light),
      materialThemeBuilder: nkasMaterialTheme,
      home: Scaffold(
        body: NkasSetupPage(
          platform: platform,
          onOpenStar: () {},
          onOpenUi: () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('开始安装'));
  await tester.pump();
  await tester.pump();
  expect(platform.starts, 1);
}

Future<void> _emit(
  WidgetTester tester,
  StreamController<NkasPlatformEvent> events,
  NkasPlatformEvent event,
) async {
  events.add(event);
  await tester.pump();
  await tester.pump();
}

SetupOutputEvent _log(String stage, String message) => SetupOutputEvent(
  '---STATE---\n$stage\n---LOG---\n[nkas] state=$stage\n$message\n---SERVICE---\n',
  log: true,
);

NkasFloatingAction _action(WidgetTester tester) =>
    tester.widget<NkasFloatingAction>(find.byType(NkasFloatingAction));

void main() {
  for (final receivedLog in [false, true]) {
    testWidgets(
      'bootstrap keeps running after callback timeout ${receivedLog ? 'after' : 'before'} the first log',
      (tester) async {
        final events = StreamController<NkasPlatformEvent>.broadcast();
        final platform = _SetupPlatform(events.stream);
        try {
          await _startSetup(tester, platform);
          if (receivedLog) {
            await _emit(
              tester,
              events,
              _log('installing-termux-tools', '正在安装 Termux 工具'),
            );
          }
          await tester.pump(const Duration(seconds: 12));
          await _emit(tester, events, _timeout);

          expect(_action(tester).label, '正在安装…');
          expect(_action(tester).enabled, isFalse);
          expect(find.text('重试当前安装'), findsNothing);
          expect(find.textContaining('Termux 外部命令等待超时'), findsNothing);
          await tester.tap(find.text('正在安装…'));
          await tester.pump();
          expect(platform.starts, 1);

          final checksBefore = platform.statusChecks;
          await tester.pump(const Duration(seconds: 4));
          expect(platform.statusChecks, greaterThan(checksBefore));

          await _emit(tester, events, _log('cloning-nkas', '正在下载源码'));
          expect(find.textContaining('正在下载源码'), findsOneWidget);
          expect(find.text('失败'), findsNothing);
          expect(_action(tester).label, '正在安装…');

          platform.status = _status(complete: true);
          await _emit(tester, events, const SetupStateEvent('ready', null));
          expect(_action(tester).label, '打开 NKAS UI');
          expect(_action(tester).enabled, isTrue);

          // A delayed command timeout must not undo a confirmed completion.
          await _emit(tester, events, _timeout);
          expect(_action(tester).label, '打开 NKAS UI');
          expect(_action(tester).enabled, isTrue);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await events.close();
        }
      },
    );
  }

  for (final (name, event, message) in [
    (
      'command exit',
      const SetupOutputEvent('apt-get 安装失败', exitCode: 100),
      'apt-get 安装失败',
    ),
    ('script state', const SetupStateEvent('failed', '安装脚本报告失败'), '安装脚本报告失败'),
  ]) {
    testWidgets('bootstrap still reports a real failure from $name', (
      tester,
    ) async {
      final events = StreamController<NkasPlatformEvent>.broadcast();
      final platform = _SetupPlatform(events.stream);
      try {
        await _startSetup(tester, platform);
        await _emit(
          tester,
          events,
          _log('installing-termux-tools', '正在安装 Termux 工具'),
        );
        await _emit(tester, events, _timeout);
        await _emit(tester, events, event);

        expect(_action(tester).label, '重试当前安装');
        expect(_action(tester).enabled, isTrue);
        await tester.scrollUntilVisible(
          find.text(message),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text(message), findsOneWidget);

        // Buffered progress/completion events cannot hide a real failure.
        await _emit(tester, events, _log('cloning-nkas', '延迟到达的日志'));
        await _emit(tester, events, const SetupStateEvent('ready', null));
        expect(_action(tester).label, '重试当前安装');
        expect(find.text(message), findsOneWidget);

        await tester.tap(find.text('重试当前安装'));
        await tester.pump();
        await tester.pump();
        expect(platform.starts, 2);
        expect(_action(tester).label, '正在安装…');
        expect(_action(tester).enabled, isFalse);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await events.close();
      }
    });
  }
}
