// 概览页按钮行在窄屏下的布局回归。
//
// 本机部署时这一行会同时出现三个按钮（刷新状态 / 启动或停止服务 / 重启服务），
// 而 widget_test.dart 的溢出用例在测试平台上拿不到本机部署分支，覆盖不到
// 三按钮并排的情况，所以在这里单独量。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:nkas_mobile/core/widgets/buttons.dart';
import 'package:nkas_mobile/features/overview/overview_page.dart';
import 'package:nkas_mobile/theme.dart';

Future<void> _pump(
  WidgetTester tester, {
  required Size size,
  required bool serviceRunning,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ShadApp(
      theme: nkasThemeData(Brightness.light),
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
          onStartService: () async {},
          onStopService: () async {},
          onRestartService: () async {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 行内三个服务按钮的矩形；概览页别处也有按钮，所以按文案精确取。
List<Rect> _actionRects(WidgetTester tester, bool running) {
  const labels = ['刷新状态', '启动服务', '停止服务', '重启服务'];
  final wanted = {'刷新状态', running ? '停止服务' : '启动服务', '重启服务'};
  final found = <String, Rect>{};
  for (final button in tester.widgetList<NkasButton>(find.byType(NkasButton))) {
    if (labels.contains(button.label) && wanted.contains(button.label)) {
      found[button.label] = tester.getRect(
        find.byWidgetPredicate(
          (widget) => widget is NkasButton && widget.label == button.label,
        ),
      );
    }
  }
  expect(found.keys.toSet(), wanted, reason: '三个服务按钮都应出现在按钮行里');
  return [for (final label in wanted) found[label]!];
}

void main() {
  for (final size in const [Size(360, 800), Size(390, 844)]) {
    final label = '${size.width.toInt()}x${size.height.toInt()}';
    testWidgets('three service actions fit on one row at $label', (
      tester,
    ) async {
      for (final running in [true, false]) {
        await _pump(tester, size: size, serviceRunning: running);
        expect(
          tester.takeException(),
          isNull,
          reason: 'serviceRunning=$running 时按钮行不能溢出',
        );
        final rects = _actionRects(tester, running);
        for (final rect in rects.skip(1)) {
          expect(rect.top, rects.first.top, reason: '三个按钮必须并排，不能换行');
        }
        // 宽度不能顶到视口边缘，否则轻微的字号或语言差异就会溢出
        final left = rects
            .map((rect) => rect.left)
            .reduce((a, b) => a < b ? a : b);
        final right = rects
            .map((rect) => rect.right)
            .reduce((a, b) => a > b ? a : b);
        expect(right - left, lessThan(size.width), reason: '按钮行总宽必须小于视口宽度');
      }
    });
  }
}
