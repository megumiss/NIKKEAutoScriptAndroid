import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile/core/api/api_client.dart';
import 'package:nkas_mobile/core/connection/connection_controller.dart';
import 'package:nkas_mobile/core/settings/backend_settings.dart';
import 'package:nkas_mobile/features/logs/logs_page.dart';
import 'package:nkas_mobile/theme.dart';

class _MemorySettings implements BackendSettings {
  @override
  Future<String?> readBaseUrl() async => null;

  @override
  Future<void> writeBaseUrl(String value) async {}
}

http.Response _jsonResponse(Object value) => http.Response.bytes(
  utf8.encode(jsonEncode(value)),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

String _message(int batch, int index) =>
    '第 $batch 批日志 $index${'\n详细输出' * (index % 3)}';

http.Response _logResponse(int batch, {int count = 80}) => _jsonResponse({
  'records': [
    for (var index = 0; index < count; index++)
      {
        'time':
            '09:${(index ~/ 60).toString().padLeft(2, '0')}:'
            '${(index % 60).toString().padLeft(2, '0')}',
        'level': 'INFO',
        'rank': 1,
        'source': 'main',
        'text': _message(batch, index),
      },
  ],
  'matched': count,
  'truncated': false,
});

Widget _host(
  ConnectionController controller, {
  Brightness brightness = Brightness.light,
}) => ShadApp(
  theme: nkasThemeData(brightness),
  materialThemeBuilder: nkasMaterialTheme,
  home: Scaffold(body: LogsPage(connectionController: controller)),
);

Future<ConnectionController> _pumpLogs(
  WidgetTester tester, {
  required Future<http.Response> Function(http.Request) query,
}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final controller = ConnectionController(
    api: ApiClient(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/logs/files')) {
          return _jsonResponse({
            'files': [
              {'date': '2026-09-10', 'source': 'main'},
              {'date': '2026-09-10', 'source': 'worker'},
              {'date': '2026-09-09', 'source': 'main'},
            ],
          });
        }
        if (request.url.path.endsWith('/logs')) return query(request);
        return _jsonResponse({
          'api_version': 2,
          'version': 'test',
          'capabilities': {'spa': true},
        });
      }),
    ),
    settings: _MemorySettings(),
  );
  addTearDown(controller.dispose);
  await controller.connect('http://logs.example');
  await tester.pumpWidget(_host(controller));
  await tester.pump();
  return controller;
}

void main() {
  testWidgets('logs open at the last record after an asynchronous load', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    await _pumpLogs(tester, query: (_) => pending.future);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    pending.complete(_logResponse(1));
    await tester.pumpAndSettle();

    expect(find.text(_message(1, 79)).hitTestable(), findsOneWidget);
    expect(find.text(_message(1, 0)).hitTestable(), findsNothing);
    expect(
      tester.getTopLeft(find.text(_message(1, 78))).dy,
      lessThan(tester.getTopLeft(find.text(_message(1, 79))).dy),
    );
  });

  testWidgets('logs preserve browsing until refreshed or filtered', (
    tester,
  ) async {
    var batch = 0;
    final controller = await _pumpLogs(
      tester,
      query: (_) async => _logResponse(++batch),
    );
    await tester.pumpAndSettle();
    expect(find.text(_message(batch, 79)).hitTestable(), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, 350));
    await tester.pumpAndSettle();
    expect(find.text(_message(batch, 79)).hitTestable(), findsNothing);
    await tester.pumpWidget(_host(controller, brightness: Brightness.dark));
    await tester.pumpAndSettle();
    expect(find.text(_message(batch, 79)).hitTestable(), findsNothing);

    await tester.tap(find.byTooltip('刷新日志'));
    await tester.pumpAndSettle();
    expect(batch, 2);
    expect(find.text(_message(batch, 79)).hitTestable(), findsOneWidget);

    for (final filter in [
      ('日志类型', 'worker'),
      ('日志日期', '2026-09-09'),
      ('日志级别', 'ERROR'),
    ]) {
      await tester.drag(find.byType(ListView), const Offset(0, 350));
      await tester.pumpAndSettle();
      expect(find.text(_message(batch, 79)).hitTestable(), findsNothing);
      await tester.tap(find.byTooltip(filter.$1));
      await tester.pumpAndSettle();
      await tester.tap(find.text(filter.$2).last);
      await tester.pumpAndSettle();
      expect(find.text(_message(batch, 79)).hitTestable(), findsOneWidget);
    }
    expect(batch, 5);
    expect(tester.takeException(), isNull);
  });

  testWidgets('logs start at the end when an empty result gains records', (
    tester,
  ) async {
    var batch = 0;
    await _pumpLogs(
      tester,
      query: (_) async => _logResponse(++batch, count: batch == 1 ? 0 : 80),
    );
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的日志'), findsOneWidget);
    await tester.tap(find.byTooltip('刷新日志'));
    await tester.pumpAndSettle();
    expect(find.text(_message(2, 79)).hitTestable(), findsOneWidget);
    expect(find.text(_message(2, 0)).hitTestable(), findsNothing);
  });
}
