import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../constants.dart';
import '../../game_host/game_host.dart';
import '../../l10n/app_strings.dart';
import '../../models.dart';
import '../theme/garden_theme.dart';
import '../widgets/garden_widgets.dart';
import '../widgets/key_art_backdrop.dart';

/// How the player left the welcome pages.
enum OnboardingExit { skipped, finished }

/// Opens the welcome pages over the launcher. Completes with null when the
/// player closed them with system Back or a controller's B.
Future<OnboardingExit?> showOnboarding(
  BuildContext context, {
  required GameHostPlatform platform,
  required GestureMode gestureMode,
  required LauncherLinks links,
  required bool hasResource,
  required bool reduceMotion,
  required Future<void> Function(String url) onOpenUrl,
}) {
  final reduced =
      reduceMotion || (MediaQuery.maybeDisableAnimationsOf(context) ?? false);
  return showGeneralDialog<OnboardingExit>(
    context: context,
    barrierDismissible: true,
    barrierLabel: context.strings.onboardingSkip,
    barrierColor: Colors.transparent,
    transitionDuration: reduced ? Duration.zero : GardenMotion.panel,
    pageBuilder: (context, _, __) => GardenMotionScope(
      reduceMotion: reduceMotion,
      child: OnboardingPage(
        platform: platform,
        gestureMode: gestureMode,
        links: links,
        hasResource: hasResource,
        onOpenUrl: onOpenUrl,
      ),
    ),
    transitionBuilder: (context, animation, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: GardenMotion.easeOut),
      child: child,
    ),
  );
}

