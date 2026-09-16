import 'package:flutter/material.dart';
import 'package:nkas_mobile/core/widgets/backend_auth_scope.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:nkas_mobile/core/api/calendar_info.dart';
import 'package:nkas_mobile/core/api/instance_info.dart';
import 'package:nkas_mobile/core/widgets/avatar.dart';
import 'package:nkas_mobile/core/widgets/buttons.dart';
import 'package:nkas_mobile/core/widgets/filter_chip.dart';
import 'package:nkas_mobile/core/widgets/page_inset.dart';
import 'package:nkas_mobile/core/widgets/page_subtitle.dart';
import 'package:nkas_mobile/core/widgets/section_header.dart';
import 'package:nkas_mobile/core/widgets/status.dart';
import 'package:nkas_mobile/core/widgets/surface.dart';
import 'package:nkas_mobile/core/widgets/tag.dart';
import 'package:nkas_mobile/theme.dart';

class OverviewPage extends StatelessWidget {
  const OverviewPage({
    required this.serviceRunning,
    required this.onRefreshStatus,
    required this.onOpenInstances,
    required this.onSelectInstance,
    required this.instances,
    required this.loadingInstances,
    required this.instancesError,
    required this.avatarUrl,
    required this.resolveAssetUrl,
    required this.calendarItems,
    required this.calendarUpdatedAt,
    required this.calendarLoading,
    required this.calendarError,
    required this.onRefreshCalendar,
    this.onStartService,
    this.onStopService,
    this.startingService = false,
    this.stoppingService = false,
    this.onRestartService,
    this.restartingService = false,
    super.key,
  });
  final bool serviceRunning;
  final Future<void> Function() onRefreshStatus;
  final VoidCallback onOpenInstances;
  final ValueChanged<String> onSelectInstance;
  final List<InstanceInfo> instances;
  final bool loadingInstances;
  final String? instancesError;
  final String? Function(InstanceInfo item) avatarUrl;
  final String Function(String value) resolveAssetUrl;
  final List<CalendarItem> calendarItems;
  final int calendarUpdatedAt;
  final bool calendarLoading;
  final String? calendarError;
  final Future<void> Function() onRefreshCalendar;

  /// 仅 Android 本机 Termux 部署提供；为 null 时不显示重启按钮
  final Future<void> Function()? onRestartService;
  final bool restartingService;

  /// 起停同一个服务，两个回调由 serviceRunning 决定实际生效的那个；
  /// 为 null 时不显示启动/停止按钮
  final Future<void> Function()? onStartService;
  final Future<void> Function()? onStopService;
  final bool startingService;
  final bool stoppingService;

  /// 按钮行要渲染的动作，顺序即显示顺序。起停共用一个位置：
  /// 后端连上说明服务在跑，此时只能停。
  List<Widget> get _serviceActions => [
    SecondaryButton(
      compact: true,
      icon: LucideIcons.refreshCw,
      label: '刷新状态',
      onPressed: () => onRefreshStatus(),
    ),
    if (onStartService != null || onStopService != null)
      if (serviceRunning)
        SecondaryButton(
          compact: true,
          icon: LucideIcons.square,
          label: '停止服务',
          // 停止会中断正在运行的任务，与重启同样用警示色，
          // 靠图标与文案区分这两件事
          destructive: true,
          loading: stoppingService,
          onPressed: stoppingService ? null : () => onStopService?.call(),
        )
      else
        SecondaryButton(
          compact: true,
          icon: LucideIcons.play,
          label: '启动服务',
          loading: startingService,
          onPressed: startingService ? null : () => onStartService?.call(),
        ),
    if (onRestartService != null)
      SecondaryButton(
        compact: true,
        icon: LucideIcons.rotateCcw,
        label: '重启服务',
        // 重启会中断正在运行的任务，用警示色与「刷新状态」区分开。
        destructive: true,
        loading: restartingService,
        onPressed: restartingService ? null : () => onRestartService!(),
      ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final scheme = theme.colorScheme;
    final inset = nkasPageInset(context);
    final actions = _serviceActions;
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
                        '移动端控制',
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
                        LucideIcons.server,
                        size: 14,
                        color: scheme.heroMetaIcon,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        serviceRunning ? '后端已连接' : '等待后端连接',
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
                  for (final (index, action) in actions.indexed) ...[
                    if (index > 0) const SizedBox(width: 8),
                    // 本机部署时这一行最多三个按钮，按内容宽度排会在 360 宽的
                    // 机型上溢出 7px，所以均分可用宽度；只有一个按钮时保持
                    // 按内容取宽，避免被拉成整行的长条。
                    if (actions.length > 1) Expanded(child: action) else action,
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 25),
        SectionHeader(title: '实例状态', action: '查看全部', onAction: onOpenInstances),
        const SizedBox(height: 8),
        Surface(
          padding: EdgeInsets.zero,
          child: loadingInstances
              ? const SizedBox(
                  height: 68,
                  child: Center(child: CircularProgressIndicator()),
                )
              : instances.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    instancesError == null ? '暂无实例' : '实例加载失败',
                    style: theme.textTheme.muted,
                  ),
                )
              : Column(
                  children: [
                    for (var i = 0; i < instances.take(2).length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      _InstanceRow(
                        initial: instances[i].name.characters.first,
                        name: instances[i].name,
                        detail: instances[i].detail,
                        status: instances[i].status,
                        imageUrl: avatarUrl(instances[i]),
                        onTap: () => onSelectInstance(instances[i].name),
                      ),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 25),
        _CalendarSection(
          items: calendarItems,
          updatedAt: calendarUpdatedAt,
          loading: calendarLoading,
          error: calendarError,
          onRefresh: onRefreshCalendar,
          resolveAssetUrl: resolveAssetUrl,
        ),
      ],
    );
  }

