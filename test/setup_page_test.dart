import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nkas_mobile/core/platform/nkas_platform.dart';
import 'package:nkas_mobile/core/widgets/floating_action.dart';
import 'package:nkas_mobile/core/widgets/surface.dart';
import 'package:nkas_mobile/features/settings/setup_page.dart';
import 'package:nkas_mobile/theme.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

const _timeout = SetupOutputEvent(
  'Termux 外部命令等待超时，请确认 Termux 已完全重启且 allow-external-apps=true。',
  exitCode: -2,
);

SetupStatus _status({bool complete = false, bool termuxInstalled = true}) =>
    SetupStatus(
      authorized: true,
      termuxInstalled: termuxInstalled,
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
  int downloads = 0;
  Object? statusError;
  Object? startError;

  @override
  Future<SetupStatus> setupStatus() async {
    statusChecks++;
    if (statusError case final error?) throw error;
    return status;
  }

  @override
  Future<bool> initialNoticeShown() async => true;

  @override
  Future<void> startSetup() async {
    starts++;
    if (startError case final error?) throw error;
  }

  @override
  Future<void> downloadTermux() async {
    downloads++;
  }
}

Future<void> _mountSetup(WidgetTester tester, _SetupPlatform platform) async {
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
}

Future<void> _startSetup(WidgetTester tester, _SetupPlatform platform) async {
  await _mountSetup(tester, platform);
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

void _expectStepMessage(
  WidgetTester tester,
  String message, {
  required String title,
  String? nextTitle,
}) {
  final feedback = find.text(message);
  expect(feedback, findsOneWidget);
  expect(
    find.ancestor(of: feedback, matching: find.byType(Surface)),
    findsOneWidget,
  );
  final bounds = tester.getRect(feedback);
  expect(bounds.top, greaterThan(tester.getRect(find.text(title)).bottom));
  if (nextTitle != null) {
    expect(bounds.bottom, lessThan(tester.getRect(find.text(nextTitle)).top));
  }
}

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
        // A failure must reopen its step even when the user collapsed its log.
        await tester.tap(find.text('Termux 工具'));
        await tester.pump();
        await _emit(tester, events, event);

        expect(_action(tester).label, '重试当前安装');
        expect(_action(tester).enabled, isTrue);
        await tester.scrollUntilVisible(
          find.text(message),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        _expectStepMessage(
          tester,
          message,
          title: 'Termux 工具',
          nextTitle: 'NKAS 源码',
        );

        // Buffered progress/completion events cannot hide a real failure.
        await _emit(tester, events, _log('cloning-nkas', '延迟到达的日志'));
        await _emit(tester, events, const SetupStateEvent('ready', null));
        expect(_action(tester).label, '重试当前安装');
        _expectStepMessage(
          tester,
          message,
          title: 'Termux 工具',
          nextTitle: 'NKAS 源码',
        );

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

  testWidgets('bootstrap start errors stay in the first installation step', (
    tester,
  ) async {
    final events = StreamController<NkasPlatformEvent>.broadcast();
    final failure = Exception('无法启动安装脚本');
    final platform = _SetupPlatform(events.stream)..startError = failure;
    try {
      await _startSetup(tester, platform);
      await tester.scrollUntilVisible(
        find.text(failure.toString()),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      _expectStepMessage(
        tester,
        failure.toString(),
        title: 'Termux 工具',
        nextTitle: 'NKAS 源码',
      );
      expect(_action(tester).label, '重试当前安装');

      platform.startError = null;
      await tester.tap(find.text('重试当前安装'));
      await tester.pump();
      await tester.pump();
      expect(platform.starts, 2);
      expect(find.text(failure.toString()), findsNothing);
      expect(_action(tester).label, '正在安装…');
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await events.close();
    }
  });

  testWidgets('Termux download errors appear once below the Termux step', (
    tester,
  ) async {
    final events = StreamController<NkasPlatformEvent>.broadcast();
    final platform = _SetupPlatform(events.stream)
      ..status = _status(termuxInstalled: false);
    try {
      await _mountSetup(tester, platform);
      await _emit(tester, events, const TermuxDownloadEvent(progress: 42));
      await _emit(tester, events, const TermuxDownloadEvent(error: '下载连接中断'));
      _expectStepMessage(
        tester,
        'Termux 下载失败：下载连接中断',
        title: 'Termux',
        nextTitle: 'Android 外部命令权限',
      );
      expect(find.text('下载连接中断'), findsNothing);
      expect(_action(tester).label, '重试下载 Termux');

      await tester.tap(find.text('重试下载 Termux'));
      await tester.pump();
      expect(platform.downloads, 1);
      expect(find.textContaining('下载连接中断'), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await events.close();
    }
  });

  testWidgets('ADB notices appear under the connection controls', (
    tester,
  ) async {
    final events = StreamController<NkasPlatformEvent>.broadcast();
    final platform = _SetupPlatform(events.stream)
      ..status = _status(complete: true);
    const notice = '已通过 mDNS 自动发现无线调试端口：37123';
    try {
      await _mountSetup(tester, platform);
      await _emit(tester, events, const SetupNoticeEvent(notice));
      await tester.scrollUntilVisible(
        find.text(notice),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      _expectStepMessage(tester, notice, title: 'ADB 设备连接');
      expect(
        tester.getRect(find.text(notice)).top,
        greaterThan(tester.getRect(find.text('配对')).bottom),
      );
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await events.close();
    }
  });

  testWidgets(
    'status query errors appear above the queue and clear on refresh',
    (tester) async {
      final events = StreamController<NkasPlatformEvent>.broadcast();
      final failure = Exception('无法读取初始化状态');
      final platform = _SetupPlatform(events.stream)..statusError = failure;
      try {
        await _mountSetup(tester, platform);
        expect(find.text(failure.toString()), findsOneWidget);
        expect(
          tester.getRect(find.text(failure.toString())).bottom,
          lessThan(tester.getRect(find.text('环境准备')).top),
        );
        platform.statusError = null;
        await _emit(
          tester,
          events,
          const StarAuthorizationEvent(StarAuthorization(authorized: true)),
        );
        expect(find.text(failure.toString()), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await events.close();
      }
    },
  );
}
