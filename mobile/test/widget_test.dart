// Widget tests for the NKAS mobile preview.
//
// The 360x800 / 390x844 suites rely on Flutter's debug overflow errors:
// any RenderFlex overflow throws and fails the test, so they act as layout
// regression guards for narrow phones.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nkas_mobile_preview/app/app.dart';

void main() {
  testWidgets('renders the mobile overview', (tester) async {
    await tester.pumpWidget(const NkasPreviewApp());
    await tester.pumpAndSettle();

    expect(find.text('快速查看本机服务与实例状态'), findsOneWidget);
    expect(find.text('服务运行正常'), findsOneWidget);
    expect(find.text('实例状态'), findsOneWidget);
  });

  testWidgets('settings keeps the mobile control entry points', (tester) async {
    await tester.pumpWidget(const NkasPreviewApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();

    expect(find.text('验证与初始化'), findsOneWidget);
    expect(find.text('STAR 验证'), findsOneWidget);
    expect(find.text('初始化 NKAS'), findsOneWidget);
    expect(find.text('后端地址'), findsOneWidget);
    expect(find.text('原始 WebUI'), findsOneWidget);
    expect(find.text('更新'), findsOneWidget);

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
    await tester.pumpAndSettle();

    expect(find.text('关于'), findsOneWidget);
    expect(find.text('部署'), findsNothing);
  });

  const sizes = {'360x800': Size(360, 800), '390x844': Size(390, 844)};

  for (final entry in sizes.entries) {
    group('no overflow at ${entry.key}', () {
      Future<void> pumpAtSize(WidgetTester tester) async {
        tester.view.physicalSize = entry.value;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(const NkasPreviewApp());
        await tester.pumpAndSettle();
      }

      testWidgets('overview page', (tester) async {
        await pumpAtSize(tester);

        expect(find.text('总览'), findsWidgets);
        expect(find.text('服务运行正常'), findsOneWidget);
        expect(find.text('活动日历'), findsOneWidget);
      });

      testWidgets('instances page, every tab', (tester) async {
        await pumpAtSize(tester);

        await tester.tap(find.byTooltip('实例'));
        await tester.pumpAndSettle();
        expect(find.text('切换实例并管理任务、调度和画面'), findsOneWidget);

        for (final tab in ['任务配置', '调度设置', '实时日志', '画面', '概览']) {
          await tester.ensureVisible(find.text(tab));
          await tester.pumpAndSettle();
          await tester.tap(find.text(tab));
          await tester.pumpAndSettle();
        }
        expect(find.text('暂无画面'), findsNothing);
        expect(find.text('概览'), findsOneWidget);
      });

      testWidgets('logs page', (tester) async {
        await pumpAtSize(tester);

        await tester.tap(find.byTooltip('日志'));
        await tester.pumpAndSettle();

        expect(find.text('查看 log 目录下的日志文件'), findsOneWidget);
        expect(find.text('日志文件'), findsOneWidget);
        expect(find.text('31 条记录'), findsOneWidget);
      });

      testWidgets('settings page', (tester) async {
        await pumpAtSize(tester);

        await tester.tap(find.byTooltip('设置'));
        await tester.pumpAndSettle();

        expect(find.text('连接、验证与外观设置'), findsOneWidget);
        expect(find.text('后端连接'), findsOneWidget);

        await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
        await tester.pumpAndSettle();
        expect(find.text('关于'), findsOneWidget);
      });
    });
  }
}
