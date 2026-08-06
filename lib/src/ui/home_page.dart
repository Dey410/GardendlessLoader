import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../app_controller.dart';
import '../constants.dart';
import '../logging/app_logger.dart';
import '../logging/log_event_catalog.dart';
import '../models.dart';
import '../services/game_update_check_service.dart';
import '../services/update_check_service.dart';
import 'launcher_visuals.dart';

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
  bool _importProgressExpanded = true;
  ImportPhase _lastImportPhase = ImportPhase.idle;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
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
        _syncImportProgressExpansion(controller.importProgress.phase);
        if (!controller.initialized && controller.busy) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return Scaffold(
          backgroundColor: LauncherVisuals.pageBackground(context),
          body: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LauncherVisuals.pageGradient(context),
            ),
            child: SafeArea(
              left: false,
              right: false,
              child: _LauncherHome(
                controller: controller,
                selectedSection: _selectedSection,
                onStartGame: _startGame,
                onImportResources: widget.controller.importResources,
                onOpenGitHub: _openGitHub,
                onOpenRelease: _openRelease,
                onDeferUpdate: widget.controller.deferUpdate,
                onDeferGameUpdate: widget.controller.deferGameUpdate,
                onCheckUpdates: widget.controller.checkForUpdates,
                onShowResources: _showResources,
                onShowDiagnostics: _showDiagnostics,
                onShowAbout: _showAbout,
                onOpenExternalUrl: _openExternalUrl,
                onCopyResourceRoot: _copyResourceRoot,
                onCopyDiagnostics: _copyDiagnostics,
                onDeleteLogHistory: _deleteLogHistory,
                importProgressExpanded: _importProgressExpanded,
                onToggleImportProgress: _toggleImportProgress,
              ),
            ),
          ),
        );
      },
    );
  }

  void _syncImportProgressExpansion(ImportPhase phase) {
    final wasActive = _lastImportPhase != ImportPhase.idle &&
        _lastImportPhase != ImportPhase.completed &&
        _lastImportPhase != ImportPhase.failed;
    final isActive = phase != ImportPhase.idle &&
        phase != ImportPhase.completed &&
        phase != ImportPhase.failed;
    if (!wasActive && isActive) {
      _importProgressExpanded = true;
    }
    _lastImportPhase = phase;
  }

  void _toggleImportProgress() {
    setState(() {
      _importProgressExpanded = !_importProgressExpanded;
    });
  }

  void _showMessageIfNeeded() {
    final message = widget.controller.message;
    if (message == null || message == _lastMessage) {
      return;
    }
    _lastMessage = message;
    final importPhase = widget.controller.importProgress.phase;
    if (importPhase == ImportPhase.completed ||
        importPhase == ImportPhase.failed) {
      return;
    }
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
    await _openExternalUrl(update.releaseUrl);
  }

  Future<void> _openExternalUrl(String url) async {
    await const MethodChannel(
      'io.github.dey410.gardendlessloader/external_browser',
    ).invokeMethod<void>('open', <String, Object?>{'url': url});
  }

  Future<void> _startGame() async {
    try {
      await widget.controller.startGame();
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
    if (_selectedSection != _LauncherSection.diagnostics) {
      setState(() {
        _selectedSection = _LauncherSection.diagnostics;
      });
    }
    await widget.controller.refreshLogs();
  }

  Future<void> _showAbout() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('关于 GardendlessLoader'),
        content: Text(widget.controller.aboutContent.content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _copyDiagnostics() async {
    await widget.controller.refreshLogs();
    final text = widget.controller.buildDiagnosticSummary();
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('日志信息已复制')),
    );
  }

  Future<void> _deleteLogHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除历史日志？'),
        content: const Text('只会删除已经结束的历史 Session，当前运行日志会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.controller.deleteLogHistory();
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
    required this.onDeferGameUpdate,
    required this.onCheckUpdates,
    required this.onShowResources,
    required this.onShowDiagnostics,
    required this.onShowAbout,
    required this.onOpenExternalUrl,
    required this.onCopyResourceRoot,
    required this.onCopyDiagnostics,
    required this.onDeleteLogHistory,
    required this.importProgressExpanded,
    required this.onToggleImportProgress,
  });

  final AppController controller;
  final _LauncherSection selectedSection;
  final Future<void> Function() onStartGame;
  final Future<void> Function() onImportResources;
  final Future<void> Function() onOpenGitHub;
  final Future<void> Function(UpdateInfo update) onOpenRelease;
  final void Function(UpdateInfo update) onDeferUpdate;
  final void Function(GameUpdateInfo update) onDeferGameUpdate;
  final Future<void> Function() onCheckUpdates;
  final VoidCallback onShowResources;
  final Future<void> Function() onShowDiagnostics;
  final Future<void> Function() onShowAbout;
  final Future<void> Function(String url) onOpenExternalUrl;
  final Future<void> Function() onCopyResourceRoot;
  final Future<void> Function() onCopyDiagnostics;
  final Future<void> Function() onDeleteLogHistory;
  final bool importProgressExpanded;
  final VoidCallback onToggleImportProgress;

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
                      importProgress: controller.importProgress,
                      selectedSection: selectedSection,
                      onShowResources: onShowResources,
                      onShowDiagnostics: onShowDiagnostics,
                      onShowAbout: onShowAbout,
                    ),
                    if (selectedSection == _LauncherSection.resources) ...[
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(26, 24, 24, 24),
                          child: _LauncherMainColumn(
                            controller: controller,
                            onImportResources: onImportResources,
                            onOpenGitHub: onOpenGitHub,
                            onCheckUpdates: onCheckUpdates,
                            onCopyResourceRoot: onCopyResourceRoot,
                            importProgressExpanded: importProgressExpanded,
                            onToggleImportProgress: onToggleImportProgress,
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
                                  onDeferGameUpdate: onDeferGameUpdate,
                                  onOpenExternalUrl: onOpenExternalUrl,
                                ),
                              ),
                              const SizedBox(height: 20),
                              _GameLaunchControls(
                                controller: controller,
                                onStartGame: onStartGame,
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
                            onDeleteLogHistory: onDeleteLogHistory,
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
            gradient: LauncherVisuals.workbenchGradient(context),
            borderRadius: radius,
            border: Border.all(
              color: LauncherVisuals.glassBorder(context),
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
    required this.importProgress,
    required this.selectedSection,
    required this.onShowResources,
    required this.onShowDiagnostics,
    required this.onShowAbout,
  });

  final ImportProgress importProgress;
  final _LauncherSection selectedSection;
  final VoidCallback onShowResources;
  final Future<void> Function() onShowDiagnostics;
  final Future<void> Function() onShowAbout;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: const ValueKey('launcher-navigation-rail'),
      child: SizedBox(
        width: 164,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: LauncherVisuals.navigationBackground(context),
            border: Border(
              right: BorderSide(color: LauncherVisuals.sidebarBorder(context)),
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
                  trailing: _ImportNavigationStatus(progress: importProgress),
                ),
                const SizedBox(height: 8),
                _NavItem(
                  icon: Icons.terminal_rounded,
                  label: '日志',
                  selected: selectedSection == _LauncherSection.diagnostics,
                  onTap: onShowDiagnostics,
                ),
                const Spacer(),
                _NavItem(
                  icon: Icons.info_outline_rounded,
                  label: '关于',
                  onTap: onShowAbout,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ImportNavigationStatus extends StatelessWidget {
  const _ImportNavigationStatus({required this.progress});

  final ImportProgress progress;

  @override
  Widget build(BuildContext context) {
    final phase = progress.phase;
    if (phase == ImportPhase.idle) {
      return const SizedBox.shrink();
    }
    if (phase == ImportPhase.completed) {
      return const Icon(
        key: ValueKey('resource-nav-progress'),
        Icons.check_circle_rounded,
        size: 18,
        color: LauncherVisuals.success,
      );
    }
    if (phase == ImportPhase.failed) {
      return Icon(
        key: const ValueKey('resource-nav-progress'),
        Icons.error_rounded,
        size: 18,
        color: Theme.of(context).colorScheme.error,
      );
    }

    final value = progress.value;
    return Row(
      key: const ValueKey('resource-nav-progress'),
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            value: value,
          ),
        ),
        if (value != null) ...[
          const SizedBox(width: 4),
          Text(
            '${(value * 100).round()}%',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ],
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground =
        selected ? colors.primary : LauncherVisuals.secondaryText(context);
    final background = selected
        ? LauncherVisuals.selectedNavigationBackground(context)
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
                if (trailing != null) ...[
                  const SizedBox(width: 6),
                  trailing!,
                ],
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
    required this.onCheckUpdates,
    required this.onCopyResourceRoot,
    required this.importProgressExpanded,
    required this.onToggleImportProgress,
  });

  final AppController controller;
  final Future<void> Function() onImportResources;
  final Future<void> Function() onOpenGitHub;
  final Future<void> Function() onCheckUpdates;
  final Future<void> Function() onCopyResourceRoot;
  final bool importProgressExpanded;
  final VoidCallback onToggleImportProgress;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _LauncherTitle(
              controller: controller,
              onCheckUpdates: onCheckUpdates,
            ),
            const SizedBox(height: 20),
            _ResourceHeroCard(
              controller: controller,
              expanded: importProgressExpanded,
              onToggle: onToggleImportProgress,
              onDismiss: controller.dismissImportProgress,
            ),
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
          ],
        ),
      ),
    );
  }
}

