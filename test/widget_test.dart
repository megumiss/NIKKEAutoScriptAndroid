// Widget tests for NKAS Mobile.
//
// The 360x800 / 390x844 suites rely on Flutter's debug overflow errors:
// any RenderFlex overflow throws and fails the test, so they act as layout
// regression guards for narrow phones.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nkas_mobile/app/app.dart';
import 'package:nkas_mobile/core/api/api_client.dart';
import 'package:nkas_mobile/core/connection/connection_controller.dart';
import 'package:nkas_mobile/core/settings/backend_settings.dart';
import 'package:nkas_mobile/features/settings/about_page.dart';

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
    if (request.url.path.endsWith('/api/system/deploy/reset')) {
      return http.Response(
        jsonEncode({'status': 'success'}),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }
    if (request.url.path.endsWith('/api/system/deploy')) {
      if (request.method == 'PATCH') {
        final body = jsonDecode(request.body);
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({'status': 'success', 'value': body['value']}),
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'groups': [
              {
                'key': 'Git',
                'name': 'Git',
                'fields': [
                  {
                    'key': 'AutoUpdate',
                    'title': '自动更新',
                    'help': '启动时自动更新 NKAS',
                    'hints': [
                      {'tag': '大多数情况下', 'text': '建议打开'},
                    ],
                    'widget': 'checkbox',
                    'value': true,
                    'default': true,
                    'options': [],
                    'wide': false,
                  },
                  {
                    'key': 'Language',
                    'title': '界面语言',
                    'help': 'Web UI 语言',
                    'hints': [],
                    'widget': 'select',
                    'value': 'zh-CN',
                    'default': 'zh-CN',
                    'options': [
                      {'value': 'zh-CN', 'label': '简体中文'},
                      {'value': 'en-US', 'label': 'English'},
                    ],
                    'wide': false,
                  },
                ],
              },
              {
                'key': 'Webui',
                'name': 'WebUI',
                'fields': [
                  {
                    'key': 'WebuiPort',
                    'title': '监听端口',
                    'help': '--port，监听端口',
                    'hints': [
                      {'tag': '大多数情况下', 'text': '默认 12271'},
                    ],
                    'widget': 'number',
                    'value': 12271,
                    'default': 12271,
                    'options': [],
                    'wide': false,
                  },
                  {
                    'key': 'GitProxy',
                    'title': 'Git 代理',
                    'help': '设置 git 代理',
                    'hints': [],
                    'widget': 'text',
                    'value': '',
                    'default': '',
                    'options': [],
                    'wide': true,
                  },
                ],
              },
            ],
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
          'local': ['abc123', 'tester', '2026-09-10 10:00:00 +0800', 'test'],
          'upstream': ['abc123', 'tester', '2026-09-10 10:00:00 +0800', 'test'],
          'history': [
            ['abc123', 'tester', '2026-09-10 10:00:00 +0800', '修复调度重启问题'],
            ['def456', 'tester', '2026-09-08 09:30:00 +0800', '新增活动日历入口'],
            [null, null, null, null],
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }
    if (request.url.path.endsWith('/screenshot')) {
      return http.Response('{}', 404);
    }
    if (request.url.path.endsWith('/queue')) {
      return http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'running': [
              {'command': 'Harvest', 'name_i18n': '收获', 'next_run': ''},
            ],
            'pending': [
              {
                'command': 'Daily',
                'name_i18n': '每日任务',
                'next_run': '2026-09-12 04:00:00',
              },
            ],
            'waiting': [],
          }),
        ),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
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
    NkasMobileApp(connectionController: controller, enableRealtime: false),
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
  });

  testWidgets('update entry opens the update subpage with history', (
    tester,
  ) async {
    await _pumpTestApp(tester);

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('更新'));
    await tester.pumpAndSettle();

    expect(find.text('源码更新'), findsOneWidget);
    expect(find.text('检查更新'), findsOneWidget);
    expect(find.text('更新记录'), findsOneWidget);
    expect(find.text('修复调度重启问题'), findsOneWidget);
    expect(find.text('新增活动日历入口'), findsOneWidget);
    expect(find.text('当前版本'), findsOneWidget);
    expect(find.text('abc123 · 2026-09-10'), findsOneWidget);

    await tester.tap(find.byTooltip('返回设置'));
    await tester.pumpAndSettle();
    expect(find.text('后端连接'), findsOneWidget);
  });

  testWidgets('about entry opens the about subpage with runtime info', (
    tester,
  ) async {
    await _pumpTestApp(tester);

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.tap(find.text('关于'));
    await tester.pumpAndSettle();

    expect(find.text('NKAS Mobile'), findsOneWidget);
    expect(find.text(appVersion), findsWidgets);
    expect(find.text('NIKKEAutoScript 移动控制端'), findsOneWidget);
    expect(find.text('项目仓库'), findsOneWidget);
    expect(find.text('问题反馈'), findsOneWidget);
    expect(find.text('应用版本'), findsOneWidget);
    expect(find.text('后端版本'), findsOneWidget);
    expect(find.text('后端地址'), findsOneWidget);
    expect(find.text('http://127.0.0.1:12271'), findsOneWidget);
    expect(find.text('API 版本'), findsOneWidget);
    expect(find.text('v2'), findsOneWidget);
    expect(find.text('技术栈'), findsOneWidget);
    expect(find.text('Flutter + shadcn_ui'), findsOneWidget);

    await tester.tap(find.byTooltip('返回设置'));
    await tester.pumpAndSettle();
    expect(find.text('后端连接'), findsOneWidget);
  });

  testWidgets('renders deploy configuration from backend schema', (
    tester,
  ) async {
    await _pumpTestApp(tester);

    for (final label in ['总览', '实例', '任务', '画面', '日志', '设置']) {
      expect(find.byTooltip(label), findsOneWidget);
    }

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('部署'));
    await tester.pumpAndSettle();

    expect(find.text('修改部署配置可能导致更新失败或程序无法启动，修改需要重启后生效，请谨慎操作。'), findsOneWidget);
    expect(find.text('还原默认'), findsOneWidget);
    expect(
      ScaffoldMessenger.maybeOf(tester.element(find.text('还原默认'))),
      isNotNull,
    );
    expect(find.text('Git'), findsOneWidget);
    expect(find.text('WebUI'), findsOneWidget);
    expect(find.text('自动更新'), findsOneWidget);
    expect(find.text('界面语言'), findsOneWidget);
    expect(find.text('监听端口'), findsOneWidget);
    expect(find.text('Git 代理'), findsOneWidget);
    expect(find.text('建议打开'), findsOneWidget);
  });

  testWidgets('renders task configuration from backend schema', (tester) async {
    await _pumpTestApp(tester);

    await tester.tap(find.byTooltip('任务'));
    await tester.pumpAndSettle();

    expect(find.text('NKAS'), findsOneWidget);
    expect(find.text('NKAS设置'), findsOneWidget);
    await tester.tap(find.text('NKAS设置'));
    await tester.pumpAndSettle();
    expect(find.text('客户端设置'), findsOneWidget);
    expect(find.text('客户端平台'), findsOneWidget);
    expect(find.text('自动点击红圈'), findsOneWidget);
    expect(find.byTooltip('返回任务列表'), findsOneWidget);
    expect(find.byTooltip('返回实例'), findsNothing);
  });

  testWidgets('renders real-time logs without prototype rows', (tester) async {
    await _pumpTestApp(tester);

    await tester.tap(find.byTooltip('实例'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('实时日志'));
    await tester.pumpAndSettle();

    // tab 标签 + 面板头部各一处
    expect(find.text('实时日志'), findsWidgets);
    expect(find.text('每日任务：开始执行前哨基地'), findsNothing);
  });

  testWidgets('instances page splits queue groups into horizontal tabs', (
    tester,
  ) async {
    await _pumpTestApp(tester);

    await tester.tap(find.byTooltip('实例'));
    await tester.pumpAndSettle();

    // 详情页横向 tab：三段队列带计数 + 实时日志，无画面卡片
    expect(find.text('查看实例状态、任务队列与实时日志'), findsOneWidget);
    expect(find.text('运行中 1'), findsOneWidget);
    expect(find.text('队列中 1'), findsOneWidget);
    expect(find.text('等待中 0'), findsOneWidget);
    expect(find.text('实时日志'), findsOneWidget);
    expect(find.text('实时画面'), findsNothing);

    // 默认运行中 tab
    expect(find.text('收获'), findsOneWidget);
    expect(find.text('每日任务'), findsNothing);

    await tester.tap(find.text('队列中 1'));
    await tester.pumpAndSettle();
    expect(find.text('每日任务'), findsOneWidget);
    expect(find.text('收获'), findsNothing);

    await tester.tap(find.text('等待中 0'));
    await tester.pumpAndSettle();
    expect(find.text('暂无任务'), findsOneWidget);

    // 队列行点击跳任务页对应配置（'Daily' 不在 schema 中，落在任务配置列表）
    await tester.tap(find.text('队列中 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('每日任务'));
    await tester.pumpAndSettle();
    expect(find.text('任务配置'), findsOneWidget);
    expect(find.text('NKAS设置'), findsOneWidget);

    // 进入任务设置详情：只显示面板的「返回任务列表」，壳层返回键隐藏
    await tester.tap(find.text('NKAS设置'));
    await tester.pumpAndSettle();
    expect(find.text('客户端设置'), findsOneWidget);
    expect(find.byTooltip('返回任务列表'), findsOneWidget);
    expect(find.byTooltip('返回'), findsNothing);

    // 先退回任务列表，壳层返回键恢复，再退回实例页
    await tester.tap(find.byTooltip('返回任务列表'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('返回'), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('查看实例状态、任务队列与实时日志'), findsOneWidget);
  });

  testWidgets('screen page shows the instance bar and empty state', (
    tester,
  ) async {
    await _pumpTestApp(tester);

    await tester.tap(find.byTooltip('画面'));
    await tester.pumpAndSettle();

    expect(find.text('查看实例实时画面，每 2 秒自动刷新'), findsOneWidget);
    expect(find.text('nkas'), findsOneWidget);
    expect(find.text('切换'), findsOneWidget);
    // Mock 后端对 /screenshot 返回 404：无画面帧，显示空态
    expect(find.text('未连接'), findsOneWidget);
    expect(find.text('暂无画面'), findsOneWidget);
    expect(find.text('刷新画面'), findsOneWidget);
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

      testWidgets('instances dashboard and tasks page', (tester) async {
        await pumpAtSize(tester);

        await tester.tap(find.byTooltip('实例'));
        await tester.pumpAndSettle();
        expect(find.text('查看实例状态、任务队列与实时日志'), findsOneWidget);
        expect(find.text('运行中 1'), findsOneWidget);
        await tester.ensureVisible(find.text('实时日志'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('实时日志'));
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('任务'));
        await tester.pumpAndSettle();
        expect(find.text('任务配置'), findsOneWidget);
        await tester.tap(find.text('调度设置'));
        await tester.pumpAndSettle();
        expect(find.text('调度设置'), findsWidgets);
      });

      testWidgets('screen page', (tester) async {
        await pumpAtSize(tester);

        await tester.tap(find.byTooltip('画面'));
        await tester.pumpAndSettle();

        expect(find.text('未连接'), findsOneWidget);
        expect(find.text('暂无画面'), findsOneWidget);
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
