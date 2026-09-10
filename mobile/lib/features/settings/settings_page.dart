import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:nkas_mobile_preview/core/api/update_info.dart';
import 'package:nkas_mobile_preview/core/widgets/icon_box.dart';
import 'package:nkas_mobile_preview/core/connection/connection_controller.dart';
import 'package:nkas_mobile_preview/core/widgets/page_inset.dart';
import 'package:nkas_mobile_preview/core/widgets/page_subtitle.dart';
import 'package:nkas_mobile_preview/core/widgets/surface.dart';
import 'package:nkas_mobile_preview/theme.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    required this.themeMode,
    required this.connectionController,
    required this.notifications,
    required this.autoScroll,
    required this.onThemeModeChanged,
    required this.onNotificationsChanged,
    required this.onAutoScrollChanged,
    super.key,
  });
  final ThemeMode themeMode;
  final ConnectionController connectionController;
  final bool notifications;
  final bool autoScroll;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ValueChanged<bool> onNotificationsChanged;
  final ValueChanged<bool> onAutoScrollChanged;

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
            const _SettingRow(
              icon: LucideIcons.shieldCheck,
              title: 'STAR 验证',
              subtitle: '设备身份与授权状态 · 待验证',
            ),
            _SettingRow(
              icon: LucideIcons.sparkles,
              iconColor: warning,
              title: '初始化 NKAS',
              subtitle: '完成后才可以部署实例',
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
              subtitle: connectionController.state.baseUrl,
              trailing: LucideIcons.pencil,
              onTap: () => _editBackendAddress(context),
            ),
            _SettingRow(
              icon: LucideIcons.globe2,
              title: '原始 WebUI',
              subtitle: '打开完整控制台，使用更多高级功能',
              trailing: LucideIcons.externalLink,
              onTap: () => _openWebUi(context),
            ),
            _UpdateSettingRow(connectionController: connectionController),
          ],
        ),
        const SizedBox(height: 20),
        _SettingGroup(
          label: '外观与通知',
          rows: [
            _SettingRow(
              title: '主题',
              subtitle: '当前：${themeMode == ThemeMode.dark ? '深色' : '浅色'}',
              customTrailing: _ThemeSegment(
                themeMode: themeMode,
                onChanged: onThemeModeChanged,
              ),
            ),
            _SettingRow(
              title: '后台通知',
              subtitle: '任务完成或发生错误时提醒',
              customTrailing: Switch(
                value: notifications,
                onChanged: onNotificationsChanged,
              ),
            ),
            _SettingRow(
              title: '日志自动滚动',
              subtitle: '新日志到达时滚动到底部',
              customTrailing: Switch(
                value: autoScroll,
                onChanged: onAutoScrollChanged,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const _SettingGroup(
          label: '关于',
          rows: [
            _SettingRow(
              title: 'NKAS Mobile Preview',
              subtitle: 'Flutter + shadcn_ui · 0.1.0-preview',
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _editBackendAddress(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) =>
          _BackendAddressDialog(connectionController: connectionController),
    );
  }

  Future<void> _openWebUi(BuildContext context) async {
    if (connectionController.state.phase != ConnectionPhase.connected) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先连接后端')));
      return;
    }
    final opened = await launchUrl(
      connectionController.webUiUri,
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
  const _UpdateSettingRow({required this.connectionController});

  final ConnectionController connectionController;

  @override
  State<_UpdateSettingRow> createState() => _UpdateSettingRowState();
}

class _UpdateSettingRowState extends State<_UpdateSettingRow> {
  UpdateInfo? info;
  bool busy = false;
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

  void _connectionChanged() {
    final connection = widget.connectionController.state;
    if (connection.phase == ConnectionPhase.connected &&
        loadedBaseUrl != connection.baseUrl &&
        !busy) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
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
      if (value.checking || value.running) unawaited(_poll());
    } catch (exception) {
      if (mounted) setState(() => error = exception.toString());
    }
  }

  Future<void> _handleTap() async {
    if (busy ||
        widget.connectionController.state.phase != ConnectionPhase.connected) {
      return;
    }
    if (info?.available == true ||
        (info?.state == 'failed' && (info?.error?.isEmpty ?? true))) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('更新 NKAS 源码'),
          content: const Text('更新会等待当前任务结束，并可能短暂重启后端。确定继续？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('立即更新'),
            ),
          ],
        ),
      );
      if (confirmed == true) await _apply();
      return;
    }
    await _check();
  }

  Future<void> _check() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.connectionController.checkForUpdate();
      await _poll(maxRounds: 30);
    } catch (exception) {
      if (mounted) setState(() => error = exception.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _apply() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.connectionController.applyUpdate();
      await _poll(maxRounds: 300, tolerateConnectionErrors: true);
      if (!mounted) return;
      await widget.connectionController.connect(
        widget.connectionController.state.baseUrl,
      );
    } catch (exception) {
      if (mounted) setState(() => error = exception.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _poll({
    int maxRounds = 30,
    bool tolerateConnectionErrors = false,
  }) async {
    for (var round = 0; round < maxRounds && mounted; round++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      try {
        final value = await widget.connectionController.fetchUpdateInfo();
        if (!mounted) return;
        setState(() {
          info = value;
          error = value.error;
        });
        if (!value.checking && !value.running) return;
      } catch (exception) {
        if (!tolerateConnectionErrors) rethrow;
      }
    }
    if (mounted) setState(() => error = '更新状态等待超时');
  }

  @override
  Widget build(BuildContext context) {
    final connected =
        widget.connectionController.state.phase == ConnectionPhase.connected;
    return _SettingRow(
      icon: LucideIcons.squareArrowUp,
      title: '更新',
      subtitle: _subtitle(connected),
      trailing: info?.available == true
          ? LucideIcons.download
          : LucideIcons.refreshCw,
      onTap: connected && !busy ? _handleTap : null,
    );
  }

  String _subtitle(bool connected) {
    if (!connected) return '连接后端后检查源码版本';
    if (busy || info?.checking == true) return '正在检查或更新，请稍候…';
    if (error != null && error!.isNotEmpty) return error!;
    final current = widget.connectionController.state.status?.version;
    final state = info?.stateLabel ?? '检查源码的新版本';
    return current == null ? state : '当前 $current · $state';
  }
}

class _BackendAddressDialog extends StatefulWidget {
  const _BackendAddressDialog({required this.connectionController});

  final ConnectionController connectionController;

  @override
  State<_BackendAddressDialog> createState() => _BackendAddressDialogState();
}

class _BackendAddressDialogState extends State<_BackendAddressDialog> {
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.connectionController.state;
    final scheme = ShadTheme.of(context).colorScheme;
    final error =
        state.phase == ConnectionPhase.disconnected ||
        state.phase == ConnectionPhase.incompatible;
    return AlertDialog(
      title: const Text('后端地址'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _textController,
              enabled: !_saving,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                hintText: 'http://127.0.0.1:12271',
                border: OutlineInputBorder(),
              ),
              onSubmitted: _saving ? null : (_) => _save(),
            ),
            const SizedBox(height: 10),
            Text(
              state.message ?? '远程地址仅用于本机或可信网络',
              style: ShadTheme.of(context).textTheme.muted.copyWith(
                color: error ? scheme.destructive : null,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? '连接中…' : '保存并连接'),
        ),
      ],
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
  });
  final IconData? icon;
  final Color? iconColor;
  final String title;
  final String subtitle;
  final IconData? trailing;
  final Widget? customTrailing;
  final VoidCallback? onTap;

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
    if (onTap == null) return content;
    return InkWell(onTap: onTap, child: content);
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