/// Four pages a new player turns by hand: what the loader is, where the game
/// comes from, how to import it and how to play.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({
    super.key,
    required this.platform,
    required this.gestureMode,
    required this.links,
    required this.hasResource,
    required this.onOpenUrl,
  });

  final GameHostPlatform platform;
  final GestureMode gestureMode;
  final LauncherLinks links;

  /// A game is already imported, so the last page needs no import.
  final bool hasResource;
  final Future<void> Function(String url) onOpenUrl;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  static const _pageCount = 4;

  final PageController _pages = PageController();
  int _page = 0;

  bool get _last => _page == _pageCount - 1;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _turnTo(int page) {
    if (GardenMotionScope.reduced(context)) {
      _pages.jumpToPage(page);
    } else {
      _pages.animateToPage(
        page,
        duration: GardenMotion.panel,
        curve: GardenMotion.easeOut,
      );
    }
  }

  void _next() {
    if (_last) {
      Navigator.of(context).pop(OnboardingExit.finished);
    } else {
      _turnTo(_page + 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    final strings = context.strings;
    final pages = [
      const _WelcomeStep(),
      _GetGameStep(
        platform: widget.platform,
        links: widget.links,
        onOpenUrl: widget.onOpenUrl,
      ),
      _ImportStep(platform: widget.platform),
      _PlayStep(platform: widget.platform, gestureMode: widget.gestureMode),
    ];
    return Material(
      color: palette.background,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const KeyArtBackdrop(),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact =
                    constraints.maxHeight < 470 || constraints.maxWidth < 760;
                return Padding(
                  padding: EdgeInsets.all(compact ? 12 : 32),
                  child: Center(
                    child: ConstrainedBox(
                      constraints:
                          const BoxConstraints(maxWidth: 880, maxHeight: 540),
                      child: SurfaceCard(
                        padding: EdgeInsets.fromLTRB(
                          compact ? 20 : 32,
                          compact ? 8 : 16,
                          compact ? 16 : 24,
                          compact ? 12 : 20,
                        ),
                        child: Column(
                          children: [
                            SizedBox(
                              height: 36,
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: _last
                                    ? null
                                    : GardenButton(
                                        key: const ValueKey('onboarding-skip'),
                                        label: strings.onboardingSkip,
                                        tone: GardenButtonTone.ghost,
                                        compact: true,
                                        onPressed: () => Navigator.of(context)
                                            .pop(OnboardingExit.skipped),
                                      ),
                              ),
                            ),
                            Expanded(
                              child: _StepScope(
                                compact: compact,
                                child: PageView(
                                  controller: _pages,
                                  onPageChanged: (page) =>
                                      setState(() => _page = page),
                                  children: pages,
                                ),
                              ),
                            ),
                            SizedBox(height: compact ? 8 : 16),
                            Row(
                              children: [
                                _PageDots(count: _pageCount, page: _page),
                                const Spacer(),
                                if (_page > 0) ...[
                                  GardenButton(
                                    key: const ValueKey('onboarding-back'),
                                    label: strings.onboardingBack,
                                    tone: GardenButtonTone.ghost,
                                    onPressed: () => _turnTo(_page - 1),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                GardenButton(
                                  key: const ValueKey('onboarding-next'),
                                  label: !_last
                                      ? strings.onboardingNext
                                      : widget.hasResource
                                          ? strings.onboardingDone
                                          : strings.onboardingImport,
                                  icon: _last && widget.hasResource
                                      ? Icons.check_rounded
                                      : Icons.arrow_forward_rounded,
                                  tone: GardenButtonTone.primary,
                                  autofocus: true,
                                  onPressed: _next,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Tells the steps whether the screen is small.
class _StepScope extends InheritedWidget {
  const _StepScope({required this.compact, required super.child});

  final bool compact;

  static bool compactOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_StepScope>()?.compact ??
      false;

  @override
  bool updateShouldNotify(_StepScope oldWidget) => oldWidget.compact != compact;
}

/// One page: the art on the left, the words on the right. The words scroll
/// when a short landscape phone cannot fit them.
class _StepLayout extends StatelessWidget {
  const _StepLayout({
    required this.art,
    required this.title,
    required this.children,
  });

  final Widget art;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    final compact = _StepScope.compactOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final artSize = math.min(compact ? 120.0 : 180.0,
            constraints.maxHeight * (compact ? 0.55 : 0.6));
        final words = LayoutBuilder(
          builder: (context, viewport) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: viewport.maxHeight),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style:
                        GardenType.title(compact ? 22 : 28, color: palette.ink),
                  ),
                  SizedBox(height: compact ? 10 : 14),
                  ...children,
                ],
              ),
            ),
          ),
        );
        return Row(
          children: [
            if (constraints.maxWidth >= 520) ...[
              SizedBox.square(dimension: artSize, child: art),
              SizedBox(width: compact ? 24 : 40),
            ],
            Expanded(child: words),
          ],
        );
      },
    );
  }
}

/// A large icon on a soft accent tile.
class _StepArt extends StatelessWidget {
  const _StepArt({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    return LayoutBuilder(
      builder: (context, constraints) => DecoratedBox(
        decoration: BoxDecoration(
          color: palette.accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(constraints.maxWidth * 0.22),
        ),
        child: Center(
          child: Icon(
            icon,
            size: constraints.maxWidth * 0.42,
            color: palette.accent,
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: context.garden.inkMuted,
        fontSize: _StepScope.compactOf(context) ? 14 : 15,
        height: 1.6,
      ),
    );
  }
}

/// An icon and a line of text, for the points of a step.
class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text, this.color});

  final IconData icon;
  final InlineSpan text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    final compact = _StepScope.compactOf(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 4 : 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 18, color: color ?? palette.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              text,
              style: TextStyle(
                color: color ?? palette.inkMuted,
                fontSize: compact ? 13 : 14,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep();

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    final strings = context.strings;
    final steps = strings.onboardingSteps;
    return _StepLayout(
      art: LayoutBuilder(
        builder: (context, constraints) => ClipRRect(
          borderRadius: BorderRadius.circular(constraints.maxWidth * 0.22),
          child: Image.asset(
            appIconAsset,
            cacheWidth: 384,
            fit: BoxFit.cover,
            semanticLabel: 'GardendlessLoader',
          ),
        ),
      ),
      title: strings.onboardingWelcomeTitle,
      children: [
        _Body(strings.onboardingWelcomeBody),
        const SizedBox(height: 18),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final (index, step) in steps.indexed) ...[
              if (index > 0)
                Icon(Icons.arrow_forward_rounded,
                    size: 16, color: palette.inkFaint),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: palette.surfaceMuted,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: palette.border),
                ),
                child: Text(
                  '${index + 1}  $step',
                  style: TextStyle(
                    color: palette.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _GetGameStep extends StatelessWidget {
  const _GetGameStep({
    required this.platform,
    required this.links,
    required this.onOpenUrl,
  });

  final GameHostPlatform platform;
  final LauncherLinks links;
  final Future<void> Function(String url) onOpenUrl;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    final strings = context.strings;
    // The cloud drive is the fast route in China; GitHub everywhere else.
    final cloudFirst = strings.isChinese;
    final ohos = platform == GameHostPlatform.ohos;
    final cloud = GardenButton(
      key: const ValueKey('onboarding-cloud-drive'),
      label: strings.cloudDriveDownload,
      icon: Icons.download_rounded,
      tone: cloudFirst ? GardenButtonTone.primary : GardenButtonTone.secondary,
      compact: true,
      onPressed: () => onOpenUrl(links.gameCloudDrive),
    );
    final github = GardenButton(
      key: const ValueKey('onboarding-github-packages'),
      label: strings.githubPackages,
      leading: const FaIcon(FontAwesomeIcons.github),
      tone: cloudFirst ? GardenButtonTone.secondary : GardenButtonTone.primary,
      compact: true,
      onPressed: () => onOpenUrl(links.gamePackages),
    );
    return _StepLayout(
      art: const _StepArt(icon: Icons.cloud_download_rounded),
      title: strings.onboardingGetTitle,
      children: [
        _Body(strings.onboardingGetBody),
        const SizedBox(height: 6),
        _Point(
          icon: ohos ? Icons.warning_amber_rounded : Icons.info_outline_rounded,
          color: ohos ? palette.warning : null,
          text: TextSpan(text: strings.onboardingPackageNote(platform)),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: cloudFirst ? [cloud, github] : [github, cloud],
        ),
        const SizedBox(height: 10),
        for (final note in strings.onboardingDownloadNotes)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              note,
              style: TextStyle(
                color: palette.inkFaint,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ),
      ],
    );
  }
}

class _ImportStep extends StatelessWidget {
  const _ImportStep({required this.platform});

  final GameHostPlatform platform;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final points = strings.onboardingImportPoints(platform);
    final icons = [
      Icons.folder_open_rounded,
      platform == GameHostPlatform.ios
          ? Icons.ios_share_rounded
          : Icons.share_rounded,
      Icons.verified_user_outlined,
    ];
    return _StepLayout(
      art: const _StepArt(icon: Icons.folder_zip_rounded),
      title: strings.onboardingImportTitle,
      children: [
        for (final (index, point) in points.indexed)
          _Point(icon: icons[index], text: TextSpan(text: point)),
      ],
    );
  }
}

class _PlayStep extends StatelessWidget {
  const _PlayStep({required this.platform, required this.gestureMode});

  final GameHostPlatform platform;
  final GestureMode gestureMode;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    final strings = context.strings;
    // The first three gestures are the ones a level needs; the guide in
    // Settings lists the rest.
    final gestureIcons = switch (gestureMode) {
      GestureMode.simulated => const [
          Icons.touch_app_rounded,
          Icons.ads_click_rounded,
          Icons.swipe_vertical_rounded,
        ],
      GestureMode.native => const [
          Icons.touch_app_rounded,
          Icons.back_hand_rounded,
          Icons.pinch_rounded,
        ],
    };
    final gestures = strings.gestures(gestureMode).take(gestureIcons.length);
    const tipIcons = [
      Icons.arrow_back_rounded,
      Icons.save_alt_rounded,
      Icons.tune_rounded,
    ];
    return _StepLayout(
      art: const _StepArt(icon: Icons.sports_esports_rounded),
      title: strings.onboardingPlayTitle,
      children: [
        _Body(strings.onboardingPlayBody),
        const SizedBox(height: 4),
        for (final (index, (gesture, mapping)) in gestures.indexed)
          _Point(
            icon: gestureIcons[index],
            text: TextSpan(
              children: [
                TextSpan(
                  text: gesture,
                  style: TextStyle(
                    color: palette.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(text: '  ·  $mapping'),
              ],
            ),
          ),
        Divider(color: palette.border, height: 20),
        for (final (index, tip) in strings.onboardingPlayTips(platform).indexed)
          _Point(icon: tipIcons[index], text: TextSpan(text: tip)),
        const SizedBox(height: 8),
        Text(
          strings.onboardingReopenHint,
          style: TextStyle(color: palette.inkFaint, fontSize: 12, height: 1.5),
        ),
      ],
    );
  }
}

/// Which page is showing; the current one is a short pill.
class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.page});

  final int count;
  final int page;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    final reduced = GardenMotionScope.reduced(context);
    return Semantics(
      label: context.strings.onboardingPage(page + 1, count),
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < count; index++)
              AnimatedContainer(
                duration: reduced ? Duration.zero : GardenMotion.quick,
                curve: GardenMotion.easeOut,
                margin: const EdgeInsets.only(right: 6),
                width: index == page ? 20 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: index == page ? palette.accent : palette.border,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
