import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../game_host/game_session_store.dart';
import '../../l10n/app_strings.dart';
import '../../services/app_settings_store.dart';
import '../../services/launcher_themes.dart';
import '../launcher_actions.dart';
import '../theme/garden_theme.dart';
import '../widgets/garden_widgets.dart';

class PlayPage extends StatefulWidget {
  const PlayPage({
    super.key,
    required this.controller,
    required this.actions,
    required this.compact,
  });

  final AppController controller;
  final LauncherActions actions;
  final bool compact;

  @override
  State<PlayPage> createState() => _PlayPageState();
}

class _PlayPageState extends State<PlayPage> {
  bool _launching = false;

  Future<void> _launch() async {
    if (_launching) return;
    setState(() => _launching = true);
    try {
      await widget.actions.startGame();
    } finally {
      if (mounted) setState(() => _launching = false);
    }
  }

  Future<void> _launchAtLowerResolution() async {
    if (_launching) return;
    final controller = widget.controller;
    await controller.setRenderResolution(controller.renderResolution.lower!);
    await _launch();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final gap = widget.compact ? 20.0 : 32.0;
    final ready = controller.canStartGame;
    final hero = _Hero(
      controller: controller,
      compact: widget.compact,
      onViewLogs: () => widget.actions.navigate(LauncherDestination.logs),
    );
    final report = controller.lastGameReport;
    final recovery = ready && report != null && report.crashed
        ? _RecoveryCard(
            report: report,
            lower: controller.renderResolution.lower,
            onLowerAndPlay: _launching ? null : _launchAtLowerResolution,
          )
        : null;
    final actionBar = _ActionBar(
      ready: ready,
      launching: _launching,
      onLaunch: _launch,
      onImport: () => widget.actions.navigate(LauncherDestination.resources),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return ListView(
            children: [
              if (recovery != null) ...[recovery, SizedBox(height: gap)],
              hero,
              SizedBox(height: gap),
              actionBar,
            ],
          );
        }
        // Launcher composition: the key art owns the open area, the title
        // sits bottom-left on the same row as the primary action.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(),
            if (recovery != null) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: recovery,
                ),
              ),
              SizedBox(height: gap),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: hero),
                const SizedBox(width: 16),
                actionBar,
              ],
            ),
          ],
        );
      },
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.controller,
    required this.compact,
    required this.onViewLogs,
  });

  final AppController controller;
  final bool compact;
  final VoidCallback onViewLogs;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    final strings = context.strings;
    final ready = controller.canStartGame;
    final journal = controller.journal;
    final lastPlayedAt = journal.lastPlayedAt;
    final report = controller.lastGameReport;
    final event = controller.gameEvent;
    final details = <String>[
      if (ready) strings.gameVersionLabel(controller.currentGameVersion),
      if (ready)
        !controller.hasGpNext
            ? strings.standardWeb
            : controller.gpNextCompatible
                ? 'GP-Next ${controller.gpNextVersion ?? ''}'.trim()
                : strings.gpNextIncompatibleShort,
      controller.gameHostPlatform.nativeHostName,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        StatusLabel(
          key: const ValueKey('game-readiness-chip'),
          label: ready ? strings.resourcesReady : strings.resourcesNeeded,
          color: ready ? palette.accent : palette.warning,
        ),
        SizedBox(height: compact ? 12 : 16),
        Text(
          ready
              ? displayGameTitle(controller.detectedTitle)
              : 'PvZ2 Gardendless',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GardenType.title(compact ? 34 : 46, color: palette.ink),
        ),
        const SizedBox(height: 10),
        Text(
          ready ? details.join('  ·  ') : strings.importToPlayHint,
          style: TextStyle(color: palette.inkMuted, fontSize: 14, height: 1.5),
        ),
        if (ready && lastPlayedAt != null)
          Text(
            '${strings.lastPlayed(lastPlayedAt, Duration(milliseconds: journal.lastPlayMs))}'
            '  ·  ${strings.totalPlayed(Duration(milliseconds: journal.totalPlayMs))}',
            key: const ValueKey('last-played'),
            style:
                TextStyle(color: palette.inkFaint, fontSize: 13, height: 1.5),
          ),
        // The game's own event today, in its words.
        if (event != null)
          Text(
            [
              LauncherTheme.forEvent(event)?.badge,
              strings.inGame(event.title),
              strings.inGame(event.description),
            ].nonNulls.join(' '),
            key: const ValueKey('game-event'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: palette.accent, fontSize: 13, height: 1.5),
          ),
        // A crash has its own card; this line is for errors in a game the
        // player left.
        if (ready &&
            report != null &&
            !report.crashed &&
            report.errorCount > 0) ...[
          const SizedBox(height: 8),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text(
                strings.lastGameErrors(report.errorCount),
                key: const ValueKey('last-game-errors'),
                style: TextStyle(color: palette.warning, fontSize: 13),
              ),
              GardenButton(
                label: strings.viewLogs,
                tone: GardenButtonTone.ghost,
                compact: true,
                onPressed: onViewLogs,
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// What ended the last game, and the one remedy the launcher can apply.
class _RecoveryCard extends StatelessWidget {
  const _RecoveryCard({
    required this.report,
    required this.lower,
    required this.onLowerAndPlay,
  });

  final GameSessionReport report;

  /// The next lower render resolution; null at the lowest.
  final RenderResolution? lower;
  final VoidCallback? onLowerAndPlay;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    final strings = context.strings;
    final rendererGone = report.reason == GameExitReason.rendererGone;
    final lower = this.lower;
    final body = [
      rendererGone
          ? strings.gameRendererGoneCause
          : strings.gameInterruptedCause,
      if (report.memoryWarnings > 0)
        strings.memoryWarnings(report.memoryWarnings),
      lower == null
          ? strings.lowestResolutionHint
          : strings.lowerResolutionHint,
    ].join(strings.isChinese ? '' : ' ');
    return SurfaceCard(
      key: const ValueKey('game-recovery-card'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: 18, color: palette.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  rendererGone
                      ? strings.gameRendererGoneTitle
                      : strings.gameInterruptedTitle,
                  style: GardenType.title(15, color: palette.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style:
                TextStyle(color: palette.inkMuted, fontSize: 13.5, height: 1.5),
          ),
          if (lower != null) ...[
            const SizedBox(height: 12),
            GardenButton(
              key: const ValueKey('lower-resolution-button'),
              label: strings.lowerResolutionAndPlay(
                strings.renderResolutionLabel(lower),
              ),
              icon: Icons.play_arrow_rounded,
              compact: true,
              onPressed: onLowerAndPlay,
            ),
          ],
        ],
      ),
    );
  }
}

/// The page's one primary action, anchored bottom-right where the thumb
/// rests in landscape.
class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.ready,
    required this.launching,
    required this.onLaunch,
    required this.onImport,
  });

  final bool ready;
  final bool launching;
  final VoidCallback onLaunch;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (ready)
          GardenButton(
            key: const ValueKey('start-game-button'),
            label: launching ? strings.starting : strings.startGame,
            icon: Icons.play_arrow_rounded,
            tone: GardenButtonTone.primary,
            busy: launching,
            onPressed: onLaunch,
          )
        else
          GardenButton(
            key: const ValueKey('go-import-button'),
            label: strings.goToImport,
            icon: Icons.arrow_forward_rounded,
            tone: GardenButtonTone.primary,
            onPressed: onImport,
          ),
      ],
    );
  }
}
