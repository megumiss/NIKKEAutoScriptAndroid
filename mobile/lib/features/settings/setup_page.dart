import 'dart:async';

import 'package:flutter/material.dart';
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

  static const _groups = <String, List<(String, String)>>{
    '环境准备': [
      ('termux', 'Termux'),
      ('permission', 'Android 外部命令权限'),
      ('termux_setting', 'Termux 外部应用开关'),
    ],
    '项目安装': [
      ('tools', 'Termux 工具'),
      ('source', 'NKAS 源码'),
      ('config', '项目配置'),
      ('container', '容器'),
      ('service', '容器服务'),
    ],
    '设备连接': [
      ('wireless', '无线调试'),
      ('adb_device', 'ADB 设备连接'),
    ],
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
      if (mounted) setState(() { loading = false; error = exception.toString(); });
    }
  }

  Future<void> _start() async {
    setState(() { running = true; error = null; output = ''; });
    try {
      await NkasPlatform.instance.startSetup();
      refreshTimer?.cancel();
      refreshTimer = Timer.periodic(const Duration(seconds: 4), (_) => _refresh());
    } on Object catch (exception) {
      if (mounted) setState(() { running = false; error = exception.toString(); });
    }
  }

  Future<void> _pair() async {
    final serial = serialController.text.trim();
    if (serial.isNotEmpty) {
      await NkasPlatform.instance.setSerial('127.0.0.1:$serial');
    }
    try {
      await NkasPlatform.instance.pairDevice(serial: serial.isEmpty ? '' : '127.0.0.1:$serial');
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
    final scheme = ShadTheme.of(context).colorScheme;
    return ListView(
      padding: EdgeInsets.fromLTRB(inset, 5, inset, 28),
      children: [
        const PageSubtitle('准备 Termux、NKAS 服务和本地 Web UI。'),
        if (!status.authorized)
          _Notice(
            icon: LucideIcons.shieldAlert,
            text: '初始化前需要先完成 STAR 验证。',
            action: '前往验证',
            onPressed: widget.onOpenStar,
          ),
        if (loading) const LinearProgressIndicator(minHeight: 2),
        for (final entry in _groups.entries) ...[
          const SizedBox(height: 18),
          Text(entry.key, style: ShadTheme.of(context).textTheme.muted),
          const SizedBox(height: 8),
          Surface(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var index = 0; index < entry.value.length; index++) ...[
                  if (index > 0) const Divider(height: 1),
                  _StepRow(
                    title: entry.value[index].$2,
                    state: _stepState(entry.value[index].$1),
                    detail: _stepDetail(entry.value[index].$1),
                  ),
                  if (entry.value[index].$1 == 'adb_device')
                    _DeviceControls(
                      serialController: serialController,
                      onPair: _pair,
                    ),
                ],
              ],
            ),
          ),
        ],
        if (output.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text('安装日志', style: ShadTheme.of(context).textTheme.muted),
          const SizedBox(height: 8),
          Surface(
            padding: const EdgeInsets.all(12),
            color: scheme.secondary,
            child: SelectableText(
              output,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11, height: 1.35),
              maxLines: 14,
            ),
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(error!, style: TextStyle(color: scheme.destructive)),
        ],
        const SizedBox(height: 20),
        PrimaryButton(
          icon: running ? LucideIcons.loaderCircle : LucideIcons.rocket,
          label: running ? '安装中' : status.initialized ? '重新检查' : '开始安装',
          onPressed: !status.authorized || running || !status.environmentReady
              ? (status.environmentReady ? null : null)
              : _start,
        ),
        if (!status.termuxInstalled && NkasPlatform.instance.supported) ...[
          const SizedBox(height: 8),
          SecondaryButton(
            icon: LucideIcons.download,
            label: '下载并安装 Termux',
            onPressed: () async {
              try {
                await NkasPlatform.instance.downloadTermux();
              } on Object catch (exception) {
                if (mounted) _show(exception.toString());
              }
            },
          ),
        ],
        if (!status.wirelessDebug && NkasPlatform.instance.supported) ...[
          const SizedBox(height: 8),
          SecondaryButton(
            icon: LucideIcons.settings2,
            label: '打开无线调试设置',
            onPressed: NkasPlatform.instance.openWirelessSettings,
          ),
        ],
      ],
    );
  }

  String _stepState(String key) {
    if (key == 'termux') return status.termuxInstalled ? '已安装' : '待安装';
    if (key == 'permission') return status.runCommandPermission ? '已授权' : '待授权';
    if (key == 'wireless') return status.wirelessDebug ? '已开启' : '待开启';
    if (status.artifacts[key] == true) return '已完成';
    return '等待环境';
  }

  String _stepDetail(String key) {
    if (key == 'adb_device' && status.serial.isNotEmpty) return status.serial;
    if (key == 'service' && status.artifacts[key] == true) return '服务已响应';
    return switch (key) {
      'termux' => '安装并允许外部命令',
      'permission' => '允许 Run commands in Termux environment',
      'termux_setting' => 'allow-external-apps=true',
      'tools' => 'bash、git、adb、curl 等工具',
      'source' => '下载并更新项目文件',
      'config' => '写入设备和 Web UI 配置',
      'container' => '安装 NKAS 运行容器',
      'service' => '启动本地服务和 Web UI',
      'wireless' => '开启 Android 无线调试',
      _ => 'Termux 中必须能看到状态为 device 的设备',
    };
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.title, required this.state, required this.detail});
  final String title;
  final String state;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final scheme = ShadTheme.of(context).colorScheme;
    final done = state == '已完成' || state == '已安装' || state == '已授权' || state == '已开启';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Icon(done ? LucideIcons.circleCheck : LucideIcons.circleDashed, color: done ? scheme.success : scheme.mutedForeground, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)), const SizedBox(height: 3), Text(detail, style: ShadTheme.of(context).textTheme.muted)])),
          Text(state, style: TextStyle(color: done ? scheme.success : scheme.mutedForeground, fontSize: 11)),
        ],
      ),
    );
  }
}

class _DeviceControls extends StatelessWidget {
  const _DeviceControls({required this.serialController, required this.onPair});
  final TextEditingController serialController;
  final VoidCallback onPair;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(42, 0, 14, 12),
      child: Row(
        children: [
          Expanded(child: TextField(controller: serialController, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: '无线调试端口', isDense: true, border: OutlineInputBorder()))),
          const SizedBox(width: 8),
          SecondaryButton(icon: LucideIcons.link, label: '配对', onPressed: onPair),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, required this.action, required this.onPressed});
  final IconData icon;
  final String text;
  final String action;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = ShadTheme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Surface(
        padding: const EdgeInsets.all(12),
        color: scheme.accent,
        child: Row(children: [Icon(icon, size: 18, color: scheme.warning), const SizedBox(width: 9), Expanded(child: Text(text, style: ShadTheme.of(context).textTheme.muted)), SecondaryButton(icon: LucideIcons.arrowRight, label: action, onPressed: onPressed)]),
      ),
    );
  }
}
