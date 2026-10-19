import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../app_controller.dart';
import '../../l10n/app_strings.dart';
import '../../logging/log_event_catalog.dart';
import '../../models.dart';
import '../../services/garden_journal.dart';
import '../launcher_actions.dart';
import '../theme/garden_theme.dart';
import '../widgets/garden_widgets.dart';

class ResourcesPage extends StatelessWidget {
  const ResourcesPage({
    super.key,
    required this.controller,
    required this.actions,
    required this.compact,
    required this.detailsExpanded,
  });

  final AppController controller;
  final LauncherActions actions;
  final bool compact;
  final bool detailsExpanded;

  @override
  Widget build(BuildContext context) {
    return TwoColumn(
      gap: compact ? 16 : 24,
      left: [
        _CurrentResourceCard(controller: controller, actions: actions),
        if (controller.journal.imports.isNotEmpty) ...[
          const SizedBox(height: 16),
          _VersionRingsCard(controller: controller),
        ],
      ],
      right: [
        _GameVersionCard(controller: controller, actions: actions),
        const SizedBox(height: 16),
        _ImportCard(
          controller: controller,
          actions: actions,
          detailsExpanded: detailsExpanded,
        ),
      ],
    );
  }
}

class _ImportCard extends StatelessWidget {
  const _ImportCard({
    required this.controller,
    required this.actions,
    required this.detailsExpanded,
  });

  final AppController controller;
  final LauncherActions actions;
  final bool detailsExpanded;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    final strings = context.strings;
    final progress = controller.importProgress;
    final hasResource = controller.hasCurrentResource;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelHeader(
            title:
                hasResource ? strings.updateResources : strings.importResources,
          ),
          const SizedBox(height: 8),
          Text(
            strings.importDescription,
            style: TextStyle(
              color: palette.inkMuted,
              fontSize: 13,
              height: 1.55,
            ),
          ),
          AnimatedSize(
            duration: GardenMotionScope.reduced(context)
                ? Duration.zero
                : GardenMotion.panel,
            curve: GardenMotion.easeOut,
            alignment: Alignment.topCenter,
            child: progress.phase == ImportPhase.idle
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 18),
                    child: _ImportProgressView(
                      key: const ValueKey('resource-progress-region'),
                      progress: progress,
                      upgrade: controller.versionUpgrade,
                      tip: controller.importTip,
                      expanded: detailsExpanded,
                      onToggle: actions.toggleImportDetails,
                      onDismiss: controller.dismissImportProgress,
                      releaseNotesUrlFor: controller.links.gameReleaseNotesFor,
                      onOpenUrl: actions.openUrl,
                    ),
                  ),
          ),
          const SizedBox(height: 18),
          Align(
            alignment: Alignment.centerLeft,
            child: GardenButton(
              key: const ValueKey('import-zip-button'),
              label: controller.isImporting
                  ? strings.importing
                  : hasResource
                      ? strings.chooseZipToUpdate
                      : strings.chooseZipToImport,
              icon: Icons.folder_open_rounded,
              tone: GardenButtonTone.primary,
              onPressed: controller.busy || controller.isImporting
                  ? null
                  : actions.importResources,
            ),
          ),
        ],
      ),
    );
  }
}

class _ImportProgressView extends StatelessWidget {
  const _ImportProgressView({
    super.key,
    required this.progress,
    required this.upgrade,
    required this.tip,
    required this.expanded,
    required this.onToggle,
    required this.onDismiss,
    required this.releaseNotesUrlFor,
    required this.onOpenUrl,
  });

  final ImportProgress progress;

