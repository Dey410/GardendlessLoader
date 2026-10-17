import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../app_controller.dart';
import '../../constants.dart';
import '../../l10n/app_strings.dart';
import '../../logging/log_event_catalog.dart';
import '../../models.dart';
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
      left: [_CurrentResourceCard(controller: controller, actions: actions)],
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
                      expanded: detailsExpanded,
                      onToggle: actions.toggleImportDetails,
                      onDismiss: controller.dismissImportProgress,
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
    required this.expanded,
    required this.onToggle,
    required this.onDismiss,
  });

  final ImportProgress progress;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final palette = context.garden;
    final strings = context.strings;
    final steps = strings.importSteps;
    final failed = progress.phase == ImportPhase.failed;
    final completed = progress.phase == ImportPhase.completed;
    final hint = failed
        ? userErrorCatalog[progress.errorCode]?.action.of(strings)
        : null;
    final title = failed
        ? strings.importFailedTitle(
            progress.message ?? strings.importPhase(progress.phase),
          )
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
                child: failed || completed
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
                onPressed: () => actions.openUrl(githubUrl),
              ),
              GardenButton(
                label: strings.cloudDriveDownload,
                icon: Icons.download_rounded,
                tone: update != null
                    ? GardenButtonTone.primary
                    : GardenButtonTone.secondary,
                compact: true,
                onPressed: () => actions.openUrl(appCloudDriveUpdateUrl),
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
