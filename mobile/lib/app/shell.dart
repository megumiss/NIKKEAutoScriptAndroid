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
import 'package:nkas_mobile/features/screen/screen_page.dart';
import 'package:nkas_mobile/features/logs/logs_page.dart';
import 'package:nkas_mobile/features/deploy/deploy_page.dart';
import 'package:nkas_mobile/features/overview/overview_page.dart';
import 'package:nkas_mobile/features/settings/settings_page.dart';
import 'package:nkas_mobile/features/settings/setup_page.dart';
import 'package:nkas_mobile/features/settings/native_control_page.dart';
import 'package:nkas_mobile/features/settings/star_verify_page.dart';
import 'package:nkas_mobile/features/settings/about_page.dart';
import 'package:nkas_mobile/features/settings/update_page.dart';
import 'package:nkas_mobile/theme.dart';

enum NkasPage {
  overview,
  instances,
  screen,
  logs,
  deploy,
  settings,
  starVerify,
  setup,
  update,
  about,
  nativeControl,
}

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
  // 预览工程支持 ?page=overview|instances|logs|deploy|settings 指定初始页，便于逐页截图验收
  NkasPage page = kIsWeb
      ? NkasPage.values.asNameMap()[Uri.base.queryParameters['page']] ??
            NkasPage.overview
      : NkasPage.overview;
  late final List<NkasPage> pageStack = [page];
  InstanceLayer instanceLayer = InstanceLayer.list;
  bool instanceListParent = false;
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
    NkasPage.screen,
    NkasPage.logs,
    NkasPage.deploy,
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

  void _connectionChanged() {
    if (!mounted) return;
    final connection = widget.connectionController.state;
    final accessGranted = _starAccessGranted;
    final connected = connection.phase == ConnectionPhase.connected;
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

  /// 列表层为非选中实例拉一次队列快照：不开队列 WS，避免挤掉选中实例的 socket
  Future<void> _loadQueueSnapshot(String name) async {
    if (!_starAccessGranted) return;
    try {
      final result = await widget.connectionController.fetchQueue(name);
      if (!mounted || !_starAccessGranted) return;
      setState(() => queues[name] = result);
    } catch (_) {
      // 列表卡片计数失败静默：卡片不显示计数行
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
                      showBack:
                          !_canPopSystemRoute && !_hasInstanceLayerBackBar,
                      backTooltip: _isSettingsSubpage ? '返回设置' : '返回',
                      onBack: _handleBack,
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
                              transitionBuilder: (child, animation) =>
                                  ClipRect(
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
                          if (!_starAccessGranted &&
                              page != NkasPage.settings &&
                              !_isSettingsSubpage)
                            Positioned.fill(
                              child: _StarGateOverlay(
                                onVerify: () => _pushPage(NkasPage.starVerify),
                              ),
                            ),
                          if (!_isSettingsSubpage)
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
      page == NkasPage.overview &&
      pageStack.length == 1 &&
      instanceLayer == InstanceLayer.list;

  bool get _hasInstanceLayerBackBar =>
      page == NkasPage.instances &&
      (instanceLayer == InstanceLayer.tasks ||
          instanceLayer == InstanceLayer.schedule ||
          instanceLayer == InstanceLayer.liveLogs);

  bool _handleBack() {
    _navDirection = -1;
    if (page == NkasPage.instances) {
      if (instanceLayer == InstanceLayer.tasks && taskKey != null) {
        setState(() => taskKey = null);
        return true;
      }
      if (instanceLayer == InstanceLayer.tasks ||
          instanceLayer == InstanceLayer.schedule ||
          instanceLayer == InstanceLayer.liveLogs) {
        setState(() => instanceLayer = InstanceLayer.dashboard);
        return true;
      }
      if (instanceLayer == InstanceLayer.dashboard &&
          instanceListParent &&
          instances.length > 1) {
        setState(() {
          instanceLayer = InstanceLayer.list;
          taskKey = null;
          schema = null;
          schemaError = null;
        });
        return true;
      }
    }
    if (pageStack.length > 1) {
      setState(() {
        pageStack.removeLast();
        page = pageStack.last;
        if (page != NkasPage.instances) {
          instanceListParent = false;
          instanceLayer = InstanceLayer.list;
          taskKey = null;
          schema = null;
          schemaError = null;
        }
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
    NkasPage.screen => '画面',
    NkasPage.logs => '日志',
    NkasPage.deploy => '部署',
    NkasPage.settings => '设置',
    NkasPage.starVerify => 'STAR 验证',
    NkasPage.setup => '初始化',
    NkasPage.update => '更新',
    NkasPage.about => '关于',
    NkasPage.nativeControl => '控制连接',
  };

  bool get _isSettingsSubpage =>
      page == NkasPage.starVerify ||
      page == NkasPage.setup ||
      page == NkasPage.update ||
      page == NkasPage.about ||
      page == NkasPage.nativeControl;

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
          instanceLayer = InstanceLayer.dashboard;
          pageStack.add(NkasPage.instances);
          page = NkasPage.instances;
          instanceListParent = false;
          taskKey = null;
          queueError = null;
          schema = null;
          schemaError = null;
        });
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
      queues: queues,
      queueLoading: loadingQueue,
      queueError: queueError,
      selected: instance,
      running: instanceStates[instance] ?? false,
      layer: instanceLayer,
      onLayerChanged: (value) {
        setState(() => instanceLayer = value);
        if (value == InstanceLayer.tasks && schema == null) {
          unawaited(_loadSchema(instance));
        }
      },
      onToggle: () => unawaited(_toggleInstance(instance)),
      onToggleInstance: (name) => unawaited(_toggleInstance(name)),
      loadQueueSnapshot: _loadQueueSnapshot,
      fetchScreenshot: (name) =>
          widget.connectionController.fetchScreenshot(name),
      onOpenScreen: () => _pushPage(NkasPage.screen),
      loadSchedule: () => widget.connectionController.fetchSchedule(instance),
      saveSchedule: (changes) =>
          widget.connectionController.saveSchedule(instance, changes),
      resetSchedule: () => widget.connectionController.resetSchedule(instance),
      schema: schema,
      schemaLoading: loadingSchema,
      schemaError: schemaError,
      loadSchema: () => _loadSchema(instance),
      patchConfig: (key, value) =>
          widget.connectionController.patchConfig(instance, key, value),
      liveLogUri: widget.connectionController.websocketUri(
        '/ws/${Uri.encodeComponent(instance)}/log',
      ),
      onOpenTask: (value) {
        setState(() {
          instanceLayer = InstanceLayer.tasks;
          taskKey = value;
        });
        if (schema == null) unawaited(_loadSchema(instance));
      },
      onTaskKeyChanged: (value) => setState(() => taskKey = value),
      initialTaskKey: taskKey,
      accessGranted: _starAccessGranted,
      onSelectInstance: _switchInstance,
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
      onOpenNativeControl: () => _pushPage(NkasPage.nativeControl),
    ),
    NkasPage.logs => LogsPage(
      connectionController: widget.connectionController,
    ),
    NkasPage.deploy => DeployPage(
      connectionController: widget.connectionController,
      accessGranted: _starAccessGranted,
    ),
    NkasPage.settings => SettingsPage(
      connectionController: widget.connectionController,
      starAuthorized: _starAccessGranted,
      themeMode: widget.themeMode,
      notifications: notifications,
      onThemeModeChanged: widget.onThemeModeChanged,
      onNotificationsChanged: (value) => setState(() => notifications = value),
      onOpenStarVerify: () => _pushPage(NkasPage.starVerify),
      onOpenSetup: () => unawaited(_openSetup()),
      onOpenUpdate: () => _pushPage(NkasPage.update),
      onOpenAbout: () => _pushPage(NkasPage.about),
      onOpenNativeControl: () => _pushPage(NkasPage.nativeControl),
    ),
    NkasPage.starVerify => StarVerifyPage(
      onOpenSetup: () => unawaited(_openSetup()),
    ),
    NkasPage.setup => NkasSetupPage(
      onOpenStar: () => _pushPage(NkasPage.starVerify),
      onOpenUi: _openWebUi,
    ),
    NkasPage.update => UpdatePage(
      connectionController: widget.connectionController,
      enabled: _starAccessGranted,
    ),
    NkasPage.about => AboutPage(
      connectionController: widget.connectionController,
    ),
    NkasPage.nativeControl => NativeControlPage(
      platform: NkasPlatform.instance,
      onClose: _handleBack,
    ),
  };

  void _switchInstance(String value) {
    setState(() {
      instance = value;
      instanceLayer = InstanceLayer.dashboard;
      queueError = null;
      schema = null;
      schemaError = null;
      taskKey = null;
    });
    unawaited(_loadQueue(value));
  }

  void _selectRootPage(NkasPage value) {
    final from = _rootPages.indexOf(page);
    final to = _rootPages.indexOf(value);
    _navDirection = from >= 0 && to >= 0 && to < from ? -1 : 1;
    setState(() {
      pageStack
        ..clear()
        ..add(value);
      page = value;
      instanceListParent = value == NkasPage.instances;
      instanceLayer = InstanceLayer.list;
      taskKey = null;
      schema = null;
      schemaError = null;
    });
  }

  void _pushPage(NkasPage value) {
    if (page == value) return;
    _navDirection = 1;
    if (value == NkasPage.instances) {
      setState(() {
        pageStack.add(value);
        page = value;
        instanceListParent = true;
        // The page decides whether a single instance skips the list. Keeping
        // the list layer here also handles instances arriving asynchronously.
        instanceLayer = InstanceLayer.list;
        taskKey = null;
        schema = null;
        schemaError = null;
      });
      return;
    }
    setState(() {
      pageStack.add(value);
      page = value;
    });
  }

  Future<void> _openSetup() async {
    if (!isAndroid && !isIOS) {
      _pushPage(NkasPage.setup);
      return;
    }
    final latest = await NkasPlatform.instance.starStatus();
    if (!mounted) return;
    _applyStarStatus(latest);
    if (latest.authorized) _pushPage(NkasPage.setup);
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
  });
  final String title;
  final BackendConnectionState connection;
  final bool showBack;
  final String backTooltip;
  final VoidCallback? onBack;

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
            Expanded(child: Text(title, style: theme.textTheme.h2)),
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
                    icon: LucideIcons.rocket,
                    label: '部署',
                    selected: page == NkasPage.deploy,
                    onTap: () => onSelect(NkasPage.deploy),
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
