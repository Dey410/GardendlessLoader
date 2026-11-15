import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../constants.dart';
import '../../l10n/app_strings.dart';
import '../../models.dart';
import '../launcher_actions.dart';
import '../theme/garden_theme.dart';
import '../widgets/garden_widgets.dart';

/// The sidebar's last tab: the loader, the two people behind it and the
/// game, where it runs, and whom it thanks. One scrolling column; the lower
/// cards sit side by side on a wide screen.
class AboutPage extends StatelessWidget {
  const AboutPage({
    super.key,
    required this.controller,
    required this.actions,
    required this.compact,
  });

  final AppController controller;
  final LauncherActions actions;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final gap = compact ? 16.0 : 20.0;
    return ListView(
      // Its own key, so it keeps its own scroll offset instead of the one
      // another tab saved at the same place in the tree.
      key: const PageStorageKey<String>('about-page'),
      padding: const EdgeInsets.only(bottom: 8),
      children: [
        _LoaderCard(controller: controller, actions: actions, compact: compact),
        SizedBox(height: gap),
        _SectionLabel(strings.aboutAuthors),
        _AuthorRow(
          controller: controller,
          actions: actions,
          compact: compact,
          gap: gap,
        ),
        SizedBox(height: gap),
        _LowerCards(controller: controller, actions: actions, gap: gap),
      ],
    );
  }
}

/// What the loader's update check says, and the colour to say it in.
(String, Color) _loaderUpdateStatus(
  AppController controller,
  AppStrings strings,
  GardenPalette palette,
) {
  return controller.availableUpdate != null
      ? (strings.updateAvailable, palette.accent)
      : controller.updateCheckInProgress
          ? (strings.checking, palette.inkMuted)
          : controller.latestAppVersion == null
              ? (strings.latestNotFetched, palette.inkMuted)
              : (strings.upToDate, palette.inkMuted);
}

/// Names a group of cards.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Text(
        text,
        style: TextStyle(
          color: context.garden.inkMuted,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

/// The loader's icon, name, version and the remote About text, with the
/// update action.
class _LoaderCard extends StatelessWidget {
  const _LoaderCard({
    required this.controller,
    required this.actions,
    required this.compact,
  });

  final AppController controller;
  final LauncherActions actions;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    final strings = context.strings;
    final about = controller.aboutContent;
    final update = controller.availableUpdate;
    final (status, statusColor) =
        _loaderUpdateStatus(controller, strings, palette);
    final iconSize = compact ? 52.0 : 64.0;
    return SurfaceCard(
      padding: EdgeInsets.all(compact ? 16 : 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(iconSize * 0.22),
            child: Image.asset(
              appIconAsset,
              width: iconSize,
              height: iconSize,
              cacheWidth: 192,
              excludeFromSemantics: true,
            ),
          ),
          SizedBox(width: compact ? 14 : 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  appDisplayName,
                  style:
                      GardenType.title(compact ? 18 : 20, color: palette.ink),
                ),
                const SizedBox(height: 3),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: 'v${controller.currentAppVersion}'),
                      const TextSpan(text: '  ·  '),
                      TextSpan(
                        text: status,
                        style: TextStyle(color: statusColor),
                      ),
                    ],
                  ),
                  key: const ValueKey('about-version-status'),
                  style: GardenType.mono(12.5, color: palette.inkMuted),
                ),
                const SizedBox(height: 10),
                ExcludeFocusTraversal(
                  child: SelectableText(
                    strings.isChinese
                        ? about.content
                        : about.contentEn ?? about.content,
                    style: TextStyle(
                      color: palette.inkMuted,
                      fontSize: 13.5,
                      height: 1.55,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (update != null)
                  GardenButton(
                    key: const ValueKey('about-view-release'),
                    label: strings.viewGithubRelease,
                    icon: Icons.download_rounded,
                    tone: GardenButtonTone.primary,
                    compact: true,
                    onPressed: () => actions.openRelease(update),
                  )
                else
                  GardenButton(
                    key: const ValueKey('about-check-updates'),
                    label: strings.checkForUpdates,
                    icon: Icons.refresh_rounded,
                    compact: true,
                    busy: controller.updateCheckInProgress,
                    onPressed: controller.initialized
                        ? controller.checkForUpdates
                        : null,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The loader's author and the game's author, side by side when they fit.
class _AuthorRow extends StatelessWidget {
  const _AuthorRow({
    required this.controller,
    required this.actions,
    required this.compact,
    required this.gap,
  });

  final AppController controller;
  final LauncherActions actions;
  final bool compact;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return LayoutBuilder(
      builder: (context, constraints) {
        final sideBySide = constraints.maxWidth >= 600;
        final cards = [
          _AuthorCard(
            key: const ValueKey('about-loader-author'),
            role: strings.loaderAuthorRole,
            avatarAsset: loaderAuthorAvatarAsset,
            fallbackIcon: Icons.smartphone_rounded,
            author: controller.loaderAuthor,
            compact: compact,
            fill: sideBySide,
            onOpenUrl: actions.openUrl,
          ),
          _AuthorCard(
            key: const ValueKey('about-game-author'),
            role: strings.gameAuthorRole,
            avatarAsset: gameAuthorAvatarAsset,
            fallbackIcon: Icons.local_florist_rounded,
            author: controller.gameAuthor,
            compact: compact,
            fill: sideBySide,
            onOpenUrl: actions.openUrl,
          ),
        ];
        if (!sideBySide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [cards[0], SizedBox(height: gap), cards[1]],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: cards[0]),
              SizedBox(width: gap),
              Expanded(child: cards[1]),
            ],
          ),
        );
      },
    );
  }
}

