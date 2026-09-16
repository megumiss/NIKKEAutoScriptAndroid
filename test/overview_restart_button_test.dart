// 概览页「重启服务」按钮的配色回归。
//
// 重启会中断正在运行的任务，所以它与旁边的「刷新状态」用不同的配色区分。
// 断言渲染层实际拿到的颜色，而不是只看 SecondaryButton 的参数：传进去的色值
// 与最终画出来的可能被其它层改写。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:nkas_mobile/core/widgets/buttons.dart';
import 'package:nkas_mobile/features/overview/overview_page.dart';
import 'package:nkas_mobile/theme.dart';

Future<void> _pumpOverview(
  WidgetTester tester, {
  required Brightness brightness,
  Future<void> Function()? onRestartService,
  bool restarting = false,
}) async {
  await tester.pumpWidget(
    ShadApp(
      theme: nkasThemeData(brightness),
      home: Scaffold(
        body: OverviewPage(
          serviceRunning: true,
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
          onRestartService: onRestartService,
          restartingService: restarting,
        ),
      ),
    ),
  );
  // 进行中会显示无限循环的进度指示，pumpAndSettle 永远不会收敛。
  if (restarting) {
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
  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets(
      'restart action uses the destructive colour in ${brightness.name} theme',
      (tester) async {
        await _pumpOverview(
          tester,
          brightness: brightness,
          onRestartService: () async {},
        );

        final scheme = ShadTheme.of(
          tester.element(find.byType(OverviewPage)),
        ).colorScheme;
        final restart = _buttonLabelled(tester, '重启服务');
        final refresh = _buttonLabelled(tester, '刷新状态');

        expect(
          restart.foreground,
          scheme.destructive,
          reason: '重启服务必须用警示色，与刷新状态区分',
        );
        expect(
          restart.foreground,
          isNot(refresh.foreground),
          reason: '两个按钮不能同色',
        );
      },
    );
  }

  testWidgets('restart action is hidden without a local service', (
    tester,
  ) async {
    await _pumpOverview(tester, brightness: Brightness.light);

    expect(
      find.text('重启服务'),
      findsNothing,
      reason: 'onRestartService 为 null 时不显示重启按钮',
    );
    expect(find.text('刷新状态'), findsOneWidget);
  });

  testWidgets('restart action keeps the destructive colour while restarting', (
    tester,
  ) async {
    await _pumpOverview(
      tester,
      brightness: Brightness.light,
      onRestartService: () async {},
      restarting: true,
    );

    final restart = _buttonLabelled(tester, '重启服务');
    expect(
      restart.foreground,
      ShadTheme.of(
        tester.element(find.byType(OverviewPage)),
      ).colorScheme.destructive,
      reason: '进行中也应保持警示色',
    );
  });
}
