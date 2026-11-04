import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../constants.dart';
import '../../game_host/game_host.dart';
import '../../l10n/app_strings.dart';
import '../../models.dart';
import '../../services/app_settings_store.dart';
import '../../services/launcher_themes.dart';
import '../../services/update_check_service.dart';
import '../launcher_actions.dart';
import '../theme/garden_theme.dart';
import '../widgets/garden_widgets.dart';

/// Two columns that scroll together: what the game uses on the left, the
/// launcher's own settings on the right. A narrow screen stacks them. A new
/// loader release shows above both.
class SettingsPage extends StatelessWidget {
  const SettingsPage({
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
    final update = controller.availableUpdate;
    final gap = compact ? 16.0 : 20.0;
    final game = <Widget>[
      _ColumnHeading(
          title: strings.settingsGame, note: strings.appliesNextLaunch),
      _DisplayGroup(controller: controller),
      SizedBox(height: gap),
      _ControlGroup(controller: controller),
      SizedBox(height: gap),
      _LaunchGroup(controller: controller),
    ];
    final launcher = <Widget>[
      _ColumnHeading(title: strings.settingsLauncher),
      _AppearanceGroup(controller: controller),
      SizedBox(height: gap),
      _AboutGroup(controller: controller, actions: actions),
      SizedBox(height: gap),
      _HelpGroup(
        gestureMode: controller.gestureMode,
        onOpenOnboarding: actions.openOnboarding,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 720;
        return ListView(
          padding: const EdgeInsets.only(bottom: 8),
          children: [
            if (update != null) ...[
              _UpdateBanner(
                update: update,
                controller: controller,
                actions: actions,
              ),
              SizedBox(height: gap),
            ],
            if (twoColumns)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: game,
                    ),
                  ),
                  SizedBox(width: gap + 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: launcher,
                    ),
                  ),
                ],
              )
            else ...[
              ...game,
              SizedBox(height: gap * 1.5),
              ...launcher,
            ],
          ],
        );
      },
    );
  }
}

/// Names a column; the game column says when its changes apply.
class _ColumnHeading extends StatelessWidget {
  const _ColumnHeading({required this.title, this.note});

  final String title;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            title,
            style: TextStyle(
              color: palette.inkMuted,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          if (note != null) ...[
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                note!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: palette.inkFaint, fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A card of settings rows under one title, with hairlines between rows.
class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
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

/// A single choice. The control sits beside the title when the row is wide
/// enough and under it otherwise; [detailOf] explains only the chosen value.
class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.values,
    required this.selected,
    required this.keyOf,
    required this.labelOf,
    required this.onChanged,
    this.detailOf,
  });

  final String title;
  final String? subtitle;
  final List<T> values;
  final T selected;
  final Key Function(T value) keyOf;
  final String Function(T value) labelOf;
  final ValueChanged<T> onChanged;
  final String Function(T value)? detailOf;

