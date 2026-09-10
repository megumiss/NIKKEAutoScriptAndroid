import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nkas_mobile_preview/core/api/api_client.dart';
import 'package:nkas_mobile_preview/core/connection/connection_controller.dart';
import 'package:nkas_mobile_preview/core/settings/backend_settings.dart';
import 'package:nkas_mobile_preview/core/connection/instance_state_socket.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryBackendSettings implements BackendSettings {
  String? value;

  @override
  Future<String?> readBaseUrl() async => value;

  @override
  Future<void> writeBaseUrl(String value) async => this.value = value;
}

http.Response _statusResponse(int apiVersion) => http.Response(
  jsonEncode({
    'api_version': apiVersion,
    'spa_version': '1',
    'version': 'test',
    'capabilities': {'spa': true, 'websocket': true},
  }),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test('normalizes backend and websocket URLs', () {
    expect(
      ApiClient.normalizeBaseUrl(' 127.0.0.1:12271/ '),
      'http://127.0.0.1:12271',
    );
    final api = ApiClient(client: MockClient((_) async => _statusResponse(2)));
    addTearDown(api.close);
    expect(
      api.websocketUri('https://nkas.example/base/', '/ws/state').toString(),
      'wss://nkas.example/base/ws/state',
    );
    expect(
      () => ApiClient.normalizeBaseUrl('ftp://nkas.example'),
      throwsFormatException,
    );
  });

  test('connects to API v2 and persists the normalized address', () async {
    late Uri requestedUri;
    final settings = _MemoryBackendSettings();
    final controller = ConnectionController(
      api: ApiClient(
        client: MockClient((request) async {
          requestedUri = request.url;
          return _statusResponse(2);
        }),
      ),
      settings: settings,
    );
    addTearDown(controller.dispose);

    final connected = await controller.connect(
      'nkas.example:12271/',
      persist: true,
    );

    expect(connected, isTrue);
    expect(
      requestedUri.toString(),
      'http://nkas.example:12271/api/system/status',
    );
    expect(controller.state.phase, ConnectionPhase.connected);
    expect(settings.value, 'http://nkas.example:12271');
  });

  test('parses the instance list returned by the backend', () async {
    final api = ApiClient(
      client: MockClient(
        (request) async => http.Response.bytes(
          utf8.encode(
            jsonEncode([
              {
                'name': 'nkas',
                'state': 2,
                'mod': 'nkas',
                'next_task': '重启设置',
                'remark': '测试实例',
                'avatar': 'avatar.webp',
              },
            ]),
          ),
          200,
        ),
      ),
    );
    addTearDown(api.close);

    final instances = await api.fetchInstances('http://nkas.example:12271');

    expect(instances, hasLength(1));
    expect(instances.single.name, 'nkas');
    expect(instances.single.detail, '下一任务 · 重启设置');
    expect(instances.single.avatar, 'avatar.webp');
  });

  test('reports incompatible API versions without persisting', () async {
    final settings = _MemoryBackendSettings();
    final controller = ConnectionController(
      api: ApiClient(client: MockClient((_) async => _statusResponse(3))),
      settings: settings,
    );
    addTearDown(controller.dispose);

    final connected = await controller.connect(
      'http://nkas.example',
      persist: true,
    );

    expect(connected, isFalse);
    expect(controller.state.phase, ConnectionPhase.incompatible);
    expect(controller.state.message, contains('API v2'));
    expect(settings.value, isNull);
  });

  test('reports request timeouts', () async {
    final controller = ConnectionController(
      api: ApiClient(
        client: MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          return _statusResponse(2);
        }),
        timeout: const Duration(milliseconds: 1),
      ),
      settings: _MemoryBackendSettings(),
    );
    addTearDown(controller.dispose);

    final connected = await controller.connect('http://nkas.example');

    expect(connected, isFalse);
    expect(controller.state.phase, ConnectionPhase.disconnected);
    expect(controller.state.message, contains('超时'));
  });

  test('persists backend address with shared preferences', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SharedPreferencesBackendSettings();

    await settings.writeBaseUrl('http://nkas.example:12271');

    expect(await settings.readBaseUrl(), 'http://nkas.example:12271');
  });

  test('parses instance state websocket events', () {
    final event = InstanceStateEvent.fromJson({
      'type': 'state',
      'name': 'nkas',
      'state': 1,
    });

    expect(event.name, 'nkas');
    expect(event.state, 1);
    expect(
      () => InstanceStateEvent.fromJson({
        'type': 'queue',
        'name': 'nkas',
        'state': 1,
      }),
      throwsFormatException,
    );
  });

  test('sends start and stop actions for an instance', () async {
    final requests = <String>[];
    final api = ApiClient(
      client: MockClient((request) async {
        requests.add('${request.method} ${request.url.path}');
        return http.Response('{}', 200);
      }),
    );
    addTearDown(api.close);

    await api.setInstanceRunning('http://nkas.example:12271', 'nkas', true);
    await api.setInstanceRunning('http://nkas.example:12271', 'nkas', false);

    expect(requests, ['POST /api/nkas/start', 'POST /api/nkas/stop']);
  });
}
