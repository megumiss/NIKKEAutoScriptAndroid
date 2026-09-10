import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile_preview/core/widgets/avatar.dart';
import 'package:nkas_mobile_preview/core/widgets/buttons.dart';
import 'package:nkas_mobile_preview/core/widgets/filter_chip.dart';
import 'package:nkas_mobile_preview/core/widgets/page_inset.dart';
import 'package:nkas_mobile_preview/core/widgets/page_subtitle.dart';
import 'package:nkas_mobile_preview/core/widgets/section_header.dart';
import 'package:nkas_mobile_preview/core/widgets/status.dart';
import 'package:nkas_mobile_preview/core/widgets/surface.dart';
import 'package:nkas_mobile_preview/core/widgets/tag.dart';
import 'package:nkas_mobile_preview/theme.dart';

class OverviewPage extends StatelessWidget {
  const OverviewPage({
    required this.serviceRunning,
    required this.canControlService,
    required this.onToggleService,
    required this.onOpenInstances,
    super.key,
  });
  final bool serviceRunning;
  final bool canControlService;
  final VoidCallback onToggleService;
  final VoidCallback onOpenInstances;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final scheme = theme.colorScheme;
    final inset = nkasPageInset(context);
    return ListView(
      padding: EdgeInsets.fromLTRB(inset, 5, inset, 88),
      children: [
        const PageSubtitle('快速查看本机服务与实例状态'),
        Surface(
          color: scheme.accentSoft,
          radius: 22,
          bordered: false,
          padding: const EdgeInsets.all(19),
          shadow: NkasShadows.brand(
            scheme.primary,
            Theme.of(context).brightness,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '主服务',
                          style: theme.textTheme.muted.copyWith(
                            color: scheme.heroEyebrow,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Dot(color: scheme.primary),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                serviceRunning ? '服务运行正常' : '服务已停止',
                                style: const TextStyle(
                                  fontSize: 21,
                                  fontWeight: FontWeight.w700,
                                  height: 25 / 21,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: scheme.secondaryButtonBg,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      serviceRunning
                          ? LucideIcons.activity
                          : LucideIcons.pauseCircle,
                      color: scheme.primary,
                      size: 20,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 13,
                runSpacing: 8,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        LucideIcons.smartphone,
                        size: 14,
                        color: scheme.heroMetaIcon,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Android 本机',
                        style: theme.textTheme.muted.copyWith(
                          color: scheme.heroMeta,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        LucideIcons.clock3,
                        size: 14,
                        color: scheme.heroMetaIcon,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        serviceRunning ? '运行 2 小时 18 分' : '等待启动',
                        style: theme.textTheme.muted.copyWith(
                          color: scheme.heroMeta,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 17),
              Row(
                children: [
                  if (canControlService) ...[
                    PrimaryButton(
                      icon: serviceRunning
                          ? LucideIcons.square
                          : LucideIcons.play,
                      label: serviceRunning ? '停止服务' : '启动服务',
                      onPressed: onToggleService,
                    ),
                    const SizedBox(width: 8),
                  ],
                  SecondaryButton(
                    icon: LucideIcons.refreshCw,
                    label: '刷新状态',
                    onPressed: () {},
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 25),
        SectionHeader(title: '实例状态', action: '查看全部', onAction: onOpenInstances),
        const SizedBox(height: 8),
        const Surface(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _InstanceRow(
                initial: '主',
                name: '主账号',
                detail: '每日任务 · 最后同步 2 分钟前',
                status: InstanceStatus.running,
              ),
              Divider(height: 1),
              _InstanceRow(
                initial: '小',
                name: '小号',
                detail: '等待初始化 · 上次运行昨天',
                status: InstanceStatus.idle,
              ),
            ],
          ),
        ),
        const SizedBox(height: 25),
        SectionHeader(
          title: '活动日历',
          subtitle: '更新于 2026/09/10 08:00',
          action: '刷新',
          actionIcon: LucideIcons.refreshCw,
          onAction: () {},
        ),
        const SizedBox(height: 9),
        SizedBox(
          height: 31,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: const [
              NkasFilterChip(label: '全部', active: true),
              NkasFilterChip(label: '招募'),
              NkasFilterChip(label: 'Raid'),
              NkasFilterChip(label: '超频'),
              NkasFilterChip(label: '时装'),
              NkasFilterChip(label: '剧情活动'),
              NkasFilterChip(label: '竞技场'),
            ],
          ),
        ),
        const SizedBox(height: 9),
        const _EventCard(),
      ],
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard();

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final scheme = theme.colorScheme;
    return Surface(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Container(
            height: 66,
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
            alignment: Alignment.bottomLeft,
            color: scheme.eventBannerDefault,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: NkasColors.eventBadgeBg,
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Text(
                '剧情活动',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: Text('当前剧情活动', style: theme.textTheme.h4)),
                    const Tag(label: 'PASS'),
                  ],
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('活动任务、商店与签到持续开放', style: theme.textTheme.muted),
                ),
                const Divider(height: 20),
                const _EventTime(label: '开始', value: '2026/09/03 05:00'),
                const _EventTime(label: '结束', value: '2026/09/24 04:59'),
                const _EventTime(label: '剩余', value: '15天 12小时', active: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InstanceRow extends StatelessWidget {
  const _InstanceRow({
    required this.initial,
    required this.name,
    required this.detail,
    required this.status,
  });
  final String initial;
  final String name;
  final String detail;
  final InstanceStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 68),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Avatar(text: initial),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(detail, style: theme.textTheme.muted),
                ],
              ),
            ),
            Status(status: status),
            const SizedBox(width: 5),
            Icon(
              LucideIcons.chevronRight,
              size: 15,
              color: theme.colorScheme.mutedForeground,
            ),
          ],
        ),
      ),
    );
  }
}

class _EventTime extends StatelessWidget {
  const _EventTime({
    required this.label,
    required this.value,
    this.active = false,
  });
  final String label;
  final String value;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.muted)),
          Text(
            value,
            style: TextStyle(
              color: active
                  ? theme.colorScheme.success
                  : theme.colorScheme.foreground,
              fontSize: 11,
              fontWeight: active ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
