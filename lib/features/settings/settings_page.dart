import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:nkas_mobile/core/widgets/icon_box.dart';
import 'package:nkas_mobile/core/connection/connection_controller.dart';
import 'package:nkas_mobile/core/platform/nkas_platform.dart';
import 'package:nkas_mobile/core/platform/runtime_platform.dart';
import 'package:nkas_mobile/core/widgets/group_label.dart';
import 'package:nkas_mobile/core/widgets/page_inset.dart';
import 'package:nkas_mobile/core/widgets/page_subtitle.dart';
import 'package:nkas_mobile/core/widgets/surface.dart';
import 'package:nkas_mobile/core/widgets/toggle.dart';
import 'package:nkas_mobile/theme.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    required this.themeMode,
    required this.connectionController,
    required this.starAuthorized,
    required this.notifications,
    required this.onThemeModeChanged,
    required this.onNotificationsChanged,
    required this.onOpenStarVerify,
    required this.onOpenSetup,
    required this.onOpenUpdate,
    required this.onOpenAbout,
    required this.onOpenNativeControl,
    required this.onOpenDeploy,
    required this.onOpenBackendAddress,
    super.key,
  });
  final ThemeMode themeMode;
  final ConnectionController connectionController;
  final bool starAuthorized;
  final bool notifications;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ValueChanged<bool> onNotificationsChanged;
  final VoidCallback onOpenStarVerify;
  final VoidCallback onOpenSetup;
  final VoidCallback onOpenUpdate;
  final VoidCallback onOpenAbout;
  final VoidCallback onOpenNativeControl;
  final VoidCallback onOpenDeploy;
  final VoidCallback onOpenBackendAddress;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  StarAuthorization star = const StarAuthorization(authorized: false);
  StreamSubscription<NkasPlatformEvent>? subscription;

  @override
  void initState() {
    super.initState();
    unawaited(_loadStar());
    if (NkasPlatform.instance.supported) {
      subscription = NkasPlatform.instance.events.listen((event) {
        if (event case StarAuthorizationEvent(:final status)) {
          if (mounted) setState(() => star = status);
        }
      });
    }
  }

  @override
  void dispose() {
    unawaited(subscription?.cancel());
    super.dispose();
  }

  Future<void> _loadStar() async {
    final value = await NkasPlatform.instance.starStatus();
    if (mounted) setState(() => star = value);
  }

  @override
  Widget build(BuildContext context) {
    final inset = nkasPageInset(context);
    final warning = ShadTheme.of(context).colorScheme.warning;
    return ListView(
      padding: EdgeInsets.fromLTRB(inset, 5, inset, 88),
      children: [
        const PageSubtitle('连接、验证与外观设置'),
        _SettingGroup(
          label: '验证与初始化',
          rows: [
            _SettingRow(
              icon: LucideIcons.shieldCheck,
              title: 'STAR 验证',
              subtitle: '设备身份与授权状态 · ${star.authorized ? '已验证' : '待验证'}',
              onTap: widget.onOpenStarVerify,
            ),
            if (isAndroid ||
                isIOS ||
                (!NkasPlatform.instance.supported && !isIOS))
              _SettingRow(
                icon: LucideIcons.sparkles,
                iconColor: warning,
                title: '初始化 NKAS',
                subtitle: isIOS
                    ? (widget.starAuthorized && star.authorized
                          ? '连接远程后端并开始控制实例'
                          : '请先完成 STAR 验证')
                    : widget.starAuthorized && star.authorized
                    ? '准备 Termux、设备连接和 NKAS 服务'
                    : '请先完成 STAR 验证',
                enabled: widget.starAuthorized,
                onTap: widget.starAuthorized ? widget.onOpenSetup : null,
              ),
          ],
        ),
        const SizedBox(height: 20),
        _SettingGroup(
          label: '后端连接',
          rows: [
            _SettingRow(
              icon: LucideIcons.server,
              title: '后端地址',
              subtitle: widget.connectionController.state.baseUrl,
              enabled: widget.starAuthorized,
              onTap: widget.starAuthorized ? widget.onOpenBackendAddress : null,
            ),
            if (NkasPlatform.instance.supported)
              _SettingRow(
                icon: LucideIcons.smartphone,
                title: '控制连接',
                subtitle: isAndroid
                    ? '远程设备、本机虚拟屏幕与 Tailscale'
                    : '远程 Android 与 Tailscale',
                enabled: widget.starAuthorized,
                onTap: widget.starAuthorized
                    ? widget.onOpenNativeControl
                    : null,
              ),
            _SettingRow(
              icon: LucideIcons.globe2,
              title: '原始 WebUI',
              subtitle: '打开完整控制台，使用更多高级功能',
              trailing: LucideIcons.externalLink,
              enabled: widget.starAuthorized,
              onTap: widget.starAuthorized ? () => _openWebUi(context) : null,
            ),
            _UpdateSettingRow(
              connectionController: widget.connectionController,
              enabled: widget.starAuthorized,
              onTap: widget.onOpenUpdate,
            ),
            _SettingRow(
              icon: LucideIcons.rocket,
              title: '部署',
              subtitle: '后端部署与更新配置，修改需谨慎',
              enabled: widget.starAuthorized,
              onTap: widget.starAuthorized ? widget.onOpenDeploy : null,
            ),
          ],
        ),
        const SizedBox(height: 20),
        _SettingGroup(
          label: '外观与通知',
          rows: [
            _SettingRow(
              icon: LucideIcons.palette,
              title: '主题',
              subtitle:
                  '当前：${widget.themeMode == ThemeMode.dark ? '深色' : '浅色'}',
              enabled: widget.starAuthorized,
              customTrailing: IgnorePointer(
                ignoring: !widget.starAuthorized,
                child: Opacity(
                  opacity: widget.starAuthorized ? 1 : .45,
                  child: _ThemeSegment(
                    themeMode: widget.themeMode,
                    onChanged: widget.starAuthorized
                        ? widget.onThemeModeChanged
                        : null,
                  ),
                ),
              ),
            ),
            _SettingRow(
              icon: LucideIcons.bell,
              title: '后台通知',
              subtitle: '任务完成或发生错误时提醒',
              enabled: widget.starAuthorized,
              customTrailing: IgnorePointer(
                ignoring: !widget.starAuthorized,
                child: Opacity(
                  opacity: widget.starAuthorized ? 1 : .45,
                  child: NkasSwitch(
                    label: '后台通知',
                    value: widget.notifications,
                    onChanged: widget.starAuthorized
                        ? widget.onNotificationsChanged
                        : null,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Surface(
          padding: EdgeInsets.zero,
          child: _SettingRow(
            icon: LucideIcons.info,
            title: '关于',
            subtitle: '版本、项目链接与运行信息',
            onTap: widget.onOpenAbout,
          ),
        ),
      ],
    );
  }

  Future<void> _openWebUi(BuildContext context) async {
    if (widget.connectionController.state.phase != ConnectionPhase.connected) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先连接后端')));
      return;
    }
    final opened = await launchUrl(
      widget.connectionController.webUiUri,
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开原始 WebUI')));
    }
  }
}

class _UpdateSettingRow extends StatefulWidget {
  const _UpdateSettingRow({
    required this.connectionController,
    required this.enabled,
    required this.onTap,
  });

  final ConnectionController connectionController;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_UpdateSettingRow> createState() => _UpdateSettingRowState();
}

class _UpdateSettingRowState extends State<_UpdateSettingRow> {
  String? error;
  String? loadedBaseUrl;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    widget.connectionController.addListener(_connectionChanged);
    _connectionChanged();
  }

  @override
  void dispose() {
    widget.connectionController.removeListener(_connectionChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _UpdateSettingRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connectionController != widget.connectionController ||
        oldWidget.enabled != widget.enabled) {
      _connectionChanged();
    }
  }

  void _connectionChanged() {
    if (!mounted) return;
    setState(() {});
    final connection = widget.connectionController.state;
    if (!widget.enabled ||
        connection.phase != ConnectionPhase.connected ||
        loadedBaseUrl == connection.baseUrl ||
        _loading) {
      return;
    }
    // 控制器连接成功后已预取更新状态，直接复用
    final info = widget.connectionController.updateInfo;
    if (info != null) {
      loadedBaseUrl = connection.baseUrl;
      error = info.error;
      return;
    }
    unawaited(_load());
  }

  Future<void> _load() async {
    if (!widget.enabled) return;
    _loading = true;
    final baseUrl = widget.connectionController.state.baseUrl;
    try {
      await widget.connectionController.refreshUpdateInfo();
      if (!mounted || widget.connectionController.state.baseUrl != baseUrl) {
        return;
      }
      setState(() {
        error = widget.connectionController.updateInfo?.error;
        loadedBaseUrl = baseUrl;
      });
    } catch (exception) {
      if (mounted) setState(() => error = exception.toString());
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected =
        widget.connectionController.state.phase == ConnectionPhase.connected;
    return _SettingRow(
      icon: LucideIcons.squareArrowUp,
      title: '更新',
      subtitle: _subtitle(connected),
      badge: widget.connectionController.updateAvailable,
      enabled: widget.enabled && connected,
      onTap: widget.enabled && connected ? widget.onTap : null,
    );
  }

  String _subtitle(bool connected) {
    if (!connected) return '连接后端后检查源码版本';
    if (error != null && error!.isNotEmpty) return error!;
    final current = widget.connectionController.state.status?.version;
    final state =
        widget.connectionController.updateInfo?.stateLabel ?? '检查源码的新版本';
    return current == null ? state : '当前 $current · $state';
  }
}

class _SettingGroup extends StatelessWidget {
  const _SettingGroup({required this.label, required this.rows});
  final String label;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GroupLabel(label),
        Surface(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                rows[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.title,
    required this.subtitle,
    this.icon,
    this.iconColor,
    this.trailing,
    this.customTrailing,
    this.onTap,
    this.enabled = true,
    this.badge = false,
  });
  final IconData? icon;
  final Color? iconColor;
  final String title;
  final String subtitle;
  final IconData? trailing;
  final Widget? customTrailing;
  final VoidCallback? onTap;
  final bool enabled;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          children: [
            if (icon != null) ...[
              IconBox(
                icon: icon!,
                color: iconColor ?? theme.colorScheme.success,
              ),
              const SizedBox(width: 11),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.muted,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (badge) ...[
              Container(
                key: const ValueKey('nkas-update-dot'),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: theme.colorScheme.destructive,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
            ],
            customTrailing ??
                Icon(
                  trailing ?? LucideIcons.chevronRight,
                  size: 15,
                  color: theme.colorScheme.mutedForeground,
                ),
          ],
        ),
      ),
    );
    final displayed = enabled ? content : Opacity(opacity: .45, child: content);
    if (onTap == null || !enabled) return displayed;
    return InkWell(onTap: onTap, child: displayed);
  }
}

class _ThemeSegment extends StatelessWidget {
  const _ThemeSegment({required this.themeMode, required this.onChanged});
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    const inset =
        (NkasActionStyle.minTapSize - NkasActionStyle.compactHeight) / 2;
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          top: inset,
          bottom: inset,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.input,
              border: Border.all(color: theme.colorScheme.border),
              borderRadius: NkasInputStyle.radius,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ThemeChoice(
                label: '浅色',
                selected: themeMode != ThemeMode.dark,
                onTap: onChanged == null
                    ? null
                    : () => onChanged!(ThemeMode.light),
              ),
              _ThemeChoice(
                label: '深色',
                selected: themeMode == ThemeMode.dark,
                onTap: onChanged == null
                    ? null
                    : () => onChanged!(ThemeMode.dark),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ThemeChoice extends StatelessWidget {
  const _ThemeChoice({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      enabled: onTap != null,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          backgroundColor: selected ? scheme.card : Colors.transparent,
          foregroundColor: selected ? scheme.primary : scheme.mutedForeground,
          disabledForegroundColor: scheme.mutedForeground,
          minimumSize: const Size(
            NkasActionStyle.minTapSize,
            NkasActionStyle.chipHeight,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          tapTargetSize: MaterialTapTargetSize.padded,
          visualDensity: VisualDensity.standard,
          textStyle: theme.textTheme.p.copyWith(
            fontFamily: theme.textTheme.family,
            fontSize: 12,
            height: 1.3,
            fontWeight: FontWeight.w600,
          ),
        ),
        child: Text(label),
      ),
    );
  }
}
