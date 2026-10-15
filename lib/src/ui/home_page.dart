import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../models.dart';
import '../services/sensor_housing_service.dart';
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
  const HomePage({super.key, required this.controller, this.sensorHousing});

  final AppController controller;

  /// Overrides the platform sensor-housing tracker, mainly for tests.
  final SensorHousingService? sensorHousing;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  LauncherDestination _destination = LauncherDestination.game;
  String? _lastMessage;
  bool _importDetailsExpanded = true;
  bool _announcementPopupScheduled = false;
  ImportPhase _lastImportPhase = ImportPhase.idle;

  AppController get _controller => widget.controller;

  late final SensorHousingService _sensorHousing =
      widget.sensorHousing ?? SensorHousingService();

  late final LauncherActions _actions = LauncherActions(
    navigate: _navigate,
    startGame: _startGame,
    importResources: _controller.importResources,
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
    _sensorHousing.addListener(_onSensorHousingChanged);
    if (widget.sensorHousing == null) unawaited(_sensorHousing.start());
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
  void dispose() {
    _sensorHousing.removeListener(_onSensorHousingChanged);
    if (widget.sensorHousing == null) _sensorHousing.dispose();
    super.dispose();
  }

  void _onSensorHousingChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        _showMessageIfNeeded();
        _showNewAnnouncementIfNeeded();
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
                  final insets = _effectiveInsets(context);
                  final compact = _isCompact(
                    Size(
                      constraints.maxWidth,
                      constraints.maxHeight - insets.top,
                    ),
                  );
                  return Stack(
                    children: [
                      // The art covers only the content area: the sidebar
                      // is opaque, so anything under it would be wasted.
                      // Full-bleed so the art continues under the frosted
                      // sidebar; it is framed for the area beside it.
                      Positioned.fill(
                        child: AnimatedOpacity(
                          opacity:
                              _destination == LauncherDestination.game ? 1 : 0,
                          duration: GardenMotionScope.reduced(context)
                              ? Duration.zero
                              : GardenMotion.panel,
                          curve: GardenMotion.easeOut,
                          child: KeyArtBackdrop(
                            key: const ValueKey('play-backdrop'),
                            resourceRoot: _controller.activeResourceRoot,
                            generation: _controller.manifest.generation,
                            contentLeft: _Sidebar.widthFor(
                              leftInset: insets.left,
                              compact: compact,
                            ),
                          ),
                        ),
                      ),
                      SafeArea(
                        left: false,
                        right: false,
                        bottom: false,
                        child: LayoutBuilder(builder: _buildWorkspace),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }

  static bool _isCompact(Size size) => size.height < 470 || size.width < 760;

  // iOS reports the notch inset on both long edges; keep it only where the
  // sensor housing actually is.
  EdgeInsets _effectiveInsets(BuildContext context) => housingAwareInsets(
        MediaQuery.paddingOf(context),
        _sensorHousing.value,
      );

  Widget _buildWorkspace(BuildContext context, BoxConstraints constraints) {
    final compact = _isCompact(constraints.biggest);
    final padding = _effectiveInsets(context);
    final reduced = GardenMotionScope.reduced(context);
    final gutter = compact ? 20.0 : 32.0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Sidebar(
          controller: _controller,
          selected: _destination,
          compact: compact,
          leftInset: padding.left,
          onSelected: _navigate,
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

  Future<void> _openAnnouncement() async {
    unawaited(_controller.markAnnouncementSeen());
    await showAnnouncementDialog(
      context,
      announcement: _controller.announcement,
      openUrl: _openExternalUrl,
    );
  }

  void _showMessageIfNeeded() {
    final message = _controller.message;
    if (message == null || message == _lastMessage) return;
    _lastMessage = message;
    final phase = _controller.importProgress.phase;
    if (phase == ImportPhase.completed || phase == ImportPhase.failed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _toast(message));
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openExternalUrl(String url) async {
    await const MethodChannel(
      'io.github.dey410.gardendlessloader/external_browser',
    ).invokeMethod<void>('open', <String, Object?>{'url': url});
  }

  Future<void> _startGame() async {
    try {
      await _controller.startGame();
    } catch (error) {
      _toast('无法启动游戏：$error');
    }
  }

  Future<void> _copyResourceRoot() async {
    await Clipboard.setData(ClipboardData(text: _controller.userVisibleRoot));
    _toast('资源根目录已复制');
  }

  Future<void> _copyDiagnostics() async {
    await _controller.refreshLogs();
    await Clipboard.setData(
      ClipboardData(text: _controller.buildDiagnosticSummary()),
    );
    _toast('日志信息已复制');
  }

  Future<void> _copyLogEvent(Map<String, Object?> event) async {
    await Clipboard.setData(
      ClipboardData(text: const JsonEncoder.withIndent('  ').convert(event)),
    );
    _toast('单条事件 JSON 已复制');
  }

  Future<void> _deleteLogHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除历史日志？'),
        content: const Text('只会删除已经结束的历史 Session，当前运行日志会保留。'),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        actions: [
          GardenButton(
            label: '取消',
            compact: true,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          GardenButton(
            label: '删除',
            compact: true,
            tone: GardenButtonTone.danger,
            icon: Icons.delete_outline_rounded,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _controller.deleteLogHistory();
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.controller,
    required this.selected,
    required this.compact,
    required this.leftInset,
    required this.onSelected,
  });

  final AppController controller;
  final LauncherDestination selected;
  final bool compact;
  final double leftInset;
  final ValueChanged<LauncherDestination> onSelected;

  static double widthFor({required double leftInset, required bool compact}) =>
      leftInset + (compact ? 76 : 92);

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    // Frosted glass: the home art flows underneath instead of stopping at a
    // hard edge; elsewhere it reads as a plain tinted panel.
    return ClipRect(
      key: const ValueKey('launcher-navigation-rail'),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          width: widthFor(leftInset: leftInset, compact: compact),
          padding: EdgeInsets.fromLTRB(
            leftInset + 10,
            compact ? 14 : 24,
            10,
            compact ? 12 : 20,
          ),
          decoration: BoxDecoration(
            color:
                palette.surface.withValues(alpha: palette.isDark ? 0.42 : 0.5),
            border: Border(
              right: BorderSide(color: palette.border.withValues(alpha: 0.25)),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(compact ? 9 : 11),
                  child: Image.asset(
                    _appIconAsset,
                    width: compact ? 36 : 42,
                    height: compact ? 36 : 42,
                    cacheWidth: 128,
                    semanticLabel: 'GardendlessLoader',
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
        semanticLabel: destination.label,
        scale: 0.95,
        child: Container(
          height: compact ? 52 : 60,
          decoration: BoxDecoration(
            color: selected ? palette.surfaceMuted : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    selected ? destination.selectedIcon : destination.icon,
                    size: 21,
                    color: color,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    destination.label,
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
    return SizedBox(
      height: 40,
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            Expanded(
              child: Text(
                destination.label,
                key: const ValueKey('page-title'),
                style: GardenType.title(compact ? 24 : 28, color: palette.ink),
              ),
            ),
            // The game version lives on the home and resources pages; the
            // top bar only carries the loader's own version.
            if (constraints.maxWidth >= 520) ...[
              Text(
                '加载器 v${controller.currentAppVersion}',
                key: const ValueKey('app-version-pill'),
                style: TextStyle(color: palette.inkMuted, fontSize: 12.5),
              ),
              const SizedBox(width: 16),
            ],
            GardenButton(
              key: const ValueKey('check-updates-button'),
              label: controller.updateCheckInProgress ? '检查中' : '检查更新',
              icon: Icons.refresh_rounded,
              compact: true,
              busy: controller.updateCheckInProgress,
              onPressed: controller.updateCheckInProgress
                  ? null
                  : () => controller.checkForUpdates(),
            ),
            const SizedBox(width: 6),
            Stack(
              clipBehavior: Clip.none,
              children: [
                GardenIconButton(
                  key: const ValueKey('announcement-button'),
                  icon: Icons.campaign_outlined,
                  tooltip: '公告',
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
