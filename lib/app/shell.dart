import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:nkas_mobile/core/api/instance_info.dart';
import 'package:nkas_mobile/core/connection/connection_controller.dart';
import 'package:nkas_mobile/core/connection/instance_state_socket.dart';
import 'package:nkas_mobile/core/connection/instance_queue_socket.dart';
import 'package:nkas_mobile/core/api/queue_info.dart';
import 'package:nkas_mobile/core/api/calendar_info.dart';
import 'package:nkas_mobile/core/api/schema_info.dart';
import 'package:nkas_mobile/core/platform/nkas_platform.dart';
import 'package:nkas_mobile/core/platform/runtime_platform.dart';
import 'package:nkas_mobile/core/widgets/buttons.dart';
import 'package:nkas_mobile/core/widgets/status.dart';
import 'package:nkas_mobile/features/instances/instances_page.dart';
import 'package:nkas_mobile/features/tasks/tasks_page.dart';
import 'package:nkas_mobile/features/screen/screen_page.dart';
import 'package:nkas_mobile/features/logs/logs_page.dart';
import 'package:nkas_mobile/features/deploy/deploy_page.dart';
import 'package:nkas_mobile/features/overview/overview_page.dart';
import 'package:nkas_mobile/features/settings/settings_page.dart';
import 'package:nkas_mobile/features/settings/backend_address_page.dart';
import 'package:nkas_mobile/features/settings/setup_page.dart';
import 'package:nkas_mobile/features/settings/native_control_page.dart';
import 'package:nkas_mobile/features/settings/star_verify_page.dart';
import 'package:nkas_mobile/features/settings/about_page.dart';
import 'package:nkas_mobile/features/settings/update_page.dart';
import 'package:nkas_mobile/theme.dart';

enum NkasPage { overview, instances, tasks, screen, logs, settings }

class NkasShell extends StatefulWidget {
  const NkasShell({
    required this.themeMode,
    required this.connectionController,
    required this.enableRealtime,
    required this.onThemeModeChanged,
    super.key,
  });

  final ThemeMode themeMode;
  final ConnectionController connectionController;
  final bool enableRealtime;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  @override
  State<NkasShell> createState() => _NkasShellState();
}

class _NkasShellState extends State<NkasShell> {
  // 预览工程支持 ?page=overview|instances|tasks|screen|logs|settings 指定初始页，便于逐页截图验收
  NkasPage page = kIsWeb
      ? NkasPage.values.asNameMap()[Uri.base.queryParameters['page']] ??
            NkasPage.overview
      : NkasPage.overview;
  late final List<NkasPage> pageStack = [page];
  String instance = '主账号';
  bool notifications = true;
  final instanceStates = <String, bool>{
    '主账号': true,
    '小号': false,
    '测试账号': false,
  };
  StarAuthorization star = const StarAuthorization(authorized: false);
  StreamSubscription<NkasPlatformEvent>? starSubscription;
  List<InstanceInfo> instances = const [];
  bool loadingInstances = false;
  bool togglingInstance = false;
  String? instancesError;
  String? loadedInstancesBaseUrl;
  InstanceStateSocket? stateSocket;
  String? stateSocketBaseUrl;
  Timer? stateSocketReconnectTimer;
  final queues = <String, QueueInfo>{};
  bool loadingQueue = false;
  String? queueError;
  InstanceQueueSocket? queueSocket;
  String? queueSocketInstance;
  Timer? queueSocketReconnectTimer;
  List<CalendarItem> calendarItems = const [];
  int calendarUpdatedAt = 0;
  bool loadingCalendar = false;
  String? calendarError;
  String? calendarBaseUrl;
  SchemaInfo? schema;
  bool loadingSchema = false;
  String? schemaError;
  String? taskKey;

  /// 切页滑动方向：1 从右进入（前进/向右切换），-1 从左进入（返回/向左切换）
  double _navDirection = 1;
  static const _rootPages = [
    NkasPage.overview,
    NkasPage.instances,
    NkasPage.tasks,
    NkasPage.screen,
    NkasPage.logs,
    NkasPage.settings,
  ];

