import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nkas_mobile/core/api/api_client.dart';
import 'package:nkas_mobile/core/api/backend_address.dart';
import 'package:nkas_mobile/core/connection/connection_controller.dart';
import 'package:nkas_mobile/core/connection/instance_state_socket.dart';
import 'package:nkas_mobile/core/settings/backend_settings.dart';
import 'package:nkas_mobile/core/settings/entry_key_store.dart';
import 'package:nkas_mobile/core/widgets/toggle.dart';
import 'package:nkas_mobile/core/widgets/surface.dart';
import 'package:nkas_mobile/features/deploy/deploy_page.dart';
import 'package:nkas_mobile/features/deploy/security_entry_actions.dart';
import 'package:nkas_mobile/theme.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

final keyA = 'a' * 43;
final keyB = 'b' * 43;

class MemorySettings implements BackendSettings {
  String? baseUrl;
  @override
  Future<String?> readBaseUrl() async => baseUrl;
  @override
  Future<void> writeBaseUrl(String value) async => baseUrl = value;
}

http.Response json(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
http.Response status({bool enabled = true, bool authorized = true}) => json({
  'api_version': 2,
  'capabilities': {'spa': true, 'security_entry': true},
  'security_entry': {'enabled': enabled, 'authorized': authorized},
});
Map<String, Object?> entry(String? key) => {
  'security_entry': {
    'enabled': key != null,
    'key': key,
    'entry_path': key == null ? null : '/entry/$key',
  },
};

void main() {
  test('full entry splits into a clean IPv6/path base and private key', () {
    final address = BackendAddress.parse(
      ' https://[::1]:12271/base/entry/$keyA/ ',
    );
    expect(address.baseUrl, 'https://[::1]:12271/base');
    expect(address.entryKey, keyA);
    for (final value in [
      'http://user:pass@example.com',
      'https://a/entry/short',
      'https://a/entry/',
      'https://a/entry/$keyA?q=1',
    ]) {
      expect(() => BackendAddress.parse(value), throwsFormatException);
    }
  });

  test(
    'HTTP 200 health is not authorization and manual loopback never reads Termux',
    () async {
      var reads = 0;
      final controller = ConnectionController(
        api: ApiClient(
          client: MockClient((_) async => status(authorized: false)),
        ),
        settings: MemorySettings(),
        localEntryLoader: () async {
          reads++;
          return BackendAddress(defaultBackendBaseUrl, entryKey: keyA);
        },
      );
      addTearDown(controller.dispose);
      expect(
        await controller.connect(defaultBackendBaseUrl, persist: true),
        isFalse,
      );
      expect(reads, 0);
      expect(controller.state.phase, ConnectionPhase.disconnected);
      expect(controller.state.message, contains('安全入口'));
    },
  );

  test(
    'remote entry persists only the base in preferences; headers stay scoped',
    () async {
      final settings = MemorySettings();
      final keys = MemoryEntryKeyStore();
      final observed = <http.Request>[];
      final controller = ConnectionController(
        api: ApiClient(
          client: MockClient((request) async {
            observed.add(request);
            return status();
          }),
        ),
        settings: settings,
        keyStore: keys,
      );
      addTearDown(controller.dispose);
      expect(
        await controller.connect(
          'https://example.test/base/entry/$keyA',
          persist: true,
        ),
        isTrue,
      );
      expect(settings.baseUrl, 'https://example.test/base');
      expect(keys.access!.key, keyA);
      expect(observed.single.headers['Authorization'], 'Bearer $keyA');
      expect(observed.single.followRedirects, isFalse);
      expect(controller.websocketHeaders['Authorization'], 'Bearer $keyA');
      expect(
        controller.headersFor(Uri.parse('https://external.test/banner.png')),
        isEmpty,
      );
      expect(
        controller.headersFor(
          Uri.parse('https://example.test/another-service/image'),
        ),
        isEmpty,
      );
      expect(
        controller.headersFor(Uri.parse('http://example.test/base/image')),
        isEmpty,
      );
      expect(controller.webUiUri.path, '/base/entry/$keyA');
    },
  );

  test(
    'explicit local profile rotates automatically but manual profile cannot reuse local key',
    () async {
      var reads = 0;
      var current = keyA;
      final keys = MemoryEntryKeyStore();
      final headers = <String?>[];
      final controller = ConnectionController(
        api: ApiClient(
          client: MockClient((request) async {
            headers.add(request.headers['Authorization']);
            return status(
              authorized: request.headers['Authorization'] == 'Bearer $current',
            );
          }),
        ),
        settings: MemorySettings(),
        keyStore: keys,
        localEntryLoader: () async {
          reads++;
          return BackendAddress(defaultBackendBaseUrl, entryKey: current);
        },
      );
      addTearDown(controller.dispose);
      expect(await controller.connectLocalDeployment(), isTrue);
      current = keyB;
      expect(await controller.refreshAuthorization(), isTrue);
      expect(controller.websocketHeaders['Authorization'], 'Bearer $keyB');
      final localReads = reads;
      expect(
        await controller.connect(defaultBackendBaseUrl, persist: true),
        isFalse,
      );
      expect(reads, localReads);
      expect(headers.last, isNull);
      expect(keys.access!.localDeployment, isFalse);
    },
  );

  test(
    'enabling and regenerating capture the response key before the next request',
    () async {
      String? current;
      final keys = MemoryEntryKeyStore();
      final controller = ConnectionController(
        api: ApiClient(
          client: MockClient((request) async {
            if (request.url.path == '/api/system/status') {
              return status(enabled: current != null);
            }
            if (request.method == 'PATCH') {
              current = keyA;
              return json({...entry(current), 'value': true});
            }
            expect(request.headers['Authorization'], 'Bearer $current');
            if (request.url.path.endsWith('/regenerate')) current = keyB;
            return json(entry(current));
          }),
        ),
        settings: MemorySettings(),
        keyStore: keys,
      );
      addTearDown(controller.dispose);
      await controller.connect('http://server.test');
      await controller.patchDeploy('SecurityEntryEnabled', true);
      expect(keys.access!.key, keyA);
      final revision = controller.credentialRevision;
      await controller.securityEntry(regenerate: true);
      expect(controller.credentialRevision, greaterThan(revision));
      expect(keys.access!.key, keyB);
      expect(controller.websocketHeaders['Authorization'], 'Bearer $keyB');
      expect(controller.state.phase, ConnectionPhase.connected);
    },
  );

  test(
    'authorization recovery waits until the current entry change is saved',
    () async {
      var current = keyA;
      var healthRequests = 0;
      final rotated = Completer<void>();
      final responseReady = Completer<void>();
      final controller = ConnectionController(
        api: ApiClient(
          client: MockClient((request) async {
            if (request.url.path.endsWith('/regenerate')) {
              current = keyB;
              rotated.complete();
              await responseReady.future;
              return json(entry(current));
            }
            healthRequests++;
            return status(
              authorized: request.headers['Authorization'] == 'Bearer $current',
            );
          }),
        ),
        settings: MemorySettings(),
      );
      addTearDown(controller.dispose);
      await controller.connect('http://server.test/entry/$keyA');
      final change = controller.securityEntry(regenerate: true);
      await rotated.future;
      final recovery = controller.refreshAuthorization();
      await Future<void>.delayed(Duration.zero);
      expect(healthRequests, 1);
      expect(controller.state.phase, ConnectionPhase.connected);
      responseReady.complete();
      await change;
      expect(await recovery, isTrue);
      expect(healthRequests, 2);
      expect(controller.websocketHeaders['Authorization'], 'Bearer $keyB');
      expect(controller.state.phase, ConnectionPhase.connected);
    },
  );

  test(
    'native websocket sends Bearer header without a query credential',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final received = Completer<void>();
      final subscription = server.listen((request) async {
        expect(request.headers.value('authorization'), 'Bearer $keyA');
        expect(request.uri.hasQuery, isFalse);
        final websocket = await WebSocketTransformer.upgrade(request);
        websocket.add(
          jsonEncode({'type': 'state', 'name': 'nkas', 'state': 1}),
        );
      });
      final socket = InstanceStateSocket(
        uri: Uri.parse('ws://127.0.0.1:${server.port}/ws/state'),
        headers: {'Authorization': 'Bearer $keyA'},
      );
      await socket.connect(
        onState: (_) {
          if (!received.isCompleted) received.complete();
        },
      );
      await received.future.timeout(const Duration(seconds: 3));
      await socket.close();
      await subscription.cancel();
      await server.close(force: true);
    },
  );

  testWidgets(
    'schema deployment field enables and rotates inline entry actions in a small dark viewport',
    (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? current;
      var failNextPatch = false;
      final controller = ConnectionController(
        api: ApiClient(
          client: MockClient((request) async {
            if (request.url.path.endsWith('/status')) {
              return status(enabled: false);
            }
            if (request.url.path == '/api/system/deploy' &&
                request.method == 'GET') {
              return json({
                'groups': [
                  {
                    'key': 'Webui',
                    'name': 'Webui',
                    'fields': [
                      {
                        'key': 'SecurityEntryEnabled',
                        'title': 'SecurityEntryEnabled',
                        'help': '来自 deploy 模板的安全入口说明',
                        'widget': 'checkbox',
                        'value': current != null,
                        'default': false,
                      },
                    ],
                  },
                ],
              });
            }
            if (current != null) {
              expect(request.headers['Authorization'], 'Bearer $current');
            }
            if (request.method == 'PATCH') {
              if (failNextPatch) {
                failNextPatch = false;
                return http.Response('{"message":"模拟保存失败"}', 500);
              }
              current = keyA;
            }
            if (request.url.path.endsWith('/regenerate')) current = keyB;
            return json({...entry(current), 'value': current != null});
          }),
        ),
        settings: MemorySettings(),
      );
      addTearDown(controller.dispose);
      await controller.connect('http://server.test');
      await tester.pumpWidget(
        ShadApp(
          theme: nkasThemeData(Brightness.dark),
          builder: (context, child) => ScaffoldMessenger(child: child!),
          home: Scaffold(
            body: DeployPage(
              connectionController: controller,
              accessGranted: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Webui'), findsOneWidget);
      expect(find.text('来自 deploy 模板的安全入口说明'), findsOneWidget);
      expect(find.text('安全入口'), findsNothing);
      expect(find.byType(SecurityEntryActions), findsNothing);
      await tester.tap(find.byType(NkasSwitch));
      await tester.pumpAndSettle();
      expect(current, keyA);
      expect(find.text('复制入口'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byType(SecurityEntryActions),
          matching: find.byType(Surface),
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).obscureText,
        isTrue,
      );
      await tester.tap(find.text('重新生成入口'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      expect(current, keyB);
      expect(controller.state.phase, ConnectionPhase.connected);
      await tester.ensureVisible(find.byType(NkasSwitch));
      await tester.tap(find.byType(NkasSwitch));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(tester.widget<NkasSwitch>(find.byType(NkasSwitch)).value, isTrue);
      expect(current, keyB);
      failNextPatch = true;
      await tester.tap(find.byType(NkasSwitch));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      expect(tester.widget<NkasSwitch>(find.byType(NkasSwitch)).value, isTrue);
      expect(current, keyB);
      expect(find.textContaining('保存失败：'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'deployment without an entry schema field adds no custom card or key request',
    (tester) async {
      final controller = ConnectionController(
        api: ApiClient(
          client: MockClient((request) async {
            if (request.url.path.endsWith('/status')) {
              return status(enabled: false);
            }
            expect(request.url.path, '/api/system/deploy');
            return json({'groups': <Object>[]});
          }),
        ),
        settings: MemorySettings(),
      );
      addTearDown(controller.dispose);
      await controller.connect('http://server.test');
      await tester.pumpWidget(
        ShadApp(
          home: Scaffold(
            body: DeployPage(
              connectionController: controller,
              accessGranted: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NkasSwitch), findsNothing);
      expect(find.byType(SecurityEntryActions), findsNothing);
      expect(find.text('暂无部署配置'), findsOneWidget);
    },
  );
}
