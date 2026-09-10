import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile_preview/core/api/instance_info.dart';
import 'package:nkas_mobile_preview/core/connection/connection_controller.dart';
import 'package:nkas_mobile_preview/core/connection/instance_state_socket.dart';
import 'package:nkas_mobile_preview/core/connection/instance_queue_socket.dart';
import 'package:nkas_mobile_preview/core/api/queue_info.dart';
import 'package:nkas_mobile_preview/core/widgets/status.dart';
import 'package:nkas_mobile_preview/features/instances/instances_page.dart';
import 'package:nkas_mobile_preview/features/logs/logs_page.dart';
import 'package:nkas_mobile_preview/features/overview/overview_page.dart';
import 'package:nkas_mobile_preview/features/settings/settings_page.dart';
import 'package:nkas_mobile_preview/theme.dart';

enum NkasPage { overview, instances, logs, settings }

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
  bool serviceRunning = true;
  bool notifications = true;
  bool autoScroll = true;
  final instanceStates = <String, bool>{
    '主账号': true,
    '小号': false,
    '测试账号': false,
  };
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

  @override
  void initState() {
    super.initState();
    widget.connectionController.addListener(_connectionChanged);
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
    unawaited(_closeStateSocket());
    unawaited(_closeQueueSocket());
    super.dispose();
  }

  void _connectionChanged() {
    if (!mounted) return;
    final connection = widget.connectionController.state;
    setState(() {
      if (connection.phase != ConnectionPhase.connected) {
        instances = const [];
        instancesError = null;
        loadedInstancesBaseUrl = null;
        stateSocketBaseUrl = null;
        queues.clear();
        queueError = null;
        queueSocketInstance = null;
      }
    });
    if (connection.phase == ConnectionPhase.connected &&
        loadedInstancesBaseUrl != connection.baseUrl &&
        !loadingInstances) {
      unawaited(_loadInstances());
    }
    if (widget.enableRealtime &&
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
    if (!mounted) return;
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
      if (!mounted || widget.connectionController.state.baseUrl != baseUrl) {
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
      if (!mounted) return;
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
    setState(() {
      loadingQueue = true;
      queueError = null;
    });
    try {
      final result = await widget.connectionController.fetchQueue(name);
      if (!mounted) return;
      setState(() => queues[name] = result);
      unawaited(_openQueueSocket(name));
    } catch (error) {
      if (!mounted) return;
      setState(() => queueError = error.toString());
    } finally {
      if (mounted) setState(() => loadingQueue = false);
    }
  }

  Future<void> _openQueueSocket(String name) async {
    queueSocketReconnectTimer?.cancel();
    await _closeQueueSocket();
    final connection = widget.connectionController.state;
    if (!mounted || connection.phase != ConnectionPhase.connected) return;
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

  bool get canControlLocalService =>
      kIsWeb || defaultTargetPlatform == TargetPlatform.android;

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
                  ),
                  // 底部导航悬浮在内容之上（原型 .np-nav：bottom 14 + 阴影 + 毛玻璃），
                  // 各页面底部预留 88 避让区
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(child: _pageBody()),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 14,
                          child: _BottomNav(page: page, onSelect: _selectPage),
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
  };

  Widget _pageBody() => switch (page) {
    NkasPage.overview => OverviewPage(
      instances: instances,
      loadingInstances: loadingInstances,
      instancesError: instancesError,
      avatarUrl: _avatarUrl,
      serviceRunning: serviceRunning,
      canControlService: canControlLocalService,
      onToggleService: () => setState(() => serviceRunning = !serviceRunning),
      onOpenInstances: () => _selectPage(NkasPage.instances),
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
      onTabChanged: (value) => setState(() => instanceTab = value),
      onToggle: () => unawaited(_toggleSelectedInstance()),
      onSelectInstance: (value) {
        setState(() {
          instance = value;
          instanceTab = InstanceTab.overview;
          queueError = null;
        });
        unawaited(_loadQueue(value));
      },
    ),
    NkasPage.logs => const LogsPage(),
    NkasPage.settings => SettingsPage(
      connectionController: widget.connectionController,
      themeMode: widget.themeMode,
      notifications: notifications,
      autoScroll: autoScroll,
      onThemeModeChanged: widget.onThemeModeChanged,
      onNotificationsChanged: (value) => setState(() => notifications = value),
      onAutoScrollChanged: (value) => setState(() => autoScroll = value),
    ),
  };

  void _selectPage(NkasPage value) => setState(() => page = value);

  Future<void> _toggleSelectedInstance() async {
    final selected = selectedInstance;
    if (selected == null || togglingInstance) return;
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
  const _AppHeader({required this.title, required this.connection});
  final String title;
  final BackendConnectionState connection;

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
                    onTap: () => onSelect(NkasPage.overview),
                  ),
                  _NavItem(
                    icon: LucideIcons.layers3,
                    label: '实例',
                    selected: page == NkasPage.instances,
                    onTap: () => onSelect(NkasPage.instances),
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
    );
  }
}
