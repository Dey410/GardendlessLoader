import 'package:flutter/material.dart';

import '../../app_controller.dart';
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

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final gap = widget.compact ? 20.0 : 32.0;
    final ready = controller.canStartGame;
    final hero = _Hero(controller: controller, compact: widget.compact);
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
            children: [hero, SizedBox(height: gap), actionBar],
          );
        }
        // Launcher composition: the key art owns the open area, the title
        // sits bottom-left on the same row as the primary action.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(),
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
  const _Hero({required this.controller, required this.compact});

  final AppController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    final ready = controller.canStartGame;
    final details = <String>[
      if (ready) '版本 ${controller.currentGameVersion ?? '未知'}',
      if (ready)
        !controller.hasGpNext
            ? '标准 Web'
            : controller.gpNextCompatible
                ? 'GP-Next ${controller.gpNextVersion ?? ''}'.trim()
                : 'GP-Next 不兼容',
      controller.gameHostPlatform.nativeHostName,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        StatusLabel(
          key: const ValueKey('game-readiness-chip'),
          label: ready ? '资源已就绪' : '需要导入资源',
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
          ready
              ? details.join('  ·  ')
              : '导入一份 Gardendless Web 资源 ZIP 后即可开始游戏。',
          style: TextStyle(color: palette.inkMuted, fontSize: 14, height: 1.5),
        ),
      ],
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (ready)
          GardenButton(
            key: const ValueKey('start-game-button'),
            label: launching ? '正在启动…' : '开始游戏',
            icon: Icons.play_arrow_rounded,
            tone: GardenButtonTone.primary,
            busy: launching,
            onPressed: onLaunch,
          )
        else
          GardenButton(
            key: const ValueKey('go-import-button'),
            label: '前往导入资源',
            icon: Icons.arrow_forward_rounded,
            tone: GardenButtonTone.primary,
            onPressed: onImport,
          ),
      ],
    );
  }
}
