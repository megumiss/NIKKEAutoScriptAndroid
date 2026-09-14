import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:nkas_mobile/core/connection/connection_controller.dart';
import 'package:nkas_mobile/core/widgets/buttons.dart';
import 'package:nkas_mobile/core/widgets/form_field.dart';

/// Private-key actions attached to the schema-rendered deployment checkbox.
class SecurityEntryActions extends StatefulWidget {
  const SecurityEntryActions({
    required this.controller,
    required this.onBusyChanged,
    this.disabled = false,
    super.key,
  });

  final ConnectionController controller;
  final ValueChanged<bool> onBusyChanged;
  final bool disabled;

  @override
  State<SecurityEntryActions> createState() => _SecurityEntryActionsState();
}

class _SecurityEntryActionsState extends State<SecurityEntryActions> {
  Map<String, dynamic>? entry;
  bool busy = true;
  bool reveal = false;
  String? error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load({bool regenerate = false}) async {
    setState(() {
      busy = true;
      error = null;
      reveal = false;
    });
    widget.onBusyChanged(true);
    try {
      final value = await widget.controller.securityEntry(
        regenerate: regenerate,
      );
      if (mounted) setState(() => entry = value);
    } catch (exception) {
      if (mounted) setState(() => error = exception.toString());
    } finally {
      if (mounted) {
        setState(() => busy = false);
        widget.onBusyChanged(false);
      }
    }
  }

  Future<void> _regenerate() async {
    if (busy || widget.disabled) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重新生成安全入口'),
        content: const Text('重新生成后，旧入口和其他客户端凭据将失效。当前 App 会自动保存新入口，后台任务不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    await _load(regenerate: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final path = entry?['entry_path'] as String?;
    final url = path == null ? '' : widget.controller.assetUri(path).toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (url.isNotEmpty) ...[
          NkasTextField(
            key: ValueKey(widget.controller.credentialRevision),
            label: '完整安全入口',
            description:
                '浏览器和远程 App 通用。远程访问时替换服务器 IP / 域名，保留完整 /entry/ 路径。入口等同凭据，请勿公开，公网建议使用 HTTPS。',
            initialValue: url,
            readOnly: true,
            obscureText: !reveal,
            suffixIcon: IconButton(
              tooltip: reveal ? '隐藏入口' : '显示入口',
              icon: Icon(
                reveal ? LucideIcons.eyeOff : LucideIcons.eye,
                size: 18,
              ),
              onPressed: busy || widget.disabled
                  ? null
                  : () => setState(() => reveal = !reveal),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              PrimaryButton(
                icon: LucideIcons.copy,
                label: '复制入口',
                onPressed: busy || widget.disabled
                    ? null
                    : () async {
                        await Clipboard.setData(ClipboardData(text: url));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('完整入口已复制，请勿公开分享')),
                        );
                      },
              ),
              SecondaryButton(
                icon: LucideIcons.refreshCw,
                label: '重新生成入口',
                onPressed: busy || widget.disabled ? null : _regenerate,
              ),
            ],
          ),
        ],
        if (busy) Text('正在读取安全入口…', style: theme.textTheme.muted),
        if (error != null) ...[
          Text(
            error!,
            style: theme.textTheme.muted.copyWith(
              color: theme.colorScheme.destructive,
            ),
          ),
          TextButton(
            onPressed: busy || widget.disabled ? null : _load,
            child: const Text('重试'),
          ),
        ],
      ],
    );
  }
}
