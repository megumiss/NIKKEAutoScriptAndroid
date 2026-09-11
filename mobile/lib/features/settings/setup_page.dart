import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile_preview/core/platform/nkas_platform.dart';
import 'package:nkas_mobile_preview/core/widgets/buttons.dart';
import 'package:nkas_mobile_preview/core/widgets/page_inset.dart';
import 'package:nkas_mobile_preview/core/widgets/page_subtitle.dart';
import 'package:nkas_mobile_preview/core/widgets/surface.dart';
import 'package:nkas_mobile_preview/theme.dart';

class NkasSetupPage extends StatefulWidget {
  const NkasSetupPage({required this.onOpenStar, super.key});

  final VoidCallback onOpenStar;

  @override
  State<NkasSetupPage> createState() => _NkasSetupPageState();
}

class _NkasSetupPageState extends State<NkasSetupPage> {
  SetupStatus status = const SetupStatus(
    authorized: false,
    termuxInstalled: false,
    runCommandPermission: false,
    wirelessDebug: false,
    serial: '',
  );
  StreamSubscription<NkasPlatformEvent>? subscription;
  Timer? refreshTimer;
  String output = '';
  String? error;
  bool loading = true;
  bool running = false;
  final serialController = TextEditingController();
  final expanded = <String>{
    'permission',
    'termux_setting',
    'wireless',
    'adb_device',
  };

  static const groups = <(String, List<String>)>[
    ('环境准备', ['termux', 'permission', 'termux_setting']),
    ('项目安装', ['tools', 'source', 'config', 'container', 'service']),
    ('设备连接', ['wireless', 'adb_device']),
  ];

