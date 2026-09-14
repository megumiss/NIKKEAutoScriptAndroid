import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:nkas_mobile/core/connection/connection_controller.dart';
import 'package:nkas_mobile/core/widgets/group_label.dart';
import 'package:nkas_mobile/core/widgets/icon_box.dart';
import 'package:nkas_mobile/core/widgets/page_inset.dart';
import 'package:nkas_mobile/core/widgets/page_subtitle.dart';
import 'package:nkas_mobile/core/widgets/surface.dart';
import 'package:nkas_mobile/core/widgets/tag.dart';
import 'package:nkas_mobile/theme.dart';

const appVersion = '1.1.2';

const _projectRepoUrl = 'https://github.com/megumiss/NIKKEAutoScript';
const _projectIssuesUrl = 'https://github.com/megumiss/NIKKEAutoScript/issues';

class AboutPage extends StatefulWidget {
  const AboutPage({required this.connectionController, super.key});

  final ConnectionController connectionController;

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  @override
  void initState() {
    super.initState();
    widget.connectionController.addListener(_connectionChanged);
  }

  @override
  void dispose() {
    widget.connectionController.removeListener(_connectionChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AboutPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connectionController != widget.connectionController) {
      oldWidget.connectionController.removeListener(_connectionChanged);
      widget.connectionController.addListener(_connectionChanged);
    }
  }

  void _connectionChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _openUrl(BuildContext context, String url) async {
    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开链接')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final scheme = theme.colorScheme;
    final inset = nkasPageInset(context);
    final connection = widget.connectionController.state;
    final backendVersion = connection.status?.version;
    return ListView(
      padding: EdgeInsets.fromLTRB(inset, 5, inset, 28),
      children: [
        const PageSubtitle('版本、项目链接与运行信息'),
        Surface(
          radius: 18,
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 22),
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(17),
                child: Image.asset('assets/nkas.png', width: 68, height: 68),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'NKAS Mobile',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 7),
                  Tag(label: appVersion, color: scheme.primary),
                ],
              ),
              const SizedBox(height: 6),
              Text('NIKKEAutoScript 移动控制端', style: theme.textTheme.muted),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _AboutGroup(
          label: '项目',
          rows: [
            _AboutRow(
              icon: LucideIcons.gitBranch,
              title: '项目仓库',
              subtitle: _projectRepoUrl,
              trailing: LucideIcons.externalLink,
              onTap: () => _openUrl(context, _projectRepoUrl),
            ),
            _AboutRow(
              icon: LucideIcons.bug,
              title: '问题反馈',
              subtitle: _projectIssuesUrl,
              trailing: LucideIcons.externalLink,
              onTap: () => _openUrl(context, _projectIssuesUrl),
            ),
            _AboutRow(
              icon: LucideIcons.fileText,
              title: '开源许可证',
              subtitle: 'Flutter、原生控制与第三方组件',
              trailing: LucideIcons.chevronRight,
              onTap: () => showLicensePage(
                context: context,
                applicationName: 'NKAS Mobile',
                applicationVersion: appVersion,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _AboutGroup(
          label: '运行信息',
          rows: [
            const _AboutInfoRow(title: '应用版本', value: appVersion),
            _AboutInfoRow(title: '后端版本', value: backendVersion ?? '未连接'),
            _AboutInfoRow(title: '后端地址', value: connection.baseUrl),
            const _AboutInfoRow(
              title: 'API 版本',
              value: 'v$supportedApiVersion',
            ),
            const _AboutInfoRow(title: '技术栈', value: 'Flutter + shadcn_ui'),
          ],
        ),
      ],
    );
  }
}

class _AboutGroup extends StatelessWidget {
  const _AboutGroup({required this.label, required this.rows});
  final String label;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GroupLabel(label),
        Surface(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                rows[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _AboutRow extends StatelessWidget {
  const _AboutRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final IconData trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            IconBox(icon: icon, color: theme.colorScheme.success),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.muted,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(trailing, size: 15, color: theme.colorScheme.mutedForeground),
          ],
        ),
      ),
    );
  }
}

class _AboutInfoRow extends StatelessWidget {
  const _AboutInfoRow({required this.title, required this.value});
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: theme.textTheme.muted,
            ),
          ),
        ],
      ),
    );
  }
}