  /// Set on a completed import that moved the game to a newer version.
  final ({String from, String to})? upgrade;
  final String tip;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onDismiss;
  final String Function(String version) releaseNotesUrlFor;
  final Future<void> Function(String url) onOpenUrl;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    final strings = context.strings;
    final steps = strings.importSteps;
    final failed = progress.phase == ImportPhase.failed;
    final completed = progress.phase == ImportPhase.completed;
    final upgrade = completed ? this.upgrade : null;
    final hint = failed
        ? userErrorCatalog[progress.errorCode]?.action.of(strings)
        : null;
    final title = failed
        ? strings.importFailedTitle(
            progress.message ?? strings.importPhase(progress.phase),
          )
        : upgrade != null
            ? strings.upgradedTitle(upgrade.to)
            : completed
                ? strings.importCompletedTitle
                : strings.importStepTitle(
                    progress.stepIndex,
                    progress.stepCount,
                    strings.importPhase(progress.phase),
                  );
    final color = failed ? palette.danger : palette.accent;
    final value = failed || completed ? 1.0 : progress.value;
    final step = completed ? 5 : progress.stepIndex;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ProgressRing(
                value: value,
                size: 44,
                color: color,
                child: upgrade != null
                    ? _Sprout(color: color)
                    : failed || completed
                        ? Icon(
                            failed ? Icons.close_rounded : Icons.check_rounded,
                            size: 20,
                            color: color,
                          )
                        : value == null
                            ? null
                            : Text(
                                '${(value * 100).round()}%',
                                style: TextStyle(
                                  color: palette.ink,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: failed ? palette.danger : palette.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Wrap between steps, never inside a two-character label.
                    Wrap(
                      spacing: 6,
                      runSpacing: 2,
                      children: [
                        for (var i = 0; i < steps.length; i++)
                          Text(
                            i == 0 ? steps[i] : '›  ${steps[i]}',
                            style: TextStyle(
                              fontSize: 12,
                              color: i + 1 <= step && !failed
                                  ? palette.ink
                                  : palette.inkFaint,
                              fontWeight: i + 1 == step
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                      ],
                    ),
                    if (hint != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        hint,
                        style:
                            TextStyle(color: palette.inkMuted, fontSize: 12.5),
                      ),
                    ],
                    if (!failed && !completed) ...[
                      const SizedBox(height: 6),
                      Text(
                        '💡 $tip',
                        key: const ValueKey('import-tip'),
                        style:
                            TextStyle(color: palette.inkMuted, fontSize: 12.5),
                      ),
                    ],
                    if (upgrade != null) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            '${upgrade.from} → ${upgrade.to}',
                            style: GardenType.mono(12.5, color: palette.ink),
                          ),
                          // Release notes exist for public releases only.
                          if (RegExp(r'^\d+\.\d+\.\d+$').hasMatch(upgrade.to))
                            GardenButton(
                              key: const ValueKey('game-release-notes'),
                              label: strings.releaseNotes,
                              icon: Icons.open_in_new_rounded,
                              tone: GardenButtonTone.ghost,
                              compact: true,
                              onPressed: () =>
                                  onOpenUrl(releaseNotesUrlFor(upgrade.to)),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              GardenIconButton(
                key: const ValueKey('resource-progress-toggle'),
                icon: expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                tooltip: expanded
                    ? strings.collapseProgressDetails
                    : strings.expandProgressDetails,
                onPressed: onToggle,
              ),
              if (failed || completed)
                GardenIconButton(
                  key: const ValueKey('dismiss-import-progress'),
                  icon: Icons.close_rounded,
                  tooltip: failed
                      ? strings.dismissFailure
                      : strings.dismissCompletion,
                  onPressed: onDismiss,
                ),
            ],
          ),
          if (expanded)
            Padding(
              key: const ValueKey('resource-progress-details'),
              padding: const EdgeInsets.only(top: 16),
              child: MetricRow(
                metrics: [
                  Metric(
                    label: strings.files,
                    value: progress.totalFiles > 0
                        ? '${progress.copiedFiles}/${progress.totalFiles}'
                        : '${progress.copiedFiles}',
                  ),
                  Metric(
                    label: strings.dataSize,
                    value: progress.totalBytes > 0
                        ? '${formatBytes(progress.copiedBytes)} / '
                            '${formatBytes(progress.totalBytes)}'
                        : formatBytes(progress.copiedBytes),
                  ),
                  Metric(
                    label: strings.speed,
                    value: progress.bytesPerSecond > 0
                        ? '${formatBytes(progress.bytesPerSecond.round())}/s'
                        : '--',
                  ),
                  Metric(
                    label: strings.elapsed,
                    value: formatDuration(progress.elapsed),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _GameVersionCard extends StatelessWidget {
  const _GameVersionCard({required this.controller, required this.actions});

  final AppController controller;
  final LauncherActions actions;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    final strings = context.strings;
    final update = controller.availableGameUpdate;
    final noteStyle =
        TextStyle(color: palette.inkMuted, fontSize: 12, height: 1.5);
    final current = controller.hasCurrentResource
        ? (controller.currentGameVersion ?? strings.unknown)
        : '--';
    final latest =
        update?.latestVersion ?? controller.latestGameVersion ?? '--';
    final (String status, Color? statusColor) = update != null
        ? (strings.updateAvailable, palette.accent)
        : controller.updateCheckInProgress
            ? (strings.checking, null)
            : controller.latestGameVersion == null
                ? (strings.latestNotFetched, null)
                : !controller.hasCurrentResource
                    ? (strings.stableAvailable, null)
                    : (strings.upToDate, palette.accent);
    return SurfaceCard(
      key: update == null ? null : const ValueKey('game-update-entry'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelHeader(
            title: strings.gameVersion,
            trailing: StatusLabel(label: status, color: statusColor),
          ),
          const SizedBox(height: 16),
          MetricRow(
            metrics: [
              Metric(label: strings.currentLabel, value: current),
              Metric(label: strings.latestStable, value: latest),
            ],
          ),
          if (update != null) ...[
            const SizedBox(height: 8),
            Text(
              '${update.currentVersion} → ${update.latestVersion}',
              style: TextStyle(color: palette.inkMuted, fontSize: 12.5),
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              GardenButton(
                label: strings.githubDownload,
                leading: const FaIcon(FontAwesomeIcons.github, size: 16),
                compact: true,
                onPressed: () => actions.openUrl(controller.links.gameGithub),
              ),
              GardenButton(
                label: strings.cloudDriveDownload,
                icon: Icons.download_rounded,
                tone: update != null
                    ? GardenButtonTone.primary
                    : GardenButtonTone.secondary,
                compact: true,
                onPressed: () =>
                    actions.openUrl(controller.links.gameCloudDrive),
              ),
              if (update != null)
                GardenButton(
                  label: strings.remindLater,
                  tone: GardenButtonTone.ghost,
                  compact: true,
                  onPressed: () => actions.deferGameUpdate(update),
                ),
            ],
          ),
          const SizedBox(height: 8),
          for (final note in strings.downloadNotes)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('•  ', style: noteStyle),
                  Expanded(child: Text(note, style: noteStyle)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CurrentResourceCard extends StatelessWidget {
  const _CurrentResourceCard({required this.controller, required this.actions});

  final AppController controller;
  final LauncherActions actions;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    final strings = context.strings;
    final manifest = controller.manifest;
    final hasResource = controller.hasCurrentResource;
    final slot = switch (manifest.activeSlot) {
      ResourceSlot.slotA => strings.slotA,
      ResourceSlot.slotB => strings.slotB,
      null => strings.noActiveSlot,
    };
    final selfCheck = manifest.lastSelfCheckAt == null
        ? (hasResource ? strings.notRun : strings.waitingForImport)
        : strings.passedAt(formatDateTime(manifest.lastSelfCheckAt));
    final lastError = manifest.lastErrorMessage == null
        ? null
        : userErrorTitle(manifest.lastErrorCode, manifest.lastErrorMessage!);
    // The missing-module detail stays in the technical details below.
    final gpNext = !controller.hasGpNext
        ? strings.gpNextNotDetected
        : controller.gpNextCompatible
            ? strings.gpNextCompatible(controller.gpNextVersion ?? '')
            : strings.gpNextIncompatible;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelHeader(
            title: strings.currentResource,
            trailing: StatusLabel(
              label: slot,
              color: hasResource ? palette.accent : null,
            ),
          ),
          const SizedBox(height: 16),
          MetricRow(
            metrics: [
              Metric(
                label: strings.fileCount,
                value: hasResource ? '${manifest.fileCount}' : '--',
              ),
              Metric(
                label: strings.size,
                value: hasResource ? formatBytes(manifest.totalBytes) : '--',
              ),
              Metric(
                label: strings.importedAt,
                value: formatDateTime(manifest.lastImportAt),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(color: palette.border),
          InfoRow(
            label: strings.title,
            value: hasResource ? controller.detectedTitle : strings.notImported,
          ),
          InfoRow(
            label: strings.validation,
            value: hasResource
                ? strings.validationPassed
                : strings.waitingForImport,
            color: hasResource ? null : palette.warning,
          ),
          InfoRow(
            label: strings.gameHost,
            value: strings.noHttpServer(
              controller.gameHostPlatform.nativeHostName,
            ),
          ),
          InfoRow(label: strings.lastSelfCheck, value: selfCheck),
          InfoRow(
            label: strings.recentError,
            value: lastError ?? strings.none,
            color: lastError == null ? null : palette.danger,
            maxLines: 3,
            hint: lastError == null
                ? null
                : userErrorCatalog[manifest.lastErrorCode]?.action.of(strings),
          ),
          InfoRow(
            label: 'GP-Next',
            value: gpNext,
            color: controller.hasGpNext && !controller.gpNextCompatible
                ? palette.danger
                : null,
            hint: controller.hasGpNext && !controller.gpNextCompatible
                ? userErrorCatalog['gp_next_incompatible']?.action.of(strings)
                : null,
          ),
          InfoRow(
            label: strings.resourceRoot,
            value: controller.userVisibleRoot,
            mono: true,
            trailing: GardenButton(
              key: const ValueKey('copy-resource-root-button'),
              label: strings.copy,
              compact: true,
              onPressed: actions.copyResourceRoot,
            ),
          ),
          Divider(color: palette.border),
          Disclosure(
            key: const ValueKey('resource-technical-details'),
            title: strings.technicalDetails,
            child: _TechnicalDetails(controller: controller),
          ),
        ],
      ),
    );
  }
}

class _TechnicalDetails extends StatelessWidget {
  const _TechnicalDetails({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    final manifest = controller.manifest;
    // Absent values (no transaction, no error) are omitted rather than shown.
    final rows = <(String, String?)>[
      ('activeSlot', manifest.activeSlot?.name),
      ('generation', '${manifest.generation}'),
      ('transaction', manifest.transactionState.name),
      ('transactionSlot', manifest.transactionSlot?.name),
      ('buildProfile', manifest.buildProfile.name),
      ('gpNextVersion', controller.gpNextVersion),
      ('gpNextError', controller.gpNextCompatibilityError),
      ('origin', controller.gameHostPlatform.origin),
      ('lastErrorCode', manifest.lastErrorCode),
    ];
    return CodeBlock(
      child: SelectionArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (key, value) in rows)
              if (value != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 128,
                        child: Text(
                          key,
                          style: GardenType.mono(11.5, color: palette.inkMuted),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          value,
                          style: GardenType.mono(11.5, color: palette.ink),
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

/// A seedling that grows in once when an import moves the game to a newer
/// version.
class _Sprout extends StatelessWidget {
  const _Sprout({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(Icons.eco_rounded, size: 22, color: color);
    if (GardenMotionScope.reduced(context)) return icon;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.2, end: 1),
      duration: GardenMotion.panel,
      curve: GardenMotion.easeOut,
      builder: (context, value, child) => Transform.scale(
        scale: value,
        alignment: Alignment.bottomCenter,
        child: child,
      ),
      child: icon,
    );
  }
}

/// Every game version this device has imported, oldest on the left; each
/// later version carries one more ring.
class _VersionRingsCard extends StatelessWidget {
  const _VersionRingsCard({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    final strings = context.strings;
    final imports = controller.journal.imports;
    return SurfaceCard(
      key: const ValueKey('version-rings'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelHeader(
            title: strings.versionRings,
            trailing: Text(
              strings.importCount(imports.length),
              style: TextStyle(color: palette.inkFaint, fontSize: 12),
            ),
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            // Opens on the newest ring.
            reverse: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (index, record) in imports.indexed) ...[
                  if (index > 0)
                    Container(
                      width: 18,
                      height: 1,
                      margin: const EdgeInsets.only(top: 18),
                      color: palette.border,
                    ),
                  _Ring(
                    record: record,
                    rings: index + 1,
                    current: index == imports.length - 1,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({
    required this.record,
    required this.rings,
    required this.current,
  });

  final ImportRecord record;
  final int rings;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    final strings = context.strings;
    final color = current ? palette.accent : palette.inkFaint;
    return Tooltip(
      message: [
        if (record.gpNextVersion != null) 'GP-Next ${record.gpNextVersion}',
        formatBytes(record.totalBytes),
      ].join(' · '),
      child: SizedBox(
        width: 72,
        child: Column(
          children: [
            CustomPaint(
              size: const Size.square(36),
              painter: _RingsPainter(count: rings, color: color),
            ),
            const SizedBox(height: 6),
            Text(
              record.gameVersion ?? strings.unknown,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GardenType.mono(
                11.5,
                weight: current ? FontWeight.w600 : null,
                color: current ? palette.ink : palette.inkMuted,
              ),
            ),
            Text(
              strings.shortDate(record.importedAt),
              style: TextStyle(color: palette.inkFaint, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  const _RingsPainter({required this.count, required this.color});

  final int count;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final outer = size.shortestSide / 2 - 1;
    // Past six rings they would merge, so the spacing stops shrinking.
    final shown = count.clamp(1, 6);
    final step = outer / shown;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = color;
    for (var ring = 1; ring <= shown; ring++) {
      canvas.drawCircle(center, step * ring, paint);
    }
    canvas.drawCircle(center, 2, paint..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(_RingsPainter oldDelegate) =>
      oldDelegate.count != count || oldDelegate.color != color;
}
