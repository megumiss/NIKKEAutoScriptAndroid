import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:nkas_mobile_preview/core/platform/nkas_platform.dart';
import 'package:nkas_mobile_preview/core/widgets/buttons.dart';
import 'package:nkas_mobile_preview/core/widgets/page_inset.dart';
import 'package:nkas_mobile_preview/core/widgets/page_subtitle.dart';
import 'package:nkas_mobile_preview/core/widgets/surface.dart';
import 'package:nkas_mobile_preview/theme.dart';

class StarVerifyPage extends StatefulWidget {
  const StarVerifyPage({required this.onOpenSetup, super.key});

  final VoidCallback onOpenSetup;

  @override
  State<StarVerifyPage> createState() => _StarVerifyPageState();
}

class _StarVerifyPageState extends State<StarVerifyPage> {
  StarAuthorization status = const StarAuthorization(authorized: false);
  StreamSubscription<NkasPlatformEvent>? subscription;
  bool loading = true;
  bool opening = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    if (NkasPlatform.instance.supported) {
      subscription = NkasPlatform.instance.events.listen((event) {
        if (event case StarAuthorizationEvent(:final status)) {
          if (mounted) setState(() => this.status = status);
        }
      });
    }
  }

  @override
  void dispose() {
    unawaited(subscription?.cancel());
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final value = await NkasPlatform.instance.starStatus();
      if (mounted) setState(() => status = value);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _authorize() async {
    setState(() => opening = true);
    try {
      await NkasPlatform.instance.beginStarVerification();
    } on Object catch (error) {
      if (mounted) _showMessage(error.toString());
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  Future<void> _openRepository() async {
    final opened = await launchUrl(
      Uri.parse('https://github.com/megumiss/NIKKEAutoScript'),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) _showMessage('无法打开项目仓库');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = ShadTheme.of(context).colorScheme;
    final inset = nkasPageInset(context);
    final unsupported = !NkasPlatform.instance.supported;
    return ListView(
      padding: EdgeInsets.fromLTRB(inset, 5, inset, 28),
      children: [
        const PageSubtitle('使用 NKAS 前需要 Star 本项目，感谢你的支持。'),
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
                      color: scheme.accentSoft,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      status.authorized
                          ? LucideIcons.shieldCheck
                          : LucideIcons.gitBranch,
                      color: status.authorized
                          ? scheme.success
                          : scheme.primary,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          status.authorized ? '授权已通过' : '完成项目授权',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          unsupported
                              ? 'STAR 验证需要 Android 平台能力。'
                              : status.authorized
                              ? '设备身份已确认，可以继续初始化 NKAS。'
                              : '通过 GitHub 验证账号是否已 Star 项目。',
                          style: ShadTheme.of(context).textTheme.muted,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: scheme.secondary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'megumiss/NIKKEAutoScript',
                  style: TextStyle(
                    color: scheme.mutedForeground,
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(height: 13),
              if (loading)
                const LinearProgressIndicator(minHeight: 2)
              else
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: status.authorized
                            ? scheme.success
                            : scheme.mutedForeground,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        status.authorized
                            ? '已确认 Star megumiss/NIKKEAutoScript'
                            : status.error ?? '尚未验证 Star',
                        style: TextStyle(
                          color: status.authorized
                              ? scheme.success
                              : scheme.mutedForeground,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              if (status.authorized) ...[
                const SizedBox(height: 13),
                Container(
                  padding: const EdgeInsets.only(top: 12),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: scheme.border)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _AuthMeta(
                          label: 'GitHub 账号',
                          value: '@${status.username ?? 'nkas-user'}',
                        ),
                      ),
                      Expanded(
                        child: _AuthMeta(
                          label: '验证有效期至',
                          value: status.expiresAt == null
                              ? '长期有效'
                              : _date(status.expiresAt!),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: status.authorized
                        ? PrimaryButton(
                            icon: LucideIcons.sparkles,
                            label: '打开初始化',
                            onPressed: widget.onOpenSetup,
                          )
                        : PrimaryButton(
                            icon: LucideIcons.gitBranch,
                            label: opening ? '正在打开…' : '前往 GitHub 验证 Star',
                            onPressed: unsupported || opening
                                ? null
                                : _authorize,
                          ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SecondaryButton(
                      icon: status.authorized
                          ? LucideIcons.refreshCw
                          : LucideIcons.externalLink,
                      label: status.authorized ? '重新验证' : '打开项目仓库',
                      onPressed: status.authorized
                          ? _authorize
                          : _openRepository,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _date(int seconds) {
    final date = DateTime.fromMillisecondsSinceEpoch(seconds * 1000).toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)}';
  }
}

class _AuthMeta extends StatelessWidget {
  const _AuthMeta({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.muted.copyWith(fontSize: 10)),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
