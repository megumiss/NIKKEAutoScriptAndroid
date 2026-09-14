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
import 'package:nkas_mobile/core/settings/entry_key_store.dart';
import 'package:nkas_mobile/features/settings/backend_address_page.dart';
import 'package:nkas_mobile/theme.dart';

class MemorySettings implements BackendSettings {
  String? address;
  @override
  Future<String?> readBaseUrl() async => address;
  @override
  Future<void> writeBaseUrl(String value) async => address = value;
}

http.Response statusResponse() => http.Response(
  jsonEncode({
    'api_version': 2,
    'spa_version': '1',
    'version': 'test',
    'capabilities': {'spa': true},
  }),
  200,
);

Widget host(Widget page) => ShadApp(
  theme: nkasThemeData(Brightness.dark),
  materialThemeBuilder: nkasMaterialTheme,
  home: Scaffold(body: SafeArea(child: page)),
);

void main() {
  testWidgets('failed connection keeps the address and allows a single retry', (
    tester,
  ) async {
    var requests = 0;
    var closed = 0;
    final pending = Completer<http.Response>();
    final settings = MemorySettings();
    final controller = ConnectionController(
      api: ApiClient(
        client: MockClient((request) {
          requests++;
          return requests == 1
              ? pending.future
              : Future.value(statusResponse());
        }),
      ),
      settings: settings,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(
        BackendAddressPage(
          connectionController: controller,
          onClose: () => closed++,
        ),
      ),
    );
    await tester.enterText(
      find.byType(TextField),
      'http://remote.example:12271',
    );
    await tester.pump();
    await tester.tap(find.text('保存并连接'));
    await tester.pump();
    expect(find.text('连接中…'), findsOneWidget);
    await tester.tap(find.text('连接中…'));
    await tester.pump();
    expect(requests, 1);
    pending.complete(http.Response('unavailable', 503));
    await tester.pumpAndSettle();
    expect(closed, 0);
    expect(settings.address, isNull);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'http://remote.example:12271',
    );
    expect(find.text('保存并连接'), findsOneWidget);
    expect(find.text(controller.state.message!), findsOneWidget);
    await tester.tap(find.text('保存并连接'));
    await tester.pump();
    await tester.pump();
    expect(requests, 2);
    expect(closed, 1);
    expect(settings.address, 'http://remote.example:12271');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'saving a complete entry keeps only the root in connection details',
    (tester) async {
      final settings = MemorySettings();
      final keys = MemoryEntryKeyStore();
      final key = List.filled(43, 'a').join();
      var closed = false;
      final controller = ConnectionController(
        api: ApiClient(client: MockClient((request) async => statusResponse())),
        settings: settings,
        keyStore: keys,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        host(
          BackendAddressPage(
            connectionController: controller,
            onClose: () => closed = true,
          ),
        ),
      );
      await tester.enterText(
        find.byType(TextField),
        'https://remote.example/entry/$key',
      );
      await tester.pump();
      await tester.tap(find.text('保存并连接'));
      await tester.pump();
      await tester.pump();
      expect(closed, isTrue);
      expect(settings.address, 'https://remote.example');
      expect((await keys.read())!.key, key);
      expect(
        tester.widget<SelectableText>(find.byType(SelectableText)).data,
        'https://remote.example',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
