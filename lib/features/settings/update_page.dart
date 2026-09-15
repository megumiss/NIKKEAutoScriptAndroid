import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile/core/api/update_info.dart';
import 'package:nkas_mobile/core/connection/connection_controller.dart';
import 'package:nkas_mobile/core/widgets/buttons.dart';
import 'package:nkas_mobile/core/widgets/group_label.dart';
import 'package:nkas_mobile/core/widgets/page_inset.dart';
import 'package:nkas_mobile/core/widgets/page_subtitle.dart';
import 'package:nkas_mobile/core/widgets/surface.dart';
import 'package:nkas_mobile/core/widgets/tag.dart';
import 'package:nkas_mobile/theme.dart';

class UpdatePage extends StatefulWidget {
  const UpdatePage({
    required this.connectionController,
    required this.enabled,
    super.key,
  });

  final ConnectionController connectionController;
  final bool enabled;

  @override
  State<UpdatePage> createState() => _UpdatePageState();
}

class _UpdatePageState extends State<UpdatePage> {
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

  @override
  void didUpdateWidget(covariant UpdatePage oldWidget) {
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
        loadedBaseUrl != connection.baseUrl &&
        !busy) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    if (!widget.enabled) return;
    final baseUrl = widget.connectionController.state.baseUrl;
    try {
      final value = await widget.connectionController.refreshUpdateInfo();
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

  Future<void> _check() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.connectionController.checkForUpdate();
      await _poll(maxRounds: 30);
      if (!mounted) return;
      await _load();
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
      if (!mounted) return;
      await _load();
    } catch (exception) {
      if (mounted) setState(() => error = exception.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _confirmApply() async {
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
  }

  Future<void> _poll({
    int maxRounds = 30,
    bool tolerateConnectionErrors = false,
  }) async {
    for (var round = 0; round < maxRounds && mounted; round++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      try {
        final value = await widget.connectionController.refreshUpdateInfo();
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
    final theme = ShadTheme.of(context);
    final scheme = theme.colorScheme;
    final inset = nkasPageInset(context);
    final connected =
        widget.connectionController.state.phase == ConnectionPhase.connected;
    final active = widget.enabled && connected;
    final version = widget.connectionController.state.status?.version;
    final history = info?.history ?? const <UpdateCommit>[];
    final localSha = info?.localSha;
    return ListView(
      padding: EdgeInsets.fromLTRB(inset, 5, inset, 28),
      children: [
        const PageSubtitle('检查并更新 NKAS 源码，查看最近的提交记录。'),
        Surface(
          radius: 18,
          padding: const EdgeInsets.all(17),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: scheme.success.withValues(alpha: .11),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      LucideIcons.squareArrowUp,
                      color: scheme.success,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '源码更新',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          !connected
                              ? '连接后端后可检查源码更新。'
                              : '当前版本：${version ?? '未知'} · ${info?.stateLabel ?? '未检查'}',
                          style: theme.textTheme.muted,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (error != null && error!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  error!,
                  style: theme.textTheme.muted.copyWith(
                    color: scheme.destructive,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(children: [Expanded(child: _actionButton(active))]),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const GroupLabel('更新记录'),
        Surface(
          padding: EdgeInsets.zero,
          child: history.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 16,
                  ),
                  child: Text(
                    connected ? '暂无更新记录' : '连接后端后显示更新记录',
                    style: theme.textTheme.muted,
                  ),
                )
              : Column(
                  children: [
                    for (var i = 0; i < history.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      _CommitRow(
                        commit: history[i],
                        current:
                            history[i].sha != null &&
                            history[i].sha == localSha,
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _actionButton(bool active) {
    if (info?.running == true) {
      return const PrimaryButton(
        icon: LucideIcons.download,
        label: '更新中…',
        onPressed: null,
      );
    }
    if (busy || info?.checking == true) {
      return const PrimaryButton(
        icon: LucideIcons.refreshCw,
        label: '检查中…',
        onPressed: null,
      );
    }
    final available = info?.updateAvailable == true;
    final retry = info?.state == 'failed' && (info?.error?.isEmpty ?? true);
    if (available || retry) {
      return PrimaryButton(
        icon: LucideIcons.download,
        label: available ? '立即更新' : '重试更新',
        onPressed: active ? _confirmApply : null,
      );
    }
    return PrimaryButton(
      icon: LucideIcons.refreshCw,
      label: '检查更新',
      onPressed: active ? _check : null,
    );
  }
}

class _CommitRow extends StatelessWidget {
  const _CommitRow({required this.commit, required this.current});

  final UpdateCommit commit;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  commit.message ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: current ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
              if (current) ...[
                const SizedBox(width: 6),
                Tag(label: '当前版本', color: scheme.success),
              ],
            ],
          ),
          const SizedBox(height: 3),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: commit.sha ?? '',
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
                TextSpan(text: ' · ${commit.dateLabel}'),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.muted,
          ),
        ],
      ),
    );
  }
}
