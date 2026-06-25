import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../app_controller.dart';
import '../constants.dart';
import '../models.dart';
import '../services/update_check_service.dart';
import 'game_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.controller});

  final AppController controller;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _lastMessage;
  String? _activeAnnouncementId;

  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.checkForUpdates(silent: true));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        _showMessageIfNeeded();
        _showAnnouncementIfNeeded();

        final controller = widget.controller;
        if (!controller.initialized && controller.busy) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return Scaffold(
          backgroundColor: _LauncherColors.pageBackground(context),
          body: SafeArea(
            child: _LauncherHome(
              controller: controller,
              onStartGame: _startGame,
              onImportResources: widget.controller.importResources,
              onOpenGitHub: _openGitHub,
              onOpenRelease: _openRelease,
              onDeferUpdate: widget.controller.deferUpdate,
              onCheckUpdates: widget.controller.checkForUpdates,
              onShowDiagnostics: _showDiagnostics,
              onShowDisclaimer: _showDisclaimer,
              onCopyResourceRoot: _copyResourceRoot,
            ),
          ),
        );
      },
    );
  }

  void _showMessageIfNeeded() {
    final message = widget.controller.message;
    if (message == null || message == _lastMessage) {
      return;
    }
    _lastMessage = message;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    });
  }

  Future<void> _openGitHub() async {
    final browser = ChromeSafariBrowser();
    await browser.open(url: WebUri(githubUrl));
  }

  Future<void> _openRelease(UpdateInfo update) async {
    final browser = ChromeSafariBrowser();
    await browser.open(url: WebUri(update.releaseUrl));
  }

  Future<void> _openAnnouncementLink(AnnouncementLink link) async {
    final browser = ChromeSafariBrowser();
    await browser.open(url: WebUri(link.url));
  }

  void _showAnnouncementIfNeeded() {
    final announcement = widget.controller.pendingAnnouncement;
    if (announcement == null || announcement.id == _activeAnnouncementId) {
      return;
    }

    _activeAnnouncementId = announcement.id;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted ||
          widget.controller.pendingAnnouncement?.id != announcement.id) {
        _activeAnnouncementId = null;
        return;
      }

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text(announcement.title),
          content: SingleChildScrollView(
            child: Text(announcement.message),
          ),
          actions: [
            for (final link in announcement.links)
              TextButton.icon(
                onPressed: () => _openAnnouncementLink(link),
                icon: const Icon(Icons.open_in_new),
                label: Text(link.label),
              ),
            TextButton(
              onPressed: () async {
                await widget.controller.dismissAnnouncement(announcement);
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              },
              child: const Text('关闭'),
            ),
          ],
        ),
      );

      if (mounted && _activeAnnouncementId == announcement.id) {
        _activeAnnouncementId = null;
      }
    });
  }

  Future<void> _startGame() async {
    try {
      await widget.controller.startGame();
      if (!mounted) {
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => GamePage(controller: widget.controller),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法启动游戏：$error')),
      );
    }
  }

  Future<void> _showDisclaimer() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('来源和免责声明'),
        content: const Text(disclaimerText),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _showDiagnostics() async {
    final text = widget.controller.diagnostics().toCopyText();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('诊断信息'),
        content: SingleChildScrollView(
          child: SelectableText(text),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (context.mounted) {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('诊断信息已复制')),
                );
              }
            },
            icon: const Icon(Icons.copy),
            label: const Text('复制'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _copyResourceRoot() async {
    await Clipboard.setData(
      ClipboardData(text: widget.controller.userVisibleRoot),
    );
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('资源根目录已复制')),
    );
  }
}

class _LauncherHome extends StatelessWidget {
  const _LauncherHome({
    required this.controller,
    required this.onStartGame,
    required this.onImportResources,
    required this.onOpenGitHub,
    required this.onOpenRelease,
    required this.onDeferUpdate,
    required this.onCheckUpdates,
    required this.onShowDiagnostics,
    required this.onShowDisclaimer,
    required this.onCopyResourceRoot,
  });

