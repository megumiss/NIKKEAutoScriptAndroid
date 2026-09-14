import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile/core/api/api_client.dart';
import 'package:nkas_mobile/core/connection/connection_controller.dart';
import 'package:nkas_mobile/core/settings/backend_settings.dart';
import 'package:nkas_mobile/core/widgets/field_select.dart';
import 'package:nkas_mobile/features/deploy/deploy_page.dart';
import 'package:nkas_mobile/theme.dart';

class MemorySettings implements BackendSettings {
  @override
  Future<String?> readBaseUrl() async => null;
  @override
  Future<void> writeBaseUrl(String value) async {}
}

const options = [
  {'value': 'a', 'label': '主账号'},
  {'value': 'b', 'label': '名称较长的第二个实例'},
  {'value': 'c', 'label': '第三个实例'},
];

Future<void> pumpDeploy(
  WidgetTester tester,
  List<Map<String, dynamic>> changes,
) async {
  http.Response response(Object value) => http.Response(
    jsonEncode(value),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
  final controller = ConnectionController(
    settings: MemorySettings(),
    api: ApiClient(
      client: MockClient((request) async {
        if (request.method == 'PATCH' || request.method == 'POST') {
          final change = jsonDecode(request.body) as Map<String, dynamic>;
          changes.add(change);
          return response({'value': change['value']});
        }
        if (request.url.path == '/api/system/deploy') {
          return response({
            'groups': [
              {
                'key': 'instances',
                'name': '实例启动',
                'fields': [
                  {
                    'key': 'priority',
                    'title': '执行顺序',
                    'widget': 'priority',
                    'value': 'a > b',
                    'options': options,
                  },
                  {
                    'key': 'startup',
                    'title': '启动实例',
                    'widget': 'multiselect',
                    'value': ['a'],
                    'options': options,
                  },
                ],
              },
            ],
          });
        }
        return response({
          'api_version': 2,
          'version': 'test',
          'capabilities': {},
        });
      }),
    ),
  );
  addTearDown(controller.dispose);
  await controller.connect('http://backend.example');
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ShadApp(
      theme: nkasThemeData(Brightness.light),
      materialThemeBuilder: nkasMaterialTheme,
      builder: (context, child) => ScaffoldMessenger(child: child!),
      home: Scaffold(
        body: DeployPage(connectionController: controller, accessGranted: true),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder select(String label) => find.byWidgetPredicate(
  (widget) => widget is FieldSelect && widget.label == label,
);

void main() {
  testWidgets(
    'priority reordering, removal and addition preserve backend tokens',
    (tester) async {
      final changes = <Map<String, dynamic>>[];
      await pumpDeploy(tester, changes);
      await tester.tap(find.byTooltip('后移').first);
      await tester.pumpAndSettle();
      expect(changes.last, {'key': 'priority', 'value': 'b > a'});
      await tester.tap(find.byTooltip('移除').first);
      await tester.pumpAndSettle();
      expect(changes.last, {'key': 'priority', 'value': 'a'});
      await tester.ensureVisible(select('添加实例'));
      await tester.tap(select('添加实例'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('第三个实例'));
      await tester.pumpAndSettle();
      expect(changes.last, {'key': 'priority', 'value': 'a > c'});
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('deployment multi-select submits the chosen option values', (
    tester,
  ) async {
    final changes = <Map<String, dynamic>>[];
    await pumpDeploy(tester, changes);
    await tester.ensureVisible(select('启动实例'));
    await tester.tap(select('启动实例'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('第三个实例'),
      ),
    );
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(changes.single, {
      'key': 'startup',
      'value': ['a', 'c'],
    });
  });

  testWidgets('reset dialog uses the selected template', (tester) async {
    final changes = <Map<String, dynamic>>[];
    await pumpDeploy(tester, changes);
    await tester.tap(find.text('还原默认'));
    await tester.pumpAndSettle();
    await tester.tap(select('部署模板'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Docker（大陆）'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('还原'));
    await tester.pumpAndSettle();
    expect(changes.single, {'template': 'docker-cn'});
    expect(tester.takeException(), isNull);
  });
}