  @override
  void initState() {
    super.initState();
    widget.connectionController.addListener(_connectionChanged);
    unawaited(_loadStar());
    if (NkasPlatform.instance.supported) {
      starSubscription = NkasPlatform.instance.events.listen((event) {
        if (event case StarAuthorizationEvent(:final status)) {
          _applyStarStatus(status);
        }
      });
    }
    _connectionChanged();
  }

  @override
  void didUpdateWidget(covariant NkasShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connectionController != widget.connectionController) {
      oldWidget.connectionController.removeListener(_connectionChanged);
      widget.connectionController.addListener(_connectionChanged);
    }
  }

  @override
  void dispose() {
    widget.connectionController.removeListener(_connectionChanged);
    unawaited(starSubscription?.cancel());
    unawaited(_closeStateSocket());
    unawaited(_closeQueueSocket());
    super.dispose();
  }

  Future<void> _loadStar() async {
    final status = await NkasPlatform.instance.starStatus();
    if (mounted) _applyStarStatus(status);
  }

  void _applyStarStatus(StarAuthorization status) {
    if (!mounted) return;
    setState(() => star = status);
    _connectionChanged();
  }

  bool get _starAccessGranted =>
      kIsWeb || (!isAndroid && !isIOS) || star.authorized;

  int _socketCredentialRevision = -1;

  void _connectionChanged() {
    if (!mounted) return;
    final connection = widget.connectionController.state;
    final accessGranted = _starAccessGranted;
    final connected = connection.phase == ConnectionPhase.connected;
    if (_socketCredentialRevision !=
        widget.connectionController.credentialRevision) {
      _socketCredentialRevision =
          widget.connectionController.credentialRevision;
      stateSocketBaseUrl = null;
      if (connected && queueSocketInstance != null) {
        unawaited(_openQueueSocket(queueSocketInstance!));
      }
    }
    setState(() {
      if (!accessGranted || !connected) {
        instances = const [];
        instancesError = null;
        loadedInstancesBaseUrl = null;
        stateSocketBaseUrl = null;
        queues.clear();
        queueError = null;
        queueSocketInstance = null;
        calendarItems = const [];
        calendarUpdatedAt = 0;
        calendarError = null;
        calendarBaseUrl = null;
        schema = null;
        schemaError = null;
      }
    });
    if (accessGranted &&
        connected &&
        loadedInstancesBaseUrl != connection.baseUrl &&
        !loadingInstances) {
      unawaited(_loadInstances());
    }
    if (accessGranted &&
        connected &&
        calendarBaseUrl != connection.baseUrl &&
        !loadingCalendar) {
      unawaited(_loadCalendar());
    }
    if (accessGranted &&
        widget.enableRealtime &&
        connected &&
        stateSocketBaseUrl != connection.baseUrl) {
      unawaited(_openStateSocket(connection.baseUrl));
    } else if (!accessGranted || !widget.enableRealtime || !connected) {
      unawaited(_closeStateSocket());
    }
    if (!accessGranted || !connected) unawaited(_closeQueueSocket());
  }

  Future<void> _openStateSocket(String baseUrl) async {
    stateSocketReconnectTimer?.cancel();
    await _closeStateSocket();
    final connection = widget.connectionController.state;
    if (!mounted ||
        !_starAccessGranted ||
        connection.phase != ConnectionPhase.connected ||
        connection.baseUrl != baseUrl) {
      return;
    }
    final socket = InstanceStateSocket(
      uri: widget.connectionController.websocketUri('/ws/state'),
      headers: widget.connectionController.websocketHeaders,
      onDisconnected: () =>
          unawaited(widget.connectionController.refreshAuthorization()),
    );
    stateSocket = socket;
    stateSocketBaseUrl = baseUrl;
    await socket.connect(
      onState: _applyStateEvent,
      onError: (_) => _scheduleStateSocketReconnect(socket, baseUrl),
      onClosed: () => _scheduleStateSocketReconnect(socket, baseUrl),
    );
  }

  void _scheduleStateSocketReconnect(
    InstanceStateSocket socket,
    String baseUrl,
  ) {
    if (!mounted ||
        stateSocket != socket ||
        !_starAccessGranted ||
        widget.connectionController.state.phase != ConnectionPhase.connected ||
        widget.connectionController.state.baseUrl != baseUrl) {
      return;
    }
    stateSocketReconnectTimer?.cancel();
    stateSocketReconnectTimer = Timer(
      const Duration(seconds: 3),
      () => unawaited(_openStateSocket(baseUrl)),
    );
  }

  void _applyStateEvent(InstanceStateEvent event) {
    if (!mounted || !_starAccessGranted) return;
    final index = instances.indexWhere((item) => item.name == event.name);
    if (index < 0) return;
    setState(() {
      instances = [
        ...instances.sublist(0, index),
        instances[index].copyWith(state: event.state),
        ...instances.sublist(index + 1),
      ];
      instanceStates[event.name] = event.state == 1;
    });
  }

  Future<void> _closeStateSocket() async {
    stateSocketReconnectTimer?.cancel();
    stateSocketReconnectTimer = null;
    final socket = stateSocket;
    stateSocket = null;
    stateSocketBaseUrl = null;
    await socket?.close();
  }

  Future<void> _loadInstances() async {
    final baseUrl = widget.connectionController.state.baseUrl;
    setState(() {
      loadingInstances = true;
      instancesError = null;
    });
    try {
      final result = await widget.connectionController.fetchInstances();
      if (!mounted ||
          !_starAccessGranted ||
          widget.connectionController.state.baseUrl != baseUrl) {
        return;
      }
      setState(() {
        instances = result;
        loadedInstancesBaseUrl = baseUrl;
        if (result.isNotEmpty && !result.any((item) => item.name == instance)) {
          instance = result.first.name;
        }
        for (final item in result) {
          instanceStates.putIfAbsent(item.name, () => item.isRunning);
        }
      });
      if (result.isNotEmpty) {
        unawaited(
          _loadQueue(result.firstWhere((item) => item.name == instance).name),
        );
      }
    } catch (error) {
      if (!mounted || !_starAccessGranted) return;
      setState(() {
        instances = const [];
        instancesError = error.toString();
        loadedInstancesBaseUrl = baseUrl;
      });
    } finally {
      if (mounted) setState(() => loadingInstances = false);
    }
  }

  InstanceInfo? get selectedInstance {
    for (final item in instances) {
      if (item.name == instance) return item;
    }
    return null;
  }

  String? _avatarUrl(InstanceInfo item) {
    if (item.avatar.isEmpty) return null;
    return widget.connectionController.avatarUri(item.avatar).toString();
  }

  Future<void> _loadQueue(String name) async {
    if (!_starAccessGranted) return;
    setState(() {
      loadingQueue = true;
      queueError = null;
    });
    try {
      final result = await widget.connectionController.fetchQueue(name);
      if (!mounted || !_starAccessGranted) return;
      setState(() => queues[name] = result);
      unawaited(_openQueueSocket(name));
    } catch (error) {
      if (!mounted || !_starAccessGranted) return;
      setState(() => queueError = error.toString());
    } finally {
      if (mounted) setState(() => loadingQueue = false);
    }
  }

  Future<void> _loadCalendar({bool refresh = false}) async {
    if (!_starAccessGranted) return;
    setState(() {
      loadingCalendar = true;
      if (refresh) calendarError = null;
    });
    try {
      final result = await widget.connectionController.fetchCalendar(
        refresh: refresh,
      );
      if (!mounted || !_starAccessGranted) return;
      setState(() {
        calendarItems = result.items;
        calendarUpdatedAt = result.updatedAt;
        calendarBaseUrl = widget.connectionController.state.baseUrl;
        calendarError = null;
      });
    } catch (error) {
      if (!mounted || !_starAccessGranted) return;
      setState(() => calendarError = error.toString());
    } finally {
      if (mounted) setState(() => loadingCalendar = false);
    }
  }

  Future<void> _openQueueSocket(String name) async {
    queueSocketReconnectTimer?.cancel();
    await _closeQueueSocket();
    final connection = widget.connectionController.state;
    if (!mounted ||
        !_starAccessGranted ||
        connection.phase != ConnectionPhase.connected) {
      return;
    }
    final socket = InstanceQueueSocket(
      headers: widget.connectionController.websocketHeaders,
      onDisconnected: () =>
          unawaited(widget.connectionController.refreshAuthorization()),
      uri: widget.connectionController.websocketUri(
        '/ws/${Uri.encodeComponent(name)}/queue',
      ),
    );
    queueSocket = socket;
    queueSocketInstance = name;
    await socket.connect(
      onQueue: (event) {
        if (!mounted || !_starAccessGranted) return;
        setState(() => queues[event.name] = event.queue);
      },
      onError: (_) => _scheduleQueueSocketReconnect(socket, name),
      onClosed: () => _scheduleQueueSocketReconnect(socket, name),
    );
  }

  void _scheduleQueueSocketReconnect(InstanceQueueSocket socket, String name) {
    if (!mounted ||
        queueSocket != socket ||
        queueSocketInstance != name ||
        !_starAccessGranted ||
        widget.connectionController.state.phase != ConnectionPhase.connected) {
      return;
    }
    queueSocketReconnectTimer?.cancel();
    queueSocketReconnectTimer = Timer(
      const Duration(seconds: 3),
      () => unawaited(_openQueueSocket(name)),
    );
  }

  Future<void> _closeQueueSocket() async {
    queueSocketReconnectTimer?.cancel();
    queueSocketReconnectTimer = null;
    final socket = queueSocket;
    queueSocket = null;
    queueSocketInstance = null;
    await socket?.close();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return PopScope<void>(
      canPop: _canPopSystemRoute,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        backgroundColor: theme.colorScheme.background,
        body: Center(
          child: LayoutBuilder(
            builder: (context, constraints) => SizedBox(
              // 内容区随窗口走，宽窗口放宽到 480（桌面浏览器预览不至于拉成一条），
              // 窄窗口/真机全幅
              width: constraints.maxWidth.clamp(0, 480),
              height: constraints.maxHeight,
              child: SafeArea(
                child: Column(
                  children: [
                    _AppHeader(
                      title: _pageTitle,
                      connection: widget.connectionController.state,
                      showBack: !_canPopSystemRoute && !_taskDetailOpen,
                      backTooltip: '返回',
                      onBack: _handleBack,
                      crumb: _taskDetailOpen ? _taskDetailName : null,
                      onCrumbRootTap: _taskDetailOpen ? _handleBack : null,
                    ),
                    // 底部导航悬浮在内容之上（原型 .np-nav：bottom 14 + 阴影 + 毛玻璃），
                    // 各页面底部预留 88 避让区
                    Expanded(
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeOutCubic,
                              transitionBuilder: (child, animation) => ClipRect(
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: Offset(_navDirection, 0),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: FadeTransition(
                                    opacity: animation,
                                    child: child,
                                  ),
                                ),
                              ),
                              layoutBuilder: (current, previous) => Stack(
                                fit: StackFit.expand,
                                children: [...previous, ?current],
                              ),
                              child: KeyedSubtree(
                                key: ValueKey(page),
                                child: _pageBody(),
                              ),
                            ),
                          ),
                          // 未通过 STAR 验证时，设置以外的页面盖遮罩，
                          // 底部导航保持可用，可经遮罩按钮或导航前往验证页
                          if (!_starAccessGranted && page != NkasPage.settings)
                            Positioned.fill(
                              child: _StarGateOverlay(
                                onVerify: () => _pushSubPage(
                                  'STAR 验证',
                                  StarVerifyPage(
                                    onOpenSetup: () => unawaited(_openSetup()),
                                  ),
                                ),
                              ),
                            ),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 14,
                            child: _BottomNav(
                              page: page,
                              onSelect: _selectRootPage,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool get _canPopSystemRoute =>
      page == NkasPage.overview && pageStack.length == 1;

  /// 任务页展开任务详情时由壳层面包屑（任务 / 任务名）接管返回，隐藏壳层返回键
  bool get _taskDetailOpen => page == NkasPage.tasks && taskKey != null;

  /// 面包屑末级显示的任务名；schema 未加载时回退为任务 key
  String get _taskDetailName => schema?.tasks[taskKey]?.name ?? taskKey ?? '';

  bool _handleBack() {
    _navDirection = -1;
    if (_taskDetailOpen) {
      setState(() => taskKey = null);
      return true;
    }
    if (pageStack.length > 1) {
      setState(() {
        pageStack.removeLast();
        page = pageStack.last;
      });
      return true;
    }
    if (page != NkasPage.overview) {
      _selectRootPage(NkasPage.overview);
      return true;
    }
    return false;
  }

  String get _pageTitle => switch (page) {
    NkasPage.overview => '总览',
    NkasPage.instances => '实例',
    NkasPage.tasks => '任务',
    NkasPage.screen => '画面',
    NkasPage.logs => '日志',
    NkasPage.settings => '设置',
  };

  /// 设置等子页面改为真实路由（见 _pushSubPage），iOS 由系统提供左边缘
  /// 侧滑返回，Android 系统返回直接 pop 路由，不再占用壳层 pageStack
  void _pushSubPage(String title, Widget child) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _SubPageScaffold(
          title: title,
          connection: widget.connectionController,
          child: child,
        ),
      ),
    );
  }

  Widget _pageBody() => switch (page) {
    NkasPage.overview => OverviewPage(
      instances: instances,
      loadingInstances: loadingInstances,
      instancesError: instancesError,
      avatarUrl: _avatarUrl,
      resolveAssetUrl: (value) =>
          widget.connectionController.assetUri(value).toString(),
      serviceRunning:
          widget.connectionController.state.phase == ConnectionPhase.connected,
      onRefreshStatus: () => widget.connectionController.connect(
        widget.connectionController.state.baseUrl,
      ),
      onOpenInstances: () => _pushPage(NkasPage.instances),
      onSelectInstance: (value) {
        setState(() {
          instance = value;
          taskKey = null;
          queueError = null;
          schema = null;
          schemaError = null;
        });
        _pushPage(NkasPage.instances);
        unawaited(_loadQueue(value));
      },
      calendarItems: calendarItems,
      calendarUpdatedAt: calendarUpdatedAt,
      calendarLoading: loadingCalendar,
      calendarError: calendarError,
      onRefreshCalendar: () => _loadCalendar(refresh: true),
    ),
    NkasPage.instances => InstancesPage(
      instances: instances,
      selectedInstance: selectedInstance,
      loading: loadingInstances,
      toggleLoading: togglingInstance,
      error: instancesError,
      avatarUrl: _avatarUrl,
      queue: queues[instance],
      queueLoading: loadingQueue,
      queueError: queueError,
      selected: instance,
      running: instanceStates[instance] ?? false,
      onToggle: () => unawaited(_toggleInstance(instance)),
      onSelectInstance: _switchInstance,
      onOpenTask: _openTask,
      liveLogUri: widget.connectionController.websocketUri(
        '/ws/${Uri.encodeComponent(instance)}/log',
      ),
      accessGranted: _starAccessGranted,
    ),
    NkasPage.tasks => TasksPage(
      instances: instances,
      selected: instance,
      selectedInstance: selectedInstance,
      avatarUrl: _avatarUrl,
      instancesLoading: loadingInstances,
      instancesError: instancesError,
      onSelectInstance: _switchInstance,
      schema: schema,
      schemaLoading: loadingSchema,
      schemaError: schemaError,
      loadSchema: () => _loadSchema(instance),
      onPatch: (key, value) =>
          widget.connectionController.patchConfig(instance, key, value),
      initialTaskKey: taskKey,
      onTaskKeyChanged: (value) => setState(() => taskKey = value),
      loadSchedule: () => widget.connectionController.fetchSchedule(instance),
      saveSchedule: (changes) =>
          widget.connectionController.saveSchedule(instance, changes),
      resetSchedule: () => widget.connectionController.resetSchedule(instance),
    ),
    NkasPage.screen => ScreenPage(
      instances: instances,
      selected: instance,
      selectedInstance: selectedInstance,
      avatarUrl: _avatarUrl,
      loading: loadingInstances,
      error: instancesError,
      onSelectInstance: _switchInstance,
      loadScreenshot: () =>
          widget.connectionController.fetchScreenshot(instance),
      accessGranted: _starAccessGranted,
      onOpenNativeControl: () => _pushSubPage(
        '控制连接',
        NativeControlPage(
          platform: NkasPlatform.instance,
          onClose: () => Navigator.of(context).pop(),
        ),
      ),
    ),
    NkasPage.logs => LogsPage(
      connectionController: widget.connectionController,
    ),
    NkasPage.settings => SettingsPage(
      connectionController: widget.connectionController,
      starAuthorized: _starAccessGranted,
      themeMode: widget.themeMode,
      notifications: notifications,
      onThemeModeChanged: widget.onThemeModeChanged,
      onNotificationsChanged: (value) => setState(() => notifications = value),
      onOpenStarVerify: () => _pushSubPage(
        'STAR 验证',
        StarVerifyPage(onOpenSetup: () => unawaited(_openSetup())),
      ),
      onOpenSetup: () => unawaited(_openSetup()),
      onOpenUpdate: () => _pushSubPage(
        '更新',
        UpdatePage(
          connectionController: widget.connectionController,
          enabled: _starAccessGranted,
        ),
      ),
      onOpenAbout: () => _pushSubPage(
        '关于',
        AboutPage(connectionController: widget.connectionController),
      ),
      onOpenNativeControl: () => _pushSubPage(
        '控制连接',
        NativeControlPage(
          platform: NkasPlatform.instance,
          onClose: () => Navigator.of(context).pop(),
        ),
      ),
      onOpenDeploy: () => _pushSubPage(
        '部署',
        DeployPage(
          connectionController: widget.connectionController,
          accessGranted: _starAccessGranted,
        ),
      ),
      onOpenBackendAddress: () => _pushSubPage(
        '后端地址',
        BackendAddressPage(
          connectionController: widget.connectionController,
          onClose: () => Navigator.of(context).pop(),
        ),
      ),
    ),
  };

  void _switchInstance(String value) {
    setState(() {
      instance = value;
      queueError = null;
      schema = null;
      schemaError = null;
      taskKey = null;
    });
    unawaited(_loadQueue(value));
    if (page == NkasPage.tasks && schema == null) {
      unawaited(_loadSchema(value));
    }
  }

  /// 进入实例/任务页前确保队列和 schema 已就绪（队列 socket 已在当前实例上则不重连）
  void _prepareInstancePage(NkasPage value) {
    if (value != NkasPage.instances && value != NkasPage.tasks) return;
    if (queueSocketInstance != instance && !loadingQueue) {
      unawaited(_loadQueue(instance));
    }
    if (value == NkasPage.tasks && schema == null) {
      unawaited(_loadSchema(instance));
    }
  }

  /// 实例详情点队列行：打开任务页并展开对应任务配置
  void _openTask(String key) {
    taskKey = key;
    if (page == NkasPage.tasks) {
      setState(() {});
      return;
    }
    _pushPage(NkasPage.tasks);
  }

  void _selectRootPage(NkasPage value) {
    final from = _rootPages.indexOf(page);
    final to = _rootPages.indexOf(value);
    _navDirection = from >= 0 && to >= 0 && to < from ? -1 : 1;
    _prepareInstancePage(value);
    setState(() {
      pageStack
        ..clear()
        ..add(value);
      page = value;
      taskKey = null;
      schema = null;
      schemaError = null;
    });
  }

  void _pushPage(NkasPage value) {
    if (page == value) return;
    _navDirection = 1;
    _prepareInstancePage(value);
    setState(() {
      pageStack.add(value);
      page = value;
    });
  }

  Future<void> _openSetup() async {
    Widget page() => NkasSetupPage(
      onOpenStar: () => _pushSubPage(
        'STAR 验证',
        StarVerifyPage(onOpenSetup: () => unawaited(_openSetup())),
      ),
      onOpenUi: _openWebUi,
    );
    if (!isAndroid && !isIOS) {
      _pushSubPage('初始化', page());
      return;
    }
    final latest = await NkasPlatform.instance.starStatus();
    if (!mounted) return;
    _applyStarStatus(latest);
    if (latest.authorized) _pushSubPage('初始化', page());
  }

  Future<void> _openWebUi() async {
    if (!_starAccessGranted) return;
    final opened = await launchUrl(
      widget.connectionController.webUiUri,
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开原始 WebUI')));
    }
  }

  Future<void> _loadSchema(String name) async {
    if (!_starAccessGranted || loadingSchema) return;
    setState(() {
      loadingSchema = true;
      schemaError = null;
    });
    try {
      final value = await widget.connectionController.fetchSchema(name);
      if (mounted && _starAccessGranted) setState(() => schema = value);
    } catch (exception) {
      if (mounted) setState(() => schemaError = exception.toString());
    } finally {
      if (mounted) setState(() => loadingSchema = false);
    }
  }

  Future<void> _toggleInstance(String name) async {
    if (!_starAccessGranted || togglingInstance) return;
    InstanceInfo? target;
    for (final item in instances) {
      if (item.name == name) {
        target = item;
        break;
      }
    }
    if (target == null) return;
    final nextRunning = target.state != 1;
    setState(() => togglingInstance = true);
    try {
      await widget.connectionController.setInstanceRunning(name, nextRunning);
      if (!mounted) return;
      await _loadInstances();
    } catch (error) {
      if (!mounted) return;
      setState(() => instancesError = error.toString());
    } finally {
      if (mounted) setState(() => togglingInstance = false);
    }
  }
}

class _AppHeader extends StatelessWidget {
  const _AppHeader({
    required this.title,
    required this.connection,
    this.showBack = false,
    this.backTooltip = '返回',
    this.onBack,
    this.crumb,
    this.onCrumbRootTap,
  });
  final String title;
  final BackendConnectionState connection;
  final bool showBack;
  final String backTooltip;
  final VoidCallback? onBack;

  /// 面包屑末级（如任务详情时的任务名）；存在时标题可点击返回上一级
  final String? crumb;
  final VoidCallback? onCrumbRootTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final scheme = theme.colorScheme;
    final color = switch (connection.phase) {
      ConnectionPhase.connected => scheme.success,
      ConnectionPhase.connecting => scheme.primary,
      ConnectionPhase.disconnected => scheme.destructive,
      ConnectionPhase.incompatible => scheme.warning,
    };
    final crumb = this.crumb;
    return SizedBox(
      height: 58,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
        child: Row(
          children: [
            if (showBack) ...[
              IconButton(
                onPressed: onBack,
                icon: const Icon(LucideIcons.arrowLeft, size: 20),
                tooltip: backTooltip,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 36,
                  height: 36,
                ),
              ),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: crumb == null
                  ? Text(title, style: theme.textTheme.h2)
                  : Row(
                      children: [
                        InkWell(
                          onTap: onCrumbRootTap,
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 2,
                              vertical: 2,
                            ),
                            child: Text(title, style: theme.textTheme.h2),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(
                            LucideIcons.chevronRight,
                            size: 16,
                            color: scheme.mutedForeground,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            crumb,
                            style: theme.textTheme.h2,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: color.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Dot(color: color),
                  const SizedBox(width: 6),
                  Text(
                    connection.label,
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 子页面的独立路由壳：与主壳层一致的头部、宽度约束与背景，
/// 不含底部导航和 STAR 遮罩（路由覆盖整个主壳层）
class _SubPageScaffold extends StatelessWidget {
  const _SubPageScaffold({
    required this.title,
    required this.connection,
    required this.child,
  });

  final String title;
  final ConnectionController connection;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      body: Center(
        child: LayoutBuilder(
          builder: (context, constraints) => SizedBox(
            width: constraints.maxWidth.clamp(0, 480),
            height: constraints.maxHeight,
            child: SafeArea(
              child: Column(
                children: [
                  ListenableBuilder(
                    listenable: connection,
                    builder: (context, _) => _AppHeader(
                      title: title,
                      connection: connection.state,
                      showBack: true,
                      backTooltip: '返回设置',
                      onBack: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                  Expanded(child: child),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.page, required this.onSelect});
  final NkasPage page;
  final ValueChanged<NkasPage> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      // 阴影必须在 ClipRRect 外层，否则会被圆角裁掉；BackdropFilter 只裁毛玻璃层
      child: Container(
        width: 344,
        height: 58,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          boxShadow: NkasShadows.raised(Theme.of(context).brightness),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              decoration: BoxDecoration(
                color: scheme.navBg,
                border: Border.all(color: scheme.navBorder),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _NavItem(
                    icon: LucideIcons.layoutDashboard,
                    label: '总览',
                    selected: page == NkasPage.overview,
                    onTap: () => onSelect(NkasPage.overview),
                  ),
                  _NavItem(
                    icon: LucideIcons.layers3,
                    label: '实例',
                    selected: page == NkasPage.instances,
                    onTap: () => onSelect(NkasPage.instances),
                  ),
                  _NavItem(
                    icon: LucideIcons.listTodo,
                    label: '任务',
                    selected: page == NkasPage.tasks,
                    onTap: () => onSelect(NkasPage.tasks),
                  ),
                  _NavItem(
                    icon: LucideIcons.monitorPlay,
                    label: '画面',
                    selected: page == NkasPage.screen,
                    onTap: () => onSelect(NkasPage.screen),
                  ),
                  _NavItem(
                    icon: LucideIcons.scrollText,
                    label: '日志',
                    selected: page == NkasPage.logs,
                    onTap: () => onSelect(NkasPage.logs),
                  ),
                  _NavItem(
                    icon: LucideIcons.settings2,
                    label: '设置',
                    selected: page == NkasPage.settings,
                    onTap: () => onSelect(NkasPage.settings),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = ShadTheme.of(context).colorScheme;
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: selected ? scheme.accentSoft : Colors.transparent,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: selected ? scheme.primary : scheme.mutedForeground,
                ),
              ),
              if (selected)
                Positioned(
                  bottom: 4,
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 未通过 STAR 验证时盖在页面上的遮罩：毛玻璃 + 半透明底色拦截页面手势，
/// 仅保留「前往 STAR 验证」入口；底部导航在 Stack 中位于其上，仍可切换页面
class _StarGateOverlay extends StatelessWidget {
  const _StarGateOverlay({required this.onVerify});

  final VoidCallback onVerify;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final scheme = theme.colorScheme;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          color: scheme.background.withValues(alpha: .78),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.accentSoft,
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Icon(LucideIcons.star, color: scheme.primary, size: 26),
              ),
              const SizedBox(height: 16),
              const Text(
                '需要 STAR 验证',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                'Star 本项目并完成验证后解锁全部功能',
                textAlign: TextAlign.center,
                style: theme.textTheme.muted,
              ),
              const SizedBox(height: 18),
              PrimaryButton(
                icon: LucideIcons.gitBranch,
                label: '前往 STAR 验证',
                onPressed: onVerify,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