  final AppController controller;
  final Future<void> Function() onStartGame;
  final Future<void> Function() onImportResources;
  final Future<void> Function() onOpenGitHub;
  final Future<void> Function(UpdateInfo update) onOpenRelease;
  final void Function(UpdateInfo update) onDeferUpdate;
  final Future<void> Function() onCheckUpdates;
  final Future<void> Function() onShowDiagnostics;
  final Future<void> Function() onShowDisclaimer;
  final Future<void> Function() onCopyResourceRoot;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.max(constraints.maxWidth, 980.0);
        final height = math.max(constraints.maxHeight, 620.0);

        return SingleChildScrollView(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              height: height,
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _LauncherNavigation(
                          onCheckUpdates: onCheckUpdates,
                          onShowDiagnostics: onShowDiagnostics,
                          onShowDisclaimer: onShowDisclaimer,
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: _LauncherMainColumn(
                            controller: controller,
                            onImportResources: onImportResources,
                            onOpenGitHub: onOpenGitHub,
                            onCopyResourceRoot: onCopyResourceRoot,
                          ),
                        ),
                        const SizedBox(width: 20),
                        SizedBox(
                          width: 340,
                          child: _LauncherSideColumn(
                            controller: controller,
                            onOpenRelease: onOpenRelease,
                            onDeferUpdate: onDeferUpdate,
                            onShowDisclaimer: onShowDisclaimer,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    right: 28,
                    bottom: 26,
                    child: _StartGameButton(
                      enabled: controller.canStartGame && !controller.busy,
                      onPressed: onStartGame,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LauncherNavigation extends StatelessWidget {
  const _LauncherNavigation({
    required this.onCheckUpdates,
    required this.onShowDiagnostics,
    required this.onShowDisclaimer,
  });

  final Future<void> Function() onCheckUpdates;
  final Future<void> Function() onShowDiagnostics;
  final Future<void> Function() onShowDisclaimer;

  @override
  Widget build(BuildContext context) {
    return _LauncherPanel(
      width: 108,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      child: Column(
        children: [
          _NavItem(
            icon: Icons.inventory_2_outlined,
            label: '资源',
            selected: true,
            onTap: () {},
          ),
          const SizedBox(height: 8),
          _NavItem(
            icon: Icons.system_update_alt,
            label: '更新',
            onTap: onCheckUpdates,
          ),
          const SizedBox(height: 8),
          _NavItem(
            icon: Icons.monitor_heart_outlined,
            label: '诊断',
            onTap: onShowDiagnostics,
          ),
          const SizedBox(height: 8),
          _NavItem(
            icon: Icons.info_outline,
            label: '关于',
            onTap: onShowDisclaimer,
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground =
        selected ? colors.primary : _LauncherColors.secondaryText(context);
    final background =
        selected ? colors.primary.withValues(alpha: 0.12) : Colors.transparent;

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: SizedBox(
            height: 68,
            width: double.infinity,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: foreground, size: 24),
                const SizedBox(height: 6),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: foreground,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LauncherMainColumn extends StatelessWidget {
  const _LauncherMainColumn({
    required this.controller,
    required this.onImportResources,
    required this.onOpenGitHub,
    required this.onCopyResourceRoot,
  });

  final AppController controller;
  final Future<void> Function() onImportResources;
  final Future<void> Function() onOpenGitHub;
  final Future<void> Function() onCopyResourceRoot;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 102),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _LauncherTitle(controller: controller),
            const SizedBox(height: 22),
            _ResourceHeroCard(controller: controller),
            const SizedBox(height: 18),
            _ResourceDetailsCard(
              controller: controller,
              onCopyResourceRoot: onCopyResourceRoot,
            ),
            const SizedBox(height: 18),
            _QuickActionsCard(
              controller: controller,
              onImportResources: onImportResources,
              onOpenGitHub: onOpenGitHub,
            ),
            if (controller.importProgress.phase != ImportPhase.idle) ...[
              const SizedBox(height: 18),
              _ImportProgressView(progress: controller.importProgress),
            ],
          ],
        ),
      ),
    );
  }
}

class _LauncherTitle extends StatelessWidget {
  const _LauncherTitle({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final canStart = controller.canStartGame;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                appDisplayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                      color: _LauncherColors.primaryText(context),
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                'Gardendless 游戏资源启动器',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: _LauncherColors.secondaryText(context),
                    ),
              ),
            ],
          ),
        ),
        _StatusPill(
          label: canStart ? '可启动' : '需导入',
          color: canStart ? const Color(0xff34c759) : const Color(0xffff9f0a),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    );
  }
}

class _ResourceHeroCard extends StatelessWidget {
  const _ResourceHeroCard({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final hasCurrent = controller.hasCurrentResource;
    final statusLabel = hasCurrent ? '资源已就绪' : '需要导入资源';
    final integrityLabel = hasCurrent ? '资源完整' : '等待校验';
    final progress = hasCurrent ? 1.0 : 0.0;

    return _LauncherPanel(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          const _AppIconMark(),
          const SizedBox(width: 22),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  controller.detectedTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: _LauncherColors.primaryText(context),
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  statusLabel,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: _LauncherColors.secondaryText(context),
                      ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Icon(
                      hasCurrent
                          ? Icons.check_circle
                          : Icons.error_outline_rounded,
                      size: 22,
                      color: hasCurrent
                          ? const Color(0xff34c759)
                          : const Color(0xffff9f0a),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      integrityLabel,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: _LauncherColors.primaryText(context),
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const Spacer(),
                    Text(
                      '${(progress * 100).round()}%',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: _LauncherColors.secondaryText(context),
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 7,
                    value: progress,
                    backgroundColor:
                        _LauncherColors.separator(context).withValues(
                      alpha: 0.65,
                    ),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      hasCurrent
                          ? const Color(0xff34c759)
                          : const Color(0xffff9f0a),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AppIconMark extends StatelessWidget {
  const _AppIconMark();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xffd7f8df),
            Color(0xff65d16f),
            Color(0xff1a9d4a),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xff34c759).withValues(alpha: 0.22),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: const SizedBox(
        width: 92,
        height: 92,
        child: Icon(
          Icons.local_florist_outlined,
          size: 44,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _ResourceDetailsCard extends StatelessWidget {
  const _ResourceDetailsCard({
    required this.controller,
    required this.onCopyResourceRoot,
  });

  final AppController controller;
  final Future<void> Function() onCopyResourceRoot;

  @override
  Widget build(BuildContext context) {
    final validationStatus = controller.hasCurrentResource ? '校验通过' : '等待导入';
    final serverStatus = switch (controller.serverStatus) {
      ServerStatus.running => '运行中',
      ServerStatus.starting => '启动中',
      ServerStatus.failed => '异常',
      ServerStatus.stopped => controller.hasCurrentResource ? '待启动' : '未启动',
    };

    return _GroupedPanel(
      children: [
        _InfoRow(
          icon: Icons.folder_outlined,
          label: '资源根目录',
          value: controller.userVisibleRoot,
          trailing: TextButton.icon(
            onPressed: onCopyResourceRoot,
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('复制'),
          ),
        ),
        _InfoRow(
          icon: Icons.verified_outlined,
          label: '资源校验',
          value: validationStatus,
          statusColor: controller.hasCurrentResource
              ? const Color(0xff34c759)
              : const Color(0xffff9f0a),
        ),
        _InfoRow(
          icon: Icons.settings_ethernet_rounded,
          label: '本地服务',
          value: '$localServerHost:$localServerPort',
          detail: serverStatus,
          statusColor: controller.serverStatus == ServerStatus.failed
              ? const Color(0xffff3b30)
              : const Color(0xff34c759),
        ),
      ],
    );
  }
}

class _QuickActionsCard extends StatelessWidget {
  const _QuickActionsCard({
    required this.controller,
    required this.onImportResources,
    required this.onOpenGitHub,
  });

  final AppController controller;
  final Future<void> Function() onImportResources;
  final Future<void> Function() onOpenGitHub;

  @override
  Widget build(BuildContext context) {
    return _LauncherPanel(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '快捷操作',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: _LauncherColors.primaryText(context),
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  icon: Icons.file_upload_outlined,
                  label:
                      controller.hasCurrentResource ? '选择 ZIP 更新' : '选择 ZIP 导入',
                  onPressed: controller.busy || controller.isImporting
                      ? null
                      : onImportResources,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ActionButton(
                  icon: Icons.open_in_new,
                  label: '打开 GitHub',
                  onPressed: onOpenGitHub,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side: BorderSide(color: _LauncherColors.separator(context)),
      ),
    );
  }
}

class _LauncherSideColumn extends StatelessWidget {
  const _LauncherSideColumn({
    required this.controller,
    required this.onOpenRelease,
    required this.onDeferUpdate,
    required this.onShowDisclaimer,
  });

  final AppController controller;
  final Future<void> Function(UpdateInfo update) onOpenRelease;
  final void Function(UpdateInfo update) onDeferUpdate;
  final Future<void> Function() onShowDisclaimer;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 118),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StartupHealthPanel(controller: controller),
            if (controller.availableUpdate != null) ...[
              const SizedBox(height: 18),
              _UpdateNotice(
                update: controller.availableUpdate!,
                onOpenRelease: onOpenRelease,
                onDefer: onDeferUpdate,
              ),
            ],
            const SizedBox(height: 18),
            _LauncherPanel(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '说明',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: _LauncherColors.primaryText(context),
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '本加载器不内置游戏资源，请自行获取并导入本地 ZIP。',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: _LauncherColors.secondaryText(context),
                          height: 1.35,
                        ),
                  ),
                  const SizedBox(height: 14),
                  TextButton(
                    onPressed: onShowDisclaimer,
                    child: const Text('免责声明'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StartupHealthPanel extends StatelessWidget {
  const _StartupHealthPanel({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final hasResource = controller.hasCurrentResource;
    final lastSelfCheck = controller.manifest.lastSelfCheckAt == null
        ? (hasResource ? '未执行' : '等待导入')
        : '已通过';
    final lastError = controller.manifest.lastErrorMessage ?? '无';

    return _LauncherPanel(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '启动健康',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: _LauncherColors.primaryText(context),
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 14),
          _HealthRow(
            icon: Icons.verified_outlined,
            label: '资源完整性',
            value: hasResource ? '正常' : '缺失',
            color:
                hasResource ? const Color(0xff34c759) : const Color(0xffff9f0a),
          ),
          _HealthRow(
            icon: Icons.fact_check_outlined,
            label: '上次自检',
            value: lastSelfCheck,
            color: controller.manifest.lastSelfCheckAt == null
                ? _LauncherColors.secondaryText(context)
                : const Color(0xff34c759),
          ),
          _HealthRow(
            icon: Icons.error_outline_rounded,
            label: '最近错误',
            value: lastError,
            color: controller.manifest.lastErrorMessage == null
                ? _LauncherColors.secondaryText(context)
                : const Color(0xffff3b30),
          ),
        ],
      ),
    );
  }
}

class _HealthRow extends StatelessWidget {
  const _HealthRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Icon(icon, size: 22, color: _LauncherColors.secondaryText(context)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: _LauncherColors.primaryText(context),
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: _LauncherColors.secondaryText(context),
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
          const SizedBox(width: 8),
          DecoratedBox(
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: const SizedBox(width: 8, height: 8),
          ),
        ],
      ),
    );
  }
}

class _StartGameButton extends StatelessWidget {
  const _StartGameButton({
    required this.enabled,
    required this.onPressed,
  });

  final bool enabled;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    final button = FilledButton.icon(
      key: const ValueKey('home-start-game-button'),
      onPressed: enabled ? onPressed : null,
      icon: const Icon(Icons.play_arrow_rounded, size: 34),
      label: const Text('开始游戏'),
      style: FilledButton.styleFrom(
        minimumSize: const Size(224, 72),
        padding: const EdgeInsets.symmetric(horizontal: 30),
        backgroundColor: const Color(0xff0a84ff),
        disabledBackgroundColor:
            _LauncherColors.separator(context).withValues(alpha: 0.7),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        textStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
        elevation: enabled ? 12 : 0,
        shadowColor: const Color(0xff0a84ff).withValues(alpha: 0.3),
      ),
    );

    if (enabled) {
      return button;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '请先导入资源',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _LauncherColors.secondaryText(context),
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 8),
        button,
      ],
    );
  }
}

class _UpdateNotice extends StatelessWidget {
  const _UpdateNotice({
    required this.update,
    required this.onOpenRelease,
    required this.onDefer,
  });