class _DiagnosticsLogView extends StatefulWidget {
  const _DiagnosticsLogView({
    required this.controller,
    required this.onCopyDiagnostics,
    required this.onDeleteLogHistory,
  });

  final AppController controller;
  final Future<void> Function() onCopyDiagnostics;
  final Future<void> Function() onDeleteLogHistory;

  @override
  State<_DiagnosticsLogView> createState() => _DiagnosticsLogViewState();
}

class _DiagnosticsLogViewState extends State<_DiagnosticsLogView> {
  String _minimumLevel = 'INFO';
  bool _errorsOnly = false;
  String _operationFilter = 'all';

  static const _levelRanks = <String, int>{
    'DEBUG': 0,
    'INFO': 1,
    'WARN': 2,
    'ERROR': 3,
    'FATAL': 4,
  };

  List<Map<String, Object?>> _visibleEvents(AppLogSnapshot snapshot) {
    final minimumRank = _levelRanks[_minimumLevel] ?? 1;
    return snapshot.events.where((event) {
      final level = event['level']?.toString().toUpperCase() ?? 'INFO';
      if ((_levelRanks[level] ?? 1) < minimumRank) return false;
      if (_errorsOnly && level != 'ERROR' && level != 'FATAL') return false;
      return _operationFilter == 'all' ||
          event['operationId']?.toString() == _operationFilter;
    }).toList(growable: false);
  }

