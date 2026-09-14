import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile/core/platform/native_control_settings.dart';
import 'package:nkas_mobile/core/platform/nkas_platform.dart';
import 'package:nkas_mobile/core/platform/runtime_platform.dart';
import 'package:nkas_mobile/core/widgets/buttons.dart';
import 'package:nkas_mobile/core/widgets/field_select.dart';
import 'package:nkas_mobile/core/widgets/floating_action.dart';
import 'package:nkas_mobile/core/widgets/form_field.dart';
import 'package:nkas_mobile/core/widgets/group_label.dart';
import 'package:nkas_mobile/core/widgets/page_inset.dart';
import 'package:nkas_mobile/core/widgets/page_subtitle.dart';
import 'package:nkas_mobile/core/widgets/surface.dart';
import 'package:nkas_mobile/core/widgets/toggle.dart';

class NativeControlPage extends StatefulWidget {
  const NativeControlPage({required this.platform, this.onClose, super.key});
  final NkasPlatform platform;

  /// 保存成功后由 shell 返回上一页
  final VoidCallback? onClose;
  @override
  State<NativeControlPage> createState() => _NativeControlPageState();
}

class _NativeControlPageState extends State<NativeControlPage> {
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
      if (!register) widget.onClose?.call();
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
    final inset = nkasPageInset(context);
    return Stack(
      children: [
        Positioned.fill(
          child: Form(
            key: form,
            child: ListView(
              padding: EdgeInsets.fromLTRB(inset, 5, inset, 92),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                PageSubtitle(
                  isAndroid
                      ? '远程 Android、本机虚拟屏幕与 Tailscale'
                      : '远程 Android 与 Tailscale',
                ),
                if (loading || busy)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                if (!loading) ...[
                  if (isAndroid) ...[
                    const GroupLabel('控制设备'),
                    Surface(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FieldSelect(
                            label: '设备类型',
                            value: mode == NativeControlMode.remoteAdb
                                ? '远程 Android'
                                : '本机虚拟屏幕',
                            selectedValue: mode == NativeControlMode.remoteAdb
                                ? 'remote_adb'
                                : 'local_virtual_display',
                            options: const [
                              FieldSelectOption('remote_adb', '远程 Android'),
                              FieldSelectOption(
                                'local_virtual_display',
                                '本机虚拟屏幕',
                              ),
                            ],
                            onChanged: busy
                                ? null
                                : (value) => setState(
                                    () =>
                                        mode = value == 'local_virtual_display'
                                        ? NativeControlMode.localVirtualDisplay
                                        : NativeControlMode.remoteAdb,
                                  ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  if (mode == NativeControlMode.remoteAdb) ...[
                    const GroupLabel('远程设备'),
                    Surface(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          NkasTextField(
                            label: 'Android ADB 地址',
                            description: '支持 host:port 和 adb://host:port',
                            controller: endpoint,
                            enabled: !busy,
                            hintText: '设备地址:5555',
                            keyboardType: TextInputType.url,
                            autocorrect: false,
                            validator: (value) {
                              final text = value?.trim() ?? '';
                              final uri = Uri.tryParse(
                                text.startsWith('adb://')
                                    ? text
                                    : 'adb://$text',
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
                          const Divider(height: 18),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: busy
                                ? null
                                : () => setState(() => tailscale = !tailscale),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        '通过 Tailscale 连接',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        '访问 tailnet 中的设备，仅影响当前应用',
                                        style: theme.textTheme.muted,
                                      ),
                                    ],
                                  ),
                                ),
                                NkasSwitch(
                                  label: '通过 Tailscale 连接',
                                  value: tailscale,
                                  onChanged: busy
                                      ? null
                                      : (value) =>
                                            setState(() => tailscale = value),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (tailscale) ...[
                      const SizedBox(height: 20),
                      const GroupLabel('Tailscale'),
                      Surface(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            NkasTextField(
                              label: 'Tailscale 节点名称',
                              controller: hostname,
                              enabled: !busy,
                              autocorrect: false,
                              validator: (value) =>
                                  RegExp(
                                    r'^[A-Za-z0-9][A-Za-z0-9-]{0,62}$',
                                  ).hasMatch(value?.trim() ?? '')
                                  ? null
                                  : '使用字母、数字和连字符，最多 63 个字符',
                            ),
                            const Divider(height: 18),
                            NkasTextField(
                              label: 'Tailscale AuthKey',
                              description:
                                  '用于将本应用注册到目标设备所在的 Tailscale 网络。\n'
                                  '在 Tailscale 管理后台 Settings → Keys → Generate auth key 创建，密钥以 tskey-auth- 开头。\n'
                                  '首次注册或清除身份后填写；注册后可留空，密钥不会保存到设置。',
                              controller: authKey,
                              enabled: !busy,
                              obscureText: true,
                              autocorrect: false,
                              enableSuggestions: false,
                              validator: (value) =>
                                  !busy &&
                                      !status.hasPersistedLogin &&
                                      (value?.trim().isEmpty ?? true)
                                  ? '首次连接请填写 Tailscale AuthKey'
                                  : null,
                            ),
                            const Divider(height: 18),
                            Text(
                              status.hasPersistedLogin
                                  ? (status.hostname.isEmpty
                                        ? '节点名称暂不可用'
                                        : status.hostname)
                                  : '节点尚未注册',
                              style: theme.textTheme.muted,
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: SecondaryButton(
                                    icon: LucideIcons.plug,
                                    label: '验证连接',
                                    onPressed: busy
                                        ? null
                                        : () => _save(register: true),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: SecondaryButton(
                                    icon: LucideIcons.trash2,
                                    label: '清除身份',
                                    onPressed: busy || !status.hasPersistedLogin
                                        ? null
                                        : _clearState,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ] else
                    Surface(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        '使用已完成无线调试配对的本机，创建独立虚拟屏幕。可在“初始化 NKAS”中完成配对。',
                        style: theme.textTheme.muted,
                      ),
                    ),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      error!,
                      style: TextStyle(color: theme.colorScheme.destructive),
                    ),
                  ],
                  if (message != null) ...[
                    const SizedBox(height: 12),
                    Text(message!, style: theme.textTheme.muted),
                  ],
                  if (busy)
                    Center(
                      child: TextButton(
                        onPressed: _cancelConnection,
                        child: const Text('取消连接'),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
        Positioned(
          left: inset,
          right: inset,
          bottom: 12,
          child: SafeArea(
            top: false,
            child: NkasFloatingAction(
              label: busy ? '正在保存…' : '保存',
              icon: LucideIcons.check,
              loading: busy,
              enabled: !busy && !loading,
              onPressed: () => _save(),
            ),
          ),
        ),
      ],
    );
  }

  String _message(Object error) =>
      error is PlatformException ? error.message ?? '连接失败' : error.toString();
}
