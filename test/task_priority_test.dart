import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile/core/api/api_client.dart';
import 'package:nkas_mobile/core/widgets/field_select.dart';
import 'package:nkas_mobile/features/instances/schema_panel.dart';
import 'package:nkas_mobile/theme.dart';

const priorityKey = 'Shop.GeneralShop.priority';
const priorityOptions = [
  {'value': 'GRATIS', 'label': '免费商品'},
  {'value': 'CORE_DUST_CASE', 'label': '较长名称的核心尘盒奖励'},
  {'value': 'ORNAMENT', 'label': '好感度礼物'},
];

http.Response response(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Future<void> pumpTaskPriority(
  WidgetTester tester,
  List<Map<String, dynamic>> changes, {
  String? initialValue = ' ORNAMENT  > GRATIS ',
  List<Map<String, String>> options = priorityOptions,
  bool readonly = false,
  Completer<http.Response>? firstPatch,
  Brightness brightness = Brightness.light,
  double scale = 1,
}) async {
  var value = initialValue;
  final api = ApiClient(
    client: MockClient((request) async {
      if (request.method == 'PATCH') {
        expect(request.url.path, '/api/nkas/config');
        final change = jsonDecode(request.body) as Map<String, dynamic>;
        changes.add(change);
        if (changes.length == 1 && firstPatch != null) {
          final result = await firstPatch.future;
          if (result.statusCode != 200) return result;
        }
        value = change['value'] as String;
        return response({'status': 'success'});
      }
      expect(request.url.path, '/api/nkas/schema');
      return response({
        'menus': [],
        'tasks': {
          'Shop': {
            'name': '商店',
            'groups': [
              {
                'key': 'GeneralShop',
                'name': '普通商店',
                'fields': [
                  {
                    'key': priorityKey,
                    'title': '购买优先级',
                    'help': '可多选并排序，按从上到下的顺序执行。',
                    'widget': 'priority',
                    'value': value,
                    'readonly': readonly,
                    'options': options,
                  },
                ],
              },
            ],
          },
        },
      });
    }),
  );
  addTearDown(api.close);
  final schema = ValueNotifier(
    await api.fetchSchema('http://backend.example', 'nkas'),
  );
  addTearDown(schema.dispose);
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ShadApp(
      theme: nkasThemeData(brightness),
      materialThemeBuilder: nkasMaterialTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: ScaffoldMessenger(child: child!),
      ),
      home: Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              ValueListenableBuilder(
                valueListenable: schema,
                builder: (context, value, _) => SchemaPanel(
                  schema: value,
                  loading: false,
                  error: null,
                  initialTaskKey: 'Shop',
                  onTaskKeyChanged: (_) {},
                  onReload: () async {
                    schema.value = await api.fetchSchema(
                      'http://backend.example',
                      'nkas',
                    );
                  },
                  onPatch: (key, value) => api.patchConfig(
                    'http://backend.example',
                    'nkas',
                    key,
                    value,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder get addPicker => find.byWidgetPredicate(
  (widget) => widget is FieldSelect && widget.label == '添加选项',
);

void main() {
  testWidgets('task priority preserves order and tokens through edits', (
    tester,
  ) async {
    final changes = <Map<String, dynamic>>[];
    await pumpTaskPriority(tester, changes, scale: 1.4);
    expect(find.text('该字段请通过原始 WebUI 操作'), findsNothing);
    expect(find.text('好感度礼物'), findsOneWidget);
    expect(find.text('免费商品'), findsOneWidget);

    await tester.tap(find.byTooltip('前移').first);
    await tester.tap(find.byTooltip('后移').last);
    expect(changes, isEmpty);
    await tester.tap(find.byTooltip('后移').first);
    await tester.pumpAndSettle();
    expect(changes.last, {'key': priorityKey, 'value': 'GRATIS > ORNAMENT'});
    await tester.tap(find.byTooltip('前移').last);
    await tester.pumpAndSettle();
    expect(changes.last['value'], 'ORNAMENT > GRATIS');
    await tester.tap(find.byTooltip('移除').first);
    await tester.pumpAndSettle();
    expect(changes.last['value'], 'GRATIS');

    await tester.ensureVisible(addPicker);
    await tester.tap(addPicker);
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<PopupMenuItem<String>>(find.byType(PopupMenuItem<String>))
          .map((item) => item.value),
      ['CORE_DUST_CASE', 'ORNAMENT'],
    );
    await tester.tap(find.text('较长名称的核心尘盒奖励'));
    await tester.pumpAndSettle();
    expect(changes.last['value'], 'GRATIS > CORE_DUST_CASE');
    await tester.tap(find.byTooltip('移除').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('移除').first);
    await tester.pumpAndSettle();
    expect(changes.last, {'key': priorityKey, 'value': ''});
    expect(find.byTooltip('移除'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('task priority disables pending edits and retries failures', (
    tester,
  ) async {
    final changes = <Map<String, dynamic>>[];
    final pending = Completer<http.Response>();
    await pumpTaskPriority(
      tester,
      changes,
      initialValue: 'GRATIS > LEGACY_ITEM',
      firstPatch: pending,
      brightness: Brightness.dark,
      scale: 1.6,
    );
    expect(find.text('LEGACY_ITEM'), findsOneWidget);
    await tester.tap(find.byTooltip('后移').first);
    await tester.pumpAndSettle();
    expect(changes, [
      {'key': priorityKey, 'value': 'LEGACY_ITEM > GRATIS'},
    ]);
    await tester.tap(find.byTooltip('移除').first);
    await tester.ensureVisible(addPicker);
    await tester.tap(addPicker);
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuItem<String>), findsNothing);
    expect(changes, hasLength(1));

    pending.complete(response({'message': 'temporarily unavailable'}, 503));
    await tester.pumpAndSettle();
    expect(find.textContaining('保存失败'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('免费商品')).dy,
      lessThan(tester.getTopLeft(find.text('LEGACY_ITEM')).dy),
    );
    await tester.ensureVisible(find.byTooltip('后移').first);
    await tester.tap(find.byTooltip('后移').first);
    await tester.pumpAndSettle();
    expect(changes, hasLength(2));
    expect(changes.last['value'], 'LEGACY_ITEM > GRATIS');
    expect(
      tester.getTopLeft(find.text('LEGACY_ITEM')).dy,
      lessThan(tester.getTopLeft(find.text('免费商品')).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('readonly task priority prevents selection and reordering', (
    tester,
  ) async {
    final changes = <Map<String, dynamic>>[];
    await pumpTaskPriority(tester, changes, readonly: true);
    await tester.tap(find.byTooltip('后移').first);
    await tester.tap(find.byTooltip('移除').first);
    await tester.tap(addPicker);
    await tester.pumpAndSettle();
    expect(changes, isEmpty);
    expect(find.byType(PopupMenuItem<String>), findsNothing);
    expect(find.text('好感度礼物'), findsOneWidget);
  });

  testWidgets('empty task priority shows its empty state', (tester) async {
    final changes = <Map<String, dynamic>>[];
    await pumpTaskPriority(tester, changes, initialValue: null, options: []);
    expect(find.text('暂无可选项'), findsOneWidget);
    expect(addPicker, findsNothing);
    expect(find.text('该字段请通过原始 WebUI 操作'), findsNothing);
    expect(changes, isEmpty);
  });
}
