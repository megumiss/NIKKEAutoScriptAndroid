import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile/core/platform/nkas_platform.dart';
import 'package:nkas_mobile/core/widgets/floating_action.dart';
import 'package:nkas_mobile/features/settings/init_config_page.dart';
import 'package:nkas_mobile/theme.dart';

/// 初始化配置页的输入框在键盘弹起后必须保持焦点：
/// NkasKeyboardGuard 会在键盘开关时切换布局分支（Stack ↔ Column），
/// 若 content 的 Element 被重建，正在编辑的输入框会丢焦点、键盘立刻回落。
class _InitPlatform extends NkasPlatform {
  _InitPlatform() : super.testing(events: const Stream.empty());

  @override
  Future<InitConfig?> initConfig() async => const InitConfig(
    webUiUrl: 'http://127.0.0.1:12271',
    repository: 'cn',
    aptSource: 'tuna',
    dockerImage: 'docker.1ms.run/megumiss/nkas:latest',
    repositorySources: [
      InitConfigSource(label: '国内镜像', value: 'cn'),
      InitConfigSource(label: 'GitHub', value: 'gh'),
    ],
    aptSources: [
      InitConfigSource(label: '清华源', value: 'tuna'),
      InitConfigSource(label: '官方源', value: 'official'),
    ],
  );

  @override
  Future<void> saveInitConfig({
    String? webUiUrl,
    String? repository,
    String? aptSource,
    String? dockerImage,
  }) async {}
}

Future<void> _mount(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ShadApp(
      theme: nkasThemeData(Brightness.light),
      materialThemeBuilder: nkasMaterialTheme,
      home: Scaffold(body: InitConfigPage(platform: _InitPlatform())),
    ),
  );
  await tester.pumpAndSettle();
}

FocusNode _focusNodeOf(WidgetTester tester, Finder field) => tester
    .widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    )
    .focusNode;

/// 模拟输入法弹起：物理尺寸不变、viewInsets 变高
Future<void> _openKeyboard(WidgetTester tester) async {
  tester.view.viewInsets = const FakeViewPadding(bottom: 300);
  await tester.pumpAndSettle();
}

Future<void> _closeKeyboard(WidgetTester tester) async {
  tester.view.viewInsets = FakeViewPadding.zero;
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('keyboard open keeps the editing field focused', (tester) async {
    await _mount(tester);
    await tester.scrollUntilVisible(
      find.text('Docker 镜像'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    final field = find.byType(TextFormField).last;
    await tester.tap(field);
    await tester.pumpAndSettle();
    final node = _focusNodeOf(tester, field);
    expect(node.hasFocus, isTrue, reason: '点击后输入框应获得焦点');

    // 键盘弹起触发 NkasKeyboardGuard 切换布局分支，Element 必须被复用
    await _openKeyboard(tester);
    expect(_focusNodeOf(tester, field), same(node), reason: '键盘弹起后输入框不应被重建');
    expect(node.hasFocus, isTrue, reason: '键盘弹起后输入框应保持焦点');
    expect(tester.takeException(), isNull);

    // 收起键盘恢复悬浮分支，同样要保持同一个 Element 与焦点
    await _closeKeyboard(tester);
    expect(_focusNodeOf(tester, field), same(node), reason: '键盘收起后输入框不应被重建');
    expect(node.hasFocus, isTrue, reason: '键盘收起后输入框应保持焦点');
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard open pins the action button below the list', (
    tester,
  ) async {
    await _mount(tester);
    await _openKeyboard(tester);
    // 键盘打开时内容区变矮，按钮固定在列表下方而不是悬浮在内容之上
    final action = find.byType(NkasFloatingAction);
    expect(action, findsOneWidget);
    expect(
      tester.getBottomLeft(action).dy,
      lessThanOrEqualTo(tester.view.physicalSize.height / 1.0 + 1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('typing then opening the keyboard keeps the text', (
    tester,
  ) async {
    await _mount(tester);
    await tester.scrollUntilVisible(
      find.text('Docker 镜像'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    final field = find.byType(TextFormField).last;
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.enterText(field, 'docker.example.com/nkas:latest');
    await tester.pumpAndSettle();
    await _openKeyboard(tester);

    final editable = tester.widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    );
    expect(editable.controller.text, 'docker.example.com/nkas:latest');
    expect(editable.focusNode.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });
}
