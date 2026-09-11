import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nkas_mobile/core/api/api_client.dart';
import 'package:nkas_mobile/core/connection/connection_controller.dart';
import 'package:nkas_mobile/core/settings/backend_settings.dart';
import 'package:nkas_mobile/core/connection/instance_state_socket.dart';
import 'package:nkas_mobile/core/connection/instance_queue_socket.dart';
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

  test('builds the original WebUI URL from the active backend', () async {
    final controller = ConnectionController(
      api: ApiClient(client: MockClient((_) async => _statusResponse(2))),
      settings: _MemoryBackendSettings(),
    );
    addTearDown(controller.dispose);
    await controller.connect('https://nkas.example/base');

    expect(controller.webUiUri.toString(), 'https://nkas.example/base/app/');
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

  test('encodes instance names in action and queue URLs', () async {
    final requests = <Uri>[];
    final api = ApiClient(
      client: MockClient((request) async {
        requests.add(request.url);
        if (request.url.path.endsWith('/queue')) {
          return http.Response('{}', 200);
        }
        return http.Response('{}', 200);
      }),
    );
    addTearDown(api.close);

    await api.setInstanceRunning('http://nkas.example:12271', '主账号/测试', true);
    await api.fetchQueue('http://nkas.example:12271', '主账号/测试');

    expect(requests.map((uri) => uri.toString()), [
      'http://nkas.example:12271/api/%E4%B8%BB%E8%B4%A6%E5%8F%B7%2F%E6%B5%8B%E8%AF%95/start',
      'http://nkas.example:12271/api/%E4%B8%BB%E8%B4%A6%E5%8F%B7%2F%E6%B5%8B%E8%AF%95/queue',
    ]);
  });

  test('parses queue snapshots and queue websocket events', () async {
    final api = ApiClient(
      client: MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'running': [
                {'command': 'daily', 'next_run': 'now', 'name_i18n': '日常'},
              ],
              'pending': [],
              'waiting': [],
            }),
          ),
          200,
        ),
      ),
    );
    addTearDown(api.close);
    final queue = await api.fetchQueue('http://nkas.example:12271', 'nkas');
    expect(queue.running.single.name, '日常');

    final event = InstanceQueueEvent.fromJson({
      'type': 'queue',
      'name': 'nkas',
      'running': [],
      'pending': [],
      'waiting': [],
    });
    expect(event.name, 'nkas');
    expect(event.queue.waiting, isEmpty);
  });

  test('parses activity calendar data', () async {
    late Uri requestedUri;
    final api = ApiClient(
      client: MockClient((request) async {
        requestedUri = request.url;
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'updated_at': 1770000000,
              'cached': false,
              'language': 'zh-CN',
              'items': [
                {
                  'id': 'event-1',
                  'category': 'version_event',
                  'title': '测试活动',
                  'subtitle': '活动说明',
                  'start_time': 1769000000,
                  'end_time': 1773000000,
                  'subtype': 'pass',
                  'banner_url': 'https://example.com/banner.webp',
                },
              ],
            }),
          ),
          200,
        );
      }),
    );
    addTearDown(api.close);

    final calendar = await api.fetchCalendar(
      'http://nkas.example:12271',
      refresh: true,
    );

    expect(
      requestedUri.toString(),
      'http://nkas.example:12271/api/calendar?language=zh-CN&refresh=1',
    );
    expect(calendar.updatedAt, 1770000000);
    expect(calendar.items, hasLength(1));
    expect(calendar.items.single.title, '测试活动');
    expect(calendar.items.single.subtype, 'pass');
  });

  test('loads and queries historical logs', () async {
    final requestedUris = <Uri>[];
    final api = ApiClient(
      client: MockClient((request) async {
        requestedUris.add(request.url);
        if (request.url.path.endsWith('/files')) {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'files': [
                  {'date': '2026-09-10', 'source': '主账号'},
                ],
              }),
            ),
            200,
          );
        }
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'records': [
                {
                  'time': '09:24:42',
                  'level': 'ERROR',
                  'rank': 3,
                  'source': '主账号',
                  'text': '任务执行失败',
                  'traceback': 'RuntimeError: failed',
                  'traceback_collapsed': 'Traceback details',
                },
              ],
              'matched': 3,
              'truncated': true,
            }),
          ),
          200,
        );
      }),
    );
    addTearDown(api.close);

    final files = await api.fetchLogFiles('http://nkas.example:12271');
    final logs = await api.fetchLogs(
      'http://nkas.example:12271',
      date: '2026-09-10',
      source: '主账号',
      level: 'warn',
    );
    final download = api.logDownloadUri(
      'http://nkas.example:12271',
      date: '2026-09-10',
      source: '主账号',
    );

    expect(files.single.source, '主账号');
    expect(logs.matched, 3);
    expect(logs.truncated, isTrue);
    expect(logs.records.single.traceback, 'RuntimeError: failed');
    expect(requestedUris.last.queryParameters, {
      'date': '2026-09-10',
      'source': '主账号',
      'level': 'warn',
      'limit': '500',
    });
    expect(
      download.toString(),
      'http://nkas.example:12271/api/system/logs/download?date=2026-09-10&source=%E4%B8%BB%E8%B4%A6%E5%8F%B7',
    );
  });

  test('reads, checks, and applies source updates', () async {
    final requests = <String>[];
    final api = ApiClient(
      client: MockClient((request) async {
        requests.add('${request.method} ${request.url.path}');
        if (request.method == 'GET') {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'state': 1,
                'error': null,
                'local': ['abc123', 'tester', '2026-09-10', 'local'],
                'upstream': ['def456', 'tester', '2026-09-11', 'upstream'],
                'history': [],
              }),
            ),
            200,
          );
        }
        return http.Response('{}', 200);
      }),
    );
    addTearDown(api.close);

    final info = await api.fetchUpdateInfo('http://nkas.example:12271');
    await api.checkForUpdate('http://nkas.example:12271');
    await api.applyUpdate('http://nkas.example:12271');

    expect(info.available, isTrue);
    expect(info.stateLabel, '有新版本');
    expect(info.local?.first, 'abc123');
    expect(requests, [
      'GET /api/system/update',
      'POST /api/update/check',
      'POST /api/update',
    ]);
  });

  test('loads screenshot bytes and capture time', () async {
    final api = ApiClient(
      client: MockClient(
        (_) async => http.Response.bytes(
          [0xff, 0xd8, 0xff, 0xd9],
          200,
          headers: {
            'content-type': 'image/jpeg',
            'x-captured-at': '1770000000.25',
          },
        ),
      ),
    );
    addTearDown(api.close);

    final frame = await api.fetchScreenshot('http://nkas.example:12271', '主账号');

    expect(frame?.bytes, [0xff, 0xd8, 0xff, 0xd9]);
    expect(frame?.capturedAt, 1770000000.25);
  });

  test('treats a missing screenshot as an empty preview', () async {
    final api = ApiClient(
      client: MockClient((_) async => http.Response('{}', 404)),
    );
    addTearDown(api.close);

    expect(
      await api.fetchScreenshot('http://nkas.example:12271', 'nkas'),
      isNull,
    );
  });

  test('loads and saves instance schedules', () async {
    final requests = <http.Request>[];
    final api = ApiClient(
      client: MockClient((request) async {
        requests.add(request);
        if (request.method == 'GET') {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'status': 'success',
                'tasks': [
                  {
                    'command': 'Daily',
                    'name_i18n': '每日任务',
                    'enabled': true,
                    'locked': false,
                    'enable_locked': false,
                    'cadence': 'daily',
                    'cadence_locked': false,
                    'next_run': '2026-09-12 04:00:00',
                    'daily_times': '04:00',
                    'weekly_days': '2',
                    'weekly_time': '04:00',
                    'monthly_day': '1',
                    'monthly_time': '04:00',
                  },
                ],
              }),
            ),
            200,
          );
        }
        return http.Response('{}', 200);
      }),
    );
    addTearDown(api.close);

    final tasks = await api.fetchSchedule('http://nkas.example:12271', 'nkas');
    await api.saveSchedule('http://nkas.example:12271', 'nkas', [
      {'command': 'Daily', 'enable': false, 'cadence': 'daily'},
    ]);
    await api.resetSchedule('http://nkas.example:12271', 'nkas');

    expect(tasks.single.name, '每日任务');
    expect(tasks.single.activeTime, '04:00');
    expect(requests.map((request) => '${request.method} ${request.url.path}'), [
      'GET /api/nkas/schedule',
      'POST /api/nkas/schedule/save',
      'POST /api/nkas/schedule/reset',
    ]);
    expect(jsonDecode(requests[1].body), {
      'changes': [
        {'command': 'Daily', 'enable': false, 'cadence': 'daily'},
      ],
    });
  });

  test('loads task configuration schema', () async {
    final api = ApiClient(
      client: MockClient(
        (request) async => http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'menus': [
                {
                  'key': 'NKAS',
                  'name': 'NKAS',
                  'tasks': [
                    {'key': 'NKAS', 'name': 'NKAS设置', 'help': ''},
                  ],
                },
              ],
              'tasks': {
                'NKAS': {
                  'name': 'NKAS设置',
                  'help': '',
                  'groups': [
                    {
                      'key': 'Client',
                      'name': '客户端设置',
                      'help': '',
                      'fields': [
                        {
                          'key': 'NKAS.Client.Platform',
                          'title': '客户端平台',
                          'widget': 'select',
                          'value': 'win',
                          'readonly': false,
                          'options': [
                            {'value': 'win', 'label': 'Windows'},
                          ],
                        },
                      ],
                    },
                  ],
                },
              },
            }),
          ),
          200,
        ),
      ),
    );
    addTearDown(api.close);

    final schema = await api.fetchSchema('http://nkas.example:12271', 'nkas');

    expect(schema.menus.single.tasks.single.name, 'NKAS设置');
    expect(schema.tasks['NKAS']!.groups.single.fields.single.title, '客户端平台');
    expect(
      schema.tasks['NKAS']!.groups.single.fields.single.options.single.label,
      'Windows',
    );
  });

  test('patches one task configuration field', () async {
    late http.Request request;
    final api = ApiClient(
      client: MockClient((value) async {
        request = value;
        return http.Response('{}', 200);
      }),
    );
    addTearDown(api.close);

    await api.patchConfig(
      'http://nkas.example:12271',
      'nkas',
      'NKAS.Client.Platform',
      'adb',
    );

    expect(request.method, 'PATCH');
    expect(request.url.path, '/api/nkas/config');
    expect(jsonDecode(request.body), {
      'key': 'NKAS.Client.Platform',
      'value': 'adb',
    });
  });
}
