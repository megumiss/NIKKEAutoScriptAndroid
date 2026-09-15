import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile/core/platform/nkas_platform.dart';
import 'package:nkas_mobile/core/widgets/field_select.dart';
import 'package:nkas_mobile/core/widgets/floating_action.dart';
import 'package:nkas_mobile/core/widgets/form_field.dart';
import 'package:nkas_mobile/core/widgets/group_label.dart';
import 'package:nkas_mobile/core/widgets/page_inset.dart';
import 'package:nkas_mobile/core/widgets/page_subtitle.dart';
import 'package:nkas_mobile/core/widgets/surface.dart';
import 'package:nkas_mobile/theme.dart';

/// Android 初始化使用的下载源、项目仓库、Docker 镜像与 WebUI 地址，
/// 由原生 SettingsStore 持久化，Termux 安装脚本启动时读取。
class InitConfigPage extends StatefulWidget {
  const InitConfigPage({this.platform, super.key});

  final NkasPlatform? platform;

  @override
  State<InitConfigPage> createState() => _InitConfigPageState();
}

class _InitConfigPageState extends State<InitConfigPage> {
  NkasPlatform get platform => widget.platform ?? NkasPlatform.instance;

  TextEditingController? webUi;
  TextEditingController? docker;
  InitConfig? config;
  String? repository;
  String? aptSource;
  bool loading = true;
  bool saving = false;
  String? loadError;
  String? error;
  bool saved = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    webUi?.dispose();
    docker?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final value = await platform.initConfig();
      if (!mounted) return;
      setState(() {
        loading = false;
        config = value;
        if (value != null) {
          webUi = TextEditingController(text: value.webUiUrl);
          docker = TextEditingController(text: value.dockerImage);
          repository = value.repository;
          aptSource = value.aptSource;
        }
      });
    } on PlatformException catch (exception) {
      if (!mounted) return;
      setState(() {
        loading = false;
        loadError = exception.message ?? '读取初始化配置失败';
      });
    }
  }

  Future<void> _save() async {
    if (saving || config == null) return;
    FocusScope.of(context).unfocus();
    setState(() {
      saving = true;
      error = null;
      saved = false;
    });
    try {
      await platform.saveInitConfig(
        webUiUrl: webUi?.text ?? '',
        repository: repository ?? '',
        aptSource: aptSource ?? '',
        dockerImage: docker?.text ?? '',
      );
      if (!mounted) return;
      setState(() {
        saving = false;
        saved = true;
      });
    } on PlatformException catch (exception) {
      if (!mounted) return;
      setState(() {
        saving = false;
        error = exception.message ?? '保存失败';
      });
    }
  }

  String _sourceLabel(List<InitConfigSource> options, String? value) =>
      options.where((option) => option.value == value).firstOrNull?.label ?? '';

  @override
  Widget build(BuildContext context) {
    final inset = nkasPageInset(context);
    final theme = ShadTheme.of(context);
    final saveButton = SafeArea(
      top: false,
      child: NkasFloatingAction(
        label: saving ? '保存中…' : '保存配置',
        icon: LucideIcons.check,
        loading: saving,
        enabled: !saving && !loading && config != null,
        onPressed: _save,
      ),
    );
    final content = ListView(
      padding: EdgeInsets.fromLTRB(inset, 5, inset, 104),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        const PageSubtitle('选择初始化时使用的下载源和项目仓库，下次安装或重试时生效'),
        if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (config == null)
          Surface(
            child: Text(
              loadError ?? '初始化配置仅支持 Android',
              style: theme.textTheme.muted.copyWith(height: 1.5),
            ),
          )
        else ...[
          const GroupLabel('服务地址'),
          Surface(
            child: NkasTextField(
              label: 'WebUI 地址',
              description: '应用、初始化检查和 Termux 服务统一使用此地址',
              controller: webUi,
              enabled: !saving,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
              hintText: 'http://127.0.0.1:12271',
              prefixIcon: const Icon(LucideIcons.globe, size: 18),
            ),
          ),
          const SizedBox(height: 20),
          const GroupLabel('下载源'),
          Surface(
            child: Column(
              children: [
                FieldSelect(
                  label: '项目仓库',
                  description: '用于下载和更新 NIKKEAutoScript，默认使用国内项目镜像',
                  value: _sourceLabel(config!.repositorySources, repository),
                  selectedValue: repository,
                  options: [
                    for (final option in config!.repositorySources)
                      FieldSelectOption(option.value, option.label),
                  ],
                  onChanged: saving
                      ? null
                      : (value) => setState(() {
                          repository = value;
                          saved = false;
                          error = null;
                        }),
                ),
                const SizedBox(height: 16),
                FieldSelect(
                  label: 'Termux apt 源',
                  description: '用于安装 Termux 工具，默认使用国内清华源',
                  value: _sourceLabel(config!.aptSources, aptSource),
                  selectedValue: aptSource,
                  options: [
                    for (final option in config!.aptSources)
                      FieldSelectOption(option.value, option.label),
                  ],
                  onChanged: saving
                      ? null
                      : (value) => setState(() {
                          aptSource = value;
                          saved = false;
                          error = null;
                        }),
                ),
                const SizedBox(height: 16),
                NkasTextField(
                  label: 'Docker 镜像',
                  description: '用于安装 NKAS 容器，默认使用毫秒镜像 docker.1ms.run',
                  controller: docker,
                  enabled: !saving,
                  textInputAction: TextInputAction.done,
                  hintText: 'docker.1ms.run/megumiss/nkas:latest',
                  prefixIcon: const Icon(LucideIcons.container, size: 18),
                  onChanged: (_) => setState(() {
                    saved = false;
                    error = null;
                  }),
                  onSubmitted: (_) => _save(),
                ),
              ],
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(
              error!,
              style: TextStyle(color: theme.colorScheme.destructive),
            ),
          ],
          if (saved) ...[
            const SizedBox(height: 12),
            Text(
              '已保存。下次安装或重试时将应用新的地址、仓库和源。',
              style: TextStyle(color: theme.colorScheme.success),
            ),
          ],
        ],
      ],
    );
    // 键盘弹出时悬浮按钮会遮住正在编辑的输入框：
    // 收起键盘前固定在列表下方，不再悬浮在内容上
    if (nkasKeyboardOpen(context)) {
      return Column(
        children: [
          Expanded(child: content),
          Padding(
            padding: EdgeInsets.fromLTRB(inset, 8, inset, 12),
            child: saveButton,
          ),
        ],
      );
    }
    return Stack(
      children: [
        Positioned.fill(child: content),
        Positioned(left: inset, right: inset, bottom: 12, child: saveButton),
      ],
    );
  }
}
