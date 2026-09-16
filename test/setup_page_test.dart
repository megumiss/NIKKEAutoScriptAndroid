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

const _alreadyRunning = '[nkas] bootstrap already running (PID 4312)\n';

SetupStatus _status({
  bool complete = false,
  bool termuxInstalled = true,
  bool adbDeviceReady = true,
}) => SetupStatus(
  authorized: true,
  termuxInstalled: termuxInstalled,
  runCommandPermission: true,
  wirelessDebug: true,
  serial: '',
  commandExitCode: 0,
  artifacts: {
    'termux_setting': true,
    'adb_device': adbDeviceReady,
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

String _installationLines(int count) =>
    List.generate(count, (index) => '安装日志第 $index 行').join('\n');

Finder _installationLog() => find.ancestor(
  of: find.textContaining('安装日志第'),
  matching: find.byType(SingleChildScrollView),
);

ScrollPosition _installationLogPosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(
        of: _installationLog(),
        matching: find.byType(Scrollable),
      ),
    )
    .position;

void _expectStepState(WidgetTester tester, String title, String state) {
  final row = find.ancestor(of: find.text(title), matching: find.byType(Row));
  expect(find.descendant(of: row, matching: find.text(state)), findsOneWidget);
}

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
          expect(find.byType(NkasFloatingAction), findsNothing);

          // A delayed command timeout must not undo a confirmed completion.
          await _emit(tester, events, _timeout);
          expect(find.byType(NkasFloatingAction), findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await events.close();
        }
      },
    );
  }

  for (final adbDeviceReady in [false, true]) {
    testWidgets(
      'service completion updates the step and action with ADB ${adbDeviceReady ? 'connected' : 'pending'}',
      (tester) async {
        final events = StreamController<NkasPlatformEvent>.broadcast();
        final platform = _SetupPlatform(events.stream);
        try {
          await _startSetup(tester, platform);
          await _emit(tester, events, _log('starting-nkas', '正在启动服务'));
          platform.status = _status(
            complete: true,
            adbDeviceReady: adbDeviceReady,
          );
          await tester.pump(const Duration(seconds: 4));
          expect(find.text('服务已响应'), findsOneWidget);

          // The final snapshot still contains earlier installation stages.
          await _emit(
            tester,
            events,
            _log(
              'ready',
              '[nkas] state=installing-container\n'
                  '[nkas] state=starting-nkas\n'
                  '[nkas] bootstrap complete',
            ),
          );
          await _emit(tester, events, const SetupStateEvent('ready', null));
          _expectStepState(tester, '容器服务', '已完成');
          expect(
            find.descendant(
              of: find.ancestor(
                of: find.text('容器服务'),
                matching: find.byType(Row),
              ),
              matching: find.byIcon(LucideIcons.check),
            ),
            findsOneWidget,
          );
          if (adbDeviceReady) {
            expect(find.byType(NkasFloatingAction), findsNothing);
          } else {
            expect(_action(tester).label, '等待 ADB 设备');
            expect(_action(tester).enabled, isFalse);
          }

          // A buffered log from an earlier poll must not reopen the install.
          await _emit(tester, events, _log('starting-nkas', '延迟到达的启动日志'));
          await tester.pump(const Duration(seconds: 4));
          _expectStepState(tester, '容器服务', '已完成');
          if (adbDeviceReady) {
            expect(find.byType(NkasFloatingAction), findsNothing);
          } else {
            expect(_action(tester).label, '等待 ADB 设备');
            expect(_action(tester).enabled, isFalse);
          }
          expect(platform.starts, 1);
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
    (
      'another exit code 2',
      const SetupOutputEvent('无法创建安装锁目录', exitCode: 2),
      '无法创建安装锁目录',
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

  for (final logBeforeResult in [false, true]) {
    testWidgets(
      'retry follows the existing installation with progress ${logBeforeResult ? 'before' : 'after'} the command result',
      (tester) async {
        final events = StreamController<NkasPlatformEvent>.broadcast();
        final previousError = Exception('Termux 外部命令等待超时');
        final platform = _SetupPlatform(events.stream)
          ..startError = previousError;
        try {
          // Start from the failed UI left by the earlier timeout behavior.
          await _startSetup(tester, platform);
          expect(_action(tester).label, '重试当前安装');
          platform.startError = null;
          await tester.tap(find.text('重试当前安装'));
          await tester.pump();
          await tester.pump();
          expect(platform.starts, 2);

          if (logBeforeResult) {
            await _emit(tester, events, _log('installing-container', '正在下载容器'));
          }
          await _emit(
            tester,
            events,
            const SetupOutputEvent(_alreadyRunning, exitCode: 2),
          );
          if (!logBeforeResult) {
            await _emit(tester, events, _log('installing-container', '正在下载容器'));
          }
          // Android also emits a setup failure for this nonzero command exit.
          await _emit(
            tester,
            events,
            const SetupStateEvent('failed', _alreadyRunning),
          );

          expect(_action(tester).label, '正在安装…');
          expect(_action(tester).enabled, isFalse);
          expect(find.text('失败'), findsNothing);
          expect(find.text(previousError.toString()), findsNothing);
          _expectStepState(tester, 'Termux 工具', '完成');
          _expectStepState(tester, '容器', '执行中');
          _expectStepState(tester, '容器服务', '等待');
          expect(find.textContaining('正在下载容器'), findsOneWidget);

          final checksBefore = platform.statusChecks;
          await tester.pump(const Duration(seconds: 4));
          expect(platform.statusChecks, greaterThan(checksBefore));
          await tester.tap(find.text('正在安装…'));
          await tester.pump();
          expect(platform.starts, 2);

          await _emit(tester, events, _log('starting-nkas', '正在启动服务'));
          _expectStepState(tester, '容器', '完成');
          _expectStepState(tester, '容器服务', '执行中');
          platform.status = _status(complete: true);
          await _emit(tester, events, const SetupStateEvent('ready', null));
          expect(find.byType(NkasFloatingAction), findsNothing);

          // A late duplicate result must not restart the completed UI.
          await _emit(
            tester,
            events,
            const SetupOutputEvent(_alreadyRunning, exitCode: 2),
          );
          await _emit(
            tester,
            events,
            const SetupStateEvent('failed', _alreadyRunning),
          );
          expect(find.byType(NkasFloatingAction), findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await events.close();
        }
      },
    );
  }

  testWidgets(
    'an existing-process notice clears a latched failure and resumes checks',
    (tester) async {
      final events = StreamController<NkasPlatformEvent>.broadcast();
      final platform = _SetupPlatform(events.stream);
      try {
        await _startSetup(tester, platform);
        await _emit(
          tester,
          events,
          const SetupOutputEvent('安装命令响应丢失', exitCode: -1),
        );
        expect(_action(tester).label, '重试当前安装');

        await _emit(
          tester,
          events,
          const SetupStateEvent('failed', _alreadyRunning),
        );
        expect(_action(tester).label, '正在安装…');
        expect(_action(tester).enabled, isFalse);
        expect(find.text('失败'), findsNothing);
        expect(find.text('安装命令响应丢失'), findsNothing);
        final checksBefore = platform.statusChecks;
        await tester.pump(const Duration(seconds: 4));
        expect(platform.statusChecks, greaterThan(checksBefore));

        await _emit(tester, events, _log('cloning-nkas', '继续下载源码'));
        _expectStepState(tester, 'Termux 工具', '完成');
        _expectStepState(tester, 'NKAS 源码', '执行中');
        expect(find.textContaining('继续下载源码'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await events.close();
      }
    },
  );

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
    'initialization logs follow new output and reopening shows the end',
    (tester) async {
      final events = StreamController<NkasPlatformEvent>.broadcast();
      final platform = _SetupPlatform(events.stream);
      try {
        await _startSetup(tester, platform);
        await _emit(
          tester,
          events,
          _log('installing-termux-tools', _installationLines(1)),
        );
        expect(tester.getSize(_installationLog()).height, lessThan(190));
        expect(_installationLogPosition(tester).maxScrollExtent, 0);

        for (final count in [80, 100]) {
          await _emit(
            tester,
            events,
            _log('installing-termux-tools', _installationLines(count)),
          );
          final position = _installationLogPosition(tester);
          expect(tester.getSize(_installationLog()).height, closeTo(190, .1));
          expect(position.maxScrollExtent, greaterThan(0));
          expect(position.pixels, closeTo(position.maxScrollExtent, .1));
        }

        await tester.tap(find.text('Termux 工具'));
        await tester.pump();
        expect(_installationLog(), findsNothing);
        await tester.tap(find.text('Termux 工具'));
        await tester.pump();
        await tester.pump();
        final position = _installationLogPosition(tester);
        expect(position.pixels, closeTo(position.maxScrollExtent, .1));
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await events.close();
      }
    },
  );

  testWidgets(
    'initialization log following pauses while reading earlier output',
    (tester) async {
      final events = StreamController<NkasPlatformEvent>.broadcast();
      final platform = _SetupPlatform(events.stream);
      try {
        await _startSetup(tester, platform);
        await _emit(
          tester,
          events,
          _log('installing-termux-tools', _installationLines(80)),
        );
        await tester.ensureVisible(_installationLog());
        await tester.drag(_installationLog(), const Offset(0, 120));
        // The install button keeps animating while the log scroll settles.
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        final previousOffset = _installationLogPosition(tester).pixels;
        expect(_installationLogPosition(tester).extentAfter, greaterThan(50));

        await _emit(
          tester,
          events,
          _log('installing-termux-tools', _installationLines(100)),
        );
        expect(
          _installationLogPosition(tester).pixels,
          closeTo(previousOffset, .1),
        );
        await tester.pump(const Duration(seconds: 4));
        expect(
          _installationLogPosition(tester).pixels,
          closeTo(previousOffset, .1),
        );

        await tester.drag(_installationLog(), const Offset(0, -4000));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(_installationLogPosition(tester).extentAfter, lessThan(1));
        await _emit(
          tester,
          events,
          _log('installing-termux-tools', _installationLines(120)),
        );
        final position = _installationLogPosition(tester);
        expect(position.pixels, closeTo(position.maxScrollExtent, .1));
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await events.close();
      }
    },
  );

  testWidgets(
    'initialization log scrolling reveals errors before later output',
    (tester) async {
      final events = StreamController<NkasPlatformEvent>.broadcast();
      final platform = _SetupPlatform(events.stream);
      try {
        await _startSetup(tester, platform);
        await _emit(
          tester,
          events,
          _log('installing-termux-tools', _installationLines(80)),
        );
        final position = _installationLogPosition(tester);
        expect(position.pixels, closeTo(position.maxScrollExtent, .1));
        await _emit(
          tester,
          events,
          const SetupOutputEvent('apt-get 下载失败', exitCode: 100),
        );
        expect(_installationLogPosition(tester).pixels, closeTo(0, .1));
        _expectStepMessage(
          tester,
          'apt-get 下载失败',
          title: 'Termux 工具',
          nextTitle: 'NKAS 源码',
        );

        await _emit(
          tester,
          events,
          _log('installing-termux-tools', _installationLines(100)),
        );
        expect(_installationLogPosition(tester).pixels, closeTo(0, .1));
        expect(_action(tester).label, '重试当前安装');
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await events.close();
      }
    },
  );

  testWidgets(
    'container step explains the image source and network requirement',
    (tester) async {
      final events = StreamController<NkasPlatformEvent>.broadcast();
      final platform = _SetupPlatform(events.stream);
      try {
        await _mountSetup(tester, platform);
        // 容器是第一个未完成的步骤，会随状态刷新自动展开
        await tester.scrollUntilVisible(
          find.text('容器'),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('官方镜像源'), findsOneWidget);
        expect(find.textContaining('网络畅通'), findsOneWidget);
        expect(
          find.textContaining('docker.1ms.run/megumiss/nkas:latest'),
          findsOneWidget,
        );

        // 收起再展开仍应保留提示，说明它挂在步骤行内部而不是临时浮层
        await tester.tap(find.text('容器'));
        await tester.pumpAndSettle();
        expect(find.textContaining('官方镜像源'), findsNothing);
        await tester.tap(find.text('容器'));
        await tester.pumpAndSettle();
        expect(find.textContaining('官方镜像源'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await events.close();
      }
    },
  );

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

  testWidgets('keyboard open pins the action button below the step inputs', (
    tester,
  ) async {
    final events = StreamController<NkasPlatformEvent>.broadcast();
    final platform = _SetupPlatform(events.stream);
    try {
      await _mountSetup(tester, platform);

      // 展开 ADB 设备连接步骤，露出端口与配对码输入框
      await tester.scrollUntilVisible(
        find.text('ADB 设备连接'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('ADB 设备连接'));
      await tester.tap(find.text('ADB 设备连接'));
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsNWidgets(2));

      // 键盘弹出后操作按钮固定在列表下方，不再悬浮遮挡输入框
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      addTearDown(tester.view.reset);
      await tester.pumpAndSettle();
      // 键盘弹出后列表视口变矮，输入框尚未构建，先滚动构建
      await tester.scrollUntilVisible(
        find.text('配对码'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(
        tester.getBottomLeft(find.byType(TextFormField).last).dy,
        lessThan(tester.getTopLeft(find.byType(NkasFloatingAction)).dy),
      );
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await events.close();
    }
  });
}
