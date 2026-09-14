import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile/core/platform/nkas_platform.dart';
import 'package:nkas_mobile/core/platform/runtime_platform.dart';
import 'package:nkas_mobile/core/widgets/buttons.dart';
import 'package:nkas_mobile/core/widgets/form_field.dart';
import 'package:nkas_mobile/core/widgets/floating_action.dart';
import 'package:nkas_mobile/core/widgets/page_inset.dart';
import 'package:nkas_mobile/core/widgets/page_subtitle.dart';
import 'package:nkas_mobile/core/widgets/surface.dart';
import 'package:nkas_mobile/theme.dart';

class NkasSetupPage extends StatefulWidget {
  const NkasSetupPage({
    required this.onOpenStar,
    required this.onOpenUi,
    this.platform,
    super.key,
  });

  final VoidCallback onOpenStar;
  final VoidCallback onOpenUi;
  final NkasPlatform? platform;

  @override
  State<NkasSetupPage> createState() => _NkasSetupPageState();
}

class _NkasSetupPageState extends State<NkasSetupPage>
    with WidgetsBindingObserver {
  NkasPlatform get platform => widget.platform ?? NkasPlatform.instance;

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
  bool setupFailed = false;
  bool termuxDownloadActive = false;
  bool termuxDownloadNeedsCheck = false;
  bool termuxDownloadFailed = false;
  bool pairingActive = false;
  Timer? pairingTimer;
  final serialController = TextEditingController();
  final serialFocusNode = FocusNode();
  final pairCodeController = TextEditingController();
  final stageStates = <String, String>{};
  final stageLogs = <String, String>{};
  final stageErrors = <String, String>{};
  final stepCompletion = <String, bool>{};
  String? activeStage;
  String? failedStage;
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

  static const bootstrapStages = <String, String>{
    'installing-termux-tools': 'tools',
    'cloning-nkas': 'source',
    'creating-config': 'config',
    'installing-container': 'container',
    'starting-nkas': 'service',
  };

  static final _bootstrapRunningNotice = RegExp(
    r'^\[nkas\] bootstrap already running \(PID [1-9][0-9]*\)\r?$',
    multiLine: true,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    serialFocusNode.addListener(_onSerialFocusChanged);
    unawaited(_refresh());
    if (platform.supported) {
      subscription = platform.events.listen(_onEvent);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    refreshTimer?.cancel();
    pairingTimer?.cancel();
    unawaited(subscription?.cancel());
    serialController.dispose();
    serialFocusNode.removeListener(_onSerialFocusChanged);
    serialFocusNode.dispose();
    pairCodeController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted && !running) {
      unawaited(_refresh());
    }
  }

  void _onEvent(NkasPlatformEvent event) {
    if (!mounted) return;
    switch (event) {
      case SetupOutputEvent(:final output, :final log, :final exitCode):
        // -2 is the bridge callback timeout, not a bootstrap exit status.
        // The installation continues; preserve its state and keep polling.
        if (!log && exitCode == -2) return;
        if (!log && exitCode == 2 && _isBootstrapRunningNotice(output)) {
          setState(_resumeBootstrap);
          return;
        }
        setState(() {
          this.output = output;
          if (log && !setupFailed) {
            running = true;
          }
          if (log && !setupFailed) {
            _applyBootstrapLog(output);
          } else if (log) {
            stageLogs[failedStage ?? activeStage ?? 'tools'] = _tail(
              output,
              5000,
            );
          }
          if (!log && exitCode != null && exitCode != 0) {
            _markSetupFailed(
              output.isEmpty ? 'Termux 外部命令执行失败（退出码 $exitCode）' : output,
            );
          }
        });
      case SetupStateEvent(:final state, :final message):
        // Android also reports the duplicate command's exit as a setup failure.
        if (state == 'failed' && _isBootstrapRunningNotice(message)) {
          setState(_resumeBootstrap);
          return;
        }
        setState(() {
          running = state != 'ready' && state != 'failed';
          if (state == 'failed') {
            _markSetupFailed(message ?? '初始化失败');
          } else if (state == 'ready' && !setupFailed) {
            output = '初始化完成';
            setupFailed = false;
            failedStage = null;
            if (activeStage != null) expanded.remove(activeStage);
            activeStage = null;
            for (final key in bootstrapStages.values) {
              stageStates[key] = '完成';
            }
          }
        });
        if (state == 'ready' || state == 'failed') unawaited(_refresh());
      case TermuxDownloadEvent(:final progress, :final message, :final error):
        setState(() {
          final text = error != null
              ? 'Termux 下载失败：$error'
              : message ?? '正在下载 Termux\n进度：$progress%';
          if (error != null) {
            stageErrors['termux'] = text;
          } else {
            stageLogs['termux'] = text;
            stageErrors.remove('termux');
          }
          expanded.add('termux');
          termuxDownloadActive = error == null && message == null;
          termuxDownloadNeedsCheck = error == null && message != null;
          termuxDownloadFailed = error != null;
        });
      case SetupSerialEvent(:final serial):
        serialController.text = isIOS ? serial : serial.split(':').last;
        unawaited(_refresh());
      case SetupNoticeEvent(:final message):
        setState(() {
          stageLogs['adb_device'] = message;
          expanded.add('adb_device');
        });
      case StarAuthorizationEvent():
        unawaited(_refresh());
      case ScrcpyVideoEvent():
        break;
      case NativeNetworkEvent():
        break;
      case ScrcpyServerEvent():
        break;
      case TsnetStateEvent():
        break;
    }
  }

  Future<void> _refresh() async {
    try {
      final value = await platform.setupStatus();
      if (!mounted) return;
      if (!serialFocusNode.hasFocus) {
        serialController.text = isIOS
            ? value.serial
            : value.serial.split(':').last;
      }
      setState(() {
        status = value;
        loading = false;
        error = null;
        _syncStepExpansion('termux', value.termuxInstalled);
        _syncStepExpansion('permission', value.runCommandPermission);
        _syncStepExpansion('wireless', value.wirelessDebug);
        for (final key in const [
          'termux_setting',
          'adb_device',
          'tools',
          'source',
          'config',
          'container',
          'service',
        ]) {
          final done = value.artifacts[key];
          if (done != null) _syncStepExpansion(key, done);
        }
        if (value.artifacts['adb_device'] == true) {
          pairingActive = false;
          pairingTimer?.cancel();
        }
        final connectResult = value.connectResult.trim();
        if (connectResult.isNotEmpty && value.artifacts['adb_device'] != true) {
          stageLogs['adb_device'] = _adbConnectMessage(connectResult);
          expanded.add('adb_device');
        }
        if (value.termuxInstalled) {
          termuxDownloadActive = false;
          termuxDownloadNeedsCheck = false;
          termuxDownloadFailed = false;
        }
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

  bool _isBootstrapRunningNotice(String? message) =>
      message != null && _bootstrapRunningNotice.hasMatch(message.trim());

  void _resumeBootstrap() {
    // Do not reopen a completed installation for a late duplicate reply.
    if (!running && !setupFailed && activeStage == null) return;
    if (failedStage case final failed?) stageErrors.remove(failed);
    failedStage = null;
    setupFailed = false;
    running = true;
    activeStage ??= 'tools';
    stageStates[activeStage!] = '执行中';
    expanded.add(activeStage!);
    output = '已有安装任务正在执行，继续读取安装进度……';
    _ensureRefreshTimer();
  }

  void _ensureRefreshTimer() {
    if (!mounted || refreshTimer?.isActive == true) return;
    refreshTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _refresh(),
    );
  }

  Future<void> _start() async {
    setState(() {
      running = true;
      setupFailed = false;
      error = null;
      failedStage = null;
      output = '正在请求 Termux 恢复安装脚本……';
      activeStage = 'tools';
      stageStates.clear();
      stageLogs.clear();
      stageErrors.clear();
      stageStates['tools'] = '执行中';
      expanded.add('tools');
    });
    try {
      await platform.startSetup();
      _ensureRefreshTimer();
    } on Object catch (exception) {
      if (mounted) {
        setState(() {
          _markSetupFailed(exception.toString());
        });
      }
    }
  }

  Future<void> _pair() async {
    if (pairingActive) return;
    if (!await _saveSerial(refresh: false)) return;
    final serial = serialController.text.trim();
    final code = pairCodeController.text.trim();
    if (code.isNotEmpty && !RegExp(r'^\d{4,8}$').hasMatch(code)) {
      setState(() {
        stageLogs['adb_device'] = '配对码格式不正确，请填写配对弹窗显示的数字配对码。';
        expanded.add('adb_device');
      });
      return;
    }
    setState(() {
      pairingActive = true;
      stageLogs['adb_device'] = '正在搜索无线调试配对服务……';
      expanded.add('adb_device');
    });
    pairingTimer?.cancel();
    pairingTimer = Timer(const Duration(seconds: 65), () {
      if (!mounted || !pairingActive) return;
      setState(() {
        pairingActive = false;
        stageLogs['adb_device'] = '等待配对服务超时，请确认无线调试中的“使用配对码配对”弹窗处于打开状态。';
      });
    });
    try {
      if (serial.isNotEmpty) {
        await platform.setSerial('127.0.0.1:$serial');
      }
      await platform.pairDevice(
        code: code,
        serial: serial.isEmpty ? '' : '127.0.0.1:$serial',
      );
      if (mounted) {
        setState(() {
          stageLogs['adb_device'] = code.isEmpty
              ? '配对服务已启动：请在无线调试页面打开“使用配对码配对”并在通知中输入配对码。'
              : '配对服务已启动：发现配对服务后将自动使用填写的配对码完成配对。';
          expanded.add('adb_device');
        });
        _show('配对服务已启动，请在无线调试配对通知中输入配对码');
      }
    } on Object catch (exception) {
      pairingTimer?.cancel();
      if (mounted) {
        setState(() {
          pairingActive = false;
          stageLogs['adb_device'] = exception.toString();
          expanded.add('adb_device');
        });
        _show(exception.toString());
      }
    }
  }

  void _onSerialFocusChanged() {
    if (!serialFocusNode.hasFocus) {
      unawaited(isIOS ? _saveIosSerial() : _saveSerial());
    }
  }

  Future<void> _saveIosSerial() async {
    final endpoint = serialController.text.trim();
    if (endpoint.isEmpty) return;
    if (!RegExp(
      r'^(adb://)?(?:\[[0-9a-fA-F:]+\]|[^:]+):\d{1,5}$',
    ).hasMatch(endpoint)) {
      if (mounted) _show('请输入 host:port 或 adb://host:port');
      return;
    }
    await platform.setSerial(
      endpoint.startsWith('adb://') ? endpoint : 'adb://$endpoint',
    );
    if (mounted) await _refresh();
  }

  Future<bool> _saveSerial({bool refresh = true}) async {
    final serial = serialController.text.trim();
    if (serial.isEmpty) return true;
    if (!RegExp(r'^\d{1,5}$').hasMatch(serial)) {
      if (mounted) {
        setState(() {
          stageLogs['adb_device'] = '端口格式不正确，请填写无线调试页面显示的端口号。';
          expanded.add('adb_device');
        });
      }
      return false;
    }
    await platform.setSerial('127.0.0.1:$serial');
    if (refresh && mounted) await _refresh();
    return true;
  }

  void _applyBootstrapLog(String raw) {
    final state = raw
        .split('---STATE---')
        .skip(1)
        .join('---STATE---')
        .split('---LOG---')
        .first
        .trim();
    final currentIndex = bootstrapStages.keys.toList().indexOf(state);
    if (currentIndex < 0) return;

    final entries = bootstrapStages.entries.toList();
    final previousStage = activeStage;
    activeStage = entries[currentIndex].value;
    if (previousStage != null && previousStage != activeStage) {
      expanded.remove(previousStage);
    }
    final log = raw
        .split('---LOG---')
        .skip(1)
        .join('---LOG---')
        .split('---SERVICE---')
        .first
        .trim();
    if (log.isNotEmpty) stageLogs[activeStage!] = _tail(log, 5000);
    final service = raw
        .split('---SERVICE---')
        .skip(1)
        .join('---SERVICE---')
        .trim();
    if (service.isNotEmpty) stageLogs['service'] = _tail(service, 5000);
    expanded.add(activeStage!);
    for (var index = 0; index < entries.length; index++) {
      final key = entries[index].value;
      stageStates[key] = index < currentIndex
          ? '完成'
          : index == currentIndex
          ? '执行中'
          : '等待';
    }
  }

  void _markSetupFailed(String message) {
    running = false;
    setupFailed = true;
    failedStage ??= activeStage ?? 'tools';
    final detail = message.trim();
    stageErrors[failedStage!] = detail.isEmpty ? '初始化失败' : detail;
    stageStates[failedStage!] = '失败';
    expanded.add(failedStage!);
    refreshTimer?.cancel();
  }

  String _tail(String value, int maxLength) => value.length <= maxLength
      ? value
      : value.substring(value.length - maxLength);

  void _show(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    if (isIOS) return _buildIos(context);
    final inset = nkasPageInset(context);
    return Stack(
      children: [
        Positioned.fill(
          child: ListView(
            padding: EdgeInsets.fromLTRB(inset, 5, inset, 92),
            children: [
              Text(
                '准备 Termux、NKAS 服务和本地 Web UI\n'
                '请开启 Termux 和 NKAS 的自启动、关联启动，并允许后台运行',
                style: TextStyle(
                  color: ShadTheme.of(context).colorScheme.mutedForeground,
                  fontSize: 13,
                  height: 19 / 13,
                ),
              ),
              const SizedBox(height: 14),
              if (loading) const LinearProgressIndicator(minHeight: 2),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(
                  error!,
                  style: TextStyle(
                    color: ShadTheme.of(context).colorScheme.destructive,
                  ),
                ),
              ],
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
            ],
          ),
        ),
        Positioned(
          left: inset,
          right: inset,
          bottom: 12,
          child: SafeArea(
            top: false,
            child: NkasFloatingAction(
              label: _actionLabel,
              icon: _actionIcon,
              enabled: !_actionDisabled,
              onPressed: _handleAction,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildIos(BuildContext context) {
    final scheme = ShadTheme.of(context).colorScheme;
    final inset = nkasPageInset(context);
    final authorized = status.authorized;
    return ListView(
      padding: EdgeInsets.fromLTRB(inset, 5, inset, 28),
      children: [
        const PageSubtitle('iOS 通过远程后端控制 NKAS，无需安装 Termux 或配置无线调试。'),
        Surface(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    authorized ? LucideIcons.circleCheck : LucideIcons.shield,
                    color: authorized ? scheme.success : scheme.mutedForeground,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      authorized ? 'STAR 验证已完成' : '请先完成 STAR 验证',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                authorized
                    ? '当前设备可以连接后端并控制实例。后端地址可在设置中修改。'
                    : '完成验证后即可返回实例页面使用控制功能。',
                style: ShadTheme.of(context).textTheme.muted,
              ),
              const SizedBox(height: 16),
              _IosSetupStep(
                icon: LucideIcons.shieldCheck,
                title: '项目授权',
                detail: authorized ? '已完成' : '待验证',
                complete: authorized,
              ),
              const Divider(height: 20),
              NkasTextField(
                label: '远程 Android ADB 地址',
                description:
                    'iOS 原生 scrcpy 使用此地址直接连接远程 Android；设备需开启 TCP ADB 并确认 RSA 授权。',
                controller: serialController,
                focusNode: serialFocusNode,
                keyboardType: TextInputType.url,
                onSubmitted: (_) => unawaited(_saveIosSerial()),
                hintText: '例如 100.64.0.2:5555',
              ),
              const Divider(height: 20),
              _IosSetupStep(
                icon: LucideIcons.server,
                title: '连接后端服务',
                detail: '在设置中配置后端地址',
                complete: false,
              ),
              const Divider(height: 20),
              _IosSetupStep(
                icon: LucideIcons.smartphone,
                title: '开始控制实例',
                detail: '从实例页面进入任务、日志和画面',
                complete: false,
              ),
            ],
          ),
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
    if (termuxDownloadActive) return '正在下载 Termux…';
    if (setupFailed) return '重试当前安装';
    if (!status.authorized) return '前往 Star 验证';
    if (!status.termuxInstalled) {
      if (termuxDownloadFailed) return '重试下载 Termux';
      return termuxDownloadNeedsCheck ? '重新检查' : '下载并安装 Termux';
    }
    if (!status.runCommandPermission) return '授权 Termux 外部命令';
    if (_artifactStatusKnown && !_termuxSettingReady) {
      return '等待 Termux 设置';
    }
    if (running) return '正在安装…';
    if (_artifactCheckFailed) return '重新检查';
    if (!_projectArtifactsReady) return '开始安装';
    if (!status.wirelessDebug) return '打开无线调试设置';
    if (_artifactBlocked) {
      return '等待 ADB 设备';
    }
    if (status.artifactsReady) return '打开 NKAS UI';
    return '开始安装';
  }

  IconData get _actionIcon {
    if (termuxDownloadActive) return LucideIcons.loaderCircle;
    if (setupFailed) return LucideIcons.refreshCw;
    if (!status.authorized) return LucideIcons.shieldCheck;
    if (!status.termuxInstalled) return LucideIcons.download;
    if (!status.runCommandPermission) return LucideIcons.shieldCheck;
    if (_artifactStatusKnown && !_termuxSettingReady) {
      return LucideIcons.terminal;
    }
    if (running) return LucideIcons.loaderCircle;
    if (_artifactCheckFailed) return LucideIcons.refreshCw;
    if (!_projectArtifactsReady) return LucideIcons.rocket;
    if (!status.wirelessDebug) return LucideIcons.settings2;
    if (status.artifactsReady) return LucideIcons.externalLink;
    return LucideIcons.rocket;
  }

  bool get _artifactBlocked =>
      _artifactCheckFailed ||
      (_artifactStatusKnown &&
          (!_termuxSettingReady ||
              (_projectArtifactsReady && !_adbDeviceReady)));

  bool get _artifactStatusKnown => status.artifacts.isNotEmpty;

  bool get _termuxSettingReady => status.artifacts['termux_setting'] == true;

  bool get _projectArtifactsReady => const [
    'tools',
    'source',
    'config',
    'container',
    'service',
  ].every((key) => status.artifacts[key] == true);

  bool get _adbDeviceReady => status.artifacts['adb_device'] == true;

  bool get _artifactCheckFailed =>
      status.commandExitCode != null &&
      (status.commandExitCode != 0 ||
          !const [
            'termux_setting',
            'adb_device',
            'tools',
            'source',
            'config',
            'container',
            'service',
          ].every(status.artifacts.containsKey));

  bool get _actionDisabled =>
      running ||
      termuxDownloadActive ||
      (_artifactBlocked && !_artifactCheckFailed);

  Future<void> _handleAction() async {
    if (setupFailed) return _start();
    if (!status.authorized) {
      widget.onOpenStar();
      return;
    }
    if (!status.termuxInstalled) {
      if (termuxDownloadNeedsCheck) return _refresh();
      setState(() {
        error = null;
        stageErrors.remove('termux');
        stageLogs.remove('termux');
        termuxDownloadNeedsCheck = false;
        termuxDownloadFailed = false;
        termuxDownloadActive = true;
      });
      return platform.downloadTermux();
    }
    if (!status.runCommandPermission) {
      await platform.requestRunCommandPermission();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      return _refresh();
    }
    if (_artifactStatusKnown && !_termuxSettingReady) return _refresh();
    if (_artifactCheckFailed) return _refresh();
    if (!_projectArtifactsReady) {
      if (!await platform.initialNoticeShown()) {
        if (!mounted) return;
        final proceed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('安装前提醒'),
            content: const Text(
              '安装可能需要较长时间。执行期间请保持 NKAS Mobile 始终在前台，并确保网络连接稳定；切换到其他应用或断网可能导致下载失败。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('继续安装'),
              ),
            ],
          ),
        );
        if (proceed != true) return;
        await platform.setInitialNoticeShown();
      }
      return _start();
    }
    if (!status.wirelessDebug) {
      return platform.openWirelessSettings();
    }
    if (_projectArtifactsReady && !_adbDeviceReady) return;
    if (status.artifactsReady) {
      return _openUi();
    }
    return _refresh();
  }

  Future<void> _openUi() async {
    final current = status.serial.trim();
    if (current.isEmpty) {
      widget.onOpenUi();
      return;
    }
    try {
      final configured = (await platform.getNkasSerial()).trim();
      if (!mounted) return;
      if (configured.isEmpty || configured == current) {
        widget.onOpenUi();
        return;
      }
      final overwrite = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Serial 不一致'),
          content: Text(
            'nkas.json 中的 Serial：$configured\n当前设备：$current\n\n是否将配置覆盖为当前设备？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('不覆盖'),
            ),
            FilledButton(
              style: NkasActionStyle.destructiveFilled(context),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('覆盖并打开'),
            ),
          ],
        ),
      );
      if (overwrite == true) {
        await platform.setNkasSerial(current);
      }
      if (mounted) widget.onOpenUi();
    } on Object catch (exception) {
      if (mounted) _show(exception.toString());
    }
  }

  String _stepState(String key) {
    if (key == 'termux' && termuxDownloadActive) return '下载中';
    if (key == 'termux') return status.termuxInstalled ? '已安装' : '待安装';
    if (key == 'permission') return status.runCommandPermission ? '已授权' : '待授权';
    if (key == 'wireless') return status.wirelessDebug ? '已开启' : '待开启';
    if (key == 'adb_device' && status.artifacts['adb_device'] == true) {
      return '已连接';
    }
    if (setupFailed && bootstrapStages.values.contains(key)) {
      final failedIndex = bootstrapStages.values.toList().indexOf(
        failedStage ?? '',
      );
      final keyIndex = bootstrapStages.values.toList().indexOf(key);
      if (key == failedStage) return '失败';
      if (failedIndex >= 0 && keyIndex > failedIndex) return '等待';
    }
    if (running && stageStates[key] != null) return stageStates[key]!;
    if (status.artifacts[key] == true) {
      return key == 'service' ? '运行中' : '已检测';
    }
    if (stageStates[key] != null) return stageStates[key]!;
    if (_projectEnvironmentBlocked &&
        const [
          'adb_device',
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

  bool get _projectEnvironmentBlocked =>
      !status.authorized ||
      !status.termuxInstalled ||
      !status.runCommandPermission ||
      !status.wirelessDebug ||
      status.artifacts['termux_setting'] == false ||
      _artifactCheckFailed;

  String _adbConnectMessage(String result) {
    final extra = result.toLowerCase().contains('not found')
        ? '\nTermux 中还没有 adb 工具，请先完成上方“项目安装”中的 Termux 工具步骤。'
        : result.toLowerCase().contains('authenticate') ||
              result.toLowerCase().contains('unauthorized')
        ? '\n设备尚未授权过 Termux，请使用下方配对地址和配对码执行一次配对，之后即可直接连接。'
        : '';
    return 'adb connect：$result$extra';
  }

  void _syncStepExpansion(String key, bool done) {
    final previous = stepCompletion[key];
    if (previous == done) return;
    stepCompletion[key] = done;
    if (done) {
      expanded.remove(key);
    } else {
      expanded.add(key);
    }
  }

  String _stepDetail(String key) {
    if (key == 'termux') {
      if (!status.termuxInstalled) return '需要安装官方 Termux';
      final version = status.termuxVersion;
      if (version != null && version.isNotEmpty) {
        return '已安装版本：Termux v$version';
      }
      return '官方 Termux 应用与运行环境';
    }
    if (key == 'adb_device' && status.serial.isNotEmpty) return status.serial;
    if (key == 'service' && status.artifacts[key] == true) return '服务已响应';
    return const {
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
    final help = _stepHelp(key);
    final error = stageErrors[key];
    final rawLog = stageLogs[key] ?? (activeStage == key ? output : '');
    final log = rawLog.trim() == error ? '' : rawLog;
    if (help == null && log.isEmpty && error == null) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?help,
        if (log.isNotEmpty || error != null)
          _ExtraPanel(text: log, monospace: true, error: error),
      ],
    );
  }

  Widget? _stepHelp(String key) {
    final scheme = ShadTheme.of(context).colorScheme;
    switch (key) {
      case 'permission':
        return _ExtraPanel(
          text:
              '部分系统不会弹出授权框，需要在系统设置中手动允许 NKAS 使用 Run commands in Termux environment。',
          child: _SetupActions(
            children: [
              SecondaryButton(
                compact: true,
                icon: LucideIcons.settings2,
                label: '打开应用权限设置',
                onPressed: platform.openAppSettings,
              ),
            ],
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
              _SetupActions(
                children: [
                  SecondaryButton(
                    compact: true,
                    icon: LucideIcons.terminal,
                    label: '打开 Termux',
                    onPressed: platform.openTermux,
                  ),
                  SecondaryButton(
                    compact: true,
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
                ],
              ),
            ],
          ),
        );
      case 'wireless':
        return _ExtraPanel(
          text: '请在 Android 系统设置中开启无线调试，随后返回此页面继续。',
          child: _SetupActions(
            children: [
              SecondaryButton(
                compact: true,
                icon: LucideIcons.settings2,
                label: '打开无线调试设置',
                onPressed: platform.openWirelessSettings,
              ),
            ],
          ),
        );
      case 'adb_device':
        return _ExtraPanel(
          text: '首次连接需要配对一次。点击“配对”，在无线调试中打开“使用配对码配对”，再在通知中输入配对码。',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NkasTextField(
                label: '无线调试端口',
                description: '通常会自动发现；手动填写时，使用无线调试主页的连接端口。',
                controller: serialController,
                focusNode: serialFocusNode,
                keyboardType: TextInputType.number,
                onSubmitted: (_) => unawaited(_saveSerial()),
                hintText: '填写系统设置中显示的端口号',
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(5),
                ],
              ),
              const SizedBox(height: 16),
              NkasTextField(
                label: '配对码',
                description: '可留空，稍后在配对通知中输入。',
                controller: pairCodeController,
                keyboardType: TextInputType.number,
                hintText: '填写数字配对码',
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(8),
                ],
              ),
              const SizedBox(height: 8),
              _SetupActions(
                children: [
                  SecondaryButton(
                    compact: true,
                    icon: LucideIcons.link,
                    label: pairingActive ? '配对中…' : '配对',
                    loading: pairingActive,
                    onPressed: pairingActive ? null : _pair,
                  ),
                ],
              ),
            ],
          ),
        );
      default:
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
    final done = const [
      '已完成',
      '已检测',
      '运行中',
      '已安装',
      '已授权',
      '已开启',
      '已连接',
    ].contains(state);
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

/// 同一组操作始终共用一行，按钮平分当前面板的可用宽度。
class _SetupActions extends StatelessWidget {
  const _SetupActions({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var index = 0; index < children.length; index++) ...[
        if (index > 0) const SizedBox(width: 8),
        Expanded(child: children[index]),
      ],
    ],
  );
}

class _ExtraPanel extends StatelessWidget {
  const _ExtraPanel({
    required this.text,
    this.child,
    this.monospace = false,
    this.error,
  });

  final String text;
  final Widget? child;
  final bool monospace;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final scheme = ShadTheme.of(context).colorScheme;
    const logStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: 10,
      height: 1.55,
    );
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
          if (monospace)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 190),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (error != null) ...[
                      Text(
                        error!,
                        style: logStyle.copyWith(color: scheme.destructive),
                      ),
                      if (text.isNotEmpty) const SizedBox(height: 8),
                    ],
                    if (text.isNotEmpty) Text(text, style: logStyle),
                  ],
                ),
              ),
            )
          else
            Text(
              text,
              style: ShadTheme.of(
                context,
              ).textTheme.muted.copyWith(height: 1.5),
            ),
          if (child != null) ...[const SizedBox(height: 8), child!],
        ],
      ),
    );
  }
}

class _IosSetupStep extends StatelessWidget {
  const _IosSetupStep({
    required this.icon,
    required this.title,
    required this.detail,
    required this.complete,
  });

  final IconData icon;
  final String title;
  final String detail;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    final scheme = ShadTheme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 20, color: complete ? scheme.success : scheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(detail, style: ShadTheme.of(context).textTheme.muted),
            ],
          ),
        ),
        if (complete) Icon(LucideIcons.check, size: 18, color: scheme.success),
      ],
    );
  }
}