  static const _segmentWidth = 84.0;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    final detail = detailOf?.call(selected);
    final control = GardenSegmented<T>(
      values: values,
      selected: selected,
      keyOf: keyOf,
      labelOf: labelOf,
      onChanged: onChanged,
    );
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: palette.ink,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 3),
          Text(
            subtitle!,
            style: TextStyle(
              color: palette.inkMuted,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final controlWidth = values.length * _segmentWidth;
          final beside = constraints.maxWidth >= controlWidth + 140;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (beside)
                Row(
                  children: [
                    Expanded(child: text),
                    const SizedBox(width: 16),
                    SizedBox(width: controlWidth, child: control),
                  ],
                )
              else ...[
                text,
                const SizedBox(height: 10),
                control,
              ],
              if (detail != null) ...[
                const SizedBox(height: 8),
                Text(
                  detail,
                  style: TextStyle(
                    color: palette.inkMuted,
                    fontSize: 12.5,
                    height: 1.45,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _DisplayGroup extends StatelessWidget {
  const _DisplayGroup({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return _SettingsGroup(
      key: const ValueKey('settings-display'),
      title: strings.displaySettings,
      children: [
        _ChoiceRow<RenderResolution>(
          key: const ValueKey('render-resolution'),
          title: strings.renderResolution,
          subtitle: strings.renderResolutionSubtitle,
          values: RenderResolution.values,
          selected: controller.renderResolution,
          keyOf: (value) => ValueKey('render-resolution-${value.name}'),
          labelOf: strings.renderResolutionLabel,
          onChanged:
              controller.initialized ? controller.setRenderResolution : (_) {},
        ),
        _ChoiceRow<ScreenFit>(
          key: const ValueKey('screen-fit'),
          title: strings.screenFit,
          values: ScreenFit.values,
          selected: controller.screenFit,
          keyOf: (value) => ValueKey('screen-fit-${value.name}'),
          labelOf: strings.screenFitLabel,
          detailOf: strings.screenFitDetail,
          onChanged: controller.initialized ? controller.setScreenFit : (_) {},
        ),
        SwitchRow(
          key: const ValueKey('home-watermark'),
          switchKey: const ValueKey('home-watermark-switch'),
          title: strings.watermark,
          subtitle: strings.watermarkSubtitle,
          value: controller.watermarkEnabled,
          onChanged:
              controller.initialized ? controller.setWatermarkEnabled : null,
        ),
      ],
    );
  }
}

class _ControlGroup extends StatelessWidget {
  const _ControlGroup({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return _SettingsGroup(
      key: const ValueKey('settings-controls'),
      title: strings.controlSettings,
      children: [
        _ChoiceRow<GestureMode>(
          key: const ValueKey('gesture-mode'),
          title: strings.gestureMode,
          values: GestureMode.values,
          selected: controller.gestureMode,
          keyOf: (value) => ValueKey('gesture-mode-${value.name}'),
          labelOf: strings.gestureModeLabel,
          detailOf: strings.gestureModeDetail,
          onChanged:
              controller.initialized ? controller.setGestureMode : (_) {},
        ),
        SwitchRow(
          key: const ValueKey('haptic-effects'),
          switchKey: const ValueKey('haptic-effects-switch'),
          title: strings.hapticEffects,
          subtitle: strings.hapticEffectsSubtitle,
          value: controller.hapticEffectsEnabled,
          onChanged: controller.initialized
              ? controller.setHapticEffectsEnabled
              : null,
        ),
      ],
    );
  }
}

class _LaunchGroup extends StatelessWidget {
  const _LaunchGroup({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    // Auto collect is kept with the imported game.
    final hasGame = controller.hasCurrentResource;
    return _SettingsGroup(
      key: const ValueKey('launch-preferences'),
      title: strings.launchSettings,
      children: [
        SwitchRow(
          key: const ValueKey('home-quick-launch'),
          switchKey: const ValueKey('home-quick-launch-switch'),
          title: strings.quickLaunch,
          subtitle: strings.quickLaunchSubtitle,
          value: controller.quickLaunchEnabled,
          onChanged:
              controller.initialized ? controller.setQuickLaunchEnabled : null,
        ),
        SwitchRow(
          key: const ValueKey('home-auto-collect-sun'),
          switchKey: const ValueKey('home-auto-collect-sun-switch'),
          title: strings.autoCollectSun,
          subtitle: hasGame
              ? strings.autoCollectSunSubtitle
              : strings.autoCollectNeedsGame,
          value: controller.autoCollectSunEnabled,
          onChanged: hasGame ? controller.setAutoCollectSunEnabled : null,
        ),
      ],
    );
  }
}

class _AppearanceGroup extends StatelessWidget {
  const _AppearanceGroup({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    final strings = context.strings;
    final platform = controller.gameHostPlatform;
    final showCanvasFrame = platform == GameHostPlatform.ios ||
        platform == GameHostPlatform.android ||
        platform == GameHostPlatform.ohos;
    return _SettingsGroup(
      key: const ValueKey('settings-appearance'),
      title: strings.appearance,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.theme,
                style: TextStyle(
                  color: palette.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              _ThemePicker(controller: controller),
            ],
          ),
        ),
        if (showCanvasFrame)
          SwitchRow(
            key: const ValueKey('game-canvas-frame'),
            switchKey: const ValueKey('game-canvas-frame-switch'),
            title: strings.gameCanvasFrame,
            subtitle: strings.gameCanvasFrameSubtitle,
            value: controller.gameCanvasFrameEnabled,
            onChanged: controller.initialized
                ? controller.setGameCanvasFrameEnabled
                : null,
          ),
        _ChoiceRow<ThemePreference>(
          key: const ValueKey('theme-preference'),
          title: strings.brightness,
          values: ThemePreference.values,
          selected: controller.themePreference,
          keyOf: (value) => ValueKey('theme-preference-${value.name}'),
          labelOf: (value) => switch (value) {
            ThemePreference.system => strings.followSystem,
            ThemePreference.light => strings.lightTheme,
            ThemePreference.dark => strings.darkTheme,
          },
          onChanged:
              controller.initialized ? controller.setThemePreference : (_) {},
        ),
        _ChoiceRow<LanguagePreference>(
          key: const ValueKey('language-preference'),
          title: strings.language,
          values: LanguagePreference.values,
          selected: controller.languagePreference,
          keyOf: (value) => ValueKey('language-preference-${value.name}'),
          // Language names stay in their own language.
          labelOf: (value) => switch (value) {
            LanguagePreference.system => strings.followSystem,
            LanguagePreference.chinese => '中文',
            LanguagePreference.english => 'English',
          },
          onChanged: controller.initialized
              ? controller.setLanguagePreference
              : (_) {},
        ),
        SwitchRow(
          key: const ValueKey('reduce-motion'),
          switchKey: const ValueKey('reduce-motion-switch'),
          title: strings.reduceMotion,
          subtitle: strings.reduceMotionSubtitle,
          value: controller.reduceMotion,
          onChanged: controller.initialized ? controller.setReduceMotion : null,
        ),
      ],
    );
  }
}

/// A newer loader release, above both columns until it is installed or put
/// off.
class _UpdateBanner extends StatelessWidget {
  const _UpdateBanner({
    required this.update,
    required this.controller,
    required this.actions,
  });

  final UpdateInfo update;
  final AppController controller;
  final LauncherActions actions;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    final strings = context.strings;
    final summary = [
      'v${update.currentVersion} → v${update.latestVersion}',
      if (update.releaseName.isNotEmpty) update.releaseName,
    ].join('  ·  ');
    return Container(
      key: const ValueKey('app-update-entry'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.system_update_alt_rounded,
              size: 22, color: palette.accent),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.loaderUpdateTitle(update.latestVersion),
                  style: GardenType.title(15, color: palette.ink),
                ),
                const SizedBox(height: 4),
                Text(
                  summary,
                  style: TextStyle(color: palette.inkMuted, fontSize: 12.5),
                ),
                if (update.releaseNotes.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    update.releaseNotes,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.inkMuted,
                      fontSize: 12.5,
                      height: 1.5,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    GardenButton(
                      label: strings.cloudDriveUpdate,
                      icon: Icons.download_rounded,
                      tone: GardenButtonTone.primary,
                      compact: true,
                      onPressed: () =>
                          actions.openUrl(controller.links.loaderCloudDrive),
                    ),
                    GardenButton(
                      label: strings.viewGithubRelease,
                      compact: true,
                      onPressed: () => actions.openRelease(update),
                    ),
                    GardenButton(
                      label: strings.remindLater,
                      tone: GardenButtonTone.ghost,
                      compact: true,
                      onPressed: () => actions.deferUpdate(update),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The loader's identity, version and links.
class _AboutGroup extends StatelessWidget {
  const _AboutGroup({required this.controller, required this.actions});

  final AppController controller;
  final LauncherActions actions;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    final strings = context.strings;
    final launcherLinks = controller.links;
    final links = <AnnouncementLink>[
      AnnouncementLink(
          label: strings.loaderGithub, url: launcherLinks.loaderGithub),
      AnnouncementLink(
          label: strings.upstreamGithub, url: launcherLinks.gameGithub),
      AnnouncementLink(
          label: strings.bilibiliHome, url: launcherLinks.bilibili),
    ];
    final (String status, Color statusColor) =
        controller.availableUpdate != null
            ? (strings.updateAvailable, palette.accent)
            : controller.updateCheckInProgress
                ? (strings.checking, palette.inkMuted)
                : controller.latestAppVersion == null
                    ? (strings.latestNotFetched, palette.inkMuted)
                    : (strings.upToDate, palette.inkMuted);
    return _SettingsGroup(
      key: const ValueKey('about-panel'),
      title: strings.aboutTitle,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.asset(
                      appIconAsset,
                      width: 40,
                      height: 40,
                      cacheWidth: 128,
                      excludeFromSemantics: true,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          appDisplayName,
                          style: TextStyle(
                            color: palette.ink,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                  text: 'v${controller.currentAppVersion}'),
                              const TextSpan(text: '  ·  '),
                              TextSpan(
                                text: status,
                                style: TextStyle(color: statusColor),
                              ),
                            ],
                          ),
                          key: const ValueKey('app-version-status'),
                          style: GardenType.mono(12.5, color: palette.inkMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ExcludeFocusTraversal(
                child: SelectableText(
                  strings.isChinese
                      ? controller.aboutContent.content
                      : controller.aboutContent.contentEn ??
                          controller.aboutContent.content,
                  style: TextStyle(
                    color: palette.inkMuted,
                    fontSize: 13,
                    height: 1.55,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final link in links)
                    GardenButton(
                      label: link.label,
                      leading: linkIcon(link),
                      compact: true,
                      onPressed: () => actions.openUrl(link.url),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The welcome guide, and the touch controls folded away until asked for.
class _HelpGroup extends StatelessWidget {
  const _HelpGroup({
    required this.gestureMode,
    required this.onOpenOnboarding,
  });

  final GestureMode gestureMode;
  final VoidCallback onOpenOnboarding;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    final strings = context.strings;
    final icons = switch (gestureMode) {
      GestureMode.simulated => const <IconData>[
          Icons.touch_app_rounded,
          Icons.ads_click_rounded,
          Icons.swipe_vertical_rounded,
          Icons.do_not_touch_rounded,
          Icons.keyboard_rounded,
        ],
      GestureMode.native => const <IconData>[
          Icons.touch_app_rounded,
          Icons.back_hand_rounded,
          Icons.pinch_rounded,
          Icons.do_not_touch_rounded,
          Icons.keyboard_rounded,
        ],
    };
    final gestures = [
      for (final (index, (gesture, mapping))
          in strings.gestures(gestureMode).indexed)
        (icons[index], gesture, mapping),
    ];
    return _SettingsGroup(
      key: const ValueKey('settings-help'),
      title: strings.help,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: GardenButton(
              key: const ValueKey('open-onboarding-button'),
              label: strings.openOnboarding,
              icon: Icons.waving_hand_outlined,
              compact: true,
              onPressed: onOpenOnboarding,
            ),
          ),
        ),
        Disclosure(
          key: const ValueKey('touch-guide'),
          title: strings.touchGuide,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (icon, gesture, mapping) in gestures)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Icon(icon, size: 18, color: palette.inkMuted),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            gesture,
                            style: TextStyle(
                              color: palette.ink,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            mapping,
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              color: palette.inkMuted,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Divider(color: palette.border, height: 20),
                for (final tip in strings.guideTips)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 7),
                          child: Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: palette.inkFaint,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            tip,
                            style: TextStyle(
                              color: palette.inkMuted,
                              fontSize: 12.5,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Auto and the launcher themes as swatches. A tap on Auto or an unlocked
/// theme wears it; a tap on a locked one only shows what unlocks it.
class _ThemePicker extends StatefulWidget {
  const _ThemePicker({required this.controller});

  final AppController controller;

  @override
  State<_ThemePicker> createState() => _ThemePickerState();
}

class _ThemePickerState extends State<_ThemePicker> {
  /// The swatch described below the grid; null is Auto.
  late LauncherTheme? _shown =
      LauncherTheme.byId(widget.controller.pickedLauncherTheme);

  void _tap(LauncherTheme? theme) {
    final controller = widget.controller;
    setState(() => _shown = theme);
    if (!controller.initialized) return;
    if (theme == null || theme.unlockedIn(controller.journal)) {
      controller.setLauncherTheme(theme?.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final palette = context.garden;
    final strings = context.strings;
    final journal = controller.journal;
    final picked = controller.pickedLauncherTheme;
    final shown = _shown;
    final detail = switch (shown) {
      null => '${strings.autoTheme} · ${strings.autoThemeDetail}',
      _ when shown.unlockedIn(journal) =>
        '${strings.inGame(shown.name)} · ${strings.themeUnlocked}',
      _ => '${strings.inGame(shown.name)} · ${strings.themeUnlock(
          shown.unlock,
          journal,
          nextFestivalDay: switch (shown.unlock) {
            final DuringFestival unlock => controller.nextFestivalDay(unlock),
            _ => null,
          },
        )}',
    };
    final garden =
        palette.isDark ? GardenPalette.dark.accent : GardenPalette.light.accent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ThemeSwatch(
              key: const ValueKey('launcher-theme-auto'),
              label: strings.autoTheme,
              color: palette.surfaceMuted,
              selected: picked == null,
              onTap: () => _tap(null),
              child: Icon(
                Icons.auto_awesome_rounded,
                size: 18,
                color: palette.inkMuted,
              ),
            ),
            for (final theme in LauncherTheme.all)
              if (theme.unlockedIn(journal))
                _ThemeSwatch(
                  key: ValueKey('launcher-theme-${theme.id}'),
                  label: strings.inGame(theme.name),
                  color: Color(
                    (palette.isDark ? theme.accentDark : theme.accent) ??
                        garden.toARGB32(),
                  ),
                  selected: picked == theme.id,
                  onTap: () => _tap(theme),
                  child: Text(
                    theme.badge ?? '',
                    style: const TextStyle(fontSize: 17, height: 1),
                  ),
                )
              else
                _ThemeSwatch(
                  key: ValueKey('launcher-theme-${theme.id}'),
                  label: strings.inGame(theme.name),
                  color: Color(
                    (palette.isDark ? theme.accentDark : theme.accent)!,
                  ).withValues(alpha: 0.22),
                  selected: false,
                  onTap: () => _tap(theme),
                  child: Icon(
                    Icons.lock_rounded,
                    size: 15,
                    color: palette.inkMuted,
                  ),
                ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          detail,
          key: const ValueKey('launcher-theme-detail'),
          style: TextStyle(
            color: palette.inkMuted,
            fontSize: 12.5,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({
    super.key,
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      tooltip: label,
      scale: 0.92,
      child: Container(
        width: 42,
        height: 42,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? palette.ink : Colors.transparent,
            width: 2,
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Center(child: child),
        ),
      ),
    );
  }
}
