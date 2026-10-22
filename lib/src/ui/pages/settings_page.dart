import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../constants.dart';
import '../../game_host/game_host.dart';
import '../../l10n/app_strings.dart';
import '../../models.dart';
import '../../services/app_settings_store.dart';
import '../launcher_actions.dart';
import '../theme/garden_theme.dart';
import '../widgets/garden_widgets.dart';

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
    return TwoColumn(
      gap: compact ? 16 : 24,
      left: [
        _LoaderPanel(controller: controller, actions: actions),
        const SizedBox(height: 16),
        _LaunchPreferences(controller: controller),
        const SizedBox(height: 16),
        _AppearancePanel(controller: controller),
      ],
      right: [
        _AboutPanel(controller: controller, actions: actions),
        const SizedBox(height: 16),
        _GuidePanel(gestureMode: controller.gestureMode),
      ],
    );
  }
}

class _LoaderPanel extends StatelessWidget {
  const _LoaderPanel({required this.controller, required this.actions});

  final AppController controller;
  final LauncherActions actions;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    final strings = context.strings;
    final update = controller.availableUpdate;
    final (String status, Color? statusColor) = update != null
        ? (strings.updateAvailable, palette.accent)
        : controller.updateCheckInProgress
            ? (strings.checking, null)
            : (strings.noUpdate, null);
    return SurfaceCard(
      key: update == null ? null : const ValueKey('app-update-entry'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PanelHeader(
            title: appDisplayName,
            trailing: StatusLabel(label: status, color: statusColor),
          ),
          const SizedBox(height: 16),
          MetricRow(
            metrics: [
              Metric(
                label: strings.currentVersion,
                value: 'v${controller.currentAppVersion}',
              ),
              Metric(
                label: strings.latestVersion,
                value: controller.latestAppVersion == null
                    ? '--'
                    : 'v${controller.latestAppVersion}',
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (update == null)
            Text(
              strings.autoCheckHint,
              style: TextStyle(
                color: palette.inkMuted,
                fontSize: 12.5,
                height: 1.5,
              ),
            )
          else ...[
            Text(
              '${update.currentVersion} → ${update.latestVersion}',
              style: TextStyle(color: palette.inkMuted, fontSize: 12.5),
            ),
            if (update.releaseName.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                update.releaseName,
                style: TextStyle(
                  color: palette.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (update.releaseNotes.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                update.releaseNotes,
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.inkMuted,
                  fontSize: 12.5,
                  height: 1.5,
                ),
              ),
            ],
            const SizedBox(height: 14),
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
        ],
      ),
    );
  }
}

class _LaunchPreferences extends StatelessWidget {
  const _LaunchPreferences({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    final strings = context.strings;
    return SurfaceCard(
      key: const ValueKey('launch-preferences'),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelHeader(
            title: strings.launchPreferences,
            trailing: Text(
              strings.appliesNextLaunch,
              style: TextStyle(color: palette.inkFaint, fontSize: 12),
            ),
          ),
          const SizedBox(height: 4),
          SwitchRow(
            key: const ValueKey('home-quick-launch'),
            switchKey: const ValueKey('home-quick-launch-switch'),
            title: strings.quickLaunch,
            subtitle: strings.quickLaunchSubtitle,
            value: controller.quickLaunchEnabled,
            onChanged: controller.initialized
                ? controller.setQuickLaunchEnabled
                : null,
          ),
          Divider(color: palette.border),
          SwitchRow(
            key: const ValueKey('home-auto-collect-sun'),
            switchKey: const ValueKey('home-auto-collect-sun-switch'),
            title: strings.autoCollectSun,
            subtitle: strings.autoCollectSunSubtitle,
            value: controller.autoCollectSunEnabled,
            onChanged: controller.hasCurrentResource
                ? controller.setAutoCollectSunEnabled
                : null,
          ),
          Divider(color: palette.border),
          _SegmentedSettingRow<RenderResolution>(
            key: const ValueKey('render-resolution'),
            title: strings.renderResolution,
            subtitle: strings.renderResolutionSubtitle,
            values: RenderResolution.values,
            selected: controller.renderResolution,
            keyOf: (value) => ValueKey('render-resolution-${value.name}'),
            labelOf: strings.renderResolutionLabel,
            onChanged: controller.initialized
                ? controller.setRenderResolution
                : (_) {},
          ),
          Divider(color: palette.border),
          _SegmentedSettingRow<ScreenFit>(
            key: const ValueKey('screen-fit'),
            title: strings.screenFit,
            subtitle: strings.screenFitSubtitle,
            values: ScreenFit.values,
            selected: controller.screenFit,
            keyOf: (value) => ValueKey('screen-fit-${value.name}'),
            labelOf: strings.screenFitLabel,
            onChanged:
                controller.initialized ? controller.setScreenFit : (_) {},
          ),
          Divider(color: palette.border),
          _SegmentedSettingRow<GestureMode>(
            key: const ValueKey('gesture-mode'),
            title: strings.gestureMode,
            subtitle: strings.gestureModeSubtitle,
            values: GestureMode.values,
            selected: controller.gestureMode,
            keyOf: (value) => ValueKey('gesture-mode-${value.name}'),
            labelOf: strings.gestureModeLabel,
            onChanged:
                controller.initialized ? controller.setGestureMode : (_) {},
          ),
          Divider(color: palette.border),
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
      ),
    );
  }
}

class _SegmentedSettingRow<T> extends StatelessWidget {
  const _SegmentedSettingRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.values,
    required this.selected,
    required this.keyOf,
    required this.labelOf,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final List<T> values;
  final T selected;
  final Key Function(T value) keyOf;
  final String Function(T value) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    // The control sits under the text: beside it, a phone's narrow column
    // left the text a few characters wide.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(
              color: palette.ink,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: TextStyle(
              color: palette.inkMuted,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          GardenSegmented<T>(
            values: values,
            selected: selected,
            keyOf: keyOf,
            labelOf: labelOf,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _AppearancePanel extends StatelessWidget {
  const _AppearancePanel({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    final strings = context.strings;
    final groupLabel = TextStyle(
      color: palette.inkMuted,
      fontSize: 12,
      fontWeight: FontWeight.w700,
    );
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelHeader(title: strings.appearance),
          const SizedBox(height: 14),
          Text(strings.theme, style: groupLabel),
          const SizedBox(height: 8),
          GardenSegmented<ThemePreference>(
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
          const SizedBox(height: 14),
          Text(strings.language, style: groupLabel),
          const SizedBox(height: 8),
          GardenSegmented<LanguagePreference>(
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
          const SizedBox(height: 8),
          SwitchRow(
            key: const ValueKey('reduce-motion'),
            switchKey: const ValueKey('reduce-motion-switch'),
            title: strings.reduceMotion,
            subtitle: strings.reduceMotionSubtitle,
            value: controller.reduceMotion,
            onChanged:
                controller.initialized ? controller.setReduceMotion : null,
          ),
        ],
      ),
    );
  }
}

class _AboutPanel extends StatelessWidget {
  const _AboutPanel({required this.controller, required this.actions});

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
    return SurfaceCard(
      key: const ValueKey('about-panel'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PanelHeader(title: strings.aboutTitle),
          const SizedBox(height: 12),
          SelectableText(
            strings.isChinese
                ? controller.aboutContent.content
                : controller.aboutContent.contentEn ??
                    controller.aboutContent.content,
            style: TextStyle(color: palette.ink, fontSize: 13.5, height: 1.6),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final link in links)
                GardenButton(
                  label: link.label,
                  compact: true,
                  onPressed: () => actions.openUrl(link.url),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GuidePanel extends StatelessWidget {
  const _GuidePanel({required this.gestureMode});

  final GestureMode gestureMode;

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
    final tips = strings.guideTips;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelHeader(title: strings.guide),
          const SizedBox(height: 10),
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
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      mapping,
                      textAlign: TextAlign.right,
                      style: TextStyle(color: palette.inkMuted, fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          Divider(color: palette.border, height: 20),
          for (final tip in tips)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
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
    );
  }
}
