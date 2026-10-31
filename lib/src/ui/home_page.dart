import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../l10n/app_strings.dart';
import '../logging/log_event_catalog.dart';
import '../models.dart';
import '../services/shortcut_service.dart';
import '../services/update_check_service.dart';
import 'launcher_actions.dart';
import 'pages/play_page.dart';
import 'pages/logs_page.dart';
import 'pages/resources_page.dart';
import 'pages/settings_page.dart';
import 'theme/garden_theme.dart';
import 'widgets/announcement_dialog.dart';
import 'widgets/garden_widgets.dart';
import 'widgets/key_art_backdrop.dart';

const _appIconAsset = 'tool/generated_icons/app_icon_master.png';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.controller});

  final AppController controller;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  LauncherDestination _destination = LauncherDestination.game;
  LauncherMessage? _lastMessage;
  bool _importDetailsExpanded = true;
  bool _announcementPopupScheduled = false;
  bool _incomingZipDialogScheduled = false;
  bool _shortcutScheduled = false;
  ImportPhase _lastImportPhase = ImportPhase.idle;
  int _iconTaps = 0;
  DateTime? _lastIconTap;

  AppController get _controller => widget.controller;

  late final LauncherActions _actions = LauncherActions(
    navigate: _navigate,
    startGame: _startGame,
    importResources: _importResources,
    openUrl: _openExternalUrl,
    openRelease: (UpdateInfo update) => _openExternalUrl(update.releaseUrl),
    deferUpdate: _controller.deferUpdate,
    deferGameUpdate: _controller.deferGameUpdate,
    copyResourceRoot: _copyResourceRoot,
    copyDiagnostics: _copyDiagnostics,
    copyLogEvent: _copyLogEvent,
    deleteLogHistory: _deleteLogHistory,
    toggleImportDetails: () =>
        setState(() => _importDetailsExpanded = !_importDetailsExpanded),
  );

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // Deferred so the first notification cannot land mid-build in the
    // theme AnimatedBuilder above this page.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_controller.checkForUpdates(silent: true));
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        _showMessageIfNeeded();
        _showNewAnnouncementIfNeeded();
        _showIncomingZipIfNeeded();
        _performShortcutIfNeeded();
        _syncImportDetails(_controller.importProgress.phase);
        return GardenMotionScope(
          reduceMotion: _controller.reduceMotion,
          child: Builder(builder: _buildScene),
        );
      },
    );
  }

  Widget _buildScene(BuildContext context) {
    final palette = context.garden;
    final loading = !_controller.initialized && _controller.busy;
    // The art and the layout both use the real four-edge padding the
    // platform reports; no edge is inferred from the current orientation.
    final padding = MediaQuery.paddingOf(context);
    final reduced = GardenMotionScope.reduced(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: palette.isDark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: palette.background,
        body: loading
            ? const Center(child: ProgressRing(value: null, size: 28))
            : LayoutBuilder(
                builder: (context, constraints) {
                  final compact = _isCompact(
                    _availableSize(constraints.biggest, padding),
                  );
                  return Stack(
                    children: [
                      // Full-bleed so the art continues under the frosted
                      // rail and the left safe-area gutter, to the display
                      // edges; it is framed for the area beside the rail.
                      Positioned.fill(
                        child: AnimatedOpacity(
                          opacity:
                              _destination == LauncherDestination.game ? 1 : 0,
                          duration:
                              reduced ? Duration.zero : GardenMotion.panel,
                          curve: GardenMotion.easeOut,
                          child: KeyArtBackdrop(
                            key: const ValueKey('play-backdrop'),
                            contentLeft: _Sidebar.widthFor(
                              leftInset: padding.left,
                              compact: compact,
                            ),
                          ),
                        ),
                      ),
                      SafeArea(
                        left: false,
                        right: false,
                        bottom: false,
                        child: _buildWorkspace(
                          compact: compact,
                          padding: padding,
                          reduced: reduced,
                        ),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }

  /// The window minus every safe-area edge the platform reports.
  static Size _availableSize(Size size, EdgeInsets padding) {
    final width = size.width - padding.horizontal;
    final height = size.height - padding.vertical;
    return Size(width < 0 ? 0 : width, height < 0 ? 0 : height);
  }

  static bool _isCompact(Size size) => size.height < 470 || size.width < 760;

  Widget _buildWorkspace({
    required bool compact,
    required EdgeInsets padding,
    required bool reduced,
  }) {
    final gutter = compact ? 20.0 : 32.0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Sidebar(
          controller: _controller,
          selected: _destination,
          compact: compact,
          leftInset: padding.left,
          bottomInset: padding.bottom,
          onSelected: _navigate,
          onIconTap: _onIconTap,
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              gutter,
              compact ? 14 : 24,
              padding.right + gutter,
              padding.bottom + (compact ? 12 : 20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TopBar(
                  controller: _controller,
                  destination: _destination,
                  compact: compact,
                  onOpenAnnouncement: _openAnnouncement,
                ),
                SizedBox(height: compact ? 14 : 24),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: reduced ? Duration.zero : GardenMotion.quick,
                    switchInCurve: GardenMotion.easeOut,
                    switchOutCurve: GardenMotion.easeOut,
                    layoutBuilder: (current, previous) => Stack(
                      fit: StackFit.expand,
                      children: [...previous, if (current != null) current],
                    ),
                    child: KeyedSubtree(
                      key: ValueKey(_destination),
                      child: _buildPage(compact),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPage(bool compact) {
    return switch (_destination) {
      LauncherDestination.game => PlayPage(
          controller: _controller,
          actions: _actions,
          compact: compact,
        ),
      LauncherDestination.resources => ResourcesPage(
          controller: _controller,
          actions: _actions,
          compact: compact,
          detailsExpanded: _importDetailsExpanded,
        ),
      LauncherDestination.logs => LogsPage(
          controller: _controller,
          actions: _actions,
          compact: compact,
        ),
      LauncherDestination.settings => SettingsPage(
          controller: _controller,
          actions: _actions,
          compact: compact,
        ),
    };
  }

  void _navigate(LauncherDestination destination) {
    if (destination == _destination) return;
    setState(() => _destination = destination);
    if (destination == LauncherDestination.logs) {
      unawaited(_controller.refreshLogs());
    }
  }

  void _syncImportDetails(ImportPhase phase) {
    bool active(ImportPhase value) =>
        value != ImportPhase.idle &&
        value != ImportPhase.completed &&
        value != ImportPhase.failed;
    if (!active(_lastImportPhase) && active(phase)) {
      _importDetailsExpanded = true;
    }
    _lastImportPhase = phase;
  }

  /// Pops up an announcement the user has not seen yet, once per launch.
  void _showNewAnnouncementIfNeeded() {
    if (_announcementPopupScheduled ||
        !_controller.initialized ||
        _controller.busy ||
        _controller.isImporting ||
        !_controller.hasUnseenAnnouncement) {
      return;
    }
    _announcementPopupScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) {
        _announcementPopupScheduled = false;
        return;
      }
      unawaited(_openAnnouncement());
    });
  }

  /// Asks whether to import a ZIP another app opened or shared with the
  /// loader; an import or game launch already running waits for it.
  void _showIncomingZipIfNeeded() {
    if (_incomingZipDialogScheduled ||
        _controller.incomingZipName == null ||
        !_controller.initialized ||
        _controller.busy ||
        _controller.isImporting) {
      return;
    }
    _incomingZipDialogScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final name = _controller.incomingZipName;
      if (!mounted || name == null) {
        _incomingZipDialogScheduled = false;
        return;
      }
      final strings = context.strings;
      final hasResource = _controller.hasCurrentResource;
      final confirmed = await _confirm(
        title: hasResource
            ? strings.updateWithZipTitle(name)
            : strings.importZipTitle(name),
        message:
            hasResource ? strings.backUpSaveMessage : strings.importZipMessage,
        confirmLabel: strings.import,
      );
      _incomingZipDialogScheduled = false;
      if (!confirmed) {
        await _controller.discardIncomingZip();
        return;
      }
      _navigate(LauncherDestination.resources);
      await _controller.importIncomingZip(confirmDowngrade: _confirmDowngrade);
    });
  }

  void _performShortcutIfNeeded() {
    if (_shortcutScheduled ||
        _controller.pendingShortcut == null ||
        !_controller.initialized ||
        _controller.busy ||
        _controller.isImporting) {
      return;
    }
    _shortcutScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _shortcutScheduled = false;
      final shortcut = _controller.takeShortcut();
      if (!mounted || shortcut == null) return;
      switch (shortcut) {
        case LauncherShortcut.startGame when _controller.canStartGame:
          _navigate(LauncherDestination.game);
          await _startGame();
        case LauncherShortcut.startGame:
          _navigate(LauncherDestination.resources);
        case LauncherShortcut.importResources:
          _navigate(LauncherDestination.resources);
          await _importResources();
      }
    });
  }

  Future<void> _importResources() async {
    if (_controller.hasCurrentResource) {
      final strings = context.strings;
      final confirmed = await _confirm(
        title: strings.backUpSaveTitle,
        message: strings.backUpSaveMessage,
        confirmLabel: strings.continueImport,
      );
      if (!confirmed) return;
    }
    await _controller.importResources(confirmDowngrade: _confirmDowngrade);
  }

  Future<bool> _confirmDowngrade(String current, String incoming) {
    final strings = context.strings;
    return _confirm(
      title: strings.downgradeTitle,
      message: strings.downgradeMessage(current, incoming),
      confirmLabel: strings.importAnyway,
      confirmTone: GardenButtonTone.danger,
    );
  }

  /// Seven quick taps on the launcher icon find or put away the tool shed;
  /// from the fourth tap a countdown shows how close it is.
  void _onIconTap() {
    final now = DateTime.now();
    final last = _lastIconTap;
    _lastIconTap = now;
    _iconTaps =
        last != null && now.difference(last) < const Duration(milliseconds: 800)
            ? _iconTaps + 1
            : 1;
    final strings = context.strings;
    if (_iconTaps >= 7) {
      _iconTaps = 0;
      final unlocked = !_controller.toolShedUnlocked;
      unawaited(_controller.setToolShedUnlocked(unlocked));
      _toast(unlocked ? strings.toolShedFound : strings.toolShedHidden);
      if (unlocked) _navigate(LauncherDestination.logs);
    } else if (_iconTaps >= 4) {
      _toast(strings.toolShedTapsLeft(7 - _iconTaps));
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    GardenButtonTone confirmTone = GardenButtonTone.primary,
    IconData? confirmIcon,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        actions: [
          GardenButton(
            label: context.strings.cancel,
            compact: true,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          GardenButton(
            label: confirmLabel,
            compact: true,
            tone: confirmTone,
            icon: confirmIcon,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _openAnnouncement() async {
    unawaited(_controller.markAnnouncementSeen());
    await showAnnouncementDialog(
      context,
      announcement: _controller.announcement,
      launcherLinks: _controller.links,
      openUrl: _openExternalUrl,
    );
  }

  void _showMessageIfNeeded() {
    final message = _controller.message;
    if (message == null || message == _lastMessage) return;
    _lastMessage = message;
    final phase = _controller.importProgress.phase;
    if (phase == ImportPhase.completed || phase == ImportPhase.failed) return;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _toast(message.text, code: message.code),
    );
  }

  /// Shows [message]; an error [code] adds that error's fix hint below it.
  void _toast(String message, {String? code}) {
    if (!mounted) return;
    final hint = userErrorCatalog[code]?.action.of(context.strings);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: Duration(seconds: hint == null ? 4 : 8),
          content: hint == null
              ? Text(message)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(message),
                    const SizedBox(height: 4),
                    Text(
                      hint,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
        ),
      );
  }

  Future<void> _openExternalUrl(String url) async {
    await const MethodChannel(
      'io.github.dey410.gardendlessloader/external_browser',
    ).invokeMethod<void>('open', <String, Object?>{'url': url});
  }

  Future<void> _startGame() async {
    final strings = context.strings;
    try {
      await _controller.startGame();
    } on PlatformException catch (error) {
      _toast(
        strings.cannotStartGame(
          userErrorTitle(error.code, error.message ?? error.code),
        ),
        code: error.code,
      );
    } catch (error) {
      _toast(
        strings.cannotStartGame('$error'),
        code: 'game_host_launch_failed',
      );
    }
  }

  Future<void> _copyResourceRoot() async {
    final strings = context.strings;
    await Clipboard.setData(ClipboardData(text: _controller.userVisibleRoot));
    _toast(strings.resourceRootCopied);
  }

  Future<void> _copyDiagnostics() async {
    final strings = context.strings;
    await _controller.refreshLogs();
    await Clipboard.setData(
      ClipboardData(text: _controller.buildDiagnosticSummary()),
    );
    _toast(strings.diagnosticsCopied);
  }

  Future<void> _copyLogEvent(Map<String, Object?> event) async {
    final strings = context.strings;
    await Clipboard.setData(
      ClipboardData(text: const JsonEncoder.withIndent('  ').convert(event)),
    );
    _toast(strings.logEventCopied);
  }

  Future<void> _deleteLogHistory() async {
    final strings = context.strings;
    final confirmed = await _confirm(
      title: strings.deleteLogHistoryTitle,
      message: strings.deleteLogHistoryMessage,
      confirmLabel: strings.delete,
      confirmTone: GardenButtonTone.danger,
      confirmIcon: Icons.delete_outline_rounded,
    );
    if (!confirmed) return;
    await _controller.deleteLogHistory();
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.controller,
    required this.selected,
    required this.compact,
    required this.leftInset,
    required this.bottomInset,
    required this.onSelected,
    required this.onIconTap,
  });

  final AppController controller;
  final LauncherDestination selected;
  final bool compact;
  final double leftInset;
  final double bottomInset;
  final ValueChanged<LauncherDestination> onSelected;
  final VoidCallback onIconTap;

  static double railWidthFor(bool compact) => compact ? 76 : 92;

  static double widthFor({required double leftInset, required bool compact}) =>
      leftInset + railWidthFor(compact);

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    final badge = controller.seasonalTheme?.badge;
    // Keep the unsafe edge free of navigation chrome while blurring the
    // mirrored art beneath it; tint only the actual rail.
    return ClipRect(
      key: const ValueKey('launcher-navigation-rail'),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Padding(
          padding: EdgeInsets.only(left: leftInset),
          child: Container(
            width: railWidthFor(compact),
            padding: EdgeInsets.fromLTRB(
              10,
              compact ? 14 : 24,
              10,
              bottomInset + (compact ? 12 : 20),
            ),
            decoration: BoxDecoration(
              color: palette.surface
                  .withValues(alpha: palette.isDark ? 0.42 : 0.5),
              border: Border(
                right:
                    BorderSide(color: palette.border.withValues(alpha: 0.25)),
              ),
            ),
            child: SingleChildScrollView(
              primary: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Pressable(
                      key: const ValueKey('launcher-icon'),
                      onTap: onIconTap,
                      scale: 0.9,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          ClipRRect(
                            borderRadius:
                                BorderRadius.circular(compact ? 9 : 11),
                            child: Image.asset(
                              _appIconAsset,
                              width: compact ? 36 : 42,
                              height: compact ? 36 : 42,
                              cacheWidth: 128,
                              semanticLabel: 'GardendlessLoader',
                            ),
                          ),
                          if (badge != null)
                            Positioned(
                              key: const ValueKey('seasonal-badge'),
                              right: -7,
                              bottom: -7,
                              child: Text(
                                badge,
                                style: const TextStyle(fontSize: 16, height: 1),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: compact ? 16 : 28),
                  for (final destination in LauncherDestination.values)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: _SidebarItem(
                        destination: destination,
                        selected: destination == selected,
                        compact: compact,
                        badge: _badgeFor(destination),
                        onTap: () => onSelected(destination),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget? _badgeFor(LauncherDestination destination) {
    switch (destination) {
      case LauncherDestination.resources:
        if (controller.isImporting) {
          return ProgressRing(
            key: const ValueKey('resource-nav-progress'),
            value: controller.importProgress.value,
            size: 12,
            stroke: 2,
          );
        }
        if (controller.availableGameUpdate != null) {
          return const _Dot(key: ValueKey('game-update-dot'));
        }
        return null;
      case LauncherDestination.settings:
        return controller.availableUpdate == null
            ? null
            : const _Dot(key: ValueKey('app-update-dot'));
      case LauncherDestination.game:
      case LauncherDestination.logs:
        return null;
    }
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.destination,
    required this.selected,
    required this.compact,
    required this.onTap,
    this.badge,
  });

  final LauncherDestination destination;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    final color = selected ? palette.ink : palette.inkMuted;
    return Semantics(
      selected: selected,
      child: Pressable(
        key: ValueKey('nav-${destination.name}'),
        onTap: onTap,
        semanticLabel: destination.label(context.strings),
        scale: 0.95,
        child: Container(
          constraints: BoxConstraints(minHeight: compact ? 52 : 60),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: selected ? palette.surfaceMuted : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    selected ? destination.selectedIcon : destination.icon,
                    size: 21,
                    color: color,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    destination.label(context.strings),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: color,
                      fontSize: 11.5,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
              if (badge != null)
                Positioned(top: 8, right: compact ? 12 : 16, child: badge!),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: context.garden.accent,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.controller,
    required this.destination,
    required this.compact,
    required this.onOpenAnnouncement,
  });

  final AppController controller;
  final LauncherDestination destination;
  final bool compact;
  final VoidCallback onOpenAnnouncement;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 40),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            Expanded(
              child: Text(
                destination.label(context.strings),
                key: const ValueKey('page-title'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GardenType.title(compact ? 24 : 28, color: palette.ink),
              ),
            ),
            // The game version lives on the home and resources pages; the
            // top bar only carries the loader's own version.
            if (constraints.maxWidth >= 520) ...[
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth * 0.35,
                ),
                child: Text(
                  context.strings.loaderVersion(controller.currentAppVersion),
                  key: const ValueKey('app-version-pill'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.inkMuted, fontSize: 12.5),
                ),
              ),
              const SizedBox(width: 16),
            ],
            GardenIconButton(
              key: const ValueKey('check-updates-button'),
              icon: Icons.refresh_rounded,
              tooltip: controller.updateCheckInProgress
                  ? context.strings.checking
                  : context.strings.checkForUpdates,
              onPressed: controller.updateCheckInProgress
                  ? null
                  : () => controller.checkForUpdates(),
            ),
            Stack(
              clipBehavior: Clip.none,
              children: [
                GardenIconButton(
                  key: const ValueKey('announcement-button'),
                  icon: Icons.campaign_outlined,
                  tooltip: context.strings.announcement,
                  onPressed: onOpenAnnouncement,
                ),
                if (controller.hasUnseenAnnouncement)
                  const Positioned(
                    top: 6,
                    right: 6,
                    child: _Dot(key: ValueKey('announcement-dot')),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