  Future<void> _copyEvent(Map<String, Object?> event) async {
    await Clipboard.setData(
      ClipboardData(text: const JsonEncoder.withIndent('  ').convert(event)),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('单条事件 JSON 已复制')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.controller.logSnapshot;
    final text = widget.controller.buildLogText(
      minimumLevel: _minimumLevel,
      errorsOnly: _errorsOnly,
    );
    final operations = (snapshot?.events
                .map((event) => event['operationId']?.toString())
                .whereType<String>()
                .where((value) => value.isNotEmpty)
                .toSet() ??
            <String>{})
        .toList(growable: false)
      ..sort();
    if (_operationFilter != 'all' && !operations.contains(_operationFilter)) {
      _operationFilter = 'all';
    }

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
                  iconColor: LauncherVisuals.service,
                  label: '日志信息',
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _StatusPill(
                      label: snapshot == null
                          ? '日志状态未知'
                          : snapshot.persisting
                              ? '持久化正常'
                              : '内存降级',
                      color: snapshot?.persisting == true
                          ? LauncherVisuals.success
                          : LauncherVisuals.warning,
                    ),
                    Text('占用 ${snapshot?.totalBytes ?? 0} B'),
                    Text('写入失败 ${snapshot?.writeFailureCount ?? 0}'),
                    DropdownButton<String>(
                      key: const ValueKey('log-minimum-level-filter'),
                      value: _minimumLevel,
                      items: const ['DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL']
                          .map(
                            (level) => DropdownMenuItem(
                              value: level,
                              child: Text(level),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _minimumLevel = value);
                        }
                      },
                    ),
                    FilterChip(
                      key: const ValueKey('log-errors-only-filter'),
                      label: const Text('只看错误'),
                      selected: _errorsOnly,
                      onSelected: (selected) =>
                          setState(() => _errorsOnly = selected),
                    ),
                    if (operations.isNotEmpty)
                      DropdownButton<String>(
                        key: const ValueKey('log-operation-filter'),
                        value: _operationFilter,
                        items: <DropdownMenuItem<String>>[
                          const DropdownMenuItem(
                            value: 'all',
                            child: Text('全部 Operation'),
                          ),
                          ...operations.map(
                            (operationId) => DropdownMenuItem(
                              value: operationId,
                              child: Text(
                                operationId,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _operationFilter = value);
                          }
                        },
                      ),
                    TextButton(
                      key: const ValueKey('clear-log-view-filter'),
                      onPressed: () => setState(() {
                        _minimumLevel = 'INFO';
                        _errorsOnly = false;
                        _operationFilter = 'all';
                      }),
                      child: const Text('清空筛选'),
                    ),
                    IconButton(
                      tooltip: '刷新日志',
                      onPressed: widget.controller.logSnapshotLoading
                          ? null
                          : widget.controller.refreshLogs,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: snapshot == null
                      ? _DiagnosticsLogBox(text: text)
                      : _StructuredLogBrowser(
                          controller: widget.controller,
                          snapshot: snapshot,
                          events: _visibleEvents(snapshot),
                          technicalText: text,
                          onCopyEvent: _copyEvent,
                        ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('delete-log-history-button'),
              onPressed: widget.onDeleteLogHistory,
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('删除历史日志'),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              key: const ValueKey('copy-diagnostics-button'),
              onPressed: widget.onCopyDiagnostics,
              icon: const Icon(Icons.copy_rounded),
              label: const Text('复制日志信息'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(178, 52),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                backgroundColor: LauncherVisuals.accentBlue,
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
          ],
        ),
      ],
    );
  }
}

