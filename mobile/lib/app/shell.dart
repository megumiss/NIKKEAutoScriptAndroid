import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:nkas_mobile_preview/core/api/instance_info.dart';
import 'package:nkas_mobile_preview/core/connection/connection_controller.dart';
import 'package:nkas_mobile_preview/core/connection/instance_state_socket.dart';
import 'package:nkas_mobile_preview/core/connection/instance_queue_socket.dart';
import 'package:nkas_mobile_preview/core/api/queue_info.dart';
import 'package:nkas_mobile_preview/core/api/calendar_info.dart';
import 'package:nkas_mobile_preview/core/api/schema_info.dart';
import 'package:nkas_mobile_preview/core/platform/nkas_platform.dart';
import 'package:nkas_mobile_preview/core/platform/runtime_platform.dart';
import 'package:nkas_mobile_preview/core/widgets/status.dart';
import 'package:nkas_mobile_preview/features/instances/instances_page.dart';
import 'package:nkas_mobile_preview/features/logs/logs_page.dart';
import 'package:nkas_mobile_preview/features/overview/overview_page.dart';
import 'package:nkas_mobile_preview/features/settings/settings_page.dart';
import 'package:nkas_mobile_preview/features/settings/setup_page.dart';
import 'package:nkas_mobile_preview/features/settings/star_verify_page.dart';
import 'package:nkas_mobile_preview/theme.dart';

