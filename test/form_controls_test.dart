import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile/core/api/instance_info.dart';
import 'package:nkas_mobile/core/api/schedule_info.dart';
import 'package:nkas_mobile/core/widgets/buttons.dart';
import 'package:nkas_mobile/core/widgets/config_input.dart';
import 'package:nkas_mobile/core/widgets/field_select.dart';
import 'package:nkas_mobile/core/widgets/floating_action.dart';
import 'package:nkas_mobile/core/widgets/form_field.dart';
import 'package:nkas_mobile/core/widgets/instance_select.dart';
import 'package:nkas_mobile/core/widgets/multi_select.dart';
import 'package:nkas_mobile/core/widgets/toggle.dart';
import 'package:nkas_mobile/features/instances/schedule_panel.dart';
import 'package:nkas_mobile/theme.dart';

Widget host(
  Widget child, {
  Brightness brightness = Brightness.light,
  double scale = 1,
}) => ShadApp(
  theme: nkasThemeData(brightness),
  materialThemeBuilder: nkasMaterialTheme,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: child,
    ),
  ),
);

void main() {
  testWidgets(
    'ordinary inputs request normal keyboards and secrets stay private',
    (tester) async {
      const fields = [
        NkasTextField(label: '节点名称'),
        NkasTextField(label: '后端地址', keyboardType: TextInputType.url),
        NkasTextField(label: '备注', maxLines: 3),
        NkasTextField(label: '次数', keyboardType: TextInputType.number),
        NkasTextField(
          label: 'AuthKey',
          obscureText: true,
          enableSuggestions: false,
        ),
      ];
      await tester.pumpWidget(host(const Column(children: fields)));
      for (final field in fields) {
        final input = find.descendant(
          of: find.byWidgetPredicate(
            (widget) => widget is NkasTextField && widget.label == field.label,
          ),
          matching: find.byType(TextField),
        );
        await tester.ensureVisible(input);
        await tester.showKeyboard(input);
        final config = tester.testTextInput.setClientArgs!;
        final secret = field.label == 'AuthKey';
        expect(config['obscureText'], secret);
        expect(config['enableSuggestions'], !secret);
        expect(config['autocorrect'], isFalse);
        expect(
          (config['inputType'] as Map)['name'],
          {
            '节点名称': 'TextInputType.text',
            '后端地址': 'TextInputType.url',
            '备注': 'TextInputType.multiline',
            '次数': 'TextInputType.number',
            'AuthKey': 'TextInputType.text',
          }[field.label],
        );
      }
    },
  );

  testWidgets('numeric input rejects invalid values and submits only once', (
    tester,
  ) async {
    final submitted = <String>[];
    final response = Completer<bool>();
    await tester.pumpWidget(
      host(
        NkasConfigInput(
          label: '数字配置',
          initialValue: '10',
          number: true,
          onSubmit: (value) {
            submitted.add(value);
            return response.future;
          },
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '12.3.4');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(submitted, isEmpty);
    expect(find.text('请输入有效数字'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '-12.5');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.tap(find.byTooltip('保存数字配置'), warnIfMissed: false);
    await tester.pump();
    expect(submitted, ['-12.5']);
    response.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('请输入有效数字'), findsNothing);
  });

  testWidgets('failed config save retains the draft for retry', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      host(
        NkasConfigInput(
          label: '代理地址',
          initialValue: 'old',
          onSubmit: (value) async => ++attempts > 1,
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'new');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('保存代理地址'));
    await tester.pumpAndSettle();
    expect(find.text('保存失败，请重试'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'new',
    );
    await tester.tap(find.byTooltip('保存代理地址'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('保存失败，请重试'), findsNothing);
  });

  testWidgets('multiline input keeps newlines until explicitly saved', (
    tester,
  ) async {
    final submitted = <String>[];
    await tester.pumpWidget(
      host(
        NkasConfigInput(
          label: '任务文本',
          initialValue: '',
          multiline: true,
          fullWidthSaveButton: true,
          onSubmit: (value) async {
            submitted.add(value);
            return true;
          },
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '第一行\n第二行');
    await tester.pumpAndSettle();
    expect(submitted, isEmpty);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(submitted, ['第一行\n第二行']);
  });

  testWidgets(
    'select returns the option key and disabled select stays closed',
    (tester) async {
      String? selected;
      await tester.pumpWidget(
        host(
          Column(
            children: [
              FieldSelect(
                label: '语言',
                compact: true,
                value: '简体中文',
                selectedValue: 'zh-CN',
                options: const [
                  FieldSelectOption('zh-CN', '简体中文'),
                  FieldSelectOption('en-US', 'English'),
                ],
                onChanged: (value) => selected = value,
              ),
              const SizedBox(height: 12),
              const FieldSelect(
                label: '禁用选择',
                value: '已锁定',
                options: [FieldSelectOption('locked', '已锁定')],
              ),
            ],
          ),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      expect(selected, 'en-US');
      await tester.tap(find.text('已锁定'));
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuItem<String>), findsNothing);
    },
  );

  testWidgets('instance dropdown keeps empty and failed lists inactive', (
    tester,
  ) async {
    for (final (loading, error, label) in [
      (true, null, '加载中…'),
      (false, null, '暂无实例'),
      (false, 'offline', '实例加载失败'),
    ]) {
      await tester.pumpWidget(
        host(
          InstanceSelect(
            instances: const [],
            selected: '',
            selectedInstance: null,
            loading: loading,
            error: error,
            avatarUrl: (_) => null,
            onSelect: (_) =>
                fail('An unavailable instance must not be selected'),
          ),
        ),
      );
      expect(find.text(label), findsOneWidget);
      await tester.tap(find.byIcon(LucideIcons.chevronDown));
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuItem<String>), findsNothing);
    }
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'instance dropdown scrolls, selects and cancels at large text in $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final instances = [
          for (var index = 0; index < 30; index++)
            InstanceInfo(name: '日常任务实例 $index', state: index % 4, mod: 'nkas'),
        ];
        var current = instances.first;
        var changes = 0;
        await tester.pumpWidget(
          host(
            StatefulBuilder(
              builder: (context, setState) => InstanceSelect(
                instances: instances,
                selected: current.name,
                selectedInstance: current,
                loading: false,
                error: null,
                avatarUrl: (_) => null,
                onSelect: (value) => setState(() {
                  current = instances.firstWhere((item) => item.name == value);
                  changes++;
                }),
              ),
            ),
            brightness: brightness,
            scale: 1.6,
          ),
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.byType(PopupMenuItem<String>), findsNWidgets(30));
        expect(
          tester.getTopLeft(find.byType(PopupMenuItem<String>).first).dy,
          greaterThanOrEqualTo(
            tester.getBottomLeft(find.byType(InstanceSelect)).dy,
          ),
        );
        // 选中当前项只收起下拉，不重复加载实例。
        await tester.tap(find.text(current.name).last);
        await tester.pumpAndSettle();
        expect(changes, 0);

        await tester.tap(find.byIcon(LucideIcons.chevronDown));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text(instances.last.name));
        await tester.pumpAndSettle();
        await tester.tap(find.text(instances.last.name));
        await tester.pumpAndSettle();
        expect(current, instances.last);
        expect(changes, 1);
        expect(find.byType(PopupMenuItem<String>), findsNothing);
        expect(find.text(current.name), findsOneWidget);

        await tester.tap(find.byIcon(LucideIcons.chevronDown));
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(changes, 1);
        expect(find.byType(PopupMenuItem<String>), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'multi-select scrolls and confirms at large text in $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        Set<String>? result;
        await tester.pumpWidget(
          host(
            Builder(
              builder: (context) => TextButton(
                child: const Text('选择实例'),
                onPressed: () async => result = await showNkasMultiSelect(
                  context: context,
                  title: '选择实例',
                  selected: {'0'},
                  options: [
                    for (var index = 0; index < 30; index++)
                      FieldSelectOption('$index', '实例 $index'),
                  ],
                ),
              ),
            ),
            brightness: brightness,
            scale: 1.6,
          ),
        );
        await tester.tap(find.text('选择实例'));
        await tester.pumpAndSettle();
        expect(find.text('完成').hitTestable(), findsOneWidget);
        await tester.ensureVisible(find.text('实例 29'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('实例 29'));
        await tester.tap(find.text('完成'));
        await tester.pumpAndSettle();
        expect(result, {'0', '29'});
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('switch supports keyboard activation with a full touch target', (
    tester,
  ) async {
    var value = false;
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) => NkasSwitch(
            label: '自动滚动',
            value: value,
            onChanged: (next) => setState(() => value = next),
          ),
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(value, isTrue);
    expect(tester.getSize(find.byType(NkasSwitch)), const Size(48, 48));
  });

  testWidgets('monthly schedule validates the day and saves the edited value', (
    tester,
  ) async {
    List<Map<String, dynamic>>? saved;
    await tester.pumpWidget(
      host(
        SchedulePanel(
          loadSchedule: () async => [
            ScheduleTask.fromJson({
              'command': 'Daily',
              'name_i18n': '每日任务',
              'enabled': true,
              'cadence': 'monthly',
            }),
          ],
          saveSchedule: (value) async => saved = value,
          resetSchedule: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    final day = find.descendant(
      of: find.byKey(const ValueKey('Daily-monthly-day')),
      matching: find.byType(TextField),
    );
    await tester.enterText(day, '32');
    await tester.tap(find.text('保存调度设置'));
    await tester.pumpAndSettle();
    expect(saved, isNull);
    expect(find.text('请输入 1–31 之间的日期'), findsOneWidget);
    await tester.enterText(day, '15');
    await tester.tap(find.text('保存调度设置'));
    await tester.pumpAndSettle();
    expect(saved!.single['monthly_day'], '15');
  });

  // 底部悬浮按钮压在滚动内容之上，半透明背景会让列表文字透出来，看起来像故障。
  // 次级按钮配色（.np-secondary）本就是给卡片内行内按钮用的半透明底，这里必须
  // 合成成不透明色，两个主题都要检查。
  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('floating action is fully opaque in ${brightness.name} theme', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          NkasFloatingAction(
            label: '开始安装',
            icon: LucideIcons.download,
            enabled: false,
            onPressed: () {},
          ),
          brightness: brightness,
        ),
      );
      await tester.pumpAndSettle();

      final button = tester.widget<NkasButton>(find.byType(NkasButton));
      expect(button.background.a, 1, reason: '禁用态悬浮按钮必须使用不透明背景');
      // Ink 决定实际绘制出的底色，兜住「传了不透明色但渲染层又叠了透明度」
      final ink = tester.widget<Ink>(find.byType(Ink).first);
      final decoration = ink.decoration! as BoxDecoration;
      expect(decoration.color!.a, 1, reason: '绘制出的背景必须不透明');
    });
  }
}
