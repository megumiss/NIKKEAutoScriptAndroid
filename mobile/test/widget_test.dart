// Widget tests for the NKAS mobile preview.
//
// The 360x800 / 390x844 suites rely on Flutter's debug overflow errors:
// any RenderFlex overflow throws and fails the test, so they act as layout
// regression guards for narrow phones.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nkas_mobile_preview/app/app.dart';
import 'package:nkas_mobile_preview/core/api/api_client.dart';
import 'package:nkas_mobile_preview/core/connection/connection_controller.dart';
import 'package:nkas_mobile_preview/core/settings/backend_settings.dart';

class _MemoryBackendSettings implements BackendSettings {
  String? value;

  @override
  Future<String?> readBaseUrl() async => value;

  @override
  Future<void> writeBaseUrl(String value) async => this.value = value;
}

Map<String, dynamic> _schemaFixture() => {
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
                {'value': 'adb', 'label': 'ADB'},
              ],
            },
            {
              'key': 'NKAS.Optimization.AutoRedCircle',
              'title': '自动点击红圈',
              'widget': 'checkbox',
              'value': true,
              'readonly': false,
            },
          ],
        },
      ],
    },
  },
};

ConnectionController _connectedController({_MemoryBackendSettings? settings}) {
  final client = MockClient((request) async {
    if (request.url.path.endsWith('/api/instances')) {
      return http.Response.bytes(
        utf8.encode(
          jsonEncode([
            {
              'name': 'nkas',
              'state': 2,
              'mod': 'nkas',
              'next_task': '重启设置',
              'remark': '测试实例',
            },
            {'name': 'nkas2', 'state': 1, 'mod': 'nkas', 'current_task': '收获'},
          ]),
        ),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }
    if (request.url.path.endsWith('/api/calendar')) {
      return http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'updated_at': 1770000000,
            'items': [
              {
                'id': 'event-1',
                'category': 'version_event',
                'title': '测试活动',
                'subtitle': '活动说明',
                'start_time': 1769000000,
                'end_time': 1773000000,
                'subtype': 'pass',
                'banner_url': '',
              },
            ],
          }),
        ),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }
    if (request.url.path.endsWith('/schema')) {
      return http.Response.bytes(
        utf8.encode(jsonEncode(_schemaFixture())),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }
    if (request.url.path.endsWith('/config') && request.method == 'PATCH') {
      return http.Response('{}', 200);
    }
    if (request.url.path.endsWith('/api/system/logs/files')) {
      return http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'files': [
              {'date': '2026-09-10', 'source': '主账号'},
              {'date': '2026-09-10', 'source': '小号'},
            ],
          }),
        ),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }
    if (request.url.path.endsWith('/api/system/logs')) {
      return http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'records': [
              {
                'time': '09:24:42',
                'level': 'INFO',
                'rank': 1,
                'source': '主账号',
                'text': '读取任务配置并加入调度队列',
              },
              {
                'time': '09:23:42',
                'level': 'WARNING',
                'rank': 2,
                'source': '服务',
                'text': '等待游戏窗口响应，稍后重试',
              },
            ],
            'matched': 2,
            'truncated': false,
          }),
        ),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }
    if (request.url.path.endsWith('/api/system/update')) {
      return http.Response(
        jsonEncode({
          'state': 0,
          'error': null,
          'local': ['abc123', 'tester', '2026-09-10', 'test'],
          'upstream': ['abc123', 'tester', '2026-09-10', 'test'],
          'history': [],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }
    if (request.url.path.endsWith('/screenshot')) {
      return http.Response('{}', 404);
    }
    if (request.url.path.endsWith('/schedule')) {
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
    return http.Response(
      jsonEncode({
        'api_version': 2,
        'spa_version': '1',
        'version': 'test',
        'capabilities': {'spa': true, 'websocket': true},
      }),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });
  return ConnectionController(
    api: ApiClient(client: client),
    settings: settings ?? _MemoryBackendSettings(),
  );
}

Future<ConnectionController> _pumpTestApp(
  WidgetTester tester, {
  _MemoryBackendSettings? settings,
}) async {
  final controller = _connectedController(settings: settings);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    NkasPreviewApp(connectionController: controller, enableRealtime: false),
  );
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  testWidgets('renders the mobile overview', (tester) async {
    await _pumpTestApp(tester);

    expect(find.text('快速查看本机服务与实例状态'), findsOneWidget);
    expect(find.text('服务运行正常'), findsOneWidget);
    expect(find.text('实例状态'), findsOneWidget);
  });

  testWidgets('settings keeps the mobile control entry points', (tester) async {
    await _pumpTestApp(tester);

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();

    expect(find.text('验证与初始化'), findsOneWidget);
    expect(find.text('STAR 验证'), findsOneWidget);
    expect(find.text('初始化 NKAS'), findsOneWidget);
    expect(find.text('后端地址'), findsOneWidget);
    expect(find.text('原始 WebUI'), findsOneWidget);
    expect(find.text('更新'), findsOneWidget);
    expect(find.text('当前 test · 已是最新'), findsOneWidget);

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
    await tester.pumpAndSettle();

    expect(find.text('关于'), findsOneWidget);
    expect(find.text('部署'), findsNothing);
  });

  testWidgets('renders task configuration from backend schema', (tester) async {
    await _pumpTestApp(tester);

    await tester.tap(find.byTooltip('实例'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('任务配置'));
    await tester.pumpAndSettle();

    expect(find.text('客户端设置'), findsOneWidget);
    expect(find.text('客户端平台'), findsOneWidget);
    expect(find.text('自动点击红圈'), findsOneWidget);
    expect(find.text('日常'), findsNothing);
  });

  testWidgets('backend address is tested and persisted from settings', (
    tester,
  ) async {
    final settings = _MemoryBackendSettings();
    await _pumpTestApp(tester, settings: settings);

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('后端地址'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'localhost:12271/');
    await tester.tap(find.text('保存并连接'));
    await tester.pumpAndSettle();

    expect(settings.value, 'http://localhost:12271');
    expect(find.text('http://localhost:12271'), findsOneWidget);
    expect(find.text('已连接'), findsOneWidget);
  });

  const sizes = {'360x800': Size(360, 800), '390x844': Size(390, 844)};

  for (final entry in sizes.entries) {
    group('no overflow at ${entry.key}', () {
      Future<void> pumpAtSize(WidgetTester tester) async {
        tester.view.physicalSize = entry.value;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await _pumpTestApp(tester);
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
        expect(find.text('共 2 条'), findsOneWidget);
        expect(find.text('读取任务配置并加入调度队列'), findsOneWidget);
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