enum NkasPage { overview, instances, logs, settings, starVerify, setup }

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
  // 预览工程支持 ?page=overview|instances|logs|settings 指定初始页，便于逐页截图验收
  NkasPage page = kIsWeb
      ? NkasPage.values.asNameMap()[Uri.base.queryParameters['page']] ??
            NkasPage.overview
      : NkasPage.overview;
  InstanceTab instanceTab = InstanceTab.overview;
  String instance = '主账号';
  bool notifications = true;
  bool autoScroll = true;
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
    setState(() {
      star = status;
      if (!_starAccessGranted &&
          page != NkasPage.settings &&
          page != NkasPage.starVerify) {
        page = NkasPage.settings;
      }
    });
    _connectionChanged();
  }

  bool get _starAccessGranted =>
      kIsWeb || (!isAndroid && !isIOS) || star.authorized;

  void _connectionChanged() {
    if (!mounted) return;
    final connection = widget.connectionController.state;
    setState(() {
      if (!_starAccessGranted ||
          connection.phase != ConnectionPhase.connected) {
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
    if (_starAccessGranted &&
        connection.phase == ConnectionPhase.connected &&
        loadedInstancesBaseUrl != connection.baseUrl &&
        !loadingInstances) {
      unawaited(_loadInstances());
    }
    if (_starAccessGranted &&
        connection.phase == ConnectionPhase.connected &&
        calendarBaseUrl != connection.baseUrl &&
        !loadingCalendar) {
      unawaited(_loadCalendar());
    }
    if (_starAccessGranted &&
        widget.enableRealtime &&
        connection.phase == ConnectionPhase.connected &&
        stateSocketBaseUrl != connection.baseUrl) {
      unawaited(_openStateSocket(connection.baseUrl));
    } else if (!widget.enableRealtime ||
        connection.phase != ConnectionPhase.connected) {
      unawaited(_closeStateSocket());
    }
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
        if (!mounted) return;
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
    return Scaffold(
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
                    showBack: _isSettingsSubpage,
                    onBack: () => _selectPage(NkasPage.settings),
                  ),
                  // 底部导航悬浮在内容之上（原型 .np-nav：bottom 14 + 阴影 + 毛玻璃），
                  // 各页面底部预留 88 避让区
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(child: _pageBody()),
                        if (!_isSettingsSubpage)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 14,
                            child: _BottomNav(
                              page: page,
                              accessEnabled: _starAccessGranted,
                              onSelect: _selectPage,
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
    );
  }

  String get _pageTitle => switch (page) {
    NkasPage.overview => '总览',
    NkasPage.instances => '实例',
    NkasPage.logs => '日志',
    NkasPage.settings => '设置',
    NkasPage.starVerify => 'STAR 验证',
    NkasPage.setup => '初始化 NKAS',
  };

  bool get _isSettingsSubpage =>
      page == NkasPage.starVerify || page == NkasPage.setup;

  Widget _pageBody() => switch (page) {
    NkasPage.overview => OverviewPage(
      instances: instances,
      loadingInstances: loadingInstances,
      instancesError: instancesError,
      avatarUrl: _avatarUrl,
      serviceRunning:
          widget.connectionController.state.phase == ConnectionPhase.connected,
      onRefreshStatus: () => widget.connectionController.connect(
        widget.connectionController.state.baseUrl,
      ),
      onOpenInstances: () => _selectPage(NkasPage.instances),
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
      tab: instanceTab,
      onTabChanged: (value) {
        setState(() => instanceTab = value);
        if (value == InstanceTab.tasks && schema == null) {
          unawaited(_loadSchema(instance));
        }
      },
      onToggle: () => unawaited(_toggleSelectedInstance()),
      loadScreenshot: () =>
          widget.connectionController.fetchScreenshot(instance),
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
      onOpenControl: _openWebUi,
      liveLogUri: widget.connectionController.websocketUri(
        '/ws/${Uri.encodeComponent(instance)}/log',
      ),
      onSelectInstance: (value) {
        setState(() {
          instance = value;
          instanceTab = InstanceTab.overview;
          queueError = null;
          schema = null;
          schemaError = null;
        });
        unawaited(_loadQueue(value));
      },
    ),
    NkasPage.logs => LogsPage(
      connectionController: widget.connectionController,
    ),
    NkasPage.settings => SettingsPage(
      connectionController: widget.connectionController,
      starAuthorized: _starAccessGranted,
      themeMode: widget.themeMode,
      notifications: notifications,
      autoScroll: autoScroll,
      onThemeModeChanged: widget.onThemeModeChanged,
      onNotificationsChanged: (value) => setState(() => notifications = value),
      onAutoScrollChanged: (value) => setState(() => autoScroll = value),
      onOpenStarVerify: () => _selectPage(NkasPage.starVerify),
      onOpenSetup: () => _selectPage(NkasPage.setup),
    ),
    NkasPage.starVerify => StarVerifyPage(
      onOpenSetup: () => _selectPage(NkasPage.setup),
    ),
    NkasPage.setup => NkasSetupPage(
      onOpenStar: () => _selectPage(NkasPage.starVerify),
    ),
  };

  void _selectPage(NkasPage value) {
    if (!_starAccessGranted &&
        value != NkasPage.settings &&
        value != NkasPage.starVerify) {
      setState(() => page = NkasPage.settings);
      return;
    }
    setState(() => page = value);
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

  Future<void> _toggleSelectedInstance() async {
    final selected = selectedInstance;
    if (!_starAccessGranted || selected == null || togglingInstance) return;
    final nextRunning = selected.state != 1;
    setState(() => togglingInstance = true);
    try {
      await widget.connectionController.setInstanceRunning(
        selected.name,
        nextRunning,
      );
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
    this.onBack,
  });
  final String title;
  final BackendConnectionState connection;
  final bool showBack;
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
                tooltip: '返回设置',
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
  const _BottomNav({
    required this.page,
    required this.accessEnabled,
    required this.onSelect,
  });
  final NkasPage page;
  final bool accessEnabled;
  final ValueChanged<NkasPage> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      // 阴影必须在 ClipRRect 外层，否则会被圆角裁掉；BackdropFilter 只裁毛玻璃层
      child: Container(
        width: 244,
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
                    enabled: accessEnabled,
                    onTap: () => onSelect(NkasPage.overview),
                  ),
                  _NavItem(
                    icon: LucideIcons.layers3,
                    label: '实例',
                    selected: page == NkasPage.instances,
                    enabled: accessEnabled,
                    onTap: () => onSelect(NkasPage.instances),
                  ),
                  _NavItem(
                    icon: LucideIcons.scrollText,
                    label: '日志',
                    selected: page == NkasPage.logs,
                    enabled: accessEnabled,
                    onTap: () => onSelect(NkasPage.logs),
                  ),
                  _NavItem(
                    icon: LucideIcons.settings2,
                    label: '设置',
                    selected: page == NkasPage.settings,
                    enabled: true,
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
    required this.enabled,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = ShadTheme.of(context).colorScheme;
    return Tooltip(
      message: enabled ? label : '$label（需 STAR 验证）',
      child: Opacity(
        opacity: enabled ? 1 : .38,
        child: InkWell(
          onTap: enabled ? onTap : null,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 46,
            height: 46,
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
      ),
    );
  }
}
