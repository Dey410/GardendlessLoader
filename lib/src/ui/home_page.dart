import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../app_controller.dart';
import '../constants.dart';
import '../models.dart';
import '../services/update_check_service.dart';
import 'game_page.dart';

enum _LauncherSection { resources, diagnostics }

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.controller});

  final AppController controller;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _lastMessage;
  _LauncherSection _selectedSection = _LauncherSection.resources;

  @override
  void initState() {
    super.initState();
    unawaited(SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: const [SystemUiOverlay.top],
    ));
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    unawaited(widget.controller.checkForUpdates(silent: true));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        _showMessageIfNeeded();

        final controller = widget.controller;
        if (!controller.initialized && controller.busy) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return Scaffold(
          backgroundColor: _LauncherColors.pageBackground(context),
          body: DecoratedBox(
            decoration: BoxDecoration(
              gradient: _LauncherColors.pageGradient(context),
            ),
            child: SafeArea(
              child: _LauncherHome(
                controller: controller,
                selectedSection: _selectedSection,
                onStartGame: _startGame,
                onImportResources: widget.controller.importResources,
                onOpenGitHub: _openGitHub,
                onOpenRelease: _openRelease,
                onDeferUpdate: widget.controller.deferUpdate,
                onCheckUpdates: widget.controller.checkForUpdates,
                onShowResources: _showResources,
                onShowDiagnostics: _showDiagnostics,
                onOpenExternalUrl: _openExternalUrl,
                onCopyResourceRoot: _copyResourceRoot,
                onCopyDiagnostics: _copyDiagnostics,
              ),
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
    await _openExternalUrl(githubUrl);
  }

  Future<void> _openRelease(UpdateInfo update) async {
    final browser = ChromeSafariBrowser();
    await browser.open(url: WebUri(update.releaseUrl));
  }

  Future<void> _openExternalUrl(String url) async {
    final browser = ChromeSafariBrowser();
    await browser.open(url: WebUri(url));
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

  void _showResources() {
    if (_selectedSection == _LauncherSection.resources) {
      return;
    }
    setState(() {
      _selectedSection = _LauncherSection.resources;
    });
  }

  Future<void> _showDiagnostics() async {
    if (_selectedSection == _LauncherSection.diagnostics) {
      return;
    }
    setState(() {
      _selectedSection = _LauncherSection.diagnostics;
    });
  }

  Future<void> _copyDiagnostics() async {
    final text = widget.controller.diagnostics().toCopyText();
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('日志信息已复制')),
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
    required this.selectedSection,
    required this.onStartGame,
    required this.onImportResources,
    required this.onOpenGitHub,
    required this.onOpenRelease,
    required this.onDeferUpdate,
    required this.onCheckUpdates,
    required this.onShowResources,
    required this.onShowDiagnostics,
    required this.onOpenExternalUrl,
    required this.onCopyResourceRoot,
    required this.onCopyDiagnostics,
  });

  final AppController controller;
  final _LauncherSection selectedSection;
  final Future<void> Function() onStartGame;
  final Future<void> Function() onImportResources;
  final Future<void> Function() onOpenGitHub;
  final Future<void> Function(UpdateInfo update) onOpenRelease;
  final void Function(UpdateInfo update) onDeferUpdate;
  final Future<void> Function() onCheckUpdates;
  final VoidCallback onShowResources;
  final Future<void> Function() onShowDiagnostics;
  final Future<void> Function(String url) onOpenExternalUrl;
  final Future<void> Function() onCopyResourceRoot;
  final Future<void> Function() onCopyDiagnostics;

  static const double _minSurfaceWidth = 980;
  static const double _minSurfaceHeight = 680;
  static const double _outerPadding = 12;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth =
            math.max(1.0, constraints.maxWidth - _outerPadding * 2);
        final availableHeight =
            math.max(1.0, constraints.maxHeight - _outerPadding * 2);
        final scale = math.min(
          1.0,
          math.min(
            availableWidth / _minSurfaceWidth,
            availableHeight / _minSurfaceHeight,
          ),
        );
        final width = math.max(_minSurfaceWidth, availableWidth / scale);
        final height = math.max(_minSurfaceHeight, availableHeight / scale);

        return Padding(
          padding: const EdgeInsets.all(_outerPadding),
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: width,
              height: height,
              child: _LauncherWorkbench(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _LauncherNavigation(
                      selectedSection: selectedSection,
                      onCheckUpdates: onCheckUpdates,
                      onShowResources: onShowResources,
                      onShowDiagnostics: onShowDiagnostics,
                    ),
                    if (selectedSection == _LauncherSection.resources) ...[
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(26, 24, 24, 24),
                          child: _LauncherMainColumn(
                            controller: controller,
                            onImportResources: onImportResources,
                            onOpenGitHub: onOpenGitHub,
                            onCopyResourceRoot: onCopyResourceRoot,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 348,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(0, 24, 24, 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: _LauncherSideColumn(
                                  controller: controller,
                                  onOpenRelease: onOpenRelease,
                                  onDeferUpdate: onDeferUpdate,
                                  onOpenExternalUrl: onOpenExternalUrl,
                                ),
                              ),
                              const SizedBox(height: 20),
                              _StartGameButton(
                                enabled:
                                    controller.canStartGame && !controller.busy,
                                onPressed: onStartGame,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ] else
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(26, 24, 24, 24),
                          child: _DiagnosticsLogView(
                            controller: controller,
                            onCopyDiagnostics: onCopyDiagnostics,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LauncherWorkbench extends StatelessWidget {
  const _LauncherWorkbench({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(32);

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: _LauncherColors.workbenchGradient(context),
            borderRadius: radius,
            border: Border.all(
              color: _LauncherColors.glassBorder(context),
            ),
            boxShadow: [
              if (Theme.of(context).brightness == Brightness.light)
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10),
                  blurRadius: 46,
                  offset: const Offset(0, 24),
                ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _LauncherNavigation extends StatelessWidget {
  const _LauncherNavigation({
    required this.selectedSection,
    required this.onCheckUpdates,
    required this.onShowResources,
    required this.onShowDiagnostics,
  });

  final _LauncherSection selectedSection;
  final Future<void> Function() onCheckUpdates;
  final VoidCallback onShowResources;
  final Future<void> Function() onShowDiagnostics;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: const ValueKey('launcher-navigation-rail'),
      child: SizedBox(
        width: 164,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _LauncherColors.navigationBackground(context),
            border: Border(
              right: BorderSide(color: _LauncherColors.sidebarBorder(context)),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 20, 12, 20),
            child: Column(
              children: [
                _NavItem(
                  icon: Icons.view_in_ar_rounded,
                  label: '资源',
                  selected: selectedSection == _LauncherSection.resources,
                  onTap: onShowResources,
                ),
                const SizedBox(height: 8),
                _NavItem(
                  icon: Icons.download_for_offline_rounded,
                  label: '更新',
                  onTap: onCheckUpdates,
                ),
                const SizedBox(height: 8),
                _NavItem(
                  icon: Icons.terminal_rounded,
                  label: '日志',
                  selected: selectedSection == _LauncherSection.diagnostics,
                  onTap: onShowDiagnostics,
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
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
    final background = selected
        ? _LauncherColors.selectedNavigationBackground(context)
        : Colors.transparent;

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
            height: 58,
            width: double.infinity,
            child: Row(
              children: [
                const SizedBox(width: 13),
                Icon(icon, color: foreground, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: foreground,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w600,
                          letterSpacing: 0,
                        ),
                  ),
                ),
                const SizedBox(width: 10),
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
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _LauncherTitle(controller: controller),
            const SizedBox(height: 20),
            _ResourceHeroCard(controller: controller),
            const SizedBox(height: 16),
            _ResourceDetailsCard(
              controller: controller,
              onCopyResourceRoot: onCopyResourceRoot,
            ),
            const SizedBox(height: 16),
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

class _DiagnosticsLogView extends StatelessWidget {
  const _DiagnosticsLogView({
    required this.controller,
    required this.onCopyDiagnostics,
  });

  final AppController controller;
  final Future<void> Function() onCopyDiagnostics;

  @override
  Widget build(BuildContext context) {
    final diagnostics = controller.diagnostics();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _LauncherPanel(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PanelTitle(
                  icon: Icons.terminal_rounded,
                  iconColor: _LauncherColors.service,
                  label: '日志信息',
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: _DiagnosticsLogBox(text: diagnostics.toLogText()),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            key: const ValueKey('copy-diagnostics-button'),
            onPressed: onCopyDiagnostics,
            icon: const Icon(Icons.copy_rounded),
            label: const Text('复制日志信息'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(178, 52),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              backgroundColor: _LauncherColors.accentBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              textStyle: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
              elevation: 0,
            ),
          ),
        ),
      ],
    );
  }
}

class _DiagnosticsLogBox extends StatelessWidget {
  const _DiagnosticsLogBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xff101114).withValues(alpha: 0.72)
            : const Color(0xfff8fafc).withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _LauncherColors.separator(context).withValues(alpha: 0.62),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SelectableText(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: _LauncherColors.primaryText(context),
                    fontFamily: 'monospace',
                    height: 1.45,
                    letterSpacing: 0,
                  ),
            ),
          ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                appDisplayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                      color: _LauncherColors.primaryText(context),
                      height: 1.04,
                    ),
              ),
            ),
            const SizedBox(width: 12),
            _StatusPill(
              label: canStart ? '可启动' : '需导入',
              color:
                  canStart ? _LauncherColors.success : _LauncherColors.warning,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Gardendless 游戏资源启动器',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: _LauncherColors.secondaryText(context),
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
              ),
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
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
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
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
      emphasized: true,
      child: Row(
        children: [
          const _AppIconMark(),
          const SizedBox(width: 24),
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
                        fontWeight: FontWeight.w500,
                      ),
                ),
                const SizedBox(height: 17),
                Row(
                  children: [
                    Icon(
                      hasCurrent
                          ? Icons.check_circle_rounded
                          : Icons.error_outline_rounded,
                      size: 22,
                      color: hasCurrent
                          ? _LauncherColors.success
                          : _LauncherColors.warning,
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
                          ? _LauncherColors.success
                          : _LauncherColors.warning,
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
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: _LauncherColors.success.withValues(alpha: 0.22),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Image.asset(
          'tool/generated_icons/app_icon_master.png',
          fit: BoxFit.cover,
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
    final validationColor = controller.hasCurrentResource
        ? _LauncherColors.success
        : _LauncherColors.warning;
    final serverColor = controller.serverStatus == ServerStatus.failed
        ? _LauncherColors.danger
        : _LauncherColors.service;

    return _GroupedPanel(
      title: '资源信息',
      icon: Icons.inventory_2_rounded,
      iconColor: _LauncherColors.accentBlue,
      children: [
        _InfoRow(
          icon: Icons.folder_rounded,
          iconColor: _LauncherColors.accentBlue,
          label: '资源根目录',
          value: controller.userVisibleRoot,
          trailing: TextButton.icon(
            key: const ValueKey('copy-resource-root-button'),
            onPressed: onCopyResourceRoot,
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('复制'),
            style: TextButton.styleFrom(
              foregroundColor: _LauncherColors.accentBlue,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        _InfoRow(
          icon: Icons.verified_rounded,
          iconColor: validationColor,
          label: '资源校验',
          value: validationStatus,
          statusColor: validationColor,
        ),
        _InfoRow(
          icon: Icons.settings_ethernet_rounded,
          iconColor: serverColor,
          label: '本地服务',
          value: '$localServerHost:$localServerPort',
          detail: serverStatus,
          statusColor: serverColor,
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
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PanelTitle(
            icon: Icons.bolt_rounded,
            iconColor: _LauncherColors.warning,
            label: '快捷操作',
          ),
          const SizedBox(height: 14),
          _InsetListCard(
            children: [
              _ActionRow(
                icon: Icons.upload_rounded,
                iconColor: _LauncherColors.warning,
                label:
                    controller.hasCurrentResource ? '选择 ZIP 更新' : '选择 ZIP 导入',
                onPressed: controller.busy || controller.isImporting
                    ? null
                    : onImportResources,
                trailingIcon: Icons.chevron_right_rounded,
              ),
              _ActionRow(
                icon: Icons.open_in_new_rounded,
                iconColor: _LauncherColors.secondaryText(context),
                label: '打开 GitHub',
                onPressed: onOpenGitHub,
                trailingIcon: Icons.open_in_new_rounded,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onPressed,
    required this.trailingIcon,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback? onPressed;
  final IconData trailingIcon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onPressed,
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              const SizedBox(width: 14),
              Icon(icon, color: iconColor, size: 23),
              const SizedBox(width: 15),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: onPressed == null
                            ? _LauncherColors.secondaryText(context)
                            : _LauncherColors.primaryText(context),
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              Icon(
                trailingIcon,
                size: 19,
                color: _LauncherColors.secondaryText(context),
              ),
              const SizedBox(width: 14),
            ],
          ),
        ),
      ),
    );
  }
}

class _LauncherSideColumn extends StatelessWidget {
  const _LauncherSideColumn({
    required this.controller,
    required this.onOpenRelease,
    required this.onDeferUpdate,
    required this.onOpenExternalUrl,
  });

  final AppController controller;
  final Future<void> Function(UpdateInfo update) onOpenRelease;
  final void Function(UpdateInfo update) onDeferUpdate;
  final Future<void> Function(String url) onOpenExternalUrl;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StartupHealthPanel(controller: controller),
          if (controller.availableUpdate != null) ...[
            const SizedBox(height: 16),
            _UpdateNotice(
              update: controller.availableUpdate!,
              onOpenRelease: onOpenRelease,
              onDefer: onDeferUpdate,
            ),
          ],
          const SizedBox(height: 16),
          _AnnouncementPanel(
            announcement: controller.announcement,
            onOpenExternalUrl: onOpenExternalUrl,
          ),
        ],
      ),
    );
  }
}

class _AnnouncementPanel extends StatelessWidget {
  const _AnnouncementPanel({
    required this.announcement,
    required this.onOpenExternalUrl,
  });

  final Announcement? announcement;
  final Future<void> Function(String url) onOpenExternalUrl;

  @override
  Widget build(BuildContext context) {
    final links = _socialLinks();

    return _LauncherPanel(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PanelTitle(
            icon: Icons.campaign_rounded,
            iconColor: _LauncherColors.accentBlue,
            label: '公告',
          ),
          const SizedBox(height: 14),
          _AnnouncementContentBox(
            message: announcement?.message ?? '暂无新公告。',
          ),
          if (links.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(
              key: const ValueKey('announcement-social-links'),
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final link in links)
                  _AnnouncementIconLink(
                    link: link,
                    onPressed: () => onOpenExternalUrl(link.url),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _AnnouncementContentBox extends StatelessWidget {
  const _AnnouncementContentBox({
    required this.message,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const ValueKey('announcement-content-box'),
      decoration: BoxDecoration(
        color: _LauncherColors.innerPanelBackground(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _LauncherColors.separator(context).withValues(alpha: 0.72),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Text(
          message,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: _LauncherColors.secondaryText(context),
                height: 1.45,
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
              ),
        ),
      ),
    );
  }
}

class _AnnouncementIconLink extends StatelessWidget {
  const _AnnouncementIconLink({
    required this.link,
    required this.onPressed,
  });

  final AnnouncementLink link;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final color = _announcementLinkColor(context, link);

    return Tooltip(
      message: link.label,
      child: IconButton.filledTonal(
        key: ValueKey('announcement-link-${link.url}'),
        onPressed: onPressed,
        icon: _announcementLinkIcon(link),
        style: IconButton.styleFrom(
          fixedSize: const Size.square(48),
          foregroundColor: color,
          backgroundColor: _LauncherColors.innerPanelBackground(context),
          hoverColor: color.withValues(alpha: 0.08),
          highlightColor: color.withValues(alpha: 0.12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

List<AnnouncementLink> _socialLinks() {
  return const <AnnouncementLink>[
    AnnouncementLink(label: 'B站主页', url: bilibiliHomeUrl),
    AnnouncementLink(label: 'GitHub', url: appGithubUrl),
  ];
}

Widget _announcementLinkIcon(AnnouncementLink link) {
  final uri = Uri.tryParse(link.url);
  final host = uri?.host.toLowerCase() ?? '';
  if (link.url == bilibiliHomeUrl || host.contains('bilibili.com')) {
    return const FaIcon(FontAwesomeIcons.bilibili, size: 22);
  }
  if (link.url == appGithubUrl ||
      host == 'github.com' ||
      host.endsWith('.github.com')) {
    return const FaIcon(FontAwesomeIcons.github, size: 22);
  }
  return const Icon(Icons.open_in_new_rounded, size: 22);
}

Color _announcementLinkColor(BuildContext context, AnnouncementLink link) {
  final uri = Uri.tryParse(link.url);
  final host = uri?.host.toLowerCase() ?? '';
  if (link.url == bilibiliHomeUrl || host.contains('bilibili.com')) {
    return const Color(0xff00a1d6);
  }
  if (link.url == appGithubUrl ||
      host == 'github.com' ||
      host.endsWith('.github.com')) {
    return _LauncherColors.primaryText(context);
  }
  return _LauncherColors.accentBlue;
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
    final resourceColor =
        hasResource ? _LauncherColors.success : _LauncherColors.warning;
    final selfCheckColor = controller.manifest.lastSelfCheckAt == null
        ? _LauncherColors.secondaryText(context)
        : _LauncherColors.success;
    final errorColor = controller.manifest.lastErrorMessage == null
        ? _LauncherColors.secondaryText(context)
        : _LauncherColors.danger;

    return _LauncherPanel(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PanelTitle(
            icon: Icons.monitor_heart_rounded,
            iconColor: _LauncherColors.service,
            label: '诊断摘要',
          ),
          const SizedBox(height: 14),
          _InsetListCard(
            dividerIndent: 54,
            children: [
              _HealthRow(
                icon: Icons.verified_rounded,
                iconColor: resourceColor,
                label: '资源完整性',
                value: hasResource ? '正常' : '缺失',
                color: resourceColor,
              ),
              _HealthRow(
                icon: Icons.fact_check_rounded,
                iconColor: selfCheckColor,
                label: '上次自检',
                value: lastSelfCheck,
                color: selfCheckColor,
              ),
              _HealthRow(
                icon: Icons.error_outline_rounded,
                iconColor: errorColor,
                label: '最近错误',
                value: lastError,
                color: errorColor,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HealthRow extends StatelessWidget {
  const _HealthRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: Row(
        children: [
          const SizedBox(width: 14),
          Icon(icon, size: 21, color: iconColor),
          const SizedBox(width: 13),
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
          const SizedBox(width: 14),
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
      icon: const Icon(Icons.play_arrow_rounded, size: 32),
      label: const Text('开始游戏'),
      style: FilledButton.styleFrom(
        minimumSize: const Size(272, 72),
        padding: const EdgeInsets.symmetric(horizontal: 30),
        backgroundColor: _LauncherColors.accentBlue,
        foregroundColor: Colors.white,
        disabledBackgroundColor:
            _LauncherColors.separator(context).withValues(alpha: 0.78),
        disabledForegroundColor: _LauncherColors.secondaryText(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        textStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
        elevation: 0,
      ),
    );

    if (enabled) {
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: _LauncherColors.accentBlue.withValues(alpha: 0.28),
              blurRadius: 26,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: button,
      );
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
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.system_update_alt_rounded,
                color: _LauncherColors.warning,
                size: 23,
              ),
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
                icon: const Icon(Icons.open_in_new_rounded),
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
  const _GroupedPanel({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.children,
  });

  final String title;
  final IconData icon;
  final Color iconColor;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return _LauncherPanel(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PanelTitle(icon: icon, iconColor: iconColor, label: title),
          const SizedBox(height: 14),
          _InsetListCard(children: children),
        ],
      ),
    );
  }
}

class _PanelTitle extends StatelessWidget {
  const _PanelTitle({
    required this.icon,
    required this.iconColor,
    required this.label,
  });

  final IconData icon;
  final Color iconColor;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox.square(
          dimension: 30,
          child: Icon(icon, color: iconColor, size: 24),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: _LauncherColors.primaryText(context),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
          ),
        ),
      ],
    );
  }
}

class _InsetListCard extends StatelessWidget {
  const _InsetListCard({required this.children, this.dividerIndent = 64});

  final List<Widget> children;
  final double dividerIndent;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _LauncherColors.innerPanelBackground(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _LauncherColors.separator(context).withValues(alpha: 0.62),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Column(
          children: [
            for (var index = 0; index < children.length; index++) ...[
              children[index],
              if (index != children.length - 1)
                Divider(
                  height: 1,
                  indent: dividerIndent,
                  color: _LauncherColors.separator(context).withValues(
                    alpha: 0.72,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.detail,
    this.statusColor,
    this.trailing,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String? detail;
  final Color? statusColor;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 62),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 24, color: iconColor),
            const SizedBox(width: 16),
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
              flex: 4,
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
              Icon(
                statusColor == _LauncherColors.warning
                    ? Icons.error_outline_rounded
                    : Icons.check_circle_rounded,
                size: 20,
                color: statusColor,
              ),
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
    this.emphasized = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(24);
    final borderColor = _LauncherColors.separator(context).withValues(
      alpha: Theme.of(context).brightness == Brightness.dark ? 0.48 : 0.70,
    );
    final panel = ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _LauncherColors.panelBackground(context),
            borderRadius: radius,
            border: Border.all(color: borderColor),
            boxShadow: [
              if (Theme.of(context).brightness == Brightness.light)
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: emphasized ? 0.075 : 0.048,
                  ),
                  blurRadius: emphasized ? 34 : 24,
                  offset: Offset(0, emphasized ? 15 : 10),
                ),
            ],
          ),
          child: Padding(
            padding: padding,
            child: child,
          ),
        ),
      ),
    );

    final decoratedPanel = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          if (Theme.of(context).brightness == Brightness.light)
            BoxShadow(
              color: _LauncherColors.accentBlue.withValues(
                alpha: emphasized ? 0.04 : 0,
              ),
              blurRadius: emphasized ? 34 : 0,
              offset: const Offset(0, 18),
            ),
        ],
      ),
      child: panel,
    );

    return decoratedPanel;
  }
}

class _LauncherColors {
  const _LauncherColors._();

  static const Color accentBlue = Color(0xff0a84ff);
  static const Color success = Color(0xff34c759);
  static const Color warning = Color(0xffff9f0a);
  static const Color danger = Color(0xffff453a);
  static const Color service = Color(0xff7c5cff);

  static bool _isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color pageBackground(BuildContext context) =>
      _isDark(context) ? const Color(0xff101114) : const Color(0xffeef1f6);

  static Gradient pageGradient(BuildContext context) => _isDark(context)
      ? const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff121316), Color(0xff1b1c20)],
        )
      : const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xfff8fafc), Color(0xffeef2f7), Color(0xfff7f8fb)],
          stops: [0, 0.55, 1],
        );

  static Gradient workbenchGradient(BuildContext context) => _isDark(context)
      ? LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xff1c1d21).withValues(alpha: 0.94),
            const Color(0xff15161a).withValues(alpha: 0.90),
          ],
        )
      : LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.76),
            Colors.white.withValues(alpha: 0.52),
            const Color(0xfff5f7fb).withValues(alpha: 0.68),
          ],
          stops: const [0, 0.52, 1],
        );

  static Color panelBackground(BuildContext context) => _isDark(context)
      ? const Color(0xff1c1c1e).withValues(alpha: 0.86)
      : Colors.white.withValues(alpha: 0.72);

  static Color innerPanelBackground(BuildContext context) => _isDark(context)
      ? const Color(0xff242529).withValues(alpha: 0.72)
      : Colors.white.withValues(alpha: 0.54);

  static Color navigationBackground(BuildContext context) => _isDark(context)
      ? const Color(0xff17181c).withValues(alpha: 0.76)
      : const Color(0xfff6f8fc).withValues(alpha: 0.56);

  static Color selectedNavigationBackground(BuildContext context) =>
      _isDark(context)
          ? accentBlue.withValues(alpha: 0.20)
          : accentBlue.withValues(alpha: 0.12);

  static Color sidebarBorder(BuildContext context) => _isDark(context)
      ? const Color(0xff34353a).withValues(alpha: 0.62)
      : const Color(0xffd7dce6).withValues(alpha: 0.72);

  static Color glassBorder(BuildContext context) => _isDark(context)
      ? Colors.white.withValues(alpha: 0.08)
      : Colors.white.withValues(alpha: 0.74);

  static Color primaryText(BuildContext context) =>
      _isDark(context) ? const Color(0xfff5f5f7) : const Color(0xff1d1d1f);

  static Color secondaryText(BuildContext context) =>
      _isDark(context) ? const Color(0xffa1a1aa) : const Color(0xff6b7280);

  static Color separator(BuildContext context) =>
      _isDark(context) ? const Color(0xff38383a) : const Color(0xffd8dfe8);
}
