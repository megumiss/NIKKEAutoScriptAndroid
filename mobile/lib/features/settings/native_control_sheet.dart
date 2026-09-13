import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile/core/platform/native_control_settings.dart';
import 'package:nkas_mobile/core/platform/nkas_platform.dart';
import 'package:nkas_mobile/core/platform/runtime_platform.dart';

Future<bool> showNativeControlSettings(
  BuildContext context, {
  NkasPlatform? platform,
}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) =>
          _NativeControlSheet(platform: platform ?? NkasPlatform.instance),
    ) ??
    false;

class _NativeControlSheet extends StatefulWidget {
  const _NativeControlSheet({required this.platform});
  final NkasPlatform platform;
  @override
  State<_NativeControlSheet> createState() => _NativeControlSheetState();
}

class _NativeControlSheetState extends State<_NativeControlSheet> {
  final endpoint = TextEditingController();
  final hostname = TextEditingController();
  final authKey = TextEditingController();
  final form = GlobalKey<FormState>();
  NativeControlMode mode = NativeControlMode.remoteAdb;
  bool tailscale = false;
  bool loading = true;
  bool busy = false;
  String? error;
  String? message;
  TsnetStatus status = const TsnetStatus();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final values = await widget.platform.nativeControlSettings();
      final state = await widget.platform.tsnetStatus();
      if (!mounted) return;
      setState(() {
        endpoint.text = values.endpoint;
        hostname.text = values.hostname;
        mode = values.mode;
        tailscale = values.tailscaleEnabled;
        status = state;
      });
    } catch (exception) {
      if (mounted) setState(() => error = _message(exception));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    endpoint.dispose();
    hostname.dispose();
    authKey.dispose();
    super.dispose();
  }

  NativeControlSettings get values => NativeControlSettings(
    mode: mode,
    endpoint: endpoint.text.trim(),
    hostname: hostname.text.trim(),
    tailscaleEnabled: tailscale,
  );

  Future<void> _save({bool register = false}) async {
    if (!form.currentState!.validate() || busy) return;
    final useTailnet = tailscale && mode == NativeControlMode.remoteAdb;
    if (useTailnet &&
        !status.hasPersistedLogin &&
        authKey.text.trim().isEmpty) {
      setState(() => error = '首次连接请填写 Tailscale AuthKey');
      return;
    }
    setState(() {
      busy = true;
      error = null;
      message = null;
    });
    final key = authKey.text.trim();
    authKey.clear();
    try {
      await widget.platform.saveNativeControlSettings(values);
      if (useTailnet && (register || key.isNotEmpty)) {
        try {
          await widget.platform.tsnetConfigure(key);
          status = await widget.platform.tsnetConnect();
        } finally {
          await widget.platform.tsnetClose();
        }
        status = await widget.platform.tsnetStatus();
      }
      if (!mounted) return;
      setState(() {
        busy = false;
        message = 'Tailscale 身份已保存，可连接设备';
      });
      if (!register) Navigator.pop(context, true);
    } catch (exception) {
      if (mounted) {
        setState(() {
          busy = false;
          error = _message(exception);
        });
      }
    }
  }

  Future<void> _clearState() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除 Tailscale 身份'),
        content: const Text('当前连接将断开，下次注册需要新的 AuthKey。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      busy = true;
      error = null;
      message = null;
    });
    authKey.clear();
    try {
      await widget.platform.tsnetClearState();
      final value = await widget.platform.tsnetStatus();
      if (mounted) {
        setState(() {
          status = value;
          message = '身份已清除';
        });
      }
    } catch (exception) {
      if (mounted) setState(() => error = _message(exception));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _cancelConnection() async {
    try {
      await widget.platform.tsnetClose();
    } catch (exception) {
      if (mounted) setState(() => error = _message(exception));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return PopScope(
      canPop: !busy,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 20,
          ),
          child: Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('控制连接', style: theme.textTheme.h3),
                const SizedBox(height: 12),
                if (loading)
                  const LinearProgressIndicator()
                else ...[
                  if (isAndroid) ...[
                    DropdownButtonFormField<NativeControlMode>(
                      initialValue: mode,
                      decoration: const InputDecoration(labelText: '控制设备'),
                      items: const [
                        DropdownMenuItem(
                          value: NativeControlMode.remoteAdb,
                          child: Text('远程 Android'),
                        ),
                        DropdownMenuItem(
                          value: NativeControlMode.localVirtualDisplay,
                          child: Text('本机虚拟屏幕'),
                        ),
                      ],
                      onChanged: busy
                          ? null
                          : (value) => setState(() => mode = value!),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (mode == NativeControlMode.remoteAdb) ...[
                    TextFormField(
                      controller: endpoint,
                      enabled: !busy,
                      decoration: const InputDecoration(
                        labelText: 'Android ADB 地址',
                        hintText: '设备地址:5555',
                        helperText: '支持 host:port 和 adb://host:port',
                      ),
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      validator: (value) {
                        final text = value?.trim() ?? '';
                        final uri = Uri.tryParse(
                          text.startsWith('adb://') ? text : 'adb://$text',
                        );
                        if (uri == null ||
                            uri.scheme != 'adb' ||
                            uri.host.isEmpty ||
                            !uri.hasPort ||
                            uri.port < 1 ||
                            uri.port > 65535 ||
                            uri.userInfo.isNotEmpty ||
                            uri.path.isNotEmpty ||
                            uri.hasQuery ||
                            uri.hasFragment) {
                          return '请输入有效的设备地址和端口';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('通过 Tailscale 连接'),
                      subtitle: const Text('访问 tailnet 中的设备，仅影响当前应用'),
                      value: tailscale,
                      onChanged: busy
                          ? null
                          : (value) => setState(() => tailscale = value),
                    ),
                    if (tailscale) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: hostname,
                        enabled: !busy,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Tailscale 节点名称',
                        ),
                        validator: (value) =>
                            RegExp(
                              r'^[A-Za-z0-9][A-Za-z0-9-]{0,62}$',
                            ).hasMatch(value?.trim() ?? '')
                            ? null
                            : '使用字母、数字和连字符，最多 63 个字符',
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: authKey,
                        enabled: !busy,
                        obscureText: true,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: const InputDecoration(
                          labelText: 'Tailscale AuthKey',
                          helperText: '首次注册时填写，注册后可留空',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        status.hasPersistedLogin ? '节点已注册' : '节点尚未注册',
                        style: theme.textTheme.muted,
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: busy
                                ? null
                                : () => _save(register: true),
                            child: const Text('验证连接'),
                          ),
                          TextButton(
                            onPressed: busy || !status.hasPersistedLogin
                                ? null
                                : _clearState,
                            child: const Text('清除身份'),
                          ),
                        ],
                      ),
                    ],
                  ] else
                    const Text('使用已完成无线调试配对的本机，创建独立虚拟屏幕。可在“初始化 NKAS”中完成配对。'),
                  if (busy)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: LinearProgressIndicator(),
                    ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        error!,
                        style: TextStyle(color: theme.colorScheme.destructive),
                      ),
                    ),
                  if (message != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(message!),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: busy
                              ? null
                              : () => Navigator.pop(context, false),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 48),
                          ),
                          child: const Text('关闭'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: busy ? null : () => _save(),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 48),
                          ),
                          child: const Text('保存'),
                        ),
                      ),
                    ],
                  ),
                  if (busy)
                    TextButton(
                      onPressed: _cancelConnection,
                      child: const Text('取消连接'),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _message(Object error) =>
      error is PlatformException ? error.message ?? '连接失败' : error.toString();
}
