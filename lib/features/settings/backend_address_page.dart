import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile/core/api/backend_address.dart';
import 'package:nkas_mobile/core/connection/connection_controller.dart';
import 'package:nkas_mobile/core/platform/runtime_platform.dart';
import 'package:nkas_mobile/core/widgets/buttons.dart';
import 'package:nkas_mobile/core/widgets/floating_action.dart';
import 'package:nkas_mobile/core/widgets/form_field.dart';
import 'package:nkas_mobile/core/widgets/group_label.dart';
import 'package:nkas_mobile/core/widgets/page_inset.dart';
import 'package:nkas_mobile/core/widgets/page_subtitle.dart';
import 'package:nkas_mobile/core/widgets/surface.dart';
import 'package:nkas_mobile/core/widgets/tag.dart';
import 'package:nkas_mobile/theme.dart';

class BackendAddressPage extends StatefulWidget {
  const BackendAddressPage({
    required this.connectionController,
    required this.onClose,
    super.key,
  });

  final ConnectionController connectionController;
  final VoidCallback onClose;

  @override
  State<BackendAddressPage> createState() => _BackendAddressPageState();
}

class _BackendAddressPageState extends State<BackendAddressPage> {
  final form = GlobalKey<FormState>();
  late final TextEditingController address;
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    address = TextEditingController(
      text: widget.connectionController.state.baseUrl,
    )..addListener(_addressChanged);
  }

  void _addressChanged() => setState(() => error = null);

  @override
  void dispose() {
    address.removeListener(_addressChanged);
    address.dispose();
    super.dispose();
  }

  Future<void> _save({bool local = false}) async {
    if (saving || (!local && !form.currentState!.validate())) return;
    FocusScope.of(context).unfocus();
    setState(() {
      saving = true;
      error = null;
    });
    final connected = local
        ? await widget.connectionController.connectLocalDeployment()
        : await widget.connectionController.connect(
            address.text,
            persist: true,
          );
    if (!mounted) return;
    if (connected) {
      widget.onClose();
    } else {
      setState(() {
        saving = false;
        error =
            widget.connectionController.state.message ?? '无法连接后端，请检查地址和服务状态';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final inset = nkasPageInset(context);
    final theme = ShadTheme.of(context);
    final scheme = theme.colorScheme;
    return Stack(
      children: [
        Positioned.fill(
          child: Form(
            key: form,
            child: ListView(
              padding: EdgeInsets.fromLTRB(inset, 5, inset, 104),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                const PageSubtitle('配置后端服务地址与安全入口'),
                const GroupLabel('连接地址'),
                Surface(
                  child: NkasTextField(
                    label: '后端地址或完整安全入口',
                    description:
                        '未开启安全入口时填写服务地址；已开启时粘贴完整 /entry/ 入口。\n'
                        '例如 http://192.168.1.20:12271，公网建议使用 HTTPS。',
                    controller: address,
                    enabled: !saving,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.done,
                    hintText: 'http://127.0.0.1:12271',
                    errorText: error,
                    prefixIcon: const Icon(LucideIcons.server, size: 18),
                    suffixIcon: address.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: '清空地址',
                            icon: const Icon(LucideIcons.x, size: 18),
                            onPressed: saving ? null : address.clear,
                          ),
                    validator: (value) {
                      try {
                        BackendAddress.parse(value ?? '');
                        return null;
                      } on FormatException catch (exception) {
                        return exception.message;
                      }
                    },
                    onSubmitted: (_) => _save(),
                  ),
                ),
                const SizedBox(height: 20),
                const GroupLabel('当前连接'),
                ListenableBuilder(
                  listenable: widget.connectionController,
                  builder: (context, _) {
                    final state = widget.connectionController.state;
                    final backendVersion = state.status?.version;
                    final valueStyle = theme.textTheme.muted.copyWith(
                      height: 1.5,
                    );
                    final color = switch (state.phase) {
                      ConnectionPhase.connected => scheme.success,
                      ConnectionPhase.connecting => scheme.primary,
                      ConnectionPhase.disconnected => scheme.destructive,
                      ConnectionPhase.incompatible => scheme.warning,
                    };
                    return Surface(
                      padding: EdgeInsets.zero,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _ConnectionInfoRow(
                            label: '连接状态',
                            value: Tag(label: state.label, color: color),
                          ),
                          const Divider(height: 1),
                          _ConnectionInfoRow(
                            label: '服务地址',
                            crossAxisAlignment: CrossAxisAlignment.start,
                            value: SelectableText(
                              state.baseUrl,
                              textAlign: TextAlign.right,
                              style: valueStyle,
                            ),
                          ),
                          if (backendVersion != null) ...[
                            const Divider(height: 1),
                            _ConnectionInfoRow(
                              label: '后端版本',
                              value: Text(
                                backendVersion,
                                textAlign: TextAlign.right,
                                style: valueStyle,
                              ),
                            ),
                          ],
                          if (state.phase != ConnectionPhase.connected &&
                              state.message != null &&
                              error == null) ...[
                            const Divider(height: 1),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 11,
                              ),
                              child: Text(
                                state.message!,
                                style: theme.textTheme.muted.copyWith(
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
                if (isAndroid) ...[
                  const SizedBox(height: 20),
                  const GroupLabel('本机部署'),
                  Surface(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '已在本机初始化 NKAS 时，可自动读取 Termux 的服务地址与安全入口。',
                          style: theme.textTheme.muted.copyWith(height: 1.5),
                        ),
                        const SizedBox(height: 12),
                        SecondaryButton(
                          icon: LucideIcons.smartphone,
                          label: '使用本机 Termux 部署',
                          onPressed: saving ? null : () => _save(local: true),
                        ),
                      ],
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
              label: saving ? '连接中…' : '保存并连接',
              icon: LucideIcons.check,
              loading: saving,
              enabled: !saving,
              onPressed: () => _save(),
            ),
          ),
        ),
      ],
    );
  }
}

class _ConnectionInfoRow extends StatelessWidget {
  const _ConnectionInfoRow({
    required this.label,
    required this.value,
    this.crossAxisAlignment = CrossAxisAlignment.center,
  });

  final String label;
  final Widget value;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        crossAxisAlignment: crossAxisAlignment,
        children: [
          Text(
            label,
            style: theme.textTheme.p.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Align(alignment: Alignment.centerRight, child: value),
          ),
        ],
      ),
    );
  }
}