  final UpdateInfo update;
  final Future<void> Function(UpdateInfo update) onOpenRelease;
  final void Function(UpdateInfo update) onDefer;

  @override
  Widget build(BuildContext context) {
    return _LauncherPanel(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.system_update_alt, color: Color(0xff0a84ff)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '发现新版本 v${update.latestVersion}',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: _LauncherColors.primaryText(context),
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '当前版本 ${update.currentVersion}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: _LauncherColors.secondaryText(context),
                ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => onOpenRelease(update),
                icon: const Icon(Icons.open_in_new),
                label: const Text('查看 GitHub Release'),
              ),
              TextButton(
                onPressed: () => onDefer(update),
                child: const Text('稍后提醒'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ImportProgressView extends StatelessWidget {
  const _ImportProgressView({required this.progress});

  final ImportProgress progress;

  @override
  Widget build(BuildContext context) {
    final total = progress.totalBytes;
    final value = total <= 0 ? null : progress.copiedBytes / total;
    return _LauncherPanel(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            progress.message ?? '处理中',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: _LauncherColors.primaryText(context),
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(value: value),
          const SizedBox(height: 8),
          Text(
            '${progress.copiedFiles}/${progress.totalFiles} 文件，'
            '${progress.copiedBytes}/${progress.totalBytes} 字节',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _LauncherColors.secondaryText(context),
                ),
          ),
        ],
      ),
    );
  }
}

class _GroupedPanel extends StatelessWidget {
  const _GroupedPanel({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return _LauncherPanel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            children[index],
            if (index != children.length - 1)
              Divider(
                height: 1,
                indent: 72,
                color: _LauncherColors.separator(context),
              ),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.detail,
    this.statusColor,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? detail;
  final Color? statusColor;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 70),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 26, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 20),
            Expanded(
              flex: 2,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: _LauncherColors.primaryText(context),
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 3,
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: _LauncherColors.secondaryText(context),
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ),
            if (detail != null) ...[
              const SizedBox(width: 10),
              Text(
                detail!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: _LauncherColors.secondaryText(context),
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ],
            if (statusColor != null) ...[
              const SizedBox(width: 10),
              Icon(Icons.check_circle, size: 20, color: statusColor),
            ],
            if (trailing != null) ...[
              const SizedBox(width: 10),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

class _LauncherPanel extends StatelessWidget {
  const _LauncherPanel({
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.width,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final borderColor = _LauncherColors.separator(context).withValues(
      alpha: Theme.of(context).brightness == Brightness.dark ? 0.5 : 0.75,
    );
    final panel = DecoratedBox(
      decoration: BoxDecoration(
        color: _LauncherColors.panelBackground(context),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor),
        boxShadow: [
          if (Theme.of(context).brightness == Brightness.light)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 32,
              offset: const Offset(0, 18),
            ),
        ],
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );

    if (width == null) {
      return panel;
    }
    return SizedBox(width: width, child: panel);
  }
}

class _LauncherColors {
  const _LauncherColors._();

  static bool _isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color pageBackground(BuildContext context) =>
      _isDark(context) ? const Color(0xff101114) : const Color(0xfff5f5f7);

  static Color panelBackground(BuildContext context) => _isDark(context)
      ? const Color(0xff1c1c1e).withValues(alpha: 0.86)
      : Colors.white.withValues(alpha: 0.88);

  static Color primaryText(BuildContext context) =>
      _isDark(context) ? const Color(0xfff5f5f7) : const Color(0xff1d1d1f);

  static Color secondaryText(BuildContext context) =>
      _isDark(context) ? const Color(0xffa1a1aa) : const Color(0xff6e6e73);

  static Color separator(BuildContext context) =>
      _isDark(context) ? const Color(0xff38383a) : const Color(0xffd8d8dc);
}