/// One author: their Bilibili avatar and name, what they made, one line
/// about them and their pages.
class _AuthorCard extends StatelessWidget {
  const _AuthorCard({
    super.key,
    required this.role,
    required this.avatarAsset,
    required this.fallbackIcon,
    required this.author,
    required this.compact,
    required this.fill,
    required this.onOpenUrl,
  });

  final String role;

  /// The author's Bilibili avatar, bundled so it shows offline.
  final String avatarAsset;

  /// Stands in for the avatar if the asset cannot be decoded.
  final IconData fallbackIcon;
  final AboutAuthor author;
  final bool compact;

  /// Keeps the links at the bottom when the card is stretched to match its
  /// neighbour.
  final bool fill;
  final Future<void> Function(String url) onOpenUrl;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    final strings = context.strings;
    final bio = author.bioFor(chinese: strings.isChinese);
    final links = [
      if (author.bilibili case final url?)
        AnnouncementLink(label: strings.bilibiliHome, url: url),
      if (author.github case final url?)
        AnnouncementLink(label: 'GitHub', url: url),
    ];
    final avatar = compact ? 44.0 : 52.0;
    return SurfaceCard(
      padding: EdgeInsets.all(compact ? 16 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: avatar,
                height: avatar,
                decoration: BoxDecoration(
                  color: palette.accent.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                  border: Border.all(color: palette.border),
                ),
                child: ClipOval(
                  child: Image.asset(
                    avatarAsset,
                    width: avatar,
                    height: avatar,
                    fit: BoxFit.cover,
                    cacheWidth: 192,
                    excludeFromSemantics: true,
                    errorBuilder: (context, _, __) => Icon(
                      fallbackIcon,
                      size: avatar * 0.48,
                      color: palette.accent,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      role,
                      style: TextStyle(
                        color: palette.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      author.name ?? strings.unknown,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GardenType.title(
                        compact ? 17 : 19,
                        color: palette.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (bio != null) ...[
            const SizedBox(height: 12),
            Text(
              bio,
              style: TextStyle(
                color: palette.inkMuted,
                fontSize: 13.5,
                height: 1.5,
              ),
            ),
          ],
          if (links.isNotEmpty) ...[
            if (fill) const Spacer(),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final link in links)
                  GardenButton(
                    label: link.label,
                    leading: linkIcon(link),
                    compact: true,
                    onPressed: () => onOpenUrl(link.url),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Where it runs, useful links, and credits: two columns on a wide screen.
class _LowerCards extends StatelessWidget {
  const _LowerCards({
    required this.controller,
    required this.actions,
    required this.gap,
  });

  final AppController controller;
  final LauncherActions actions;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final environment =
        _EnvironmentGroup(controller: controller, actions: actions);
    final links = _LinksGroup(links: controller.links, actions: actions);
    final credits = _CreditsGroup(controller: controller);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 720) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              environment,
              SizedBox(height: gap),
              links,
              SizedBox(height: gap),
              credits,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [environment, SizedBox(height: gap), links],
              ),
            ),
            SizedBox(width: gap),
            Expanded(child: credits),
          ],
        );
      },
    );
  }
}

/// A titled card whose rows are split by hairlines, like the settings
/// groups.
class _Group extends StatelessWidget {
  const _Group({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelHeader(title: title),
          const SizedBox(height: 4),
          for (final (index, child) in children.indexed) ...[
            if (index > 0) Divider(color: palette.border, height: 1),
            child,
          ],
        ],
      ),
    );
  }
}