class _StructuredLogBrowser extends StatelessWidget {
  const _StructuredLogBrowser({
    required this.controller,
    required this.snapshot,
    required this.events,
    required this.technicalText,
    required this.onCopyEvent,
  });

  final AppController controller;
  final AppLogSnapshot snapshot;
  final List<Map<String, Object?>> events;
  final String technicalText;
  final Future<void> Function(Map<String, Object?> event) onCopyEvent;

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    String? gameSessionId;
    Map<String, Object?>? recentError;
    for (final event in snapshot.events) {
      final level = event['level']?.toString().toUpperCase() ?? 'INFO';
      counts[level] = (counts[level] ?? 0) + 1;
      gameSessionId = event['gameSessionId']?.toString() ?? gameSessionId;
      if (level == 'ERROR' || level == 'FATAL') recentError = event;
    }
    final recentErrorInfo = recentError == null
        ? null
        : userErrorCatalog[recentError['code']?.toString()];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 270,
          child: ListView(
            key: const ValueKey('log-overview'),
            children: [
              Text('当前会话', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              SelectableText(snapshot.appSessionId),
              const SizedBox(height: 10),
              Text('游戏会话：${gameSessionId ?? '无'}'),
              Text(
                '应用：v${controller.currentAppVersion} · '
                '${controller.gameHostPlatform.wireName}',
              ),
              Text('日志占用：${snapshot.totalBytes} B'),
              Text('写入失败：${snapshot.writeFailureCount}'),
              Text('等级计数：${jsonEncode(counts)}'),
              Text('丢弃计数：${jsonEncode(snapshot.droppedByLevel)}'),
              const SizedBox(height: 10),
              Text('最近错误', style: Theme.of(context).textTheme.titleSmall),
              Text(
                recentError == null
                    ? '无'
                    : recentErrorInfo?.title ??
                        '${recentError['code'] ?? recentError['event']}: '
                            '${recentError['message'] ?? ''}',
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
              if (recentErrorInfo != null)
                Text(
                  recentErrorInfo.action,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              const SizedBox(height: 8),
              Material(
                color: Colors.transparent,
                child: ExpansionTile(
                  key: const ValueKey('log-technical-details'),
                  tilePadding: EdgeInsets.zero,
                  title: const Text('技术详情'),
                  children: [
                    SizedBox(
                      height: 220,
                      child: _DiagnosticsLogBox(text: technicalText),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 24),
        Expanded(
          child: events.isEmpty
              ? const Center(child: Text('当前筛选条件下没有事件'))
              : ListView.builder(
                  key: const ValueKey('structured-log-events'),
                  itemCount: events.length,
                  itemBuilder: (context, index) {
                    final event = events[events.length - index - 1];
                    final level = event['level']?.toString() ?? 'INFO';
                    return Material(
                      color: Colors.transparent,
                      child: ExpansionTile(
                        key: ValueKey(
                          'log-event-${event['sequence'] ?? index}',
                        ),
                        leading: Text(level),
                        title:
                            Text(event['event']?.toString() ?? 'unknown_event'),
                        subtitle: Text(
                          [
                            if (event['code'] != null) event['code'],
                            if (event['operationId'] != null)
                              'op=${event['operationId']}',
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          tooltip: '复制单条事件 JSON',
                          onPressed: () => onCopyEvent(event),
                          icon: const Icon(Icons.copy_rounded, size: 18),
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: SelectableText(
                              const JsonEncoder.withIndent('  ').convert(event),
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
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
          color: LauncherVisuals.separator(context).withValues(alpha: 0.62),
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
                    color: LauncherVisuals.primaryText(context),
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
  const _LauncherTitle({
    required this.controller,
    required this.onCheckUpdates,
  });

  final AppController controller;
  final Future<void> Function() onCheckUpdates;

  @override
  Widget build(BuildContext context) {
    final canStart = controller.canStartGame;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          appDisplayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
                color: LauncherVisuals.primaryText(context),
                height: 1.04,
              ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _VersionPill(
              label: '加载器',
              version: controller.currentAppVersion,
              hasUpdate: controller.availableUpdate != null,
              checking: controller.updateCheckInProgress,
              pillKey: const ValueKey('app-version-pill'),
              dotKey: const ValueKey('app-update-dot'),
              spinnerKey: const ValueKey('app-update-spinner'),
              onTap: onCheckUpdates,
            ),
            _VersionPill(
              label: '游戏',
              version: controller.currentGameVersion ??
                  (controller.hasCurrentResource ? '未知' : '--'),
              hasUpdate: controller.availableGameUpdate != null,
              checking: controller.updateCheckInProgress,
              pillKey: const ValueKey('game-version-pill'),
              dotKey: const ValueKey('game-update-dot'),
              spinnerKey: const ValueKey('game-update-spinner'),
              onTap: onCheckUpdates,
            ),
            _StatusPill(
              label: canStart ? '可启动' : '需导入',
              color:
                  canStart ? LauncherVisuals.success : LauncherVisuals.warning,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Gardendless 游戏资源启动器',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: LauncherVisuals.secondaryText(context),
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
              ),
        ),
      ],
    );
  }
}

class _VersionPill extends StatelessWidget {
  const _VersionPill({
    required this.label,
    required this.version,
    required this.hasUpdate,
    required this.checking,
    required this.pillKey,
    required this.dotKey,
    required this.spinnerKey,
    required this.onTap,
  });

  final String label;
  final String version;
  final bool hasUpdate;
  final bool checking;
  final Key pillKey;
  final Key dotKey;
  final Key spinnerKey;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final color = LauncherVisuals.accentBlue;
    final foreground = checking
        ? color.withValues(alpha: 0.72)
        : LauncherVisuals.primaryText(context);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          key: pillKey,
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: checking ? null : onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$label ${version == '--' || version == '未知' ? version : 'v$version'}',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0,
                        ),
                  ),
                  if (checking) ...[
                    const SizedBox(width: 7),
                    SizedBox(
                      key: spinnerKey,
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: color.withValues(alpha: 0.78),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (hasUpdate)
          Positioned(
            key: dotKey,
            top: -2,
            right: -2,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: LauncherVisuals.danger,
                shape: BoxShape.circle,
                border: Border.all(
                  color: LauncherVisuals.panelBackground(context),
                  width: 2,
                ),
              ),
              child: const SizedBox(width: 11, height: 11),
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
  const _ResourceHeroCard({
    required this.controller,
    required this.expanded,
    required this.onToggle,
    required this.onDismiss,
  });

  final AppController controller;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final hasCurrent = controller.hasCurrentResource;
    final statusLabel = hasCurrent ? '资源已就绪' : '需要导入资源';
    final progress = controller.importProgress;

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
                        color: LauncherVisuals.primaryText(context),
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  statusLabel,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: LauncherVisuals.secondaryText(context),
                        fontWeight: FontWeight.w500,
                      ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeInOut,
                  alignment: Alignment.topCenter,
                  child: progress.phase == ImportPhase.idle
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(top: 17),
                          child: _ImportProgressRegion(
                            progress: progress,
                            expanded: expanded,
                            hasCurrentResource: hasCurrent,
                            onToggle: onToggle,
                            onDismiss: onDismiss,
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

class _ImportProgressRegion extends StatelessWidget {
  const _ImportProgressRegion({
    required this.progress,
    required this.expanded,
    required this.hasCurrentResource,
    required this.onToggle,
    required this.onDismiss,
  });

  final ImportProgress progress;
  final bool expanded;
  final bool hasCurrentResource;
  final VoidCallback onToggle;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final isFailed = progress.phase == ImportPhase.failed;
    final isCompleted = progress.phase == ImportPhase.completed;
    final color = isFailed
        ? Theme.of(context).colorScheme.error
        : isCompleted
            ? LauncherVisuals.success
            : Theme.of(context).colorScheme.primary;
    final value = isFailed || isCompleted ? 1.0 : progress.value;
    final message = progress.message ?? _importPhaseMessage(progress.phase);
    final title = isFailed
        ? '导入失败 · $message'
        : isCompleted
            ? '导入完成 100%'
            : '步骤 ${progress.stepIndex}/${progress.stepCount} · $message';

    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: Column(
        key: const ValueKey('resource-progress-region'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (isFailed || isCompleted)
                Icon(
                  isFailed ? Icons.error_rounded : Icons.check_circle_rounded,
                  size: 21,
                  color: color,
                )
              else
                SizedBox(
                  width: 19,
                  height: 19,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: color,
                  ),
                ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: LauncherVisuals.primaryText(context),
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              if (!isFailed && !isCompleted && progress.value != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    '${(progress.value! * 100).round()}%',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
              IconButton(
                key: const ValueKey('resource-progress-toggle'),
                tooltip: expanded ? '收起进度详情' : '展开进度详情',
                onPressed: onToggle,
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                ),
              ),
              if (isFailed)
                IconButton(
                  key: const ValueKey('dismiss-import-progress'),
                  tooltip: '关闭失败提示',
                  onPressed: onDismiss,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 7,
              value: value,
              backgroundColor:
                  LauncherVisuals.separator(context).withValues(alpha: 0.65),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          if (expanded) ...[
            const SizedBox(height: 10),
            _ImportProgressDetails(
              key: const ValueKey('resource-progress-details'),
              progress: progress,
              hasCurrentResource: hasCurrentResource,
            ),
          ],
        ],
      ),
    );
  }
}

class _ImportProgressDetails extends StatelessWidget {
  const _ImportProgressDetails({
    super.key,
    required this.progress,
    required this.hasCurrentResource,
  });

  final ImportProgress progress;
  final bool hasCurrentResource;

  @override
  Widget build(BuildContext context) {
    final items = <String>[];
    if (progress.totalBytes > 0) {
      items.add(
        '${_formatImportBytes(progress.copiedBytes)} / '
        '${_formatImportBytes(progress.totalBytes)}',
      );
    }
    if (progress.totalFiles > 0) {
      items.add('${progress.copiedFiles} / ${progress.totalFiles} 个文件');
    }
    if (progress.bytesPerSecond > 0) {
      items.add('${_formatImportBytes(progress.bytesPerSecond.round())}/s');
    }
    items.add('已用 ${_formatImportDuration(progress.elapsed)}');

    final isFailed = progress.phase == ImportPhase.failed;
    final isCompleted = progress.phase == ImportPhase.completed;
    final hint = isFailed
        ? hasCurrentResource
            ? '原有资源未受影响，可重新选择 ZIP。'
            : '请重新选择有效的 ZIP 资源。'
        : isCompleted
            ? '资源已就绪。'
            : '仍在处理中，请保持应用在前台。';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          items.join(' · '),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: LauncherVisuals.secondaryText(context),
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          hint,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: LauncherVisuals.secondaryText(context),
              ),
        ),
      ],
    );
  }
}

String _importPhaseMessage(ImportPhase phase) => switch (phase) {
      ImportPhase.receiving => '正在读取 ZIP',
      ImportPhase.extracting => '正在解压资源',
      ImportPhase.validating => '正在校验资源',
      ImportPhase.scanning => '正在统计资源',
      ImportPhase.selfChecking => '正在本地自检',
      ImportPhase.completed => '导入完成',
      ImportPhase.failed => '导入失败',
      ImportPhase.idle => '等待导入',
    };

String _formatImportBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }
  final digits = unitIndex == 0 || value >= 100 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unitIndex]}';
}

String _formatImportDuration(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
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
            color: LauncherVisuals.success.withValues(alpha: 0.22),
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
    final validationColor = controller.hasCurrentResource
        ? LauncherVisuals.success
        : LauncherVisuals.warning;

    return _GroupedPanel(
      title: '资源信息',
      icon: Icons.inventory_2_rounded,
      iconColor: LauncherVisuals.accentBlue,
      children: [
        _InfoRow(
          icon: Icons.folder_rounded,
          iconColor: LauncherVisuals.accentBlue,
          label: '资源根目录',
          value: controller.userVisibleRoot,
          trailing: TextButton.icon(
            key: const ValueKey('copy-resource-root-button'),
            onPressed: onCopyResourceRoot,
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('复制'),
            style: TextButton.styleFrom(
              foregroundColor: LauncherVisuals.accentBlue,
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
          icon: Icons.rocket_launch_rounded,
          iconColor: LauncherVisuals.service,
          label: '游戏宿主',
          value: controller.gameHostPlatform.nativeHostName,
          detail: '无 HTTP Server',
          statusColor: LauncherVisuals.service,
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
            iconColor: LauncherVisuals.warning,
            label: '快捷操作',
          ),
          const SizedBox(height: 14),
          _InsetListCard(
            children: [
              _ActionRow(
                icon: Icons.upload_rounded,
                iconColor: LauncherVisuals.warning,
                label:
                    controller.hasCurrentResource ? '选择 ZIP 更新' : '选择 ZIP 导入',
                onPressed: controller.busy || controller.isImporting
                    ? null
                    : onImportResources,
                trailingIcon: Icons.chevron_right_rounded,
              ),
              _ActionRow(
                icon: Icons.open_in_new_rounded,
                iconColor: LauncherVisuals.secondaryText(context),
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
                            ? LauncherVisuals.secondaryText(context)
                            : LauncherVisuals.primaryText(context),
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              Icon(
                trailingIcon,
                size: 19,
                color: LauncherVisuals.secondaryText(context),
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
    required this.onDeferGameUpdate,
    required this.onOpenExternalUrl,
  });

  final AppController controller;
  final Future<void> Function(UpdateInfo update) onOpenRelease;
  final void Function(UpdateInfo update) onDeferUpdate;
  final void Function(GameUpdateInfo update) onDeferGameUpdate;
  final Future<void> Function(String url) onOpenExternalUrl;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StartupHealthPanel(controller: controller),
          if (controller.availableUpdate != null ||
              controller.availableGameUpdate != null) ...[
            const SizedBox(height: 16),
            _UpdateCenter(
              appUpdate: controller.availableUpdate,
              gameUpdate: controller.availableGameUpdate,
              onOpenCloudDrive: () => onOpenExternalUrl(appCloudDriveUpdateUrl),
              onOpenRelease: onOpenRelease,
              onOpenGameGitHub: () => onOpenExternalUrl(githubUrl),
              onDeferApp: onDeferUpdate,
              onDeferGame: onDeferGameUpdate,
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
            iconColor: LauncherVisuals.accentBlue,
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
        color: LauncherVisuals.innerPanelBackground(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: LauncherVisuals.separator(context).withValues(alpha: 0.72),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Text(
          message,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: LauncherVisuals.secondaryText(context),
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
          backgroundColor: LauncherVisuals.innerPanelBackground(context),
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
    return LauncherVisuals.primaryText(context);
  }
  return LauncherVisuals.accentBlue;
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
        hasResource ? LauncherVisuals.success : LauncherVisuals.warning;
    final selfCheckColor = controller.manifest.lastSelfCheckAt == null
        ? LauncherVisuals.secondaryText(context)
        : LauncherVisuals.success;
    final errorColor = controller.manifest.lastErrorMessage == null
        ? LauncherVisuals.secondaryText(context)
        : LauncherVisuals.danger;

    return _LauncherPanel(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PanelTitle(
            icon: Icons.monitor_heart_rounded,
            iconColor: LauncherVisuals.service,
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
                    color: LauncherVisuals.primaryText(context),
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
                    color: LauncherVisuals.secondaryText(context),
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

class _GameLaunchControls extends StatelessWidget {
  const _GameLaunchControls({
    required this.controller,
    required this.onStartGame,
  });

  final AppController controller;
  final Future<void> Function() onStartGame;

  @override
  Widget build(BuildContext context) {
    final showAutoCollectSun = controller.hasCurrentResource;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showAutoCollectSun)
          _AutoCollectSunControl(
            enabled: !controller.busy,
            value: controller.autoCollectSunEnabled,
            onChanged: controller.setAutoCollectSunEnabled,
          ),
        _StartGameButton(
          enabled: controller.canStartGame && !controller.busy,
          joinedAtTop: showAutoCollectSun,
          onPressed: onStartGame,
        ),
      ],
    );
  }
}

class _AutoCollectSunControl extends StatelessWidget {
  const _AutoCollectSunControl({
    required this.enabled,
    required this.value,
    required this.onChanged,
  });

  final bool enabled;
  final bool value;
  final Future<void> Function(bool enabled) onChanged;

  @override
  Widget build(BuildContext context) {
    const borderRadius = BorderRadius.vertical(top: Radius.circular(28));
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Material(
        key: const ValueKey('home-auto-collect-sun'),
        color: LauncherVisuals.separator(context).withValues(alpha: 0.64),
        shape: const RoundedRectangleBorder(borderRadius: borderRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? () => unawaited(onChanged(!value)) : null,
          child: SizedBox(
            width: 272,
            height: 54,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 17),
              child: Row(
                children: [
                  const Icon(
                    Icons.wb_sunny_rounded,
                    size: 23,
                    color: LauncherVisuals.warning,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      '自动收集',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: LauncherVisuals.primaryText(context),
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  Switch(
                    key: const ValueKey('home-auto-collect-sun-switch'),
                    value: value,
                    onChanged: enabled
                        ? (nextValue) => unawaited(onChanged(nextValue))
                        : null,
                    activeTrackColor: LauncherVisuals.accentBlue,
                    activeThumbColor: Colors.white,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StartGameButton extends StatelessWidget {
  const _StartGameButton({
    required this.enabled,
    required this.joinedAtTop,
    required this.onPressed,
  });

  final bool enabled;
  final bool joinedAtTop;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    final borderRadius = joinedAtTop
        ? const BorderRadius.vertical(bottom: Radius.circular(28))
        : BorderRadius.circular(28);
    final button = FilledButton.icon(
      key: const ValueKey('home-start-game-button'),
      onPressed: enabled ? onPressed : null,
      icon: const Icon(Icons.play_arrow_rounded, size: 32),
      label: const Text('开始游戏'),
      style: FilledButton.styleFrom(
        minimumSize: const Size(272, 72),
        padding: const EdgeInsets.symmetric(horizontal: 30),
        backgroundColor: LauncherVisuals.accentBlue,
        foregroundColor: Colors.white,
        disabledBackgroundColor:
            LauncherVisuals.separator(context).withValues(alpha: 0.78),
        disabledForegroundColor: LauncherVisuals.secondaryText(context),
        shape: RoundedRectangleBorder(borderRadius: borderRadius),
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
          borderRadius: borderRadius,
          boxShadow: [
            BoxShadow(
              color: LauncherVisuals.accentBlue.withValues(alpha: 0.28),
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
                color: LauncherVisuals.secondaryText(context),
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 8),
        button,
      ],
    );
  }
}

class _UpdateCenter extends StatelessWidget {
  const _UpdateCenter({
    required this.appUpdate,
    required this.gameUpdate,
    required this.onOpenCloudDrive,
    required this.onOpenRelease,
    required this.onOpenGameGitHub,
    required this.onDeferApp,
    required this.onDeferGame,
  });

  final UpdateInfo? appUpdate;
  final GameUpdateInfo? gameUpdate;
  final Future<void> Function() onOpenCloudDrive;
  final Future<void> Function(UpdateInfo update) onOpenRelease;
  final Future<void> Function() onOpenGameGitHub;
  final void Function(UpdateInfo update) onDeferApp;
  final void Function(GameUpdateInfo update) onDeferGame;

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
                color: LauncherVisuals.warning,
                size: 23,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '更新中心',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: LauncherVisuals.primaryText(context),
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
          if (appUpdate != null) ...[
            const SizedBox(height: 14),
            _UpdateEntry(
              key: const ValueKey('app-update-entry'),
              title: '加载器',
              currentVersion: appUpdate!.currentVersion,
              latestVersion: appUpdate!.latestVersion,
              primaryLabel: '网盘更新',
              secondaryLabel: '查看 GitHub Release',
              onPrimary: onOpenCloudDrive,
              onSecondary: () => onOpenRelease(appUpdate!),
              onDefer: () => onDeferApp(appUpdate!),
            ),
          ],
          if (gameUpdate != null) ...[
            const SizedBox(height: 14),
            _UpdateEntry(
              key: const ValueKey('game-update-entry'),
              title: '游戏资源',
              currentVersion: gameUpdate!.currentVersion,
              latestVersion: gameUpdate!.latestVersion,
              primaryLabel: '获取游戏资源',
              secondaryLabel: '查看游戏 GitHub',
              onPrimary: onOpenCloudDrive,
              onSecondary: onOpenGameGitHub,
              onDefer: () => onDeferGame(gameUpdate!),
            ),
          ],
        ],
      ),
    );
  }
}

class _UpdateEntry extends StatelessWidget {
  const _UpdateEntry({
    super.key,
    required this.title,
    required this.currentVersion,
    required this.latestVersion,
    required this.primaryLabel,
    required this.secondaryLabel,
    required this.onPrimary,
    required this.onSecondary,
    required this.onDefer,
  });

  final String title;
  final String currentVersion;
  final String latestVersion;
  final String primaryLabel;
  final String secondaryLabel;
  final Future<void> Function() onPrimary;
  final Future<void> Function() onSecondary;
  final VoidCallback onDefer;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: LauncherVisuals.primaryText(context),
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 5),
        Text(
          '$currentVersion → $latestVersion',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: LauncherVisuals.secondaryText(context),
              ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: onPrimary,
              icon: const Icon(Icons.cloud_download_rounded),
              label: Text(primaryLabel),
            ),
            FilledButton.tonalIcon(
              onPressed: onSecondary,
              icon: const Icon(Icons.open_in_new_rounded),
              label: Text(secondaryLabel),
            ),
            TextButton(
              onPressed: onDefer,
              child: const Text('稍后提醒'),
            ),
          ],
        ),
      ],
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
                  color: LauncherVisuals.primaryText(context),
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
        color: LauncherVisuals.innerPanelBackground(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: LauncherVisuals.separator(context).withValues(alpha: 0.62),
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
                  color: LauncherVisuals.separator(context).withValues(
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
                      color: LauncherVisuals.primaryText(context),
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
                      color: LauncherVisuals.secondaryText(context),
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
                      color: LauncherVisuals.secondaryText(context),
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ],
            if (statusColor != null) ...[
              const SizedBox(width: 10),
              Icon(
                statusColor == LauncherVisuals.warning
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
    final borderColor = LauncherVisuals.separator(context).withValues(
      alpha: Theme.of(context).brightness == Brightness.dark ? 0.48 : 0.70,
    );
    final panel = ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: LauncherVisuals.panelBackground(context),
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
              color: LauncherVisuals.accentBlue.withValues(
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
