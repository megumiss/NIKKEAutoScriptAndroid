import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

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
    required this.onThemeModeChanged,
    super.key,
  });

  final ThemeMode themeMode;
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
                  _AppHeader(title: _pageTitle, connected: true),
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
      serviceRunning: serviceRunning,
      canControlService: canControlLocalService,
      onToggleService: () => setState(() => serviceRunning = !serviceRunning),
      onOpenInstances: () => _selectPage(NkasPage.instances),
    ),
    NkasPage.instances => InstancesPage(
      selected: instance,
      running: instanceStates[instance] ?? false,
      tab: instanceTab,
      onTabChanged: (value) => setState(() => instanceTab = value),
      onToggle: () => setState(() {
        instanceStates[instance] = !(instanceStates[instance] ?? false);
      }),
      onSelectInstance: (value) => setState(() {
        instance = value;
        instanceTab = InstanceTab.overview;
      }),
    ),
    NkasPage.logs => const LogsPage(),
    NkasPage.settings => SettingsPage(
      themeMode: widget.themeMode,
      notifications: notifications,
      autoScroll: autoScroll,
      onThemeModeChanged: widget.onThemeModeChanged,
      onNotificationsChanged: (value) => setState(() => notifications = value),
      onAutoScrollChanged: (value) => setState(() => autoScroll = value),
    ),
  };

  void _selectPage(NkasPage value) => setState(() => page = value);
}

class _AppHeader extends StatelessWidget {
  const _AppHeader({required this.title, required this.connected});
  final String title;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final scheme = theme.colorScheme;
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
                color: scheme.connectionBg,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Dot(color: scheme.connectionDot),
                  const SizedBox(width: 6),
                  Text(
                    connected ? '已连接' : '未连接',
                    style: TextStyle(
                      color: scheme.connectionText,
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
