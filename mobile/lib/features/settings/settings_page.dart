import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:nkas_mobile/core/api/update_info.dart';
import 'package:nkas_mobile/core/widgets/icon_box.dart';
import 'package:nkas_mobile/core/connection/connection_controller.dart';
import 'package:nkas_mobile/core/platform/nkas_platform.dart';
import 'package:nkas_mobile/core/platform/runtime_platform.dart';
import 'package:nkas_mobile/core/widgets/buttons.dart';
import 'package:nkas_mobile/core/widgets/page_inset.dart';
import 'package:nkas_mobile/core/widgets/page_subtitle.dart';
import 'package:nkas_mobile/core/widgets/surface.dart';
import 'package:nkas_mobile/theme.dart';
import 'package:nkas_mobile/features/settings/native_control_page.dart';

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
              trailing: LucideIcons.pencil,
              enabled: widget.starAuthorized,
              onTap: widget.starAuthorized
                  ? () => _editBackendAddress(context)
                  : null,
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
                    ? () => openNativeControlSettings(context)
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
                    onChanged: widget.onThemeModeChanged,
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
                  child: _SettingsSwitch(
                    label: '后台通知',
                    value: widget.notifications,
                    onChanged: widget.onNotificationsChanged,
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

  Future<void> _editBackendAddress(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => _BackendAddressSheet(
        connectionController: widget.connectionController,
      ),
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
  UpdateInfo? info;
  String? error;
  String? loadedBaseUrl;

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
    final connection = widget.connectionController.state;
    if (widget.enabled &&
        connection.phase == ConnectionPhase.connected &&
        loadedBaseUrl != connection.baseUrl) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    if (!widget.enabled) return;
    final baseUrl = widget.connectionController.state.baseUrl;
    try {
      final value = await widget.connectionController.fetchUpdateInfo();
      if (!mounted || widget.connectionController.state.baseUrl != baseUrl) {
        return;
      }
      setState(() {
        info = value;
        error = value.error;
        loadedBaseUrl = baseUrl;
      });
    } catch (exception) {
      if (mounted) setState(() => error = exception.toString());
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
      enabled: widget.enabled && connected,
      onTap: widget.enabled && connected ? widget.onTap : null,
    );
  }

  String _subtitle(bool connected) {
    if (!connected) return '连接后端后检查源码版本';
    if (error != null && error!.isNotEmpty) return error!;
    final current = widget.connectionController.state.status?.version;
    final state = info?.stateLabel ?? '检查源码的新版本';
    return current == null ? state : '当前 $current · $state';
  }
}

class _BackendAddressSheet extends StatefulWidget {
  const _BackendAddressSheet({required this.connectionController});

  final ConnectionController connectionController;

  @override
  State<_BackendAddressSheet> createState() => _BackendAddressSheetState();
}

class _BackendAddressSheetState extends State<_BackendAddressSheet> {
  late final TextEditingController _textController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(
      text: widget.connectionController.state.baseUrl,
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final connected = await widget.connectionController.connect(
      _textController.text,
      persist: true,
    );
    if (!mounted) return;
    if (connected) {
      Navigator.pop(context);
    } else {
      setState(() => _saving = false);
      final message = widget.connectionController.state.message;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message ?? '无法连接后端，请检查地址和服务状态')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.connectionController.state;
    final scheme = ShadTheme.of(context).colorScheme;
    final error =
        state.phase == ConnectionPhase.disconnected ||
        state.phase == ConnectionPhase.incompatible;
    final inset = nkasPageInset(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        inset,
        0,
        inset,
        MediaQuery.viewInsetsOf(context).bottom + 18,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('修改后端地址', style: ShadTheme.of(context).textTheme.h3),
          const SizedBox(height: 6),
          Text(
            '支持本机或远程 NKAS 后端，例如 http://192.168.1.20:12271。',
            style: ShadTheme.of(context).textTheme.muted,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _textController,
            enabled: !_saving,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              hintText: 'http://127.0.0.1:12271',
              border: OutlineInputBorder(),
              suffixIcon: _textController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清空地址',
                      icon: const Icon(LucideIcons.x, size: 17),
                      onPressed: _saving ? null : _textController.clear,
                    ),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: _saving ? null : (_) => _save(),
          ),
          const SizedBox(height: 10),
          Text(
            state.message ?? '远程地址仅用于本机或可信网络',
            style: ShadTheme.of(context).textTheme.muted.copyWith(
              color: error ? scheme.destructive : null,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  icon: LucideIcons.x,
                  label: '取消',
                  onPressed: _saving ? null : () => Navigator.pop(context),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: PrimaryButton(
                  icon: LucideIcons.check,
                  label: _saving ? '连接中…' : '保存并连接',
                  onPressed: _saving ? null : _save,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingGroup extends StatelessWidget {
  const _SettingGroup({required this.label, required this.rows});
  final String label;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 3, bottom: 8),
          child: Text(label, style: theme.textTheme.muted),
        ),
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
  });
  final IconData? icon;
  final Color? iconColor;
  final String title;
  final String subtitle;
  final IconData? trailing;
  final Widget? customTrailing;
  final VoidCallback? onTap;
  final bool enabled;

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
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Container(
      height: 34,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          _ThemeChoice(
            label: '浅色',
            selected: themeMode != ThemeMode.dark,
            onTap: () => onChanged(ThemeMode.light),
          ),
          _ThemeChoice(
            label: '深色',
            selected: themeMode == ThemeMode.dark,
            onTap: () => onChanged(ThemeMode.dark),
          ),
        ],
      ),
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
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.card : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.mutedForeground,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _SettingsSwitch extends StatelessWidget {
  const _SettingsSwitch({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = ShadTheme.of(context).colorScheme;
    return Semantics(
      button: true,
      toggled: value,
      label: '$label，${value ? '已开启' : '已关闭'}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!value),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 42,
              height: 24,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: value ? scheme.primary : scheme.border,
                borderRadius: BorderRadius.circular(999),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 150),
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: Color(0x24000000), blurRadius: 3),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
