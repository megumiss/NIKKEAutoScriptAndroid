// 概览页「启动服务 / 停止服务」按钮的回归。
//
// 起停共用同一个位置，由 serviceRunning（后端是否连上）决定显示哪一个：
// 服务在跑时只能停，服务没跑时只能起。停止会中断正在运行的任务，用警示色；
// 启动是恢复性操作，保持次级按钮的常规配色。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:nkas_mobile/core/widgets/buttons.dart';
import 'package:nkas_mobile/features/overview/overview_page.dart';
import 'package:nkas_mobile/theme.dart';

Future<void> _pumpOverview(
  WidgetTester tester, {
  required Brightness brightness,
  required bool serviceRunning,
  bool withServiceActions = true,
  bool busy = false,
}) async {
  await tester.pumpWidget(
    ShadApp(
      theme: nkasThemeData(brightness),
      home: Scaffold(
        body: OverviewPage(
          serviceRunning: serviceRunning,
          onRefreshStatus: () async {},
          onOpenInstances: () {},
          onSelectInstance: (_) {},
          instances: const [],
          loadingInstances: false,
          instancesError: null,
          avatarUrl: (_) => null,
          resolveAssetUrl: (value) => value,
          calendarItems: const [],
          calendarUpdatedAt: 0,
          calendarLoading: false,
          calendarError: null,
          onRefreshCalendar: () async {},
          onStartService: withServiceActions ? () async {} : null,
          onStopService: withServiceActions ? () async {} : null,
          startingService: busy && !serviceRunning,
          stoppingService: busy && serviceRunning,
        ),
      ),
    ),
  );
  // busy 时会显示无限循环的进度指示，pumpAndSettle 永远不会收敛。
  if (busy) {
    await tester.pump();
  } else {
    await tester.pumpAndSettle();
  }
}

NkasButton _buttonLabelled(WidgetTester tester, String label) {
  return tester
      .widgetList<NkasButton>(find.byType(NkasButton))
      .firstWhere((button) => button.label == label);
}

void main() {
  testWidgets('running service offers stop instead of start', (tester) async {
    await _pumpOverview(
      tester,
      brightness: Brightness.light,
      serviceRunning: true,
    );

    expect(find.text('停止服务'), findsOneWidget);
    expect(find.text('启动服务'), findsNothing, reason: '服务在跑时不应还能再启动一次');
  });

  testWidgets('stopped service offers start instead of stop', (tester) async {
    await _pumpOverview(
      tester,
      brightness: Brightness.light,
      serviceRunning: false,
    );

    expect(find.text('启动服务'), findsOneWidget);
    expect(find.text('停止服务'), findsNothing, reason: '服务没跑时没有可停止的对象');
  });

  testWidgets('stop action uses the destructive colour', (tester) async {
    await _pumpOverview(
      tester,
      brightness: Brightness.light,
      serviceRunning: true,
    );

    final scheme = ShadTheme.of(
      tester.element(find.byType(OverviewPage)),
    ).colorScheme;
    final stop = _buttonLabelled(tester, '停止服务');

    expect(stop.foreground, scheme.destructive, reason: '停止会中断正在运行的任务，需要警示色');
  });

  testWidgets('start action keeps the ordinary secondary colour', (
    tester,
  ) async {
    await _pumpOverview(
      tester,
      brightness: Brightness.light,
      serviceRunning: false,
    );

    final scheme = ShadTheme.of(
      tester.element(find.byType(OverviewPage)),
    ).colorScheme;
    final start = _buttonLabelled(tester, '启动服务');
    final refresh = _buttonLabelled(tester, '刷新状态');

    expect(
      start.foreground,
      refresh.foreground,
      reason: '启动是恢复性操作，沿用次级按钮的常规配色',
    );
    expect(start.foreground, isNot(scheme.destructive));
  });

  testWidgets('service actions are hidden without a local deployment', (
    tester,
  ) async {
    await _pumpOverview(
      tester,
      brightness: Brightness.light,
      serviceRunning: true,
      withServiceActions: false,
    );

    expect(find.text('启动服务'), findsNothing);
    expect(find.text('停止服务'), findsNothing);
    expect(find.text('刷新状态'), findsOneWidget);
  });

  for (final (running, label) in [(true, '停止服务'), (false, '启动服务')]) {
    testWidgets('$label keeps its colour while the action is in flight', (
      tester,
    ) async {
      await _pumpOverview(
        tester,
        brightness: Brightness.light,
        serviceRunning: running,
        busy: true,
      );

      final button = _buttonLabelled(tester, label);
      final scheme = ShadTheme.of(
        tester.element(find.byType(OverviewPage)),
      ).colorScheme;

      expect(
        button.foreground,
        running
            ? scheme.destructive
            : _buttonLabelled(tester, '刷新状态').foreground,
        reason: '进行中也应保持各自的配色',
      );
    });
  }
}