  static const stepNames = <String, String>{
    'termux': 'Termux',
    'permission': 'Android 外部命令权限',
    'termux_setting': 'Termux 外部应用开关',
    'tools': 'Termux 工具',
    'source': 'NKAS 源码',
    'config': '项目配置',
    'container': '容器',
    'service': '容器服务',
    'wireless': '无线调试',
    'adb_device': 'ADB 设备连接',
  };

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    if (NkasPlatform.instance.supported) {
      subscription = NkasPlatform.instance.events.listen(_onEvent);
    }
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    unawaited(subscription?.cancel());
    serialController.dispose();
    super.dispose();
  }

  void _onEvent(NkasPlatformEvent event) {
    if (!mounted) return;
    switch (event) {
      case SetupOutputEvent(:final output, :final log):
        setState(() {
          this.output = output;
          if (log) running = true;
        });
      case SetupStateEvent(:final state, :final message):
        setState(() {
          running = state != 'ready' && state != 'failed';
          if (state == 'failed') error = message ?? '初始化失败';
          if (state == 'ready') output = '初始化完成';
        });
        if (state == 'ready' || state == 'failed') unawaited(_refresh());
      case TermuxDownloadEvent(:final progress, :final message, :final error):
        setState(() {
          output = message ?? '正在下载 Termux：$progress%';
          if (error != null) this.error = error;
        });
      case SetupSerialEvent(:final serial):
        serialController.text = serial.split(':').last;
        unawaited(_refresh());
      case StarAuthorizationEvent():
        unawaited(_refresh());
    }
  }

  Future<void> _refresh() async {
    try {
      final value = await NkasPlatform.instance.setupStatus();
      if (!mounted) return;
      serialController.text = value.serial.split(':').last;
      setState(() {
        status = value;
        loading = false;
      });
    } on Object catch (exception) {
      if (mounted) {
        setState(() {
          loading = false;
          error = exception.toString();
        });
      }
    }
  }

  Future<void> _start() async {
    setState(() {
      running = true;
      error = null;
      output = '';
    });
    try {
      await NkasPlatform.instance.startSetup();
      refreshTimer?.cancel();
      refreshTimer = Timer.periodic(
        const Duration(seconds: 4),
        (_) => _refresh(),
      );
    } on Object catch (exception) {
      if (mounted) {
        setState(() {
          running = false;
          error = exception.toString();
        });
      }
    }
  }

  Future<void> _pair() async {
    final serial = serialController.text.trim();
    if (serial.isNotEmpty) {
      await NkasPlatform.instance.setSerial('127.0.0.1:$serial');
    }
    try {
      await NkasPlatform.instance.pairDevice(
        serial: serial.isEmpty ? '' : '127.0.0.1:$serial',
      );
      if (mounted) _show('配对服务已启动，请在无线调试配对通知中输入配对码');
    } on Object catch (exception) {
      if (mounted) _show(exception.toString());
    }
  }

  void _show(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final inset = nkasPageInset(context);
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(inset, 5, inset, 20),
            children: [
              const PageSubtitle(
                '准备 Termux、NKAS 服务和本地 Web UI；请开启自启动、关联启动，并允许后台运行。',
              ),
              if (loading) const LinearProgressIndicator(minHeight: 2),
              for (final group in groups) ...[
                const SizedBox(height: 19),
                Text(group.$1, style: ShadTheme.of(context).textTheme.muted),
                const SizedBox(height: 8),
                Surface(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var index = 0; index < group.$2.length; index++) ...[
                        if (index > 0) const Divider(height: 1),
                        _setupStepRow(group.$2[index], index + 1),
                      ],
                    ],
                  ),
                ),
              ],
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(
                  error!,
                  style: TextStyle(
                    color: ShadTheme.of(context).colorScheme.destructive,
                  ),
                ),
              ],
            ],
          ),
        ),
        _SetupFooter(
          label: _actionLabel,
          icon: _actionIcon,
          enabled: !_actionDisabled,
          onPressed: _handleAction,
        ),
      ],
    );
  }

  Widget _setupStepRow(String key, int index) {
    final extra = _stepExtra(key);
    return _StepRow(
      index: index,
      title: stepNames[key]!,
      detail: _stepDetail(key),
      state: _stepState(key),
      expanded: extra != null && expanded.contains(key),
      extra: extra,
      onTap: extra == null
          ? () {}
          : () => setState(() {
              if (expanded.contains(key)) {
                expanded.remove(key);
              } else {
                expanded.add(key);
              }
            }),
    );
  }

  String get _actionLabel {
    if (!status.authorized) return '前往 Star 验证';
    if (!status.termuxInstalled) return '下载并安装 Termux';
    if (!status.runCommandPermission) return '授权 Termux 外部命令';
    if (!status.wirelessDebug) return '打开无线调试设置';
    if (running) return '正在安装…';
    if (status.initialized) return '重新检查';
    return '开始安装';
  }

  IconData get _actionIcon {
    if (!status.authorized) return LucideIcons.shieldCheck;
    if (!status.termuxInstalled) return LucideIcons.download;
    if (!status.runCommandPermission) return LucideIcons.shieldCheck;
    if (!status.wirelessDebug) return LucideIcons.settings2;
    if (running) return LucideIcons.loaderCircle;
    if (status.initialized) return LucideIcons.refreshCw;
    return LucideIcons.rocket;
  }

  bool get _actionDisabled =>
      running || (status.initialized && status.wirelessDebug);

  Future<void> _handleAction() async {
    if (!status.authorized) {
      widget.onOpenStar();
      return;
    }
    if (!status.termuxInstalled) return NkasPlatform.instance.downloadTermux();
    if (!status.runCommandPermission) {
      await NkasPlatform.instance.requestRunCommandPermission();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      return _refresh();
    }
    if (!status.wirelessDebug) {
      return NkasPlatform.instance.openWirelessSettings();
    }
    if (status.initialized) return _refresh();
    return _start();
  }

  String _stepState(String key) {
    if (key == 'termux') return status.termuxInstalled ? '已安装' : '待安装';
    if (key == 'permission') return status.runCommandPermission ? '已授权' : '待授权';
    if (key == 'wireless') return status.wirelessDebug ? '已开启' : '待开启';
    if (key == 'adb_device' && status.serial.isNotEmpty) return '已连接';
    if (status.artifacts[key] == true) return '已完成';
    if (!status.authorized &&
        const [
          'tools',
          'source',
          'config',
          'container',
          'service',
        ].contains(key)) {
      return '等待环境';
    }
    return switch (key) {
      'termux_setting' => '待设置',
      'tools' => '待安装',
      'source' => '待下载',
      'config' => '待配置',
      'container' => '待安装',
      'service' => '未运行',
      'adb_device' => '待连接',
      _ => '等待环境',
    };
  }

  String _stepDetail(String key) {
    if (key == 'adb_device' && status.serial.isNotEmpty) return status.serial;
    if (key == 'service' && status.artifacts[key] == true) return '服务已响应';
    return const {
      'termux': '官方 Termux 应用与运行环境',
      'permission': '系统权限：Run commands in Termux environment',
      'termux_setting': 'Termux 配置 allow-external-apps=true',
      'tools': '安装 bash、git、adb、curl 等工具',
      'source': '下载并更新项目文件',
      'config': '写入本地设备和 Web UI 配置',
      'container': '安装包含 Python 运行环境的 NKAS 容器',
      'service': '启动本地服务和 Web UI',
      'wireless': '开启并检查 Android 无线调试',
      'adb_device': 'Termux 中必须能看到状态为 device 的设备',
    }[key]!;
  }

  Widget? _stepExtra(String key) {
    final scheme = ShadTheme.of(context).colorScheme;
    switch (key) {
      case 'permission':
        return _ExtraPanel(
          text:
              '部分系统不会弹出授权框，需要在系统设置中手动允许 NKAS 使用 Run commands in Termux environment。',
          child: SecondaryButton(
            icon: LucideIcons.settings2,
            label: '打开应用权限设置',
            onPressed: () async {
              await NkasPlatform.instance.requestRunCommandPermission();
              await Future<void>.delayed(const Duration(milliseconds: 500));
              await _refresh();
            },
          ),
        );
      case 'termux_setting':
        return _ExtraPanel(
          text: '在 Termux 中执行以下命令，然后完全退出并重新打开 Termux。页面会根据实际配置自动更新状态。',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                "mkdir -p ~/.termux\necho 'allow-external-apps=true' > ~/.termux/termux.properties",
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  height: 1.55,
                  color: scheme.foreground,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: SecondaryButton(
                      icon: LucideIcons.terminal,
                      label: '打开 Termux',
                      onPressed: NkasPlatform.instance.openTermux,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: SecondaryButton(
                      icon: LucideIcons.copy,
                      label: '复制命令',
                      onPressed: () async {
                        await Clipboard.setData(
                          const ClipboardData(
                            text:
                                "mkdir -p ~/.termux\necho 'allow-external-apps=true' > ~/.termux/termux.properties",
                          ),
                        );
                        if (mounted) _show('命令已复制');
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      case 'wireless':
        return _ExtraPanel(
          text: '请在 Android 系统设置中开启无线调试，随后返回此页面继续。',
          child: SecondaryButton(
            icon: LucideIcons.settings2,
            label: '打开无线调试设置',
            onPressed: NkasPlatform.instance.openWirelessSettings,
          ),
        );
      case 'adb_device':
        return _ExtraPanel(
          text:
              '初始化需要配对一次：\n1. 点击下方“配对”按钮\n2. 在无线调试里打开“使用配对码配对”\n3. 在弹出的通知中输入配对码',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: serialController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        hintText: '无线调试端口',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SecondaryButton(
                    icon: LucideIcons.link,
                    label: '配对',
                    onPressed: _pair,
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                '本机无线调试端口通常会自动发现，也可以填写设置页面显示的端口号。',
                style: ShadTheme.of(context).textTheme.muted,
              ),
            ],
          ),
        );
      default:
        if (running && output.isNotEmpty) {
          return _ExtraPanel(text: output, monospace: true);
        }
        return null;
    }
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.index,
    required this.title,
    required this.detail,
    required this.state,
    required this.expanded,
    required this.extra,
    required this.onTap,
  });

  final int index;
  final String title;
  final String detail;
  final String state;
  final bool expanded;
  final Widget? extra;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = ShadTheme.of(context).colorScheme;
    final done = const ['已完成', '已安装', '已授权', '已开启', '已连接'].contains(state);
    final active = state == '执行中';
    final row = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 61),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: done
                        ? scheme.success.withValues(alpha: .11)
                        : active
                        ? scheme.accentSoft
                        : scheme.secondary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: done
                      ? Icon(LucideIcons.check, size: 14, color: scheme.success)
                      : Text(
                          '$index',
                          style: TextStyle(
                            color: active
                                ? scheme.primary
                                : scheme.mutedForeground,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: scheme.mutedForeground,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  state,
                  style: TextStyle(
                    color: done
                        ? scheme.success
                        : active
                        ? scheme.primary
                        : scheme.mutedForeground,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 7),
                Icon(
                  expanded ? LucideIcons.chevronDown : LucideIcons.chevronRight,
                  size: 15,
                  color: scheme.mutedForeground,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (extra == null || !expanded) return row;
    return Column(children: [row, extra!]);
  }
}

class _ExtraPanel extends StatelessWidget {
  const _ExtraPanel({required this.text, this.child, this.monospace = false});

  final String text;
  final Widget? child;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    final scheme = ShadTheme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(48, 10, 12, 12),
      decoration: BoxDecoration(
        color: scheme.secondary,
        border: Border(top: BorderSide(color: scheme.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: monospace
                ? const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    height: 1.55,
                  )
                : ShadTheme.of(context).textTheme.muted,
          ),
          if (child != null) ...[const SizedBox(height: 8), child!],
        ],
      ),
    );
  }
}

class _SetupFooter extends StatelessWidget {
  const _SetupFooter({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final inset = nkasPageInset(context);
    return Container(
      padding: EdgeInsets.fromLTRB(inset, 12, inset, 15),
      decoration: BoxDecoration(
        color: ShadTheme.of(context).colorScheme.background,
        border: Border(
          top: BorderSide(color: ShadTheme.of(context).colorScheme.border),
        ),
      ),
      child: SizedBox(
        width: double.infinity,
        child: PrimaryButton(
          icon: icon,
          label: label,
          onPressed: enabled ? onPressed : null,
        ),
      ),
    );
  }
}