  static String _formatDateTime(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(
      timestamp * 1000,
    ).toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}/${two(date.month)}/${two(date.day)} '
        '${two(date.hour)}:${two(date.minute)}';
  }
}

class _CalendarSection extends StatefulWidget {
  const _CalendarSection({
    required this.items,
    required this.updatedAt,
    required this.loading,
    required this.error,
    required this.onRefresh,
    required this.resolveAssetUrl,
  });

  final List<CalendarItem> items;
  final int updatedAt;
  final bool loading;
  final String? error;
  final Future<void> Function() onRefresh;
  final String Function(String value) resolveAssetUrl;

  @override
  State<_CalendarSection> createState() => _CalendarSectionState();
}

class _CalendarSectionState extends State<_CalendarSection> {
  static const categories = <(String, String)>[
    ('', '全部'),
    ('character_gacha', '招募'),
    ('raid', 'Raid'),
    ('simulation_room', '超频'),
    ('skin_gacha', '时装'),
    ('version_event', '剧情活动'),
    ('arena', '竞技场'),
  ];

  String category = '';

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final visibleItems =
        (category.isEmpty
                ? widget.items
                : widget.items.where((item) => item.category == category))
            .where((item) => item.endTime > now)
            .toList()
          ..sort(
            (left, right) => left.endTime.compareTo(right.endTime) != 0
                ? left.endTime.compareTo(right.endTime)
                : left.sourceOrder.compareTo(right.sourceOrder),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: '活动日历',
          subtitle: widget.updatedAt == 0
              ? null
              : '更新于 ${OverviewPage._formatDateTime(widget.updatedAt)}',
          action: '刷新',
          actionIcon: LucideIcons.refreshCw,
          onAction: () => widget.onRefresh(),
        ),
        const SizedBox(height: 9),
        SizedBox(
          height: 31,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final item in categories)
                NkasFilterChip(
                  label: item.$2,
                  active: category == item.$1,
                  onTap: () => setState(() => category = item.$1),
                ),
            ],
          ),
        ),
        const SizedBox(height: 9),
        if (widget.loading)
          const SizedBox(
            height: 140,
            child: Center(child: CircularProgressIndicator()),
          )
        else if (visibleItems.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 22),
            child: Text(
              widget.error == null ? '暂无进行中的活动' : '活动数据加载失败',
              style: theme.textTheme.muted,
            ),
          )
        else
          for (var i = 0; i < visibleItems.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _EventCard(
              item: visibleItems[i],
              resolveAssetUrl: widget.resolveAssetUrl,
            ),
          ],
      ],
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.item, required this.resolveAssetUrl});

  final CalendarItem item;
  final String Function(String value) resolveAssetUrl;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final scheme = theme.colorScheme;
    return Surface(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 3 / 1,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: scheme.eventBannerDefault,
                image: item.bannerUrl != null && item.bannerUrl!.isNotEmpty
                    ? DecorationImage(
                        image: NetworkImage(
                          resolveAssetUrl(item.bannerUrl!),
                          headers: BackendAuthScope.headersFor(
                            context,
                            resolveAssetUrl(item.bannerUrl!),
                          ),
                        ),
                        fit: BoxFit.cover,
                        onError: (_, _) {},
                      )
                    : null,
              ),
              child: item.bannerUrl == null || item.bannerUrl!.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
                      child: _bannerLabel(context),
                    )
                  : null,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(item.title, style: theme.textTheme.h4),
                    ),
                    if (item.subtype != null && item.subtype!.isNotEmpty)
                      Tag(
                        label: item.subtype == 'pass' ? 'PASS' : item.subtype!,
                      ),
                  ],
                ),
                if (item.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(item.subtitle, style: theme.textTheme.muted),
                  ),
                ],
                const Divider(height: 20),
                _EventTime(
                  label: '开始',
                  value: OverviewPage._formatDateTime(item.startTime),
                ),
                _EventTime(
                  label: '结束',
                  value: OverviewPage._formatDateTime(item.endTime),
                ),
                _EventTime(
                  label: '剩余',
                  value: _remainingText(item.endTime),
                  active: true,
                ),
                if (item.stageEndTime != null && item.stageEndTime! > 0)
                  _EventTime(
                    label: '距离Buff重置',
                    value: _remainingText(item.stageEndTime!),
                    active: true,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bannerLabel(BuildContext context) {
    final label =
        const {
          'character_gacha': '招募',
          'raid': 'Raid',
          'simulation_room': '超频',
          'skin_gacha': '时装',
          'version_event': '剧情活动',
          'arena': '竞技场',
        }[item.category] ??
        item.category;
    return Align(
      alignment: Alignment.bottomLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: NkasColors.eventBadgeBg,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  static String _remainingText(int timestamp) {
    final seconds = (timestamp - DateTime.now().millisecondsSinceEpoch ~/ 1000)
        .clamp(0, 1 << 31);
    if (seconds < 60) return '不足1分钟';
    final days = seconds ~/ 86400;
    final hours = (seconds % 86400) ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final parts = <String>[];
    if (days > 0) parts.add('$days天');
    if (hours > 0 || days > 0) parts.add('$hours小时');
    if (days == 0) parts.add('$minutes分钟');
    return parts.join(' ');
  }
}

class _InstanceRow extends StatelessWidget {
  const _InstanceRow({
    required this.initial,
    required this.name,
    required this.detail,
    required this.status,
    this.imageUrl,
    required this.onTap,
  });
  final String initial;
  final String name;
  final String detail;
  final InstanceStatus status;
  final String? imageUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 68),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Avatar(text: initial, imageUrl: imageUrl),
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