/// The versions and the device a problem report needs, and the button that
/// copies them with the recent errors.
class _EnvironmentGroup extends StatelessWidget {
  const _EnvironmentGroup({required this.controller, required this.actions});

  final AppController controller;
  final LauncherActions actions;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    final strings = context.strings;
    final device = controller.hostDevice;
    final game = controller.hasCurrentResource
        ? [
            displayGameTitle(controller.detectedTitle),
            if (controller.currentGameVersion case final version?) version,
          ].join(' ')
        : strings.notImported;
    return _Group(
      key: const ValueKey('about-environment'),
      title: strings.aboutEnvironment,
      children: [
        InfoRow(
          label: strings.aboutLoader,
          value: 'v${controller.currentAppVersion}',
          mono: true,
        ),
        InfoRow(
          label: strings.aboutGame,
          value: game,
          color: controller.hasCurrentResource ? null : palette.inkMuted,
        ),
        if (controller.hasGpNext)
          InfoRow(
            label: 'GP-Next',
            value: controller.gpNextVersion ?? strings.unknown,
            color: controller.gpNextCompatible ? null : palette.warning,
            mono: true,
          ),
        InfoRow(
          label: strings.aboutWebEngine,
          value: device?.webViewVersion ?? strings.unknown,
        ),
        if (device?.model case final model?)
          InfoRow(label: strings.aboutDevice, value: model),
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                strings.aboutEnvironmentNote,
                style: TextStyle(
                  color: palette.inkMuted,
                  fontSize: 12.5,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 10),
              GardenButton(
                key: const ValueKey('about-copy-summary'),
                label: strings.copySummary,
                icon: Icons.copy_rounded,
                compact: true,
                onPressed: controller.initialized ? actions.copySummary : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Where to report a problem, get the loader or the game, and read the code.
class _LinksGroup extends StatelessWidget {
  const _LinksGroup({required this.links, required this.actions});

  final LauncherLinks links;
  final LauncherActions actions;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final items = <(String, Widget, String)>[
      (
        strings.reportIssue,
        const Icon(Icons.bug_report_outlined),
        appIssuesUrl
      ),
      (
        strings.loaderReleases,
        const Icon(Icons.new_releases_outlined),
        appReleasesUrl,
      ),
      (
        strings.cloudDriveDownload,
        const Icon(Icons.cloud_download_outlined),
        links.gameCloudDrive,
      ),
      (
        strings.githubPackages,
        const Icon(Icons.inventory_2_outlined),
        links.gamePackages,
      ),
      (
        strings.loaderGithub,
        linkIcon(AnnouncementLink(label: '', url: links.loaderGithub)),
        links.loaderGithub,
      ),
      (
        strings.upstreamGithub,
        linkIcon(AnnouncementLink(label: '', url: links.gameGithub)),
        links.gameGithub,
      ),
    ];
    return _Group(
      key: const ValueKey('about-links'),
      title: strings.aboutLinks,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (label, icon, url) in items)
                GardenButton(
                  label: label,
                  leading: icon,
                  compact: true,
                  onPressed: () => actions.openUrl(url),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Thanks, the licence and the trademark notice, and the bundled
/// third-party licences.
class _CreditsGroup extends StatelessWidget {
  const _CreditsGroup({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    final strings = context.strings;
    final body = TextStyle(color: palette.inkMuted, fontSize: 13, height: 1.5);
    return _Group(
      key: const ValueKey('about-credits'),
      title: strings.aboutCredits,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (index, line) in strings.aboutThanks.indexed) ...[
                if (index > 0) const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 7, right: 10),
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: palette.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Expanded(child: Text(line, style: body)),
                  ],
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(strings.aboutLicenseNotice, style: body),
              const SizedBox(height: 8),
              Text(
                strings.aboutTrademarkNotice,
                style: TextStyle(
                  color: palette.inkFaint,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: GardenButton(
                  key: const ValueKey('about-open-source-licenses'),
                  label: strings.openSourceLicenses,
                  icon: Icons.description_outlined,
                  compact: true,
                  onPressed: () => showLicensePage(
                    context: context,
                    applicationName: appDisplayName,
                    applicationVersion: 'v${controller.currentAppVersion}',
                    applicationIcon: Padding(
                      padding: const EdgeInsets.all(12),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.asset(
                          appIconAsset,
                          width: 56,
                          height: 56,
                          cacheWidth: 168,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
